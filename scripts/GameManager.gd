# GameManager.gd
extends Node

# --- Constants ---
const PLAYER_SPAWN_OFFSET: float = 2.0
const SPAWN_HEIGHT_CLEARANCE: float = 5.0  # Height above terrain surface to spawn players

# --- Properties ---
var world_generator: WorldGenerator
var campfire: Node  # Will be cast to Campfire when accessed


func _ready() -> void:
	"""
	Called when the node is added to the scene.
	Sets up connections and waits for terrain to be ready before spawning players.
	"""
	# Display current world scaling information
	GameConstants.print_world_info()
	
	# Find the WorldGenerator in the scene
	world_generator = get_node("../WorldGenerator") as WorldGenerator
	
	# Find the Campfire in the scene
	campfire = get_node("../Environment/Campfire") as Node
	
	# Wait for terrain generation to complete before spawning players
	if world_generator:
		world_generator.terrain_generation_complete.connect(_on_terrain_ready)
	else:
		printerr("Could not find WorldGenerator! Players will spawn at default height.")
		_spawn_all_players()


func _on_terrain_ready() -> void:
	"""Called when the terrain generation is complete. Now we can safely spawn players."""
	print("GameManager: Terrain is ready, spawning players...")
	_spawn_all_players()


func _exit_tree() -> void:
	"""Clean up when GameManager is removed from scene (e.g., returning to menu)."""
	# Force cleanup of pause system when leaving game scene
	if PauseManager:
		PauseManager.force_cleanup()


func _spawn_all_players() -> void:
	"""
	Spawns all players that have connected and chosen a role.
	Only called after terrain is ready.
	"""
	print("GameManager: Starting player spawn process...")
	# When the main game scene loads, spawn all players.
	# The player data (including roles) is stored in our NetworkManager singleton.
	for id in NetworkManager.players:
		var player_data: Dictionary = NetworkManager.players[id]
		var player_scene: PackedScene = null
		
		if player_data.role == "human":
			player_scene = NetworkManager.human_scene
		elif player_data.role == "dog":
			player_scene = NetworkManager.dog_scene
		else:
			printerr("Player %d has no role!" % id)
			continue

		if player_scene:
			var player: Node = player_scene.instantiate()
			player.name = "Player_" + str(id)
			
			# This is the most important part: give control to the correct player.
			player.set_multiplayer_authority(id)
			
			add_child(player)
			
			# Calculate spawn position near the campfire
			var spawn_position: Vector3 = _get_safe_spawn_position(id)
			player.global_position = spawn_position
			print("GameManager: Spawned player %d (%s) at position %s" % [id, player_data.role, spawn_position])
	
	print("GameManager: All players spawned successfully!")


func _get_safe_spawn_position(player_id: int) -> Vector3:
	"""
	Calculates a safe spawn position for a player near the campfire.
	Uses the campfire's spawn position as the base and offsets for multiple players.
	"""
	var base_spawn_position: Vector3
	
	# Use campfire spawn position if available, otherwise use default
	if campfire and campfire.has_method("get_spawn_position"):
		base_spawn_position = campfire.get_spawn_position()
		print("GameManager: Using campfire spawn position: ", base_spawn_position)
	else:
		# Fallback to terrain-based spawning if campfire not available
		print("GameManager: Campfire not found, using terrain-based spawning")
		var spawn_x: float = player_id * PLAYER_SPAWN_OFFSET
		var spawn_z: float = 0.0
		
		# Get terrain height at spawn location
		var terrain_height: float = 0.0
		if world_generator and world_generator.has_method("get_terrain_height_at_position"):
			var check_position: Vector3 = Vector3(spawn_x, 0, spawn_z)
			terrain_height = world_generator.get_terrain_height_at_position(check_position)
		
		# Spawn with clearance above terrain
		var spawn_y: float = terrain_height + SPAWN_HEIGHT_CLEARANCE
		base_spawn_position = Vector3(spawn_x, spawn_y, spawn_z)
	
	# Offset players around the campfire to prevent overlap
	var angle: float = (player_id - 1) * PI * 0.5  # 90 degrees apart for up to 4 players
	var offset: Vector3 = Vector3(
		cos(angle) * PLAYER_SPAWN_OFFSET,
		0,
		sin(angle) * PLAYER_SPAWN_OFFSET
	)
	
	return base_spawn_position + offset

