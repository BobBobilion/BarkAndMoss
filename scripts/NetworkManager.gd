# NetworkManager.gd
# This script manages the entire network session, from connection to player data.
extends Node

# --- Signals ---
signal player_list_changed
signal connection_failed(reason: String)

# --- Properties ---
var players: Dictionary = {}
var connection_timeout_timer: Timer

@export var human_scene: PackedScene = preload("res://scenes/Player.tscn")
@export var dog_scene: PackedScene = preload("res://scenes/Dog.tscn")


# --- Engine Callbacks ---

func _ready() -> void:
	"""Connects multiplayer signals."""
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


# --- Public Methods ---

func host_game() -> void:
	"""Creates a server and sets up the host player."""
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(GameConstants.NETWORK.DEFAULT_PORT, GameConstants.NETWORK.MAX_PLAYERS)
	if error != OK:
		var reason = "Failed to create host. Port %d might be in use." % GameConstants.NETWORK.DEFAULT_PORT
		push_error("NetworkManager: " + reason)
		connection_failed.emit(reason)
		return

	multiplayer.multiplayer_peer = peer
	
	# The host is player 1.
	_add_player(GameConstants.NETWORK.SERVER_ID, "HostPlayer")
	
	# Note: Role assignment will happen through character selection or lobby


func join_game(ip_address: String) -> void:
	"""Joins an existing server at the given IP address."""
	var peer := ENetMultiplayerPeer.new()
	peer.create_client(ip_address, 8080)  # Use direct constant for now
	multiplayer.multiplayer_peer = peer


func disconnect_from_game() -> void:
	"""Disconnect from the current multiplayer session and clean up."""
	print("NetworkManager: Disconnecting from game...")
	
	# Clear player data
	players.clear()
	
	# Close the multiplayer peer connection
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	# Emit signal to notify about player list change (now empty)
	player_list_changed.emit()
	
	print("NetworkManager: Disconnected from game")


# --- Signal Handlers ---

func _on_peer_connected(_id: int) -> void:
	"""Handles a new peer connecting to the server."""
	# This runs on the SERVER when a new client connects.
	# We wait for the client to register itself via RPC.
	pass


func _on_peer_disconnected(id: int) -> void:
	"""Handles a peer disconnecting from the server."""
	if players.has(id):
		players.erase(id)
		player_list_changed.emit()
		
		# Also remove their character from the game world if it exists
		var player_node: Node = get_tree().get_root().find_child("Player_" + str(id), true, false)
		if is_instance_valid(player_node):
			player_node.queue_free()


# --- Private Methods ---

func _add_player(id: int, player_name: String) -> void:
	"""Adds a new player to the players dictionary."""
	players[id] = {"name": player_name, "role": "unassigned"}
	player_list_changed.emit()


# --- RPCs (Remote Procedure Calls) ---

@rpc("authority")
func register_player(player_name: String) -> void:
	"""
	[Client->Server] Called by a client on the server to announce its arrival.
	"""
	var id: int = multiplayer.get_remote_sender_id()
	_add_player(id, player_name)


@rpc("authority", "call_local")
func claim_role(role: String) -> void:
	"""
	[Client->Server] Called by a client to claim a role (human or dog).
	The host can also call this locally.
	"""
	var id: int = multiplayer.get_remote_sender_id()
	if id == 0: # ID is 0 if called locally by the host
		id = 1  # Server ID

	if not players.has(id):
		return

	# Check if role is already taken
	for p_id in players:
		if players[p_id].role == role:
			return # Role is taken, do nothing.

	players[id].role = role
	
	# Tell everyone about the change
	update_player_list.rpc(players)


@rpc("any_peer", "call_local")
func update_player_list(new_player_list: Dictionary) -> void:
	"""
	[Server->All] The server sends the complete player list to all clients
	to keep everyone in sync.
	"""
	self.players = new_player_list
	player_list_changed.emit()
		

@rpc("authority", "call_local")
func request_start_game() -> void:
	"""
	[Client->Server] The host calls this to start the game for everyone.
	The server validates that all players are ready before proceeding.
	"""
	# Ensure everyone has a role before starting
	for p_id in players:
		if players[p_id].role == "unassigned":
			return
			
	# If all checks pass, tell everyone to load the main scene
	load_main_scene.rpc()


@rpc("any_peer", "call_local")
func load_main_scene() -> void:
	"""[Server->All] Loads the main game scene for all players."""
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
