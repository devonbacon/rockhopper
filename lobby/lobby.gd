class_name Lobby
extends Node3D
## Before the drop: the map from above, as it'll be played, with its
## deposits (and how much ore each holds) and vents (and what a tap on
## each would make); everyone who's in; and where the pod will land. The
## leader clicks to pick the landing zone (somewhere flat, away from the
## wall, off the deposits and clear of the vents), can roll a new map, and
## drops the pod once everyone's ready. WASD or dragging with the middle
## button pans, the wheel zooms.

const PAN_SPEED := 60.0
const MIN_HEIGHT := 60.0
const MAX_HEIGHT := 220.0
const GOOD := Color(0.45, 1.0, 0.55)
const BAD := Color(1.0, 0.35, 0.3)
const VENT := Color(1.0, 0.6, 0.3)

var game: Game
var camera: Camera3D

var _height := 150.0
var _ring: RangeRing
var _pick_ring: RangeRing
var _layer: CanvasLayer
var _overlay: Control
var _players: Label
var _note: Label
var _ready_button: Button
var _map_button: Button
var _drop_button: Button
var _drop_armed := 0.0
var _hover := Vector3.INF
var _hover_ok := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.far = 2000.0
	camera.fov = 55.0
	add_child(camera)
	for child in game.get_children():
		if child is WorldEnvironment:
			var env: Environment = (child as WorldEnvironment).environment.duplicate()
			env.ambient_light_energy = 0.5
			env.ambient_light_color = Color(0.55, 0.65, 0.85)
			camera.environment = env
	camera.make_current()
	_ring = RangeRing.new()
	add_child(_ring)
	_pick_ring = RangeRing.new()
	add_child(_pick_ring)
	for vent in game.vents:
		var clear := RangeRing.new()
		add_child(clear)
		clear.show_around(vent.global_position, Game.VENT_CLEAR, Color(VENT, 0.35), 0.4)
	_place_camera()
	game.terrain.wall_material.set_shader_parameter("reveal", 1.0e6)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()


func _exit_tree() -> void:
	if is_instance_valid(game.terrain):
		game.terrain.wall_material.set_shader_parameter("reveal", 18.0)


func _process(delta: float) -> void:
	var pan := Vector2(_axis(KEY_D, KEY_A), _axis(KEY_S, KEY_W))
	if pan != Vector2.ZERO and !SoundEditor.open:
		_move(Vector3(pan.x, 0, pan.y).limit_length(1.0) * PAN_SPEED * (_height / 150.0) * delta)
	_hover = Vector3.INF
	var hit := _mouse_hit()
	if !hit.is_empty() and Net.leading():
		_hover = hit.position
		_hover_ok = game.can_land(_hover)
		_ring.show_around(_hover, Game.LANDING_ROOM, GOOD if _hover_ok else BAD, 0.4)
	else:
		_ring.hide_ring()
	if Net.pick != Vector3.INF:
		_pick_ring.show_around(Net.pick, Game.LANDING_ROOM + 1.0, Color(Hud.DAY_COLOR, 0.95), 0.6)
	else:
		_pick_ring.hide_ring()
	_update_ui()
	_overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_height = maxf(MIN_HEIGHT, _height * 0.9)
				_place_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_height = minf(MAX_HEIGHT, _height / 0.9)
				_place_camera()
			MOUSE_BUTTON_LEFT:
				if Net.leading() and _hover != Vector3.INF:
					if _hover_ok:
						Sfx.play(&"place")
						game.lobby_act(&"pick", [_hover])
					else:
						Sfx.play(&"cancel")
						_note.text = game.landing_problem(_hover)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		var scale := _height / get_viewport().get_visible_rect().size.y * 1.1
		_move(Vector3(-event.relative.x, 0, -event.relative.y) * scale)


func _move(by: Vector3) -> void:
	var flat := Vector2(position.x + by.x, position.z + by.z).limit_length(Terrain.FLOOR_RADIUS)
	position = Vector3(flat.x, 0, flat.y)
	_place_camera()


func _place_camera() -> void:
	camera.global_position = global_position + Vector3(0, _height, _height * 0.6)
	camera.look_at(global_position, Vector3.UP)


func _mouse_hit() -> Dictionary:
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var query := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(mouse) * 1000.0, Terrain.ROCK_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query)


func _axis(positive: Key, negative: Key) -> float:
	return (1.0 if Input.is_physical_key_pressed(positive) else 0.0) - (1.0 if Input.is_physical_key_pressed(negative) else 0.0)


func _everyone_ready() -> bool:
	for id in Net.peers:
		if id != Net.leader and !Net.ready_peers.get(id, false):
			return false
	return true


func _update_ui() -> void:
	var lines: Array[String] = []
	if Net.networked():
		for id in Net.peers:
			var mark := "LEADER" if id == Net.leader else ("READY" if Net.ready_peers.get(id, false) else "not ready")
			lines.append("%s%s   %s" % [Net.peers[id].name, " (you)" if id == Net.local_id() else "", mark])
	else:
		lines.append("%s   solo" % Net.player_name)
	_players.text = "\n".join(lines)
	var leading := Net.leading()
	_ready_button.visible = !leading
	_ready_button.text = "Not ready" if Net.ready_peers.get(Net.local_id(), false) else "Ready"
	_map_button.visible = leading
	_drop_button.visible = leading
	_drop_button.disabled = Net.pick == Vector3.INF
	var waiting := !_everyone_ready()
	_drop_button.text = "Drop the pod" if !waiting else ("Drop anyway?" if _now() < _drop_armed else "Drop (not all ready)")
	if _now() < _drop_armed:
		return
	if leading:
		_note.text = "Click the map to pick where the pod lands." if Net.pick == Vector3.INF else ("Ready to drop." if !waiting else "Waiting on everyone to say they're ready.")
	else:
		var who: String = Net.peers.get(Net.leader, {}).get("name", "The leader")
		_note.text = "%s picks where the pod lands and drops it." % who if Net.pick == Vector3.INF else "%s has picked a landing zone." % who


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _drop() -> void:
	if !_everyone_ready() and _now() > _drop_armed:
		_drop_armed = _now() + 3.0
		_note.text = "Not everyone's ready. Press again to drop anyway."
		return
	_drop_armed = 0.0
	Sfx.play(&"press")
	game.lobby_act(&"drop", [])


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_layer.add_child(_overlay)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size.x = 320
	var title := Label.new()
	title.text = "LANDING"
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)
	var seed_label := Label.new()
	seed_label.text = "Asteroid %d" % game.seed_value
	seed_label.modulate = Hud.DIM
	column.add_child(seed_label)
	_players = Label.new()
	_players.add_theme_font_size_override("font_size", 17)
	column.add_child(_players)
	_note = Label.new()
	_note.modulate = Hud.DAY_COLOR
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_note)
	_ready_button = _button(column, "Ready", func() -> void:
		Sfx.play(&"press")
		game.lobby_act(&"ready", [!Net.ready_peers.get(Net.local_id(), false)]))
	_map_button = _button(column, "New map", func() -> void:
		Sfx.play(&"press")
		game.lobby_act(&"reroll", []))
	_drop_button = _button(column, "Drop the pod", _drop)
	_button(column, "Leave" if Net.networked() else "Back to the menu", func() -> void:
		Net.leave()
		get_tree().change_scene_to_file("res://menu/menu.tscn"))
	var help := Label.new()
	help.text = "[WASD / middle drag] pan   [wheel] zoom"
	help.modulate = Hud.DIM
	column.add_child(help)
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.02, 0.03, 0.05, 0.85)
	box.set_content_margin_all(18)
	box.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", box)
	panel.add_child(column)
	panel.position = Vector2(24, 24)
	_layer.add_child(panel)


func _button(parent: Control, text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(pressed)
	parent.add_child(button)
	return button


func _draw_overlay() -> void:
	var font := _overlay.get_theme_default_font()
	var from := _hover if _hover != Vector3.INF else Net.pick
	for deposit in game.deposits:
		_label(font, deposit.global_position + Vector3.UP * 3.0, "ORE %d" % deposit.amount, Hud.ORE_COLOR)
	for vent in game.vents:
		var text := "VENT +%.1f/s" % vent.power
		if from != Vector3.INF:
			text += "  %d m" % roundi(vent.global_position.distance_to(from))
		_label(font, vent.global_position + Vector3.UP * 3.0, text, VENT)
	if Net.pick != Vector3.INF:
		_label(font, Net.pick + Vector3.UP * 6.0, "LANDING ZONE", Hud.DAY_COLOR)


func _label(font: Font, at: Vector3, text: String, color: Color) -> void:
	if camera.is_position_behind(at):
		return
	var spot := camera.unproject_position(at)
	_overlay.draw_string_outline(font, spot + Vector2(-90, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 180, 14, 4, Color(0, 0, 0, 0.75))
	_overlay.draw_string(font, spot + Vector2(-90, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 180, 14, color)
