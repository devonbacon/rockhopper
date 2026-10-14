class_name Metrics
extends RefCounted
## Server: a log of how a mission goes, a JSON object a line, for reading
## back after a playtest (tools/session_summary.py). One file per server
## run, under user://sessions, every mission it hosts in it.

const SAMPLE_EVERY := 30.0
const DIR := "user://sessions"

static var _file: FileAccess

var game: Game
## Per peer (0 for the team as a whole): running counts of what they did.
var tallies := {}
## Who each peer was, kept after they leave.
var names := {}
var _sample_in := 0.0


func _init(for_game: Game) -> void:
	game = for_game
	if !_file:
		DirAccess.make_dir_recursive_absolute(DIR)
		var stamp := Time.get_datetime_string_from_system().replace(":", "-")
		_file = FileAccess.open("%s/%s.jsonl" % [DIR, stamp], FileAccess.WRITE)
		if !_file:
			push_warning("can't write metrics to %s" % DIR)
			return
		print("metrics: %s" % ProjectSettings.globalize_path(_file.get_path()))
	note(&"mission", {build = Net.version, seed = game.seed_value, players = Net.peers.size()})


func note(kind: StringName, data := {}) -> void:
	if !_file:
		return
	var line := {t = snappedf(game.time, 0.1), at = int(Time.get_unix_time_from_system()), kind = kind}
	for key in data:
		line[key] = plain(data[key])
	_file.store_line(JSON.stringify(line))
	_file.flush()


func add(peer: int, key: StringName, amount := 1.0) -> void:
	if !tallies.has(peer):
		tallies[peer] = {}
	tallies[peer][key] = tallies[peer].get(key, 0.0) + amount


func tick(delta: float) -> void:
	_sample_in -= delta
	if _sample_in > 0.0:
		return
	_sample_in = SAMPLE_EVERY
	var kinds := {}
	var damaged := 0
	for fixture in game.built:
		kinds[fixture.kind] = kinds.get(fixture.kind, 0) + 1
		if fixture.health < fixture.max_health:
			damaged += 1
	var soldiers := {}
	for peer in game.bodies:
		if peer == game.commander_peer:
			continue
		var s: Dictionary = game.stats[peer]
		var body: Node3D = game.bodies[peer]
		soldiers[game.name_of(peer)] = {health = s.health, warmth = s.warmth, carried = s.carried, gear = s.gear, down = s.down >= 0.0, from_pod = body.global_position.distance_to(game.pod.global_position)}
	note(&"sample", {
		day = game.time / Sun.TURN,
		night = game._night,
		stock = game.stock,
		alloy = game.alloy,
		battery = game.battery,
		power_in = game.power_in,
		power_out = game.power_out,
		pod_health = game.pod.health,
		spiders = game.spiders.size(),
		holes = game.holes.size(),
		built = kinds,
		damaged = damaged,
		blueprints = game.blueprints.size(),
		cables = game.links.size(),
		researched = game.researched.keys(),
		commander = game.name_of(game.commander_peer) if game.commander_peer != 0 else "",
		soldiers = soldiers,
		tallies = named_tallies(),
	})


func finish(state: String, text: String) -> void:
	note(&"end", {result = state, outcome = text, stock = game.stock, alloy = game.alloy, tallies = named_tallies()})


func named_tallies() -> Dictionary:
	var named := {}
	for peer in tallies:
		named["team" if peer == 0 else names.get(peer, game.name_of(peer))] = tallies[peer]
	return named


## What's loggable as JSON: vectors to rounded lists, names to strings,
## a world thing by its kind.
func plain(value: Variant) -> Variant:
	if value is Vector3:
		return [snappedf(value.x, 0.1), snappedf(value.y, 0.1), snappedf(value.z, 0.1)]
	if value is float:
		return snappedf(value, 0.01)
	if value is StringName:
		return String(value)
	if value is Object:
		return String(value.kind) if "kind" in value else value.get_class()
	if value is Array or value is PackedStringArray:
		return Array(value).map(plain)
	if value is Dictionary:
		var out := {}
		for key in value:
			out[String(key) if key is StringName else key] = plain(value[key])
		return out
	return value
