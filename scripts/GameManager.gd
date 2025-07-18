class_name GameManager
extends Node

# --- Signals ---
signal player_spawned(player: Node3D)
signal game_started()
signal game_ended()

# --- Constants ---
const PLAYER_SCENE_PATH: String = "res://scenes/Player.tscn"
const DOG_SCENE_PATH: String = "res://scenes/Dog.tscn"
const SPAWN_HEIGHT_OFFSET: float = 5.0  # Height above terrain to spawn players

# --- Properties ---
var players: Dictionary = {}  # peer_id -> player_node
var is_server: bool = false
var world_node: Node3D = null
var chunk_manager: ChunkManager = null  # Changed from world_generator

# Game state
var is_game_started: bool = false
var selected_character_types: Dictionary = {}  # peer_id -> character_type

# --- Engine Callbacks ---
func _ready() -> void:
	"""Initialize the game manager."""
	# Add to groups for easy finding
	add_to_group("game_manager")
	
	# Set up multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	# Check if we're the server
	is_server = multiplayer.is_server()
	
	# Create chunk manager
	_create_chunk_manager()
	
	print("GameManager: Initialized (Server: %s)" % is_server)

# --- Public Methods ---
func initialize_world(world: Node3D) -> void:
	"""Set the world node reference and initialize chunk manager."""
	world_node = world
	if chunk_manager:
		chunk_manager.initialize_world(world)

func start_game() -> void:
	"""Start the game and spawn initial players."""
	if not multiplayer.is_server():
		return
		
	is_game_started = true
	game_started.emit()
	
	# Spawn all connected players at origin initially
	# Chunks will load around them automatically
	for peer_id in multiplayer.get_peers():
		_spawn_player(peer_id)
	
	# Spawn server player
	_spawn_player(multiplayer.get_unique_id())
	
	print("GameManager: Game started!")

func set_character_selection(peer_id: int, character_type: String) -> void:
	"""Store character selection for a player."""
	selected_character_types[peer_id] = character_type
	print("GameManager: Player %d selected character: %s" % [peer_id, character_type])

func get_spawn_position() -> Vector3:
	"""Get a valid spawn position near the origin."""
	# Start at origin and find ground level
	var spawn_pos := Vector3.ZERO
	
	# Get terrain height from chunk manager
	if chunk_manager:
		var height := chunk_manager.get_height_at_position(spawn_pos)
		spawn_pos.y = height + SPAWN_HEIGHT_OFFSET
	else:
		spawn_pos.y = SPAWN_HEIGHT_OFFSET
	
	return spawn_pos

func respawn_player(peer_id: int) -> void:
	"""Respawn a player at a new position."""
	if not multiplayer.is_server():
		return
		
	if players.has(peer_id):
		var player = players[peer_id]
		var spawn_pos := get_spawn_position()
		player.position = spawn_pos
		
		# Reset player state
		if player.has_method("reset_health"):
			player.reset_health()

# --- Private Methods ---
func _create_chunk_manager() -> void:
	"""Create and configure the chunk manager."""
	chunk_manager = ChunkManager.new()
	chunk_manager.name = "ChunkManager"
	add_child(chunk_manager)
	
	print("GameManager: Created ChunkManager")

func _spawn_player(peer_id: int) -> void:
	"""Spawn a player for the given peer ID."""
	if players.has(peer_id):
		print("GameManager: Player %d already spawned" % peer_id)
		return
	
	# Get character type (default to human if not selected)
	var character_type: String = selected_character_types.get(peer_id, "human")
	
	# Load appropriate scene
	var player_scene_path: String = DOG_SCENE_PATH if character_type == "dog" else PLAYER_SCENE_PATH
	var player_scene := load(player_scene_path) as PackedScene
	if not player_scene:
		push_error("GameManager: Failed to load player scene: %s" % player_scene_path)
		return
	
	# Instance player
	var player := player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	
	# Set multiplayer authority
	player.set_multiplayer_authority(peer_id)
	
	# Set spawn position
	player.position = get_spawn_position()
	
	# Add to world
	if world_node:
		world_node.add_child(player)
	else:
		add_child(player)
	
	# Track player
	players[peer_id] = player
	
	# Register player with chunk manager for chunk loading
	if chunk_manager:
		# Give the system a frame to initialize player position
		await get_tree().process_frame
		# Now update chunk manager with initial position
		update_player_chunk_position(player)
	
	# Emit signal
	player_spawned.emit(player)
	
	print("GameManager: Spawned %s for peer %d at %v" % [character_type, peer_id, player.position])

func _on_peer_connected(id: int) -> void:
	"""Handle peer connection."""
	print("GameManager: Peer connected: %d" % id)
	
	# If game already started, spawn the new player
	if is_game_started and multiplayer.is_server():
		_spawn_player(id)

func _on_peer_disconnected(id: int) -> void:
	"""Handle peer disconnection."""
	print("GameManager: Peer disconnected: %d" % id)
	
	# Remove player
	if players.has(id):
		var player = players[id]
		player.queue_free()
		players.erase(id)
		
		# Remove from chunk manager tracking
		if chunk_manager:
			chunk_manager.player_tracker.remove_player(id)

# --- Public Methods for Chunk System ---
func get_chunk_manager() -> ChunkManager:
	"""Get the chunk manager instance."""
	return chunk_manager

func get_biome_manager() -> BiomeManager:
	"""Get the biome manager instance from the chunk generator."""
	if chunk_manager and chunk_manager.chunk_generator:
		return chunk_manager.chunk_generator.biome_manager
	return null

func update_player_chunk_position(player: Node3D) -> void:
	"""Update player position in chunk system. Called by Player/Dog scripts."""
	if not chunk_manager or not is_instance_valid(player):
		return
	
	# Get player ID from node
	var peer_id := player.get_multiplayer_authority()
	
	# Update position and velocity in chunk manager
	var velocity := Vector3.ZERO
	if "velocity" in player:
		velocity = player.velocity
	
	chunk_manager.player_tracker.update_player_position(peer_id, player.global_position, velocity)
