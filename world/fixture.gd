class_name Fixture
extends StaticBody3D
## Anything standing on the rock: the drop pod, ore, and what you build.
## Stood upright along the surface normal it was placed on.

const LAYER := 2
const COST := {&"lamp": 1, &"panel": 2}
const LAMP_RANGE := 13.0

var kind: StringName
var normal := Vector3.UP
## Kept up to date by the game: whether the sun reaches it, and for lamps,
## whether they're lit.
var sunlit := false
var on := false
var amount := 3

var light: OmniLight3D
var _bulb: StandardMaterial3D
var _beacon: OmniLight3D
var _beacon_bulb: StandardMaterial3D


static func make(fixture_kind: StringName, pos: Vector3, surface_normal: Vector3) -> Fixture:
	var fixture := Fixture.new()
	fixture.kind = fixture_kind
	fixture.normal = surface_normal
	fixture.transform = Transform3D(upright(surface_normal), pos)
	return fixture


## A basis whose y is up, turned about it arbitrarily.
static func upright(up: Vector3) -> Basis:
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	return Basis(x, up, x.cross(up))


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	match kind:
		&"pod": _build_pod()
		&"lamp": _build_lamp()
		&"panel": _build_panel()
		&"ore": _build_ore()


func set_on(value: bool) -> void:
	on = value
	light.visible = on
	_bulb.emission_energy_multiplier = 6.0 if on else 0.0


func _process(_delta: float) -> void:
	if _beacon:
		var blink := fmod(Time.get_ticks_msec() / 1000.0, 1.6) < 0.25
		_beacon.visible = blink
		_beacon_bulb.emission_energy_multiplier = 8.0 if blink else 0.3


func _build_pod() -> void:
	var hull := _material(Color(0.78, 0.76, 0.72), 0.45, 0.5)
	_add_mesh(_cylinder(1.25, 1.65, 3.0), hull, Vector3(0, 1.3, 0))
	_add_mesh(_cylinder(0.35, 1.25, 1.2), hull, Vector3(0, 3.4, 0))
	var stripe := _material(Color(1.0, 0.55, 0.15), 0.2, 0.4)
	stripe.emission_enabled = true
	stripe.emission = Color(1.0, 0.5, 0.1)
	stripe.emission_energy_multiplier = 1.5
	var torus := TorusMesh.new()
	torus.inner_radius = 1.5
	torus.outer_radius = 1.62
	_add_mesh(torus, stripe, Vector3(0, 1.0, 0))
	var cells := _material(Color(0.08, 0.12, 0.3), 0.6, 0.2)
	for side in [-1.0, 1.0]:
		var box := BoxMesh.new()
		box.size = Vector3(0.06, 1.6, 1.0)
		_add_mesh(box, cells, Vector3(side * 1.55, 2.0, 0)).rotation.z = side * 0.12
	for i in 3:
		var leg := BoxMesh.new()
		leg.size = Vector3(0.15, 1.6, 0.15)
		var angle := TAU * i / 3.0
		var foot := _add_mesh(leg, hull, Vector3(cos(angle) * 1.7, 0.3, sin(angle) * 1.7))
		foot.rotation = Vector3(sin(angle) * 0.5, 0, -cos(angle) * 0.5)
	_beacon_bulb = _material(Color(1.0, 0.2, 0.15), 0.3, 0.3)
	_beacon_bulb.emission_enabled = true
	_beacon_bulb.emission = Color(1.0, 0.15, 0.1)
	var bulb := SphereMesh.new()
	bulb.radius = 0.16
	bulb.height = 0.32
	_add_mesh(bulb, _beacon_bulb, Vector3(0, 4.1, 0))
	_beacon = OmniLight3D.new()
	_beacon.light_color = Color(1.0, 0.2, 0.1)
	_beacon.omni_range = 9.0
	_beacon.light_energy = 1.5
	_beacon.position = Vector3(0, 4.3, 0)
	add_child(_beacon)
	var shape := CylinderShape3D.new()
	shape.radius = 1.6
	shape.height = 4.0
	_add_collider(shape, Vector3(0, 1.9, 0))


func _build_lamp() -> void:
	var metal := _material(Color(0.5, 0.5, 0.52), 0.7, 0.4)
	var base := BoxMesh.new()
	base.size = Vector3(0.45, 0.12, 0.45)
	_add_mesh(base, metal, Vector3(0, 0.06, 0))
	# The post and bulb sit right under the light: they'd shadow everything
	# round the lamp.
	_add_mesh(_cylinder(0.04, 0.05, 1.4), metal, Vector3(0, 0.75, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bulb = _material(Color(1.0, 0.85, 0.6), 0.0, 0.3)
	_bulb.emission_enabled = true
	_bulb.emission = Color(1.0, 0.75, 0.45)
	var bulb := SphereMesh.new()
	bulb.radius = 0.14
	bulb.height = 0.28
	_add_mesh(bulb, _bulb, Vector3(0, 1.5, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.78, 0.5)
	light.omni_range = LAMP_RANGE
	light.light_energy = 2.2
	light.shadow_enabled = true
	light.position = Vector3(0, 1.75, 0)
	add_child(light)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.45, 1.6, 0.45)
	_add_collider(shape, Vector3(0, 0.8, 0))
	set_on(false)


func _build_panel() -> void:
	var metal := _material(Color(0.5, 0.5, 0.52), 0.7, 0.4)
	_add_mesh(_cylinder(0.04, 0.05, 0.6), metal, Vector3(0, 0.3, 0))
	var cells := _material(Color(0.06, 0.1, 0.32), 0.6, 0.18)
	var face := BoxMesh.new()
	face.size = Vector3(1.6, 0.05, 1.0)
	_add_mesh(face, cells, Vector3(0, 0.65, 0))
	var frame := BoxMesh.new()
	frame.size = Vector3(1.7, 0.03, 1.1)
	_add_mesh(frame, metal, Vector3(0, 0.62, 0))
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.7, 0.75, 1.1)
	_add_collider(shape, Vector3(0, 0.38, 0))


func _build_ore() -> void:
	var crystal := _material(Color(0.3, 0.85, 0.92), 0.25, 0.12)
	crystal.emission_enabled = true
	crystal.emission = Color(0.2, 0.75, 0.9)
	crystal.emission_energy_multiplier = 0.12
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(position)
	for i in 5:
		var height := rng.randf_range(0.6, 1.4)
		var mesh := _cylinder(0.0, rng.randf_range(0.14, 0.28), height)
		mesh.radial_segments = 5
		var offset := Vector3(rng.randf_range(-0.35, 0.35), height * 0.4, rng.randf_range(-0.35, 0.35))
		var shard := _add_mesh(mesh, crystal, offset)
		shard.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0, TAU), rng.randf_range(-0.5, 0.5))
	var shape := SphereShape3D.new()
	shape.radius = 0.75
	_add_collider(shape, Vector3(0, 0.45, 0))


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	return mesh


func _add_mesh(mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	add_child(instance)
	return instance


func _add_collider(shape: Shape3D, pos: Vector3) -> void:
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = pos
	add_child(collider)
