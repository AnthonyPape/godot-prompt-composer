@tool
extends EditorPlugin
class_name AIPromptComposerPlugin

## Adds a "PromptComposer" main-screen tab.
## Goal: fast prompt building without leaving the editor.

const TEMPLATES_FILE_PATH: String = "user://ai_prompt_templates.json"
const SETTINGS_FILE_PATH: String = "user://ai_prompt_composer_settings.json"

var _script_editor: ScriptEditor = null
var _main_screen_root: Control = null

var _template_search_line_edit: LineEdit = null
var _template_option_button: OptionButton = null
var _extra_instructions_text_edit: TextEdit = null
var _include_rules_check_box: CheckBox = null
var _include_file_path_check_box: CheckBox = null
var _include_fences_check_box: CheckBox = null
var _include_selection_stats_check_box: CheckBox = null
var _prompt_style_option_button: OptionButton = null
var _status_label: Label = null
var _prompt_preview_text_edit: TextEdit = null
var _coding_rules_text_edit: TextEdit = null

var _last_selected_code: String = ""
var _last_file_path: String = ""

var _templates: Array[TemplateEntry] = []
var _filtered_template_indices: Array[int] = []
var _selected_template_id: String = ""

var _settings: Dictionary = {}

class TemplateEntry:
	var template_id: String = ""
	var display_name: String = ""
	var prompt_text: String = ""
	var sort_index: int = 0
	
	func _init(template_id_input: String, display_name_input: String, prompt_text_input: String, sort_index_input: int) -> void:
		template_id = template_id_input
		display_name = display_name_input
		prompt_text = prompt_text_input
		sort_index = sort_index_input
	
	func to_dictionary() -> Dictionary:
		return {
			"template_id": template_id,
			"display_name": display_name,
			"prompt_text": prompt_text,
			"sort_index": sort_index,
		}
	
	static func from_dictionary(data: Dictionary) -> TemplateEntry:
		var entry: TemplateEntry = TemplateEntry.new(
			String(data.get("template_id", "")),
			String(data.get("display_name", "")),
			String(data.get("prompt_text", "")),
			int(data.get("sort_index", 0))
		)
		return entry




## Godot: tell the editor we provide a main screen.
func _has_main_screen() -> bool:
	return true

## The label that appears in the top bar.
func _get_plugin_name() -> String:
	return "PromptComposer"

## Optional icon.
func _get_plugin_icon() -> Texture2D:
	return preload("res://addons/ai_prompt_composer/icon.png")

## Show/hide our main screen root when user switches tabs.
func _make_visible(visible: bool) -> void:
	if not is_instance_valid(_main_screen_root):
		return
	
	_main_screen_root.visible = visible
	_main_screen_root.mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
	
	if visible:
		_refresh_preview_from_current_selection()




## Called when the plugin enters the editor tree.
func _enter_tree() -> void:
	_script_editor = get_editor_interface().get_script_editor()
	_load_settings()
	_load_templates()
	
	# Safety: if the user file exists but is invalid/empty, still populate defaults.
	if _templates.size() == 0:
		_seed_default_templates()
		_save_templates()
	
	_create_main_screen_ui()
	
	_main_screen_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main_screen_root.visible = false
	
	var editor_main_screen: Control = get_editor_interface().get_editor_main_screen()
	if is_instance_valid(editor_main_screen):
		editor_main_screen.add_child(_main_screen_root)
	
	_make_visible(false)
	_apply_settings_to_ui()
	_rebuild_template_dropdown()
	_update_prompt_preview()


## Called when the plugin exits the editor tree.
func _exit_tree() -> void:
	_save_settings_from_ui()
	_save_settings()
	
	if is_instance_valid(_main_screen_root):
		_main_screen_root.queue_free()




## ----------------------------
## Selection capture
## ----------------------------

func _refresh_preview_from_current_selection() -> void:
	_capture_selection_context()
	_update_prompt_preview()

func _capture_selection_context() -> void:
	_last_selected_code = ""
	_last_file_path = ""
	
	if is_instance_valid(_script_editor):
		var current_script: Script = _script_editor.get_current_script()
		if is_instance_valid(current_script):
			_last_file_path = current_script.resource_path
	
	var editor_base: Control = null
	if is_instance_valid(_script_editor):
		editor_base = _script_editor.get_current_editor()
	
	if is_instance_valid(editor_base):
		var code_edit: CodeEdit = _find_code_edit(editor_base)
		if is_instance_valid(code_edit):
			var selected_text: String = code_edit.get_selected_text()
			if selected_text.strip_edges().length() > 0:
				_last_selected_code = selected_text

func _find_code_edit(root: Node) -> CodeEdit:
	if root is CodeEdit:
		return root as CodeEdit
	
	for child: Node in root.get_children():
		var found: CodeEdit = _find_code_edit(child)
		if is_instance_valid(found):
			return found
	
	return null




## ----------------------------
## UI
## ----------------------------

func _create_main_screen_ui() -> void:
	_main_screen_root = MarginContainer.new()
	_main_screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_screen_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_screen_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_screen_root.name = "PromptComposerMainScreen"
	_main_screen_root.add_theme_constant_override("margin_left", 12)
	_main_screen_root.add_theme_constant_override("margin_right", 12)
	_main_screen_root.add_theme_constant_override("margin_top", 12)
	_main_screen_root.add_theme_constant_override("margin_bottom", 12)
	
	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_screen_root.add_child(root_vbox)
	
	# --- Top actions ---
	var actions_row: HBoxContainer = HBoxContainer.new()
	root_vbox.add_child(actions_row)
	
	var capture_button: Button = Button.new()
	capture_button.text = "Capture selection"
	capture_button.pressed.connect(func() -> void:
		_refresh_preview_from_current_selection()
	)
	actions_row.add_child(capture_button)
	
	var copy_button: Button = Button.new()
	copy_button.text = "Copy prompt"
	copy_button.pressed.connect(_on_copy_prompt_pressed)
	actions_row.add_child(copy_button)
	
	var copy_code_button: Button = Button.new()
	copy_code_button.text = "Copy code"
	copy_code_button.pressed.connect(func() -> void:
		_refresh_preview_from_current_selection()
		DisplayServer.clipboard_set(_last_selected_code)
		_status_label.text = "Copied code to clipboard."
	)
	actions_row.add_child(copy_code_button)
	
	_status_label = Label.new()
	_status_label.text = "Select code in the Script tab, then click Capture (or Copy prompt)."
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_row.add_child(_status_label)
	
	# --- Template row ---
	var template_row: HBoxContainer = HBoxContainer.new()
	root_vbox.add_child(template_row)
	
	var template_label: Label = Label.new()
	template_label.text = "Template"
	template_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	template_row.add_child(template_label)
	
	_template_search_line_edit = LineEdit.new()
	_template_search_line_edit.placeholder_text = "Search templates..."
	_template_search_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_template_search_line_edit.text_changed.connect(func(_t: String) -> void:
		_rebuild_template_dropdown()
		_update_prompt_preview()
		_save_settings_from_ui()
		_save_settings()
	)
	template_row.add_child(_template_search_line_edit)
	
	_template_option_button = OptionButton.new()
	_template_option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_template_option_button.item_selected.connect(func(_index: int) -> void:
		_update_prompt_preview()
		_save_settings_from_ui()
		_save_settings()
	)
	template_row.add_child(_template_option_button)
	
	# --- Options row ---
	var options_row: HBoxContainer = HBoxContainer.new()
	root_vbox.add_child(options_row)
	
	_include_rules_check_box = CheckBox.new()
	_include_rules_check_box.text = "Include my coding rules"
	_include_rules_check_box.button_pressed = true
	_include_rules_check_box.toggled.connect(func(_is_on: bool) -> void:
		_update_prompt_preview()
		_save_settings_from_ui()
		_save_settings()
	)
	options_row.add_child(_include_rules_check_box)
	
	_include_file_path_check_box = CheckBox.new()
	_include_file_path_check_box.text = "Include file path"
	_include_file_path_check_box.button_pressed = true
	_include_file_path_check_box.toggled.connect(func(_is_on: bool) -> void:
		_update_prompt_preview()
		_save_settings_from_ui()
		_save_settings()
	)
	options_row.add_child(_include_file_path_check_box)
	
	_include_fences_check_box = CheckBox.new()
	_include_fences_check_box.text = "Use code fences"
	_include_fences_check_box.button_pressed = true
	_include_fences_check_box.toggled.connect(func(_is_on: bool) -> void:
		_update_prompt_preview()
		_save_settings_from_ui()
		_save_settings()
	)
	options_row.add_child(_include_fences_check_box)
	
	_include_selection_stats_check_box = CheckBox.new()
	_include_selection_stats_check_box.text = "Include selection stats"
	_include_selection_stats_check_box.button_pressed = false
	_include_selection_stats_check_box.toggled.connect(func(_is_on: bool) -> void:
		_update_prompt_preview()
		_save_settings_from_ui()
		_save_settings()
	)
	options_row.add_child(_include_selection_stats_check_box)
	
	var style_label: Label = Label.new()
	style_label.text = "Prompt style"
	style_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	options_row.add_child(style_label)
	
	_prompt_style_option_button = OptionButton.new()
	_prompt_style_option_button.add_item("Full prompt")
	_prompt_style_option_button.add_item("Instruction only")
	_prompt_style_option_button.add_item("Instruction + code")
	_prompt_style_option_button.add_item("Code only")
	_prompt_style_option_button.item_selected.connect(func(_idx: int) -> void:
		_update_prompt_preview()
		_save_settings_from_ui()
		_save_settings()
	)
	options_row.add_child(_prompt_style_option_button)
	
	# --- Project / style rules editor ---
	var rules_header_row: HBoxContainer = HBoxContainer.new()
	root_vbox.add_child(rules_header_row)

	var rules_label: Label = Label.new()
	rules_label.text = "Project / style rules"
	rules_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules_header_row.add_child(rules_label)

	var reset_rules_button: Button = Button.new()
	reset_rules_button.text = "Reset to defaults"
	reset_rules_button.pressed.connect(func() -> void:
		if is_instance_valid(_coding_rules_text_edit):
			_coding_rules_text_edit.text = _get_default_coding_rules_text()
			_update_prompt_preview()
			_save_settings_from_ui()
			_save_settings()
	)
	rules_header_row.add_child(reset_rules_button)

	_coding_rules_text_edit = TextEdit.new()
	_coding_rules_text_edit.custom_minimum_size = Vector2(0.0, 110.0)
	_coding_rules_text_edit.placeholder_text = "These rules are injected into the prompt when enabled above. One per line is a good format."
	_coding_rules_text_edit.text_changed.connect(func() -> void:
		_update_prompt_preview()
		_save_settings_from_ui()
		_save_settings()
	)
	root_vbox.add_child(_coding_rules_text_edit)
	
	# --- Extra instructions ---
	var extra_label: Label = Label.new()
	extra_label.text = "Extra instructions (optional)"
	root_vbox.add_child(extra_label)
	
	_extra_instructions_text_edit = TextEdit.new()
	_extra_instructions_text_edit.custom_minimum_size = Vector2(0.0, 90.0)
	_extra_instructions_text_edit.placeholder_text = "Example: Return a unified diff. Do not rename exported variables. Keep behavior identical."
	_extra_instructions_text_edit.text_changed.connect(func() -> void:
		_update_prompt_preview()
		_save_settings_from_ui()
		_save_settings()
	)
	root_vbox.add_child(_extra_instructions_text_edit)
	
	# --- Prompt preview ---
	var preview_label: Label = Label.new()
	preview_label.text = "Prompt preview"
	root_vbox.add_child(preview_label)
	
	_prompt_preview_text_edit = TextEdit.new()
	_prompt_preview_text_edit.editable = false
	_prompt_preview_text_edit.custom_minimum_size = Vector2(0.0, 220.0)
	_prompt_preview_text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prompt_preview_text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(_prompt_preview_text_edit)


func _rebuild_template_dropdown() -> void:
	if not is_instance_valid(_template_option_button):
		return
	
	var query: String = ""
	if is_instance_valid(_template_search_line_edit):
		query = _template_search_line_edit.text.strip_edges().to_lower()
	
	_filtered_template_indices.clear()
	for i in range(_templates.size()):
		var name_text: String = _templates[i].display_name.to_lower()
		var id_text: String = _templates[i].template_id.to_lower()
		if query.length() == 0 or name_text.find(query) != -1 or id_text.find(query) != -1:
			_filtered_template_indices.append(i)
	
	_template_option_button.clear()
	if _filtered_template_indices.size() == 0:
		_template_option_button.add_item("(No templates match)")
		_template_option_button.select(0)
		return
	
	for idx: int in _filtered_template_indices:
		_template_option_button.add_item(_templates[idx].display_name)
	
	# Restore selection by template_id if possible.
	var restored_visible_index: int = 0
	if _selected_template_id.length() > 0:
		for visible_i in range(_filtered_template_indices.size()):
			var real_i: int = _filtered_template_indices[visible_i]
			if _templates[real_i].template_id == _selected_template_id:
				restored_visible_index = visible_i
				break
	
	restored_visible_index = clamp(restored_visible_index, 0, _filtered_template_indices.size() - 1)
	_template_option_button.select(restored_visible_index)


func _update_prompt_preview() -> void:
	if not is_instance_valid(_prompt_preview_text_edit):
		return
	
	var prompt: String = _build_prompt()
	_prompt_preview_text_edit.text = prompt
	
	if _last_selected_code.strip_edges().length() == 0:
		_status_label.text = "No selection captured yet. Select code in the Script tab, then click Capture."
	else:
		_status_label.text = "Selection captured (%d chars)." % _last_selected_code.length()


func _on_copy_prompt_pressed() -> void:
	_refresh_preview_from_current_selection()
	var prompt: String = _build_prompt()
	DisplayServer.clipboard_set(prompt)
	_status_label.text = "Copied prompt to clipboard."




## ----------------------------
## Prompt building
## ----------------------------

func _build_prompt() -> String:
	var style_index: int = 0
	if is_instance_valid(_prompt_style_option_button):
		style_index = _prompt_style_option_button.get_selected()
	
	var template_text: String = _get_template_text_from_visible_index(_template_option_button.get_selected())
	var extra_text: String = ""
	if is_instance_valid(_extra_instructions_text_edit):
		extra_text = _extra_instructions_text_edit.text.strip_edges()
	
	var include_rules: bool = is_instance_valid(_include_rules_check_box) and _include_rules_check_box.button_pressed
	var include_file_path: bool = is_instance_valid(_include_file_path_check_box) and _include_file_path_check_box.button_pressed
	var include_fences: bool = is_instance_valid(_include_fences_check_box) and _include_fences_check_box.button_pressed
	var include_stats: bool = is_instance_valid(_include_selection_stats_check_box) and _include_selection_stats_check_box.button_pressed
	
	var instruction_lines: Array[String] = []
	instruction_lines.append(template_text)
	
	if extra_text.length() > 0:
		instruction_lines.append("")
		instruction_lines.append("Additional constraints:")
		instruction_lines.append(extra_text)
	
	if include_rules:
		instruction_lines.append("")
		instruction_lines.append("Project / style rules:")
		instruction_lines.append(_get_coding_rules_text())
	
	if include_file_path and _last_file_path.length() > 0:
		instruction_lines.append("")
		instruction_lines.append("File: %s" % _last_file_path)
	
	if include_stats:
		instruction_lines.append("")
		instruction_lines.append("Selection stats:")
		instruction_lines.append(_get_selection_stats_text())
	
	var code_block_lines: Array[String] = []
	if include_fences:
		code_block_lines.append("Code:")
		code_block_lines.append("```gdscript")
		code_block_lines.append(_get_code_or_placeholder())
		code_block_lines.append("```")
	else:
		code_block_lines.append("Code:")
		code_block_lines.append(_get_code_or_placeholder())
	
	# Prompt style:
	# 0 Full prompt          -> instructions + blank + code block
	# 1 Instruction only     -> instructions
	# 2 Instruction + code   -> instructions + blank + code block
	# 3 Code only            -> code block only
	match style_index:
		1:
			# Instruction only
			return "\n".join(instruction_lines)
		2:
			# Instruction + code
			return "\n".join(instruction_lines) + "\n\n" + "\n".join(code_block_lines)
		3:
			# Code only
			return "\n".join(code_block_lines)
		_:
			# Full prompt (default)
			return "\n".join(instruction_lines) + "\n\n" + "\n".join(code_block_lines)



func _get_code_or_placeholder() -> String:
	if _last_selected_code.strip_edges().length() > 0:
		return _last_selected_code.strip_edges()
	return "# (No selection was captured. Paste the relevant code here.)"


func _get_selection_stats_text() -> String:
	var lines: Array[String] = []
	var code_text: String = _last_selected_code
	if code_text.length() == 0:
		return "(No selection.)"
	
	var char_count: int = code_text.length()
	var line_count: int = max(1, code_text.count("\n") + 1)
	var tab_count: int = code_text.count("	")
	var space_count: int = code_text.count(" ")
	lines.append("- Characters: %d" % char_count)
	lines.append("- Lines: %d" % line_count)
	lines.append("- Tabs: %d" % tab_count)
	lines.append("- Spaces: %d" % space_count)
	return "\n".join(lines)



func _get_template_text_from_visible_index(visible_index: int) -> String:
	if visible_index < 0:
		return "Help with this code."
	if _filtered_template_indices.size() == 0:
		return "Help with this code."
	if visible_index >= _filtered_template_indices.size():
		return "Help with this code."
	
	var real_index: int = _filtered_template_indices[visible_index]
	if real_index < 0 or real_index >= _templates.size():
		return "Help with this code."
	
	var entry: TemplateEntry = _templates[real_index]
	_selected_template_id = entry.template_id
	return entry.prompt_text


func _get_coding_rules_text() -> String:
	if is_instance_valid(_coding_rules_text_edit):
		var text: String = _coding_rules_text_edit.text.strip_edges()
		if text.length() > 0:
			return text

	var fallback: String = String(_settings.get("coding_rules_text", "")).strip_edges()
	if fallback.length() > 0:
		return fallback

	return _get_default_coding_rules_text()


func _get_default_coding_rules_text() -> String:
	var rules: Array[String] = []
	rules.append("- Godot 4.4+ syntax only.")
	rules.append("- Use tabs for indentation. Empty lines inside functions must include one tab.")
	rules.append("- Use explicit type declarations for variables and functions (type after name).")
	rules.append("- No inline conditional expressions using ?: . Use standard if statements.")
	rules.append("- Use clear names (no shortening).")
	rules.append("- Use words for colors (e.g. Color.RED).")
	rules.append("- Put a '##' description above each function and @onready variable.")
	return "\n".join(rules)





## ----------------------------
## Settings persistence
## ----------------------------

func _load_settings() -> void:
	_settings = {
		"include_rules": true,
		"include_file_path": true,
		"include_fences": true,
		"include_selection_stats": false,
		"prompt_style": 0,
		"selected_template_id": "",
		"template_search": "",
		"extra_instructions": "",
		"coding_rules_text": _get_default_coding_rules_text(),
	}
	
	if not FileAccess.file_exists(SETTINGS_FILE_PATH):
		return
	
	var file: FileAccess = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.READ)
	if not is_instance_valid(file):
		return
	
	var raw_text: String = file.get_as_text()
	file.close()
	
	var parsed: Variant = JSON.parse_string(raw_text)
	if not (parsed is Dictionary):
		return
	
	for key: String in parsed.keys():
		_settings[key] = parsed[key]


func _apply_settings_to_ui() -> void:
	if is_instance_valid(_include_rules_check_box):
		_include_rules_check_box.button_pressed = bool(_settings.get("include_rules", true))
	if is_instance_valid(_include_file_path_check_box):
		_include_file_path_check_box.button_pressed = bool(_settings.get("include_file_path", true))
	if is_instance_valid(_include_fences_check_box):
		_include_fences_check_box.button_pressed = bool(_settings.get("include_fences", true))
	if is_instance_valid(_include_selection_stats_check_box):
		_include_selection_stats_check_box.button_pressed = bool(_settings.get("include_selection_stats", false))
	
	if is_instance_valid(_prompt_style_option_button):
		var idx: int = int(_settings.get("prompt_style", 0))
		idx = clamp(idx, 0, _prompt_style_option_button.item_count - 1)
		_prompt_style_option_button.select(idx)
	
	_selected_template_id = String(_settings.get("selected_template_id", ""))
	
	if is_instance_valid(_template_search_line_edit):
		_template_search_line_edit.text = String(_settings.get("template_search", ""))
	
	if is_instance_valid(_extra_instructions_text_edit):
		_extra_instructions_text_edit.text = String(_settings.get("extra_instructions", ""))
	
	if is_instance_valid(_coding_rules_text_edit):
		_coding_rules_text_edit.text = String(_settings.get("coding_rules_text", _get_default_coding_rules_text()))


func _save_settings_from_ui() -> void:
	if is_instance_valid(_include_rules_check_box):
		_settings["include_rules"] = _include_rules_check_box.button_pressed
	if is_instance_valid(_include_file_path_check_box):
		_settings["include_file_path"] = _include_file_path_check_box.button_pressed
	if is_instance_valid(_include_fences_check_box):
		_settings["include_fences"] = _include_fences_check_box.button_pressed
	if is_instance_valid(_include_selection_stats_check_box):
		_settings["include_selection_stats"] = _include_selection_stats_check_box.button_pressed
	if is_instance_valid(_prompt_style_option_button):
		_settings["prompt_style"] = _prompt_style_option_button.get_selected()
	
	_settings["selected_template_id"] = _selected_template_id
	
	if is_instance_valid(_template_search_line_edit):
		_settings["template_search"] = _template_search_line_edit.text
	if is_instance_valid(_extra_instructions_text_edit):
		_settings["extra_instructions"] = _extra_instructions_text_edit.text
	if is_instance_valid(_coding_rules_text_edit):
		_settings["coding_rules_text"] = _coding_rules_text_edit.text


func _save_settings() -> void:
	var file: FileAccess = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.WRITE)
	if not is_instance_valid(file):
		return
	file.store_string(JSON.stringify(_settings, "	"))
	file.close()




## ----------------------------
## Template storage
## ----------------------------

func _load_templates() -> void:
	_templates.clear()
	
	if not FileAccess.file_exists(TEMPLATES_FILE_PATH):
		_seed_default_templates()
		_save_templates()
		return
	
	var file: FileAccess = FileAccess.open(TEMPLATES_FILE_PATH, FileAccess.READ)
	if not is_instance_valid(file):
		_seed_default_templates()
		return
	
	var raw_text: String = file.get_as_text()
	file.close()
	
	var parsed: Variant = JSON.parse_string(raw_text)
	if not (parsed is Array):
		_seed_default_templates()
		return
	
	for item: Variant in parsed:
		if not (item is Dictionary):
			continue
		var entry: TemplateEntry = TemplateEntry.from_dictionary(item)
		if entry.template_id.length() == 0 or entry.display_name.length() == 0:
			continue
		_templates.append(entry)
	
	_templates.sort_custom(func(a: TemplateEntry, b: TemplateEntry) -> bool:
		return a.sort_index < b.sort_index
	)
	
	if _templates.size() == 0:
		_seed_default_templates()


func _save_templates() -> void:
	var arr: Array = []
	for entry: TemplateEntry in _templates:
		arr.append(entry.to_dictionary())
	
	var file: FileAccess = FileAccess.open(TEMPLATES_FILE_PATH, FileAccess.WRITE)
	if not is_instance_valid(file):
		return
	
	file.store_string(JSON.stringify(arr, "	"))
	file.close()


func _seed_default_templates() -> void:
	_templates.clear()
	
	# --- Refactors / cleanup ---
	_templates.append(TemplateEntry.new("keep_public_api_cleanup", "Keep public API and clean up internals", "Keep public API and clean up internals. Preserve behavior. Return updated code only.", 0))
	_templates.append(TemplateEntry.new("keep_private_api_cleanup", "Keep private API and clean up internals", "Keep private API and clean up internals. Preserve behavior. Return updated code only.", 1))
	_templates.append(TemplateEntry.new("split_into_helpers", "Split into helper methods", "Refactor by extracting clear helper methods. Preserve behavior. Do not change the public API. Return updated code only.", 2))
	_templates.append(TemplateEntry.new("rename_for_clarity", "Rename for clarity", "Rename variables/functions for clarity and consistency. Keep behavior identical. Update all references. Return updated code only.", 3))
	_templates.append(TemplateEntry.new("remove_dead_code", "Remove dead code", "Remove unused variables, dead branches, and unreachable code. Preserve behavior. Return updated code only.", 4))
	_templates.append(TemplateEntry.new("add_docs_comments", "Add docs/comments", "Add concise doc comments and inline comments where helpful. Do not change behavior. Return updated code only.", 5))
	
	# --- Bugfix / correctness ---
	_templates.append(TemplateEntry.new("fix_bug_preserve", "Fix bug, preserve behavior", "Fix the bug with minimal changes. Preserve behavior elsewhere. Explain the root cause briefly, then return updated code only.", 6))
	_templates.append(TemplateEntry.new("fix_types_strict", "Fix typing / strict types", "Fix type errors and tighten types (variables, function signatures). Preserve behavior. Return updated code only.", 7))
	_templates.append(TemplateEntry.new("edge_cases", "Handle edge cases", "Harden this code against edge cases (nulls, empty arrays, invalid nodes). Preserve normal behavior. Return updated code only.", 8))
	_templates.append(TemplateEntry.new("godot_api_update", "Update to Godot 4.4 API", "Update this code to correct Godot 4.4+ APIs and best practices. Preserve behavior. Return updated code only.", 9))
	
	# --- Performance ---
	_templates.append(TemplateEntry.new("optimize_no_behavior_change", "Optimize (no behavior changes)", "Optimize this code for performance without changing behavior. Avoid micro-optimizations that reduce readability. Return updated code only.", 10))
	_templates.append(TemplateEntry.new("reduce_allocations", "Reduce allocations / GC", "Reduce allocations (arrays, strings, temporary objects) in hot paths. Preserve behavior. Return updated code only.", 11))
	_templates.append(TemplateEntry.new("cache_nodes", "Cache node lookups", "Cache expensive get_node/find calls and repeated queries. Preserve behavior. Return updated code only.", 12))
	
	# --- Explain / review ---
	_templates.append(TemplateEntry.new("explain_code", "Explain what this code does", "Explain what this code does, including key assumptions, data flow, and edge cases. Suggest any risks or improvements.", 13))
	_templates.append(TemplateEntry.new("code_review", "Code review checklist", "Review this code like a senior engineer: correctness, readability, performance, and Godot pitfalls. Provide prioritized actionable notes.", 14))
	_templates.append(TemplateEntry.new("debug_plan", "Debug plan", "Propose a step-by-step debugging plan with concrete checks/logs to isolate the issue. No large refactor unless needed.", 15))
	
	# --- Godot-specific helpers ---
	_templates.append(TemplateEntry.new("signals_cleanup", "Signals cleanup", "Make signal connections safer and clearer. Avoid duplicate connections. Preserve behavior. Return updated code only.", 16))
	_templates.append(TemplateEntry.new("editor_tool_hardening", "Harden @tool script", "Harden this @tool/editor code: handle editor reloads, null interfaces, and avoid leaking nodes. Preserve behavior. Return updated code only.", 17))
	_templates.append(TemplateEntry.new("scene_tree_safety", "SceneTree safety", "Make scene-tree interactions safe: instance validity checks, queue_free timing, and avoiding freed references. Preserve behavior. Return updated code only.", 18))
	
	# --- Style / consistency ---
	_templates.append(TemplateEntry.new("format_to_rules", "Format to my rules", "Rewrite to match my project style rules strictly (tabs, explicit types, no ?:, clear names, ## docs). Preserve behavior. Return updated code only.", 19))
	_templates.append(TemplateEntry.new("public_private_api", "Separate public/private API", "Separate public API from private helpers. Keep public surface minimal and stable. Preserve behavior. Return updated code only.", 20))
