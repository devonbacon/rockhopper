extends Node
## Headless smoke test. Generates a few maps and reports on them, then
## plays a mission roughly:
## - checks you stand on the ground;
## - builds a drill rig on the deposit nearest the pod and lets it and the
##   rover work for a minute and a half in daylight;
## - skips to midnight and watches the spiders come.
## Run it as a scene, with --fixed-fps 60 so it goes as fast as it can:
## Godot --headless --fixed-fps 60 --path . res://tests/smoke.tscn

var _game: Game
var _elapsed := 0.0
var _phase := 0
var _stock_before := 0
var _rig: Fixture
var _lab: Fixture
var _plan: Fixture


func _ready() -> void:
	for seed_value in [1, 2, 3]:
		var terrain := Terrain.new()
		terrain.generate(seed_value)
		var polygons := terrain.navigation.navigation_mesh.get_polygon_count()
		print("seed %d: %d ms, %d triangles, %d nav polygons, cave spots %d, surface spots %d" % [seed_value, terrain.generate_ms, terrain.triangle_count, polygons, terrain.cave_spots.size(), terrain.surface_spots.size()])
		if polygons == 0:
			push_error("nothing baked for rovers to drive on")
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
			print("mission seed %d: %d deposits, %d ore, %d rovers" % [_game.seed_value, _game.deposits.size(), _game.ores.size(), _game.rovers.size()])
			print("after %.1fs: on floor %s, %.2f m above the ground, battery %.1f, warmth %.0f lit by '%s'" % [_elapsed, player.is_on_floor(), height, _game.battery, _game.warmth, _game.lit_by])
			if !player.is_on_floor() or absf(height) > 1.5:
				push_error("player isn't standing on the ground")
			var nearest := _game.deposits[0]
			for deposit in _game.deposits:
				if deposit.global_position.distance_to(_game.pod.global_position) < nearest.global_position.distance_to(_game.pod.global_position):
					nearest = deposit
			if !_game.can_build(&"drill", nearest.global_position):
				push_error("can't build a rig on the nearest deposit")
			_game.build(&"drill", nearest.global_position, nearest.normal)
			_rig = nearest.rig
			_game.stock += Fixture.COST[&"lab"] + Game.UPGRADES[&"armour"].cost
			var lab_spot: Array = _game.terrain.surface_point(_game.pod.global_position - Fixture.upright(_game.pod.normal).x * 9.0)
			if _game.can_build(&"lab", lab_spot[0]):
				_game.build(&"lab", lab_spot[0], lab_spot[1])
				_lab = _game.built[-1]
				print("lab: %s" % _lab.screen.pressed.call(&"armour"))
			else:
				push_error("couldn't place a lab by the pod")
			var plan_spot: Array = _game.terrain.surface_point(_game.pod.global_position + Fixture.upright(_game.pod.normal).z * 12.0)
			_plan = _game.place_blueprint(&"lamp", plan_spot[0], plan_spot[1])
			_game.commander_peer = Net.local_id()
			_game.handle(Net.local_id(), &"order", [[_game.rovers[0].net_id], &"build", Vector3.INF, _plan.net_id])
			_game.commander_peer = 0
			_stock_before = _game.stock
			var path := _game.terrain.find_path(_game.rovers[0].global_position, _rig.global_position)
			print("built a rig %.0f m from the pod; path for the rover: %d points, ending %.1f m from it" % [nearest.global_position.distance_to(_game.pod.global_position), path.size(), path[-1].distance_to(_rig.global_position) if !path.is_empty() else INF])
			_phase = 1
		1:
			if _elapsed < 94.0:
				return false
			var rover := _game.rovers[0]
			print("after 90 s: rig holds %d (%s), stock %d -> %d, rover %s carrying %d, %.0f m from the pod" % [_rig.stored if is_instance_valid(_rig) else -1, (_rig.stalled if _rig.stalled != "" else "drilling") if is_instance_valid(_rig) else "destroyed", _stock_before, _game.stock, Rover.Task.keys()[rover.task], rover.cargo, rover.global_position.distance_to(_game.pod.global_position)])
			if _game.stock <= _stock_before:
				push_error("the rover brought nothing home")
			print("rover sent to build a lamp blueprint: built %s, lamps %d" % [!is_instance_valid(_plan), _game.built.filter(func(f: Fixture) -> bool: return f.kind == &"lamp").size()])
			if is_instance_valid(_plan):
				push_error("the rover didn't build the blueprint")
			print("research: armour %s, max health %.0f" % [_game.has(&"armour"), _game.max_health()])
			if !_game.has(&"armour"):
				push_error("the lab didn't finish its research")
			var screen := rover.screen
			var rect: Rect2 = screen._rects[&"home"]
			var uv := rect.get_center() / Vector2(screen.pixels)
			var on := screen.global_transform * Vector3((uv.x - 0.5) * screen.size_m.x, (0.5 - uv.y) * screen.size_m.y, 0.0)
			var normal := screen.global_basis.z.normalized()
			screen.aim(on + normal * 1.2, -normal)
			print("aimed at the rover's GO HOME button: hover %s" % screen.hover)
			screen.press()
			if rover.order != &"home":
				push_error("pressing the rover's screen didn't send it home")
			var midnight := (1.5 * PI - Sun.START) / TAU * Sun.DAY
			while midnight < _game.time:
				midnight += Sun.DAY
			_game.time = midnight
			_game.sun.set_time(_game.time)
			print("skipped to midnight, t=%.0f, dark here: %s" % [_game.time, _game.lit_at(player.camera.global_position) == ""])
			_game.handle(Net.local_id(), &"flare", [player.global_position + Vector3.UP * 1.6, Vector3.DOWN])
			_phase = 2
		2:
			if _elapsed < 124.0:
				return false
			if !_game.rovers.is_empty():
				print("sent home 30 s ago: rover %s, %.0f m from the pod" % [Rover.Task.keys()[_game.rovers[0].task], _game.rovers[0].global_position.distance_to(_game.pod.global_position)])
			print("30 s into the night: %d spiders, health %.0f, state %s, rovers %d, built %d, rig %s" % [_game.spiders.size(), _game.health, Game.State.keys()[_game.state], _game.rovers.size(), _game.built.size(), _rig.stalled if is_instance_valid(_rig) else "destroyed"])
			if _game.spiders.is_empty() and _game.state == Game.State.PLAYING:
				push_error("no spiders came")
			var flare_lit := _game.flares.any(func(f: Flare) -> bool: return f.global_position.distance_to(player.global_position) < 12.0)
			print("flare thrown at our feet 30 s ago (we may have been shoved): still burning %s, flares left %d, pod hull %.0f" % [flare_lit, _game.flares_left, _game.pod.health])
			if !flare_lit:
				push_error("the flare didn't land and burn by us")
			return true
	return false
