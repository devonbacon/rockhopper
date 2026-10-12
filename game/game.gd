class_name Game
extends Node3D
## One mission: drop onto a turning asteroid, get ore into the pod, and be
## beside it when it launches.
##
## Power is one shared battery, filled by sunlight on the pod and on any
## panels you build, and drained by lamps, which light themselves whenever
## the sun's off them. Out of light, sun or lamp, your suit cools, and if
## it runs out you freeze.
##
## Ore is banked in the pod: what you carry counts once you hand it in,
## and bots fly in what they mine from marked deposits, which they'll only
## do while the deposit's lit. Lamps, panels and bots are paid for from the
## bank, and what's in it at launch is the score.
##
## In the dark, spiders climb out of the rock wherever no light falls,
## more of them as the mission goes on, and go for you, working bots, and
## what you've built. Sunlight sends them back under.

enum State { PLAYING, WON, LOST }

const MISSION := 720.0
const QUOTA := 100
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
## Ore's all on the surface for now: none in the caves.
const CAVE_ORE := 0
const SURFACE_ORE := 12
const DEPOSITS := 6
const START_STOCK := 8
const START_BOTS := 2
const HEALTH := 100.0
## Health comes back this fast once nothing's hurt you for a while.
const HEAL_RATE := 4.0
const HEAL_DELAY := 4.0
## Spiders: the most alive at once grows from the first to the second over
## the mission, and they come up this many seconds apart.
const SPIDERS_START := 5
const SPIDERS_END := 16
const SPAWN_GAP_START := 4.0
const SPAWN_GAP_END := 1.5
const BOT_BITE_REACH := 3.8

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
## Ore in the pod, and in your pockets.
var stock := START_STOCK
var carried := 0
var warmth := 100.0
var health := HEALTH
## How recently you were hurt, 1 fading to 0, for the HUD.
var hurt := 0.0
var lit_by := ""

var asteroid: Asteroid
var sun: Sun
var player: Player
var pod: Fixture
var hud: Hud
## Lamps and panels.
var built: Array[Fixture] = []
var ores: Array[Fixture] = []
var deposits: Array[Fixture] = []
var bots: Array[Bot] = []
var spiders: Array[Spider] = []

var _rng := RandomNumberGenerator.new()
var _light_check := 0.0
var _since_hurt := 99.0
var _spawn_in := 2.0
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
	_place_deposits()
	_place_ore()
	for i in START_BOTS:
		_add_bot()
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
	_spawn_spiders(delta)
	for bot in bots.duplicate():
		if bot.health <= 0.0:
			bots.erase(bot)
			bot.queue_free()
	for fixture in built.duplicate():
		if fixture.health <= 0.0:
			built.erase(fixture)
			fixture.queue_free()
	lit_by = _light_on_player()
	warmth = clampf(warmth + (WARM_RATE if lit_by != "" else -COLD_RATE) * delta, 0.0, 100.0)
	_since_hurt += delta
	hurt = maxf(0.0, hurt - delta * 2.0)
	if _since_hurt > HEAL_DELAY:
		health = minf(HEALTH, health + HEAL_RATE * delta)
	if warmth <= 0.0:
		_end(State.LOST, "You froze in the dark.")
	elif health <= 0.0:
		_end(State.LOST, "The spiders got you.")
	elif time >= MISSION:
		if player.global_position.distance_to(pod.global_position) < POD_RANGE + 2.0:
			_end(State.WON, "Extracted with %d of %d ore in the pod.%s" % [stock, QUOTA, " Quota met." if stock >= QUOTA else ""])
		else:
			_end(State.LOST, "The pod launched without you.")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and !event.echo and event.physical_keycode == KEY_R and state != State.PLAYING:
		if event.shift_pressed:
			_last_seed = seed_value
		get_tree().reload_current_scene()


## What light reaches a point: "sun", "lamp", or "" for none.
func lit_at(pos: Vector3) -> String:
	var space := get_world_3d().direct_space_state
	if sun.lights(pos, space):
		return "sun"
	for fixture in built:
		if fixture.kind == &"lamp" and fixture.on:
			var bulb := fixture.light.global_position
			if bulb.distance_to(pos) < Fixture.LAMP_RANGE * 0.75:
				var query := PhysicsRayQueryParameters3D.create(bulb, pos, Asteroid.ROCK_LAYER)
				if space.intersect_ray(query).is_empty():
					return "lamp"
	return ""


## What's keeping the player warm: "sun", "lamp", "pod", or "" for nothing.
func _light_on_player() -> String:
	var head := player.camera.global_position
	var light := lit_at(head)
	if light == "" and battery > 0.0 and head.distance_to(pod.global_position) < POD_RANGE:
		return "pod"
	return light


## How far out from the centre the rock's outer surface is, along dir.
func ground_radius(dir: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(dir * 120.0, dir * 2.0, Asteroid.ROCK_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.length() if !hit.is_empty() else Asteroid.RADIUS


func can_build(kind: StringName, pos: Vector3) -> bool:
	if stock < Fixture.COST[kind]:
		return false
	for fixture: Fixture in built + ores + deposits + [pod]:
		var room := 3.0 if fixture == pod else (2.6 if fixture.kind == &"deposit" else 1.2)
		if fixture.global_position.distance_to(pos) < room:
			return false
	return true


func build(kind: StringName, pos: Vector3, normal: Vector3) -> void:
	stock -= Fixture.COST[kind]
	var fixture := Fixture.make(kind, pos, normal)
	add_child(fixture)
	built.push_back(fixture)
	_light_check = 0.0


func pick_up(fixture: Fixture) -> void:
	stock += Fixture.COST[fixture.kind]
	built.erase(fixture)
	fixture.queue_free()


## Mining by hand: an ore cluster comes away whole, a deposit a piece at a
## time.
func mine(ore: Fixture) -> void:
	if ore.kind == &"deposit":
		carried += 1
		return
	carried += ore.amount
	ores.erase(ore)
	ore.queue_free()


func hand_in() -> void:
	stock += carried
	carried = 0


func deliver(amount: int) -> void:
	stock += amount


## Prints a bot at the pod from the bank, if there's enough in it.
func print_bot() -> bool:
	if stock < Fixture.COST[&"bot"]:
		return false
	stock -= Fixture.COST[&"bot"]
	_add_bot()
	return true


func toggle_designation(deposit: Fixture) -> void:
	deposit.set_designated(!deposit.designated)


## The marked deposit with fewest bots headed to or working it.
func pick_deposit() -> Fixture:
	var best: Fixture = null
	var fewest := 1 << 30
	for deposit in deposits:
		if !deposit.designated:
			continue
		var count := bots_on(deposit)
		if count < fewest:
			fewest = count
			best = deposit
	return best


func bots_on(deposit: Fixture) -> int:
	var count := 0
	for bot in bots:
		if bot.deposit == deposit and (bot.task == Bot.Task.OUTBOUND or bot.task == Bot.Task.MINING):
			count += 1
	return count


## The nearest thing a spider would bite: you, a bot out working, a lamp
## or a panel. You count as a little nearer than you are.
func spider_target(spider: Spider) -> Node3D:
	var from := spider.global_position
	var best: Node3D = null
	var best_distance := Spider.SIGHT
	var candidates: Array[Node3D] = [player]
	for bot in bots:
		if bot.exposed():
			candidates.push_back(bot)
	candidates.append_array(built)
	for candidate in candidates:
		var distance := from.distance_to(candidate.global_position) * (0.75 if candidate == player else 1.0)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## How close a spider has to be to bite target.
func bite_reach(target: Node3D) -> float:
	if target is Bot:
		return BOT_BITE_REACH
	if target == player:
		return 1.7
	return 1.9


func damage(target: Node3D, amount: float) -> void:
	if state != State.PLAYING:
		return
	if target == player:
		health -= amount
		hurt = 1.0
		_since_hurt = 0.0
	elif target is Bot:
		(target as Bot).damage(amount)
	elif target is Fixture:
		(target as Fixture).health -= amount


func remove_spider(spider: Spider) -> void:
	spiders.erase(spider)
	spider.queue_free()


func spawn_spider(spot: Vector3) -> void:
	var spider := Spider.new()
	spider.game = self
	spider.position = spot
	spider.basis = Fixture.upright(spot.normalized())
	add_child(spider)
	spiders.push_back(spider)


func _add_bot() -> void:
	var bot := Bot.new()
	bot.game = self
	bot.slot = bots.size()
	add_child(bot)
	bot.global_position = pod.global_position + pod.normal * 5.0
	bots.push_back(bot)


## Brings spiders up out of the rock, somewhere unlit not far from you, a
## bot, or something you've built.
func _spawn_spiders(delta: float) -> void:
	_spawn_in -= delta
	if _spawn_in > 0.0:
		return
	var progress := time / MISSION
	_spawn_in = lerpf(SPAWN_GAP_START, SPAWN_GAP_END, progress)
	if spiders.size() >= roundi(lerpf(SPIDERS_START, SPIDERS_END, progress)):
		return
	var near: Array[Node3D] = [player, player, player]
	near.append_array(bots)
	near.append_array(built)
	var focus: Node3D = near[_rng.randi() % near.size()]
	for attempt in 4:
		var spot := _spawn_spot(focus.global_position)
		if spot != Vector3.INF:
			spawn_spider(spot)
			return


## Somewhere dark on the rock 12-28 m from around, and not too near you,
## or INF if this try didn't find one.
func _spawn_spot(around: Vector3) -> Vector3:
	var up := around.normalized()
	var frame := Fixture.upright(up)
	var angle := _rng.randf() * TAU
	var start := around + up * 6.0 + (frame.x * cos(angle) + frame.z * sin(angle)) * _rng.randf_range(12.0, 28.0)
	if asteroid.density(start) < 0.0:
		return Vector3.INF
	var query := PhysicsRayQueryParameters3D.create(start, start - start.normalized() * 24.0, Asteroid.ROCK_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	var spot: Vector3 = hit.position
	if spot.distance_to(player.global_position) < 10.0 or lit_at(spot + spot.normalized() * 0.6) != "":
		return Vector3.INF
	return spot


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


## Big outcrops that never run out, spread well apart, none too near the
## pod.
func _place_deposits() -> void:
	var spots: Array[Array] = asteroid.surface_spots.duplicate()
	_shuffle(spots)
	for spot in spots:
		if deposits.size() == DEPOSITS:
			break
		var p: Vector3 = spot[0]
		if p.distance_to(pod.global_position) < 18.0:
			continue
		var crowded := false
		for deposit in deposits:
			if deposit.global_position.distance_to(p) < 25.0:
				crowded = true
				break
		if crowded:
			continue
		var up: Vector3 = (spot[1] + p.normalized()).normalized()
		var deposit := Fixture.make(&"deposit", p - up * 0.3, up)
		add_child(deposit)
		deposits.push_back(deposit)


func _place_ore() -> void:
	var spots: Array[Array] = asteroid.cave_spots.duplicate()
	_add_ore(spots, CAVE_ORE, 7.0)
	spots = asteroid.surface_spots.duplicate()
	_add_ore(spots, SURFACE_ORE, 12.0)


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
		for other: Fixture in ores + deposits:
			if other.global_position.distance_to(p) < spacing:
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
## lamps=N (around you), mark (marks the deposit nearest the pod and
## stands you by it), spiders=N (in front of you), tool=lamp|panel,
## pitch=degrees, and shot=path.png and shot_at=seconds to save a
## screenshot and quit.
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
			# Stand on the floor of a chamber, which is always open.
			var chamber := asteroid.chambers[0]
			var centre := Vector3(chamber.x, chamber.y, chamber.z)
			await get_tree().physics_frame
			var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(centre, centre * 0.2, Asteroid.ROCK_LAYER))
			place_player((hit.position if !hit.is_empty() else centre) + centre.normalized() * 0.3, centre * 2.0)
	if _args.has("mark"):
		var nearest := deposits[0]
		for deposit in deposits:
			if deposit.global_position.distance_to(pod.global_position) < nearest.global_position.distance_to(pod.global_position):
				nearest = deposit
		nearest.set_designated(true)
		var spot: Array = asteroid.surface_point(nearest.global_position + Fixture.upright(nearest.normal).x * 8.0)
		place_player(spot[0] + spot[0].normalized() * 0.6, nearest.global_position)
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for i in int(_args.get("lamps", "0")):
		var up := player.global_position.normalized()
		var from := player.global_position + up * 1.5 + player.global_basis * Vector3(cos(i * 2.4) * 3.5, 0, sin(i * 2.4) * 3.5 - 3.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from - up * 10.0, Asteroid.ROCK_LAYER))
		if !hit.is_empty():
			stock += Fixture.COST[&"lamp"]
			build(&"lamp", hit.position, hit.normal)
	for i in int(_args.get("spiders", "0")):
		var ahead := -player.global_basis.z
		var side := player.global_basis.x
		var around := player.global_position + player.global_position.normalized() * 4.0 + ahead * (5.0 + i * 1.2) + side * ((i % 3) - 1) * 1.8
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(around, around * 0.5, Asteroid.ROCK_LAYER))
		if !hit.is_empty():
			spawn_spider(hit.position)
	if _args.has("tool"):
		player.tool = StringName(_args.tool)
	if _args.has("pitch"):
		player.look(deg_to_rad(float(_args.pitch)))
	if _args.has("shot"):
		await get_tree().create_timer(float(_args.get("shot_at", "3"))).timeout
		var image := get_viewport().get_texture().get_image()
		image.save_png(_args.shot)
		print("saved ", _args.shot)
		get_tree().quit()
