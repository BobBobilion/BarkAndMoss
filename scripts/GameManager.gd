class_name GameManager
extends Node

# --- Imports ---
const BiomeManagerClass = preload("res://scripts/BiomeManager.gd")

# --- Signals ---
signal player_spawned(player: Node3D)
signal game_started()
signal game_ended()

# --- Constants ---
const PLAYER_SCENE_PATH: String = "res://scenes/Player.tscn"
const DOG_SCENE_PATH: String = "res://scenes/Dog.tscn"
const SPAWN_HEIGHT_OFFSET: float = 10.0  # Increased from 5.0 to prevent falling through terrain

# --- Properties ---
var players: Dictionary = {}  # peer_id -> player_node
var is_server: bool = false
var world_node: Node3D = null
var chunk_manager: ChunkManager = null  # Changed from world_generator

# Game state
var is_game_started: bool = false

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
func initialize_world(world: Node3D, seed: int) -> void:
	"""Set the world node reference and initialize chunk manager."""
	world_node = world
	if chunk_manager:
		chunk_manager.initialize(world, seed)
		
	# Debug: Test texture loading on startup
	_debug_texture_loading()
	
	# Debug chunk system after a delay
	await get_tree().create_timer(2.0).timeout
	_debug_chunk_system()

func start_game() -> void:
	"""Start the game and spawn initial players."""
	# Remove server check - allow single player mode
	print("GameManager: Starting game (multiplayer: %s)" % multiplayer.has_multiplayer_peer())
		
	is_game_started = true
	game_started.emit()
	spawn_initial_players()
	print("GameManager: Game started!")

func spawn_initial_players() -> void:
	"""Spawn players based on their selected character types."""
	print("GameManager: spawn_initial_players called (is_server: %s)" % multiplayer.is_server())
	
	# Always spawn the local player
	var local_id: int = multiplayer.get_unique_id()
	print("GameManager: Local player ID: %d" % local_id)
	_spawn_player(local_id)
	
	# If we're the server and have connected players, spawn them too
	if multiplayer.is_server():
		for peer_id in multiplayer.get_peers():
			print("GameManager: Spawning connected player: %d" % peer_id)
			_spawn_player(peer_id)

	print("GameManager: Initial players spawned.")

func get_spawn_position() -> Vector3:
	"""Get a safe spawn position near the campfire."""
	# Try to find the campfire first
	var campfire = _find_campfire()
	if campfire:
		# Use campfire's built-in spawn position method
		var spawn_pos = campfire.get_spawn_position()
		print("GameManager: Using campfire spawn position: ", spawn_pos)
		return spawn_pos
	
	print("GameManager: Campfire not found, using fallback spawn calculation")
	
	# Fallback: spawn at new world spawn location (100, 0, 100) on terrain surface
	var base_position = Vector3(100, 0, 100)  # Changed from (0, 0, 0) to (100, 0, 100)
	if chunk_manager:
		var terrain_height = chunk_manager.get_height_at_position(base_position)
		print("GameManager: Terrain height at spawn location: ", terrain_height)
		
		# Validate terrain height before using it
		if terrain_height < 0 or terrain_height > 500:
			print("GameManager: WARNING - Suspicious terrain height (", terrain_height, "), using raycast")
			
			# Try raycast to find ground
			var space_state: PhysicsDirectSpaceState3D = world_node.get_world_3d().direct_space_state
			if space_state:
				var from: Vector3 = Vector3(100, 1000, 100)  # Cast from very high
				var to: Vector3 = Vector3(100, -100, 100)    # Cast down deep
				var query = PhysicsRayQueryParameters3D.create(from, to)
				query.collide_with_areas = false
				query.collide_with_bodies = true
				var result = space_state.intersect_ray(query)
				
				if result:
					var ground_height = result.position.y
					print("GameManager: Raycast found ground at: ", ground_height)
					base_position.y = ground_height + SPAWN_HEIGHT_OFFSET
					print("GameManager: Using raycast spawn position: ", base_position)
					return base_position
				else:
					print("GameManager: Raycast found no ground! Using emergency position")
					base_position = Vector3(100, 100, 100)  # High emergency position
					print("GameManager: Using emergency spawn position: ", base_position)
					return base_position
		else:
			# Terrain height seems reasonable
			base_position.y = terrain_height + SPAWN_HEIGHT_OFFSET
			print("GameManager: Using terrain-based spawn position: ", base_position, " (terrain: ", terrain_height, ")")
			return base_position
	else:
		# Last resort: just use a high position at the new spawn coordinates
		base_position = Vector3(100, 100, 100)  # Increased from 50 to 100 for safety
		print("GameManager: Using emergency fallback spawn position (no chunk manager): ", base_position)
	
	return base_position


func _find_campfire() -> Node:
	"""Find the campfire in the world."""
	# Look for campfire in the campfire group
	var campfires = get_tree().get_nodes_in_group("campfire")
	if not campfires.is_empty():
		return campfires[0]
	
	# Fallback: search in Environment node
	if world_node:
		var environment = world_node.get_node_or_null("Environment")
		if environment:
			var campfire = environment.get_node_or_null("Campfire")
			if campfire:
				return campfire
	
	print("GameManager: WARNING - Campfire not found!")
	return null

func respawn_player(peer_id: int) -> void:
	"""Respawn a player at a new position."""
	if not multiplayer.is_server():
		return
		
	if players.has(peer_id):
		var player = players[peer_id]
		var spawn_pos := get_spawn_position()
		player.position = spawn_pos
		player.visible = true # Make sure respawned player is visible
		
		# Reset player state
		if player.has_method("reset_health"):
			player.reset_health()

# --- Private Methods ---
func _create_chunk_manager() -> void:
	"""Create and configure the chunk manager."""
	chunk_manager = ChunkManager.new()
	chunk_manager.name = "ChunkManager"
	add_child(chunk_manager)
	print("GameManager: ChunkManager created and added")

func _spawn_player(peer_id: int) -> void:
	"""Spawn a player for the given peer ID."""
	if players.has(peer_id):
		print("GameManager: Player %d already spawned" % peer_id)
		return
	
	# Get character type from NetworkManager (default to human if not selected)
	var character_type: String = "human"  # Default fallback
	if NetworkManager.players.has(peer_id):
		var player_data = NetworkManager.players[peer_id]
		if player_data.has("role") and player_data.role != "unassigned":
			character_type = player_data.role
	
	print("GameManager: Spawning character type '%s' for peer %d" % [character_type, peer_id])
	
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
	
	# Set spawn position with character-specific adjustments
	var base_spawn_pos = get_spawn_position() + Vector3(0, 5, 0)
	
	# Adjust spawn height for different character types due to different collision shapes
	if character_type == "dog":
		# Dog has lower collision box (0.29 units above origin) vs human (1.2+ units above origin)
		# Add extra height to compensate for dog's lower collision shape
		base_spawn_pos.y += 1.0  # Additional offset for dog to account for collision shape difference
		print("GameManager: Adjusted dog spawn position by +1.0 for collision shape difference")
	
	player.position = base_spawn_pos
	
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
	
	print("GameManager: Successfully spawned %s (%s) for peer %d at %v" % [character_type, player_scene_path, peer_id, player.position])

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
		if chunk_manager and chunk_manager.player_tracker:
			chunk_manager.player_tracker.remove_player(id)

# --- Public Methods for Chunk System ---
func get_chunk_manager() -> ChunkManager:
	"""Get the chunk manager instance."""
	return chunk_manager

func get_biome_manager() -> BiomeManagerClass:
	"""Get the biome manager instance from the chunk generator."""
	if chunk_manager and chunk_manager.chunk_generator:
		return chunk_manager.chunk_generator.biome_manager
	return null

func update_player_chunk_position(player: Node3D) -> void:
	"""Update player position in chunk system."""
	if not chunk_manager or not is_instance_valid(player):
		return
	
	# Get player ID - use instance ID in single player mode
	var peer_id: int
	if multiplayer.has_multiplayer_peer():
		peer_id = player.get_multiplayer_authority()
	else:
		# Single player mode - use instance ID
		peer_id = player.get_instance_id()
	
	# Update position in chunk manager
	chunk_manager.player_tracker.update_player_position(peer_id, player.global_position)

func _debug_chunk_system() -> void:
	"""Debug the chunk system to see what's happening."""
	print("=== CHUNK SYSTEM DEBUG ===")
	
	if chunk_manager:
		print("✅ ChunkManager exists")
		print("  Active chunks: ", chunk_manager.active_chunks.size())
		print("  Has terrain material: ", chunk_manager.cached_terrain_material != null)
		
		if chunk_manager.chunk_generator:
			print("✅ ChunkGenerator exists")
			if chunk_manager.chunk_generator.biome_manager:
				print("✅ BiomeManager exists")
				# Test biome at origin
				var test_pos = Vector3.ZERO
				var biome = chunk_manager.chunk_generator.biome_manager.get_biome_at_position(test_pos)
				print("  Biome at origin: ", biome)
				var height = chunk_manager.chunk_generator.biome_manager.get_terrain_height_at_position(test_pos)
				print("  Height at origin: ", height)
			else:
				print("❌ BiomeManager missing")
		else:
			print("❌ ChunkGenerator missing")
			
		# Check for any visible chunks
		for chunk_pos in chunk_manager.active_chunks:
			var chunk = chunk_manager.active_chunks[chunk_pos]
			print("  Chunk at ", chunk_pos, ": state=", chunk.current_state, " has_mesh=", chunk.terrain_mesh_instance != null)
			if chunk.terrain_mesh_instance:
				print("    Material: ", chunk.terrain_mesh_instance.material_override)
	else:
		print("❌ ChunkManager is null")
	
	print("=== END CHUNK DEBUG ===")

func _debug_texture_loading() -> void:
	"""Debug function to test if all expected textures can be loaded."""
	print("=== TEXTURE LOADING DEBUG ===")
	
	var texture_paths: Array[String] = [
		"res://assets/textures/grass terrain/textures/rocky_terrain_02_diff_4k.jpg",
		"res://assets/textures/leaves terrain/textures/leaves_forest_ground_diff_4k.jpg", 
		"res://assets/textures/snow terrain/Snow002_4K_Color.jpg",
		"res://assets/textures/snow terrain/Snow002_4K_NormalGL.jpg",
		"res://assets/textures/snow terrain/Snow002_4K_Roughness.jpg",
		"res://assets/textures/rock terrain/textures/rocks_ground_05_diff_4k.jpg",
		"res://assets/textures/rock terrain/textures/rocks_ground_05_rough_4k.jpg"
	]
	
	for path in texture_paths:
		if ResourceLoader.exists(path):
			var texture = load(path) as Texture2D
			if texture:
				print("✅ Successfully loaded: ", path)
			else:
				print("❌ Failed to load texture from: ", path)
		else:
			print("🚫 File does not exist: ", path)
	
	# Test shader loading
	var shader_path = "res://shaders/terrain_blend.gdshader"
	if ResourceLoader.exists(shader_path):
		var shader = load(shader_path) as Shader
		if shader:
			print("✅ Successfully loaded terrain blend shader")
		else:
			print("❌ Failed to load terrain blend shader")
	else:
		print("🚫 Terrain blend shader file does not exist")
	
	print("=== END TEXTURE DEBUG ===")


# --- Cleanup Methods ---

func cleanup_game_state() -> void:
	"""Clean up all game state when returning to main menu."""
	print("GameManager: Cleaning up game state...")
	
	# Remove all player instances from the scene
	for peer_id in players.keys():
		var player = players[peer_id]
		if is_instance_valid(player):
			print("GameManager: Removing player %d (%s)" % [peer_id, player.name])
			player.queue_free()
	
	# Clear the players dictionary
	players.clear()
	
	# Clean up campfire and its related UI
	_cleanup_campfire()
	
	# Clean up world objects (trees, rocks, grass)
	_cleanup_world_objects()
	
	# Clean up animal corpses
	_cleanup_corpses()
	
	# Clean up animals
	_cleanup_animals()
	
	# Clean up animal spawner
	_cleanup_animal_spawner()
	
	# Clean up chunk manager first (this will clean up chunks properly)
	if chunk_manager:
		if chunk_manager.has_method("cleanup"):
			chunk_manager.cleanup()
		chunk_manager.queue_free()
		chunk_manager = null
	
	# Clean up any remaining chunks as fallback
	_cleanup_chunks()
	
	# Reset game state
	is_game_started = false
	
	print("GameManager: Game state cleaned up")


func _cleanup_campfire() -> void:
	"""Clean up campfire and its related UI instances."""
	print("GameManager: Cleaning up campfire...")
	
	# Find and clean up any campfire instances
	var all_campfires = get_tree().get_nodes_in_group("campfire")
	for campfire in all_campfires:
		if is_instance_valid(campfire):
			print("GameManager: Removing campfire: ", campfire.name)
			# Close any open campfire menus first
			if campfire.has_method("close_menu"):
				campfire.close_menu()
			campfire.queue_free()
	
	# Also look for campfires in the Environment node as fallback
	if world_node:
		var environment = world_node.get_node_or_null("Environment")
		if environment:
			var campfire = environment.get_node_or_null("Campfire")
			if campfire and is_instance_valid(campfire):
				print("GameManager: Removing Environment campfire")
				# Close any open campfire menus first
				if campfire.has_method("close_menu"):
					campfire.close_menu()
				campfire.queue_free()
	
	# Clean up any campfire menu instances that might be floating around
	var campfire_menus = get_tree().get_nodes_in_group("campfire_menu")
	for menu in campfire_menus:
		if is_instance_valid(menu):
			print("GameManager: Removing campfire menu: ", menu.name)
			menu.queue_free()
	
	print("GameManager: Campfire cleanup complete")


func _cleanup_world_objects() -> void:
	"""Clean up all world objects (trees, rocks, grass) from the scene."""
	print("GameManager: Cleaning up world objects...")
	
	# Find WorldGenerator and clean up all its children (trees, rocks, grass)
	var world_generators = get_tree().get_nodes_in_group("world_generator")
	for world_gen in world_generators:
		if is_instance_valid(world_gen):
			print("GameManager: Removing %d children from WorldGenerator" % world_gen.get_child_count())
			# Remove all children (terrain, trees, rocks, grass)
			for child in world_gen.get_children():
				if is_instance_valid(child):
					child.queue_free()
	
	# Clean up any standalone tree/rock nodes that might exist
	var all_trees = get_tree().get_nodes_in_group("trees")
	for tree in all_trees:
		if is_instance_valid(tree):
			tree.queue_free()
	
	var all_rocks = get_tree().get_nodes_in_group("rocks")
	for rock in all_rocks:
		if is_instance_valid(rock):
			rock.queue_free()
	
	print("GameManager: World objects cleanup complete")


func _cleanup_corpses() -> void:
	"""Clean up all animal corpses from the scene."""
	print("GameManager: Cleaning up corpses...")
	
	var all_corpses = get_tree().get_nodes_in_group("corpses")
	for corpse in all_corpses:
		if is_instance_valid(corpse):
			corpse.queue_free()
	
	print("GameManager: Removed %d corpses" % all_corpses.size())


func _cleanup_animals() -> void:
	"""Clean up all animals from the scene."""
	print("GameManager: Cleaning up animals...")
	
	var all_animals = get_tree().get_nodes_in_group("animals")
	for animal in all_animals:
		if is_instance_valid(animal):
			animal.queue_free()
	
	print("GameManager: Removed %d animals" % all_animals.size())


func _cleanup_animal_spawner() -> void:
	"""Clean up the animal spawner and its tracking."""
	print("GameManager: Cleaning up animal spawner...")
	
	# Find the animal spawner and clear its tracking
	var animal_spawners = get_tree().get_nodes_in_group("animal_spawner")
	for spawner in animal_spawners:
		if is_instance_valid(spawner):
			# Clear its animal tracking if it has cleanup methods
			if spawner.has_method("clear_all_tracking"):
				spawner.clear_all_tracking()
			elif spawner.has_method("_cleanup_invalid_animals"):
				spawner._cleanup_invalid_animals()
	
	print("GameManager: Animal spawner cleanup complete")


func _cleanup_chunks() -> void:
	"""Clean up all chunk instances from the scene."""
	print("GameManager: Cleaning up chunks...")
	
	# Find and remove all chunk nodes
	var all_chunks = get_tree().get_nodes_in_group("chunks")
	for chunk in all_chunks:
		if is_instance_valid(chunk):
			chunk.queue_free()
	
	# Also clean up any nodes with "Chunk" in their name as fallback
	var main_scene = get_tree().current_scene
	if main_scene:
		var children_to_remove = []
		_find_chunk_nodes_recursive(main_scene, children_to_remove)
		for chunk_node in children_to_remove:
			if is_instance_valid(chunk_node):
				chunk_node.queue_free()
	
	print("GameManager: Removed %d chunks" % all_chunks.size())


func _find_chunk_nodes_recursive(node: Node, chunk_list: Array) -> void:
	"""Recursively find nodes that might be chunks."""
	if node.name.contains("Chunk") or node.name.contains("chunk"):
		chunk_list.append(node)
	
	for child in node.get_children():
		_find_chunk_nodes_recursive(child, chunk_list)
