extends SceneTree
## Headless smoke test: generates a few asteroids and reports on them, then
## runs a mission for a few seconds to check the player stands on the rock
## and power flows.

var _game: Game
var _elapsed := 0.0
var _start_height := 0.0


func _initialize() -> void:
	for seed_value in [1, 2, 3]:
		var rock := Asteroid.new()
		rock.generate(seed_value)
		print("seed %d: %d ms, %d triangles, cave spots %d, surface spots %d" % [seed_value, rock.generate_ms, rock.triangle_count, rock.cave_spots.size(), rock.surface_spots.size()])
		rock.free()
	_game = load("res://game/game.tscn").instantiate()
	root.add_child(_game)
	await process_frame
	print("mission: seed %d, ore %d, pod at %s, player at %s" % [_game.seed_value, _game.ores.size(), _game.pod.global_position, _game.player.global_position])


func _physics_process(delta: float) -> bool:
	_elapsed += delta
	var player := _game.player
	if _elapsed < 4.0:
		return false
	var below := _game.asteroid.surface_point(player.global_position)
	var height: float = player.global_position.distance_to(below[0])
	print("after %.1fs: on floor %s, %.2f m above the surface along its radius, speed %.2f, battery %.1f (+%.2f -%.2f), warmth %.0f lit by '%s'" % [_elapsed, player.is_on_floor(), height, player.velocity.length(), _game.battery, _game.power_in, _game.power_out, _game.warmth, _game.lit_by])
	if !player.is_on_floor() or height > 1.5:
		push_error("player isn't standing on the rock")
	_game.build(&"lamp", below[0], below[1])
	print("built a lamp: carried %d, lamps %d" % [_game.carried, _game.built.size()])
	return true
