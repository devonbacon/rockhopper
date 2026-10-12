extends Control
## The front door: play solo, host, or join a server. Everyone starts as a
## soldier; the commander's seat is in the pod. On the command line (after
## --): server [port=], join=host:port, host, name=; any other argument goes
## straight into a solo game, so the debug arguments keep working.

var _name: LineEdit
var _address: LineEdit
var _status: Label


func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	Net.player_name = args.get("name", Net.player_name)
	Net.role = StringName(args.get("role", Net.role))
	if args.has("seed"):
		Net.seed_value = int(args.seed)
	var port := int(args.get("port", str(Net.PORT)))
	if args.has("server"):
		if Net.start_server(port, true) != OK:
			get_tree().quit(1)
		return
	if args.has("host"):
		Net.start_server(port, false)
		return
	if args.has("join"):
		_build()
		var target := String(args.join).split(":")
		Net.join(target[0], int(target[1]) if target.size() > 1 else Net.PORT)
		return
	if !args.is_empty():
		get_tree().change_scene_to_file.call_deferred("res://game/game.tscn")
		return
	_build()


func _build() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var back := ColorRect.new()
	back.color = Color(0.02, 0.03, 0.05)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.custom_minimum_size = Vector2(420, 0)
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(column)
	var title := Label.new()
	title.text = "ROCKHOPPER"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_name = _field(column, "Name", Net.player_name)
	_address = _field(column, "Server", "192.168.1.27:%d" % Net.PORT)
	for entry: Array in [["Join", _on_join], ["Host here", _on_host], ["Play solo", _on_solo], ["Quit", func() -> void: get_tree().quit()]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size.y = 44
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(entry[1])
		column.add_child(button)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(1.0, 0.7, 0.4)
	column.add_child(_status)
	Net.status.connect(func(text: String) -> void: _status.text = text)


func _field(parent: Control, label: String, value: String) -> LineEdit:
	var row := HBoxContainer.new()
	var caption := Label.new()
	caption.text = label
	caption.custom_minimum_size.x = 90
	row.add_child(caption)
	var edit := LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size.y = 40
	row.add_child(edit)
	parent.add_child(row)
	return edit


func _take_settings() -> void:
	Net.player_name = _name.text.strip_edges() if _name.text.strip_edges() != "" else "Soldier"


func _on_join() -> void:
	_take_settings()
	var target := _address.text.strip_edges().split(":")
	Net.join(target[0], int(target[1]) if target.size() > 1 else Net.PORT)


func _on_host() -> void:
	_take_settings()
	Net.start_server(Net.PORT, false)


func _on_solo() -> void:
	_take_settings()
	Net.leave()
	get_tree().change_scene_to_file("res://game/game.tscn")
