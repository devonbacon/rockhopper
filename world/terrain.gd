class_name Terrain
extends Node3D
## The ground: a round playable area, marked by a blue hologram wall, of
## rolling hills, boulders, small craters, and a few caves under it. Past
## it the hills flatten out into a plain, ringed further off by mountains
## you can't reach, high in some directions and low in others, with one
## giant somewhere. They're solid to the sun, so they cast real shadows:
## dusk comes early under a range to the west. Down is -y everywhere.
##
## It's a signed distance field (negative inside rock), sampled on a grid
## and meshed once with surface nets into chunks, each with a trimesh
## collider. Nothing deforms it after that; the field is kept for placing
## things on it. The rock is also baked into a navigation mesh for rovers.

const CELL := 1.5
## Half the width of the sampled square, and how far down and up it goes.
const HALF := 84.0
const BOTTOM := -16.0
const TOP := 12.0
## The playable area's radius, where the hologram wall stands.
const FLOOR_RADIUS := 60.0
const WALL_HEIGHT := 12.0
const HILLS := 4.0
const CHUNK := 16
const ROCK_LAYER := 1
## The mountains: from the foothills to the far edge, in metres from the
## middle, and how tall the ranges and the one giant get.
const RANGE_NEAR := 110.0
const RANGE_FAR := 1300.0
const RANGE_HEIGHT := 150.0
const GIANT_HEIGHT := 320.0
## Features are bucketed by where they sit on the ground, this wide.
const BUCKET := 16.0

## Chambers: centre and radius. Worms: segments, as [a, b, radius].
var chambers: Array[Vector4] = []
var worms: Array[Array] = []
## Where ore and deposits can go: [position, normal] on open, flat-ish
## ground inside the floor, and on cave floors.
var surface_spots: Array[Array] = []
var cave_spots: Array[Array] = []
var triangle_count := 0
var generate_ms := 0
var navigation: NavigationRegion3D

var _shape := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
## Boulders (added rock) and craters (carved), as centre and radius, kept
## in buckets by ground position: Vector2i -> [boulders, craters].
var _buckets := {}
var _faces := PackedVector3Array()


## Which way is up at p. The ground's flat, so it's always +y; the rest of
## the game asks here rather than assuming.
static func up_at(_p: Vector3) -> Vector3:
	return Vector3.UP


func generate(seed_value: int, _landing_dir := Vector3.ZERO) -> void:
	var started := Time.get_ticks_msec()
	_rng.seed = seed_value
	_shape.seed = seed_value
	_shape.frequency = 0.022
	_shape.fractal_octaves = 3
	_add_features()
	var cells := Vector3i(ceili(2.0 * HALF / CELL), ceili((TOP - BOTTOM) / CELL), ceili(2.0 * HALF / CELL))
	var origin := Vector3(-HALF, BOTTOM, -HALF)
	var field := _sample(origin, cells)
	_mesh(field, origin, cells)
	_add_plain()
	_add_mountains(seed_value)
	_add_wall()
	_bake_navigation()
	generate_ms = Time.get_ticks_msec() - started


## The ground's height at x, z, before anything's added or carved.
func ground_height(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	return HILLS * _shape.get_noise_2d(x, z) * (1.0 - smoothstep(FLOOR_RADIUS + 4.0, HALF - 4.0, r))


## Signed distance to rock, roughly in metres: negative inside.
func density(p: Vector3) -> float:
	var d := p.y - ground_height(p.x, p.z)
	if d > 6.0:
		return d
	var bucket: Array = _buckets.get(_bucket_of(p), [[], []])
	for b: Vector4 in bucket[0]:
		d = minf(d, p.distance_to(Vector3(b.x, b.y, b.z)) - b.w)
	for c: Vector4 in bucket[1]:
		d = maxf(d, c.w - p.distance_to(Vector3(c.x, c.y, c.z)))
	return maxf(d, -carve(p))


## Distance to open space under the ground: chambers and the worms
## between them and up to the surface.
func carve(p: Vector3) -> float:
	var d := INF
	for c in chambers:
		d = minf(d, p.distance_to(Vector3(c.x, c.y, c.z)) - c.w)
	for w in worms:
		d = minf(d, _segment_distance(p, w[0], w[1]) - w[2])
	return d


## The first rock straight down from high above x, z, and its normal.
func surface_point(at: Vector3) -> Array:
	var p := Vector3(at.x, TOP, at.z)
	while p.y > BOTTOM and density(p) > 0.0:
		p.y -= 0.5
	var lo := p.y
	var hi := p.y + 0.5
	for i in 16:
		var mid := (lo + hi) * 0.5
		if density(Vector3(p.x, mid, p.z)) > 0.0:
			hi = mid
		else:
			lo = mid
	p.y = hi
	return [p, normal_at(p)]


func normal_at(p: Vector3) -> Vector3:
	var h := 0.25
	return Vector3(
		density(p + Vector3(h, 0, 0)) - density(p - Vector3(h, 0, 0)),
		density(p + Vector3(0, h, 0)) - density(p - Vector3(0, h, 0)),
		density(p + Vector3(0, 0, h)) - density(p - Vector3(0, 0, h))).normalized()


## How far a point is below the open ground over it (negative above it).
func depth(p: Vector3) -> float:
	return ground_height(p.x, p.z) - p.y


func _bucket_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / BUCKET), floori(p.z / BUCKET))


func _add_bucketed(feature: Vector4, which: int) -> void:
	var lo := _bucket_of(Vector3(feature.x - feature.w, 0, feature.z - feature.w))
	var hi := _bucket_of(Vector3(feature.x + feature.w, 0, feature.z + feature.w))
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var key := Vector2i(bx, bz)
			if !_buckets.has(key):
				_buckets[key] = [[], []]
			_buckets[key][which].push_back(feature)


func _add_features() -> void:
	chambers.clear()
	worms.clear()
	_buckets.clear()
	for i in 10:
		var at := _floor_point(FLOOR_RADIUS - 6.0)
		var r := _rng.randf_range(4.0, 9.0)
		var y := ground_height(at.x, at.y) + r * 0.6
		_add_bucketed(Vector4(at.x, y, at.y, r), 1)
	for i in 34:
		var at := _floor_point(FLOOR_RADIUS - 2.0)
		var r := _rng.randf_range(0.8, 3.0)
		var y := ground_height(at.x, at.y) + r * _rng.randf_range(-0.2, 0.5)
		_add_bucketed(Vector4(at.x, y, at.y, r), 0)
	var previous := Vector3.INF
	for i in 4:
		var at := _floor_point(FLOOR_RADIUS - 14.0)
		var r := _rng.randf_range(5.0, 7.0)
		var centre := Vector3(at.x, ground_height(at.x, at.y) - r - _rng.randf_range(3.0, 6.0), at.y)
		chambers.push_back(Vector4(centre.x, centre.y, centre.z, r))
		# A sloping tunnel up to the surface, so every chamber can be
		# reached on foot.
		var away := Vector2.from_angle(_rng.randf() * TAU) * 16.0
		var mouth := Vector3(centre.x + away.x, 0.0, centre.z + away.y)
		mouth.y = ground_height(mouth.x, mouth.z) + 2.0
		var bend := centre.lerp(mouth, 0.5) + Vector3(_rng.randf_range(-4, 4), -2.0, _rng.randf_range(-4, 4))
		var width := _rng.randf_range(2.2, 2.8)
		worms.push_back([centre, bend, width])
		worms.push_back([bend, mouth, width])
		if previous != Vector3.INF and previous.distance_to(centre) < 50.0:
			worms.push_back([previous, centre, _rng.randf_range(2.0, 2.4)])
		previous = centre


## A random point on the floor, within radius of the middle, as x, z.
func _floor_point(radius: float) -> Vector2:
	return Vector2.from_angle(_rng.randf() * TAU) * radius * sqrt(_rng.randf())


func _segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _sample(origin: Vector3, cells: Vector3i) -> PackedFloat32Array:
	var s := cells + Vector3i.ONE
	var field := PackedFloat32Array()
	field.resize(s.x * s.y * s.z)
	var i := 0
	for k in s.z:
		for j in s.y:
			for x in s.x:
				field[i] = density(origin + Vector3(x, j, k) * CELL)
				i += 1
	return field


## Surface nets: a vertex in every cell the surface crosses, at the mean of
## its edge crossings, and a quad across every crossed grid edge.
func _mesh(field: PackedFloat32Array, origin: Vector3, cells: Vector3i) -> void:
	var sx := cells.x + 1
	var sxy := sx * (cells.y + 1)
	var corner_offset: PackedInt32Array = [0, 1, sx, sx + 1, sxy, sxy + 1, sxy + sx, sxy + sx + 1]
	var corner_pos: Array[Vector3] = []
	for c in 8:
		corner_pos.push_back(Vector3(c & 1, (c >> 1) & 1, (c >> 2) & 1))
	var edges: Array[Vector2i] = []
	for c in 8:
		for bit in [1, 2, 4]:
			if c & bit == 0:
				edges.push_back(Vector2i(c, c | bit))
	var cx := cells.x
	var cxy := cells.x * cells.y
	var cell_vert := PackedInt32Array()
	cell_vert.resize(cells.x * cells.y * cells.z)
	cell_vert.fill(-1)
	var active := PackedInt32Array()
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var v := PackedFloat32Array()
	v.resize(8)
	for k in cells.z:
		for j in cells.y:
			for i in cells.x:
				var base := i + sx * j + sxy * k
				# Far from the surface, no corner of this cell can cross it.
				if absf(field[base]) > 7.5:
					continue
				var mask := 0
				for c in 8:
					v[c] = field[base + corner_offset[c]]
					if v[c] < 0.0:
						mask |= 1 << c
				if mask == 0 or mask == 255:
					continue
				var sum := Vector3.ZERO
				var count := 0
				for e in edges:
					var va := v[e.x]
					var vb := v[e.y]
					if (va < 0.0) != (vb < 0.0):
						sum += corner_pos[e.x].lerp(corner_pos[e.y], va / (va - vb))
						count += 1
				var gradient := Vector3(
					v[1] - v[0] + v[3] - v[2] + v[5] - v[4] + v[7] - v[6],
					v[2] - v[0] + v[3] - v[1] + v[6] - v[4] + v[7] - v[5],
					v[4] - v[0] + v[5] - v[1] + v[6] - v[2] + v[7] - v[3])
				var cell := i + cx * j + cxy * k
				cell_vert[cell] = positions.size()
				positions.push_back(origin + (Vector3(i, j, k) + sum / count) * CELL)
				normals.push_back(gradient.normalized())
				active.push_back(cell)
	var chunk_tris := {}
	for cell in active:
		var i := cell % cx
		var j := (cell / cx) % cells.y
		var k := cell / cxy
		var base := i + sx * j + sxy * k
		var d0 := field[base]
		var key := Vector3i(i / CHUNK, j / CHUNK, k / CHUNK)
		# The edges leaving this cell's low corner along x, y and z, each
		# shared by four cells, this one the highest.
		if j > 0 and k > 0 and (d0 < 0.0) != (field[base + 1] < 0.0):
			_quad(chunk_tris, key, positions, normals, [
				cell_vert[cell - cx - cxy], cell_vert[cell - cxy], cell_vert[cell], cell_vert[cell - cx]])
		if i > 0 and k > 0 and (d0 < 0.0) != (field[base + sx] < 0.0):
			_quad(chunk_tris, key, positions, normals, [
				cell_vert[cell - 1 - cxy], cell_vert[cell - cxy], cell_vert[cell], cell_vert[cell - 1]])
		if i > 0 and j > 0 and (d0 < 0.0) != (field[base + sxy] < 0.0):
			_quad(chunk_tris, key, positions, normals, [
				cell_vert[cell - 1 - cx], cell_vert[cell - cx], cell_vert[cell], cell_vert[cell - 1]])
	_build_chunks(chunk_tris, positions, normals)
	_find_spots(positions, normals)


## Adds a quad as two triangles, wound clockwise seen from the side its
## normals face, which is Godot's front.
func _quad(chunk_tris: Dictionary, key: Vector3i, positions: PackedVector3Array, normals: PackedVector3Array, q: Array) -> void:
	var a: int = q[0]
	var b: int = q[1]
	var c: int = q[2]
	var d: int = q[3]
	var facing := normals[a] + normals[b] + normals[c] + normals[d]
	if (positions[b] - positions[a]).cross(positions[c] - positions[a]).dot(facing) > 0.0:
		var t := b
		b = d
		d = t
	if !chunk_tris.has(key):
		chunk_tris[key] = []
	chunk_tris[key].append_array([a, b, c, a, c, d])


func _build_chunks(chunk_tris: Dictionary, positions: PackedVector3Array, normals: PackedVector3Array) -> void:
	var material := _rock_material()
	triangle_count = 0
	_faces.clear()
	for key: Vector3i in chunk_tris:
		var tris := PackedInt32Array(chunk_tris[key])
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		verts.resize(tris.size())
		norms.resize(tris.size())
		for n in tris.size():
			verts[n] = positions[tris[n]]
			norms[n] = normals[tris[n]]
		triangle_count += tris.size() / 3
		_faces.append_array(verts)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		add_child(instance)
		var body_node := StaticBody3D.new()
		body_node.collision_layer = ROCK_LAYER
		body_node.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(verts)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body_node.add_child(collider)
		add_child(body_node)


## Flat ground at height 0 from the edge of the sampled square out to the
## horizon, just under where the meshed ground flattens out to meet it.
func _add_plain() -> void:
	var far := 4000.0
	var near := HALF - 2.0
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	for rect: Rect2 in [Rect2(-far, -far, 2.0 * far, far - near), Rect2(-far, near, 2.0 * far, far - near), Rect2(-far, -near, far - near, 2.0 * near), Rect2(near, -near, far - near, 2.0 * near)]:
		var a := Vector3(rect.position.x, -0.02, rect.position.y)
		var b := Vector3(rect.end.x, -0.02, rect.position.y)
		var c := Vector3(rect.end.x, -0.02, rect.end.y)
		var d := Vector3(rect.position.x, -0.02, rect.end.y)
		for v in [a, b, c, a, c, d]:
			tool.add_vertex(v)
	var plain := MeshInstance3D.new()
	plain.mesh = tool.commit()
	plain.material_override = _rock_material()
	add_child(plain)


## A ring of ridged mountains on the plain, on a grid of rings spaced out
## further the further they are, with a collider so the sun's checks see
## them.
func _add_mountains(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7
	var ridges := FastNoiseLite.new()
	ridges.seed = seed_value + 1
	ridges.noise_type = FastNoiseLite.TYPE_PERLIN
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 5
	ridges.frequency = 0.0035
	var ranges := FastNoiseLite.new()
	ranges.seed = seed_value + 2
	ranges.frequency = 0.9
	var giant_angle := rng.randf() * TAU
	var giant := Vector2(cos(giant_angle), sin(giant_angle)) * rng.randf_range(320.0, 480.0)
	var giant_width := rng.randf_range(110.0, 160.0)
	var rings := 70
	var segments := 240
	var heights := PackedFloat32Array()
	var points := PackedVector3Array()
	for i in rings + 1:
		var r := RANGE_NEAR * pow(RANGE_FAR / RANGE_NEAR, i / float(rings))
		var rise := smoothstep(RANGE_NEAR, RANGE_NEAR + 160.0, r) * (1.0 - smoothstep(RANGE_FAR * 0.75, RANGE_FAR, r) * 0.6)
		for j in segments:
			var angle := TAU * j / segments
			var flat := Vector2(cos(angle), sin(angle)) * r
			# How high the range is this way round: some directions open,
			# some walled in.
			var tall := clampf(0.55 + 0.6 * ranges.get_noise_2d(cos(angle), sin(angle)), 0.1, 1.0)
			var ridge := clampf(0.5 + 0.5 * ridges.get_noise_2d(flat.x, flat.y), 0.0, 1.0)
			var h := RANGE_HEIGHT * tall * rise * ridge * ridge
			var peak := exp(-flat.distance_squared_to(giant) / (giant_width * giant_width))
			h += GIANT_HEIGHT * peak * (0.75 + 0.25 * ridge)
			points.push_back(Vector3(flat.x, h - 0.5 * (1.0 - rise), flat.y))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings:
		for j in segments:
			var a := i * segments + j
			var b := i * segments + (j + 1) % segments
			var c := a + segments
			var d := b + segments
			for k in [a, c, b, b, c, d]:
				tool.add_vertex(points[k])
	tool.generate_normals()
	var mesh := tool.commit()
	var mountains := MeshInstance3D.new()
	mountains.mesh = mesh
	var material := _rock_material()
	material.uv1_scale = Vector3.ONE * 0.012
	material.albedo_color = Color(0.5, 0.46, 0.42)
	mountains.material_override = material
	add_child(mountains)
	var body := StaticBody3D.new()
	body.collision_layer = ROCK_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)


## The edge of the playable area: a hologram wall, brighter as you near it.
func _add_wall() -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = FLOOR_RADIUS
	cylinder.bottom_radius = FLOOR_RADIUS
	cylinder.height = WALL_HEIGHT + 8.0
	cylinder.radial_segments = 128
	cylinder.rings = 1
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	var material := ShaderMaterial.new()
	material.shader = load("res://world/boundary.gdshader")
	material.set_shader_parameter("radius", FLOOR_RADIUS)
	var wall := MeshInstance3D.new()
	wall.mesh = cylinder
	wall.material_override = material
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.position.y = WALL_HEIGHT * 0.5 - 4.0
	add_child(wall)


## Bakes where a rover can drive: gentle slopes inside the wall, round
## boulders and out of the caves' mouths where it's too steep.
func _bake_navigation() -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_radius = 1.0
	nav_mesh.agent_height = 1.5
	nav_mesh.agent_max_climb = 0.5
	nav_mesh.agent_max_slope = 28.0
	nav_mesh.filter_baking_aabb = AABB(Vector3(-FLOOR_RADIUS - 4, BOTTOM, -FLOOR_RADIUS - 4), Vector3(FLOOR_RADIUS * 2 + 8, TOP - BOTTOM, FLOOR_RADIUS * 2 + 8))
	var source := NavigationMeshSourceGeometryData3D.new()
	source.add_faces(_faces, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	navigation = NavigationRegion3D.new()
	navigation.navigation_mesh = nav_mesh
	add_child(navigation)
	if is_inside_tree():
		NavigationServer3D.map_force_update(get_world_3d().navigation_map)


## A path over the ground for a rover, from near `from` to as near `to` as
## it can get.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if !is_inside_tree():
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(get_world_3d().navigation_map, from, to, true)


## Picks out flat-ish open floor for ore and deposits, and cave floors.
func _find_spots(positions: PackedVector3Array, normals: PackedVector3Array) -> void:
	surface_spots.clear()
	cave_spots.clear()
	for n in positions.size():
		var p := positions[n]
		if normals[n].y < 0.8 or Vector2(p.x, p.z).length() > FLOOR_RADIUS - 5.0:
			continue
		if depth(p) > 3.0:
			cave_spots.push_back([p, normals[n]])
		elif normals[n].y > 0.9 and absf(depth(p)) < 1.0:
			surface_spots.push_back([p, normals[n]])


func _rock_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.46, 0.42, 0.38)
	material.roughness = 0.95
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * 0.08
	var grain := FastNoiseLite.new()
	grain.frequency = 0.02
	grain.fractal_octaves = 5
	var albedo := NoiseTexture2D.new()
	albedo.noise = grain
	albedo.seamless = true
	albedo.color_ramp = Gradient.new()
	albedo.color_ramp.set_color(0, Color(0.55, 0.55, 0.55))
	albedo.color_ramp.set_color(1, Color(1.0, 1.0, 1.0))
	material.albedo_texture = albedo
	var bumps := NoiseTexture2D.new()
	bumps.noise = grain
	bumps.seamless = true
	bumps.as_normal_map = true
	bumps.bump_strength = 6.0
	material.normal_enabled = true
	material.normal_texture = bumps
	return material
