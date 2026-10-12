class_name Player
extends CharacterBody3D
## You, in first person, on the crater floor.
##
## WASD walks (Shift runs), Space jumps, and holding Space in the air burns
## the jetpack, which refills on the ground. Holding Q brings up the radial
## build menu: move the mouse towards a lamp, panel or drill rig and let go
## of Q to take it in hand, or let go in the middle to put it away. Left
## mouse fires, or with something in hand, builds it; a rig goes over a
## deposit. Right-click puts it away. E is use: tap it at the pod to hand
## in ore, on a button on the pod's screen to press it, or at a rig to
## empty its hopper; hold it on ore or a deposit to mine it, or on a lamp,
## panel or rig to pick it back up. F toggles the headlamp.

const LAYER := 4
const GRAVITY := 5.0
const WALK := 5.0
const RUN := 8.5
const ACCEL := 30.0
const AIR_ACCEL := 3.0
const JUMP := 4.5
const JET := 11.0
const JET_DRAIN := 35.0
## The jetpack won't push you up faster than this.
const JET_RISE := 5.0
const JET_REFILL := 45.0
const REACH := 4.5
const BUILD_REACH := 8.0
const MINE_TIME := 1.5
const PICK_UP_TIME := 0.5
## How far out from the middle you can go before the crater wall stops
## you, in case the jetpack gets you up it.
const BOUNDS := Terrain.FLOOR_RADIUS + 9.0
const FIRE_EVERY := 0.14
const DAMAGE := 10.0
const GUN_RANGE := 60.0
const SENSITIVITY := 0.0025
## What the radial menu offers, clockwise from the top.
const BUILD: Array[StringName] = [&"lamp", &"panel", &"drill"]
## How far the mouse has to move from the middle to pick, and how far the
## pointer can go.
const RADIAL_DEAD := 40.0
const RADIAL_REACH := 140.0
const HEIGHT := 1.8

var game: Game
var camera: Camera3D
var headlamp: SpotLight3D
var fuel := 100.0
var tool: StringName = &""
## The radial build menu: whether it's up, and which of BUILD the mouse
## has moved towards (-1 for the middle).
var radial_open := false
var radial_choice := -1
## What E would do now, and how far through a hold it is, for the HUD.
var prompt := ""
var progress := 0.0
var jetting := false
## A line of feedback for the HUD, and how long it's still shown.
var notice := ""
var notice_time := 0.0

var _head: Node3D
var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D
var _ghost_meshes := {}
var _pitch := 0.0
var _use_target: Fixture
var _use_held := 0.0
var _use_was_down := false
var _radial_aim := Vector2.ZERO
var _cooldown := 0.0
var _recoil := 0.0
var _gun: Node3D
var _muzzle: Node3D
var _muzzle_light: OmniLight3D


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = Terrain.ROCK_LAYER | Fixture.LAYER
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.4
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = HEIGHT
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = HEIGHT * 0.5
	add_child(collider)
	_head = Node3D.new()
	_head.position.y = HEIGHT - 0.15
	add_child(_head)
	camera = Camera3D.new()
	camera.fov = 80.0
	camera.near = 0.05
	camera.far = 1500.0
	_head.add_child(camera)
	headlamp = SpotLight3D.new()
	headlamp.light_color = Color(0.85, 0.92, 1.0)
	headlamp.spot_range = 11.0
	headlamp.spot_angle = 20.0
	headlamp.light_energy = 1.6
	headlamp.position = Vector3(0.2, -0.1, 0)
	camera.add_child(headlamp)
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var post := CylinderMesh.new()
	post.top_radius = 0.12
	post.bottom_radius = 0.2
	post.height = 1.6
	var panel := BoxMesh.new()
	panel.size = Vector3(1.6, 0.6, 1.0)
	var rig := CylinderMesh.new()
	rig.top_radius = 0.6
	rig.bottom_radius = 2.4
	rig.height = 3.8
	_ghost_meshes = {&"lamp": post, &"panel": panel, &"drill": rig}
	_build_gun()
	_ghost = MeshInstance3D.new()
	_ghost.top_level = true
	_ghost.material_override = _ghost_material
	_ghost.visible = false
	add_child(_ghost)


func look(pitch: float) -> void:
	_pitch = pitch
	_head.rotation.x = _pitch


func _unhandled_input(event: InputEvent) -> void:
	if !game or game.state != Game.State.PLAYING:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.physical_keycode == KEY_Q and !event.echo:
		if event.pressed:
			radial_open = true
			radial_choice = -1
			_radial_aim = Vector2.ZERO
		elif radial_open:
			radial_open = false
			_choose(&"" if radial_choice < 0 else BUILD[radial_choice])
		return
	if radial_open:
		if event is InputEventMouseMotion:
			_radial_aim = (_radial_aim + event.relative).limit_length(RADIAL_REACH)
			radial_choice = -1
			if _radial_aim.length() > RADIAL_DEAD:
				# Screen y points down, so the top is -PI/2; wedges go clockwise.
				var turn := fposmod(_radial_aim.angle() + PI * 0.5, TAU)
				radial_choice = roundi(turn / (TAU / BUILD.size())) % BUILD.size()
		return
	if event is InputEventMouseMotion and captured:
		rotate_object_local(Vector3.UP, -event.relative.x * SENSITIVITY)
		look(clampf(_pitch - event.relative.y * SENSITIVITY, -1.5, 1.5))
	elif event is InputEventMouseButton and event.pressed:
		if !captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT and tool != &"":
			_build()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			tool = &""
	elif event is InputEventKey and event.pressed and !event.echo:
		match event.physical_keycode:
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_F: headlamp.visible = !headlamp.visible


func _physics_process(delta: float) -> void:
	var up := Vector3.UP
	var playing := game.state == Game.State.PLAYING
	var vertical := up * velocity.dot(up)
	var horizontal := velocity - vertical
	var input := Vector2.ZERO
	if playing:
		input = Vector2(_axis(KEY_D, KEY_A), _axis(KEY_W, KEY_S)).limit_length(1.0)
	var speed := RUN if Input.is_physical_key_pressed(KEY_SHIFT) else WALK
	var wish := (global_basis.x * input.x - global_basis.z * input.y) * speed
	var jump_held := playing and Input.is_physical_key_pressed(KEY_SPACE)
	jetting = false
	if is_on_floor():
		horizontal = horizontal.move_toward(wish, ACCEL * delta)
		fuel = minf(100.0, fuel + JET_REFILL * delta)
		if jump_held:
			vertical = up * JUMP
	else:
		if input != Vector2.ZERO:
			horizontal = horizontal.move_toward(wish, AIR_ACCEL * delta)
		jetting = jump_held and fuel > 0.0
		if jetting:
			if vertical.dot(up) < JET_RISE:
				vertical += up * JET * delta
			horizontal = horizontal.move_toward(wish * 1.2, JET * 0.6 * delta)
			fuel = maxf(0.0, fuel - JET_DRAIN * delta)
	vertical -= up * GRAVITY * delta
	velocity = horizontal + vertical
	var flat := Vector2(global_position.x, global_position.z)
	if flat.length() > BOUNDS and Vector2(velocity.x, velocity.z).dot(flat) > 0.0:
		var out := Vector3(flat.x, 0.0, flat.y).normalized()
		velocity -= out * velocity.dot(out)
	move_and_slide()
	notice_time = maxf(0.0, notice_time - delta)
	_cooldown = maxf(0.0, _cooldown - delta)
	_recoil = maxf(0.0, _recoil - delta * 12.0)
	_muzzle_light.light_energy = _recoil * 3.0
	_gun.position.z = -0.36 + _recoil * 0.04
	if playing:
		_use(delta)
		_aim_ghost()
		var trigger := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if trigger and tool == &"" and !radial_open and _cooldown <= 0.0:
			_fire()
	else:
		_ghost.visible = false


func _axis(positive: Key, negative: Key) -> float:
	return (1.0 if Input.is_physical_key_pressed(positive) else 0.0) - (1.0 if Input.is_physical_key_pressed(negative) else 0.0)


## What the crosshair's on, within reach.
func _aim(reach: float) -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_basis.z * reach
	var query := PhysicsRayQueryParameters3D.create(from, to, Terrain.ROCK_LAYER | Fixture.LAYER, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


func _use(delta: float) -> void:
	var hit := _aim(REACH)
	var target: Fixture = hit.collider if !hit.is_empty() and hit.collider is Fixture else null
	var down := Input.is_physical_key_pressed(KEY_E)
	var pressed := down and !_use_was_down
	var released := !down and _use_was_down
	_use_was_down = down
	if target != _use_target:
		_use_target = target
		_use_held = 0.0
	prompt = ""
	progress = 0.0
	game.pod.screen.hover = &""
	if !target:
		return
	if target.kind == &"pod" and target.screen.aim(camera.global_position, -camera.global_basis.z):
		var labels := {&"rover": "Print a rover", &"hand_in": "Hand in ore"}
		prompt = ("[E] " + labels[target.screen.hover]) if target.screen.hover != &"" else ""
		if pressed:
			target.screen.press()
		return
	match target.kind:
		&"deposit":
			prompt = "[Hold E] Mine" + ("" if target.rig == null else "    a rig's on it")
			_hold(down, delta, MINE_TIME, func() -> void: game.mine(target))
		&"drill":
			var why: String = {"": "drilling", "dark": "too dark to drill", "full": "hopper full"}[target.stalled]
			prompt = "Rig: %d / %d, %s\n[E] Empty hopper    [Hold E] Pick up" % [target.stored, Fixture.HOPPER, why]
			# A tap empties the hopper; holding on picks the rig up.
			if released and _use_held < 0.3 and target.stored > 0:
				game.empty_rig(target)
			_hold(down, delta, PICK_UP_TIME * 2.0, func() -> void: game.pick_up(target))
			if progress < 0.3 / (PICK_UP_TIME * 2.0):
				progress = 0.0
		&"pod":
			prompt = ("[E] Hand in %d ore" % game.carried) if game.carried > 0 else ("Drop pod: %d ore banked" % game.stock)
			if pressed:
				game.hand_in()
		&"ore":
			prompt = "[Hold E] Mine ore (%d)" % target.amount
			_hold(down, delta, MINE_TIME, func() -> void: game.mine(target))
		&"lamp", &"panel":
			prompt = "[Hold E] Pick up %s" % target.kind
			_hold(down, delta, PICK_UP_TIME, func() -> void: game.pick_up(target))


func _hold(down: bool, delta: float, needed: float, done: Callable) -> void:
	_use_held = _use_held + delta if down else 0.0
	progress = _use_held / needed
	if _use_held >= needed:
		_use_held = 0.0
		_use_target = null
		done.call()


## Where the tool in hand would build, or an empty dictionary if it can't.
## A rig goes over the deposit you're looking at.
func _placement() -> Dictionary:
	if tool == &"":
		return {}
	var hit := _aim(BUILD_REACH)
	if hit.is_empty():
		return {}
	if tool == &"drill":
		if hit.collider is Fixture and hit.collider.kind == &"deposit":
			return {position = hit.collider.global_position, normal = Vector3.UP}
		return {}
	if hit.collider is Fixture:
		return {}
	return hit


func _aim_ghost() -> void:
	var hit := _placement()
	_ghost.visible = !hit.is_empty()
	if hit.is_empty():
		return
	_ghost.mesh = _ghost_meshes[tool]
	var ok := game.can_build(tool, hit.position)
	_ghost_material.albedo_color = Color(0.3, 1.0, 0.5, 0.35) if ok else Color(1.0, 0.3, 0.25, 0.35)
	var lift: float = {&"lamp": 0.8, &"panel": 0.3, &"drill": 1.9}[tool]
	_ghost.global_transform = Transform3D(Fixture.upright(hit.normal), hit.position + hit.normal * lift)


func _build() -> void:
	var hit := _placement()
	if !hit.is_empty() and game.can_build(tool, hit.position):
		game.build(tool, hit.position, hit.normal)


## Takes a lamp, panel or rig in hand, or nothing.
func _choose(kind: StringName) -> void:
	tool = kind


func _say(text: String) -> void:
	notice = text
	notice_time = 2.5


## Hitscan: whatever the crosshair's on, out to range. Spiders take damage;
## anything else just stops the shot. The flash lights up the dark.
func _fire() -> void:
	_cooldown = FIRE_EVERY
	_recoil = 1.0
	var from := camera.global_position
	var to := from - camera.global_basis.z * GUN_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to, Terrain.ROCK_LAYER | Fixture.LAYER | Spider.LAYER, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if !hit.is_empty():
		to = hit.position
		if hit.collider is Spider:
			(hit.collider as Spider).hit(DAMAGE)
	_tracer(_muzzle.global_position, to)


func _tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var along := (to - from) / length
	var side := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.7, 1.0, 1.0, 0.9)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.012
	mesh.bottom_radius = 0.012
	mesh.height = 1.0
	mesh.radial_segments = 4
	var tracer := MeshInstance3D.new()
	tracer.mesh = mesh
	tracer.material_override = material
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.add_child(tracer)
	tracer.global_transform = Transform3D(Basis(side, along * length, side.cross(along)), (from + to) * 0.5)
	var fade := tracer.create_tween()
	fade.tween_property(material, "albedo_color:a", 0.0, 0.08)
	fade.tween_callback(tracer.queue_free)


func _build_gun() -> void:
	_gun = Node3D.new()
	_gun.position = Vector3(0.2, -0.17, -0.36)
	_gun.scale = Vector3.ONE * 0.55
	camera.add_child(_gun)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.32, 0.33, 0.36)
	metal.metallic = 0.7
	metal.roughness = 0.35
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.5, 1.0, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.4, 1.0, 1.0)
	glow.emission_energy_multiplier = 3.0
	var body := BoxMesh.new()
	body.size = Vector3(0.08, 0.1, 0.42)
	_gun_part(body, metal, Vector3.ZERO, Vector3.ZERO)
	var grip := BoxMesh.new()
	grip.size = Vector3(0.06, 0.14, 0.07)
	_gun_part(grip, metal, Vector3(0, -0.1, 0.12), Vector3(-0.3, 0, 0))
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.022
	barrel.bottom_radius = 0.03
	barrel.height = 0.26
	_gun_part(barrel, metal, Vector3(0, 0.01, -0.33), Vector3(PI * 0.5, 0, 0))
	var strip := BoxMesh.new()
	strip.size = Vector3(0.02, 0.015, 0.3)
	_gun_part(strip, glow, Vector3(0, 0.055, -0.02), Vector3.ZERO)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.01, -0.47)
	_gun.add_child(_muzzle)
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(0.6, 0.95, 1.0)
	_muzzle_light.omni_range = 9.0
	_muzzle_light.light_energy = 0.0
	_muzzle.add_child(_muzzle_light)


func _gun_part(mesh: Mesh, material: Material, pos: Vector3, rotation_angles: Vector3) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	part.rotation = rotation_angles
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gun.add_child(part)
