class_name Fixture
extends StaticBody3D
## Anything standing on the rock: the drop pod, ore, deposits, and what you
## build. Stood upright along the surface normal it was placed on.
##
## Ore is a small cluster, gone once mined. A deposit is a big outcrop
## that never runs out: you can chip at it by hand, or build a drill rig
## over it. A rig drills while it's lit, by the sun or a lamp, into a
## hopper that rovers come and empty, or you can by hand.

const LAYER := 2
const COST := {&"lamp": 1, &"panel": 2, &"drill": 3, &"rover": 4}
const HEALTH := 30.0
const DRILL_EVERY := 6.0
const HOPPER := 12
const LAMP_RANGE := 13.0

var kind: StringName
var normal := Vector3.UP
## Kept up to date by the game: whether the sun reaches it, and for lamps,
## whether they're lit.
var sunlit := false
var on := false
var amount := 3
## Lamps, panels and rigs: spiders wear this down.
var health := HEALTH
## A deposit's rig, and a rig's deposit.
var rig: Fixture
var deposit: Fixture
## Rigs: ore in the hopper, progress towards the next, and why it isn't
## drilling: "" if it is, "dark" or "full".
var stored := 0
var drilled := 0.0
var stalled := ""

var light: OmniLight3D
## The pod's screen.
var screen: PodScreen
var _bulb: StandardMaterial3D
var _beacon: OmniLight3D
var _beacon_bulb: StandardMaterial3D
var _shaft: Node3D
var _status: StandardMaterial3D
var _fill: MeshInstance3D


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
		&"deposit": _build_deposit()
		&"drill": _build_drill()


func set_on(value: bool) -> void:
	on = value
	light.visible = on
	_bulb.emission_energy_multiplier = 6.0 if on else 0.0


## Rigs: drills for delta seconds if it's lit and has room, given whether
## it's lit.
func drill(delta: float, lit: bool) -> void:
	stalled = "full" if stored >= HOPPER else ("dark" if !lit else "")
	if stalled != "":
		return
	drilled += delta
	if drilled >= DRILL_EVERY:
		drilled -= DRILL_EVERY
		stored += 1


## Rigs: empties up to amount from the hopper, returning what it gave.
func take(amount: int) -> int:
	var given := mini(amount, stored)
	stored -= given
	return given


func _process(delta: float) -> void:
	if _shaft:
		if stalled == "":
			_shaft.rotate_object_local(Vector3.UP, delta * 9.0)
		var color := Color(0.3, 1.0, 0.4) if stalled == "" else (Color(0.4, 0.7, 1.0) if stalled == "dark" else Color(1.0, 0.7, 0.2))
		_status.albedo_color = color
		_status.emission = color
		_fill.scale.y = maxf(0.02, stored / float(HOPPER))
		_fill.position.y = 3.05 + 0.28 * _fill.scale.y
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
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 1.6, 1.0)
	_add_mesh(box, cells, Vector3(-1.55, 2.0, 0)).rotation.z = -0.12
	# The screen faces out of the +x side, leaning back with the hull.
	var lean := atan2(0.4, 3.0)
	var out := Vector3(cos(lean), sin(lean), 0.0)
	var up := Vector3(-sin(lean), cos(lean), 0.0)
	var screen_basis := Basis(up.cross(out), up, out)
	var frame := BoxMesh.new()
	frame.size = Vector3(PodScreen.SIZE.x + 0.12, PodScreen.SIZE.y + 0.12, 0.06)
	_add_mesh(frame, _material(Color(0.2, 0.21, 0.24), 0.6, 0.4), Vector3(1.34, 2.1, 0)).basis = screen_basis
	screen = PodScreen.new()
	screen.transform = Transform3D(screen_basis, Vector3(1.34, 2.1, 0) + out * 0.035)
	add_child(screen)
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


func _build_deposit() -> void:
	var crystal := _material(Color(0.3, 0.85, 0.92), 0.25, 0.12)
	crystal.emission_enabled = true
	crystal.emission = Color(0.2, 0.75, 0.9)
	crystal.emission_energy_multiplier = 0.15
	var rock := _material(Color(0.32, 0.3, 0.28), 0.0, 0.95)
	var base := SphereMesh.new()
	base.radius = 1.7
	base.height = 1.6
	_add_mesh(base, rock, Vector3(0, 0.1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(position)
	for i in 9:
		var height := rng.randf_range(1.4, 3.2)
		var mesh := _cylinder(0.0, rng.randf_range(0.3, 0.6), height)
		mesh.radial_segments = 6
		var angle := TAU * i / 9.0 + rng.randf_range(-0.3, 0.3)
		var out := rng.randf_range(0.2, 1.1)
		var shard := _add_mesh(mesh, crystal, Vector3(cos(angle) * out, height * 0.4 + 0.3, sin(angle) * out))
		shard.rotation = Vector3(sin(angle) * out * 0.5, rng.randf_range(0, TAU), -cos(angle) * out * 0.5)
	var shape := SphereShape3D.new()
	shape.radius = 1.6
	_add_collider(shape, Vector3(0, 0.9, 0))


## A tripod over the deposit, a spinning drill down its middle, and a
## hopper up top with a gauge, in white, gold foil and orange.
func _build_drill() -> void:
	health = 40.0
	var white := _material(Color(0.88, 0.88, 0.86), 0.3, 0.45)
	var gold := _material(Color(0.85, 0.62, 0.22), 0.9, 0.3)
	var orange := _material(Color(1.0, 0.45, 0.1), 0.1, 0.5)
	for i in 3:
		var angle := TAU * i / 3.0
		var foot := Vector3(cos(angle) * 2.4, 0.0, sin(angle) * 2.4)
		var top := Vector3(0, 3.2, 0)
		var leg := BoxMesh.new()
		leg.size = Vector3(0.14, foot.distance_to(top), 0.14)
		var along := (top - foot).normalized()
		var side := along.cross(Vector3.FORWARD if absf(along.z) < 0.9 else Vector3.RIGHT).normalized()
		var instance := _add_mesh(leg, white, (foot + top) * 0.5)
		instance.basis = Basis(side, along, side.cross(along))
		var pad := BoxMesh.new()
		pad.size = Vector3(0.45, 0.1, 0.45)
		_add_mesh(pad, orange, foot + Vector3(0, 0.05, 0))
	_shaft = Node3D.new()
	_shaft.position = Vector3(0, 1.6, 0)
	add_child(_shaft)
	var bit := _cylinder(0.12, 0.12, 2.6)
	var shaft_mesh := MeshInstance3D.new()
	shaft_mesh.mesh = bit
	shaft_mesh.material_override = _material(Color(0.4, 0.4, 0.42), 0.8, 0.3)
	_shaft.add_child(shaft_mesh)
	var flight := BoxMesh.new()
	flight.size = Vector3(0.5, 0.06, 0.08)
	for i in 4:
		var blade := MeshInstance3D.new()
		blade.mesh = flight
		blade.material_override = orange
		blade.position = Vector3(0, -0.9 + i * 0.5, 0)
		blade.rotation.y = i * 0.8
		_shaft.add_child(blade)
	var hopper := BoxMesh.new()
	hopper.size = Vector3(1.3, 0.75, 1.3)
	_add_mesh(hopper, gold, Vector3(0, 3.4, 0))
	var gauge := BoxMesh.new()
	gauge.size = Vector3(0.18, 0.56, 0.05)
	var gauge_back := _material(Color(0.05, 0.05, 0.06), 0.0, 0.8)
	_add_mesh(gauge, gauge_back, Vector3(0, 3.33, 0.67))
	var fill_material := _material(Color(0.3, 0.85, 0.92), 0.0, 0.3)
	fill_material.emission_enabled = true
	fill_material.emission = Color(0.2, 0.75, 0.9)
	fill_material.emission_energy_multiplier = 2.0
	var fill := BoxMesh.new()
	fill.size = Vector3(0.12, 0.56, 0.06)
	_fill = _add_mesh(fill, fill_material, Vector3(0, 3.05, 0.68))
	_status = _material(Color(0.3, 1.0, 0.4), 0.0, 0.3)
	_status.emission_enabled = true
	_status.emission_energy_multiplier = 4.0
	var bulb := SphereMesh.new()
	bulb.radius = 0.1
	bulb.height = 0.2
	_add_mesh(bulb, _status, Vector3(0, 3.9, 0))
	var shape := CylinderShape3D.new()
	shape.radius = 1.0
	shape.height = 4.0
	_add_collider(shape, Vector3(0, 2.0, 0))


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
