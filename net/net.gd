extends Node
## Networking, over WebSockets so browsers can join. Solo needs none of
## it; a host is a server with a local player; a dedicated server
## (--server) has none; clients mirror the server. Every RPC lives on this
## autoload, so its path is the same on every peer.
##
## Each mission starts in the lobby, on the map it'll be played on: the
## leader (whoever's been connected longest) picks where the pod lands,
## everyone says they're ready, and the leader drops it. The leader can
## send everyone back to the lobby mid-mission, and a finished mission
## goes back to it on a new map.

enum Mode { SOLO, HOST, SERVER, CLIENT }

const PORT := 7777
const MAX_PEERS := 8
## A peer that hasn't said hello by then (an older build, say) is dropped.
const HELLO_WITHIN := 10.0

var mode := Mode.SOLO
var seed_value := 0
var start_time := 0.0
var player_name := "Soldier"
var role := &"soldier"
## peer id -> {name, role}
var peers := {}
var game: Game
## The lobby: who leads, who's ready (peer id -> true), and where the
## leader means to land; and where the pod's landed, once it has (INF in
## the lobby).
var leader := 0
var ready_peers := {}
var pick := Vector3.INF
var landing := Vector3.INF
## A hash of the game's scripts and shaders: a client and server must match.
var version := ""
## Why the last game ended, for the menu to show.
var last_error := ""
## Whether the menu's acted on the command line yet: once only, so being
## dropped back to it doesn't rejoin.
var launched := false
var _target := ""

signal status(text: String)


func _ready() -> void:
	version = _source_hash()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: status.emit("Couldn't reach %s" % _target))
	multiplayer.server_disconnected.connect(_on_server_gone)


func _source_hash() -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_MD5)
	for path in _sources("res://"):
		hashing.update(path.to_utf8_buffer())
		hashing.update(FileAccess.get_file_as_string(path).replace("\r", "").to_utf8_buffer())
	return hashing.finish().hex_encode().left(8)


func _sources(dir: String) -> PackedStringArray:
	var found := PackedStringArray()
	var subs := DirAccess.get_directories_at(dir)
	subs.sort()
	for sub in subs:
		if !sub.begins_with(".") and !(sub in ["addons", "tests", "tools"]):
			found.append_array(_sources(dir.path_join(sub)))
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for file in files:
		if file.get_extension() in ["gd", "gdshader"]:
			found.append(dir.path_join(file))
	return found


func authority() -> bool:
	return mode != Mode.CLIENT


func networked() -> bool:
	return mode != Mode.SOLO


func local_id() -> int:
	return 1 if mode == Mode.SOLO else multiplayer.get_unique_id()


func has_local_player() -> bool:
	return mode != Mode.SERVER


func start_server(port: int, dedicated: bool) -> Error:
	var peer := _socket()
	var err := peer.create_server(port, "*")
	if err != OK:
		status.emit("Couldn't listen on port %d (%s)" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.SERVER if dedicated else Mode.HOST
	if seed_value == 0:
		seed_value = randi()
	peers.clear()
	if !dedicated:
		peers[1] = {name = player_name, role = role}
	_update_leader()
	print("serving on port %d, seed %d, build %s" % [port, seed_value, version])
	_start_game()
	return OK


## `url` is ws://host:port, wss://..., or just host[:port].
func join(url: String) -> Error:
	if !url.contains("://"):
		url = "ws://" + url
	if url.begins_with("ws://") and url.count(":") < 2:
		url += ":%d" % PORT
	var peer := _socket()
	var err := peer.create_client(url)
	if err != OK:
		status.emit("Couldn't connect (%s)" % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	_target = url
	last_error = ""
	status.emit("Connecting to %s..." % url)
	return OK


func _socket() -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = 1 << 20
	peer.outbound_buffer_size = 1 << 20
	return peer


## Back to solo, as after leaving a game.
func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = Mode.SOLO
	peers.clear()
	seed_value = 0
	leader = 0
	ready_peers.clear()
	pick = Vector3.INF
	landing = Vector3.INF


func leading() -> bool:
	return mode == Mode.SOLO or leader == local_id()


## Server (or solo): everyone back to the lobby, on a new map.
func new_map() -> void:
	seed_value = randi()
	to_lobby()


## Server (or solo): everyone back to the lobby, on the same map.
func to_lobby() -> void:
	start_time = 0.0
	pick = Vector3.INF
	landing = Vector3.INF
	ready_peers.clear()
	if networked():
		for id in peers:
			if id != 1:
				welcome.rpc_id(id, seed_value, 0.0, Vector3.INF)
		share_lobby()
	_start_game()


func _update_leader() -> void:
	if !peers.has(leader):
		leader = peers.keys()[0] if !peers.is_empty() else 0


## Server: tells everyone how the lobby stands.
func share_lobby() -> void:
	if networked() and authority():
		lobby_state.rpc(leader, ready_peers, pick)


func _start_game() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred("res://game/game.tscn")


func _on_connected() -> void:
	status.emit("Connected; loading...")
	hello.rpc_id(1, player_name, role, version)


func _on_server_gone() -> void:
	leave()
	get_tree().change_scene_to_file.call_deferred("res://menu/menu.tscn")


func _on_peer_connected(id: int) -> void:
	print("peer %d connected" % id)
	if !authority():
		return
	if multiplayer.get_peers().size() > MAX_PEERS:
		print("full; dropping peer %d" % id)
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	get_tree().create_timer(HELLO_WITHIN).timeout.connect(func() -> void:
		if multiplayer.multiplayer_peer and !peers.has(id) and multiplayer.get_peers().has(id):
			print("peer %d never said hello; dropping it" % id)
			multiplayer.multiplayer_peer.disconnect_peer(id))


func _on_peer_disconnected(id: int) -> void:
	print("peer %d left" % id)
	# Clients hear of each other leaving too; the server's the one to tell.
	if !multiplayer.is_server() or !peers.has(id):
		return
	peers.erase(id)
	ready_peers.erase(id)
	_update_leader()
	roster.rpc(peers)
	share_lobby()
	if is_instance_valid(game):
		game.remove_soldier(id)
	# Everyone's gone: a fresh lobby for whoever comes next.
	if mode == Mode.SERVER and peers.is_empty() and landing != Vector3.INF:
		new_map()


@rpc("any_peer", "reliable")
func hello(name: String, chosen_role: StringName, client_version: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if client_version != version:
		print("%s is on build %s, not %s; turning them away" % [name, client_version, version])
		turned_away.rpc_id(id, version)
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if multiplayer.multiplayer_peer and multiplayer.get_peers().has(id):
				multiplayer.multiplayer_peer.disconnect_peer(id))
		return
	peers[id] = {name = name, role = chosen_role}
	_update_leader()
	print("%s joined as %s" % [name, chosen_role])
	welcome.rpc_id(id, seed_value, game.time if game else 0.0, landing)
	roster.rpc(peers)
	share_lobby()


@rpc("authority", "reliable")
func turned_away(server_version: String) -> void:
	last_error = "The server's on build %s and you're on %s. Pull to match it, or redeploy the server." % [server_version, version]
	status.emit(last_error)


@rpc("authority", "reliable")
func welcome(seed_from_server: int, time: float, landed_at: Vector3) -> void:
	seed_value = seed_from_server
	start_time = time
	landing = landed_at
	_start_game()


@rpc("authority", "reliable")
func lobby_state(new_leader: int, now_ready: Dictionary, picked: Vector3) -> void:
	leader = new_leader
	ready_peers = now_ready
	pick = picked


## Client to server: a lobby choice (or the leader's call back to it).
@rpc("any_peer", "reliable")
func lobby_request(action: StringName, args: Array) -> void:
	if is_instance_valid(game):
		game.lobby_handle(multiplayer.get_remote_sender_id(), action, args)


## Server to clients: the pod's coming down here.
@rpc("authority", "reliable")
func land(at: Vector3) -> void:
	landing = at
	if is_instance_valid(game):
		game.begin_landing(at)


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
