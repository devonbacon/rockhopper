class_name Asteroid
extends Node3D
## The rock: a lumpy, stretched ball with craters, chambers and tunnels.
##
## It's a signed distance field (negative inside rock), sampled on a grid
## and meshed once with surface nets into chunks, each with a trimesh
## collider. Nothing deforms it after that; the field is kept only for
## placing things on it.

const CELL := 1.5
const RADIUS := 40.0
const LUMP := 7.0
const STRETCH := Vector3(1.25, 0.9, 1.0)
const CHUNK := 16
## Spaghetti tunnels: where two noises are both near zero. Width is in
## noise units, scale turns noise units into roughly metres.
const CAVE_FREQ := 0.022
const CAVE_WIDTH := 0.13
const CAVE_SCALE := 18.0
const ROCK_LAYER := 1

## Chambers: centre and radius. Worms: segments, as [a, b, radius].
var chambers: Array[Vector4] = []
var worms: Array[Array] = []
var craters: Array[Vector4] = []
## Where ore can go: [position, normal], in caves and on the surface.
var cave_spots: Array[Array] = []
var surface_spots: Array[Array] = []
var triangle_count := 0
var generate_ms := 0

var _shape := FastNoiseLite.new()
var _cave_a := FastNoiseLite.new()
var _cave_b := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()


func generate(seed_value: int) -> void:
	var started := Time.get_ticks_msec()
	_rng.seed = seed_value
	_shape.seed = seed_value
	_shape.frequency = 0.045
	_shape.fractal_octaves = 3
	for noise: FastNoiseLite in [_cave_a, _cave_b]:
		noise.seed = _rng.randi()
		noise.frequency = CAVE_FREQ
		noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	_carve_features()
	var extent := maxf(STRETCH.x, maxf(STRETCH.y, STRETCH.z)) * (RADIUS + LUMP) + 3.0
	var cells := ceili(2.0 * extent / CELL)
	var origin := -Vector3.ONE * cells * CELL * 0.5
	var field := _sample(origin, cells)
	_mesh(field, origin, cells)
	generate_ms = Time.get_ticks_msec() - started


## Signed distance to rock, roughly in metres: negative inside.
func density(p: Vector3) -> float:
	var d := body(p)
	if d > 3.0:
		return d
	for c in craters:
		d = maxf(d, c.w - p.distance_to(Vector3(c.x, c.y, c.z)))
	return maxf(d, -carve(p))


## The ball before anything's carved from it.
func body(p: Vector3) -> float:
	var q := p / STRETCH
	var length := q.length()
	if length < 0.001:
		return -RADIUS
	return length - (RADIUS + LUMP * _shape.get_noise_3dv(q / length * 30.0))


## Distance to open space inside the rock: chambers, worms and spaghetti.
func carve(p: Vector3) -> float:
	var d := INF
	for c in chambers:
		d = minf(d, p.distance_to(Vector3(c.x, c.y, c.z)) - c.w)
	for w in worms:
		d = minf(d, _segment_distance(p, w[0], w[1]) - w[2])
	var a := _cave_a.get_noise_3dv(p)
	var b := _cave_b.get_noise_3dv(p)
	return minf(d, (sqrt(a * a + b * b) - CAVE_WIDTH) * CAVE_SCALE)


## The first point of rock along a ray in from outside, along dir, and the
## surface's normal there.
func surface_point(dir: Vector3) -> Array:
	dir = dir.normalized()
	var t := (RADIUS + LUMP) * 2.0
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


func _carve_features() -> void:
	chambers.clear()
	worms.clear()
	craters.clear()
	for i in 12:
		var dir := _random_dir()
		var r := _rng.randf_range(5.0, 13.0)
		var surface := dir * (RADIUS + LUMP * _shape.get_noise_3dv(dir * 30.0)) * STRETCH
		craters.push_back(Vector4(surface.x, surface.y, surface.z, r) + Vector4(dir.x, dir.y, dir.z, 0.0) * r * 0.55)
	var previous := Vector3.INF
	for i in 5:
		var dir := _random_dir()
		var centre := dir * RADIUS * _rng.randf_range(0.25, 0.6) * STRETCH
		chambers.push_back(Vector4(centre.x, centre.y, centre.z, _rng.randf_range(6.0, 9.0)))
		# A bent tunnel out to the surface, so every chamber can be reached.
		var out_dir := (dir + _random_dir() * 0.5).normalized()
		var mouth := out_dir * (RADIUS + LUMP + 6.0) * STRETCH
		var bend := centre.lerp(mouth, 0.5) + _random_dir() * 8.0
		var r := _rng.randf_range(2.2, 2.8)
		worms.push_back([centre, bend, r])
		worms.push_back([bend, mouth, r])
		if previous != Vector3.INF:
			worms.push_back([previous, centre, _rng.randf_range(2.0, 2.5)])
		previous = centre


func _random_dir() -> Vector3:
	return Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()).normalized()


func _segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _sample(origin: Vector3, cells: int) -> PackedFloat32Array:
	var s := cells + 1
	var field := PackedFloat32Array()
	field.resize(s * s * s)
	var i := 0
	for k in s:
		for j in s:
			for x in s:
				field[i] = density(origin + Vector3(x, j, k) * CELL)
				i += 1
	return field


## Surface nets: a vertex in every cell the surface crosses, at the mean of
## its edge crossings, and a quad across every crossed grid edge.
func _mesh(field: PackedFloat32Array, origin: Vector3, cells: int) -> void:
	var s := cells + 1
	var corner_offset: PackedInt32Array = [0, 1, s, s + 1, s * s, s * s + 1, s * s + s, s * s + s + 1]
	var corner_pos: Array[Vector3] = []
	for c in 8:
		corner_pos.push_back(Vector3(c & 1, (c >> 1) & 1, (c >> 2) & 1))
	var edges: Array[Vector2i] = []
	for c in 8:
		for bit in [1, 2, 4]:
			if c & bit == 0:
				edges.push_back(Vector2i(c, c | bit))
	var cell_vert := PackedInt32Array()
	cell_vert.resize(cells * cells * cells)
	cell_vert.fill(-1)
	var active := PackedInt32Array()
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var v := PackedFloat32Array()
	v.resize(8)
	for k in cells:
		for j in cells:
			for i in cells:
				var base := i + s * (j + s * k)
				var d0 := field[base]
				# Far from the surface, no corner of this cell can cross it.
				if absf(d0) > 7.5:
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
				var cell := i + cells * (j + cells * k)
				cell_vert[cell] = positions.size()
				positions.push_back(origin + (Vector3(i, j, k) + sum / count) * CELL)
				normals.push_back(gradient.normalized())
				active.push_back(cell)
	var chunk_tris := {}
	for cell in active:
		var i := cell % cells
		var j := (cell / cells) % cells
		var k := cell / (cells * cells)
		var base := i + s * (j + s * k)
		var d0 := field[base]
		var key := Vector3i(i / CHUNK, j / CHUNK, k / CHUNK)
		# The edges leaving this cell's low corner along x, y and z, each
		# shared by four cells, this one the highest.
		if j > 0 and k > 0 and (d0 < 0.0) != (field[base + 1] < 0.0):
			_quad(chunk_tris, key, positions, normals, [
				cell_vert[i + cells * (j - 1 + cells * (k - 1))], cell_vert[i + cells * (j + cells * (k - 1))],
				cell_vert[cell], cell_vert[i + cells * (j - 1 + cells * k)]])
		if i > 0 and k > 0 and (d0 < 0.0) != (field[base + s] < 0.0):
			_quad(chunk_tris, key, positions, normals, [
				cell_vert[i - 1 + cells * (j + cells * (k - 1))], cell_vert[i + cells * (j + cells * (k - 1))],
				cell_vert[cell], cell_vert[i - 1 + cells * (j + cells * k)]])
		if i > 0 and j > 0 and (d0 < 0.0) != (field[base + s * s] < 0.0):
			_quad(chunk_tris, key, positions, normals, [
				cell_vert[i - 1 + cells * (j - 1 + cells * k)], cell_vert[i + cells * (j - 1 + cells * k)],
				cell_vert[cell], cell_vert[i - 1 + cells * (j + cells * k)]])
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


## Picks out floors for ore: in chambers and worms (never spaghetti, which
## might not connect to anything), and on the open surface.
func _find_spots(positions: PackedVector3Array, normals: PackedVector3Array) -> void:
	cave_spots.clear()
	surface_spots.clear()
	for n in positions.size():
		var p := positions[n]
		var floor_up := normals[n].dot(p.normalized())
		if floor_up < 0.5:
			continue
		if depth(p) > 4.0:
			var feature := INF
			for c in chambers:
				feature = minf(feature, p.distance_to(Vector3(c.x, c.y, c.z)) - c.w)
			for w in worms:
				feature = minf(feature, _segment_distance(p, w[0], w[1]) - w[2])
			if feature < 1.0:
				cave_spots.push_back([p, normals[n]])
		elif depth(p) < 1.0 and floor_up > 0.7:
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
