class_name Terrain
extends Node3D
## The asteroid: a lumpy, stretched ball with craters and a few chambers
## inside, joined to the surface by tunnels. Down is towards the centre.
##
## It's a signed distance field (negative inside rock), sampled on a grid
## and meshed once with surface nets into chunks with trimesh colliders.
## The mesh's own vertices make the rovers' walkable graph.

const CELL := 1.75
const RADIUS := 58.0
const LUMP := 8.0
const STRETCH := Vector3(1.2, 0.9, 1.0)
const CHUNK := 16
const ROCK_LAYER := 1
const BUCKET := 12.0
## Steepest a rover will drive, against up from the centre.
const ROVER_SLOPE := 30.0
## The landing crater: a level floor this far across (arc, metres from its
## middle), then a rim over the next few.
const LANDING_FLOOR := 15.0
const LANDING_RIM := 10.0

var chambers: Array[Vector4] = []
var worms: Array[Array] = []
var craters: Array[Vector4] = []
## [position, normal] on open, flat-ish surface, and on cave floors.
var surface_spots: Array[Array] = []
var cave_spots: Array[Array] = []
var triangle_count := 0
var generate_ms := 0
var graph := AStar3D.new()
## Where the landing crater is, as a direction in the unstretched ball.
var landing := Vector3.ZERO

var _shape := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
## Vector3i -> [craters, chambers, worms] overlapping that cube.
var _buckets := {}
var _quads := PackedInt32Array()
var _landing_r := 0.0


func generate(seed_value: int, landing_dir := Vector3.ZERO) -> void:
	var started := Time.get_ticks_msec()
	_rng.seed = seed_value
	_shape.seed = seed_value
	_shape.frequency = 0.045
	_shape.fractal_octaves = 3
	landing = (landing_dir / STRETCH).normalized() if landing_dir != Vector3.ZERO else Vector3.ZERO
	_landing_r = RADIUS + LUMP * _shape.get_noise_3dv(landing * 30.0) - 1.0
	_add_features()
	var extent := maxf(STRETCH.x, maxf(STRETCH.y, STRETCH.z)) * (RADIUS + LUMP) + 3.0
	var count := ceili(2.0 * extent / CELL)
	var cells := Vector3i(count, count, count)
	var origin := -Vector3.ONE * count * CELL * 0.5
	var field := _sample(origin, cells)
	_mesh(field, origin, cells)
	generate_ms = Time.get_ticks_msec() - started


## Signed distance to rock, roughly in metres: negative inside.
func density(p: Vector3) -> float:
	var q := p / STRETCH
	var length := q.length()
	if length > RADIUS + LUMP + 4.0:
		return length - (RADIUS + LUMP + 2.0)
	var d := length - (RADIUS - LUMP) if length < RADIUS - LUMP - 2.0 else body(p)
	if d > 3.0:
		return d
	var bucket: Array = _buckets.get(_bucket_of(p), [])
	if bucket.is_empty():
		return d
	for c: Vector4 in bucket[0]:
		d = maxf(d, c.w - p.distance_to(Vector3(c.x, c.y, c.z)))
	var open := INF
	for c: Vector4 in bucket[1]:
		open = minf(open, p.distance_to(Vector3(c.x, c.y, c.z)) - c.w)
	for w: Array in bucket[2]:
		open = minf(open, _segment_distance(p, w[0], w[1]) - w[2])
	return maxf(d, -open)


func body(p: Vector3) -> float:
	var q := p / STRETCH
	var length := q.length()
	if length < 0.001:
		return -RADIUS
	var dir := q / length
	var surface := RADIUS + LUMP * _shape.get_noise_3dv(dir * 30.0)
	var arc := _landing_arc(dir)
	if arc < LANDING_FLOOR + LANDING_RIM * 2.0:
		var level := 1.0 - smoothstep(LANDING_FLOOR - 2.0, LANDING_FLOOR + LANDING_RIM, arc)
		var rim := (arc - LANDING_FLOOR - 2.0) / 4.0
		surface = lerpf(surface, _landing_r, level) + 1.2 * exp(-rim * rim)
	return length - surface


## How far round the surface, roughly, a direction is from the landing
## crater's middle.
func _landing_arc(dir: Vector3) -> float:
	if landing == Vector3.ZERO:
		return INF
	return acos(clampf(dir.dot(landing), -1.0, 1.0)) * RADIUS


## The first rock along a ray in from outside towards the centre, through
## `at` (any point along that direction), and its normal.
func surface_point(at: Vector3) -> Array:
	var dir := at.normalized()
	var t := (RADIUS + LUMP) * maxf(STRETCH.x, maxf(STRETCH.y, STRETCH.z)) + 4.0
	while t > 0.0 and density(dir * t) > 0.0:
		t -= 0.5
	var lo := t
	var hi := t + 0.5
	for i in 16:
		var mid := (lo + hi) * 0.5
		if density(dir * mid) > 0.0:
			hi = mid
		else:
			lo = mid
	var p := dir * hi
	return [p, normal_at(p)]


func normal_at(p: Vector3) -> Vector3:
	var h := 0.25
	return Vector3(
		density(p + Vector3(h, 0, 0)) - density(p - Vector3(h, 0, 0)),
		density(p + Vector3(0, h, 0)) - density(p - Vector3(0, h, 0)),
		density(p + Vector3(0, 0, h)) - density(p - Vector3(0, 0, h))).normalized()


## How deep a point is inside the rock's outline, ignoring caves.
func depth(p: Vector3) -> float:
	return -body(p)


## A path over the surface for a rover, from near `from` to as near `to`
## as it can get.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if graph.get_point_count() == 0:
		return PackedVector3Array()
	return graph.get_point_path(graph.get_closest_point(from), graph.get_closest_point(to), true)


func _bucket_of(p: Vector3) -> Vector3i:
	return Vector3i((p / BUCKET).floor())


func _add_bucketed(lo: Vector3, hi: Vector3, which: int, feature: Variant) -> void:
	var a := _bucket_of(lo)
	var b := _bucket_of(hi)
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			for z in range(a.z, b.z + 1):
				var key := Vector3i(x, y, z)
				if !_buckets.has(key):
					_buckets[key] = [[], [], []]
				_buckets[key][which].push_back(feature)


func _add_features() -> void:
	chambers.clear()
	worms.clear()
	craters.clear()
	_buckets.clear()
	for i in 18:
		var dir := _random_dir()
		var r := _rng.randf_range(5.0, 14.0)
		if _landing_arc((dir / STRETCH).normalized()) < LANDING_FLOOR + LANDING_RIM + r:
			continue
		var surface := dir * (RADIUS + LUMP * _shape.get_noise_3dv(dir * 30.0)) * STRETCH
		var c := surface + dir * r * 0.55
		craters.push_back(Vector4(c.x, c.y, c.z, r))
		_add_bucketed(c - Vector3.ONE * r, c + Vector3.ONE * r, 0, Vector4(c.x, c.y, c.z, r))
	var previous := Vector3.INF
	for i in 6:
		var dir := _random_dir()
		var centre := dir * RADIUS * _rng.randf_range(0.3, 0.65) * STRETCH
		var size := _rng.randf_range(6.0, 9.0)
		chambers.push_back(Vector4(centre.x, centre.y, centre.z, size))
		_add_bucketed(centre - Vector3.ONE * size, centre + Vector3.ONE * size, 1, Vector4(centre.x, centre.y, centre.z, size))
		var out_dir := (dir + _random_dir() * 0.5).normalized()
		for attempt in 8:
			if _landing_arc((out_dir / STRETCH).normalized()) > LANDING_FLOOR + LANDING_RIM + 6.0:
				break
			out_dir = (dir + _random_dir() * 0.8).normalized()
		var mouth := out_dir * (RADIUS + LUMP + 6.0) * STRETCH
		var bend := centre.lerp(mouth, 0.5) + _random_dir() * 8.0
		var width := _rng.randf_range(2.2, 2.8)
		_add_worm(centre, bend, width)
		_add_worm(bend, mouth, width)
		if previous != Vector3.INF and previous.distance_to(centre) < 60.0:
			_add_worm(previous, centre, _rng.randf_range(2.0, 2.5))
		previous = centre


func _add_worm(a: Vector3, b: Vector3, width: float) -> void:
	worms.push_back([a, b, width])
	_add_bucketed(a.min(b) - Vector3.ONE * width, a.max(b) + Vector3.ONE * width, 2, [a, b, width])


func _random_dir() -> Vector3:
	return Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()).normalized()


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
	_build_graph(positions, normals)


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
	_quads.append_array([a, b, c, d])


func _build_chunks(chunk_tris: Dictionary, positions: PackedVector3Array, normals: PackedVector3Array) -> void:
	var material := _rock_material()
	triangle_count = 0
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


## Rovers drive on the outer surface where it's gentle enough, kept a
## cell back from anything steeper.
func _build_graph(positions: PackedVector3Array, normals: PackedVector3Array) -> void:
	graph.clear()
	var count := positions.size()
	var level := PackedByteArray()
	level.resize(count)
	var gentle := cos(deg_to_rad(ROVER_SLOPE))
	for n in count:
		var p := positions[n]
		level[n] = 1 if normals[n].dot(p.normalized()) > gentle and depth(p) < 2.0 else 0
	var clear := level.duplicate()
	for q in range(0, _quads.size(), 4):
		if level[_quads[q]] == 0 or level[_quads[q + 1]] == 0 or level[_quads[q + 2]] == 0 or level[_quads[q + 3]] == 0:
			for k in 4:
				clear[_quads[q + k]] = 0
	graph.reserve_space(count)
	for n in count:
		if clear[n] == 1:
			graph.add_point(n, positions[n])
	for q in range(0, _quads.size(), 4):
		for k in 4:
			var a := _quads[q + k]
			var b := _quads[q + (k + 1) % 4]
			if clear[a] == 1 and clear[b] == 1:
				graph.connect_points(a, b)
	_quads.clear()


func _find_spots(positions: PackedVector3Array, normals: PackedVector3Array) -> void:
	surface_spots.clear()
	cave_spots.clear()
	for n in positions.size():
		var p := positions[n]
		var up := normals[n].dot(p.normalized())
		if depth(p) > 3.0 and up > 0.6:
			cave_spots.push_back([p, normals[n]])
		elif up > 0.9 and absf(depth(p)) < 1.5:
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
