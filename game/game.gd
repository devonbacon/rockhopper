class_name Game
extends Node3D
## One mission: drop onto a turning asteroid, mine ore out of its caves,
## and be back at the pod when it launches.
##
## Power is one shared battery, filled by sunlight on the pod and on any
## panels you build, and drained by lamps, which light themselves whenever
## the sun's off them. Out of light, sun or lamp, your suit cools, and if
## it runs out you freeze. Ore pays for lamps and panels; what you hand in
## at the pod is the score.

enum State { PLAYING, WON, LOST }

const MISSION := 720.0
const QUOTA := 30
const BATTERY := 100.0
const START_BATTERY := 60.0
const POD_SOLAR := 0.8
const PANEL_SOLAR := 1.6
const LAMP_DRAW := 0.4
## Suit warmth, out of 100: how fast it's lost in the dark and regained in
## light.
const COLD_RATE := 100.0 / 45.0
const WARM_RATE := 100.0 / 6.0
const POD_RANGE := 6.0
const CAVE_ORE := 16
const SURFACE_ORE := 6
const START_ORE := 3

## Kept across a restart that keeps the seed.
static var _last_seed := 0

var state := State.PLAYING
var outcome := ""
var seed_value := 0
var time := 0.0
var battery := START_BATTERY
## This frame's power in and out, per second, for the HUD.
var power_in := 0.0
var power_out := 0.0
var carried := START_ORE
var delivered := 0
var warmth := 100.0
var lit_by := ""

var asteroid: Asteroid
var sun: Sun
var player: Player
var pod: Fixture
var hud: Hud
## Lamps and panels.
var built: Array[Fixture] = []
var ores: Array[Fixture] = []

var _rng := RandomNumberGenerator.new()
var _light_check := 0.0
var _args := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else ""
	seed_value = int(_args.seed) if _args.has("seed") else (_last_seed if _last_seed != 0 else randi())
	_last_seed = 0
	_rng.seed = seed_value
	time = float(_args.get("time", "0"))
	_add_environment()
	asteroid = Asteroid.new()
	add_child(asteroid)
	asteroid.generate(seed_value)
	sun = Sun.new()
	sun.time = time
	add_child(sun)
	_place_pod()
	_place_ore()
	player = Player.new()
	player.game = self
	add_child(player)
	_spawn_player()
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_debug_setup()


func _physics_process(delta: float) -> void:
	if state == State.PLAYING:
		time += delta
	sun.set_time(time)
	var space := get_world_3d().direct_space_state
	_light_check -= delta
	if _light_check <= 0.0:
		_light_check = 0.25
		pod.sunlit = sun.lights(pod.global_position + pod.normal * 3.6, space)
		for fixture in built:
			fixture.sunlit = sun.lights(fixture.global_position + fixture.normal * 1.6, space)
	var sun_dir := Sun.dir_at(time)
	power_in = POD_SOLAR if pod.sunlit else 0.0
	power_out = 0.0
	for fixture in built:
		if fixture.kind == &"panel" and fixture.sunlit:
			power_in += PANEL_SOLAR * maxf(0.0, fixture.normal.dot(sun_dir))
		elif fixture.kind == &"lamp":
			var want := !fixture.sunlit and battery > 0.0
			if want != fixture.on:
				fixture.set_on(want)
			if fixture.on:
				power_out += LAMP_DRAW
	battery = clampf(battery + (power_in - power_out) * delta, 0.0, BATTERY)
	if state != State.PLAYING:
		return
	lit_by = _light_on_player(space)
	warmth = clampf(warmth + (WARM_RATE if lit_by != "" else -COLD_RATE) * delta, 0.0, 100.0)
	if warmth <= 0.0:
		_end(State.LOST, "You froze in the dark.")
	elif time >= MISSION:
		if player.global_position.distance_to(pod.global_position) < POD_RANGE + 2.0:
			_end(State.WON, "Extracted with %d of %d ore handed in.%s" % [delivered, QUOTA, " Quota met." if delivered >= QUOTA else ""])
		else:
			_end(State.LOST, "The pod launched without you.")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and !event.echo and event.physical_keycode == KEY_R and state != State.PLAYING:
		if event.shift_pressed:
			_last_seed = seed_value
		get_tree().reload_current_scene()


## What's keeping the player warm: "sun", "lamp", "pod", or "" for nothing.
func _light_on_player(space: PhysicsDirectSpaceState3D) -> String:
	var head := player.camera.global_position
	if sun.lights(head, space):
		return "sun"
	for fixture in built:
		if fixture.kind == &"lamp" and fixture.on:
			var bulb := fixture.light.global_position
			if bulb.distance_to(head) < Fixture.LAMP_RANGE * 0.75:
				var query := PhysicsRayQueryParameters3D.create(bulb, head, Asteroid.ROCK_LAYER)
				if space.intersect_ray(query).is_empty():
					return "lamp"
	if battery > 0.0 and head.distance_to(pod.global_position) < POD_RANGE:
		return "pod"
	return ""


func can_build(kind: StringName, pos: Vector3) -> bool:
	if carried < Fixture.COST[kind]:
		return false
	for fixture: Fixture in built + ores + [pod]:
		if fixture.global_position.distance_to(pos) < (3.0 if fixture == pod else 1.2):
			return false
	return true


func build(kind: StringName, pos: Vector3, normal: Vector3) -> void:
	carried -= Fixture.COST[kind]
	var fixture := Fixture.make(kind, pos, normal)
	add_child(fixture)
	built.push_back(fixture)
	_light_check = 0.0


func pick_up(fixture: Fixture) -> void:
	carried += Fixture.COST[fixture.kind]
	built.erase(fixture)
	fixture.queue_free()


func mine(ore: Fixture) -> void:
	carried += ore.amount
	ores.erase(ore)
	ore.queue_free()


func hand_in() -> void:
	delivered += carried
	carried = 0


func _end(new_state: State, text: String) -> void:
	state = new_state
	outcome = text
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _add_environment() -> void:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://world/space.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.55, 0.8)
	env.ambient_light_energy = 0.025
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.ssao_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


## The pod comes down where the sun's just risen at the start, so the
## first day is long.
func _place_pod() -> void:
	var landing: Array = asteroid.surface_point(Sun.dir_at(Sun.DAY * 0.21))
	var up: Vector3 = (landing[1] + landing[0].normalized() * 2.0).normalized()
	pod = Fixture.make(&"pod", landing[0] - up * 0.4, up)
	add_child(pod)


func _place_ore() -> void:
	var spots: Array[Array] = asteroid.cave_spots.duplicate()
	_add_ore(spots, CAVE_ORE, 7.0)
	spots = asteroid.surface_spots.duplicate()
	_add_ore(spots, SURFACE_ORE, 18.0)


func _add_ore(spots: Array[Array], count: int, spacing: float) -> void:
	_shuffle(spots)
	var placed := 0
	for spot in spots:
		if placed == count:
			break
		var p: Vector3 = spot[0]
		if p.distance_to(pod.global_position) < 15.0:
			continue
		var crowded := false
		for ore in ores:
			if ore.global_position.distance_to(p) < spacing:
				crowded = true
				break
		if crowded:
			continue
		var ore := Fixture.make(&"ore", p - spot[1] * 0.15, spot[1])
		add_child(ore)
		ores.push_back(ore)
		placed += 1


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Variant = list[i]
		list[i] = list[j]
		list[j] = t


func _spawn_player() -> void:
	var up := pod.global_position.normalized()
	var side := Fixture.upright(up).x
	var spot: Array = asteroid.surface_point(pod.global_position + side * 5.0)
	place_player(spot[0] + spot[0].normalized() * 0.6, pod.global_position)


## Puts the player at pos, standing up and facing towards target.
func place_player(pos: Vector3, target: Vector3) -> void:
	var up := pos.normalized()
	var ahead := (target - pos)
	ahead = (ahead - up * ahead.dot(up)).normalized()
	player.global_transform = Transform3D(Basis.looking_at(ahead, up), pos)
	player.velocity = Vector3.ZERO
	player.align_up()


## Debug setup from user args (after `--`): seed=, time=, view=orbit|cave,
## lamps=N (around you), pitch=degrees, shot=path.png and shot_at=seconds
## to save a screenshot and quit.
func _debug_setup() -> void:
	match _args.get("view", ""):
		"orbit":
			var orbit := Camera3D.new()
			orbit.far = 2000.0
			add_child(orbit)
			var from := (Sun.dir_at(time).rotated(Vector3.UP, PI * 0.5) * 160.0) + Vector3.UP * 50.0
			orbit.look_at_from_position(from, Vector3.ZERO)
			orbit.make_current()
			player.process_mode = Node.PROCESS_MODE_DISABLED
		"cave":
			# Stand on the floor of a chamber, which is always open, facing
			# the nearest ore.
			var chamber := asteroid.chambers[0]
			var centre := Vector3(chamber.x, chamber.y, chamber.z)
			var ore := ores[0]
			for candidate in ores:
				if candidate.global_position.distance_to(centre) < ore.global_position.distance_to(centre):
					ore = candidate
			await get_tree().physics_frame
			var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(centre, centre * 0.2, Asteroid.ROCK_LAYER))
			place_player((hit.position if !hit.is_empty() else centre) + centre.normalized() * 0.3, ore.global_position)
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for i in int(_args.get("lamps", "0")):
		var up := player.global_position.normalized()
		var from := player.global_position + up * 1.5 + player.global_basis * Vector3(cos(i * 2.4) * 3.5, 0, sin(i * 2.4) * 3.5 - 3.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from - up * 10.0, Asteroid.ROCK_LAYER))
		if !hit.is_empty():
			carried += Fixture.COST[&"lamp"]
			build(&"lamp", hit.position, hit.normal)
	if _args.has("pitch"):
		player.look(deg_to_rad(float(_args.pitch)))
	if _args.has("shot"):
		await get_tree().create_timer(float(_args.get("shot_at", "3"))).timeout
		var image := get_viewport().get_texture().get_image()
		image.save_png(_args.shot)
		print("saved ", _args.shot)
		get_tree().quit()
