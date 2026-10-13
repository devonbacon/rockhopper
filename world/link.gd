class_name Link
extends Node3D
## A cable strung from one pylon, rig, foundry or the pod to another,
## carrying ore and alloy one way along it, spaced out, at walking pace.
## What reaches the far end waits there till it's taken in. Soldiers can
## ride it either way, hanging underneath. The commander lays them as
## blueprints, a line of hologram, that take a soldier's hammer blow to
## string up.

const RANGE := 20.0
const SPEED := 3.0
const GAP := 1.5
## A rider's feet hang this far under the cable.
const HANG := 2.2
const ORE := Color(0.3, 0.85, 0.92)
const ALLOY := Color(1.0, 0.6, 0.2)
const PLAN := Color(0.45, 0.8, 1.0)

var net_id := 0
var from: Fixture
var to: Fixture
## On the way: [kind, metres along], furthest first.
var items: Array = []
var blueprint := false

var _cable: MeshInstance3D
var _material: StandardMaterial3D
var _plan_material: StandardMaterial3D
var _crates: Array[MeshInstance3D] = []
var _ore_material: StandardMaterial3D
var _alloy_material: StandardMaterial3D
## Lit up while the commander's mouse is on it.
var highlight := false


static func make(a: Fixture, b: Fixture) -> Link:
	var link := Link.new()
	link.from = a
	link.to = b
	return link


func _ready() -> void:
	top_level = true
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.15, 0.15, 0.17)
	_material.metallic = 0.6
	_material.roughness = 0.4
	_material.emission_enabled = true
	_material.emission = Color.BLACK
	_plan_material = StandardMaterial3D.new()
	_plan_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_plan_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.035
	mesh.bottom_radius = 0.035
	mesh.height = 1.0
	mesh.radial_segments = 6
	_cable = MeshInstance3D.new()
	_cable.mesh = mesh
	_cable.material_override = _material
	_cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cable)
	_ore_material = _glow(ORE)
	_alloy_material = _glow(ALLOY)


func start() -> Vector3:
	return from.cable_point()


func end() -> Vector3:
	return to.cable_point()


func length() -> float:
	return start().distance_to(end())


## Whether a new item can go on at the start.
func has_room() -> bool:
	return items.is_empty() or items[-1][1] >= GAP


## Moves everything along, each stopping short of the one ahead, and the
## first at the end.
func advance(delta: float, speed: float) -> void:
	var stop := length()
	for item: Array in items:
		item[1] = minf(item[1] + speed * delta, stop)
		stop = item[1] - GAP


## The point on the cable nearest a ray, and how far along: [distance from
## the ray, metres along, metres out along the ray].
func nearest_to_ray(origin: Vector3, dir: Vector3) -> Array:
	var a := start()
	var along := end() - a
	var span := along.length()
	along /= span
	var w := origin - a
	var b := along.dot(dir)
	var d := along.dot(w)
	var e := dir.dot(w)
	var denom := 1.0 - b * b
	var s := clampf((d - b * e) / denom, 0.0, span) if denom > 0.0001 else 0.0
	var t := maxf(0.0, s * b - e)
	var gap := (a + along * s).distance_to(origin + dir * t)
	return [gap, s, t]


func _process(_delta: float) -> void:
	if !is_instance_valid(from) or !is_instance_valid(to):
		return
	var a := start()
	var b := end()
	var span := a.distance_to(b)
	if span < 0.01:
		return
	var along := (b - a) / span
	var side := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
	_cable.global_transform = Transform3D(Basis(side, along * span, side.cross(along)), (a + b) * 0.5)
	_material.emission = PLAN * (1.5 if highlight else 0.0)
	_cable.material_override = _plan_material if blueprint else _material
	_plan_material.albedo_color = Color(PLAN, 0.9 if highlight else 0.35 + 0.2 * sin(Time.get_ticks_msec() * 0.006))
	while _crates.size() < items.size():
		var crate := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.28, 0.28, 0.28)
		crate.mesh = box
		add_child(crate)
		_crates.push_back(crate)
	for i in _crates.size():
		var crate := _crates[i]
		crate.visible = i < items.size()
		if crate.visible:
			crate.material_override = _ore_material if items[i][0] == &"ore" else _alloy_material
			crate.global_position = a + along * minf(items[i][1], span) - Vector3.UP * 0.25


func _glow(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	return material
