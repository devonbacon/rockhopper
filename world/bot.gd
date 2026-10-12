class_name Bot
extends Node3D
## A mining drone. It waits round the pod until a deposit's marked, flies
## out to whichever marked deposit has the fewest bots on it, mines while
## the deposit's lit, and flies the ore home two at a time.
##
## It flies over the rock at a set height, never through it. It won't
## fight: a spider that can reach it while it's working will wear it down,
## and a bot that's destroyed is gone with what it carried. Round the pod's
## top it's out of reach.

enum Task { DOCKED, OUTBOUND, MINING, HOMEBOUND }

const SPEED := 8.0
const CLIMB := 5.0
## How high it flies over the rock between places.
const CRUISE := 4.0
const MINE_TIME := 6.0
const LOAD := 2
const HEALTH := 30.0

var game: Game
var task := Task.DOCKED
var deposit: Fixture
var cargo := 0
var health := HEALTH
## Whether it's at its deposit but can't mine for the dark.
var dark := false
## Which place round the pod (and round a deposit) is its own.
var slot := 0

var _mined := 0.0
var _beam: MeshInstance3D
var _beam_material: StandardMaterial3D
var _hull_material: StandardMaterial3D
var _flash := 0.0
var _bob := 0.0


func _ready() -> void:
	_hull_material = StandardMaterial3D.new()
	_hull_material.albedo_color = Color(0.85, 0.86, 0.88)
	_hull_material.metallic = 0.5
	_hull_material.roughness = 0.35
	var body := SphereMesh.new()
	body.radius = 0.3
	body.height = 0.45
	_add_mesh(body, _hull_material, Vector3.ZERO)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.38
	ring.outer_radius = 0.46
	var dark_metal := StandardMaterial3D.new()
	dark_metal.albedo_color = Color(0.25, 0.26, 0.3)
	dark_metal.metallic = 0.6
	_add_mesh(ring, dark_metal, Vector3.ZERO)
	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = Color(0.4, 0.95, 1.0)
	eye_material.emission_enabled = true
	eye_material.emission = Color(0.3, 0.9, 1.0)
	eye_material.emission_energy_multiplier = 4.0
	var eye := SphereMesh.new()
	eye.radius = 0.08
	eye.height = 0.16
	_add_mesh(eye, eye_material, Vector3(0, 0, -0.27))
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.9, 1.0)
	light.omni_range = 3.5
	light.light_energy = 0.5
	add_child(light)
	_beam_material = StandardMaterial3D.new()
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.albedo_color = Color(0.5, 1.0, 1.0)
	_beam_material.emission_enabled = true
	_beam_material.emission = Color(0.4, 1.0, 1.0)
	_beam_material.emission_energy_multiplier = 4.0
	var beam := CylinderMesh.new()
	beam.top_radius = 0.035
	beam.bottom_radius = 0.035
	beam.height = 1.0
	_beam = MeshInstance3D.new()
	_beam.mesh = beam
	_beam.material_override = _beam_material
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	_beam.visible = false
	add_child(_beam)


func _physics_process(delta: float) -> void:
	_bob += delta
	_flash = maxf(0.0, _flash - delta * 4.0)
	_hull_material.emission_enabled = _flash > 0.0
	_hull_material.emission = Color(1.0, 0.3, 0.2) * _flash
	dark = false
	match task:
		Task.DOCKED:
			_fly_to(_dock_point(), delta)
			deposit = game.pick_deposit()
			if deposit:
				task = Task.OUTBOUND
		Task.OUTBOUND:
			if !_wanted():
				task = Task.HOMEBOUND
			elif _fly_to(_work_point(), delta):
				task = Task.MINING
				_mined = 0.0
		Task.MINING:
			if !_wanted():
				task = Task.HOMEBOUND
			else:
				_fly_to(_work_point() + global_position.normalized() * sin(_bob * 2.0) * 0.1, delta)
				dark = game.lit_at(deposit.work_point()) == ""
				if !dark:
					_mined += delta
					if _mined >= MINE_TIME:
						cargo = LOAD
						task = Task.HOMEBOUND
		Task.HOMEBOUND:
			if _fly_to(_dock_point(), delta):
				game.deliver(cargo)
				cargo = 0
				task = Task.DOCKED
	_aim_beam()


## Whether it's somewhere a spider could get at it.
func exposed() -> bool:
	return task == Task.MINING or (task != Task.DOCKED and global_position.distance_to(game.pod.global_position) > 8.0)


func damage(amount: float) -> void:
	health -= amount
	_flash = 1.0


func _wanted() -> bool:
	return is_instance_valid(deposit) and deposit.designated


func _dock_point() -> Vector3:
	var angle := slot * 2.4
	return game.pod.global_position + game.pod.normal * 5.2 + Fixture.upright(game.pod.normal) * Vector3(cos(angle) * 2.2, 0.0, sin(angle) * 2.2)


func _work_point() -> Vector3:
	var angle := slot * 2.4
	return deposit.work_point() + Fixture.upright(deposit.normal) * Vector3(cos(angle) * 1.2, 0.0, sin(angle) * 1.2)


## Flies a step towards target, over the rock at cruise height until it's
## close, then straight in. Returns whether it's there.
func _fly_to(target: Vector3, delta: float) -> bool:
	var pos := global_position
	var r := pos.length()
	var dir := pos / r
	var target_dir := target.normalized()
	var angle := dir.angle_to(target_dir)
	var arc := angle * r
	var new_dir := target_dir
	if arc > 0.001:
		new_dir = dir.slerp(target_dir, minf(1.0, SPEED * delta / arc))
	var ground := game.ground_radius(new_dir)
	var want_r := target.length()
	if arc > 6.0:
		want_r = maxf(ground + CRUISE, want_r)
	r = maxf(move_toward(r, want_r, CLIMB * delta), ground + 1.0)
	var moved := new_dir * r - pos
	global_position = new_dir * r
	var flat := moved - new_dir * moved.dot(new_dir)
	if flat.length() > 0.001:
		global_basis = global_basis.slerp(Basis.looking_at(flat.normalized(), new_dir), minf(1.0, delta * 6.0))
	return global_position.distance_to(target) < 0.3


func _aim_beam() -> void:
	_beam.visible = task == Task.MINING and !dark and _wanted()
	if !_beam.visible:
		return
	var from := global_position
	var to := deposit.global_position + deposit.normal * 1.2
	var length := from.distance_to(to)
	var along := (to - from) / length
	var side := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
	_beam.global_transform = Transform3D(Basis(side, along * length, side.cross(along)), (from + to) * 0.5)
	_beam_material.emission_energy_multiplier = 3.0 + sin(_bob * 40.0) * 1.5


func _add_mesh(mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	add_child(instance)
	return instance
