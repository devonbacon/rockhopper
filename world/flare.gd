class_name Flare
extends Node3D
## A thrown flare: it arcs, lands, and burns for a while, lighting and
## warming what's round it and keeping spiders from climbing out near it.

const LIFE := 35.0
const RANGE := 11.0
const SPEED := 13.0
const GRAVITY := 5.0
const FADE := 5.0

var game: Game
var net_id := 0
## On clients: eased to where the server says.
var puppet := false
var target_position := Vector3.ZERO
var velocity := Vector3.ZERO
var life := LIFE
var landed := false
var light: OmniLight3D

var _glow: StandardMaterial3D
var _flicker := 0.0


func _ready() -> void:
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = Color(1.0, 0.45, 0.2)
	_glow.emission_enabled = true
	_glow.emission = Color(1.0, 0.4, 0.15)
	_glow.emission_energy_multiplier = 6.0
	var stick := CylinderMesh.new()
	stick.top_radius = 0.04
	stick.bottom_radius = 0.04
	stick.height = 0.3
	var mesh := MeshInstance3D.new()
	mesh.mesh = stick
	mesh.material_override = _glow
	mesh.rotation.z = PI * 0.5
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.25)
	light.omni_range = RANGE
	light.light_energy = 2.4
	light.shadow_enabled = true
	light.position = Vector3(0, 0.35, 0)
	add_child(light)
	target_position = global_position


func _physics_process(delta: float) -> void:
	_burn(delta)
	if puppet:
		global_position = global_position.lerp(target_position, 1.0 - exp(-16.0 * delta))
		return
	life -= delta
	if life <= 0.0:
		game.remove_flare(self)
		return
	if landed:
		return
	velocity -= Terrain.up_at(global_position) * GRAVITY * delta
	var next := global_position + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next, Terrain.ROCK_LAYER | Fixture.LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = next
		rotate_y(delta * 9.0)
		if global_position.y < -60.0:
			game.remove_flare(self)
	else:
		global_position = hit.position + hit.normal * 0.06
		landed = true


func _burn(delta: float) -> void:
	_flicker = move_toward(_flicker, randf_range(-0.35, 0.35), delta * 6.0)
	var strength := clampf(life / FADE, 0.0, 1.0)
	light.light_energy = (2.4 + _flicker) * strength
	_glow.emission_energy_multiplier = 6.0 * strength
