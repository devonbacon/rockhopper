extends Control
## The front door: play solo, host, or join a server. Everyone starts as a
## soldier; the commander's seat is in the pod. On the command line (after
## --): server [port=], join=host:port (or a ws:// or wss:// URL), host,
## name=; any other argument goes straight into a solo game, so the debug
## arguments keep working. In a browser, ?server= and ?name= on the page's
## address fill the fields in.

## Where the server's public address is published, beside the web build.
const SERVER_INFO := "https://play.devoncoleman.com/rockhopper-server.json"
## If that can't be had: the proxy's address in a browser (an HTTPS page
## can't open a plain ws://), the LAN's elsewhere.
var _fallback_server := "wss://rockhopper.play.devoncoleman.com:9443" if OS.has_feature("web") else "192.168.1.27:7777"

var _name: LineEdit
var _address: LineEdit
var _status: Label


func _ready() -> void:
	Music.in_game = false
	if Net.launched:
		_build()
		return
	Net.launched = true
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	var saved := ConfigFile.new()
	saved.load("user://settings.cfg")
	Net.player_name = args.get("name", _query().get("name", saved.get_value("net", "name", Net.player_name)))
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
		Net.join(args.join)
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
	var saved := ConfigFile.new()
	saved.load("user://settings.cfg")
	_name = _field(column, "Name", Net.player_name)
	_address = _field(column, "Server", _query().get("server", saved.get_value("net", "server", "")))
	_address.placeholder_text = "wss://... or host:port"
	if _address.text == "":
		_fetch_server()
	var entries: Array = [["Join", _on_join], ["Host here", _on_host], ["Play solo", _on_solo], ["Quit", func() -> void: get_tree().quit()]]
	if OS.has_feature("web"):
		entries = [entries[0], entries[2]]
	for entry: Array in entries:
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
	_status.text = Net.last_error
	Net.status.connect(func(text: String) -> void: _status.text = text)
	var build := Label.new()
	build.text = "build %s" % Net.version
	build.modulate = Color(1, 1, 1, 0.35)
	build.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(build)


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


## The page's ?key=value pairs, in a browser.
func _query() -> Dictionary:
	var query := {}
	if !OS.has_feature("web"):
		return query
	for part in str(JavaScriptBridge.eval("window.location.search")).trim_prefix("?").split("&", false):
		var pair := part.split("=", true, 1)
		if pair.size() == 2:
			query[pair[0].uri_decode()] = pair[1].uri_decode()
	return query


## Fills the server in from where it's published.
func _fetch_server() -> void:
	var url := SERVER_INFO
	if OS.has_feature("web"):
		url = str(JavaScriptBridge.eval("new URL('../rockhopper-server.json', window.location.href).href"))
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		request.queue_free()
		var info: Variant = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
		if _address.text == "":
			_address.text = info.url if info is Dictionary and info.has("url") else _fallback_server)
	if request.request(url + "?t=%d" % Time.get_unix_time_from_system()) != OK:
		_address.text = _fallback_server


func _take_settings() -> void:
	Net.player_name = _name.text.strip_edges() if _name.text.strip_edges() != "" else "Soldier"
	var saved := ConfigFile.new()
	saved.load("user://settings.cfg")
	saved.set_value("net", "name", Net.player_name)
	saved.set_value("net", "server", _address.text.strip_edges())
	saved.save("user://settings.cfg")


func _on_join() -> void:
	_take_settings()
	Net.join(_address.text.strip_edges())


func _on_host() -> void:
	_take_settings()
	Net.start_server(Net.PORT, false)


func _on_solo() -> void:
	_take_settings()
	Net.leave()
	get_tree().change_scene_to_file("res://game/game.tscn")
