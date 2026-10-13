class_name Commander
extends Node3D
## The commander's view from the pod: overhead on the crater, lit up like
## a tactical display so night doesn't blind it.
##
## WASD, the screen edges or dragging with the middle button pan, the wheel
## zooms, Q and E turn it, and X climbs back out.
##
## Rovers: click one or drag a box round some to select them (Shift adds),
## Tab selects them all. Right-click sends them: on the ground, to drive
## there and wait; on a rig, or the deposit under one, to haul from it
## alone; on a blueprint, to hammer it up, slower than a soldier; on the
## pod, home. The buttons set them hauling wherever's worth
## it, holding still, or home. With no rovers selected, right-click pings
## the spot for the soldiers.
##
## Building: 1-5 or the bar picks something, left-click places it as a
## blueprint, paid for now, for soldiers to hammer up (Shift keeps placing),
## and right-click or Esc puts it away. Delete over a blueprint cancels it,
## refunded. R opens the research panel.

const PAN_SPEED := 40.0
const TURN_SPEED := 1.8
const EDGE := 12.0
const MIN_HEIGHT := 18.0
const MAX_HEIGHT := 140.0
const BUILD: Array[StringName] = [&"lamp", &"panel", &"battery", &"drill", &"lab"]
const PICK := 26.0
const DRAG := 8.0
const SELECTED := Color(0.45, 1.0, 0.55)
const ROVER := Color(1, 1, 1, 0.7)
const SOLDIER := Color(0.45, 0.85, 1.0)
const SPIDER := Color(1.0, 0.3, 0.25)
const PLAN := Color(0.45, 0.8, 1.0)

var game: Game
var camera: Camera3D
var selected: Array[Rover] = []
var placing: StringName = &""

var _height := 70.0
var _yaw := 0.0
var _layer: CanvasLayer
var _overlay: Control
var _status: Label
var _toast: Label
var _toast_time := 0.0
var _build_buttons := {}
var _rover_button: Button
var _orders: Control
var _orders_label: Label
var _research: Control
var _research_rows: VBoxContainer
var _research_buttons := {}
var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D
var _drag_from := Vector2.INF
## Where orders were given lately: [point, age].
var _marks: Array = []
var _hover_plan: Fixture
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
	selected.clear()
	_drag_from = Vector2.INF


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
	selected.assign(selected.filter(func(rover: Rover) -> bool: return is_instance_valid(rover)))
	for mark: Array in _marks:
		mark[1] += delta
	_marks = _marks.filter(func(mark: Array) -> bool: return mark[1] < 0.8)
	_toast_time = maxf(0.0, _toast_time - delta)
	_alarm = maxf(0.0, _alarm - delta * 0.5)
	_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	var hit := _mouse_hit()
	_aim_ghost(hit)
	_hover_plan = hit.collider if !hit.is_empty() and placing == &"" and hit.collider is Fixture and (hit.collider as Fixture).blueprint else null
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
	if DisplayServer.window_is_focused() and _drag_from == Vector2.INF and !Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
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
		var mouse: Vector2 = event.position
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_height = maxf(MIN_HEIGHT, _height * 0.88)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_height = minf(MAX_HEIGHT, _height / 0.88)
			MOUSE_BUTTON_LEFT:
				if placing != &"":
					if event.pressed:
						_place(event.shift_pressed)
				elif event.pressed:
					_drag_from = mouse
				elif _drag_from != Vector2.INF:
					_select(Rect2(_drag_from, mouse - _drag_from).abs(), event.shift_pressed)
					_drag_from = Vector2.INF
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					if placing != &"":
						_choose(&"")
					elif !selected.is_empty():
						_order_at(_mouse_hit())
					else:
						var hit := _mouse_hit()
						if !hit.is_empty():
							game.act(&"ping", [hit.position])
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		var was := _ground_at(event.position - event.relative)
		var now := _ground_at(event.position)
		if was != Vector3.INF and now != Vector3.INF:
			_move_to(global_position + was - now)
	elif event is InputEventKey and event.pressed and !event.echo:
		match event.physical_keycode:
			KEY_X:
				game.act(&"uncommand", [])
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				var kind := BUILD[event.physical_keycode - KEY_1]
				_choose(&"" if placing == kind else kind)
			KEY_TAB:
				selected.assign(game.rovers)
			KEY_R:
				_research.visible = !_research.visible
			KEY_DELETE, KEY_BACKSPACE:
				if _hover_plan:
					game.act(&"cancel", [_hover_plan.net_id])
					toast("%s blueprint cancelled, %d ore back." % [Fixture.NAMES[_hover_plan.kind], Fixture.COST[_hover_plan.kind]])
			KEY_ESCAPE:
				if placing != &"" or !selected.is_empty() or _research.visible:
					_choose(&"")
					selected.clear()
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


func _choose(kind: StringName) -> void:
	placing = kind
	_ghost.visible = false


## Where what's being placed would go, from a mouse hit: a rig snaps to
## the deposit nearest the mouse. Empty if it can't go anywhere there.
func _placement(hit: Dictionary) -> Dictionary:
	if hit.is_empty() or placing == &"":
		return {}
	if placing == &"drill":
		var best: Fixture = null
		for deposit in game.deposits:
			if deposit.global_position.distance_to(hit.position) < 4.0 and (best == null or deposit.global_position.distance_to(hit.position) < best.global_position.distance_to(hit.position)):
				best = deposit
		if best:
			return {position = best.global_position, normal = best.normal}
		return {}
	if hit.collider is Fixture:
		return {}
	if Vector2(hit.position.x, hit.position.z).length() > Terrain.FLOOR_RADIUS + 4.0:
		return {}
	return {position = hit.position, normal = hit.normal}


func _aim_ghost(hit: Dictionary) -> void:
	var spot := _placement(hit)
	_ghost.visible = !spot.is_empty()
	if spot.is_empty():
		return
	_ghost.mesh = Fixture.ghost_mesh(placing) if _ghost.get_meta("kind", &"") != placing else _ghost.mesh
	_ghost.set_meta("kind", placing)
	var ok := game.can_build(placing, spot.position)
	_ghost_material.albedo_color = Color(0.3, 1.0, 0.5, 0.4) if ok else Color(1.0, 0.3, 0.25, 0.4)
	var normal: Vector3 = spot.normal
	_ghost.global_transform = Transform3D(Fixture.upright(normal), spot.position + normal * Fixture.GHOST_LIFT[placing])


func _place(keep_placing: bool) -> void:
	var spot := _placement(_mouse_hit())
	if spot.is_empty():
		return
	if game.stock < Fixture.COST[placing]:
		toast("Not enough ore banked: a %s needs %d." % [String(Fixture.NAMES[placing]).to_lower(), Fixture.COST[placing]])
		return
	if !game.can_build(placing, spot.position):
		toast("Too close to something.")
		return
	game.act(&"blueprint", [placing, spot.position, spot.normal, game.pod.global_position])
	_marks.append([spot.position, 0.0])
	if !keep_placing:
		_choose(&"")


## Click (a small box) or drag-box selection of rovers.
func _select(box: Rect2, additive: bool) -> void:
	if !additive:
		selected.clear()
	var click := box.size.length() < DRAG
	var best: Rover = null
	var best_distance := PICK
	for rover in game.rovers:
		var top := rover.global_position + Terrain.up_at(rover.global_position) * 0.9
		if camera.is_position_behind(top):
			continue
		var at := camera.unproject_position(top)
		if click:
			if at.distance_to(box.position) < best_distance:
				best_distance = at.distance_to(box.position)
				best = rover
		elif box.has_point(at) and !selected.has(rover):
			selected.push_back(rover)
	if best and !selected.has(best):
		selected.push_back(best)


func _order_at(hit: Dictionary) -> void:
	if hit.is_empty():
		return
	var ids: Array = selected.map(func(rover: Rover) -> int: return rover.net_id)
	var target: Fixture = hit.collider if hit.collider is Fixture else null
	if target and target.kind == &"deposit" and target.rig:
		target = target.rig
	if target and target.blueprint:
		game.act(&"order", [ids, &"build", Vector3.INF, target.net_id])
		toast("Building the %s." % String(Fixture.NAMES[target.kind]).to_lower())
	elif target == game.pod:
		game.act(&"order", [ids, &"home", Vector3.INF, 0])
		toast("Heading home.")
	elif target and target.kind == &"drill":
		game.act(&"order", [ids, &"fetch", Vector3.INF, target.net_id])
		toast("Hauling from that rig.")
	else:
		var point: Vector3 = game.terrain.surface_point(hit.position)[0]
		game.act(&"order", [ids, &"move", point, 0])
	_marks.append([hit.position, 0.0])


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

	var orders := HBoxContainer.new()
	orders.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orders.alignment = BoxContainer.ALIGNMENT_CENTER
	orders.add_theme_constant_override("separation", 8)
	_orders_label = _label(16)
	orders.add_child(_orders_label)
	for entry: Array in [["Haul", &"haul"], ["Stay", &"stay"], ["Go home", &"home"]]:
		var button := _button(entry[0], Vector2(100, 36))
		var order: StringName = entry[1]
		button.pressed.connect(func() -> void:
			game.act(&"order", [selected.map(func(rover: Rover) -> int: return rover.net_id), order, Vector3.INF, 0]))
		orders.add_child(button)
	_orders = _panel(orders)
	_orders.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_orders)

	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 6)
	for i in BUILD.size():
		var kind := BUILD[i]
		var button := _button("", Vector2(96, 92))
		button.draw.connect(func() -> void: _draw_build_button(button, kind, i))
		button.pressed.connect(func() -> void: _choose(&"" if placing == kind else kind))
		button.tooltip_text = "%s: %d ore, %d hammer blows" % [Fixture.NAMES[kind], Fixture.COST[kind], Fixture.BUILD_HITS[kind]]
		bar.add_child(button)
		_build_buttons[kind] = button
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 14
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)
	_rover_button = _button("", Vector2(150, 92))
	_rover_button.pressed.connect(func() -> void: game.act(&"press", [game.pod.net_id, &"rover"]))
	bar.add_child(_rover_button)
	var research := _button("Research\n[R]", Vector2(110, 92))
	research.pressed.connect(func() -> void: _research.visible = !_research.visible)
	bar.add_child(research)
	var bar_panel := _panel(bar)
	bar_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(bar_panel)

	var help := _label(13, Hud.DIM)
	help.text = "[WASD / edges] pan  [wheel] zoom  [middle drag] turn  |  [click / drag] select rovers  [Tab] all  [right-click] send  [right-click, none selected] ping  |  [1-5] build  [Del] cancel blueprint  |  [X] leave the pod  [Esc] pause"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(help)

	_research_rows = VBoxContainer.new()
	_research_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_research_rows.add_theme_constant_override("separation", 6)
	var title := _label(18)
	title.text = "RESEARCH"
	_research_rows.add_child(title)
	for upgrade: StringName in Game.UPGRADES:
		var button := _button("", Vector2(380, 34))
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
	var out := game.rovers.filter(func(rover: Rover) -> bool: return rover.task != Rover.Task.PARKED).size()
	var lines := ["ORE  %d / %d" % [game.stock, Game.QUOTA],
		"BATTERY  %d / %d   %+.1f/s" % [game.battery, game.capacity(), game.power_in - game.power_out],
		"LAUNCH IN  %d:%02d" % [int(left) / 60, int(left) % 60],
		"POD HULL  %d%%" % roundi(game.pod.health / game.pod.max_health * 100.0),
		"ROVERS  %d  (%d out)" % [game.rovers.size(), out],
		"SOLDIERS  %d" % (game.bodies.size() - (1 if game.commander_peer != 0 else 0))]
	for lab in game.built:
		if lab.kind == &"lab" and lab.researching != &"":
			var upgrade: Dictionary = Game.UPGRADES[lab.researching]
			lines.append("RESEARCHING  %s  %d%%%s" % [upgrade.name, roundi(lab.research_time / upgrade.time * 100.0), "  NO POWER" if lab.unpowered else ""])
	_status.text = "\n".join(lines)
	_orders.visible = !selected.is_empty()
	_orders_label.text = "%d rover%s selected   " % [selected.size(), "" if selected.size() == 1 else "s"]
	_rover_button.text = "Print rover\n%d ore" % Fixture.COST[&"rover"]
	_rover_button.disabled = game.stock < Fixture.COST[&"rover"]
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


func _draw_build_button(button: Button, kind: StringName, index: int) -> void:
	var affordable: bool = game.stock >= Fixture.COST[kind]
	var tint := Color.WHITE if affordable else Color(1, 1, 1, 0.35)
	var size := button.size
	if placing == kind:
		button.draw_rect(Rect2(Vector2.ZERO, size), Color(Hud.DAY_COLOR, 0.25))
		button.draw_rect(Rect2(Vector2.ZERO, size), Hud.DAY_COLOR, false, 2.0)
	Hud.draw_icon(button, kind, Vector2(size.x * 0.5, 32), tint)
	var font := button.get_theme_default_font()
	button.draw_string(font, Vector2(0, 66), "%d  %s" % [index + 1, {&"lamp": "Lamp", &"panel": "Panel", &"battery": "Battery", &"drill": "Rig", &"lab": "Lab"}[kind]], HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, tint)
	button.draw_string(font, Vector2(0, 83), "%d ore" % Fixture.COST[kind], HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Hud.ORE_COLOR if affordable else Hud.ALERT)


func _draw_overlay() -> void:
	var font := _overlay.get_theme_default_font()
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
		var color := Hud.DAY_COLOR if plan == _hover_plan else PLAN
		var text := "%s %d/%d" % [String(Fixture.NAMES[plan.kind]).to_upper(), plan.hits, plan.hits_needed()]
		if plan == _hover_plan:
			text += "   [Del] cancel"
		_overlay.draw_rect(Rect2(at - Vector2(6, 6), Vector2(12, 12)), color, false, 2.0)
		_text(font, at + Vector2(0, -12), text, 13, color)
	for rig in game.built:
		if rig.kind != &"drill":
			continue
		var at := _screen(rig.global_position + rig.normal * 4.6)
		if at != Vector2.INF:
			var color := Hud.ORE_COLOR if rig.stalled == "" else (Hud.COLD_COLOR if rig.stalled == "dark" else Hud.DAY_COLOR)
			_text(font, at, "RIG %d/%d%s" % [rig.stored, Fixture.HOPPER, "" if rig.stalled == "" else "  " + rig.stalled.to_upper()], 13, color)
	for rover in game.rovers:
		var at := _screen(rover.global_position + Terrain.up_at(rover.global_position) * 0.9)
		if at == Vector2.INF:
			continue
		var chosen := selected.has(rover)
		var color := SELECTED if chosen else ROVER
		_overlay.draw_arc(at, 14.0, 0, TAU, 24, color, 2.5 if chosen else 1.5)
		if chosen:
			var goal := Vector3.INF
			if rover.task == Rover.Task.MOVING:
				goal = rover.move_to
			elif (rover.order == &"fetch" or rover.order == &"build") and is_instance_valid(rover.assigned):
				goal = rover.assigned.global_position
			var to := _screen(goal) if goal != Vector3.INF else Vector2.INF
			if to != Vector2.INF:
				_overlay.draw_dashed_line(at, to, Color(SELECTED, 0.6), 1.5, 8.0)
				_overlay.draw_circle(to, 4.0, Color(SELECTED, 0.6))
			var doing: String = {Rover.Task.PARKED: "parked", Rover.Task.OUTBOUND: "to rig", Rover.Task.LOADING: "loading", Rover.Task.HOMEBOUND: "home", Rover.Task.MOVING: "moving", Rover.Task.BUILDING: "building"}[rover.task]
			if rover.order == &"stay":
				doing = "holding"
			_text(font, at + Vector2(0, 30), "R-%d  %s  %d/%d" % [rover.slot + 1, doing, rover.cargo, game.rover_capacity()], 12, color)
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
	if _drag_from != Vector2.INF:
		var box := Rect2(_drag_from, get_viewport().get_mouse_position() - _drag_from).abs()
		if box.size.length() >= DRAG:
			_overlay.draw_rect(box, Color(SELECTED, 0.08))
			_overlay.draw_rect(box, Color(SELECTED, 0.7), false, 1.0)


func _screen(point: Vector3) -> Vector2:
	if camera.is_position_behind(point):
		return Vector2.INF
	return camera.unproject_position(point)


func _text(font: Font, at: Vector2, text: String, size: int, color: Color) -> void:
	_overlay.draw_string_outline(font, at + Vector2(-100, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 200, size, 4, Color(0, 0, 0, 0.75))
	_overlay.draw_string(font, at + Vector2(-100, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 200, size, color)


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
	button.custom_minimum_size = size
	button.focus_mode = Control.FOCUS_NONE
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
