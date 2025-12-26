# Prompt Composer (Godot 4.4+)
Prompt Composer is a lightweight editor plugin that lets you build structured AI prompts directly from selected code in the Script editor. It does **not** send code anywhere; it only formats text and copies it to your clipboard.

## Features
- Capture selected code from the Script editor
- Template presets + template search
- Optional: include file path, code fences, selection stats
- Prompt style modes (full / instruction only / instruction + code / code only)
- Editable “Project / style rules” block with reset-to-defaults
- Live prompt preview
- Settings persistence (saved to `user://ai_prompt_composer_settings.json`)
- Templates stored in `user://ai_prompt_templates.json`

## Install
- Copy `addons/ai_prompt_composer/` into your project
- Enable: **Project → Project Settings → Plugins → Prompt Composer**

## Usage
1. Open the **Script** tab and select some code.
2. Open the **PromptComposer** tab.
3. Click **Copy prompt** (or **Capture selection** if you want a manual refresh).
4. Paste into your AI tool.

## Notes
- Best results when code is selected in the Script editor.
- `user://` files are stored in Godot’s per-project user data location:
  - Windows: `%APPDATA%/Godot/app_userdata/<ProjectName>/`
  - Linux: `~/.local/share/godot/app_userdata/<ProjectName>/`
  - macOS: `~/Library/Application Support/Godot/app_userdata/<ProjectName>/`

## License
MIT
