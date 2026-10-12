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
## Ore is banked in the pod: what you carry counts once you hand it in.
## Build a drill rig over a deposit and it drills while it's lit; rovers
## drive out to rigs with a load worth the trip and haul it home. Lamps,
## panels, rigs and rovers are paid for from the bank, and what's in it at
## launch is the score.
##
## In the dark, spiders climb out of the ground wherever no light falls,
## more of them as the mission goes on, and go for you, rovers out on the
## road, and what you've built. Sunlight sends them back under.

enum State { PLAYING, WON, LOST }

const MISSION := 720.0
const QUOTA := 100
const BATTERY := 100.0
const START_BATTERY := 60.0
const POD_SOLAR := 0.8
const PANEL_SOLAR := 1.6
const LAMP_DRAW := 0.4
const BATTERY_BANK := 80.0
const LAB_DRAW := 0.6
const UPGRADES := {
	&"armour": {name = "ARMOUR PLATING", cost = 5, time = 40.0, text = "+50 max health"},
	&"heated": {name = "HEATED SUIT", cost = 4, time = 30.0, text = "Cold takes twice as long to freeze you"},
	&"tanks": {name = "BIGGER TANKS", cost = 3, time = 30.0, text = "The jetpack burns fuel 40% slower"},
	&"rounds": {name = "OVERCHARGED ROUNDS", cost = 6, time = 45.0, text = "Double damage: one shot kills a spider"},
	&"stabiliser": {name = "STABILISER", cost = 4, time = 30.0, text = "Half the bloom from firing, tighter at rest"},
	&"drills": {name = "FASTER DRILLS", cost = 6, time = 45.0, text = "Rigs drill 40% faster"},
	&"rovers": {name = "ROVER TUNING", cost = 5, time = 40.0, text = "Rovers drive 40% faster and carry 4 more"},
	&"lamps": {name = "EFFICIENT LAMPS", cost = 4, time = 30.0, text = "Lamps draw half the power"},
}
## Suit warmth, out of 100: how fast it's lost in the dark and regained in
## light.
const COLD_RATE := 100.0 / 45.0
const WARM_RATE := 100.0 / 6.0
const POD_RANGE := 6.0
const SURFACE_ORE := 16
const DEPOSITS := 8
## The first this many are somewhere a rover can drive to from the pod.
const REACHABLE_DEPOSITS := 4
const START_STOCK := 10
const START_ROVERS := 1
## A rover goes out for a rig with at least this much in its hopper.
const WORTH_A_TRIP := 4
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
var researched := {}

var terrain: Terrain
var sun: Sun
var player: Player
var pod: Fixture
var hud: Hud
## Lamps, panels and rigs.
var built: Array[Fixture] = []
var ores: Array[Fixture] = []
var deposits: Array[Fixture] = []
var rovers: Array[Rover] = []
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
	terrain = Terrain.new()
	add_child(terrain)
	terrain.generate(seed_value, Sun.dir_at(Sun.DAY * 0.21))
	sun = Sun.new()
	sun.time = time
	add_child(sun)
	_place_pod()
	_place_deposits()
	_place_ore()
	for i in START_ROVERS:
		_add_rover()
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
				power_out += LAMP_DRAW * (0.5 if has(&"lamps") else 1.0)
	for lab in built:
		if lab.kind == &"lab" and lab.researching != &"" and state == State.PLAYING:
			lab.unpowered = battery <= 0.0
			if !lab.unpowered:
				power_out += LAB_DRAW
				lab.research_time += delta
				if lab.research_time >= UPGRADES[lab.researching].time:
					researched[lab.researching] = true
					hud.announce("Researched: %s" % String(UPGRADES[lab.researching].name).capitalize())
					lab.researching = &""
	var full := capacity()
	battery = clampf(battery + (power_in - power_out) * delta, 0.0, full)
	for fixture in built:
		if fixture.kind == &"battery":
			fixture.charge = battery / full
	if state != State.PLAYING:
		return
	for fixture in built:
		if fixture.kind == &"drill":
			fixture.drill(delta, fixture.sunlit or lit_at(fixture.global_position + fixture.normal * 1.0) != "", Fixture.DRILL_EVERY * (0.6 if has(&"drills") else 1.0))
	_spawn_spiders(delta)
	for rover in rovers.duplicate():
		if rover.health <= 0.0:
			rovers.erase(rover)
			rover.queue_free()
	for fixture in built.duplicate():
		if fixture.health <= 0.0:
			_remove_built(fixture)
	lit_by = _light_on_player()
	warmth = clampf(warmth + (WARM_RATE if lit_by != "" else -COLD_RATE * (0.5 if has(&"heated") else 1.0)) * delta, 0.0, 100.0)
	_since_hurt += delta
	hurt = maxf(0.0, hurt - delta * 2.0)
	if _since_hurt > HEAL_DELAY:
		health = minf(max_health(), health + HEAL_RATE * delta)
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


func has(upgrade: StringName) -> bool:
	return researched.has(upgrade)


func max_health() -> float:
	return HEALTH + (50.0 if has(&"armour") else 0.0)


func rover_capacity() -> int:
	return Rover.CAPACITY + (4 if has(&"rovers") else 0)


func rover_speed() -> float:
	return Rover.SPEED * (1.4 if has(&"rovers") else 1.0)


## Whether a lab is working on it, and which.
func researching(upgrade: StringName) -> Fixture:
	for lab in built:
		if lab.kind == &"lab" and lab.researching == upgrade:
			return lab
	return null


func _wire_lab_screen(lab: Fixture) -> void:
	var screen := lab.screen
	screen.info = func() -> String:
		if lab.researching == &"":
			return "IDLE. PICK SOMETHING TO RESEARCH."
		var upgrade: Dictionary = UPGRADES[lab.researching]
		var left: float = upgrade.time - lab.research_time
		return "%s  %ds%s" % [upgrade.name, ceili(left), "  NO POWER" if lab.unpowered else ""]
	screen.button = func(action: StringName) -> Array:
		var upgrade: Dictionary = UPGRADES[action]
		if has(action):
			return ["%s   DONE" % upgrade.name, false, false]
		if lab.researching == action:
			return ["%s   %d%%   CANCEL" % [upgrade.name, roundi(lab.research_time / upgrade.time * 100.0)], true, true]
		var busy := lab.researching != &"" or researching(action) != null
		return ["%s   %d ORE  %ds" % [upgrade.name, upgrade.cost, upgrade.time], !busy and stock >= upgrade.cost, false]
	screen.describe = func(action: StringName) -> String:
		var upgrade: Dictionary = UPGRADES[action]
		if has(action):
			return "%s: researched" % String(upgrade.name).capitalize()
		if lab.researching == action:
			return "[E] Cancel %s, refunding %d ore" % [String(upgrade.name).capitalize(), upgrade.cost]
		return "[E] Research %s: %s" % [String(upgrade.name).capitalize(), upgrade.text]
	screen.pressed = func(action: StringName) -> String:
		var upgrade: Dictionary = UPGRADES[action]
		if has(action):
			return "ALREADY RESEARCHED."
		if lab.researching == action:
			lab.researching = &""
			stock += upgrade.cost
			return "CANCELLED. %d ORE REFUNDED." % upgrade.cost
		if lab.researching != &"":
			return "BUSY: CANCEL THE CURRENT RESEARCH FIRST."
		if researching(action) != null:
			return "ANOTHER LAB IS ON IT."
		if stock < upgrade.cost:
			return "NOT ENOUGH ORE BANKED."
		stock -= upgrade.cost
		lab.researching = action
		lab.research_time = 0.0
		return "RESEARCHING %s." % upgrade.name


func capacity() -> float:
	var total := BATTERY
	for fixture in built:
		if fixture.kind == &"battery":
			total += BATTERY_BANK
	return total


## What light reaches a point: "sun", "lamp", or "" for none.
func lit_at(pos: Vector3) -> String:
	var space := get_world_3d().direct_space_state
	if sun.lights(pos, space):
		return "sun"
	for fixture in built:
		if fixture.kind == &"lamp" and fixture.on:
			var bulb := fixture.light.global_position
			if bulb.distance_to(pos) < Fixture.LAMP_RANGE * 0.75:
				var query := PhysicsRayQueryParameters3D.create(bulb, pos, Terrain.ROCK_LAYER)
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


## Whether kind can go at pos; for a rig, pos is the deposit's.
func can_build(kind: StringName, pos: Vector3) -> bool:
	if stock < Fixture.COST[kind]:
		return false
	if kind == &"drill":
		var deposit := deposit_at(pos)
		return deposit != null and deposit.rig == null
	for fixture: Fixture in built + ores + deposits + [pod]:
		var room := 3.0 if fixture == pod else (2.6 if fixture.kind == &"deposit" or fixture.kind == &"drill" else 1.2)
		if kind == &"lab" or fixture.kind == &"lab":
			room += 1.6
		if fixture.global_position.distance_to(pos) < room:
			return false
	return true


func build(kind: StringName, pos: Vector3, normal: Vector3) -> void:
	stock -= Fixture.COST[kind]
	var fixture: Fixture
	if kind == &"drill":
		var deposit := deposit_at(pos)
		fixture = Fixture.make(kind, deposit.global_position, deposit.normal)
		fixture.deposit = deposit
		deposit.rig = fixture
	else:
		fixture = Fixture.make(kind, pos, normal)
	if kind == &"lab":
		var towards := player.global_position - pos
		towards -= normal * towards.dot(normal)
		if towards.length() > 0.1:
			fixture.basis = Basis.looking_at(-towards.normalized(), normal)
	add_child(fixture)
	built.push_back(fixture)
	_light_check = 0.0
	if kind == &"lab":
		_wire_lab_screen(fixture)


func deposit_at(pos: Vector3) -> Fixture:
	for deposit in deposits:
		if deposit.global_position.distance_to(pos) < 0.5:
			return deposit
	return null


## Picks up a lamp, panel or rig, refunding it to the bank; a rig's hopper
## comes with it, into your pockets.
func pick_up(fixture: Fixture) -> void:
	stock += Fixture.COST[fixture.kind]
	carried += fixture.stored
	if fixture.researching != &"":
		stock += UPGRADES[fixture.researching].cost
	_remove_built(fixture)


func _remove_built(fixture: Fixture) -> void:
	if fixture.deposit:
		fixture.deposit.rig = null
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


## Empties a rig's hopper into your pockets.
func empty_rig(rig: Fixture) -> void:
	carried += rig.take(Fixture.HOPPER)


func hand_in() -> void:
	stock += carried
	carried = 0


func deliver(amount: int) -> void:
	stock += amount


func screens() -> Array[Screen]:
	var all: Array[Screen] = [pod.screen]
	for fixture in built:
		if fixture.kind == &"lab":
			all.push_back(fixture.screen)
	for rover in rovers:
		all.push_back(rover.screen)
	return all


func _wire_pod_screen() -> void:
	var screen := pod.screen
	screen.info = func() -> String:
		var out := 0
		for rover in rovers:
			if rover.task != Rover.Task.PARKED:
				out += 1
		var left := maxf(0.0, MISSION - time)
		return "ORE BANKED    %d / %d\nROVERS        %d  (%d OUT)\nBATTERY       %d%%\nLAUNCH IN     %d:%02d" % [
			stock, QUOTA, rovers.size(), out, roundi(battery / capacity() * 100.0), int(left) / 60, int(left) % 60]
	screen.button = func(action: StringName) -> Array:
		if action == &"rover":
			return ["PRINT ROVER   %d ORE" % Fixture.COST[&"rover"], stock >= Fixture.COST[&"rover"], false]
		return ["HAND IN ORE   %d CARRIED" % carried, carried > 0, false]
	screen.pressed = func(action: StringName) -> String:
		if action == &"rover":
			if print_rover():
				return "ROVER PRINTED. %d ON THE ROSTER." % rovers.size()
			return "NOT ENOUGH ORE BANKED: A ROVER NEEDS %d." % Fixture.COST[&"rover"]
		if carried == 0:
			return "NOTHING TO HAND IN."
		var amount := carried
		hand_in()
		return "%d ORE BANKED." % amount


## Prints a rover at the pod from the bank, if there's enough in it.
func print_rover() -> bool:
	if stock < Fixture.COST[&"rover"]:
		return false
	stock -= Fixture.COST[&"rover"]
	_add_rover()
	return true


## The rig most worth a trip for this rover: the fullest, after what other
## rovers are already headed for, over the distance, skipping rigs it
## couldn't reach lately.
func pick_rig(rover: Rover) -> Fixture:
	var best: Fixture = null
	var best_score := 0.0
	for rig in built:
		if rig.kind != &"drill" or rover.unreachable.get(rig, -INF) > time:
			continue
		var spoken_for := 0
		for other in rovers:
			if other != rover and other.rig == rig and (other.task == Rover.Task.OUTBOUND or other.task == Rover.Task.LOADING):
				spoken_for += rover_capacity()
		var waiting := rig.stored - spoken_for
		if waiting < WORTH_A_TRIP:
			continue
		var score := waiting / (10.0 + rover.global_position.distance_to(rig.global_position))
		if score > best_score:
			best_score = score
			best = rig
	return best


## The nearest thing a spider would bite: you, a rover out on the road, a
## lamp, a panel or a rig. You count as a little nearer than you are.
func spider_target(spider: Spider) -> Node3D:
	var from := spider.global_position
	var best: Node3D = null
	var best_distance := Spider.SIGHT
	var candidates: Array[Node3D] = [player]
	for rover in rovers:
		if rover.exposed():
			candidates.push_back(rover)
	candidates.append_array(built)
	for candidate in candidates:
		var distance := from.distance_to(candidate.global_position) * (0.75 if candidate == player else 1.0)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## How close a spider has to be to bite target.
func bite_reach(target: Node3D) -> float:
	if target is Rover:
		return 2.0
	if target == player:
		return 1.7
	if target is Fixture and (target as Fixture).kind == &"drill":
		return 2.8
	return 1.9


func damage(target: Node3D, amount: float) -> void:
	if state != State.PLAYING:
		return
	if target == player:
		health -= amount
		hurt = 1.0
		_since_hurt = 0.0
	elif target is Rover:
		(target as Rover).damage(amount)
	elif target is Fixture:
		(target as Fixture).health -= amount


func remove_spider(spider: Spider) -> void:
	spiders.erase(spider)
	spider.queue_free()


func spawn_spider(spot: Vector3) -> void:
	var spider := Spider.new()
	spider.game = self
	spider.position = spot
	add_child(spider)
	spiders.push_back(spider)


func _add_rover() -> void:
	var rover := Rover.new()
	rover.game = self
	rover.slot = rovers.size()
	add_child(rover)
	rover.global_position = rover.park_point()
	rovers.push_back(rover)


## Brings spiders up out of the ground, somewhere unlit not far from you, a
## rover, or something you've built.
func _spawn_spiders(delta: float) -> void:
	_spawn_in -= delta
	if _spawn_in > 0.0:
		return
	var progress := time / MISSION
	_spawn_in = lerpf(SPAWN_GAP_START, SPAWN_GAP_END, progress)
	if spiders.size() >= roundi(lerpf(SPIDERS_START, SPIDERS_END, progress)):
		return
	var near: Array[Node3D] = [player, player, player]
	near.append_array(rovers)
	near.append_array(built)
	var focus: Node3D = near[_rng.randi() % near.size()]
	for attempt in 4:
		var spot := _spawn_spot(focus.global_position)
		if spot != Vector3.INF:
			spawn_spider(spot)
			return


## Somewhere dark on the surface 12-28 m from around, and not too near you,
## or INF if this try didn't find one.
func _spawn_spot(around: Vector3) -> Vector3:
	var up := around.normalized()
	var frame := Fixture.upright(up)
	var angle := _rng.randf() * TAU
	var start := around + up * 6.0 + (frame.x * cos(angle) + frame.z * sin(angle)) * _rng.randf_range(12.0, 28.0)
	if terrain.density(start) < 0.0:
		return Vector3.INF
	var query := PhysicsRayQueryParameters3D.create(start, start - start.normalized() * 24.0, Terrain.ROCK_LAYER)
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
	var landing: Array = terrain.surface_point(Sun.dir_at(Sun.DAY * 0.21))
	var up: Vector3 = (landing[1] + landing[0].normalized() * 2.0).normalized()
	pod = Fixture.make(&"pod", landing[0] - up * 0.4, up)
	add_child(pod)
	_wire_pod_screen()

## Big outcrops that never run out, spread well apart, none too near the
## pod, on ground flat enough for a rig.
func _place_deposits() -> void:
	var spots: Array[Array] = terrain.surface_spots.duplicate()
	_shuffle(spots)
	_place_deposits_from(spots, true)
	_place_deposits_from(spots, false)


func _place_deposits_from(spots: Array[Array], reachable_only: bool) -> void:
	for spot in spots:
		if deposits.size() == (REACHABLE_DEPOSITS if reachable_only else DEPOSITS):
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
		if reachable_only:
			var path := terrain.find_path(pod.global_position, p)
			if path.is_empty() or path[-1].distance_to(p) > 4.0:
				continue
		var up: Vector3 = (spot[1] + p.normalized()).normalized()
		var deposit := Fixture.make(&"deposit", p - up * 0.3, up)
		add_child(deposit)
		deposits.push_back(deposit)


func _place_ore() -> void:
	var spots: Array[Array] = terrain.surface_spots.duplicate()
	_shuffle(spots)
	for spot in spots:
		if ores.size() == SURFACE_ORE:
			break
		var p: Vector3 = spot[0]
		if p.distance_to(pod.global_position) < 15.0:
			continue
		var crowded := false
		for other: Fixture in ores + deposits:
			if other.global_position.distance_to(p) < 12.0:
				crowded = true
				break
		if crowded:
			continue
		var ore := Fixture.make(&"ore", p - spot[1] * 0.15, spot[1])
		add_child(ore)
		ores.push_back(ore)


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Variant = list[i]
		list[i] = list[j]
		list[j] = t


func _spawn_player() -> void:
	var side := Fixture.upright(pod.global_position.normalized()).x
	var spot: Array = terrain.surface_point(pod.global_position + side * 5.0)
	place_player(spot[0] + spot[0].normalized() * 0.6, pod.global_position)

## Puts the player at pos, standing up and facing towards target.
func place_player(pos: Vector3, target: Vector3) -> void:
	var up := pos.normalized()
	var ahead := target - pos
	ahead -= up * ahead.dot(up)
	if ahead.length() < 0.01:
		ahead = Fixture.upright(up).z
	player.global_transform = Transform3D(Basis.looking_at(ahead.normalized(), up), pos)
	player.velocity = Vector3.ZERO
	player.align_up()

## Debug setup from user args (after `--`): seed=, time=, view=orbit|
## cave|screen|rover, lab (builds one ahead, researching), rig (builds one on the deposit nearest the pod and stands you by
## it), lamps=N (around you), spiders=N (in front of you), tool=,
## radial=N (the build menu up, N chosen, -1 for none), pitch=
## degrees, and shot=path.png and shot_at=seconds to save a screenshot and
## quit.
func _debug_setup() -> void:
	match _args.get("view", ""):
		"orbit":
			var orbit := Camera3D.new()
			orbit.far = 2000.0
			add_child(orbit)
			var from := Sun.dir_at(time).rotated(Vector3.UP, PI * 0.5) * 210.0 + Vector3.UP * 60.0
			orbit.look_at_from_position(from, Vector3.ZERO)
			orbit.make_current()
			player.process_mode = Node.PROCESS_MODE_DISABLED
		"screen":
			var front: Vector3 = pod.screen.global_position + pod.screen.global_basis.z * 2.6
			var spot: Array = terrain.surface_point(front)
			place_player(spot[0] + spot[0].normalized() * 0.3, pod.screen.global_position)
		"rover":
			var rover := rovers[0]
			var behind: Vector3 = rover.screen.global_position + rover.global_basis.z * 1.6
			var spot: Array = terrain.surface_point(behind)
			place_player(spot[0] + spot[0].normalized() * 0.3, rover.screen.global_position)
		"cave":
			var chamber := terrain.chambers[0]
			var centre := Vector3(chamber.x, chamber.y, chamber.z)
			await get_tree().physics_frame
			var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(centre, centre * 0.2, Terrain.ROCK_LAYER))
			place_player((hit.position if !hit.is_empty() else centre) + centre.normalized() * 0.3, centre * 2.0)
	if _args.has("rig"):
		var nearest := deposits[0]
		for deposit in deposits:
			if deposit.global_position.distance_to(pod.global_position) < nearest.global_position.distance_to(pod.global_position):
				nearest = deposit
		stock += Fixture.COST[&"drill"]
		build(&"drill", nearest.global_position, nearest.normal)
		var spot: Array = terrain.surface_point(nearest.global_position + Fixture.upright(nearest.normal).x * 7.0)
		place_player(spot[0] + spot[0].normalized() * 0.3, nearest.global_position)
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for i in int(_args.get("lamps", "0")):
		var up := player.global_position.normalized()
		var from := player.global_position + up * 1.5 + player.global_basis * Vector3(cos(i * 2.4) * 3.5, 0, sin(i * 2.4) * 3.5 - 3.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from - up * 10.0, Terrain.ROCK_LAYER))
		if !hit.is_empty():
			stock += Fixture.COST[&"lamp"]
			build(&"lamp", hit.position, hit.normal)
	for i in int(_args.get("spiders", "0")):
		var around := player.global_position + player.global_position.normalized() * 4.0 - player.global_basis.z * (5.0 + i * 1.2) + player.global_basis.x * ((i % 3) - 1) * 1.8
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(around, around * 0.7, Terrain.ROCK_LAYER))
		if !hit.is_empty():
			spawn_spider(hit.position)
	if _args.has("tool"):
		player.tool = StringName(_args.tool)
	if _args.has("radial"):
		player.radial_open = true
		player.radial_choice = int(_args.radial)
	if _args.has("lab"):
		player.rotate_object_local(Vector3.UP, PI)
		var ahead: Array = terrain.surface_point(player.global_position - player.global_basis.z * 5.0)
		stock += Fixture.COST[&"lab"] + Game.UPGRADES[&"tanks"].cost
		build(&"lab", ahead[0], ahead[1])
		built[-1].screen.pressed.call(&"tanks")
	player.debug_aim = _args.has("aim")
	if _args.has("pause"):
		hud.set_paused(true)
	if _args.has("pitch"):
		player.look(deg_to_rad(float(_args.pitch)))
	if _args.has("shot"):
		await get_tree().create_timer(float(_args.get("shot_at", "3"))).timeout
		var image := get_viewport().get_texture().get_image()
		image.save_png(_args.shot)
		print("saved ", _args.shot)
		get_tree().quit()
