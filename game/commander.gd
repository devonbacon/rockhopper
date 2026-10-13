class_name Commander
extends Node3D
## The commander's view from the pod: overhead on the playable area, lit up like
## a tactical display so night doesn't blind it.
##
## WASD, the screen edges or dragging with the middle button pan, the wheel
## zooms, Q and E turn it, and X climbs back out.
##
## Building: 1-9 or the bar picks something, the wheel turns it (Ctrl and
## the wheel still zooms), left-click places it as a blueprint for
## soldiers to hammer up, each blow paying its share from the bank (Shift
## keeps placing), and right-click or Esc puts it away. Delete over a
## blueprint cancels it, refunding what's been paid.
##
## Cables: drag from a pylon, rig, foundry or turret, built or still a
## blueprint, to where it runs; or L, then click where it runs from and
## where it runs to (Shift carries on from there). Letting go or clicking
## on open ground puts a pylon blueprint there for it. They're free, laid as
## a blueprint a soldier puts up with one hammer blow once both ends are
## built. They run one way, the way the arrows point; R over a cable turns
## it round, and Delete cuts it.
##
## Click something built to see how it's doing; P, or its button, switches
## it off or on. Right-click pings the spot for the soldiers. R, when not
## over a cable, opens the research panel.

const PAN_SPEED := 40.0
const TURN_SPEED := 1.8
const EDGE := 12.0
const MIN_HEIGHT := 18.0
const MAX_HEIGHT := 140.0
const BUILD: Array[StringName] = [&"lamp", &"panel", &"battery", &"drill", &"lab", &"pylon", &"foundry", &"turret", &"barricade"]
const SHORT := {&"lamp": "Lamp", &"panel": "Panel", &"battery": "Battery", &"drill": "Rig", &"lab": "Lab", &"pylon": "Pylon", &"foundry": "Foundry", &"turret": "Turret", &"barricade": "Wall"}
const PICK := 26.0
const SELECTED := Color(0.45, 1.0, 0.55)
const SOLDIER := Color(0.45, 0.85, 1.0)
const SPIDER := Color(1.0, 0.3, 0.25)
const PLAN := Color(0.45, 0.8, 1.0)
const OFF := Color(0.6, 0.6, 0.65)
const TURN_STEP := PI / 12.0
## How far the mouse goes with the button down before it's a drag.
const DRAG := 12.0

var game: Game
var camera: Camera3D
var placing: StringName = &""
## What's been clicked on, to watch and switch.
var focus: Fixture
var linking := false
## How far what's being placed is turned from facing the pod.
var turn := 0.0

var _height := 70.0
var _yaw := 0.0
var _layer: CanvasLayer
var _overlay: Control
var _status: Label
var _toast: Label
var _toast_time := 0.0
var _build_buttons := {}
var _link_button: Button
var _focus_panel: Control
var _focus_label: Label
var _power_button: Button
var _research: Control
var _research_rows: VBoxContainer
var _research_buttons := {}
var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D
var _link_from: Fixture
## Where a pylon's just been asked for, to carry on from once it shows up.
var _link_next := Vector3.INF
## A cable-end the left button went down on, and where, to drag a cable off.
var _press_on: Fixture
var _press_at := Vector2.ZERO
var _dragging := false
## Where things were placed or linked lately: [point, age].
var _marks: Array = []
var _hover: Fixture
var _hover_link: Link
var _refresh := 0.0
var _alarm := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.far = 2000.0
	camera.fov = 55.0
	add_child(camera)
	for child in game.get_children():
		if child is WorldEnvironment:
			var env: Environment = (child as WorldEnvironment).environment.duplicate()
			env.ambient_light_energy = 0.4
			env.ambient_light_color = Color(0.55, 0.65, 0.85)
			camera.environment = env
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost = MeshInstance3D.new()
	_ghost.material_override = _ghost_material
	_ghost.top_level = true
	_ghost.visible = false
	add_child(_ghost)
	_build_ui()
	global_position = game.pod.global_position
	_place_camera()


func enter() -> void:
	visible = true
	_layer.visible = true
	camera.make_current()
	global_position = game.pod.global_position
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func leave() -> void:
	visible = false
	_layer.visible = false
	_ghost.visible = false
	placing = &""
	focus = null
	_stop_linking()


## The pod's been bitten: a red flash round the edge, and word of it.
func pod_hit() -> void:
	if _alarm <= 0.0:
		toast("The pod is under attack!")
	_alarm = 1.0


func toast(text: String) -> void:
	_toast.text = text
	_toast_time = 3.0


func _process(delta: float) -> void:
	if !visible:
		return
	_pan(delta)
	if !is_instance_valid(focus):
		focus = null
	if !is_instance_valid(_link_from):
		_link_from = null
	if !is_instance_valid(_press_on):
		_press_on = null
	if _link_next != Vector3.INF:
		for plan in game.blueprints:
			if plan.kind == &"pylon" and plan.global_position.distance_to(_link_next) < 0.3:
				_link_from = plan
				_link_next = Vector3.INF
	for mark: Array in _marks:
		mark[1] += delta
	_marks = _marks.filter(func(mark: Array) -> bool: return mark[1] < 0.8)
	_toast_time = maxf(0.0, _toast_time - delta)
	_alarm = maxf(0.0, _alarm - delta * 0.5)
	_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	var hit := _mouse_hit()
	_hover = hit.collider if !hit.is_empty() and placing == &"" and hit.collider is Fixture else null
	if _hover and _hover.kind == &"deposit" and _hover.rig:
		_hover = _hover.rig
	_aim_ghost(hit)
	var was := _hover_link
	_hover_link = _link_under_mouse() if placing == &"" and !linking and (!_hover or _hover.kind == &"deposit") else null
	if is_instance_valid(was) and was != _hover_link:
		was.highlight = false
	if _hover_link:
		_hover_link.highlight = true
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.2
		_update_ui()
	_overlay.queue_redraw()


func _pan(delta: float) -> void:
	_yaw += _axis(KEY_Q, KEY_E) * TURN_SPEED * delta
	var pan := Vector2(_axis(KEY_D, KEY_A), _axis(KEY_S, KEY_W))
	var mouse := get_viewport().get_mouse_position()
	var size := get_viewport().get_visible_rect().size
	if DisplayServer.window_is_focused() and !Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		if mouse.x < EDGE:
			pan.x -= 1.0
		elif mouse.x > size.x - EDGE:
			pan.x += 1.0
		if mouse.y < EDGE:
			pan.y -= 1.0
		elif mouse.y > size.y - EDGE:
			pan.y += 1.0
	var turn := Basis(Vector3.UP, _yaw)
	_move_to(global_position + turn * Vector3(pan.x, 0, pan.y).limit_length(1.0) * PAN_SPEED * (_height / 70.0) * delta)


func _move_to(point: Vector3) -> void:
	var flat := Vector2(point.x, point.z).limit_length(Terrain.FLOOR_RADIUS + 10.0)
	global_position = Vector3(flat.x, 0.0, flat.y)
	_place_camera()


## Where the mouse at this point on screen meets the plane the view's
## centred on, so a middle-drag keeps the same spot under the mouse.
func _ground_at(mouse: Vector2) -> Vector3:
	var hit: Variant = Plane(Vector3.UP, global_position.y).intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	return hit if hit != null else Vector3.INF


func _unhandled_input(event: InputEvent) -> void:
	if !visible:
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					if placing != &"" and !event.ctrl_pressed:
						turn = wrapf(turn + TURN_STEP, -PI, PI)
					else:
						_height = maxf(MIN_HEIGHT, _height * 0.88)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					if placing != &"" and !event.ctrl_pressed:
						turn = wrapf(turn - TURN_STEP, -PI, PI)
					else:
						_height = minf(MAX_HEIGHT, _height / 0.88)
			MOUSE_BUTTON_LEFT:
				if !event.pressed:
					if _dragging and linking and _link_from:
						_link_click(event.shift_pressed)
					_dragging = false
					_press_on = null
					return
				if placing != &"":
					_place(event.shift_pressed)
				elif linking:
					var had := _link_from
					_link_click(event.shift_pressed)
					if !had and _link_from:
						_press_on = _link_from
						_press_at = event.position
				else:
					focus = _hover if _hover and _hover.kind != &"deposit" and _hover.kind != &"ore" and !_hover.blueprint else null
					_update_ui()
					if _hover and _hover != game.pod and Fixture.CABLE_HEIGHT.has(_hover.kind):
						_press_on = _hover
						_press_at = event.position
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					if placing != &"":
						_choose(&"")
					elif linking:
						_stop_linking()
					else:
						var hit := _mouse_hit()
						if !hit.is_empty():
							game.act(&"ping", [hit.position])
	elif event is InputEventMouseMotion and _press_on and !_dragging and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and event.position.distance_to(_press_at) > DRAG:
		_dragging = true
		if !linking:
			_start_linking(true)
		_link_from = _press_on
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		var was := _ground_at(event.position - event.relative)
		var now := _ground_at(event.position)
		if was != Vector3.INF and now != Vector3.INF:
			_move_to(global_position + was - now)
	elif event is InputEventKey and event.pressed and !event.echo:
		match event.physical_keycode:
			KEY_X:
				game.act(&"uncommand", [])
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				var kind := BUILD[event.physical_keycode - KEY_1]
				_choose(&"" if placing == kind else kind)
			KEY_L:
				if linking:
					_stop_linking()
				else:
					_start_linking()
			KEY_P:
				_switch(_hover if _hover and Fixture.SWITCHED.has(_hover.kind) and !_hover.blueprint else focus)
			KEY_R:
				if _hover_link:
					var why := game.can_flip(_hover_link)
					if why != "":
						toast(why)
					else:
						game.act(&"flip", [_hover_link.net_id])
						toast("Cable turned round.")
				else:
					_research.visible = !_research.visible
			KEY_DELETE, KEY_BACKSPACE:
				if _hover and _hover.blueprint:
					game.act(&"cancel", [_hover.net_id])
					toast("%s blueprint cancelled, %s back." % [Fixture.NAMES[_hover.kind], Game.price(_hover.paid(), _hover.paid(true))])
				elif _hover_link:
					game.act(&"unlink", [_hover_link.net_id])
					toast("Cable blueprint cancelled." if _hover_link.blueprint else "Cable cut.")
			KEY_ESCAPE:
				if placing != &"" or linking or focus or _research.visible:
					_choose(&"")
					_stop_linking()
					focus = null
					_research.visible = false
				else:
					return
			_:
				return
		get_viewport().set_input_as_handled()


## What's under the mouse: the rock, or something standing on it.
func _mouse_hit() -> Dictionary:
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var to := from + camera.project_ray_normal(mouse) * 800.0
	var query := PhysicsRayQueryParameters3D.create(from, to, Terrain.ROCK_LAYER | Fixture.LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query)


## The cable nearest the mouse on screen, if one's close enough.
func _link_under_mouse() -> Link:
	var mouse := get_viewport().get_mouse_position()
	var best: Link = null
	var best_distance := 8.0
	for link in game.links:
		var a := _screen(link.start())
		var b := _screen(link.end())
		if a == Vector2.INF or b == Vector2.INF:
			continue
		var distance := mouse.distance_to(Geometry2D.get_closest_point_to_segment(mouse, a, b))
		if distance < best_distance:
			best_distance = distance
			best = link
	return best


func _choose(kind: StringName) -> void:
	placing = kind
	_ghost.visible = false
	if kind != &"":
		_stop_linking()


func _start_linking(quiet := false) -> void:
	_choose(&"")
	linking = true
	_link_from = null
	if !quiet:
		toast("Click where the cable runs from, then where it runs to: open ground puts a pylon there.")


func _stop_linking() -> void:
	linking = false
	_link_from = null
	_link_next = Vector3.INF
	_dragging = false


func _link_click(keep_going: bool) -> void:
	if !_link_from:
		if !_hover:
			return
		if _hover == game.pod:
			toast("The pod only takes cables in.")
		elif !Fixture.CABLE_HEIGHT.has(_hover.kind):
			toast("Cables tie to pylons, rigs, foundries, turrets and the pod.")
		else:
			_link_from = _hover
		return
	if _hover == _link_from:
		return
	if !_hover:
		var spot := _placement(_mouse_hit(), &"pylon")
		if spot.is_empty():
			return
		var why := game.can_link_pylon(_link_from, spot.position, spot.normal)
		if why != "":
			toast(why)
			return
		game.act(&"link_pylon", [_link_from.net_id, spot.position, spot.normal])
		_marks.append([spot.position, 0.0])
		_link_from = null
		if keep_going:
			_link_next = spot.position
		else:
			_stop_linking()
		return
	var why := game.can_link(_link_from, _hover)
	if why != "":
		toast(why)
		return
	game.act(&"link", [_link_from.net_id, _hover.net_id])
	_marks.append([_hover.cable_point(), 0.0])
	if keep_going and _hover != game.pod:
		_link_from = _hover
	else:
		_stop_linking()


func _switch(fixture: Fixture) -> void:
	if !fixture or !Fixture.SWITCHED.has(fixture.kind):
		return
	game.act(&"switch", [fixture.net_id])
	toast("%s switched %s." % [Fixture.NAMES[fixture.kind], "off" if fixture.enabled else "on"])


## Where kind would go, from a mouse hit: a rig snaps to the deposit
## nearest the mouse. Empty if it can't go anywhere there.
func _placement(hit: Dictionary, kind: StringName) -> Dictionary:
	if hit.is_empty() or kind == &"":
		return {}
	if kind == &"drill":
		var best: Fixture = null
		for deposit in game.deposits:
			if deposit.global_position.distance_to(hit.position) < 4.0 and (best == null or deposit.global_position.distance_to(hit.position) < best.global_position.distance_to(hit.position)):
				best = deposit
		if best:
			return {position = best.global_position, normal = best.normal}
		return {}
	if hit.collider is Fixture:
		return {}
	if Vector2(hit.position.x, hit.position.z).length() > Terrain.FLOOR_RADIUS - 1.0:
		return {}
	return {position = hit.position, normal = hit.normal}


## Shows what's being placed where it'd go; or, stringing a cable over open
## ground, the pylon it'd put there.
func _aim_ghost(hit: Dictionary) -> void:
	var kind := placing
	if linking and _link_from and !_hover:
		kind = &"pylon"
	var spot := _placement(hit, kind)
	_ghost.visible = !spot.is_empty()
	if spot.is_empty():
		return
	_ghost.mesh = Fixture.ghost_mesh(kind) if _ghost.get_meta("kind", &"") != kind else _ghost.mesh
	_ghost.set_meta("kind", kind)
	var ok := game.can_build(kind, spot.position, spot.normal) if placing != &"" else game.can_link_pylon(_link_from, spot.position, spot.normal) == ""
	_ghost_material.albedo_color = Color(0.3, 1.0, 0.5, 0.4) if ok else Color(1.0, 0.3, 0.25, 0.4)
	var up: Vector3 = spot.normal if kind == &"drill" else Terrain.up_at(spot.position)
	_ghost.global_transform = Transform3D(Basis.looking_at(-_facing(spot.position, up), up), spot.position + up * Fixture.GHOST_LIFT[kind])


## Which way the front of something placed at pos faces: at the pod,
## turned by the wheel.
func _facing(pos: Vector3, up: Vector3) -> Vector3:
	var towards: Vector3 = game.pod.global_position - pos
	towards -= up * towards.dot(up)
	if towards.length() < 0.1:
		towards = Fixture.upright(up).z
	return towards.normalized().rotated(up, turn)


func _place(keep_placing: bool) -> void:
	var spot := _placement(_mouse_hit(), placing)
	if spot.is_empty():
		return
	if !game.can_build(placing, spot.position, spot.normal):
		toast("Too steep there, or too close to something.")
		return
	var up: Vector3 = spot.normal if placing == &"drill" else Terrain.up_at(spot.position)
	game.act(&"blueprint", [placing, spot.position, spot.normal, spot.position + _facing(spot.position, up) * 5.0])
	_marks.append([spot.position, 0.0])
	if !keep_placing:
		_choose(&"")


func _place_camera() -> void:
	var turn := Basis(Vector3.UP, _yaw)
	camera.global_position = global_position + turn * Vector3(0, _height, _height * 0.75)
	camera.look_at(global_position, Vector3.UP)


func _axis(positive: Key, negative: Key) -> float:
	return (1.0 if Input.is_physical_key_pressed(positive) else 0.0) - (1.0 if Input.is_physical_key_pressed(negative) else 0.0)


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_layer.add_child(_overlay)
	_status = _label(17)
	_status.position = Vector2(24, 20)
	_layer.add_child(_status)
	_toast = _label(20, Hud.DAY_COLOR)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position.y = 70
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_layer.add_child(_toast)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	column.alignment = BoxContainer.ALIGNMENT_END
	column.anchor_left = 0.5
	column.anchor_right = 0.5
	column.anchor_top = 1.0
	column.anchor_bottom = 1.0
	column.offset_top = -20
	column.offset_bottom = -20
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_layer.add_child(column)

	var focus_row := HBoxContainer.new()
	focus_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_row.alignment = BoxContainer.ALIGNMENT_CENTER
	focus_row.add_theme_constant_override("separation", 12)
	_focus_label = _label(16)
	focus_row.add_child(_focus_label)
	_power_button = _button("", Vector2(130, 36))
	_power_button.pressed.connect(func() -> void: _switch(focus))
	focus_row.add_child(_power_button)
	_focus_panel = _panel(focus_row)
	_focus_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_focus_panel)

	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 6)
	for i in BUILD.size():
		var kind := BUILD[i]
		var button := _button("", Vector2(96, 92))
		button.draw.connect(func() -> void: _draw_build_button(button, kind, i))
		button.pressed.connect(func() -> void: _choose(&"" if placing == kind else kind))
		button.tooltip_text = "%s: %s, paid over %d hammer blows" % [Fixture.NAMES[kind], Game.price(Fixture.COST[kind], Fixture.ALLOY.get(kind, 0)), Fixture.BUILD_HITS[kind]]
		bar.add_child(button)
		_build_buttons[kind] = button
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 14
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)
	_link_button = _button("", Vector2(110, 92))
	_link_button.pressed.connect(func() -> void:
		if linking:
			_stop_linking()
		else:
			_start_linking())
	_link_button.tooltip_text = "Cables carry ore and alloy one way, the way the arrows point, up to %d m. Drag one off a pylon, rig, foundry or turret; let go on open ground for a new pylon. Free: a soldier strings each up with one hammer blow once both ends are built, then can ride it." % Link.RANGE
	bar.add_child(_link_button)
	var research := _button("Research\n[R]", Vector2(110, 92))
	research.pressed.connect(func() -> void: _research.visible = !_research.visible)
	bar.add_child(research)
	var bar_panel := _panel(bar)
	bar_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(bar_panel)

	var help := _label(13, Hud.DIM)
	help.text = "[WASD / edges] pan  [wheel] zoom  [middle drag] pan  [Q/E] turn  |  [1-9] build  [wheel] turn it  [Ctrl+wheel] zoom  [drag] / [L] cable  [R] flip cable  [Del] cancel blueprint / cut cable  |  [click] inspect  [P] power  [right-click] ping  |  [X] leave the pod  [Esc] pause"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(help)

	_research_rows = VBoxContainer.new()
	_research_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_research_rows.add_theme_constant_override("separation", 6)
	var title := _label(18)
	title.text = "RESEARCH"
	_research_rows.add_child(title)
	for upgrade: StringName in Game.UPGRADES:
		var button := _button("", Vector2(440, 34))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void:
			var lab := _lab_for(upgrade)
			if lab:
				game.act(&"press", [lab.net_id, upgrade]))
		_research_rows.add_child(button)
		_research_buttons[upgrade] = button
	_research = _panel(_research_rows)
	_research.anchor_left = 1.0
	_research.anchor_right = 1.0
	_research.offset_left = -24
	_research.offset_right = -24
	_research.offset_top = 20
	_research.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_research.visible = false
	_layer.add_child(_research)


## The lab to ask about upgrade: the one researching it, else an idle one,
## else any.
func _lab_for(upgrade: StringName) -> Fixture:
	var lab := game.researching(upgrade)
	if lab:
		return lab
	var labs := game.built.filter(func(f: Fixture) -> bool: return f.kind == &"lab")
	for candidate: Fixture in labs:
		if candidate.researching == &"":
			return candidate
	return labs[0] if !labs.is_empty() else null


func _update_ui() -> void:
	var left := maxf(0.0, Game.MISSION - game.time)
	var lines := ["ORE  %d / %d" % [game.stock, Game.QUOTA],
		"ALLOY  %d" % game.alloy,
		"BATTERY  %d / %d   %+.1f/s" % [game.battery, game.capacity(), game.power_in - game.power_out],
		"LAUNCH IN  %d:%02d" % [int(left) / 60, int(left) % 60],
		"POD HULL  %d%%" % roundi(game.pod.health / game.pod.max_health * 100.0),
		"SOLDIERS  %d" % (game.bodies.size() - (1 if game.commander_peer != 0 else 0))]
	for lab in game.built:
		if lab.kind == &"lab" and lab.researching != &"":
			var upgrade: Dictionary = Game.UPGRADES[lab.researching]
			lines.append("RESEARCHING  %s  %d%%%s" % [upgrade.name, roundi(lab.research_time / upgrade.time * 100.0), "  OFF" if !lab.enabled else ("  NO POWER" if lab.unpowered else "")])
	_status.text = "\n".join(lines)
	_focus_panel.visible = focus != null
	if focus:
		_focus_label.text = "%s   %s" % [_name(focus).to_upper(), _describe(focus)]
		_power_button.visible = Fixture.SWITCHED.has(focus.kind)
		_power_button.text = "Switch off [P]" if focus.enabled else "Switch on [P]"
	_link_button.text = "Cable [L]\nfree"
	_link_button.modulate = Hud.DAY_COLOR if linking else Color.WHITE
	for kind in _build_buttons:
		(_build_buttons[kind] as Button).queue_redraw()
	if _research.visible:
		for upgrade: StringName in _research_buttons:
			var button: Button = _research_buttons[upgrade]
			var lab := _lab_for(upgrade)
			if !lab:
				button.text = "%s   NEEDS A LAB" % Game.UPGRADES[upgrade].name
				button.disabled = true
				continue
			var state: Array = lab.screen.button.call(upgrade)
			button.text = state[0]
			button.disabled = !state[1]
			button.tooltip_text = Game.UPGRADES[upgrade].text


func _name(fixture: Fixture) -> String:
	return "Drop pod" if fixture == game.pod else String(Fixture.NAMES.get(fixture.kind, fixture.kind))


## A line on how something built is doing.
func _describe(fixture: Fixture) -> String:
	var parts: Array[String] = []
	match fixture.kind:
		&"drill":
			parts.append("hopper %d/%d, %s" % [fixture.stored, Fixture.HOPPER, "drilling" if fixture.stalled == "" else fixture.stalled])
		&"foundry":
			parts.append("ore %d/%d, alloy %d/%d, %s (%.0f power/s)" % [fixture.ore_in, Fixture.BIN, fixture.alloy_out, Fixture.BIN, "smelting" if fixture.stalled == "" else fixture.stalled, Game.FOUNDRY_DRAW])
		&"pylon":
			parts.append("passing on %d" % fixture.holding.size())
		&"turret":
			parts.append("ammo %d/%d, %s (%.1f power a shot, fires at spiders in light)" % [fixture.ammo, Fixture.MAGAZINE, "ready" if fixture.stalled == "" else fixture.stalled, Fixture.TURRET_SHOT])
		&"lab":
			parts.append("off" if !fixture.enabled else ("idle" if fixture.researching == &"" else String(Game.UPGRADES[fixture.researching].name).capitalize()))
		&"lamp":
			parts.append("off" if !fixture.enabled else ("lit" if fixture.on else "waiting for dark"))
		&"panel":
			parts.append("in sun" if fixture.sunlit else "shaded")
		&"battery":
			parts.append("%d%% charged" % roundi(fixture.charge * 100.0))
	parts.append("hull %d/%d" % [fixture.health, fixture.max_health])
	if fixture.noise() > 0.0:
		parts.append("LOUD: draws spiders")
	return "   ".join(parts)


func _draw_build_button(button: Button, kind: StringName, index: int) -> void:
	var alloy_cost: int = Fixture.ALLOY.get(kind, 0)
	var affordable: bool = game.stock >= Fixture.COST[kind] and game.alloy >= alloy_cost
	var tint := Color.WHITE
	var size := button.size
	if placing == kind:
		button.draw_rect(Rect2(Vector2.ZERO, size), Color(Hud.DAY_COLOR, 0.25))
		button.draw_rect(Rect2(Vector2.ZERO, size), Hud.DAY_COLOR, false, 2.0)
	Hud.draw_icon(button, kind, Vector2(size.x * 0.5, 32), tint)
	var font := button.get_theme_default_font()
	button.draw_string(font, Vector2(0, 66), "%d  %s" % [index + 1, SHORT[kind]], HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, tint)
	var cost := "%d ore" % Fixture.COST[kind] + (" +%d al" % alloy_cost if alloy_cost > 0 else "")
	button.draw_string(font, Vector2(0, 83), cost, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Hud.ORE_COLOR if affordable else Hud.ALERT)


func _draw_overlay() -> void:
	var font := _overlay.get_theme_default_font()
	for hole in game.holes:
		var at := _screen(hole.global_position)
		if at != Vector2.INF:
			_overlay.draw_arc(at, 12.0, 0, TAU, 24, SPIDER, 2.5)
			_overlay.draw_circle(at, 5.0, Color(SPIDER, 0.5))
			_text(font, at + Vector2(0, 26), "BUG HOLE", 12, SPIDER)
	for spider in game.spiders:
		var at := _screen(spider.global_position)
		if at != Vector2.INF:
			_overlay.draw_circle(at, 4.0, SPIDER)
	for peer in game.bodies:
		if peer == game.commander_peer:
			continue
		var body: Node3D = game.bodies[peer]
		var at := _screen(body.global_position + Vector3.UP * 1.0)
		if at == Vector2.INF:
			continue
		var r := 7.0
		var diamond := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0), at + Vector2(0, -r)])
		_overlay.draw_polyline(diamond, SOLDIER, 2.0)
	for plan in game.blueprints:
		var at := _screen(plan.global_position + plan.normal * 2.0)
		if at == Vector2.INF:
			continue
		var color := Hud.DAY_COLOR if plan == _hover else PLAN
		var text := "%s %d/%d" % [String(Fixture.NAMES[plan.kind]).to_upper(), plan.hits, plan.hits_needed()]
		if plan == _hover:
			text += "   [Del] cancel"
		_overlay.draw_rect(Rect2(at - Vector2(6, 6), Vector2(12, 12)), color, false, 2.0)
		_text(font, at + Vector2(0, -12), text, 13, color)
	for fixture in game.built:
		var text := ""
		var color := Hud.ORE_COLOR
		match fixture.kind:
			&"drill":
				text = "RIG %d/%d%s" % [fixture.stored, Fixture.HOPPER, "" if fixture.stalled == "" else "  " + fixture.stalled.to_upper()]
				color = Hud.ORE_COLOR if fixture.stalled == "" else (Hud.COLD_COLOR if fixture.stalled == "dark" else (OFF if fixture.stalled == "off" else Hud.DAY_COLOR))
			&"foundry":
				text = "FOUNDRY %d>%d%s" % [fixture.ore_in, fixture.alloy_out, "" if fixture.stalled == "" else "  " + fixture.stalled.to_upper()]
				color = Link.ALLOY if fixture.stalled == "" else (OFF if fixture.stalled == "off" else Hud.DAY_COLOR)
			&"turret":
				text = "TURRET %d%s" % [fixture.ammo, "" if fixture.stalled == "" else "  " + fixture.stalled.to_upper()]
				color = Hud.ORE_COLOR if fixture.stalled == "" else (OFF if fixture.stalled == "off" else Hud.ALERT)
			_:
				if Fixture.SWITCHED.has(fixture.kind) and !fixture.enabled:
					text = "OFF"
					color = OFF
		if fixture == focus or fixture == _hover:
			var ring := _screen(fixture.global_position + fixture.normal * 0.5)
			if ring != Vector2.INF:
				_overlay.draw_arc(ring, 22.0, 0, TAU, 32, SELECTED if fixture == focus else Color(SELECTED, 0.5), 2.0)
		if text == "":
			continue
		var at := _screen(fixture.global_position + fixture.normal * 4.6)
		if at != Vector2.INF:
			_text(font, at, text, 13, color)
			if fixture.noise() > 0.0:
				_text(font, at + Vector2(0, 14), "LOUD", 11, Color(SPIDER, 0.8))
	for link in game.links:
		var a := _screen(link.start())
		var b := _screen(link.end())
		if a != Vector2.INF and b != Vector2.INF:
			_arrows(a, b, PLAN if link.blueprint or link == _hover_link else Color(Link.ORE, 0.8))
	if _hover_link:
		var middle := _screen((_hover_link.start() + _hover_link.end()) * 0.5)
		if middle != Vector2.INF:
			_text(font, middle + Vector2(0, -10), ("CABLE BLUEPRINT  [Del] cancel" if _hover_link.blueprint else "CABLE  [Del] cut") + "  [R] flip", 13, PLAN)
	if linking:
		var mouse := get_viewport().get_mouse_position()
		if _link_from:
			var from := _screen(_link_from.cable_point())
			var to := mouse
			var color := Color(SELECTED, 0.5)
			var why := ""
			var length := 0.0
			if _hover and _hover != _link_from:
				to = _screen(_hover.cable_point())
				why = game.can_link(_link_from, _hover)
				length = _link_from.cable_point().distance_to(_hover.cable_point())
			elif !_hover:
				var spot := _placement(_mouse_hit(), &"pylon")
				if !spot.is_empty():
					var top: Vector3 = spot.position + Terrain.up_at(spot.position) * Fixture.CABLE_HEIGHT.pylon
					to = _screen(top)
					why = game.can_link_pylon(_link_from, spot.position, spot.normal)
					length = _link_from.cable_point().distance_to(top)
			if length > 0.0:
				color = SELECTED if why == "" else Hud.ALERT
			if from != Vector2.INF and to != Vector2.INF:
				_overlay.draw_dashed_line(from, to, color, 2.0, 8.0)
				_arrows(from, to, color)
			if why != "":
				_text(font, mouse + Vector2(0, 28), why, 13, Hud.ALERT)
			elif length > 0.0:
				_text(font, mouse + Vector2(0, 28), "%.0f m%s" % [length, "  + pylon" if !_hover else ""], 13, color)
		else:
			_text(font, mouse + Vector2(0, 28), "CABLE FROM...", 13, SELECTED)
	for mark: Array in _marks:
		var at := _screen(mark[0])
		if at != Vector2.INF:
			var t: float = mark[1] / 0.8
			_overlay.draw_arc(at, 6.0 + 18.0 * t, 0, TAU, 24, Color(SELECTED, 1.0 - t), 2.0)
	for ping in game.pings:
		var at := _screen(ping.position)
		if at != Vector2.INF:
			var fade := clampf((Game.PING_TIME - ping.age) / 1.5, 0.0, 1.0)
			var color := Color(Hud.DAY_COLOR if ping.commander else Hud.FUEL_COLOR, fade)
			_overlay.draw_arc(at, 10.0 + 4.0 * sin(ping.age * 6.0), 0, TAU, 24, color, 2.0)
			_text(font, at + Vector2(0, -16), "PING" if ping.commander else String(ping.name).to_upper(), 13, color)
	if _alarm > 0.0:
		_overlay.draw_rect(Rect2(Vector2.ZERO, _overlay.size), Color(Hud.ALERT, 0.5 * _alarm), false, 10.0)


## Arrowheads along a line on screen, the way it runs.
func _arrows(a: Vector2, b: Vector2, color: Color) -> void:
	var span := a.distance_to(b)
	if span < 24.0:
		return
	var along := (b - a) / span
	var across := along.orthogonal()
	var count := clampi(int(span / 70.0), 1, 6)
	for i in count:
		var tip := a + along * (span * (i + 1) / (count + 1) + 5.0)
		_overlay.draw_colored_polygon(PackedVector2Array([tip, tip - along * 10.0 + across * 6.0, tip - along * 10.0 - across * 6.0]), color)


func _screen(point: Vector3) -> Vector2:
	if point == Vector3.INF or camera.is_position_behind(point):
		return Vector2.INF
	return camera.unproject_position(point)


func _text(font: Font, at: Vector2, text: String, size: int, color: Color) -> void:
	_overlay.draw_string_outline(font, at + Vector2(-150, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 300, size, 4, Color(0, 0, 0, 0.75))
	_overlay.draw_string(font, at + Vector2(-150, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 300, size, color)


func _label(size: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.modulate = color
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = size
	button.add_theme_font_size_override("font_size", 15)
	return button


func _panel(content: Control) -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = Hud.PANEL
	style.border_color = Hud.EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(content)
	return panel
