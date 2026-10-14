class_name Game
extends Node3D
## One mission: drop onto a patch of asteroid inside a hologram wall, get ore into the pod, and
## be beside it when it launches.
##
## Power is one shared battery, filled by sunlight on the pod and on any
## panels you build, and drained by lamps, which light themselves whenever
## the sun's off them. Out of light, sun or lamp, your suit cools, and if
## it runs out you freeze.
##
## Ore is banked in the pod: what you carry counts once you hand it in.
## Build a drill rig over a deposit and it drills while it's lit; cables
## carry what it drills home. What's built is paid for from the bank, and
## what's in it at launch is the score.
##
## The commander, in the pod, places what gets built, as blueprints that
## soldiers hammer up, paid for a blow at a time; strings the cables; and
## picks what the labs research and what gear armories make for whom.
##
## Foundries smelt ore into alloy, which pays for batteries and the bigger
## upgrades. The commander strings cables between pylons, rigs, foundries
## and the pod to carry ore and alloy about, and switches things off to
## save power at night, or to quiet them: spiders can hear working rigs,
## foundries and labs from further than they can see.
##
## At nightfall bug holes tear open out in the dark, more of them each
## night, and spiders climb out of them, more as the mission goes on and
## the more players there are, and go for soldiers, what's been built, and
## the pod. Sunlight sends them back
## under. If they tear the pod open, nobody's going home; hammering it
## patches it up. Soldiers carry flares, which recharge, to light the dark
## for a while.
##
## Networked, the server (or solo) runs all of that; clients mirror it from
## snapshots, and send what their soldier does as requests (act()). Every
## soldier has their own health, warmth and pockets (stats); health and the
## rest read and write the local soldier's, or, while the server handles a
## request, the requester's.

enum State { PLAYING, WON, LOST }

## Seconds over which the spiders' spawning climbs to its END numbers;
## it keeps climbing past them, so staying on gets riskier.
const RAMP := 720.0
## Seconds from the commander calling the launch to lift-off.
const LAUNCH_COUNTDOWN := 45.0
## Calling it spools the engines up, and the noise tears this many bug
## holes open nearer the pod (one more with three players or more), whose
## frenzied spiders come for the pod, day or night, this often, up to
## this many at once (both for one player, scaled like the night's).
const EXTRACTION_HOLES := 2
const EXTRACTION_NEAR := 16.0
const EXTRACTION_FAR := 30.0
const EXTRACTION_GAP := 1.4
const EXTRACTION_SPIDERS := 6
const QUOTA := 100
const BATTERY := 100.0
const START_BATTERY := 60.0
const POD_SOLAR := 0.8
const PANEL_SOLAR := 1.6
const LAMP_DRAW := 0.4
const BATTERY_BANK := 80.0
const LAB_DRAW := 0.6
const FOUNDRY_DRAW := 1.0
## The tech tree. Each costs ore, and some alloy too, paid when a lab
## starts it, and `needs` another researched first. `at` is its place in
## the commander's tree: column (how deep), row.
const UPGRADES := {
	&"gun": {name = "RIFLE", cost = 3, alloy = 0, time = 25.0, at = Vector2i(0, 0), text = "A hitscan rifle (1, or the wheel); until then, only the hammer"},
	&"rounds": {name = "OVERCHARGED ROUNDS", cost = 3, alloy = 3, time = 45.0, needs = &"gun", at = Vector2i(1, 0), text = "Double damage from the rifle"},
	&"stabiliser": {name = "STABILISER", cost = 4, alloy = 0, time = 30.0, needs = &"gun", at = Vector2i(1, 1), text = "Half the bloom from firing, tighter at rest"},
	&"runners": {name = "BLADE RUNNERS", cost = 3, alloy = 0, time = 25.0, at = Vector2i(0, 2), text = "Walk, run and slide as fast as you're built to"},
	&"jetpack": {name = "JETPACK", cost = 3, alloy = 2, time = 35.0, needs = &"runners", at = Vector2i(1, 2), text = "Hold Space in the air to fly"},
	&"tanks": {name = "BIGGER TANKS", cost = 3, alloy = 0, time = 30.0, needs = &"jetpack", at = Vector2i(2, 2), text = "The jetpack burns fuel 40% slower"},
	&"grapple": {name = "GRAPPLE", cost = 4, alloy = 0, time = 30.0, needs = &"runners", at = Vector2i(1, 3), text = "Middle mouse: reel yourself to rock, or tug a spider to you"},
	&"heated": {name = "HEATED SUIT", cost = 4, alloy = 0, time = 30.0, at = Vector2i(0, 4), text = "Cold takes twice as long to freeze you"},
	&"armour": {name = "ARMOUR PLATING", cost = 3, alloy = 3, time = 40.0, at = Vector2i(0, 5), text = "+50 max health"},
	&"drills": {name = "FASTER DRILLS", cost = 4, alloy = 2, time = 45.0, at = Vector2i(0, 6), text = "Rigs drill 40% faster"},
	&"cables": {name = "FAST CABLES", cost = 3, alloy = 2, time = 40.0, needs = &"drills", at = Vector2i(1, 6), text = "Cables carry ore and alloy twice as fast"},
	&"lamps": {name = "EFFICIENT LAMPS", cost = 4, alloy = 0, time = 30.0, at = Vector2i(0, 7), text = "Lamps draw half the power"},
}
## Personal gear: once researched, the commander has an armory make it
## for each soldier, one at a time, for this much; it waits there for
## them to collect. Lost if you're not got back up when you fall.
const GEAR := {
	&"gun": {cost = 2, alloy = 0, time = 12.0},
	&"runners": {cost = 2, alloy = 0, time = 10.0},
	&"jetpack": {cost = 2, alloy = 1, time = 18.0},
	&"grapple": {cost = 2, alloy = 0, time = 12.0},
	&"heated": {cost = 2, alloy = 0, time = 12.0},
	&"armour": {cost = 1, alloy = 2, time = 18.0},
}
const ARMORY_DRAW := 0.6
## Suit warmth, out of 100: how fast it's lost in the dark and regained in
## light.
const COLD_RATE := 100.0 / 45.0
const WARM_RATE := 100.0 / 6.0
const POD_RANGE := 6.0
const SURFACE_ORE := 16
const DEPOSITS := 8
## The first this many are somewhere you can walk to from the pod without
## climbing.
const REACHABLE_DEPOSITS := 4
const START_STOCK := 10
const HEALTH := 100.0
## Health comes back this fast once nothing's hurt you for a while.
const HEAL_RATE := 4.0
const HEAL_DELAY := 4.0
## Seconds a fallen soldier lies down for, waiting to be revived, before
## they're back at the pod; how long E's held on them to revive them, from
## how near, and what they get back up with.
const DOWN_TIME := 30.0
const REVIVE_TIME := 2.5
const REVIVE_REACH := 2.5
const REVIVE_HEALTH := 0.5
## Spiders, for one player: the most alive at once grows from the first to
## the second over the mission, and they come up this many seconds apart.
## Each player past the first adds half as much again.
const SPIDERS_START := 3
const SPIDERS_END := 8
const SPAWN_GAP_START := 5.0 / 3.0
const SPAWN_GAP_END := 2.5 / 3.0
## Bug holes open this far from the pod, at least this far apart.
const HOLE_NEAR := 28.0
const HOLE_FAR := 46.0
const HOLE_APART := 18.0
const SNAPSHOT_EVERY := 0.05
const SLOW_EVERY := 0.25
const MOVE_EVERY := 1.0 / 30.0
const RESTART_AFTER := 15.0
const FLARES := 4
const FLARE_RECHARGE := 20.0
const PING_TIME := 8.0
const POD_ALERT_EVERY := 10.0
const REPAIR := 25.0
## The pod patches itself this fast, while there's power and nothing's
## bitten it for a while.
const POD_MEND := 1.5
const POD_MEND_DELAY := 8.0
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
## When the pod lifts off: INF until the commander calls the launch.
var launch_at := INF
var stock := START_STOCK
var alloy := 0
var researched := {}
## Upgrades the commander's queued, in order; an idle lab takes the first
## it can start (what it needs done, and the bank can pay).
var research_queue: Array[StringName] = []
## Gear the commander's ordered, [item, peer], in order; an idle armory
## takes the first it can make. Then made, waiting to be collected.
var orders: Array = []
var racked: Array = []
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
var flares_left: int:
	get: return _me().flares
## Seconds left lying down before you're back at the pod, or -1 standing.
var down_left: float:
	get: return _me().get("down", -1.0)

var terrain: Terrain
var sun: Sun
var player: Player
var pod: Fixture
var hud: Hud
## Lamps, panels, batteries, rigs and labs.
var built: Array[Fixture] = []
## What the commander's placed and soldiers haven't hammered up yet.
var blueprints: Array[Fixture] = []
var ores: Array[Fixture] = []
var deposits: Array[Fixture] = []
var spiders: Array[Spider] = []
var flares: Array[Flare] = []
var holes: Array[Hole] = []
var links: Array[Link] = []
## Lately pinged spots: {position, name, commander, age, peer}.
var pings: Array[Dictionary] = []
## Net id -> node, for everything that has one.
var entities := {}

var _next_id := 1
var _acting := 0
var _nobody := _new_stats()
var _rng := RandomNumberGenerator.new()
var _light_check := 0.0
var _spawn_in := 2.0
var _frenzy_in := 0.0
var _night := false
var _snap_in := 0.0
var _slow_in := 0.0
var _move_in := 0.0
var _end_in := INF
var _pod_alert := 0.0
var _pod_bitten := 99.0
var _link_turn := 0
## When the pod was last bitten, for the music.
var _pod_hurt_at := -INF
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
	if player:
		_feed_music()
	for ping in pings:
		ping.age += delta
	pings.assign(pings.filter(func(p: Dictionary) -> bool: return p.age < PING_TIME))
	if Net.authority():
		_simulate(delta)
		if Net.networked():
			_send_snapshots(delta)
	else:
		if state == State.PLAYING:
			time += delta
		sun.set_time(time)
		for link in links:
			link.advance(delta, cable_speed())
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
			var want := fixture.enabled and !fixture.sunlit and battery > 0.0
			if want != fixture.on:
				fixture.set_on(want)
			if fixture.on:
				power_out += LAMP_DRAW * (0.5 if has(&"lamps") else 1.0)
		elif fixture.kind == &"foundry" and state == State.PLAYING:
			fixture.smelt(delta, battery > 0.0)
			if fixture.stalled == "":
				power_out += FOUNDRY_DRAW
		elif fixture.kind == &"turret" and state == State.PLAYING:
			_run_turret(fixture, delta)
	for lab in built:
		if lab.kind == &"lab" and lab.researching != &"" and lab.enabled and state == State.PLAYING:
			lab.unpowered = battery <= 0.0
			if !lab.unpowered:
				power_out += LAB_DRAW
				lab.research_time += delta
				if lab.research_time >= UPGRADES[lab.researching].time:
					researched[lab.researching] = true
					_announce("Researched: %s" % String(UPGRADES[lab.researching].name).capitalize(), &"researched")
					lab.researching = &""
		for armory in built:
			if armory.kind == &"armory" and armory.researching != &"" and armory.enabled and state == State.PLAYING:
				armory.unpowered = battery <= 0.0
				if !armory.unpowered:
					power_out += ARMORY_DRAW
					armory.research_time += delta
					if armory.research_time >= GEAR[armory.researching].time:
						racked.append([armory.researching, armory.made_for])
						_announce("%s made for %s: collect it at the armory" % [String(UPGRADES[armory.researching].name).capitalize(), name_of(armory.made_for)], &"built")
						armory.researching = &""
	if state == State.PLAYING:
		_run_queue()
		_run_orders()
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
	_move_goods(delta)
	_spawn_spiders(delta)
	for fixture in built.duplicate():
		if fixture.health <= 0.0:
			_remove_built(fixture)
	_pod_alert = maxf(0.0, _pod_alert - delta)
	_pod_bitten += delta
	if _pod_bitten > POD_MEND_DELAY and battery > 0.0:
		pod.health = minf(pod.max_health, pod.health + POD_MEND * delta)
	if pod.health <= 0.0:
		_end(State.LOST, "The spiders tore the pod open. Nobody's going home.")
		return
	for peer in bodies.keys():
		if peer != commander_peer:
			_look_after(peer, delta)
	if time >= launch_at:
		var aboard := 1 if commander_peer != 0 else 0
		for peer in bodies:
			if peer != commander_peer and (bodies[peer] as Node3D).global_position.distance_to(pod.global_position) < POD_RANGE + 2.0:
				aboard += 1
		if aboard > 0:
			_end(State.WON, "Extracted with %d of %d ore in the pod.%s" % [stock, QUOTA, " Quota met." if stock >= QUOTA else ""])
		else:
			_end(State.LOST, "The pod launched without anyone.")


## Tells the soundtrack how things stand where you are (or at the pod,
## from the command chair).
func _feed_music() -> void:
	var commanding := commander_view != null and commander_view.visible
	var centre := pod.global_position if commanding else player.global_position
	var near := 0
	for spider in spiders:
		if spider.global_position.distance_to(centre) < 30.0:
			near += 1
	Music.in_game = state == State.PLAYING
	Music.night = Sun.dir_at(time).y < 0.05
	Music.danger = near
	Music.alarm = time - _pod_hurt_at < 6.0
	Music.final = launch_at < INF


## One soldier's warmth and health, and a trip back to the pod if they've
## frozen or been killed.
func _look_after(peer: int, delta: float) -> void:
	var s: Dictionary = stats[peer]
	var body: Node3D = bodies[peer]
	if s.down >= 0.0:
		s.down -= delta
		if s.down <= 0.0:
			_respawn(peer, "Nobody got to you in time. Back at the pod, without what you carried or wore.")
		return
	var head := body.global_position + Terrain.up_at(body.global_position) * 1.65
	var light := lit_at(head)
	if light == "" and battery > 0.0 and head.distance_to(pod.global_position) < POD_RANGE:
		light = "pod"
	s.lit_by = light
	s.warmth = clampf(s.warmth + (WARM_RATE if light != "" else -COLD_RATE * (0.5 if equipped(&"heated", peer) else 1.0)) * delta, 0.0, 100.0)
	s.since_hurt += delta
	s.hurt = maxf(0.0, s.hurt - delta * 2.0)
	if s.flares < FLARES:
		s.flare_charge += delta
		if s.flare_charge >= FLARE_RECHARGE:
			s.flare_charge = 0.0
			s.flares += 1
	if s.since_hurt > HEAL_DELAY:
		s.health = minf(max_health(peer), s.health + HEAL_RATE * delta)
	if s.warmth <= 0.0:
		_fall(peer, "You froze in the dark.")
	elif s.health <= 0.0:
		_fall(peer, "The spiders got you.")


## A soldier's fallen: down where they are for DOWN_TIME, for another to
## revive; or, with nobody else on their feet to, straight back to the pod.
func _fall(peer: int, why: String) -> void:
	var helpers := bodies.keys().filter(func(other: int) -> bool: return other != peer and other != commander_peer and !is_down(bodies[other]))
	if helpers.is_empty():
		_respawn(peer, why + " Back at the pod, without what you carried or wore.")
		return
	var s: Dictionary = stats[peer]
	s.down = DOWN_TIME
	s.health = 0.0
	_show_down(peer, true)
	sound(&"bite", bodies[peer].global_position)
	_announce("%s is down! Hold E on them to get them up." % name_of(peer), &"alarm")


## Whether a soldier's body is lying down.
func is_down(body: Node) -> bool:
	return body != null and body.has_meta("peer") and stats.get(body.get_meta("peer"), _nobody).get("down", -1.0) >= 0.0


func _show_down(peer: int, on: bool) -> void:
	var body: Node3D = bodies.get(peer, null)
	if body is Avatar:
		(body as Avatar).set_down(on)


func name_of(peer: int) -> String:
	var info: Dictionary = Net.peers.get(peer, {})
	return info.get("name", Net.player_name if peer == Net.local_id() else "Soldier")


func _respawn(peer: int, why: String) -> void:
	stats[peer] = _new_stats()
	_show_down(peer, false)
	var spot := _spawn_spot_by_pod(peer)
	if peer == Net.local_id() and player:
		place_player(spot, pod.global_position)
		player._say(why)
		Sfx.play(&"respawn")
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
	return {health = HEALTH, warmth = 100.0, carried = 0, lit_by = "", hurt = 0.0, since_hurt = 99.0, flares = FLARES, flare_charge = 0.0, down = -1.0, gear = []}


func _track(node: Node, id := 0) -> void:
	if id == 0:
		id = _next_id
		_next_id += 1
	node.net_id = id
	entities[id] = node


func has(upgrade: StringName) -> bool:
	return researched.has(upgrade)


## Whether a soldier (by default the local one, or the one acting) has
## that gear on.
func equipped(item: StringName, peer := 0) -> bool:
	var s: Dictionary = _me() if peer == 0 else stats.get(peer, _nobody)
	return s.gear.has(item)


func max_health(peer := 0) -> float:
	return HEALTH + (50.0 if equipped(&"armour", peer) else 0.0)


func cable_speed() -> float:
	return Link.SPEED * (2.0 if has(&"cables") else 1.0)


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
	if stats[peer].get("down", -1.0) >= 0.0:
		# Lying down, all you can do is give up.
		if action == &"give_up":
			_respawn(peer, "Back at the pod, without what you carried or wore.")
		return
	_acting = peer
	var target: Node = entities.get(args[0], null) if !args.is_empty() and args[0] is int else null
	match action:
		&"mine":
			if target is Fixture and (ores.has(target) or deposits.has(target)):
				sound(&"mine", target.global_position)
				mine(target)
		&"pick_up":
			if target is Fixture and built.has(target):
				sound(&"pick_up", target.global_position)
				pick_up(target)
		&"empty_rig":
			if target is Fixture and built.has(target):
				sound(&"pick_up", target.global_position)
				empty_rig(target)
		&"load":
			if target is Fixture and built.has(target) and target.kind == &"turret":
				sound(&"pick_up", target.global_position)
				load_turret(target)
		&"hand_in":
			sound(&"hand_in", pod.global_position)
			hand_in()
		&"blueprint":
			if peer == commander_peer and can_build(args[0], args[1], args[2]):
				place_blueprint(args[0], args[1], args[2], args[3])
		&"cancel":
			if peer == commander_peer and target is Fixture and blueprints.has(target):
				stock += target.paid()
				alloy += target.paid(true)
				_unlink_all(target)
				_remove_blueprint(target)
		&"switch":
			if peer == commander_peer and target is Fixture and built.has(target) and Fixture.SWITCHED.has(target.kind):
				target.enabled = !target.enabled
		&"link":
			var onto: Node = entities.get(args[1], null)
			if peer != commander_peer and target is Fixture and onto is Fixture and can_link(target, onto) == "":
				sound(&"clank", onto.global_position)
				add_link(target, onto, 0, target.blueprint or onto.blueprint)
		&"link_pylon":
			if peer != commander_peer and target is Fixture and can_link_pylon(target, args[1], args[2]) == "":
				add_link(target, place_blueprint(&"pylon", args[1], args[2], target.global_position), 0, true)
		&"flip":
			if peer != commander_peer and target is Link and can_flip(target) == "":
				flip(target)
		&"unlink":
			if peer != commander_peer and target is Link:
				sound(&"clank", (target.start() + target.end()) * 0.5)
				remove_link(target)
		&"string":
			if target is Link and target.blueprint and !target.from.blueprint and !target.to.blueprint:
				target.blueprint = false
				sound(&"clank", (target.start() + target.end()) * 0.5)
				_announce("Cable strung")
		&"construct":
			if target is Fixture and blueprints.has(target):
				sound(&"clank", target.global_position)
				construct(target)
		&"repair":
			if target is Fixture and (target == pod or built.has(target)):
				sound(&"clank", target.global_position)
				target.health = minf(target.max_health, target.health + REPAIR)
		&"flare":
			var s: Dictionary = stats[peer]
			if s.flares > 0:
				s.flares -= 1
				sound(&"flare", args[0])
				_throw_flare(args[0], args[1])
		&"ping":
			var info: Dictionary = Net.peers.get(peer, {})
			var who: String = info.get("name", Net.player_name if peer == Net.local_id() else "Soldier")
			var ping := [args[0], who, peer == commander_peer, peer]
			if Net.has_local_player():
				on_event(&"ping", ping)
			for id in Net.peers:
				if id != Net.local_id():
					Net.event.rpc_id(id, &"ping", ping)
		&"press":
			if target and "screen" in target and target.screen:
				var reply: String = target.screen.pressed.call(args[1])
				if peer == Net.local_id():
					_show_reply(target, reply)
				else:
					Net.event.rpc_id(peer, &"reply", [args[0], reply])
		&"research":
			if peer == commander_peer and !args.is_empty() and UPGRADES.has(args[0]):
				var reply := queue_research(args[0])
				if peer == Net.local_id():
					if commander_view:
						commander_view.toast(reply)
				else:
					Net.event.rpc_id(peer, &"toast", [reply])
		&"order":
			if peer == commander_peer and args.size() == 2 and GEAR.has(args[0]) and stats.has(args[1]):
				var reply := order_gear(args[0], args[1])
				if peer == Net.local_id():
					if commander_view:
						commander_view.toast(reply)
				else:
					Net.event.rpc_id(peer, &"toast", [reply])
		&"gear_up":
			if target is Fixture and built.has(target) and target.kind == &"armory":
				var s: Dictionary = stats[peer]
				var got: Array[String] = []
				for entry: Array in racked.duplicate():
					if entry[1] == peer:
						racked.erase(entry)
						if !s.gear.has(entry[0]):
							s.gear.append(entry[0])
							got.append(String(UPGRADES[entry[0]].name).capitalize())
				if !got.is_empty():
					sound(&"pick_up", target.global_position)
					_say_to(peer, "Geared up: %s" % ", ".join(got))
		&"launch":
			if peer == commander_peer:
				if launch_at == INF:
					launch_at = time + LAUNCH_COUNTDOWN
					_announce("The pod launches in %d s: get back aboard! The engines are waking the bugs: hold the pod!" % LAUNCH_COUNTDOWN, &"alarm")
					_open_extraction_holes()
				else:
					launch_at = INF
					_close_holes(true)
					_announce("Launch called off. The engines spool down.")
		&"revive":
			var fallen: Node3D = bodies.get(args[0], null)
			var reviver: Node3D = bodies.get(peer, null)
			if peer != commander_peer and fallen and reviver and is_down(fallen) and fallen.global_position.distance_to(reviver.global_position) < REVIVE_REACH + 1.5:
				var s: Dictionary = stats[args[0]]
				s.down = -1.0
				s.health = max_health(args[0]) * REVIVE_HEALTH
				s.warmth = maxf(s.warmth, 50.0)
				s.since_hurt = 0.0
				_show_down(args[0], false)
				sound(&"respawn", fallen.global_position)
				_announce("%s got %s back up." % [name_of(peer), name_of(args[0])])
		&"uncommand":
			if commander_peer == peer:
				_leave_command(peer)
		&"hit":
			if target is Spider:
				sound(&"spider_hurt", target.global_position)
				(target as Spider).hit(args[1], bodies.get(peer, null))
		&"fling":
			if target is Spider:
				(target as Spider).fling(args[1], args[2])
		&"shot":
			for id in Net.peers:
				if id != peer and id != Net.local_id():
					Net.effect.rpc_id(id, &"tracer", [args[0], args[1], &"shot"])
			if peer != Net.local_id() and player:
				player._tracer(args[0], args[1])
				Sfx.play(&"shot", args[0])
	_acting = 0


## Client: something the server's telling this peer alone.
func on_event(kind: StringName, args: Array) -> void:
	match kind:
		&"reply":
			var owner: Node = entities.get(args[0], null)
			if owner and "screen" in owner and owner.screen:
				_show_reply(owner, args[1])
		&"respawn":
			if player:
				place_player(args[0], pod.global_position)
				player._say(args[1])
				Sfx.play(&"respawn")
		&"toast":
			if commander_view:
				commander_view.toast(args[0])
		&"say":
			if player:
				player._say(args[0])
		&"announce":
			if hud:
				hud.announce(args[0])
			Sfx.play(args[1])
		&"command":
			if args[0]:
				_enter_view()
			else:
				_exit_view()
		&"tracer":
			if player:
				player._tracer(args[0], args[1])
			Sfx.play(args[2], args[0])
		&"sound":
			Sfx.play(args[0], args[1])
		&"ping":
			pings.assign(pings.filter(func(p: Dictionary) -> bool: return p.peer != args[3]))
			pings.push_back({position = args[0], name = args[1], commander = args[2], age = 0.0, peer = args[3]})
			_ping_beam(args[0], args[2])
			Sfx.play(&"ping")


func _show_reply(owner: Node, text: String) -> void:
	owner.screen.reply(text)
	if commander_view and commander_view.visible and text != "":
		commander_view.toast(text)


## Server: a line for one soldier's prompt.
func _say_to(peer: int, text: String) -> void:
	if peer == Net.local_id():
		if player:
			player._say(text)
	else:
		Net.event.rpc_id(peer, &"say", [text])


func _announce(text: String, sound_name := &"announce") -> void:
	if hud:
		hud.announce(text)
	if Net.has_local_player():
		Sfx.play(sound_name)
	if Net.networked():
		for id in Net.peers:
			if id != Net.local_id():
				Net.event.rpc_id(id, &"announce", [text, sound_name])


## Server: a sound for everyone in earshot, at `at` (or flat, if INF).
func sound(sound_name: StringName, at := Vector3.INF) -> void:
	if Net.has_local_player():
		Sfx.play(sound_name, at)
	if Net.networked():
		for id in Net.peers:
			if id != Net.local_id():
				Net.effect.rpc_id(id, &"sound", [sound_name, at])


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
	orders = orders.filter(func(entry: Array) -> bool: return entry[1] != peer)
	racked = racked.filter(func(entry: Array) -> bool: return entry[1] != peer)


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
			Net.snapshot.rpc_id(id, [fast, [s.health, s.warmth, s.carried, s.lit_by, s.hurt, s.flares, s.down]])
		if !slow.is_empty():
			Net.slow_snapshot.rpc_id(id, slow)


func _fast_state() -> Array:
	var soldiers: Array = []
	for peer in bodies:
		if peer == commander_peer:
			continue
		var body: Node3D = bodies[peer]
		var pitch: float = body.pitch if "pitch" in body else 0.0
		soldiers.append([peer, body.global_position, body.global_rotation.y, pitch, is_down(body)])
	var spider_rows: Array = []
	for spider in spiders:
		spider_rows.append([spider.net_id, spider.global_position, spider.global_basis.get_rotation_quaternion(), spider.health])
	var flare_rows: Array = []
	for flare in flares:
		flare_rows.append([flare.net_id, flare.global_position, flare.life])
	return [time, battery, power_in, power_out, stock, state, outcome, soldiers, spider_rows, commander_peer, flare_rows, pod.health, alloy]


func _slow_state() -> Array:
	var rows: Array = []
	for f in built:
		rows.append([f.net_id, f.kind, f.global_position, f.global_basis.get_rotation_quaternion(), f.normal, f.health, f.on, f.stored, f.stalled, f.researching, f.research_time, f.unpowered, f.charge, f.deposit.net_id if f.deposit else 0, f.enabled, f.ore_in, f.alloy_out, f.smelted, f.holding.duplicate(), f.ammo, f.aim, f.since_shot, f.made_for])
	var alive := PackedInt32Array()
	for ore in ores:
		alive.append(ore.net_id)
	var plans: Array = []
	for b in blueprints:
		plans.append([b.net_id, b.kind, b.global_position, b.global_basis.get_rotation_quaternion(), b.normal, b.hits, b.deposit.net_id if b.deposit else 0])
	var hole_rows: Array = []
	for hole in holes:
		hole_rows.append([hole.net_id, hole.global_position, hole.normal])
	var link_rows: Array = []
	for link in links:
		link_rows.append([link.net_id, link.from.net_id, link.to.net_id, link.items.duplicate(true), link.blueprint])
	var worn := {}
	for peer in stats:
		worn[peer] = stats[peer].gear.duplicate()
	return [rows, alive, researched.keys(), plans, hole_rows, link_rows, launch_at, research_queue.duplicate(), orders.duplicate(true), racked.duplicate(true), worn]


## Client: the server's latest of everything that moves.
func apply_snapshot(data: Array) -> void:
	var f: Array = data[0]
	time = f[0]
	battery = f[1]
	power_in = f[2]
	power_out = f[3]
	stock = f[4]
	alloy = f[12]
	if state == State.PLAYING and f[5] != State.PLAYING:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	state = f[5]
	outcome = f[6]
	commander_peer = f[9]
	if f[11] < pod.health:
		_pod_hurt_at = time
	if f[11] < pod.health and commander_view and commander_view.visible:
		commander_view.pod_hit()
	pod.health = f[11]
	var lit := {}
	for row: Array in f[10]:
		lit[row[0]] = true
		var flare: Flare = entities.get(row[0], null)
		if !flare:
			flare = Flare.new()
			flare.game = self
			flare.puppet = true
			flare.position = row[1]
			add_child(flare)
			_track(flare, row[0])
			flares.push_back(flare)
		flare.target_position = row[1]
		flare.life = row[2]
	for flare in flares.duplicate():
		if !lit.has(flare.net_id):
			remove_flare(flare)
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
		stats[peer].down = 1.0 if row[4] else -1.0
		avatar.set_down(row[4])
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
	var mine: Array = data[1]
	var s: Dictionary = _me()
	s.health = mine[0]
	s.warmth = mine[1]
	s.carried = mine[2]
	s.lit_by = mine[3]
	s.hurt = mine[4]
	s.flares = mine[5]
	s.down = mine[6]


## Client: the server's latest of what's built, what ore's left, and what's
## been researched.
func apply_slow(data: Array) -> void:
	launch_at = data[6]
	research_queue.assign(data[7])
	orders = data[8]
	racked = data[9]
	for peer: int in data[10]:
		if stats.has(peer):
			stats[peer].gear = data[10][peer]
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
		fixture.health = row[5]
		if fixture.kind == &"lamp" and fixture.on != row[6]:
			fixture.set_on(row[6])
		fixture.stored = row[7]
		fixture.stalled = row[8]
		fixture.researching = row[9]
		fixture.research_time = row[10]
		fixture.unpowered = row[11]
		fixture.charge = row[12]
		fixture.enabled = row[14]
		fixture.ore_in = row[15]
		fixture.alloy_out = row[16]
		fixture.smelted = row[17]
		fixture.holding.assign(row[18])
		fixture.ammo = row[19]
		fixture.aim = row[20]
		fixture.since_shot = row[21]
		fixture.made_for = row[22]
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
	seen.clear()
	for row: Array in data[3]:
		seen[row[0]] = true
		var plan: Fixture = entities.get(row[0], null)
		if !plan:
			plan = Fixture.make(row[1], row[2], row[4])
			plan.basis = Basis(row[3])
			plan.blueprint = true
			if row[6] != 0 and entities.has(row[6]):
				plan.deposit = entities[row[6]]
				plan.deposit.rig = plan
			add_child(plan)
			_track(plan, row[0])
			blueprints.push_back(plan)
		plan.hits = row[5]
	for plan in blueprints.duplicate():
		if !seen.has(plan.net_id):
			_remove_blueprint(plan)
	seen.clear()
	for row: Array in data[4]:
		seen[row[0]] = true
		if !entities.has(row[0]):
			_add_hole(row[1], row[2], row[0])
	for hole in holes.duplicate():
		if !seen.has(hole.net_id):
			holes.erase(hole)
			entities.erase(hole.net_id)
			hole.queue_free()
	seen.clear()
	for row: Array in data[5]:
		seen[row[0]] = true
		var link: Link = entities.get(row[0], null)
		if !link:
			if !entities.has(row[1]) or !entities.has(row[2]):
				continue
			link = add_link(entities[row[1]], entities[row[2]], row[0])
		link.from = entities.get(row[1], link.from)
		link.to = entities.get(row[2], link.to)
		link.items = row[3]
		link.blueprint = row[4]
	for link in links.duplicate():
		if !seen.has(link.net_id):
			remove_link(link)
	for upgrade: StringName in data[2]:
		if !researched.has(upgrade):
			researched[upgrade] = true
			if hud:
				hud.announce("Researched: %s" % String(UPGRADES[upgrade].name).capitalize())


## Client: presses on this thing's screen go to the server.
func _send_presses(owner: Node) -> void:
	if Net.mode == Net.Mode.CLIENT:
		owner.screen.send = func(action: StringName) -> void: act(&"press", [owner.net_id, action])


## Server: the commander's click on an upgrade. Queues it (and whatever
## it needs, first), or takes it off the queue, or cancels it under way
## for a refund. Says how that went.
func queue_research(upgrade_id: StringName) -> String:
	var upgrade: Dictionary = UPGRADES[upgrade_id]
	if has(upgrade_id):
		return "Already researched."
	var lab := researching(upgrade_id)
	if lab:
		lab.researching = &""
		stock += upgrade.cost
		alloy += upgrade.alloy
		_unqueue_after(upgrade_id)
		return "Cancelled, %s refunded." % price(upgrade.cost, upgrade.alloy)
	if research_queue.has(upgrade_id):
		research_queue.erase(upgrade_id)
		_unqueue_after(upgrade_id)
		return "Taken off the queue."
	var chain: Array[StringName] = []
	var at := upgrade_id
	while at != &"" and !has(at) and !research_queue.has(at) and !researching(at):
		chain.push_front(at)
		at = UPGRADES[at].get("needs", &"")
	research_queue.append_array(chain)
	if chain.size() > 1:
		return "Queued, after %s." % ", ".join(chain.slice(0, -1).map(func(id: StringName) -> String: return String(UPGRADES[id].name).capitalize()))
	return "Queued."


## Takes off the queue whatever needs upgrade_id, which won't be done now.
func _unqueue_after(upgrade_id: StringName) -> void:
	for queued in research_queue.duplicate():
		if UPGRADES[queued].get("needs", &"") == upgrade_id:
			research_queue.erase(queued)
			_unqueue_after(queued)


## Starts idle labs on the first queued upgrades they can.
func _run_queue() -> void:
	for lab in built:
		if lab.kind != &"lab" or lab.researching != &"" or !lab.enabled:
			continue
		for queued in research_queue:
			var upgrade: Dictionary = UPGRADES[queued]
			var needs: StringName = upgrade.get("needs", &"")
			if (needs != &"" and !has(needs)) or stock < upgrade.cost or alloy < upgrade.alloy:
				continue
			stock -= upgrade.cost
			alloy -= upgrade.alloy
			lab.researching = queued
			lab.research_time = 0.0
			research_queue.erase(queued)
			break


## Server: the commander's click on a soldier's gear. Orders it (and
## queues its research, if that's not done), or takes the order back, or
## cancels it under way for a refund. Says how that went.
func order_gear(item: StringName, peer: int) -> String:
	var info: Dictionary = GEAR[item]
	var gear_name := String(UPGRADES[item].name).capitalize()
	if equipped(item, peer):
		return "%s already has a %s." % [name_of(peer), gear_name]
	for entry: Array in racked:
		if entry[0] == item and entry[1] == peer:
			return "It's made: %s can collect it at an armory." % name_of(peer)
	var armory := making(item, peer)
	if armory:
		armory.researching = &""
		stock += info.cost
		alloy += info.alloy
		return "Cancelled, %s refunded." % price(info.cost, info.alloy)
	for entry: Array in orders:
		if entry[0] == item and entry[1] == peer:
			orders.erase(entry)
			return "Order taken back."
	orders.append([item, peer])
	if !has(item) and !research_queue.has(item) and !researching(item):
		queue_research(item)
		return "Ordered; %s queued for research first." % gear_name
	return "Ordered %s for %s." % [gear_name, name_of(peer)]


## Which armory's making item for peer, if any.
func making(item: StringName, peer: int) -> Fixture:
	for armory in built:
		if armory.kind == &"armory" and armory.researching == item and armory.made_for == peer:
			return armory
	return null


## Starts idle armories on the first orders they can: researched, and
## paid for.
func _run_orders() -> void:
	for armory in built:
		if armory.kind != &"armory" or armory.researching != &"" or !armory.enabled:
			continue
		for entry: Array in orders:
			var info: Dictionary = GEAR[entry[0]]
			if !has(entry[0]) or stock < info.cost or alloy < info.alloy:
				continue
			stock -= info.cost
			alloy -= info.alloy
			armory.researching = entry[0]
			armory.made_for = entry[1]
			armory.research_time = 0.0
			orders.erase(entry)
			break


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
	for flare in flares:
		if flare.life > 0.0:
			var glow := flare.light.global_position
			if glow.distance_to(pos) < Flare.RANGE * 0.7:
				var query := PhysicsRayQueryParameters3D.create(glow, pos, Terrain.ROCK_LAYER)
				if space.intersect_ray(query).is_empty():
					return "flare"
	return ""


## Whether kind can go at pos, on ground facing normal; for a rig, pos is
## the deposit's.
func can_build(kind: StringName, pos: Vector3, normal := Vector3.UP) -> bool:
	if !Fixture.BUILD_HITS.has(kind):
		return false
	if kind == &"drill":
		var deposit := deposit_at(pos)
		return deposit != null and deposit.rig == null
	if normal.angle_to(Terrain.up_at(pos)) > deg_to_rad(Fixture.MAX_SLOPE.get(kind, Fixture.SLOPE)):
		return false
	for fixture: Fixture in built + blueprints + ores + deposits + [pod]:
		var room := 3.0 if fixture == pod else (2.6 if fixture.kind == &"deposit" or fixture.kind == &"drill" else 1.2)
		if kind == &"barricade" and fixture.kind == &"barricade":
			room = 2.9
		if [&"lab", &"foundry", &"armory"].has(kind) or [&"lab", &"foundry", &"armory"].has(fixture.kind):
			room += 1.6
		if fixture.global_position.distance_to(pos) < room:
			return false
	return true


## "3 ore", or "3 ore + 2 alloy".
static func price(ore: int, alloy_cost: int) -> String:
	return "%d ore" % ore + (" + %d alloy" % alloy_cost if alloy_cost > 0 else "")


## Builds kind at pos, its front turned towards facing_from.
func build(kind: StringName, pos: Vector3, normal: Vector3, facing_from := Vector3.INF) -> Fixture:
	stock -= Fixture.COST[kind]
	alloy -= Fixture.ALLOY.get(kind, 0)
	var fixture := _make_fixture(kind, pos, normal, facing_from)
	add_child(fixture)
	_track(fixture)
	built.push_back(fixture)
	_light_check = 0.0
	return fixture


## Rigs stand on their deposit's slope; everything else stands upright,
## on a plinth if the ground slopes.
func _make_fixture(kind: StringName, pos: Vector3, normal: Vector3, facing_from: Vector3) -> Fixture:
	var fixture: Fixture
	if kind == &"drill":
		var deposit := deposit_at(pos)
		fixture = Fixture.make(kind, deposit.global_position, deposit.normal)
		fixture.deposit = deposit
		deposit.rig = fixture
	else:
		normal = Terrain.up_at(pos)
		fixture = Fixture.make(kind, pos, normal)
	if facing_from != Vector3.INF:
		var up := fixture.normal
		var towards := facing_from - fixture.position
		towards -= up * towards.dot(up)
		if towards.length() > 0.1:
			fixture.basis = Basis.looking_at(-towards.normalized(), up)
	return fixture


## The commander's: kind, as a hologram for soldiers to hammer up, paid
## for a blow at a time.
func place_blueprint(kind: StringName, pos: Vector3, normal: Vector3, facing_from := Vector3.INF) -> Fixture:
	var plan := _make_fixture(kind, pos, normal, facing_from)
	plan.blueprint = true
	add_child(plan)
	_track(plan)
	blueprints.push_back(plan)
	return plan


## Whether the bank can pay for the next blow on a blueprint.
func can_pay(plan: Fixture) -> bool:
	return stock >= plan.blow_cost() and alloy >= plan.blow_cost(true)


## A hammer blow on a blueprint, if the bank can pay for it; the last one
## puts it up for real.
func construct(plan: Fixture) -> bool:
	if !can_pay(plan):
		return false
	stock -= plan.blow_cost()
	alloy -= plan.blow_cost(true)
	plan.hits += 1
	if plan.hits < plan.hits_needed():
		return true
	var at := plan.global_transform
	_remove_blueprint(plan)
	stock += Fixture.COST[plan.kind]
	alloy += Fixture.ALLOY.get(plan.kind, 0)
	var fixture := build(plan.kind, at.origin, plan.normal)
	fixture.basis = at.basis
	for link in links:
		if link.from == plan:
			link.from = fixture
		if link.to == plan:
			link.to = fixture
		# A cable laid to a blueprint goes up once both its ends are built.
		if link.blueprint and !link.from.blueprint and !link.to.blueprint:
			link.blueprint = false
	_announce("%s built" % Fixture.NAMES[plan.kind], &"built")
	return true


func _remove_blueprint(plan: Fixture) -> void:
	if plan.deposit and plan.deposit.rig == plan:
		plan.deposit.rig = null
	blueprints.erase(plan)
	entities.erase(plan.net_id)
	plan.queue_free()


func deposit_at(pos: Vector3) -> Fixture:
	for deposit in deposits:
		if deposit.global_position.distance_to(pos) < 0.5:
			return deposit
	return null


## Picks up something built, refunding it to the bank; what's in a rig's
## hopper or a foundry's bin comes with it, ore into your pockets and
## alloy into the bank.
func pick_up(fixture: Fixture) -> void:
	stock += Fixture.COST[fixture.kind]
	alloy += Fixture.ALLOY.get(fixture.kind, 0) + fixture.alloy_out
	carried += fixture.stored + fixture.ore_in + fixture.ammo / Fixture.ROUNDS_PER_ORE
	if fixture.researching != &"" and fixture.kind == &"lab":
		stock += UPGRADES[fixture.researching].cost
		alloy += UPGRADES[fixture.researching].alloy
	elif fixture.researching != &"":
		stock += GEAR[fixture.researching].cost
		alloy += GEAR[fixture.researching].alloy
		orders.push_front([fixture.researching, fixture.made_for])
	_remove_built(fixture)


func _remove_built(fixture: Fixture) -> void:
	if fixture.deposit:
		fixture.deposit.rig = null
	_unlink_all(fixture)
	built.erase(fixture)
	entities.erase(fixture.net_id)
	fixture.queue_free()


func _unlink_all(fixture: Fixture) -> void:
	for link in links.duplicate():
		if link.from == fixture or link.to == fixture:
			remove_link(link)


## Why a cable can't go from a to b, or "" if it can. Either end can still
## be a blueprint; the cable can't be strung till both are up.
func can_link(a: Fixture, b: Fixture) -> String:
	if a == b:
		return "Pick somewhere else to run it to."
	if !Fixture.CABLE_HEIGHT.has(a.kind) or !Fixture.CABLE_HEIGHT.has(b.kind):
		return "Cables tie to pylons, rigs, foundries, turrets and the pod."
	if a == pod:
		return "The pod only takes cables in."
	if b.kind == &"drill":
		return "A rig only sends."
	for link in links:
		if (link.from == a and link.to == b) or (link.from == b and link.to == a):
			return "They're already linked."
	return cable_clear(a.cable_point(), b.cable_point())


## Why a cable can't run from a to a new pylon at pos, or "" if it can.
func can_link_pylon(a: Fixture, pos: Vector3, normal: Vector3) -> String:
	if !Fixture.CABLE_HEIGHT.has(a.kind):
		return "Cables tie to pylons, rigs, foundries, turrets and the pod."
	if a == pod:
		return "The pod only takes cables in."
	if !can_build(&"pylon", pos, normal):
		return "No room for a pylon there."
	return cable_clear(a.cable_point(), pos + Terrain.up_at(pos) * Fixture.CABLE_HEIGHT.pylon)


func can_flip(link: Link) -> String:
	if link.to == pod:
		return "The pod only takes cables in."
	if link.from.kind == &"drill":
		return "A rig only sends."
	return ""


## Turns a cable round; what's on it heads back the way it came.
func flip(link: Link) -> void:
	var span := link.length()
	var turned: Array = []
	for item: Array in link.items:
		turned.push_front([item[0], span - item[1]])
	var was := link.from
	link.from = link.to
	link.to = was
	link.items = turned


## Why a cable can't run straight from start to end, or "" if it can.
func cable_clear(start: Vector3, end: Vector3) -> String:
	if start.distance_to(end) > Link.RANGE:
		return "Too far: a cable reaches %d m." % Link.RANGE
	var space := get_world_3d().direct_space_state
	for drop in [0.0, Link.HANG]:
		var query := PhysicsRayQueryParameters3D.create(start - Vector3.UP * drop, end - Vector3.UP * drop, Terrain.ROCK_LAYER)
		if !space.intersect_ray(query).is_empty():
			return "The ground's in the way."
	return ""


## A cable from a to b; as a blueprint, it carries nothing till a soldier's
## hammered it up.
func add_link(a: Fixture, b: Fixture, id := 0, plan := false) -> Link:
	var link := Link.make(a, b)
	link.blueprint = plan
	add_child(link)
	_track(link, id)
	links.push_back(link)
	return link


func remove_link(link: Link) -> void:
	links.erase(link)
	entities.erase(link.net_id)
	link.queue_free()


## Moves what's on the cables along, takes in what's reached the far end
## if there's room for it, and puts the next thing on each cable that has
## room, taking turns between a place's cables.
func _move_goods(delta: float) -> void:
	var speed := cable_speed()
	var strung := links.filter(func(l: Link) -> bool: return !l.blueprint)
	for link: Link in strung:
		link.advance(delta, speed)
		if !link.items.is_empty() and link.items[0][1] >= link.length() - 0.01 and link.to.accepts(link.items[0][0]):
			_take_in(link.to, link.items.pop_front()[0])
	if strung.is_empty():
		return
	_link_turn = (_link_turn + 1) % strung.size()
	for i in strung.size():
		var link: Link = strung[(i + _link_turn) % strung.size()]
		var item := link.from.output()
		if item != &"" and link.has_room():
			link.from.take_output()
			link.items.push_back([item, 0.0])


func _take_in(fixture: Fixture, item: StringName) -> void:
	match fixture.kind:
		&"pod":
			if item == &"alloy":
				alloy += 1
			else:
				stock += 1
		&"foundry":
			fixture.ore_in += 1
		&"pylon":
			fixture.holding.push_back(item)
		&"turret":
			fixture.ammo += Fixture.ROUNDS_PER_ORE


## A turret: when it's ready, turns on the nearest spider in range that
## it can see and that's in light, and shoots it, if it has ammo and
## there's power.
func _run_turret(turret: Fixture, delta: float) -> void:
	turret.since_shot += delta
	turret.cooldown -= delta
	if !turret.enabled:
		turret.stalled = "off"
	elif turret.ammo <= 0:
		turret.stalled = "no ammo"
	elif battery <= 0.0:
		turret.stalled = "no power"
	else:
		turret.stalled = ""
	if turret.stalled != "" or turret.cooldown > 0.0:
		return
	turret.cooldown = 0.25
	var from := turret.muzzle()
	var space := get_world_3d().direct_space_state
	var best: Spider = null
	var best_distance := Fixture.TURRET_RANGE
	for spider in spiders:
		var at := spider.global_position + Terrain.up_at(spider.global_position) * 0.4
		var distance := from.distance_to(at)
		if distance >= best_distance or !spider.active() or lit_at(at) == "":
			continue
		if !space.intersect_ray(PhysicsRayQueryParameters3D.create(from, at, Terrain.ROCK_LAYER)).is_empty():
			continue
		best_distance = distance
		best = spider
	if !best:
		return
	var at := best.global_position + Terrain.up_at(best.global_position) * 0.4
	var local := turret.global_basis.inverse() * (at - from)
	turret.aim = atan2(-local.x, -local.z)
	turret.cooldown = Fixture.TURRET_EVERY
	turret.since_shot = 0.0
	turret.ammo -= 1
	battery = maxf(0.0, battery - Fixture.TURRET_SHOT)
	best.hit(Fixture.TURRET_DAMAGE, turret)
	_tracer_for_all(from, at)


## A shot's tracer, for everyone who can see.
func _tracer_for_all(from: Vector3, to: Vector3) -> void:
	if player:
		player._tracer(from, to)
		Sfx.play(&"turret", from)
	for id in Net.peers:
		if id != Net.local_id():
			Net.effect.rpc_id(id, &"tracer", [from, to, &"turret"])


## Loads a turret from your pockets, as much as it'll take.
func load_turret(turret: Fixture) -> void:
	var room := (Fixture.MAGAZINE - turret.ammo) / Fixture.ROUNDS_PER_ORE
	var given := mini(room, carried)
	carried -= given
	turret.ammo += given * Fixture.ROUNDS_PER_ORE


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


func screens() -> Array[Screen]:
	return [pod.screen]


func _wire_pod_screen() -> void:
	var screen := pod.screen
	screen.info = func() -> String:
		var left := maxf(0.0, launch_at - time)
		return "ORE BANKED    %d / %d\nALLOY         %d\nBATTERY       %d%%   HULL %d%%\n%s" % [
			stock, QUOTA, alloy, roundi(battery / capacity() * 100.0), roundi(pod.health / pod.max_health * 100.0), ("LAUNCH IN     %d:%02d" % [int(left) / 60, int(left) % 60]) if launch_at < INF else "LAUNCH        COMMANDER'S CALL"]
	screen.button = func(action: StringName) -> Array:
		if action == &"command":
			if commander_peer == 0:
				return ["TAKE COMMAND", true, false]
			var info: Dictionary = Net.peers.get(commander_peer, {})
			return ["COMMANDER: %s" % String(info.get("name", "YOU" if commander_peer == Net.local_id() else "TAKEN")).to_upper(), false, true]
		return ["HAND IN ORE   %d CARRIED" % carried, carried > 0, false]
	screen.pressed = func(action: StringName) -> String:
		if action == &"command":
			if commander_peer != 0:
				return "THE SEAT'S TAKEN."
			_take_command(_acting if _acting != 0 else Net.local_id())
			return ""
		if carried == 0:
			return "NOTHING TO HAND IN."
		var amount := carried
		hand_in()
		return "%d ORE BANKED." % amount
	_send_presses(pod)


## What a spider goes for: the nearest soldier or thing built that it can
## see, or anything working loud enough to hear from further off; noise
## counts for less the closer it gets, so up close it bites what's nearest.
## Soldiers count as a little nearer than they are, and the pod further;
## whoever's hurt it lately, it goes for regardless.
func spider_target(spider: Spider) -> Node3D:
	if spider.grudge and is_instance_valid(spider.grudge) and spider.grudge_time > 0.0 and spider.grudge.visible and !is_down(spider.grudge):
		return spider.grudge
	if spider.frenzied:
		return pod
	var from := spider.global_position
	var best: Node3D = null
	var best_distance := Spider.SIGHT
	var candidates: Array[Node3D] = []
	for peer in bodies:
		if peer != commander_peer and !is_down(bodies[peer]):
			candidates.push_back(bodies[peer])
	candidates.append_array(built)
	candidates.push_back(pod)
	for candidate in candidates:
		var distance := from.distance_to(candidate.global_position)
		if candidate.has_meta("peer"):
			distance *= 0.75
		else:
			if candidate == pod:
				distance *= 1.4
			distance -= (candidate as Fixture).noise() * clampf((distance - Spider.NEAR) / 10.0, 0.0, 1.0)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best if best else pod


## How close a spider has to be to bite target.
func bite_reach(target: Node3D) -> float:
	if target.has_meta("peer"):
		return 1.7
	if target is Fixture and (target as Fixture).kind == &"drill":
		return 2.8
	if target is Fixture and (target as Fixture).kind == &"barricade":
		return 2.4
	if target is Fixture and (target as Fixture).kind == &"foundry":
		return 2.2
	if target == pod:
		return 2.7
	return 1.9


func damage(target: Node3D, amount: float) -> void:
	if state != State.PLAYING:
		return
	sound(&"bite", target.global_position)
	if target.has_meta("peer"):
		if is_down(target):
			return
		var s: Dictionary = stats.get(target.get_meta("peer"), _nobody)
		s.health -= amount
		s.hurt = 1.0
		s.since_hurt = 0.0
	elif target is Fixture:
		(target as Fixture).health -= amount
		if target == pod:
			_pod_bitten = 0.0
			_pod_hurt_at = time
		if target == pod and _pod_alert <= 0.0:
			_pod_alert = POD_ALERT_EVERY
			_announce("The pod is under attack!", &"alarm")
		if target == pod and commander_view and commander_view.visible:
			commander_view.pod_hit()


func remove_spider(spider: Spider) -> void:
	spiders.erase(spider)
	entities.erase(spider.net_id)
	spider.queue_free()


func spawn_spider(spot: Vector3, frenzied := false) -> void:
	var spider := Spider.new()
	spider.game = self
	spider.frenzied = frenzied
	spider.position = spot
	add_child(spider)
	_track(spider)
	spiders.push_back(spider)


func _throw_flare(from: Vector3, dir: Vector3) -> void:
	var flare := Flare.new()
	flare.game = self
	flare.position = from
	flare.velocity = dir.normalized() * Flare.SPEED
	add_child(flare)
	_track(flare)
	flares.push_back(flare)


func remove_flare(flare: Flare) -> void:
	flares.erase(flare)
	entities.erase(flare.net_id)
	flare.queue_free()


## A column of light over a pinged spot, fading as the ping does.
func _ping_beam(at: Vector3, from_commander: bool) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(Hud.DAY_COLOR if from_commander else Hud.FUEL_COLOR, 0.5)
	var column := CylinderMesh.new()
	column.top_radius = 0.05
	column.bottom_radius = 0.25
	column.height = 40.0
	var beam := MeshInstance3D.new()
	beam.mesh = column
	beam.material_override = material
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = at + Vector3.UP * 20.0
	add_child(beam)
	var tween := beam.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, PING_TIME).set_ease(Tween.EASE_IN)
	tween.tween_callback(beam.queue_free)




## Brings spiders up out of the ground, somewhere unlit not far from a
## soldier or something built.
func _spawn_spiders(delta: float) -> void:
	var players := (1.0 + maxi(1, bodies.size())) * 0.5
	_spawn_frenzied(delta, players)
	if Sun.dir_at(time).y > 0.0:
		_night = false
		_close_holes(false)
		return
	if !_night:
		_night = true
		_open_holes()
	_spawn_in -= delta
	var night_holes := holes.filter(func(h: Hole) -> bool: return !h.extraction)
	if _spawn_in > 0.0 or night_holes.is_empty():
		return
	var progress := time / RAMP
	_spawn_in = maxf(lerpf(SPAWN_GAP_START, SPAWN_GAP_END, progress), SPAWN_GAP_END * 0.5) / players
	var calm := spiders.filter(func(s: Spider) -> bool: return !s.frenzied).size()
	if calm >= roundi(minf(lerpf(SPIDERS_START, SPIDERS_END, progress), SPIDERS_END * 2.0) * players):
		return
	spawn_spider(_spot_by(night_holes[_rng.randi() % night_holes.size()]))


## While the engines spool up: frenzied spiders out of the holes they tore.
func _spawn_frenzied(delta: float, players: float) -> void:
	_frenzy_in -= delta
	var torn := holes.filter(func(h: Hole) -> bool: return h.extraction)
	if _frenzy_in > 0.0 or torn.is_empty():
		return
	_frenzy_in = EXTRACTION_GAP / players
	if spiders.filter(func(s: Spider) -> bool: return s.frenzied).size() >= roundi(EXTRACTION_SPIDERS * players):
		return
	spawn_spider(_spot_by(torn[_rng.randi() % torn.size()]), true)


## Somewhere in a bug hole's mouth.
func _spot_by(hole: Hole) -> Vector3:
	var frame := Fixture.upright(hole.normal)
	var angle := _rng.randf() * TAU
	var spot := hole.global_position + (frame.x * cos(angle) + frame.z * sin(angle)) * _rng.randf_range(0.0, Hole.RADIUS * 0.7)
	return terrain.surface_point(spot)[0]


## Closes the night's holes, or the ones the engines tore.
func _close_holes(extraction: bool) -> void:
	for hole in holes.duplicate():
		if hole.extraction == extraction:
			holes.erase(hole)
			entities.erase(hole.net_id)
			hole.queue_free()


func _open_extraction_holes() -> void:
	var want := EXTRACTION_HOLES + (1 if bodies.size() >= 3 else 0)
	var spots: Array[Array] = terrain.surface_spots.duplicate()
	_shuffle(spots)
	var opened := 0
	for loose in [1.0, 0.6]:
		for spot in spots:
			if opened >= want:
				break
			var at: Vector3 = spot[0]
			var from_pod := at.distance_to(pod.global_position)
			if from_pod < EXTRACTION_NEAR * loose or from_pod > EXTRACTION_FAR / loose or Vector2(at.x, at.z).length() > Terrain.FLOOR_RADIUS - 4.0 or (spot[1] as Vector3).y < 0.8 * loose:
				continue
			if holes.any(func(h: Hole) -> bool: return h.global_position.distance_to(at) < HOLE_APART * 0.6 * loose):
				continue
			_add_hole(at, spot[1]).extraction = true
			opened += 1
	_frenzy_in = 3.0


## Nightfall: one bug hole the first night, one more each night after, and
## one more with three players or more, out away from the pod.
func _open_holes() -> void:
	var first_sunset := Sun.time_of(PI)
	var night := floori((time - first_sunset) / Sun.TURN) + 1
	var want := night + (1 if bodies.size() >= 3 else 0)
	var spots: Array[Array] = terrain.surface_spots.duplicate()
	_shuffle(spots)
	for loose in [1.0, 0.5]:
		for spot in spots:
			if holes.filter(func(h: Hole) -> bool: return !h.extraction).size() >= want:
				break
			var at: Vector3 = spot[0]
			var from_pod := at.distance_to(pod.global_position)
			if from_pod < HOLE_NEAR * loose or from_pod > HOLE_FAR / loose or Vector2(at.x, at.z).length() > Terrain.FLOOR_RADIUS - 4.0 or (spot[1] as Vector3).y < 0.8 * loose:
				continue
			if holes.any(func(h: Hole) -> bool: return h.global_position.distance_to(at) < HOLE_APART * loose):
				continue
			_add_hole(at, spot[1])
	_announce("Bug holes are tearing open in the dark." if holes.size() > 1 else "A bug hole's torn open in the dark.")


func _add_hole(at: Vector3, normal: Vector3, id := 0) -> Hole:
	var hole := Hole.new()
	hole.normal = normal
	hole.position = at
	add_child(hole)
	_track(hole, id)
	holes.push_back(hole)
	return hole


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


## The pod comes down on open, flat ground near the middle.
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
	player.zip = null
	player.velocity = Vector3.ZERO
	player.align_up()


## Debug setup from user args (after `--`): seed=, time=, view=overview|
## cave|screen, lab (builds one ahead, researching), rig (builds one
## on the deposit nearest the pod and stands you by it), cables (a rig,
## cabled to a foundry cabled to the pod), lamps=N (around
## you), spiders=N (in front of you), plan=N (blueprints round the pod),
## flares=N (thrown ahead), ping (25 m ahead),
## command (in the commander's seat), aim, hammer, pause, yaw= and pitch=degrees,
## and shot=path.png and shot_at=seconds to save a screenshot and quit.
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
	if _args.has("defence"):
		var away := player.global_position - pod.global_position
		away.y = 0.0
		print(debug_defence(player.global_position + away.normalized() * 6.0, player.global_position))
	if _args.has("cables"):
		print(debug_cables())
		var foundry: Fixture = built[-1]
		var side: Vector3 = terrain.surface_point(foundry.global_position + Fixture.upright(foundry.normal).x * 6.0)[0]
		place_player(side + Vector3.UP * 0.3, foundry.global_position)
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
	for i in int(_args.get("flares", "0")):
		var ahead := -player.global_basis.z
		var side := player.global_basis.x
		_throw_flare(player.global_position + Vector3.UP * 1.6, (ahead * (0.6 + i * 0.25) + side * (i - 1) * 0.35 + Vector3.UP * 0.3).normalized())
	if _args.has("ping"):
		handle(Net.local_id(), &"ping", [player.global_position - player.global_basis.z * 25.0])
	if _args.has("plan"):
		var frame := Fixture.upright(pod.normal)
		for i in int(_args.plan):
			var kind: StringName = [&"lab", &"lamp", &"panel", &"battery"][i % 4]
			var spot: Array = terrain.surface_point(pod.global_position + (frame.x * cos(i * 1.3 + 2.0) + frame.z * sin(i * 1.3 + 2.0)) * (8.0 + i * 1.5))
			var plan := place_blueprint(kind, spot[0], spot[1], pod.global_position)
			plan.hits = i % plan.hits_needed()
	if _args.has("lab"):
		player.rotate_object_local(Vector3.UP, PI)
		var ahead: Array = terrain.surface_point(player.global_position - player.global_basis.z * 5.0)
		stock += Fixture.COST[&"lab"] + Game.UPGRADES[&"gun"].cost
		build(&"lab", ahead[0], ahead[1], player.global_position)
		queue_research(&"gun")
	if _args.has("armory"):
		player.rotate_object_local(Vector3.UP, PI)
		var ahead: Array = terrain.surface_point(player.global_position - player.global_basis.z * 5.0)
		stock += Fixture.COST[&"armory"]
		build(&"armory", ahead[0], ahead[1], player.global_position)
	if _args.has("upgrades"):
		for upgrade in str(_args.upgrades).split(",", false):
			if UPGRADES.has(StringName(upgrade)):
				researched[StringName(upgrade)] = true
				if GEAR.has(StringName(upgrade)):
					_me().gear.append(StringName(upgrade))
	player.debug_aim = _args.has("aim")
	if _args.has("hammer"):
		player._switch(&"hammer")
	if _args.has("pause"):
		hud.set_paused(true)
	if _args.has("yaw"):
		player.rotate_object_local(Vector3.UP, deg_to_rad(float(_args.yaw)))
	if _args.has("pitch"):
		player.look(deg_to_rad(float(_args.pitch)))
	if _args.has("command"):
		_take_command(Net.local_id())
		commander_view._research.visible = _args.has("research")
		commander_view._armory.visible = _args.has("armory_panel")
	if _args.has("probe"):
		_probe(_args.probe)
	if _args.has("shot"):
		await get_tree().create_timer(float(_args.get("shot_at", "3"))).timeout
		var image := get_viewport().get_texture().get_image()
		image.save_png(_args.shot)
		print("saved ", _args.shot)
		get_tree().quit()


## Debug: a loaded turret at spot with a lamp beside it, and three
## barricades in a line past it, away from from, all free. Says what it
## built.
func debug_defence(spot: Vector3, from: Vector3) -> String:
	var ahead := spot - from
	ahead.y = 0.0
	ahead = ahead.normalized()
	var side := ahead.cross(Vector3.UP)
	var made: Array[String] = []
	var plan := [[&"turret", spot], [&"lamp", spot + side * 2.5]]
	for i in 3:
		plan.append([&"barricade", spot + ahead * 6.0 + side * (i - 1) * 3.0])
	for entry: Array in plan:
		var at: Array = terrain.surface_point(entry[1])
		if !can_build(entry[0], at[0], at[1]):
			continue
		stock += Fixture.COST[entry[0]]
		alloy += Fixture.ALLOY.get(entry[0], 0)
		var fixture := build(entry[0], at[0], at[1], from)
		if fixture.kind == &"turret":
			fixture.ammo = Fixture.MAGAZINE
		made.append(String(fixture.kind))
	return "defence: built %s" % ", ".join(made)


## Debug: a rig on the deposit nearest the pod, and a foundry halfway home,
## a rig cabled to the foundry and the foundry to the pod, all free. Says
## how it went.
func debug_cables() -> String:
	var nearest := deposits[0]
	for deposit in deposits:
		if deposit.global_position.distance_to(pod.global_position) < nearest.global_position.distance_to(pod.global_position):
			nearest = deposit
	stock += Fixture.COST[&"drill"] + Fixture.COST[&"foundry"]
	var rig := build(&"drill", nearest.global_position, nearest.normal)
	var foundry: Fixture = null
	var why := ""
	for step in 24:
		var t := 0.5 + (step % 2 * 2 - 1) * (step / 2 % 4) * 0.06
		var side := Fixture.upright(pod.normal).x * (step / 8 - 1) * 3.0
		var spot: Array = terrain.surface_point(nearest.global_position.lerp(pod.global_position, t) + side)
		if !can_build(&"foundry", spot[0], spot[1]):
			continue
		if foundry:
			_remove_built(foundry)
		stock += Fixture.COST[&"foundry"]
		foundry = build(&"foundry", spot[0], spot[1], pod.global_position)
		why = can_link(rig, foundry) + can_link(foundry, pod)
		if why == "":
			break
	stock -= Fixture.COST[&"foundry"]
	if why == "":
		add_link(rig, foundry)
		add_link(foundry, pod)
	return "cables: rig %.0f m from the pod, %d links %s" % [nearest.global_position.distance_to(pod.global_position), links.size(), why]


## Debug, networked: a scripted client. "builder" mines and hands in,
## checking each reached the server; "commander" plans a pylon, hammers it
## up and cables it to the pod; "walker" walks in
## circles round the pod; "stander" stands by the pod's screen. Both report what they see, then quit.
func _probe(kind: String) -> void:
	var tree := get_tree()
	var report := func(tag: String) -> void:
		var others := []
		for peer in bodies:
			if peer != Net.local_id():
				others.append("%d@%s" % [peer, (bodies[peer] as Node3D).global_position.snapped(Vector3.ONE * 0.1)])
		print("[%s %s] t=%.1f stock %d carried %d | ores %d built %d links %d spiders %d flares %d (mine %d left) pings %s pod %.0f | others %s" % [kind, tag, time, stock, carried, ores.size(), built.size(), links.size(), spiders.size(), flares.size(), flares_left, pings.map(func(p: Dictionary) -> String: return p.name), pod.health, others])
	await tree.create_timer(3.0).timeout
	report.call("joined")
	if kind == "commander":
		act(&"press", [pod.net_id, &"command"])
		await tree.create_timer(2.0).timeout
		print("[commander] in the pod: commander %d (me %d), view %s" % [commander_peer, Net.local_id(), commander_view != null and commander_view.visible])
		var frame := Fixture.upright(pod.normal)
		var spot: Array = terrain.surface_point(pod.global_position + frame.x * 9.0)
		var stock_before := stock
		act(&"blueprint", [&"pylon", spot[0], spot[1], pod.global_position])
		await tree.create_timer(1.0).timeout
		print("[commander] blueprints %d, stock %d -> %d" % [blueprints.size(), stock_before, stock])
		act(&"order", [&"gun", Net.local_id()])
		await tree.create_timer(1.0).timeout
		print("[commander] ordered a rifle for myself: orders %s, research queue %s" % [orders, research_queue])
		act(&"uncommand", [])
		await tree.create_timer(1.0).timeout
		if !blueprints.is_empty():
			var plan := blueprints[0]
			for i in plan.hits_needed():
				act(&"construct", [plan.net_id])
			await tree.create_timer(1.0).timeout
			var pylons := built.filter(func(f: Fixture) -> bool: return f.kind == &"pylon")
			print("[commander] hammered it: blueprints %d, pylons %d" % [blueprints.size(), pylons.size()])
			if !pylons.is_empty():
				act(&"link", [pylons[0].net_id, pod.net_id])
				await tree.create_timer(1.0).timeout
				print("[commander] out of the pod, cabled the pylon to it: links %d, strung %s" % [links.size(), !links.is_empty() and !links[-1].blueprint])
		await tree.create_timer(2.0).timeout
		print("[commander] out: commander %d, view %s, player visible %s" % [commander_peer, commander_view != null and commander_view.visible, player.visible])
	elif kind == "stander":
		var spot: Vector3 = pod.screen.global_position + pod.screen.global_basis.z * 1.6 + pod.screen.global_basis.x * 1.2
		for i in 60:
			player.global_position = terrain.surface_point(spot)[0] + Vector3.UP * 0.1
			await tree.create_timer(0.25).timeout
	elif kind == "walker":
		act(&"flare", [player.global_position + Vector3.UP * 1.6, Vector3(0.3, 0.2, 0.9).normalized()])
		act(&"ping", [pod.global_position + Vector3(10, 0, 0)])
		await tree.create_timer(1.5).timeout
		report.call("flared+pinged")
		var centre := pod.global_position
		for i in 60:
			var angle := i * 0.2
			player.global_position = terrain.surface_point(centre + Vector3(cos(angle), 0, sin(angle)) * 9.0)[0] + Vector3.UP * 0.5
			await tree.create_timer(0.2).timeout
		report.call("walked")
	else:
		var stock_before := stock
		var nearest := ores[0]
		for ore in ores:
			if ore.global_position.distance_to(player.global_position) < nearest.global_position.distance_to(player.global_position):
				nearest = ore
		act(&"mine", [nearest.net_id])
		await tree.create_timer(1.0).timeout
		report.call("mined")
		print("[builder] stock %d -> %d, carrying %d" % [stock_before, stock, carried])
		act(&"press", [pod.net_id, &"hand_in"])
		await tree.create_timer(1.0).timeout
		report.call("handed in")
		for i in 8:
			await tree.create_timer(1.0).timeout
			report.call("watching")
	tree.quit()
