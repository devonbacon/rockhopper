class_name Rover
extends Node3D
## A six-wheeled hauler. It waits by the pod until a rig's hopper has a
## load worth the trip, drives out along the navigation mesh, empties the
## hopper, and drives the ore home.
##
## It drives in the dark too, by its own headlights, so it's in spiders'
## reach the whole way out and back: anywhere but parked by the pod. A
## rover that's destroyed is gone with what it carried. If it can't find a
## way to a rig, it comes home and leaves that rig alone for a while.

enum Task { PARKED, OUTBOUND, LOADING, HOMEBOUND }

const SPEED := 4.0
## How fast it turns, in radians a second.
const TURN := 2.2
const LOAD_TIME := 2.0
const CAPACITY := 6
const HEALTH := 40.0
const WHEEL_RADIUS := 0.32
## How long it leaves a rig it couldn't reach.
const GIVE_UP_FOR := 30.0

var game: Game
var task := Task.PARKED
var rig: Fixture
var cargo := 0
var health := HEALTH
## Which place round the pod is its own.
var slot := 0
## Rigs it couldn't reach, and when it may try again.
var unreachable := {}

var _path := PackedVector3Array()
var _next := 0
var _goal := Vector3.INF
var _repath := 0.0
var _heading := Vector3.FORWARD
var _ground_up := Vector3.UP
var _loading := 0.0
var _flash := 0.0
var _wheels: Array[Node3D] = []
var _hull: StandardMaterial3D
var _load: Node3D


func _ready() -> void:
	_build_model()
	_heading = -global_basis.z


func _physics_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 4.0)
	_hull.emission = Color(1.0, 0.3, 0.2) * _flash
	_load.visible = cargo > 0
	match task:
		Task.PARKED:
			_drive_to(park_point(), 1.0, delta)
			rig = game.pick_rig(self)
			if rig:
				task = Task.OUTBOUND
		Task.OUTBOUND:
			if !is_instance_valid(rig):
				task = Task.HOMEBOUND
			else:
				var arrived := _drive_to(rig.global_position, 3.4, delta)
				if arrived > 0:
					task = Task.LOADING
					_loading = 0.0
				elif arrived < 0:
					unreachable[rig] = game.time + GIVE_UP_FOR
					task = Task.HOMEBOUND
		Task.LOADING:
			if !is_instance_valid(rig):
				task = Task.HOMEBOUND
			else:
				_loading += delta
				if _loading >= LOAD_TIME:
					cargo += rig.take(CAPACITY - cargo)
					task = Task.HOMEBOUND
		Task.HOMEBOUND:
			if _drive_to(game.pod.global_position, 4.6, delta) != 0:
				game.deliver(cargo)
				cargo = 0
				task = Task.PARKED


## Whether it's somewhere a spider could get at it.
func exposed() -> bool:
	return task != Task.PARKED or global_position.distance_to(game.pod.global_position) > 9.0


func damage(amount: float) -> void:
	health -= amount
	_flash = 1.0


func park_point() -> Vector3:
	var angle := 2.2 + slot * 0.75
	return game.pod.global_position + Vector3(cos(angle), 0.0, sin(angle)) * 6.5


## Drives a step towards target along a path. 1 once it's within arrive
## (across the ground), -1 if the path's run out short of it, else 0.
func _drive_to(target: Vector3, arrive: float, delta: float) -> int:
	var pos := global_position
	var flat := Vector2(target.x - pos.x, target.z - pos.z)
	if flat.length() <= arrive:
		return 1
	_repath -= delta
	if _goal.distance_to(target) > 0.5 or _repath <= 0.0:
		_goal = target
		_repath = 3.0
		_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, pos, target, true)
		_next = 0
	while _next < _path.size() and Vector2(_path[_next].x - pos.x, _path[_next].z - pos.z).length() < 1.0:
		_next += 1
	var waypoint := target
	if !_path.is_empty():
		if _next >= _path.size():
			return 1 if flat.length() < arrive * 2.5 else -1
		waypoint = _path[_next]
	var want := Vector3(waypoint.x - pos.x, 0.0, waypoint.z - pos.z).normalized()
	var turn := _heading.signed_angle_to(want, Vector3.UP)
	_heading = _heading.rotated(Vector3.UP, clampf(turn, -TURN * delta, TURN * delta)).normalized()
	var speed := SPEED * clampf(_heading.dot(want), 0.15, 1.0)
	var step := _heading * speed * delta
	_settle(pos + step, delta)
	for wheel in _wheels:
		wheel.rotate_object_local(Vector3.RIGHT, -speed * delta / WHEEL_RADIUS)
	return 0


## Puts it at pos on the ground, tilted to the slope under it.
func _settle(pos: Vector3, delta: float) -> void:
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 3.0, pos - Vector3.UP * 6.0, Terrain.ROCK_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if !hit.is_empty():
		pos.y = hit.position.y
		_ground_up = _ground_up.slerp(hit.normal, minf(1.0, delta * 6.0)).normalized()
	var ahead := (_heading - _ground_up * _heading.dot(_ground_up)).normalized()
	global_transform = Transform3D(Basis.looking_at(ahead, _ground_up), pos)


func _build_model() -> void:
	_hull = _material(Color(0.9, 0.9, 0.88), 0.3, 0.45)
	_hull.emission_enabled = true
	_hull.emission = Color.BLACK
	var gold := _material(Color(0.85, 0.62, 0.22), 0.9, 0.3)
	var dark := _material(Color(0.12, 0.12, 0.14), 0.4, 0.6)
	var orange := _material(Color(1.0, 0.45, 0.1), 0.1, 0.5)
	var cells := _material(Color(0.06, 0.1, 0.32), 0.6, 0.18)
	_add_box(Vector3(1.3, 0.45, 1.9), _hull, Vector3(0, 0.85, 0))
	_add_box(Vector3(1.0, 0.25, 1.6), gold, Vector3(0, 0.55, 0))
	_add_box(Vector3(1.45, 0.04, 1.3), cells, Vector3(0, 1.1, 0.25))
	_add_box(Vector3(1.32, 0.08, 0.08), orange, Vector3(0, 0.9, -0.96))
	_add_box(Vector3(0.08, 0.9, 0.08), _hull, Vector3(0.45, 1.5, -0.7))
	_add_box(Vector3(0.3, 0.18, 0.2), _hull, Vector3(0.45, 2.0, -0.7))
	_add_box(Vector3(0.2, 0.08, 0.04), dark, Vector3(0.45, 2.0, -0.81))
	for side in [-1.0, 1.0]:
		_add_box(Vector3(0.08, 0.08, 1.7), dark, Vector3(side * 0.72, 0.62, 0))
		for z in [-0.75, 0.0, 0.75]:
			var wheel := Node3D.new()
			wheel.position = Vector3(side * 0.85, WHEEL_RADIUS, z)
			add_child(wheel)
			var tyre := CylinderMesh.new()
			tyre.top_radius = WHEEL_RADIUS
			tyre.bottom_radius = WHEEL_RADIUS
			tyre.height = 0.24
			tyre.radial_segments = 10
			var instance := MeshInstance3D.new()
			instance.mesh = tyre
			instance.material_override = dark
			instance.rotation.z = PI * 0.5
			wheel.add_child(instance)
			var hub := BoxMesh.new()
			hub.size = Vector3(0.26, 0.4, 0.08)
			var spoke := MeshInstance3D.new()
			spoke.mesh = hub
			spoke.material_override = _hull
			wheel.add_child(spoke)
			_wheels.push_back(wheel)
	_load = Node3D.new()
	add_child(_load)
	var crystal := _material(Color(0.3, 0.85, 0.92), 0.25, 0.12)
	crystal.emission_enabled = true
	crystal.emission = Color(0.2, 0.75, 0.9)
	crystal.emission_energy_multiplier = 0.5
	for i in 3:
		var shard := CylinderMesh.new()
		shard.top_radius = 0.0
		shard.bottom_radius = 0.16
		shard.height = 0.45
		shard.radial_segments = 5
		var instance := MeshInstance3D.new()
		instance.mesh = shard
		instance.material_override = crystal
		instance.position = Vector3(-0.25 + i * 0.25, 1.3, 0.55)
		instance.rotation.z = (i - 1) * 0.4
		_load.add_child(instance)
	var headlight := SpotLight3D.new()
	headlight.light_color = Color(0.95, 0.95, 1.0)
	headlight.spot_range = 10.0
	headlight.spot_angle = 32.0
	headlight.light_energy = 1.4
	headlight.position = Vector3(0, 1.0, -1.0)
	headlight.rotation.x = -0.25
	add_child(headlight)
	var lens := _material(Color(1.0, 1.0, 0.95), 0.0, 0.2)
	lens.emission_enabled = true
	lens.emission = Color(1.0, 1.0, 0.9)
	lens.emission_energy_multiplier = 3.0
	for side in [-0.4, 0.4]:
		_add_box(Vector3(0.18, 0.1, 0.04), lens, Vector3(side, 0.95, -0.97))


func _add_box(size: Vector3, material: Material, pos: Vector3) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = box
	instance.material_override = material
	instance.position = pos
	add_child(instance)
	return instance


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material
