class_name Spider
extends CharacterBody3D
## Climbs up out of the rock in the dark and goes for whatever's nearest
## that it can bite: you, a working bot, a lamp or a panel. Sunlight drives
## it back underground. You can outrun one, but not by walking.

const LAYER := 16
const SPEED := 4.6
const GRAVITY := 5.0
const HEALTH := 20.0
const BITE := 6.0
const BITE_EVERY := 0.8
const RISE_TIME := 1.2
const SINK_TIME := 1.0
const SIGHT := 40.0

var game: Game
var health := HEALTH
var target: Node3D

## Counting down while it climbs out of the rock, or sinks back in.
var _rising := RISE_TIME
var _sinking := -1.0
var _bite := 0.0
var _retarget := 0.0
var _sun_check := 0.0
var _walk := 0.0
var _flash := 0.0
var _stuck := 0.0
var _collider: CollisionShape3D
var _legs: Array[Node3D] = []
var _body_material: StandardMaterial3D


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = Asteroid.ROCK_LAYER
	floor_max_angle = deg_to_rad(65.0)
	floor_snap_length = 0.5
	var shape := SphereShape3D.new()
	shape.radius = 0.4
	_collider = CollisionShape3D.new()
	_collider.shape = shape
	_collider.position.y = 0.4
	_collider.disabled = true
	add_child(_collider)
	_build_model()
	global_position -= global_position.normalized() * 1.0
	_retarget = randf() * 0.5
	_sun_check = randf() * 0.5


func _physics_process(delta: float) -> void:
	var up := global_position.normalized()
	_align(up, delta)
	_flash = maxf(0.0, _flash - delta * 5.0)
	_body_material.emission = Color(1.0, 0.9, 0.8) * _flash
	if _rising > 0.0:
		_rising -= delta
		global_position += up * (1.0 / RISE_TIME) * delta
		_animate(delta, 2.0)
		if _rising <= 0.0:
			_collider.disabled = false
		return
	if _sinking >= 0.0:
		_sinking -= delta
		global_position -= up * (1.2 / SINK_TIME) * delta
		_animate(delta, 2.0)
		if _sinking < 0.0:
			game.remove_spider(self)
		return
	_sun_check -= delta
	if _sun_check <= 0.0:
		_sun_check = 0.5
		if game.sun.lights(global_position + up * 0.6, get_world_3d().direct_space_state):
			burrow()
			return
	_retarget -= delta
	if _retarget <= 0.0 or !is_instance_valid(target):
		_retarget = 0.5
		target = game.spider_target(self)
	var vertical := up * velocity.dot(up)
	var horizontal := Vector3.ZERO
	_bite = maxf(0.0, _bite - delta)
	if is_instance_valid(target):
		var to := target.global_position - global_position
		var flat := to - up * to.dot(up)
		if to.length() <= game.bite_reach(target):
			if _bite <= 0.0:
				_bite = BITE_EVERY
				game.damage(target, BITE)
		elif flat.length() > 0.3:
			horizontal = flat.normalized() * SPEED
	if is_on_floor():
		vertical = Vector3.ZERO
		if horizontal != Vector3.ZERO and get_real_velocity().length() < SPEED * 0.3:
			_stuck += delta
			if _stuck > 0.6:
				_stuck = 0.0
				vertical = up * 4.0
		else:
			_stuck = 0.0
	vertical -= up * GRAVITY * delta
	velocity = horizontal + vertical
	up_direction = up
	move_and_slide()
	_animate(delta, horizontal.length() / SPEED)


func hit(amount: float) -> void:
	if _rising > 0.0 or _sinking >= 0.0:
		return
	health -= amount
	_flash = 1.0
	if health <= 0.0:
		game.remove_spider(self)


## Back into the rock, as when the sun reaches it.
func burrow() -> void:
	_sinking = SINK_TIME
	_collider.disabled = true


## Stands it on the rock, turned towards where it's going.
func _align(up: Vector3, delta: float) -> void:
	var ahead := -global_basis.z
	var flat := velocity - up * velocity.dot(up)
	if flat.length() > 0.5:
		ahead = flat.normalized()
	ahead = ahead - up * ahead.dot(up)
	if ahead.length() < 0.01:
		ahead = Fixture.upright(up).z
	global_basis = global_basis.orthonormalized().slerp(Basis.looking_at(ahead.normalized(), up), minf(1.0, delta * 10.0))


func _animate(delta: float, pace: float) -> void:
	_walk += delta * (4.0 + 14.0 * pace)
	for i in _legs.size():
		var leg := _legs[i]
		var side := -1.0 if i % 2 == 0 else 1.0
		var phase := _walk + (i / 2) * PI * 0.5 + (PI if i % 2 == 0 else 0.0)
		leg.rotation = Vector3(0.0, leg.get_meta("yaw") + sin(phase) * 0.35 * minf(1.0, pace + 0.2), side * maxf(0.0, cos(phase)) * 0.3)


func _build_model() -> void:
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color(0.09, 0.07, 0.07)
	_body_material.roughness = 0.55
	_body_material.metallic = 0.2
	_body_material.emission_enabled = true
	_body_material.emission = Color.BLACK
	var abdomen := SphereMesh.new()
	abdomen.radius = 0.38
	abdomen.height = 0.6
	_add_mesh(abdomen, _body_material, Vector3(0, 0.5, 0.32)).scale = Vector3(1.0, 0.85, 1.2)
	var head := SphereMesh.new()
	head.radius = 0.22
	head.height = 0.4
	_add_mesh(head, _body_material, Vector3(0, 0.42, -0.2))
	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = Color(1.0, 0.15, 0.1)
	eye_material.emission_enabled = true
	eye_material.emission = Color(1.0, 0.1, 0.05)
	eye_material.emission_energy_multiplier = 6.0
	var eye := SphereMesh.new()
	eye.radius = 0.04
	eye.height = 0.08
	for offset in [Vector3(-0.08, 0.5, -0.38), Vector3(0.08, 0.5, -0.38), Vector3(-0.14, 0.46, -0.33), Vector3(0.14, 0.46, -0.33)]:
		_add_mesh(eye, eye_material, offset)
	for i in 8:
		var side := -1.0 if i % 2 == 0 else 1.0
		var row := i / 2
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.16, 0.42, -0.25 + row * 0.13)
		pivot.set_meta("yaw", side * (row - 1.5) * -0.35)
		add_child(pivot)
		var knee := Vector3(side * 0.45, 0.32, 0.0)
		var foot := Vector3(side * 0.85, -0.42, 0.0)
		_segment(pivot, Vector3.ZERO, knee, 0.035)
		_segment(pivot, knee, foot, 0.025)
		_legs.push_back(pivot)


func _segment(parent: Node3D, a: Vector3, b: Vector3, radius: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 0.6
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 5
	var along := (b - a).normalized()
	var side := along.cross(Vector3.FORWARD).normalized()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _body_material
	instance.transform = Transform3D(Basis(side, along, side.cross(along)), (a + b) * 0.5)
	parent.add_child(instance)


func _add_mesh(mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	add_child(instance)
	return instance
