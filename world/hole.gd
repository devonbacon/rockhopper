class_name Hole
extends Node3D
## A bug hole: torn open in the ground at nightfall, where the spiders come
## up from, and closed again at sunrise.

const RADIUS := 1.6

var net_id := 0
var normal := Vector3.UP

var _glow: OmniLight3D
var _age := 0.0


func _ready() -> void:
	basis = Fixture.upright(normal)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS * 0.8
	torus.outer_radius = RADIUS * 1.35
	rim.mesh = torus
	rim.scale = Vector3(1, 0.45, 1)
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.22, 0.2, 0.19)
	rock.roughness = 1.0
	rim.material_override = rock
	add_child(rim)
	var pit := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS
	disc.bottom_radius = RADIUS * 0.6
	disc.height = 0.3
	pit.mesh = disc
	pit.position.y = -0.1
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color.BLACK
	dark.emission_enabled = true
	dark.emission = Color(1.0, 0.12, 0.05)
	dark.emission_energy_multiplier = 2.0
	pit.material_override = dark
	add_child(pit)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.25, 0.15)
	_glow.omni_range = 14.0
	_glow.position.y = 1.5
	add_child(_glow)


func _process(delta: float) -> void:
	_age += delta
	_glow.light_energy = 2.2 + 0.8 * sin(_age * 2.3)
