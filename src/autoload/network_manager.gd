extends Node
## Host-authoritative ENet. Singleplayer is a local host with one player.

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4
const IDENTITY_PATH: String = "user://coop_identity.key"
const IDENTITY_BYTES: int = 32

signal peer_joined(id: int)
signal peer_left(id: int)

var _guest_owners: Dictionary = {} ## ENet peer -> durable, host-only board owner
var _identity: PackedByteArray


func _ready() -> void:
	multiplayer.peer_connected.connect(func(id: int) -> void: peer_joined.emit(id))
	multiplayer.peer_disconnected.connect(_on_peer_left)
	var api: SceneMultiplayer = multiplayer as SceneMultiplayer
	api.auth_timeout = 20.0 ## a guest can still be loading the world when the host asks for their identity
	api.peer_authenticating.connect(_on_authenticating)
	api.peer_authentication_failed.connect(func(id: int) -> void: _guest_owners.erase(id))


func _on_peer_left(id: int) -> void:
	peer_left.emit(id) ## the world can store the departing player's state while the binding is still known
	_guest_owners.erase(id)


func guest_owner(peer: int) -> String:
	return String(_guest_owners.get(peer, ""))


func guest_peer(owner: String) -> int:
	var peer: Variant = _guest_owners.find_key(owner)
	return int(peer) if peer != null else 0


func _local_identity() -> PackedByteArray:
	if _identity.size() == IDENTITY_BYTES:
		return _identity
	_identity = FileAccess.get_file_as_bytes(IDENTITY_PATH) if FileAccess.file_exists(IDENTITY_PATH) else PackedByteArray()
	if _identity.size() == IDENTITY_BYTES:
		return _identity
	_identity = Crypto.new().generate_random_bytes(IDENTITY_BYTES)
	var file: FileAccess = FileAccess.open(IDENTITY_PATH, FileAccess.WRITE)
	if file != null:
		file.store_buffer(_identity)
	return _identity


func _on_authenticating(id: int) -> void:
	if multiplayer.is_server():
		var api: SceneMultiplayer = multiplayer as SceneMultiplayer
		## Scope a guest's credential to this host. The installation's private key stays local.
		api.send_auth(id, ("shadowspore-coop:" + _local_identity().hex_encode()).sha256_buffer())


func _authenticate(id: int, data: PackedByteArray) -> void:
	var api: SceneMultiplayer = multiplayer as SceneMultiplayer
	if data.size() != IDENTITY_BYTES:
		api.disconnect_peer(id)
		return
	if multiplayer.is_server():
		var owner: String = "guest:" + data.hex_encode().sha256_text()
		var current: int = guest_peer(owner)
		if current != 0 and current != id:
			api.disconnect_peer(id)
			return
		_guest_owners[id] = owner
	elif id == 1:
		var credential: PackedByteArray = Crypto.new().hmac_digest(HashingContext.HASH_SHA256, _local_identity(), data)
		if api.send_auth(id, credential) != OK:
			api.disconnect_peer(id)
			return
	api.complete_auth(id)


func host_singleplayer() -> Error:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return OK
	leave()
	return OK


func host_multiplayer(port: int = DEFAULT_PORT) -> Error:
	return _host(MAX_PLAYERS - 1, "*", port)


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err == OK:
		_guest_owners.clear()
		(multiplayer as SceneMultiplayer).auth_callback = _authenticate
		multiplayer.multiplayer_peer = peer
	return err


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	(multiplayer as SceneMultiplayer).auth_callback = Callable()
	_guest_owners.clear()


func _host(max_clients: int, bind_ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind_ip)
	var err: Error = peer.create_server(port, max_clients)
	if err == OK:
		_guest_owners.clear()
		(multiplayer as SceneMultiplayer).auth_callback = _authenticate
		multiplayer.multiplayer_peer = peer
	return err
