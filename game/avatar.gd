class_name Avatar
extends Node3D
## Another soldier, as seen by everyone else: a suit with a helmet and a
## name over it, eased towards wherever their game last said they were.

var peer := 0
var pitch := 0.0
var target_position := Vector3.ZERO
var target_yaw := 0.0

var _label: Label3D
var _head: Node3D
var _name := ""
## Lying where they fell, waiting for someone to revive them.
var down := false


func _ready() -> void:
	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.9, 0.9, 0.88)
	suit.roughness = 0.6
	var visor := StandardMaterial3D.new()
	visor.albedo_color = Color(1.0, 0.55, 0.15)
	visor.metallic = 0.8
	visor.roughness = 0.15
	visor.emission_enabled = true
	visor.emission = Color(1.0, 0.45, 0.1)
	visor.emission_energy_multiplier = 0.6
	var body := CapsuleMesh.new()
	body.radius = 0.35
	body.height = 1.3
	_add(body, suit, Vector3(0, 0.75, 0), self)
	var pack := BoxMesh.new()
	pack.size = Vector3(0.5, 0.6, 0.25)
	_add(pack, suit, Vector3(0, 1.0, 0.3), self)
	_head = Node3D.new()
	_head.position.y = 1.55
	add_child(_head)
	var helmet := SphereMesh.new()
	helmet.radius = 0.24
	helmet.height = 0.48
	_add(helmet, suit, Vector3.ZERO, _head)
	var glass := BoxMesh.new()
	glass.size = Vector3(0.32, 0.14, 0.1)
	_add(glass, visor, Vector3(0, 0.02, -0.2), _head)
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(0.85, 0.92, 1.0)
	lamp.spot_range = 11.0
	lamp.spot_angle = 20.0
	lamp.light_energy = 1.6
	lamp.position = Vector3(0.15, 0.0, -0.25)
	_head.add_child(lamp)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 40
	_label.pixel_size = 0.0007
	_label.fixed_size = true
	_label.outline_size = 8
	_label.position = Vector3(0, 2.1, 0)
	add_child(_label)
	target_position = global_position


func set_label(text: String) -> void:
	_name = text
	_label.text = text


func set_down(on: bool) -> void:
	if on == down:
		return
	down = on
	rotation.z = PI * 0.5 if on else 0.0
	_label.text = "%s\nDOWN: hold E" % _name if on else _name
	_label.modulate = Color(1.0, 0.45, 0.35) if on else Color.WHITE


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-14.0 * delta)
	global_position = global_position.lerp(target_position, blend)
	rotation.y = lerp_angle(rotation.y, target_yaw, blend)
	_head.rotation.x = lerp_angle(_head.rotation.x, pitch, blend)


func _add(mesh: Mesh, material: Material, pos: Vector3, parent: Node3D) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	parent.add_child(instance)
