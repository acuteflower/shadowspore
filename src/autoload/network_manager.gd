extends Node
## Host-authoritative ENet. Singleplayer is a local host with one player.

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4

signal peer_joined(id: int)
signal peer_left(id: int)


func _ready() -> void:
	multiplayer.peer_connected.connect(func(id: int) -> void: peer_joined.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int) -> void: peer_left.emit(id))


func host_singleplayer() -> Error:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server() and multiplayer.get_peers().is_empty():
		return OK
	return _host(1, "127.0.0.1")


func host_multiplayer(port: int = DEFAULT_PORT) -> Error:
	return _host(MAX_PLAYERS - 1, "*", port)


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _host(max_clients: int, bind_ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind_ip)
	var err: Error = peer.create_server(port, max_clients)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err
