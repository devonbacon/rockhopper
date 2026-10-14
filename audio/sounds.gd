class_name Sounds
extends RefCounted
## Everything the music and the sound effects are made from, as one JSON
## file: the score's tempo, chords, theme, patterns, levels and instrument
## settings (see Music), and each effect's instrument and settings (see
## Sfx). The sound editor (F2) edits it in place while it plays.
##
## Run from the Godot editor, saving writes the project's copy. Anywhere
## else it's kept in user://, which then wins over the project's.

const PATH := "res://audio/sounds.json"
const USER_PATH := "user://sounds.json"

static var data: Dictionary = load_data()


static func load_data() -> Dictionary:
	var path := PATH
	if !OS.has_feature("editor") and FileAccess.file_exists(USER_PATH):
		path = USER_PATH
	var loaded := parse(FileAccess.get_file_as_string(path))
	if loaded.is_empty() and path != PATH:
		loaded = parse(FileAccess.get_file_as_string(PATH))
	return loaded


static func parse(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and parsed.get("music") is Dictionary and parsed.get("sfx") is Dictionary:
		return parsed
	return {}


static func to_json() -> String:
	return JSON.stringify(data, "\t") + "\n"


## Writes it where it's kept: see the class notes. Returns where, or "".
static func save() -> String:
	var path := PATH if OS.has_feature("editor") else USER_PATH
	var file := FileAccess.open(path, FileAccess.WRITE)
	if !file:
		return ""
	file.store_string(to_json())
	return ProjectSettings.globalize_path(path)
