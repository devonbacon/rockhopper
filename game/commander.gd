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
## Cables are the soldiers' to lay; here they show, arrowed the way they
## run.
##
## Click something built to see how it's doing; P, or its button, switches
## it off or on. Right-click pings the spot for the soldiers. R opens the
## research panel; G the armory's, to have gear made for each soldier. L,
## twice, calls the launch: the pod lifts off a little later with
## whoever's aboard; L again calls it off.

const PAN_SPEED := 40.0
## A cell of the research tree, and the gap left between its buttons.
const TREE_CELL := Vector2(230, 54)
const TREE_GAP := Vector2(30, 8)
const TURN_SPEED := 1.8
const EDGE := 12.0
const MIN_HEIGHT := 18.0
const MAX_HEIGHT := 140.0
const BUILD: Array[StringName] = [&"lamp", &"panel", &"battery", &"drill", &"lab", &"pylon", &"foundry", &"turret", &"barricade", &"armory"]
const SHORT := {&"lamp": "Lamp", &"panel": "Panel", &"battery": "Battery", &"drill": "Rig", &"lab": "Lab", &"pylon": "Pylon", &"foundry": "Foundry", &"turret": "Turret", &"barricade": "Wall", &"armory": "Armory"}
const PICK := 26.0
const SELECTED := Color(0.45, 1.0, 0.55)
const SOLDIER := Color(0.45, 0.85, 1.0)
const SPIDER := Color(1.0, 0.3, 0.25)
const PLAN := Color(0.45, 0.8, 1.0)
const OFF := Color(0.6, 0.6, 0.65)
const TURN_STEP := PI / 12.0
## How far the mouse goes with the button down before it's a drag.

var game: Game
var camera: Camera3D
var placing: StringName = &""
## What's been clicked on, to watch and switch.
var focus: Fixture
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
var _focus_panel: Control
var _focus_label: Label
var _power_button: Button
var _research: Control
var _research_buttons := {}
var _research_note: Label
var _research_queue: Label
var _armory: Control
var _armory_grid: GridContainer
var _armory_note: Label
## Whose rows the armory's grid has, to rebuild it when that changes.
var _armory_peers: Array = []
var _launch_button: Button
## Until when a second press of Launch goes ahead.
var _launch_armed := 0.0
var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D
## How far a cable reaches from what's being placed, if it takes cables;
## and where it'd go.
var _ring: RangeRing
var _ghost_at := Vector3.INF
## Where things were placed or linked lately: [point, age].
var _marks: Array = []
var _hover: Fixture
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
	_ring = RangeRing.new()
	add_child(_ring)
	_build_ui()
	global_position = game.pod.global_position
	_place_camera()


func enter() -> void:
	visible = true
	_layer.visible = true
	camera.make_current()
	global_position = game.pod.global_position
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.terrain.wall_material.set_shader_parameter("reveal", 1.0e6)


func leave() -> void:
	visible = false
	_layer.visible = false
	_ghost.visible = false
	_ring.hide_ring()
	placing = &""
	focus = null
	game.terrain.wall_material.set_shader_parameter("reveal", 18.0)


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
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.2
		_update_ui()
	_overlay.queue_redraw()


func _pan(delta: float) -> void:
	if SoundEditor.open:
		return
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
					return
				if placing != &"":
					_place(event.shift_pressed)
				else:
					focus = _hover if _hover and _hover.kind != &"deposit" and _hover.kind != &"ore" and !_hover.blueprint else null
					_update_ui()
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					if placing != &"":
						_choose(&"")
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
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0:
				var kind := BUILD[9 if event.physical_keycode == KEY_0 else event.physical_keycode - KEY_1]
				_choose(&"" if placing == kind else kind)
			KEY_P:
				_switch(_hover if _hover and Fixture.SWITCHED.has(_hover.kind) and !_hover.blueprint else focus)
			KEY_R:
				_show_panel(_research)
			KEY_G:
				_show_panel(_armory)
			KEY_L:
				_launch()
			KEY_DELETE, KEY_BACKSPACE:
				if _hover and _hover.blueprint:
					Sfx.play(&"cancel")
					game.act(&"cancel", [_hover.net_id])
					toast("%s blueprint cancelled, %s back." % [Fixture.NAMES[_hover.kind], Game.price(_hover.paid(), _hover.paid(true))])
			KEY_ESCAPE:
				if placing != &"" or focus or _research.visible or _armory.visible:
					_choose(&"")
					focus = null
					_research.visible = false
					_armory.visible = false
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


## Opens the research or armory panel, closing the other; or closes it.
func _show_panel(panel: Control) -> void:
	var open := !panel.visible
	_research.visible = false
	_armory.visible = false
	panel.visible = open
	_update_ui()


func _choose(kind: StringName) -> void:
	placing = kind
	_ghost.visible = false


## Calls the launch, on a second press within a few seconds; or, counting
## down, calls it off.
func _launch() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if game.launch_at == INF and now > _launch_armed:
		_launch_armed = now + 3.0
		toast("Press Launch again to lift off in %d s. The engines will bring the bugs; anyone not aboard is left behind." % Game.LAUNCH_COUNTDOWN)
		return
	_launch_armed = 0.0
	Sfx.play(&"press")
	game.act(&"launch", [])


func _switch(fixture: Fixture) -> void:
	if !fixture or !Fixture.SWITCHED.has(fixture.kind):
		return
	Sfx.play(&"press")
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


## Shows what's being placed where it'd go.
func _aim_ghost(hit: Dictionary) -> void:
	var kind := placing
	_ring.hide_ring()
	_ghost_at = Vector3.INF
	if kind == &"":
		_ghost.visible = false
		return
	var spot := _placement(hit, kind)
	_ghost.visible = !spot.is_empty()
	if spot.is_empty():
		return
	if Fixture.CABLE_HEIGHT.has(kind):
		_ring.show_around(spot.position, Link.RANGE, Color(Link.ORE, 0.8), 0.7)
		_ghost_at = spot.position
	_ghost.mesh = Fixture.ghost_mesh(kind) if _ghost.get_meta("kind", &"") != kind else _ghost.mesh
	_ghost.set_meta("kind", kind)
	var ok := game.can_build(kind, spot.position, spot.normal)
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
	Sfx.play(&"place")
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
	var research := _button("Research\n[R]", Vector2(110, 92))
	research.pressed.connect(func() -> void: _show_panel(_research))
	bar.add_child(research)
	var gear := _button("Armory\n[G]", Vector2(110, 92))
	gear.pressed.connect(func() -> void: _show_panel(_armory))
	gear.tooltip_text = "Have armories make gear for each soldier"
	bar.add_child(gear)
	_launch_button = _button("", Vector2(110, 92))
	_launch_button.pressed.connect(_launch)
	_launch_button.tooltip_text = "Lift off in %d s, with whoever's aboard. Whatever's banked then is the score; staying on gets you more, but every night's worse.
The engines spooling up tear bug holes open near the pod, and frenzied spiders come for it till lift-off." % Game.LAUNCH_COUNTDOWN
	bar.add_child(_launch_button)
	var bar_panel := _panel(bar)
	bar_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(bar_panel)

	var help := _label(13, Hud.DIM)
	help.text = "[WASD / edges] pan  [wheel] zoom  [middle drag] pan  [Q/E] turn  |  [1-0] build  [wheel] turn it  [Ctrl+wheel] zoom  [Del] cancel blueprint  |  [L] launch  |  [click] inspect  [P] power  [right-click] ping  |  [X] leave the pod  [Esc] pause"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(help)

	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 6)
	var title := _label(18)
	title.text = "RESEARCH"
	rows.add_child(title)
	_research_note = _label(13, Hud.DIM)
	rows.add_child(_research_note)
	var tree := Control.new()
	tree.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var columns := 0
	var tree_rows := 0
	for upgrade: StringName in Game.UPGRADES:
		var at: Vector2i = Game.UPGRADES[upgrade].at
		columns = maxi(columns, at.x + 1)
		tree_rows = maxi(tree_rows, at.y + 1)
		var button := _button("", TREE_CELL - TREE_GAP)
		button.add_theme_font_size_override("font_size", 13)
		for look: String in ["normal", "hover", "pressed", "disabled"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color(1, 1, 1, 0.1 if look == "hover" else 0.04)
			box.border_color = Color(1, 1, 1, 0.35)
			box.set_border_width_all(1)
			box.set_corner_radius_all(4)
			button.add_theme_stylebox_override(look, box)
		button.position = Vector2(at) * TREE_CELL
		button.size = TREE_CELL - TREE_GAP
		button.tooltip_text = Game.UPGRADES[upgrade].text + ("
Gear: then made for each soldier at an armory (G)." if Game.GEAR.has(upgrade) else "")
		button.pressed.connect(func() -> void:
			game.act(&"research", [upgrade])
			Sfx.play(&"press"))
		tree.add_child(button)
		_research_buttons[upgrade] = button
	tree.custom_minimum_size = Vector2(columns, tree_rows) * TREE_CELL - TREE_GAP
	tree.draw.connect(func() -> void: _draw_tree(tree))
	rows.add_child(tree)
	_research_queue = _label(13, Hud.DIM)
	_research_queue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_research_queue.custom_minimum_size.x = tree.custom_minimum_size.x
	rows.add_child(_research_queue)
	_research = _panel(rows)
	_research.anchor_left = 1.0
	_research.anchor_right = 1.0
	_research.offset_left = -24
	_research.offset_right = -24
	_research.offset_top = 20
	_research.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_research.visible = false
	_layer.add_child(_research)

	var gear_rows := VBoxContainer.new()
	gear_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gear_rows.add_theme_constant_override("separation", 6)
	var gear_title := _label(18)
	gear_title.text = "ARMORY"
	gear_rows.add_child(gear_title)
	_armory_note = _label(13, Hud.DIM)
	gear_rows.add_child(_armory_note)
	_armory_grid = GridContainer.new()
	_armory_grid.columns = 1 + Game.GEAR.size()
	_armory_grid.add_theme_constant_override("h_separation", 6)
	_armory_grid.add_theme_constant_override("v_separation", 6)
	gear_rows.add_child(_armory_grid)
	_armory = _panel(gear_rows)
	_armory.anchor_left = 1.0
	_armory.anchor_right = 1.0
	_armory.offset_left = -24
	_armory.offset_right = -24
	_armory.offset_top = 20
	_armory.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_armory.visible = false
	_layer.add_child(_armory)


## The armory's grid: a row per soldier, a button per piece of gear.
func _build_armory_grid(peers: Array) -> void:
	_armory_peers = peers
	for child in _armory_grid.get_children():
		child.queue_free()
	_armory_grid.add_child(_label(13, Hud.DIM))
	for item: StringName in Game.GEAR:
		var head := _label(13, Hud.DIM)
		head.text = Game.UPGRADES[item].name
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_armory_grid.add_child(head)
	for peer: int in peers:
		var who := _label(15)
		who.text = game.name_of(peer) + (" (you)" if peer == Net.local_id() else "")
		who.set_meta("peer", peer)
		_armory_grid.add_child(who)
		for item: StringName in Game.GEAR:
			var info: Dictionary = Game.GEAR[item]
			var button := _button("", Vector2(118, 46))
			button.add_theme_font_size_override("font_size", 12)
			button.tooltip_text = "%s\nMade for one soldier: %s, %ds." % [Game.UPGRADES[item].text, Game.price(info.cost, info.alloy), info.time]
			button.set_meta("item", item)
			button.set_meta("peer", peer)
			button.pressed.connect(func() -> void:
				game.act(&"order", [item, peer])
				Sfx.play(&"press"))
			_armory_grid.add_child(button)


## How a soldier's piece of gear stands: its button's text, and colour.
func _gear_line(item: StringName, peer: int) -> Array:
	var info: Dictionary = Game.GEAR[item]
	if game.equipped(item, peer):
		return ["WORN", Color(SELECTED, 0.8)]
	if game.racked.any(func(entry: Array) -> bool: return entry[0] == item and entry[1] == peer):
		return ["MADE\nwaiting at an armory", Hud.DAY_COLOR]
	var armory := game.making(item, peer)
	if armory:
		return ["%d%%%s\nclick to cancel" % [roundi(armory.research_time / info.time * 100.0), "  NO POWER" if armory.unpowered else ("  OFF" if !armory.enabled else "")], Hud.DAY_COLOR]
	var cost := Game.price(info.cost, info.alloy)
	for i in game.orders.size():
		if game.orders[i][0] == item and game.orders[i][1] == peer:
			return ["ORDERED %d\n%s" % [i + 1, cost if game.has(item) else "awaiting research"], Hud.FUEL_COLOR]
	if !game.has(item):
		return [cost + "\nneeds research", Color(1, 1, 1, 0.5)]
	return [cost, Color.WHITE]


## Lines from each upgrade to what it opens up.
func _draw_tree(tree: Control) -> void:
	for upgrade: StringName in Game.UPGRADES:
		var needs: StringName = Game.UPGRADES[upgrade].get("needs", &"")
		if needs == &"":
			continue
		var from := Vector2(Game.UPGRADES[needs].at) * TREE_CELL + Vector2(TREE_CELL.x - TREE_GAP.x, (TREE_CELL.y - TREE_GAP.y) * 0.5)
		var to := Vector2(Game.UPGRADES[upgrade].at) * TREE_CELL + Vector2(0, (TREE_CELL.y - TREE_GAP.y) * 0.5)
		var bend := Vector2(from.x + TREE_GAP.x * 0.5, from.y)
		var color := Color(SELECTED, 0.9) if game.has(needs) else Color(1, 1, 1, 0.25)
		tree.draw_polyline(PackedVector2Array([from, bend, Vector2(bend.x, to.y), to]), color, 2.0)


## How an upgrade stands: its button's second line, and its colour.
func _research_line(upgrade: StringName) -> Array:
	var info: Dictionary = Game.UPGRADES[upgrade]
	if game.has(upgrade):
		return ["DONE", Color(SELECTED, 0.8)]
	var lab := game.researching(upgrade)
	if lab:
		return ["%d%%%s  click to cancel" % [roundi(lab.research_time / info.time * 100.0), "  NO POWER" if lab.unpowered else ("  OFF" if !lab.enabled else "")], Hud.DAY_COLOR]
	var cost := "%s, %ds" % [Game.price(info.cost, info.alloy), info.time]
	var place := game.research_queue.find(upgrade)
	if place >= 0:
		return ["QUEUED %d  %s" % [place + 1, cost], Hud.FUEL_COLOR]
	var needs: StringName = info.get("needs", &"")
	if needs != &"" and !game.has(needs):
		return [cost, Color(1, 1, 1, 0.5)]
	return [cost, Color.WHITE]


func _update_ui() -> void:
	var left := maxf(0.0, game.launch_at - game.time)
	var lines := ["ORE  %d / %d" % [game.stock, Game.QUOTA],
		"ALLOY  %d" % game.alloy,
		"BATTERY  %d / %d   %+.1f/s" % [game.battery, game.capacity(), game.power_in - game.power_out],
		("LAUNCH IN  %d:%02d" % [int(left) / 60, int(left) % 60]) if game.launch_at < INF else "ON THE ROCK  %d:%02d" % [int(game.time) / 60, int(game.time) % 60],
		"POD HULL  %d%%" % roundi(game.pod.health / game.pod.max_health * 100.0),
		"SOLDIERS  %d" % (game.bodies.size() - (1 if game.commander_peer != 0 else 0))]
	for lab in game.built:
		if lab.kind == &"lab" and lab.researching != &"":
			var upgrade: Dictionary = Game.UPGRADES[lab.researching]
			lines.append("RESEARCHING  %s  %d%%%s" % [upgrade.name, roundi(lab.research_time / upgrade.time * 100.0), "  OFF" if !lab.enabled else ("  NO POWER" if lab.unpowered else "")])
	for armory in game.built:
		if armory.kind == &"armory" and armory.researching != &"":
			lines.append("MAKING  %s for %s  %d%%%s" % [Game.UPGRADES[armory.researching].name, game.name_of(armory.made_for).to_upper(), roundi(armory.research_time / Game.GEAR[armory.researching].time * 100.0), "  OFF" if !armory.enabled else ("  NO POWER" if armory.unpowered else "")])
	_status.text = "\n".join(lines)
	_focus_panel.visible = focus != null
	if focus:
		_focus_label.text = "%s   %s" % [_name(focus).to_upper(), _describe(focus)]
		_power_button.visible = Fixture.SWITCHED.has(focus.kind)
		_power_button.text = "Switch off [P]" if focus.enabled else "Switch on [P]"
	_launch_button.text = "Call off\n[L]" if game.launch_at < INF else "Launch\n[L]"
	_launch_button.modulate = Hud.ALERT if game.launch_at < INF or Time.get_ticks_msec() / 1000.0 < _launch_armed else Color.WHITE
	for kind in _build_buttons:
		(_build_buttons[kind] as Button).queue_redraw()
	if _research.visible:
		var labs := game.built.filter(func(f: Fixture) -> bool: return f.kind == &"lab")
		var idle := labs.filter(func(f: Fixture) -> bool: return f.researching == &"" and f.enabled).size()
		_research_note.text = "Click to queue (with what it needs); click again to take it off, or cancel it.\n%s" % ("No lab yet: build one to research." if labs.is_empty() else "%d lab%s, %d idle." % [labs.size(), "" if labs.size() == 1 else "s", idle])
		for upgrade: StringName in _research_buttons:
			var button: Button = _research_buttons[upgrade]
			var line := _research_line(upgrade)
			button.text = "%s\n%s" % [Game.UPGRADES[upgrade].name, line[0]]
			button.modulate = line[1]
			button.disabled = game.has(upgrade)
		var queued := game.research_queue.map(func(id: StringName) -> String: return String(Game.UPGRADES[id].name).capitalize())
		_research_queue.text = "Queue: %s" % (" > ".join(queued) if !queued.is_empty() else "empty")
		_research.get_child(0).get_child(2).queue_redraw()
	if _armory.visible:
		var peers := game.bodies.keys()
		peers.sort()
		if peers != _armory_peers:
			_build_armory_grid(peers)
		var armories := game.built.filter(func(f: Fixture) -> bool: return f.kind == &"armory")
		var idle := armories.filter(func(f: Fixture) -> bool: return f.researching == &"" and f.enabled).size()
		_armory_note.text = "Click to order gear for a soldier (researching it first, if need be); click again to take it back.\nIt waits at the armory for them. Fall and not get back up, and you lose what you wore.\n%s" % ("No armory yet: build one to make gear." if armories.is_empty() else "%d armor%s, %d idle." % [armories.size(), "y" if armories.size() == 1 else "ies", idle])
		for child in _armory_grid.get_children():
			if child is Button and child.has_meta("item"):
				var line := _gear_line(child.get_meta("item"), child.get_meta("peer"))
				(child as Button).text = line[0]
				(child as Button).modulate = line[1]
				(child as Button).disabled = line[0] == "WORN"


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
		&"armory":
			parts.append("off" if !fixture.enabled else ("idle" if fixture.researching == &"" else "making a %s for %s" % [String(Game.UPGRADES[fixture.researching].name).capitalize(), game.name_of(fixture.made_for)]))
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
	button.draw_string(font, Vector2(0, 66), "%d  %s" % [(index + 1) % 10, SHORT[kind]], HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, tint)
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
	for fixture: Fixture in game.built + [game.pod]:
		if fixture.health < fixture.max_health - 0.5:
			var bar := _screen(fixture.global_position + fixture.normal * Hud.bar_height(fixture))
			if bar != Vector2.INF:
				Hud.draw_health_bar(_overlay, bar + Vector2(0, 10), fixture.health / fixture.max_health)
	for link in game.links:
		var a := _screen(link.start())
		var b := _screen(link.end())
		if a != Vector2.INF and b != Vector2.INF:
			_arrows(a, b, PLAN if link.blueprint else Color(Link.ORE, 0.8))
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
	# Placing something that takes cables: what's in a cable's reach of it.
	if _ghost_at != Vector3.INF:
		var from := _screen(_ghost_at + Vector3.UP * 2.0)
		for fixture: Fixture in game.built + game.blueprints + [game.pod]:
			if Fixture.CABLE_HEIGHT.has(fixture.kind) and fixture.global_position.distance_to(_ghost_at) < Link.RANGE:
				var at := _screen(fixture.cable_point())
				if at != Vector2.INF:
					_overlay.draw_arc(at, 9.0, 0, TAU, 20, Link.ORE, 2.0)
					if from != Vector2.INF:
						_overlay.draw_line(at, from, Color(Link.ORE, 0.35), 1.5)
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
