class_name Game
extends Node3D
## One mission: drop onto the floor of a crater, get ore into the pod, and
## be beside it when it launches.
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
## more of them as the mission goes on, and go for soldiers, rovers out on
## the road, and what's been built. Sunlight sends them back under.
##
## Networked, the server (or solo) runs all of that; clients mirror it from
## snapshots, and send what their soldier does as requests (act()). Every
## soldier has their own health, warmth and pockets (stats); health and the
## rest read and write the local soldier's, or, while the server handles a
## request, the requester's.

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
	&"runners": {name = "BLADE RUNNERS", cost = 3, time = 25.0, text = "Walk and run as fast as you're built to"},
	&"jetpack": {name = "JETPACK", cost = 5, time = 35.0, text = "Hold Space in the air to fly"},
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
const SNAPSHOT_EVERY := 0.05
const SLOW_EVERY := 0.25
const MOVE_EVERY := 1.0 / 30.0
const RESTART_AFTER := 15.0
## Net ids below this are the world as generated, the same on every peer.
const FIRST_SPAWNED_ID := 1000

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
## Ore in the pod.
var stock := START_STOCK
var researched := {}
## Per soldier, by peer id: health, warmth, carried, lit_by, hurt,
## since_hurt.
var stats := {}
## Per soldier, by peer id: the local Player, or an Avatar.
var bodies := {}
## Whoever's in the pod commanding, by peer id, or 0. Their body's hidden
## and out of harm's way till they climb out.
var commander_peer := 0
var commander_view: Commander

var health: float:
	get: return _me().health
	set(value): _me().health = value
var warmth: float:
	get: return _me().warmth
	set(value): _me().warmth = value
var carried: int:
	get: return _me().carried
	set(value): _me().carried = value
var lit_by: String:
	get: return _me().lit_by
	set(value): _me().lit_by = value
## How recently you were hurt, 1 fading to 0, for the HUD.
var hurt: float:
	get: return _me().hurt
	set(value): _me().hurt = value

var terrain: Terrain
var sun: Sun
var player: Player
var pod: Fixture
var hud: Hud
## Lamps, panels, batteries, rigs and labs.
var built: Array[Fixture] = []
var ores: Array[Fixture] = []
var deposits: Array[Fixture] = []
var rovers: Array[Rover] = []
var spiders: Array[Spider] = []
## Net id -> node, for everything that has one.
var entities := {}

var _next_id := 1
var _acting := 0
var _nobody := _new_stats()
var _rng := RandomNumberGenerator.new()
var _light_check := 0.0
var _spawn_in := 2.0
var _snap_in := 0.0
var _slow_in := 0.0
var _move_in := 0.0
var _end_in := INF
var _args := {}


func _ready() -> void:
	Net.game = self
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else ""
	if Net.networked():
		seed_value = Net.seed_value
		time = Net.start_time
	else:
		seed_value = int(_args.seed) if _args.has("seed") else (_last_seed if _last_seed != 0 else randi())
		time = float(_args.get("time", "0"))
	_last_seed = 0
	_rng.seed = seed_value
	_add_environment()
	terrain = Terrain.new()
	add_child(terrain)
	terrain.generate(seed_value)
	sun = Sun.new()
	sun.time = time
	add_child(sun)
	_place_pod()
	_place_deposits()
	_place_ore()
	_next_id = FIRST_SPAWNED_ID
	if Net.authority():
		for i in START_ROVERS:
			_add_rover()
	if Net.has_local_player():
		var me := Net.local_id()
		player = Player.new()
		player.game = self
		player.set_meta("peer", me)
		add_child(player)
		stats[me] = _new_stats()
		bodies[me] = player
		_spawn_player()
		hud = Hud.new()
		hud.game = self
		add_child(hud)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if Net.mode == Net.Mode.CLIENT:
			Net.ready_to_play.rpc_id(1)
		_debug_setup()


func _physics_process(delta: float) -> void:
	if Net.authority():
		_simulate(delta)
		if Net.networked():
			_send_snapshots(delta)
	else:
		if state == State.PLAYING:
			time += delta
		sun.set_time(time)
		_move_in -= delta
		if player and _move_in <= 0.0:
			_move_in = MOVE_EVERY
			Net.move.rpc_id(1, player.global_position, player.global_rotation.y, player.pitch)


func _simulate(delta: float) -> void:
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
					_announce("Researched: %s" % String(UPGRADES[lab.researching].name).capitalize())
					lab.researching = &""
	var full := capacity()
	battery = clampf(battery + (power_in - power_out) * delta, 0.0, full)
	for fixture in built:
		if fixture.kind == &"battery":
			fixture.charge = battery / full
	if state != State.PLAYING:
		_end_in -= delta
		if _end_in <= 0.0 and Net.networked():
			_end_in = INF
			Net.restart()
		return
	for fixture in built:
		if fixture.kind == &"drill":
			fixture.drill(delta, fixture.sunlit or lit_at(fixture.global_position + fixture.normal * 1.0) != "", Fixture.DRILL_EVERY * (0.6 if has(&"drills") else 1.0))
	_spawn_spiders(delta)
	for rover in rovers.duplicate():
		if rover.health <= 0.0:
			rovers.erase(rover)
			entities.erase(rover.net_id)
			rover.queue_free()
	for fixture in built.duplicate():
		if fixture.health <= 0.0:
			_remove_built(fixture)
	for peer in bodies.keys():
		if peer != commander_peer:
			_look_after(peer, delta)
	if time >= MISSION:
		var aboard := 1 if commander_peer != 0 else 0
		for peer in bodies:
			if peer != commander_peer and (bodies[peer] as Node3D).global_position.distance_to(pod.global_position) < POD_RANGE + 2.0:
				aboard += 1
		if aboard > 0:
			_end(State.WON, "Extracted with %d of %d ore in the pod.%s" % [stock, QUOTA, " Quota met." if stock >= QUOTA else ""])
		else:
			_end(State.LOST, "The pod launched without anyone.")


## One soldier's warmth and health, and a trip back to the pod if they've
## frozen or been killed.
func _look_after(peer: int, delta: float) -> void:
	var s: Dictionary = stats[peer]
	var body: Node3D = bodies[peer]
	var head := body.global_position + Terrain.up_at(body.global_position) * 1.65
	var light := lit_at(head)
	if light == "" and battery > 0.0 and head.distance_to(pod.global_position) < POD_RANGE:
		light = "pod"
	s.lit_by = light
	s.warmth = clampf(s.warmth + (WARM_RATE if light != "" else -COLD_RATE * (0.5 if has(&"heated") else 1.0)) * delta, 0.0, 100.0)
	s.since_hurt += delta
	s.hurt = maxf(0.0, s.hurt - delta * 2.0)
	if s.since_hurt > HEAL_DELAY:
		s.health = minf(max_health(), s.health + HEAL_RATE * delta)
	if s.warmth <= 0.0:
		_respawn(peer, "You froze in the dark. Back at the pod, without what you carried.")
	elif s.health <= 0.0:
		_respawn(peer, "The spiders got you. Back at the pod, without what you carried.")


func _respawn(peer: int, why: String) -> void:
	stats[peer] = _new_stats()
	var spot := _spawn_spot_by_pod(peer)
	if peer == Net.local_id() and player:
		place_player(spot, pod.global_position)
		player._say(why)
	else:
		var body: Node3D = bodies[peer]
		body.global_position = spot
		if body is Avatar:
			(body as Avatar).target_position = spot
		Net.event.rpc_id(peer, &"respawn", [spot, why])


func _unhandled_input(event: InputEvent) -> void:
	if Net.networked():
		return
	if event is InputEventKey and event.pressed and !event.echo and event.physical_keycode == KEY_R and state != State.PLAYING:
		if event.shift_pressed:
			_last_seed = seed_value
		get_tree().reload_current_scene()


func _me() -> Dictionary:
	return stats.get(_acting if _acting != 0 else Net.local_id(), _nobody)


func _new_stats() -> Dictionary:
	return {health = HEALTH, warmth = 100.0, carried = 0, lit_by = "", hurt = 0.0, since_hurt = 99.0}


func _track(node: Node, id := 0) -> void:
	if id == 0:
		id = _next_id
		_next_id += 1
	node.net_id = id
	entities[id] = node


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


## Something the local soldier does to the world: done here if this is the
## server (or solo), asked of the server if not.
func act(action: StringName, args: Array) -> void:
	if Net.authority():
		handle(Net.local_id(), action, args)
	else:
		Net.request.rpc_id(1, action, args)


## Server: does what peer asked, as peer.
func handle(peer: int, action: StringName, args: Array) -> void:
	if !stats.has(peer):
		return
	_acting = peer
	var target: Node = entities.get(args[0], null) if !args.is_empty() and args[0] is int else null
	match action:
		&"mine":
			if target is Fixture and (ores.has(target) or deposits.has(target)):
				mine(target)
		&"pick_up":
			if target is Fixture and built.has(target):
				pick_up(target)
		&"empty_rig":
			if target is Fixture and built.has(target):
				empty_rig(target)
		&"hand_in":
			hand_in()
		&"build":
			if can_build(args[0], args[1]):
				build(args[0], args[1], args[2], args[3])
			elif OS.is_debug_build():
				print("refused to build %s (%s) at %s: stock %d, has cost %s, pod %.1f m away" % [args[0], type_string(typeof(args[0])), args[1], stock, Fixture.COST.has(args[0]), pod.global_position.distance_to(args[1])])
		&"press":
			if target and "screen" in target and target.screen:
				var reply: String = target.screen.pressed.call(args[1])
				if peer == Net.local_id():
					target.screen.reply(reply)
				else:
					Net.event.rpc_id(peer, &"reply", [args[0], reply])
		&"uncommand":
			if commander_peer == peer:
				_leave_command(peer)
		&"hit":
			if target is Spider:
				(target as Spider).hit(args[1])
		&"fling":
			if target is Spider:
				(target as Spider).fling(args[1], args[2])
		&"shot":
			for id in Net.peers:
				if id != peer and id != Net.local_id():
					Net.effect.rpc_id(id, &"tracer", args)
			if peer != Net.local_id() and player:
				player._tracer(args[0], args[1])
	_acting = 0


## Client: something the server's telling this peer alone.
func on_event(kind: StringName, args: Array) -> void:
	match kind:
		&"reply":
			var owner: Node = entities.get(args[0], null)
			if owner and "screen" in owner and owner.screen:
				owner.screen.reply(args[1])
		&"respawn":
			if player:
				place_player(args[0], pod.global_position)
				player._say(args[1])
		&"announce":
			if hud:
				hud.announce(args[0])
		&"command":
			if args[0]:
				_enter_view()
			else:
				_exit_view()
		&"tracer":
			if player:
				player._tracer(args[0], args[1])


func _announce(text: String) -> void:
	if hud:
		hud.announce(text)
	if Net.networked():
		for id in Net.peers:
			if id != Net.local_id():
				Net.event.rpc_id(id, &"announce", [text])


func add_soldier(peer: int) -> void:
	if bodies.has(peer):
		return
	stats[peer] = _new_stats()
	var avatar := _make_avatar(peer)
	var spot := _spawn_spot_by_pod(peer)
	avatar.global_position = spot
	avatar.target_position = spot


func _take_command(peer: int) -> void:
	commander_peer = peer
	var body: Node3D = bodies.get(peer, null)
	if body is Avatar:
		body.visible = false
	if peer == Net.local_id():
		_enter_view()
	else:
		Net.event.rpc_id(peer, &"command", [true])


func _leave_command(peer: int) -> void:
	commander_peer = 0
	var body: Node3D = bodies.get(peer, null)
	if body is Avatar:
		body.visible = true
	var spot := _spawn_spot_by_pod(peer)
	if peer == Net.local_id():
		_exit_view()
		place_player(spot, pod.global_position)
	else:
		if body:
			body.global_position = spot
			(body as Avatar).target_position = spot
		Net.event.rpc_id(peer, &"command", [false])
		Net.event.rpc_id(peer, &"respawn", [spot, "Out of the pod."])


## Local: from the soldier's eyes to the commander's.
func _enter_view() -> void:
	if !player:
		return
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.visible = false
	hud.visible = false
	if !commander_view:
		commander_view = Commander.new()
		commander_view.game = self
		add_child(commander_view)
	commander_view.enter()


func _exit_view() -> void:
	if !player:
		return
	if commander_view:
		commander_view.leave()
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.visible = true
	player.camera.make_current()
	hud.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func remove_soldier(peer: int) -> void:
	if commander_peer == peer:
		commander_peer = 0
	if bodies.has(peer) and bodies[peer] != player:
		bodies[peer].queue_free()
	bodies.erase(peer)
	stats.erase(peer)


func _make_avatar(peer: int) -> Avatar:
	var avatar := Avatar.new()
	avatar.peer = peer
	avatar.set_meta("peer", peer)
	add_child(avatar)
	var info: Dictionary = Net.peers.get(peer, {})
	avatar.set_label(info.get("name", "Soldier"))
	bodies[peer] = avatar
	return avatar


func remote_move(peer: int, pos: Vector3, yaw: float, pitch: float) -> void:
	if peer == commander_peer:
		return
	var body: Node3D = bodies.get(peer, null)
	if body is Avatar:
		var avatar := body as Avatar
		avatar.target_position = pos
		avatar.target_yaw = yaw
		avatar.pitch = pitch


func _send_snapshots(delta: float) -> void:
	_snap_in -= delta
	_slow_in -= delta
	var fast: Array = []
	var slow: Array = []
	if _snap_in <= 0.0:
		_snap_in = SNAPSHOT_EVERY
		fast = _fast_state()
	if _slow_in <= 0.0:
		_slow_in = SLOW_EVERY
		slow = _slow_state()
	for id in stats:
		if id == Net.local_id():
			continue
		if !fast.is_empty():
			var s: Dictionary = stats[id]
			Net.snapshot.rpc_id(id, [fast, [s.health, s.warmth, s.carried, s.lit_by, s.hurt]])
		if !slow.is_empty():
			Net.slow_snapshot.rpc_id(id, slow)


func _fast_state() -> Array:
	var soldiers: Array = []
	for peer in bodies:
		if peer == commander_peer:
			continue
		var body: Node3D = bodies[peer]
		var pitch: float = body.pitch if "pitch" in body else 0.0
		soldiers.append([peer, body.global_position, body.global_rotation.y, pitch])
	var spider_rows: Array = []
	for spider in spiders:
		spider_rows.append([spider.net_id, spider.global_position, spider.global_basis.get_rotation_quaternion(), spider.health])
	var rover_rows: Array = []
	for rover in rovers:
		rover_rows.append([rover.net_id, rover.global_position, rover.global_basis.get_rotation_quaternion(), rover.task, rover.order, rover.cargo, rover.health, rover.slot])
	return [time, battery, power_in, power_out, stock, state, outcome, soldiers, spider_rows, rover_rows, commander_peer]


func _slow_state() -> Array:
	var rows: Array = []
	for f in built:
		rows.append([f.net_id, f.kind, f.global_position, f.global_basis.get_rotation_quaternion(), f.normal, f.health, f.on, f.stored, f.stalled, f.researching, f.research_time, f.unpowered, f.charge, f.deposit.net_id if f.deposit else 0])
	var alive := PackedInt32Array()
	for ore in ores:
		alive.append(ore.net_id)
	return [rows, alive, researched.keys()]


## Client: the server's latest of everything that moves.
func apply_snapshot(data: Array) -> void:
	var f: Array = data[0]
	time = f[0]
	battery = f[1]
	power_in = f[2]
	power_out = f[3]
	stock = f[4]
	if state == State.PLAYING and f[5] != State.PLAYING:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	state = f[5]
	outcome = f[6]
	commander_peer = f[10]
	var seen := {}
	for row: Array in f[7]:
		var peer: int = row[0]
		seen[peer] = true
		if peer == Net.local_id():
			continue
		var avatar: Avatar = bodies.get(peer, null)
		if !avatar:
			avatar = _make_avatar(peer)
			avatar.global_position = row[1]
			stats[peer] = _new_stats()
		remote_move(peer, row[1], row[2], row[3])
	for peer in bodies.keys():
		if !seen.has(peer) and peer != Net.local_id():
			remove_soldier(peer)
	seen.clear()
	for row: Array in f[8]:
		seen[row[0]] = true
		var spider: Spider = entities.get(row[0], null)
		if !spider:
			spider = Spider.new()
			spider.game = self
			spider.puppet = true
			spider.position = row[1]
			add_child(spider)
			_track(spider, row[0])
			spiders.push_back(spider)
		spider.target_position = row[1]
		spider.target_basis = Basis(row[2])
		spider.show_health(row[3])
	for spider in spiders.duplicate():
		if !seen.has(spider.net_id):
			spiders.erase(spider)
			entities.erase(spider.net_id)
			spider.queue_free()
	seen.clear()
	for row: Array in f[9]:
		seen[row[0]] = true
		var rover: Rover = entities.get(row[0], null)
		if !rover:
			rover = Rover.new()
			rover.game = self
			rover.puppet = true
			rover.slot = row[7]
			add_child(rover)
			rover.global_position = row[1]
			_track(rover, row[0])
			rovers.push_back(rover)
			_send_presses(rover)
		rover.target_position = row[1]
		rover.target_basis = Basis(row[2])
		rover.task = row[3]
		rover.order = row[4]
		rover.cargo = row[5]
		rover.show_health(row[6])
	for rover in rovers.duplicate():
		if !seen.has(rover.net_id):
			rovers.erase(rover)
			entities.erase(rover.net_id)
			rover.queue_free()
	var mine: Array = data[1]
	var s: Dictionary = _me()
	s.health = mine[0]
	s.warmth = mine[1]
	s.carried = mine[2]
	s.lit_by = mine[3]
	s.hurt = mine[4]


## Client: the server's latest of what's built, what ore's left, and what's
## been researched.
func apply_slow(data: Array) -> void:
	var seen := {}
	for row: Array in data[0]:
		seen[row[0]] = true
		var fixture: Fixture = entities.get(row[0], null)
		if !fixture:
			fixture = Fixture.make(row[1], row[2], row[4])
			fixture.basis = Basis(row[3])
			if row[13] != 0 and entities.has(row[13]):
				fixture.deposit = entities[row[13]]
				fixture.deposit.rig = fixture
			add_child(fixture)
			_track(fixture, row[0])
			built.push_back(fixture)
			if fixture.kind == &"lab":
				_wire_lab_screen(fixture)
				_send_presses(fixture)
		fixture.health = row[5]
		if fixture.kind == &"lamp" and fixture.on != row[6]:
			fixture.set_on(row[6])
		fixture.stored = row[7]
		fixture.stalled = row[8]
		fixture.researching = row[9]
		fixture.research_time = row[10]
		fixture.unpowered = row[11]
		fixture.charge = row[12]
	for fixture in built.duplicate():
		if !seen.has(fixture.net_id):
			_remove_built(fixture)
	var alive := {}
	for id in data[1]:
		alive[id] = true
	for ore in ores.duplicate():
		if !alive.has(ore.net_id):
			ores.erase(ore)
			entities.erase(ore.net_id)
			ore.queue_free()
	for upgrade: StringName in data[2]:
		if !researched.has(upgrade):
			researched[upgrade] = true
			if hud:
				hud.announce("Researched: %s" % String(UPGRADES[upgrade].name).capitalize())


## Client: presses on this thing's screen go to the server.
func _send_presses(owner: Node) -> void:
	if Net.mode == Net.Mode.CLIENT:
		owner.screen.send = func(action: StringName) -> void: act(&"press", [owner.net_id, action])


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
		if action == &"tanks" and !has(&"jetpack"):
			return ["%s   NEEDS JETPACK" % upgrade.name, false, false]
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
		if action == &"tanks" and !has(&"jetpack"):
			return "RESEARCH THE JETPACK FIRST."
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


## Whether kind can go at pos; for a rig, pos is the deposit's.
func can_build(kind: StringName, pos: Vector3) -> bool:
	if !Fixture.COST.has(kind) or stock < Fixture.COST[kind]:
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


## Builds kind at pos; a lab turns its screen towards facing_from.
func build(kind: StringName, pos: Vector3, normal: Vector3, facing_from := Vector3.INF) -> void:
	stock -= Fixture.COST[kind]
	var fixture: Fixture
	if kind == &"drill":
		var deposit := deposit_at(pos)
		fixture = Fixture.make(kind, deposit.global_position, deposit.normal)
		fixture.deposit = deposit
		deposit.rig = fixture
	else:
		fixture = Fixture.make(kind, pos, normal)
	if kind == &"lab" and facing_from != Vector3.INF:
		var towards := facing_from - pos
		towards -= normal * towards.dot(normal)
		if towards.length() > 0.1:
			fixture.basis = Basis.looking_at(-towards.normalized(), normal)
	add_child(fixture)
	_track(fixture)
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
	entities.erase(fixture.net_id)
	fixture.queue_free()


## Mining by hand: an ore cluster comes away whole, a deposit a piece at a
## time.
func mine(ore: Fixture) -> void:
	if ore.kind == &"deposit":
		carried += 1
		return
	carried += ore.amount
	ores.erase(ore)
	entities.erase(ore.net_id)
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
		if action == &"command":
			if commander_peer == 0:
				return ["TAKE COMMAND", true, false]
			var info: Dictionary = Net.peers.get(commander_peer, {})
			return ["COMMANDER: %s" % String(info.get("name", "YOU" if commander_peer == Net.local_id() else "TAKEN")).to_upper(), false, true]
		if action == &"rover":
			return ["PRINT ROVER   %d ORE" % Fixture.COST[&"rover"], stock >= Fixture.COST[&"rover"], false]
		return ["HAND IN ORE   %d CARRIED" % carried, carried > 0, false]
	screen.pressed = func(action: StringName) -> String:
		if action == &"command":
			if commander_peer != 0:
				return "THE SEAT'S TAKEN."
			_take_command(_acting if _acting != 0 else Net.local_id())
			return ""
		if action == &"rover":
			if print_rover():
				return "ROVER PRINTED. %d ON THE ROSTER." % rovers.size()
			return "NOT ENOUGH ORE BANKED: A ROVER NEEDS %d." % Fixture.COST[&"rover"]
		if carried == 0:
			return "NOTHING TO HAND IN."
		var amount := carried
		hand_in()
		return "%d ORE BANKED." % amount
	_send_presses(pod)


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


## The nearest thing a spider would bite: a soldier, a rover out on the
## road, or something built. Soldiers count as a little nearer than they
## are.
func spider_target(spider: Spider) -> Node3D:
	var from := spider.global_position
	var best: Node3D = null
	var best_distance := Spider.SIGHT
	var candidates: Array[Node3D] = []
	for peer in bodies:
		if peer != commander_peer:
			candidates.push_back(bodies[peer])
	for rover in rovers:
		if rover.exposed():
			candidates.push_back(rover)
	candidates.append_array(built)
	for candidate in candidates:
		var distance := from.distance_to(candidate.global_position) * (0.75 if candidate.has_meta("peer") else 1.0)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## How close a spider has to be to bite target.
func bite_reach(target: Node3D) -> float:
	if target is Rover:
		return 2.0
	if target.has_meta("peer"):
		return 1.7
	if target is Fixture and (target as Fixture).kind == &"drill":
		return 2.8
	return 1.9


func damage(target: Node3D, amount: float) -> void:
	if state != State.PLAYING:
		return
	if target.has_meta("peer"):
		var s: Dictionary = stats.get(target.get_meta("peer"), _nobody)
		s.health -= amount
		s.hurt = 1.0
		s.since_hurt = 0.0
	elif target is Rover:
		(target as Rover).damage(amount)
	elif target is Fixture:
		(target as Fixture).health -= amount


func remove_spider(spider: Spider) -> void:
	spiders.erase(spider)
	entities.erase(spider.net_id)
	spider.queue_free()


func spawn_spider(spot: Vector3) -> void:
	var spider := Spider.new()
	spider.game = self
	spider.position = spot
	add_child(spider)
	_track(spider)
	spiders.push_back(spider)


func _add_rover() -> void:
	var rover := Rover.new()
	rover.game = self
	rover.slot = rovers.size()
	add_child(rover)
	rover.global_position = rover.park_point()
	_track(rover)
	rovers.push_back(rover)


## Brings spiders up out of the ground, somewhere unlit not far from a
## soldier, a rover, or something built.
func _spawn_spiders(delta: float) -> void:
	_spawn_in -= delta
	if _spawn_in > 0.0:
		return
	var progress := time / MISSION
	_spawn_in = lerpf(SPAWN_GAP_START, SPAWN_GAP_END, progress)
	if spiders.size() >= roundi(lerpf(SPIDERS_START, SPIDERS_END, progress)):
		return
	var near: Array[Node3D] = []
	for peer in bodies:
		if peer != commander_peer:
			near.append_array([bodies[peer], bodies[peer], bodies[peer]])
	near.append_array(rovers)
	near.append_array(built)
	if near.is_empty():
		return
	var focus: Node3D = near[_rng.randi() % near.size()]
	for attempt in 4:
		var spot := _spawn_spot(focus.global_position)
		if spot != Vector3.INF:
			spawn_spider(spot)
			return


## Somewhere dark on the ground 12-28 m from around, inside the crater and
## not too near any soldier, or INF if this try didn't find one.
func _spawn_spot(around: Vector3) -> Vector3:
	var up := Terrain.up_at(around)
	var frame := Fixture.upright(up)
	var angle := _rng.randf() * TAU
	var start := around + up * 6.0 + (frame.x * cos(angle) + frame.z * sin(angle)) * _rng.randf_range(12.0, 28.0)
	if Vector2(start.x, start.z).length() > Terrain.FLOOR_RADIUS or terrain.density(start) < 0.0:
		return Vector3.INF
	var query := PhysicsRayQueryParameters3D.create(start, start - up * 24.0, Terrain.ROCK_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	var spot: Vector3 = hit.position
	for peer in bodies:
		if peer != commander_peer and spot.distance_to((bodies[peer] as Node3D).global_position) < 10.0:
			return Vector3.INF
	if lit_at(spot + up * 0.6) != "":
		return Vector3.INF
	return spot


func _end(new_state: State, text: String) -> void:
	state = new_state
	outcome = text
	_end_in = RESTART_AFTER
	if player:
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


## The pod comes down on open, flat ground near the middle of the crater.
func _place_pod() -> void:
	var spots: Array[Array] = terrain.surface_spots.duplicate()
	_shuffle(spots)
	var landing: Array = spots[0]
	for spot in spots:
		if Vector2(spot[0].x, spot[0].z).length() < 20.0 and spot[1].y > 0.97:
			landing = spot
			break
	pod = Fixture.make(&"pod", landing[0] - Vector3.UP * 0.4, Vector3.UP)
	add_child(pod)
	_track(pod)
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
		var up: Vector3 = (spot[1] + Terrain.up_at(p)).normalized()
		var deposit := Fixture.make(&"deposit", p - up * 0.3, up)
		add_child(deposit)
		_track(deposit)
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
		_track(ore)
		ores.push_back(ore)


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Variant = list[i]
		list[i] = list[j]
		list[j] = t


## Somewhere round the pod for a soldier to start, spread out by peer.
func _spawn_spot_by_pod(peer: int) -> Vector3:
	var frame := Fixture.upright(pod.normal)
	var angle := 0.4 + (peer % 7) * 0.9
	var spot: Array = terrain.surface_point(pod.global_position + (frame.x * cos(angle) + frame.z * sin(angle)) * 5.0)
	return spot[0] + Terrain.up_at(spot[0]) * 0.6


func _spawn_player() -> void:
	var side := Fixture.upright(pod.normal).x
	var spot: Array = terrain.surface_point(pod.global_position + side * 5.0)
	var at: Vector3 = spot[0] + Terrain.up_at(spot[0]) * 0.6
	if Net.networked():
		at = _spawn_spot_by_pod(Net.local_id())
	place_player(at, pod.global_position)


## Puts the player at pos, standing up and facing towards target.
func place_player(pos: Vector3, target: Vector3) -> void:
	var up := Terrain.up_at(pos)
	var ahead := target - pos
	ahead -= up * ahead.dot(up)
	if ahead.length() < 0.01:
		ahead = Fixture.upright(up).z
	player.global_transform = Transform3D(Basis.looking_at(ahead.normalized(), up), pos)
	player.velocity = Vector3.ZERO
	player.align_up()


## Debug setup from user args (after `--`): seed=, time=, view=overview|
## cave|screen|rover, lab (builds one ahead, researching), rig (builds one
## on the deposit nearest the pod and stands you by it), lamps=N (around
## you), spiders=N (in front of you), tool=, radial=N (the build menu up, N
## chosen, -1 for none), aim, hammer, pause, pitch=degrees, and
## shot=path.png and shot_at=seconds to save a screenshot and quit.
func _debug_setup() -> void:
	match _args.get("view", ""):
		"overview":
			var overview := Camera3D.new()
			overview.far = 2000.0
			add_child(overview)
			overview.look_at_from_position(Vector3(0, 110, 120), Vector3(0, 0, 5))
			overview.make_current()
			player.process_mode = Node.PROCESS_MODE_DISABLED
		"screen":
			var front: Vector3 = pod.screen.global_position + pod.screen.global_basis.z * 2.6
			var spot: Array = terrain.surface_point(front)
			place_player(spot[0] + Terrain.up_at(spot[0]) * 0.3, pod.screen.global_position)
		"rover":
			if !rovers.is_empty():
				var rover := rovers[0]
				var behind: Vector3 = rover.screen.global_position + rover.global_basis.z * 1.6
				var spot: Array = terrain.surface_point(behind)
				place_player(spot[0] + Terrain.up_at(spot[0]) * 0.3, rover.screen.global_position)
		"cave":
			var chamber := terrain.chambers[0]
			var centre := Vector3(chamber.x, chamber.y, chamber.z)
			await get_tree().physics_frame
			var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(centre, centre - Vector3.UP * 12.0, Terrain.ROCK_LAYER))
			place_player((hit.position if !hit.is_empty() else centre) + Vector3.UP * 0.3, centre + Vector3(5, 0, 0))
	if _args.has("rig"):
		var nearest := deposits[0]
		for deposit in deposits:
			if deposit.global_position.distance_to(pod.global_position) < nearest.global_position.distance_to(pod.global_position):
				nearest = deposit
		stock += Fixture.COST[&"drill"]
		build(&"drill", nearest.global_position, nearest.normal)
		var spot: Array = terrain.surface_point(nearest.global_position + Fixture.upright(nearest.normal).x * 7.0)
		place_player(spot[0] + Terrain.up_at(spot[0]) * 0.3, nearest.global_position)
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for i in int(_args.get("lamps", "0")):
		var up := Terrain.up_at(player.global_position)
		var from := player.global_position + up * 1.5 + player.global_basis * Vector3(cos(i * 2.4) * 3.5, 0, sin(i * 2.4) * 3.5 - 3.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from - up * 10.0, Terrain.ROCK_LAYER))
		if !hit.is_empty():
			stock += Fixture.COST[&"lamp"]
			build(&"lamp", hit.position, hit.normal)
	for i in int(_args.get("spiders", "0")):
		var around := player.global_position + Terrain.up_at(player.global_position) * 4.0 - player.global_basis.z * (5.0 + i * 1.2) + player.global_basis.x * ((i % 3) - 1) * 1.8
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(around, around - Terrain.up_at(around) * 12.0, Terrain.ROCK_LAYER))
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
		build(&"lab", ahead[0], ahead[1], player.global_position)
		built[-1].screen.pressed.call(&"tanks")
	player.debug_aim = _args.has("aim")
	if _args.has("hammer"):
		player._switch(&"hammer")
	if _args.has("pause"):
		hud.set_paused(true)
	if _args.has("pitch"):
		player.look(deg_to_rad(float(_args.pitch)))
	if _args.has("command"):
		_take_command(Net.local_id())
	if _args.has("probe"):
		_probe(_args.probe)
	if _args.has("shot"):
		await get_tree().create_timer(float(_args.get("shot_at", "3"))).timeout
		var image := get_viewport().get_texture().get_image()
		image.save_png(_args.shot)
		print("saved ", _args.shot)
		get_tree().quit()


## Debug, networked: a scripted client. "builder" builds, mines, hands in
## and prints a rover, checking each reached the server; "walker" walks in
## circles round the pod; "stander" stands by the pod's screen. Both report what they see, then quit.
func _probe(kind: String) -> void:
	var tree := get_tree()
	var report := func(tag: String) -> void:
		var others := []
		for peer in bodies:
			if peer != Net.local_id():
				others.append("%d@%s" % [peer, (bodies[peer] as Node3D).global_position.snapped(Vector3.ONE * 0.1)])
		print("[%s %s] t=%.1f stock %d carried %d | ores %d built %d rovers %d spiders %d | others %s" % [kind, tag, time, stock, carried, ores.size(), built.size(), rovers.size(), spiders.size(), others])
	await tree.create_timer(3.0).timeout
	report.call("joined")
	if kind == "commander":
		act(&"press", [pod.net_id, &"command"])
		await tree.create_timer(2.0).timeout
		print("[commander] in the pod: commander %d (me %d), view %s" % [commander_peer, Net.local_id(), commander_view != null and commander_view.visible])
		act(&"uncommand", [])
		await tree.create_timer(2.0).timeout
		print("[commander] out: commander %d, view %s, player visible %s" % [commander_peer, commander_view != null and commander_view.visible, player.visible])
	elif kind == "stander":
		var spot: Vector3 = pod.screen.global_position + pod.screen.global_basis.z * 1.6 + pod.screen.global_basis.x * 1.2
		for i in 60:
			player.global_position = terrain.surface_point(spot)[0] + Vector3.UP * 0.1
			await tree.create_timer(0.25).timeout
	elif kind == "walker":
		var centre := pod.global_position
		for i in 60:
			var angle := i * 0.2
			player.global_position = terrain.surface_point(centre + Vector3(cos(angle), 0, sin(angle)) * 9.0)[0] + Vector3.UP * 0.5
			await tree.create_timer(0.2).timeout
		report.call("walked")
	else:
		var ahead: Array = terrain.surface_point(player.global_position + Vector3(3, 0, 3))
		var stock_before := stock
		act(&"build", [&"lamp", ahead[0], ahead[1], player.global_position])
		var nearest := ores[0]
		for ore in ores:
			if ore.global_position.distance_to(player.global_position) < nearest.global_position.distance_to(player.global_position):
				nearest = ore
		act(&"mine", [nearest.net_id])
		await tree.create_timer(1.0).timeout
		report.call("built+mined")
		print("[builder] lamp built: %s (stock %d -> %d), carrying %d" % [built.any(func(f: Fixture) -> bool: return f.kind == &"lamp"), stock_before, stock, carried])
		act(&"press", [pod.net_id, &"hand_in"])
		await tree.create_timer(1.0).timeout
		act(&"press", [pod.net_id, &"rover"])
		await tree.create_timer(1.5).timeout
		report.call("handed in + rover")
		for i in 8:
			await tree.create_timer(1.0).timeout
			report.call("watching")
	tree.quit()
