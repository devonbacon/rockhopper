extends Node
## Networking. Solo needs none of it; a host is a server with a local
## player; a dedicated server (--server) has none; clients mirror the
## server. Every RPC lives on this autoload, so its path is the same on
## every peer.

enum Mode { SOLO, HOST, SERVER, CLIENT }

const PORT := 7777
const MAX_PEERS := 8

var mode := Mode.SOLO
var seed_value := 0
var start_time := 0.0
var player_name := "Soldier"
var role := &"soldier"
## peer id -> {name, role}
var peers := {}
var game: Game

signal status(text: String)


func authority() -> bool:
	return mode != Mode.CLIENT


func networked() -> bool:
	return mode != Mode.SOLO


func local_id() -> int:
	return 1 if mode == Mode.SOLO else multiplayer.get_unique_id()


func has_local_player() -> bool:
	return mode != Mode.SERVER


func start_server(port: int, dedicated: bool) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err != OK:
		status.emit("Couldn't listen on port %d (%s)" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.SERVER if dedicated else Mode.HOST
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if seed_value == 0:
		seed_value = randi()
	peers.clear()
	if !dedicated:
		peers[1] = {name = player_name, role = role}
	print("serving on port %d, seed %d" % [port, seed_value])
	_start_game()
	return OK


func join(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		status.emit("Couldn't connect (%s)" % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: status.emit("Couldn't reach %s:%d" % [address, port]))
	multiplayer.server_disconnected.connect(_on_server_gone)
	status.emit("Connecting to %s:%d..." % [address, port])
	return OK


## Back to solo, as after leaving a game.
func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = Mode.SOLO
	peers.clear()
	seed_value = 0


## Server: a new mission for everyone, on a new seed.
func restart() -> void:
	seed_value = randi()
	start_time = 0.0
	for id in peers:
		if id != 1:
			welcome.rpc_id(id, seed_value, 0.0)
	_start_game()


func _start_game() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred("res://game/game.tscn")


func _on_connected() -> void:
	status.emit("Connected; loading...")
	hello.rpc_id(1, player_name, role)


func _on_server_gone() -> void:
	leave()
	get_tree().change_scene_to_file.call_deferred("res://menu/menu.tscn")


func _on_peer_connected(id: int) -> void:
	print("peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	print("peer %d left" % id)
	peers.erase(id)
	roster.rpc(peers)
	if is_instance_valid(game):
		game.remove_soldier(id)


@rpc("any_peer", "reliable")
func hello(name: String, chosen_role: StringName) -> void:
	var id := multiplayer.get_remote_sender_id()
	peers[id] = {name = name, role = chosen_role}
	print("%s joined as %s" % [name, chosen_role])
	welcome.rpc_id(id, seed_value, game.time if game else 0.0)
	roster.rpc(peers)


@rpc("authority", "reliable")
func welcome(seed_from_server: int, time: float) -> void:
	seed_value = seed_from_server
	start_time = time
	_start_game()


@rpc("authority", "reliable")
func roster(list: Dictionary) -> void:
	peers = list


## Client to server: the client's game is loaded and its soldier's ready.
@rpc("any_peer", "reliable")
func ready_to_play() -> void:
	if is_instance_valid(game):
		game.add_soldier(multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func request(action: StringName, args: Array) -> void:
	if is_instance_valid(game):
		game.handle(multiplayer.get_remote_sender_id(), action, args)


@rpc("any_peer", "unreliable_ordered")
func move(pos: Vector3, yaw: float, pitch: float) -> void:
	if is_instance_valid(game):
		game.remote_move(multiplayer.get_remote_sender_id(), pos, yaw, pitch)


@rpc("authority", "unreliable_ordered")
func snapshot(data: Array) -> void:
	if is_instance_valid(game):
		game.apply_snapshot(data)


@rpc("authority", "unreliable_ordered")
func slow_snapshot(data: Array) -> void:
	if is_instance_valid(game):
		game.apply_slow(data)


## Server to one client: a reply, a respawn, a tracer, an announcement.
@rpc("authority", "reliable")
func event(kind: StringName, args: Array) -> void:
	if is_instance_valid(game):
		game.on_event(kind, args)


@rpc("authority", "unreliable")
func effect(kind: StringName, args: Array) -> void:
	if is_instance_valid(game):
		game.on_event(kind, args)
