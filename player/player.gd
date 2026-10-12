class_name Player
extends CharacterBody3D
## You, in first person, walking on a rock whose down is always its centre.
##
## WASD walks (Shift runs), Space jumps, and holding Space in the air burns
## the jetpack, which refills on the ground. E is use: tap it at the pod to
## hand in ore, hold it on ore to mine it, or on a lamp or panel to pick it
## back up. 1 and 2 pick a lamp or a panel to build, left-click builds it,
## right-click puts the tool away. F toggles the headlamp.

const LAYER := 4
const GRAVITY := 2.5
const WALK := 5.0
const RUN := 8.5
const ACCEL := 30.0
const AIR_ACCEL := 3.0
const JUMP := 4.0
const JET := 6.0
const JET_DRAIN := 30.0
## The jetpack won't push you up faster than this.
const JET_RISE := 5.0
const JET_REFILL := 45.0
const REACH := 4.5
const BUILD_REACH := 8.0
const MINE_TIME := 1.5
const PICK_UP_TIME := 0.5
const SENSITIVITY := 0.0025
const HEIGHT := 1.8

var game: Game
var camera: Camera3D
var headlamp: SpotLight3D
var fuel := 100.0
var tool: StringName = &""
## What E would do now, and how far through a hold it is, for the HUD.
var prompt := ""
var progress := 0.0
var jetting := false

var _head: Node3D
var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D
var _ghost_meshes := {}
var _pitch := 0.0
var _use_target: Fixture
var _use_held := 0.0
var _use_was_down := false


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = Asteroid.ROCK_LAYER | Fixture.LAYER
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
	_ghost_meshes = {&"lamp": post, &"panel": panel}
	_ghost = MeshInstance3D.new()
	_ghost.top_level = true
	_ghost.material_override = _ghost_material
	_ghost.visible = false
	add_child(_ghost)


## Turns the body so its up points away from the asteroid's centre,
## keeping where it faces as near as it can.
func align_up() -> void:
	var up := global_position.normalized()
	var b := global_basis.orthonormalized()
	var angle := b.y.angle_to(up)
	if angle > 0.0001:
		b = Basis(b.y.cross(up).normalized(), angle) * b
	global_basis = b.orthonormalized()
	up_direction = up


func look(pitch: float) -> void:
	_pitch = pitch
	_head.rotation.x = _pitch


func _unhandled_input(event: InputEvent) -> void:
	if !game or game.state != Game.State.PLAYING:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
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
			KEY_1: tool = &"" if tool == &"lamp" else &"lamp"
			KEY_2: tool = &"" if tool == &"panel" else &"panel"
			KEY_F: headlamp.visible = !headlamp.visible


func _physics_process(delta: float) -> void:
	align_up()
	var up := up_direction
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
	move_and_slide()
	if playing:
		_use(delta)
		_aim_ghost()
	else:
		_ghost.visible = false


func _axis(positive: Key, negative: Key) -> float:
	return (1.0 if Input.is_physical_key_pressed(positive) else 0.0) - (1.0 if Input.is_physical_key_pressed(negative) else 0.0)


## What the crosshair's on, within reach.
func _aim(reach: float) -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_basis.z * reach
	var query := PhysicsRayQueryParameters3D.create(from, to, Asteroid.ROCK_LAYER | Fixture.LAYER, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


func _use(delta: float) -> void:
	var hit := _aim(REACH)
	var target: Fixture = hit.collider if !hit.is_empty() and hit.collider is Fixture else null
	var down := Input.is_physical_key_pressed(KEY_E)
	var pressed := down and !_use_was_down
	_use_was_down = down
	if target != _use_target:
		_use_target = target
		_use_held = 0.0
	prompt = ""
	progress = 0.0
	if !target:
		return
	match target.kind:
		&"pod":
			prompt = "[E] Hand in ore" if game.carried > 0 else "Drop pod"
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
func _placement() -> Dictionary:
	if tool == &"":
		return {}
	var hit := _aim(BUILD_REACH)
	if hit.is_empty() or hit.collider is Fixture:
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
	_ghost.global_transform = Transform3D(Fixture.upright(hit.normal), hit.position + hit.normal * (0.8 if tool == &"lamp" else 0.3))


func _build() -> void:
	var hit := _placement()
	if !hit.is_empty() and game.can_build(tool, hit.position):
		game.build(tool, hit.position, hit.normal)
