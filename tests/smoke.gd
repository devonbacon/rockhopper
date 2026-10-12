extends SceneTree
## Headless smoke test. Generates a few asteroids and reports on them, then
## plays a mission roughly:
## - checks you stand on the rock;
## - marks the deposit nearest the pod and lets the bots work it for a
##   minute in daylight;
## - skips to night and watches the spiders come.
## Run it with --fixed-fps 60 so it goes as fast as it can.

var _game: Game
var _elapsed := 0.0
var _phase := 0
var _stock_before := 0


func _initialize() -> void:
	for seed_value in [1, 2, 3]:
		var rock := Asteroid.new()
		rock.generate(seed_value)
		print("seed %d: %d ms, %d triangles, cave spots %d, surface spots %d" % [seed_value, rock.generate_ms, rock.triangle_count, rock.cave_spots.size(), rock.surface_spots.size()])
		rock.free()
	_game = load("res://game/game.tscn").instantiate()
	root.add_child(_game)


func _physics_process(delta: float) -> bool:
	_elapsed += delta
	var player := _game.player
	match _phase:
		0:
			if _elapsed < 4.0:
				return false
			var below := _game.asteroid.surface_point(player.global_position)
			var height: float = player.global_position.distance_to(below[0])
			print("mission seed %d: %d deposits, %d ore, %d bots" % [_game.seed_value, _game.deposits.size(), _game.ores.size(), _game.bots.size()])
			print("after %.1fs: on floor %s, %.2f m above the surface, battery %.1f, warmth %.0f lit by '%s'" % [_elapsed, player.is_on_floor(), height, _game.battery, _game.warmth, _game.lit_by])
			if !player.is_on_floor() or height > 1.5:
				push_error("player isn't standing on the rock")
			var nearest := _game.deposits[0]
			for deposit in _game.deposits:
				if deposit.global_position.distance_to(_game.pod.global_position) < nearest.global_position.distance_to(_game.pod.global_position):
					nearest = deposit
			_game.toggle_designation(nearest)
			_stock_before = _game.stock
			print("marked a deposit %.0f m from the pod, lit by '%s'" % [nearest.global_position.distance_to(_game.pod.global_position), _game.lit_at(nearest.work_point())])
			_phase = 1
		1:
			if _elapsed < 64.0:
				return false
			var tasks := _game.bots.map(func(b: Bot) -> String: return Bot.Task.keys()[b.task] + (" dark" if b.dark else ""))
			print("after a minute of mining: stock %d -> %d, bots %s" % [_stock_before, _game.stock, tasks])
			if _game.stock <= _stock_before:
				push_error("the bots brought nothing home")
			var forecast := _game.sun.forecast(player.camera.global_position, _game.get_world_3d().direct_space_state, 120)
			var dark := forecast.find(false)
			var light_again := forecast.find(true, maxi(dark, 0))
			if dark >= 0:
				var middle := (dark + (light_again if light_again > dark else 120)) * 0.5
				_game.time += Sun.DAY * middle / 120.0
				_game.sun.set_time(_game.time)
			print("skipped to t=%.0f, the middle of the night here: %s" % [_game.time, _game.lit_at(player.camera.global_position) == ""])
			_phase = 2
		2:
			if _elapsed < 94.0:
				return false
			print("30 s into the night: %d spiders, health %.0f, warmth %.0f, state %s, bots %d, built %d" % [_game.spiders.size(), _game.health, _game.warmth, Game.State.keys()[_game.state], _game.bots.size(), _game.built.size()])
			if _game.spiders.is_empty() and _game.state == Game.State.PLAYING:
				push_error("no spiders came")
			return true
	return false
