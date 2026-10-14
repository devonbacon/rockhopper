extends Node
## Headless smoke test. Generates a few maps and reports on them, then
## plays a mission roughly:
## - checks you stand on the ground;
## - builds a drill rig on the deposit nearest the pod, cabled to a
##   foundry cabled to the pod, and lets them work for a minute and a half
##   in daylight, with a lab researching;
## - rides a cable, and from the rig's cable on through the foundry onto
##   the pod's, looking that way;
## - as a soldier, lays a cable off a pylon to open ground for a new
##   pylon, hammers that up (the cable goes up with it), and turns the
##   cable round, which the commander can't;
## - builds a loaded turret with a lamp and a row of barricades;
## - hammers up a blueprint, switches the rig off and on, and presses a
##   button on the pod's screen;
## - skips to midnight and watches the spiders come;
## - calls the launch from the command chair and lifts off.
## Run it as a scene, with --fixed-fps 60 so it goes as fast as it can:
## Godot --headless --fixed-fps 60 --path . res://tests/smoke.tscn

var _game: Game
var _elapsed := 0.0
var _phase := 0
var _stock_before := 0
var _rig: Fixture
var _foundry: Fixture
var _lab: Fixture
var _ride_from := Vector3.ZERO


func _ready() -> void:
	for seed_value in [1, 2, 3]:
		var terrain := Terrain.new()
		terrain.generate(seed_value)
		var polygons := terrain.navigation.navigation_mesh.get_polygon_count()
		print("seed %d: %d ms, %d triangles, %d nav polygons, cave spots %d, surface spots %d" % [seed_value, terrain.generate_ms, terrain.triangle_count, polygons, terrain.cave_spots.size(), terrain.surface_spots.size()])
		terrain.free()
	_game = load("res://game/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_game)


func _physics_process(delta: float) -> void:
	if !_game.is_inside_tree():
		return
	if _step(delta):
		get_tree().quit()


func _step(delta: float) -> bool:
	_elapsed += delta
	var player := _game.player
	match _phase:
		0:
			if _elapsed < 4.0:
				return false
			var below: Array = _game.terrain.surface_point(player.global_position)
			var height: float = player.global_position.y - below[0].y
			print("mission seed %d: %d deposits, %d ore" % [_game.seed_value, _game.deposits.size(), _game.ores.size()])
			print("after %.1fs: on floor %s, %.2f m above the ground, battery %.1f, warmth %.0f lit by '%s'" % [_elapsed, player.is_on_floor(), height, _game.battery, _game.warmth, _game.lit_by])
			if !player.is_on_floor() or absf(height) > 1.5:
				push_error("player isn't standing on the ground")
			print(_game.debug_cables())
			_foundry = _game.built[-1]
			_rig = _game.built[-2]
			if _game.links.size() != 2:
				push_error("couldn't cable the rig to a foundry to the pod")
			_game.stock += Fixture.COST[&"lab"] + Game.UPGRADES[&"armour"].cost
			_game.alloy += Game.UPGRADES[&"armour"].alloy
			var frame := Fixture.upright(_game.pod.normal)
			for i in 16:
				var lab_spot: Array = _game.terrain.surface_point(_game.pod.global_position + (frame.x * cos(i * 0.4) + frame.z * sin(i * 0.4)) * (8.0 + i * 0.3))
				if _game.can_build(&"lab", lab_spot[0], lab_spot[1]):
					_game.build(&"lab", lab_spot[0], lab_spot[1])
					_lab = _game.built[-1]
					break
			if _lab:
				print("lab: %s" % _game.research(_lab, &"armour"))
			else:
				push_error("couldn't place a lab by the pod")
			_stock_before = _game.stock
			var cable := _game.links[-1]
			player._grab(cable, 1.0)
			player._zip_dir = 1.0
			_ride_from = cable.start() - Vector3.UP * Link.HANG
			_phase = 1
		1:
			if _elapsed < 4.4:
				return false
			print("rode a cable for 0.4 s: %.1f m along, still on %s" % [player.global_position.distance_to(_ride_from), player.zip != null])
			if player.global_position.distance_to(_ride_from) < 2.5:
				push_error("the cable didn't carry us")
			player.let_go()
			var into := _game.links[0]
			player._grab(into, into.length() - 2.5)
			player._zip_dir = 1.0
			var up := player.up_direction
			var towards := _game.pod.global_position - player.global_position
			towards -= up * towards.dot(up)
			player.global_basis = Basis.looking_at(towards.normalized(), up)
			_phase = 5
		5:
			if _elapsed < 4.8:
				return false
			print("rode the rig's cable into the foundry, looking at the pod: now on the pod's cable %s" % [player.zip == _game.links[1]])
			if player.zip != _game.links[1]:
				push_error("didn't carry on through the junction")
			player.let_go()
			_phase = 2
		2:
			if _elapsed < 94.0:
				return false
			print("after 90 s: rig holds %d (%s), foundry %d ore in, %d alloy made (%s), stock %d -> %d, alloy %d, on the cables %d" % [_rig.stored, _rig.stalled if _rig.stalled != "" else "drilling", _foundry.ore_in, _foundry.alloy_out, _foundry.stalled if _foundry.stalled != "" else "smelting", _stock_before, _game.stock, _game.alloy, _game.links.reduce(func(n: int, l: Link) -> int: return n + l.items.size(), 0)])
			if _game.alloy == 0:
				push_error("no alloy reached the pod")
			print("research: armour %s, max health %.0f" % [_game.has(&"armour"), _game.max_health()])
			if !_game.has(&"armour"):
				push_error("the lab didn't finish its research")
			_game.handle(Net.local_id(), &"research", [_lab.net_id, &"stabiliser"])
			var by_soldier := _lab.researching
			_game.commander_peer = Net.local_id()
			_game.handle(Net.local_id(), &"research", [_lab.net_id, &"stabiliser"])
			var by_commander := _lab.researching
			_game.handle(Net.local_id(), &"research", [_lab.net_id, &"stabiliser"])
			_game.commander_peer = 0
			print("research asked for by a soldier: '%s'; by the commander: '%s', then cancelled: '%s'" % [by_soldier, by_commander, _lab.researching])
			if by_soldier != &"" or by_commander != &"stabiliser" or _lab.researching != &"":
				push_error("research from the command chair went wrong")
			var plan_spot: Array = _game.terrain.surface_point(_game.pod.global_position + Fixture.upright(_game.pod.normal).z * 12.0)
			var plan := _game.place_blueprint(&"pylon", plan_spot[0], plan_spot[1])
			for i in plan.hits_needed():
				_game.construct(plan)
			var built := !_game.blueprints.has(plan)
			print("hammered up a pylon blueprint: built %s" % built)
			if !built:
				push_error("hammering didn't put the blueprint up")
			var pylon: Fixture = _game.built[-1]
			var reached := false
			for i in 16:
				var out := pylon.global_position + (Fixture.upright(pylon.normal).x * cos(i * 0.4) + Fixture.upright(pylon.normal).z * sin(i * 0.4)) * 10.0
				var ground: Array = _game.terrain.surface_point(out)
				if _game.can_link_pylon(pylon, ground[0], ground[1]) == "":
					_game.handle(Net.local_id(), &"link_pylon", [pylon.net_id, ground[0], ground[1]])
					reached = true
					break
			var cable: Link = _game.links[-1]
			print("dragged a cable off the pylon to open ground: %s, to a pylon blueprint %s" % [reached, cable.to.blueprint])
			if !reached or cable.from != pylon or !cable.to.blueprint:
				push_error("couldn't drag a cable to a new pylon")
			var far := cable.to
			var early := !cable.blueprint
			for i in far.hits_needed():
				_game.construct(far)
			print("strung before the far pylon was up %s; once it's built, onto it %s, strung %s" % [early, !cable.to.blueprint and _game.built.has(cable.to), !cable.blueprint])
			if early or cable.to.blueprint or cable.blueprint:
				push_error("the cable didn't follow its blueprint end into the built pylon")
			far = cable.to
			_game.handle(Net.local_id(), &"flip", [cable.net_id])
			var flipped := cable.from == far and cable.to == pylon
			_game.handle(Net.local_id(), &"flip", [_game.links[1].net_id])
			print("flipped it: %s; the pod's cable stays in: %s" % [flipped, _game.links[1].to == _game.pod])
			if !flipped or _game.links[1].to != _game.pod:
				push_error("flipping went wrong")
			_game.commander_peer = Net.local_id()
			_game.handle(Net.local_id(), &"flip", [cable.net_id])
			if cable.from != far:
				push_error("the commander turned a cable round")
			_game.handle(Net.local_id(), &"switch", [_rig.net_id])
			var off := !_rig.enabled
			_game.handle(Net.local_id(), &"switch", [_rig.net_id])
			_game.commander_peer = 0
			print("switched the rig off and on: %s, %s" % [off, _rig.enabled])
			if !off or !_rig.enabled:
				push_error("the commander couldn't switch the rig")
			_game.carried = 3
			var stock := _game.stock
			var screen := _game.pod.screen
			var rect: Rect2 = screen._rects[&"hand_in"]
			var uv := rect.get_center() / Vector2(screen.pixels)
			var on := screen.global_transform * Vector3((uv.x - 0.5) * screen.size_m.x, (0.5 - uv.y) * screen.size_m.y, 0.0)
			var normal := screen.global_basis.z.normalized()
			screen.aim(on + normal * 1.2, -normal)
			print("aimed at the pod's HAND IN button: hover %s" % screen.hover)
			screen.press()
			if _game.stock != stock + 3:
				push_error("pressing the pod's screen didn't hand in what we carried")
			print(_game.debug_defence(_game.pod.global_position + Fixture.upright(_game.pod.normal).z * 8.0, _game.pod.global_position))
			var midnight := Sun.time_of(1.5 * PI)
			while midnight < _game.time:
				midnight += Sun.TURN
			_game.time = midnight
			_game.sun.set_time(_game.time)
			print("skipped to midnight, t=%.0f, dark here: %s" % [_game.time, _game.lit_at(player.camera.global_position) == ""])
			_game.handle(Net.local_id(), &"flare", [player.global_position + Vector3.UP * 1.6, Vector3.DOWN])
			_phase = 3
		3:
			if _elapsed < 124.0:
				return false
			for s in _game.spiders:
				print("  spider: %.1f m from the pod, %.1f m from us, after %s" % [s.global_position.distance_to(_game.pod.global_position), s.global_position.distance_to(player.global_position), (s.target.get("kind") if s.target is Fixture else ("a soldier" if s.target else "nothing"))])
			var loud := _game.spiders.filter(func(s: Spider) -> bool: return s.target is Fixture and (s.target as Fixture).noise() > 0.0).size()
			print("30 s into the night: %d spiders (%d going for something loud), %.0f m from the pod, health %.0f, state %s, built %d, rig %s, foundry %s" % [_game.spiders.size(), loud, player.global_position.distance_to(_game.pod.global_position), _game.health, Game.State.keys()[_game.state], _game.built.size(), _rig.stalled if is_instance_valid(_rig) else "destroyed", _foundry.stalled if is_instance_valid(_foundry) else "destroyed"])
			if _game.spiders.is_empty() and _game.state == Game.State.PLAYING:
				push_error("no spiders came")
			var turrets := _game.built.filter(func(f: Fixture) -> bool: return f.kind == &"turret")
			var walls := _game.built.filter(func(f: Fixture) -> bool: return f.kind == &"barricade")
			print("defences: turret fired %d shots, barricades standing %d, worst hull %s" % [Fixture.MAGAZINE - turrets[0].ammo if !turrets.is_empty() else -1, walls.size(), walls.map(func(w: Fixture) -> int: return roundi(w.health)).min() if !walls.is_empty() else -1])
			var flare_lit := _game.flares.any(func(f: Flare) -> bool: return f.global_position.distance_to(player.global_position) < 12.0)
			print("flare thrown at our feet 30 s ago (we may have been shoved): still burning %s, flares left %d, pod hull %.0f" % [flare_lit, _game.flares_left, _game.pod.health])
			if !flare_lit:
				push_error("the flare didn't land and burn by us")
			_game.handle(Net.local_id(), &"launch", [])
			var by_soldier := _game.launch_at
			_game.commander_peer = Net.local_id()
			_game.handle(Net.local_id(), &"launch", [])
			_game.handle(Net.local_id(), &"launch", [])
			var called_off := _game.launch_at
			_game.handle(Net.local_id(), &"launch", [])
			print("launch called by a soldier: %s; by the commander, then called off: %s; called again for %.0f s on" % [by_soldier < INF, called_off < INF, _game.launch_at - _game.time])
			if by_soldier < INF or called_off < INF or _game.launch_at == INF:
				push_error("calling the launch went wrong")
			_phase = 6
		6:
			if _game.state == Game.State.PLAYING:
				return false
			print("after the launch: %s" % _game.outcome)
			if _game.state != Game.State.WON:
				push_error("the commander's launch didn't extract")
			return true
	return false
