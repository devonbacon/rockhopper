class_name RangeRing
extends MeshInstance3D
## A glowing band laid over the ground in a circle: how far a cable reaches
## from something.

const SEGMENTS := 96
const LIFT := 0.15

var _centre := Vector3.INF
var _radius := 0.0
var _width := 0.0
var _material := StandardMaterial3D.new()


func _ready() -> void:
	top_level = true
	visible = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = ImmediateMesh.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = false
	material_override = _material


## Shows the ring round centre, in color; it's only re-laid over the
## ground when it moves.
func show_around(centre: Vector3, radius: float, color: Color, width := 0.3) -> void:
	visible = true
	_material.albedo_color = color
	if centre.distance_to(_centre) < 0.05 and radius == _radius and width == _width:
		return
	_centre = centre
	_radius = radius
	_width = width
	var space := get_world_3d().direct_space_state
	var band := mesh as ImmediateMesh
	band.clear_surfaces()
	band.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in SEGMENTS + 1:
		var out := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / SEGMENTS)
		for edge in [radius - width, radius + width]:
			var at: Vector3 = centre + out * edge
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, Terrain.TOP + 20.0, at.z), Vector3(at.x, Terrain.BOTTOM, at.z), Terrain.ROCK_LAYER))
			band.surface_add_vertex((hit.position if !hit.is_empty() else at) + Vector3.UP * LIFT)
	band.surface_end()


func hide_ring() -> void:
	visible = false
