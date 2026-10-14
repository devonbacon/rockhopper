extends CanvasLayer
## The sound editor, an autoload: F2 opens and closes it, over the menu or
## the game. Adapted from Real-Time Logistics' music editor.
##
## It edits Sounds while it plays: the score's tempo, levels, patterns,
## chords, theme and instruments (see Music), and each sound effect (see
## Sfx). Every change is heard straight away; only the sounds whose
## settings changed are made again, and an effect plays itself once it's
## made, so you hear what you did. The transport holds a mood and mutes
## parts until the editor closes.
##
## Debug: sound_editor=N (a user arg) opens it on tab N.
##
## Save writes the project's sounds.json when run from the Godot editor,
## and user:// anywhere else. Copy and Paste move the whole thing as JSON.

const WIDTH := 660.0
const ACCENT := Color(1.0, 0.6, 0.2)
const MOODS: Array[String] = ["Follow the game", "Day", "Night", "Swarm", "Siege"]
const PATTERNS: Array[Array] = [["bass", "Bass", false], ["octave", "Bass octave", true], ["arp", "Arpeggio", false], ["hat", "Hat", false], ["open_hat", "Open hat", false], ["kick", "Kick", false], ["snare", "Snare", false], ["guitar", "Guitar mute", false], ["guitar_open", "Guitar open", false]]
## What sets each effect off, to show by it.
const USES := {
	"shot": "Your gun, and other soldiers'",
	"turret": "A turret firing",
	"swing": "The hammer swung",
	"smash": "The hammer hitting a spider",
	"clank": "Hammering a blueprint up, or patching something",
	"mine": "Mining ore or a deposit, by hand or hammer",
	"pick_up": "Picking a building up, emptying a rig, loading a turret",
	"hand_in": "Handing ore in at the pod",
	"spider_hurt": "A spider hit",
	"spider_die": "A spider killed",
	"bite": "A spider biting someone or something",
	"flare": "A flare thrown",
	"grapple": "The grapple fired",
	"latch": "Grabbing a cable to ride",
	"announce": "Any announcement without its own sound",
	"built": "Something finished building",
	"researched": "Research done",
	"alarm": "The pod under attack",
	"ping": "A ping",
	"press": "A screen button, or a commander's click",
	"place": "The commander placing a blueprint or cable",
	"cancel": "The commander cancelling or cutting",
	"respawn": "Back at the pod after dying",
	"jet": "The jetpack, looping while it burns",
	"zip": "Riding a cable, looping",
}
## Seconds an edit waits for the next before it's heard, so dragging a
## slider doesn't ask for sounds at every step.
const APPLY_DELAY := 0.1
## Edits closer together than this undo as one.
const UNDO_MERGE := 0.6
const MAX_UNDO := 100

var open := false
var _panel: PanelContainer
var _status: Label
var _position: Label
var _mood: OptionButton
var _tabs: TabContainer
var _mutes: Dictionary[String, Button] = {}
## Re-reads every field from Sounds, after an edit or undo.
var _refreshers: Array[Callable] = []
var _effect := "shot"
var _audition := ""
var _autoplay: CheckBox
## What's waiting to be heard: the music, and effects by name.
var _music_due := false
var _effects_due: Dictionary[String, bool] = {}
var _apply_in := -1.0
var _undo: Array[Dictionary] = []
var _last_edit := -1000.0
var _mouse_was := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		set_process(false)
		set_process_input(false)
		return
	_panel = PanelContainer.new()
	_panel.theme = _theme()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -WIDTH - 10.0
	_panel.offset_right = -10.0
	_panel.offset_top = 10.0
	_panel.offset_bottom = -10.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.visible = false
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
	_build_header(column)
	_build_transport(column)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_tabs)
	Sfx.made.connect(func(sound_name: String) -> void:
		if sound_name == _audition:
			_audition = ""
			Sfx.play(sound_name))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("sound_editor="):
			toggle()
			_tabs.current_tab = int(arg.get_slice("=", 1))


func toggle() -> void:
	open = !open
	_panel.visible = open
	if open:
		_mouse_was = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_rebuild()
	else:
		Music.hold_mood = -1
		Music.muted.clear()
		Input.mouse_mode = _mouse_was


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and !event.echo:
		if event.keycode == KEY_F2:
			toggle()
			get_viewport().set_input_as_handled()
		elif open and event.keycode == KEY_Z and event.ctrl_pressed and !(get_viewport().gui_get_focus_owner() is LineEdit):
			_pop_undo()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _apply_in >= 0.0:
		_apply_in -= delta
		if _apply_in < 0.0:
			_apply()
	if !open:
		return
	var beats := Music.beats()
	_position.text = "Bar %d  beat %d    %s    %.0f bpm" % [floori(beats / 4.0) + 1, posmod(floori(beats), 4) + 1, Music.MOODS[Music.mood].capitalize(), Music.bpm]


## Lets the music and effects hear what's been edited.
func _apply() -> void:
	if _music_due:
		Music.reload()
	for sound_name in _effects_due:
		Sfx.reload(sound_name)
		if _autoplay.button_pressed:
			_audition = sound_name
	_music_due = false
	_effects_due.clear()


# --- Reading and writing Sounds ------------------------------------------


func _lookup(path: Array) -> Variant:
	var at: Variant = Sounds.data
	for key: Variant in path:
		if !(at is Dictionary) or !at.has(key):
			return null
		at = at[key]
	return at


func _write(path: Array, value: Variant) -> void:
	_remember()
	var at: Dictionary = Sounds.data
	for i in path.size() - 1:
		if !(at.get(path[i]) is Dictionary):
			at[path[i]] = {}
		at = at[path[i]]
	at[path[-1]] = value
	_edited(path)


## Drops the value at `path`, back to its default.
func _erase(path: Array) -> void:
	var chain: Array[Dictionary] = [Sounds.data]
	for i in path.size() - 1:
		var next: Variant = chain[-1].get(path[i])
		if !(next is Dictionary):
			return
		chain.push_back(next)
	if !chain[-1].has(path[-1]):
		return
	_remember()
	chain[-1].erase(path[-1])
	_edited(path)


func _edited(path: Array) -> void:
	if path[0] == "music":
		_music_due = true
	elif path.size() > 1:
		_effects_due[path[1]] = true
	_apply_in = APPLY_DELAY
	_refresh()
	_set_status("Edited (not saved)")


func _refresh() -> void:
	for refresh in _refreshers:
		refresh.call()


## After Sounds has been swapped whole: hears it all again.
func _reload_all() -> void:
	_music_due = true
	for sound_name: String in Sounds.data.sfx:
		_effects_due[sound_name] = true
	_apply()
	_audition = ""
	_rebuild()


# --- Undo ------------------------------------------------------------------


func _remember() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_edit > UNDO_MERGE:
		_undo.push_back(Sounds.data.duplicate(true))
		if _undo.size() > MAX_UNDO:
			_undo.pop_front()
	_last_edit = now


func _pop_undo() -> void:
	if _undo.is_empty():
		_set_status("Nothing to undo")
		return
	Sounds.data = _undo.pop_back()
	_last_edit = -1000.0
	_reload_all()
	_set_status("Undone")


# --- Building --------------------------------------------------------------


func _theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.05, 0.06, 0.08, 0.94)
	panel.border_color = Color(ACCENT, 0.5)
	panel.set_border_width_all(1)
	panel.set_content_margin_all(10)
	theme.set_stylebox("panel", "PanelContainer", panel)
	return theme


func _build_header(column: VBoxContainer) -> void:
	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var title := Label.new()
	title.text = "Sound editor  (F2)"
	title.modulate = ACCENT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(_button("Undo", _pop_undo, "Ctrl+Z"))
	title_row.add_child(_button("✕", toggle))

	var file_row := HBoxContainer.new()
	column.add_child(file_row)
	file_row.add_child(_button("Save", _save, "Into the project when run from the Godot editor; user:// otherwise"))
	file_row.add_child(_button("Copy", func() -> void:
		DisplayServer.clipboard_set(Sounds.to_json())
		_set_status("Copied it all as JSON"), "Everything, as JSON on the clipboard"))
	file_row.add_child(_button("Paste", _paste, "Everything, from JSON on the clipboard"))
	file_row.add_child(_button("Revert", func() -> void:
		_remember()
		Sounds.data = Sounds.load_data()
		_reload_all()
		_set_status("Back to what's saved"), "Drop every edit since the last save"))
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	_status.modulate = Color(1, 1, 1, 0.7)
	file_row.add_child(_status)


func _build_transport(column: VBoxContainer) -> void:
	column.add_child(HSeparator.new())
	_position = Label.new()
	column.add_child(_position)
	var mood_row := HBoxContainer.new()
	column.add_child(mood_row)
	var mood_label := Label.new()
	mood_label.text = "Mood"
	mood_label.custom_minimum_size.x = 60
	mood_row.add_child(mood_label)
	_mood = OptionButton.new()
	for each in MOODS:
		_mood.add_item(each)
	_mood.item_selected.connect(func(index: int) -> void: Music.hold_mood = index - 1)
	mood_row.add_child(_mood)
	var mute_row := HFlowContainer.new()
	column.add_child(mute_row)
	var mute_label := Label.new()
	mute_label.text = "Mute"
	mute_row.add_child(mute_label)
	for part in Music.PARTS:
		var mute := Button.new()
		mute.text = part
		mute.toggle_mode = true
		mute.focus_mode = Control.FOCUS_NONE
		mute.toggled.connect(func(on: bool) -> void:
			if on:
				Music.muted[part] = true
			else:
				Music.muted.erase(part))
		mute_row.add_child(mute)
		_mutes[part] = mute


func _rebuild() -> void:
	_refreshers.clear()
	var open_tab := _tabs.current_tab
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_mood.select(Music.hold_mood + 1)
	for part in _mutes:
		_mutes[part].set_pressed_no_signal(Music.muted.has(part))
	_build_mixer(_page("Mixer"))
	_build_patterns(_page("Patterns"))
	_build_harmony(_page("Harmony"))
	_build_instruments(_page("Instruments"))
	_build_effects(_page("Effects"))
	_tabs.current_tab = clampi(open_tab, 0, _tabs.get_tab_count() - 1)
	_refresh()


func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 4)
	scroll.add_child(page)
	return page


func _build_mixer(page: VBoxContainer) -> void:
	_number(page, "BPM", ["music", "bpm"], 60.0, 200.0, 116.0, true)
	_heading(page, "Levels")
	for part: String in ["pad", "bass", "arp", "brass", "low_brass", "braam", "guitar", "kick", "snare", "hat", "tom", "crash", "riser"]:
		_number(page, part.capitalize(), ["music", "levels", part], 0.0, 1.0, 0.0)
	_heading(page, "Effects")
	var row := HBoxContainer.new()
	page.add_child(row)
	var label := Label.new()
	label.text = "Volume"
	label.custom_minimum_size.x = 118
	row.add_child(label)
	var slider := HSlider.new()
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Sfx.volume
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(value: float) -> void: Sfx.volume = value)
	slider.drag_ended.connect(func(_changed: bool) -> void: Sfx.save_volume())
	row.add_child(slider)


func _build_patterns(page: VBoxContainer) -> void:
	_heading(page, "Click, drag to paint; right-drag or wheel sets strength")
	var note := Label.new()
	note.text = "By day the arpeggio and hats play every other phrase."
	note.modulate = Color(1, 1, 1, 0.6)
	page.add_child(note)
	for mood: String in Music.MOODS:
		_heading(page, mood.capitalize())
		for pattern: Array in PATTERNS:
			_pattern(page, pattern[1], ["music", "patterns", mood, pattern[0]], pattern[2])


func _build_harmony(page: VBoxContainer) -> void:
	_heading(page, "Two bars a chord, four chords a phrase")
	_text(page, "Day chords", ["music", "day_chords"], "Chord names: roots from G under D up to F♯, m for minor. \"Dm Bb F C\"")
	_text(page, "Night chords", ["music", "night_chords"], "The chords for night, the swarm and the siege")
	_heading(page, "The brass theme, over the night chords")
	_text(page, "Theme", ["music", "theme"], "Notes and how many beats each: \"D4:3 F4:1 -:2\", a dash resting. 32 beats fill the phrase.")
	_text(page, "Arpeggio order", ["music", "arp_order"], "Which of the six arpeggio tones each sixteenth plays, 0-5: root, third, fifth, then an octave up")


func _build_instruments(page: VBoxContainer) -> void:
	for key: String in Music.KINDS:
		_instrument(page, key.capitalize(), Music.KINDS[key], ["music", "instruments", key])


func _build_effects(page: VBoxContainer) -> void:
	var names: Array = Sounds.data.sfx.keys()
	names.sort()
	if !names.has(_effect):
		_effect = names[0]
	var row := HBoxContainer.new()
	page.add_child(row)
	var picker := OptionButton.new()
	for each: String in names:
		picker.add_item(each)
	picker.select(names.find(_effect))
	picker.item_selected.connect(func(index: int) -> void:
		_effect = names[index]
		_rebuild())
	row.add_child(picker)
	row.add_child(_button("▶ Play", func() -> void: Sfx.play(_effect)))
	_autoplay = CheckBox.new()
	_autoplay.text = "Play on edit"
	_autoplay.button_pressed = true
	_autoplay.focus_mode = Control.FOCUS_NONE
	row.add_child(_autoplay)
	var use := Label.new()
	use.text = USES.get(_effect, "")
	use.modulate = Color(1, 1, 1, 0.6)
	page.add_child(use)

	var path := ["sfx", _effect]
	var def: Dictionary = Sounds.data.sfx[_effect]
	var instrument := str(def.get("instrument", "snare"))
	var kind_row := HBoxContainer.new()
	page.add_child(kind_row)
	var kind_label := Label.new()
	kind_label.text = "Instrument"
	kind_label.custom_minimum_size.x = 118
	kind_row.add_child(kind_label)
	var kinds := OptionButton.new()
	for each in Sfx.INSTRUMENTS:
		kinds.add_item(each)
	kinds.select(Sfx.INSTRUMENTS.find(instrument))
	kinds.item_selected.connect(func(index: int) -> void:
		_write(path + ["instrument"], Sfx.INSTRUMENTS[index])
		_erase(path + ["settings"])
		_rebuild())
	kind_row.add_child(kinds)
	_number(page, "Level", path + ["level"], 0.0, 1.5, 0.5)
	_number(page, "Vary (semitones)", path + ["vary"], 0.0, 12.0, 0.0)
	_number(page, "Range (m, 0 flat)", path + ["range"], 0.0, 100.0, 0.0)
	if instrument == "lead" or instrument == "bass":
		_number(page, "Note", path + ["note"], 24.0, 108.0, 60.0, true)
		var notes := _line(page, "Run of notes", "")
		notes.tooltip_text = "Semitones from the note, played one after another: \"0 4 7\""
		_refreshers.push_back(func() -> void:
			if !notes.has_focus():
				notes.text = " ".join(PackedStringArray(Array(_lookup(path + ["notes"]) if _lookup(path + ["notes"]) is Array else [0]).map(func(n: Variant) -> String: return str(int(n))))))
		notes.text_submitted.connect(func(_text: String) -> void: notes.release_focus())
		notes.focus_exited.connect(func() -> void:
			var run := []
			for word in notes.text.split(" ", false):
				if word.is_valid_int():
					run.push_back(int(word))
			if !run.is_empty() and run != _lookup(path + ["notes"]):
				_write(path + ["notes"], run))
		_number(page, "Gap (s)", path + ["gap"], 0.0, 0.5, 0.0)
	elif instrument == "hat":
		_number(page, "Decay (s)", path + ["decay"], 0.005, 0.5, 0.05)
	_instrument(page, instrument.capitalize(), instrument, path + ["settings"])


## Which model an instrument makes its sound with, and sliders for each of
## that model's settings, kept at `path`.
func _instrument(page: VBoxContainer, label_text: String, kind: String, path: Array) -> void:
	var table: Dictionary = Sfx.NOISE if kind == "noise" else Instruments.PARAMS[kind]
	var models: Array = table.keys()
	var chosen: Variant = _lookup(path + ["model"])
	var model: String = chosen if models.has(chosen) else models[0]
	var row := HBoxContainer.new()
	page.add_child(row)
	var heading := Label.new()
	heading.text = label_text
	heading.modulate = ACCENT
	heading.custom_minimum_size.x = 118
	row.add_child(heading)
	if models.size() > 1:
		var picker := OptionButton.new()
		for each: String in models:
			picker.add_item(each)
		picker.select(models.find(model))
		picker.item_selected.connect(func(index: int) -> void:
			_write(path + ["model"], models[index])
			_rebuild())
		row.add_child(picker)
	for param: String in table[model]:
		var spec: Array = table[model][param]
		_number(page, param.capitalize(), path + [model, param], spec[1], spec[2], spec[0])


## A number at `path`, showing `fallback` while it's not set.
func _number(page: VBoxContainer, label_text: String, path: Array, lowest: float, highest: float, fallback: float, whole := false) -> void:
	var slider := ParamSlider.new(label_text, lowest, highest)
	page.add_child(slider)
	_refreshers.push_back(func() -> void:
		var found: Variant = _lookup(path)
		slider.set_value(float(found) if found != null else fallback)
		slider.set_source("set" if found != null else "default", found != null))
	slider.changed.connect(func(value: float) -> void: _write(path, roundi(value) if whole else value))
	slider.reset.connect(func() -> void: _erase(path))


## Text at `path`, written when you're done with it.
func _text(page: VBoxContainer, label_text: String, path: Array, tooltip: String) -> void:
	var edit := _line(page, label_text, "")
	edit.tooltip_text = tooltip
	_refreshers.push_back(func() -> void:
		if !edit.has_focus():
			edit.text = str(_lookup(path)) if _lookup(path) != null else "")
	edit.text_submitted.connect(func(_text: String) -> void: edit.release_focus())
	edit.focus_exited.connect(func() -> void:
		if edit.text != str(_lookup(path)):
			_write(path, edit.text))


## A pattern to click in.
func _pattern(page: VBoxContainer, label_text: String, path: Array, octave: bool) -> void:
	var row := HBoxContainer.new()
	page.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 100
	row.add_child(label)
	var steps := StepRow.new()
	steps.octave = octave
	row.add_child(steps)
	row.add_child(_button("✕", func() -> void: _erase(path), "Clear it"))
	_refreshers.push_back(func() -> void: steps.set_pattern(str(_lookup(path)) if _lookup(path) != null else ""))
	steps.changed.connect(func(pattern: String) -> void: _write(path, pattern))


func _heading(page: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = ACCENT
	page.add_child(label)


func _line(page: VBoxContainer, label_text: String, text: String) -> LineEdit:
	var row := HBoxContainer.new()
	page.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 118
	row.add_child(label)
	var edit := LineEdit.new()
	edit.text = text
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit


func _button(text: String, on_press: Callable, tooltip := "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_press)
	return button


# --- Files -----------------------------------------------------------------


func _save() -> void:
	var where := Sounds.save()
	_set_status("Saved to %s" % where if where != "" else "Couldn't save")


func _paste() -> void:
	var pasted := Sounds.parse(DisplayServer.clipboard_get())
	if pasted.is_empty():
		_set_status("The clipboard doesn't hold the sounds' JSON")
		return
	_remember()
	Sounds.data = pasted
	_reload_all()
	_set_status("Pasted (not saved)")


func _set_status(text: String) -> void:
	_status.text = text
