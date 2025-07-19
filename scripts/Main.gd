class_name Main
extends Node3D

# --- Properties ---
@onready var game_manager: GameManager = $GameManager as GameManager
@onready var animal_spawner: Node = $AnimalSpawner
@onready var environment_node: Node3D = $Environment
@onready var day_night_cycle: Node3D = $DayNightCycle
@onready var cloud_manager: Node3D = $CloudManager

# --- Engine Callbacks ---
func _ready() -> void:
	"""Initialize the main scene with chunk system."""
	print("Main: Initializing world with chunk-based system")
	
	# Ensure random number generator is properly seeded
	randomize()
	
	# Add to group for easy finding by other scripts
	add_to_group("main")
	
	# Initialize game manager with this as the world node
	if game_manager:
		print("Main: GameManager found, initializing world...")
		# Randomize seed on every generation
		var world_seed = randi()  # Generate random seed instead of using fixed constant
		print("Main: Using random world seed: ", world_seed)
		game_manager.initialize_world(self, world_seed)
		
		# Start immediate chunk loading and game setup
		print("Main: Starting immediate setup...")
		call_deferred("_quick_setup_and_start")
	else:
		print("Main: ERROR - GameManager not found!")
	
	# Add debug UI
	var debug_ui := ChunkDebugUI.new()
	debug_ui.name = "ChunkDebugUI"
	add_child(debug_ui)
	
	print("Main: Chunk system initialized")


func _quick_setup_and_start() -> void:
	"""Quick setup with minimal delay - chunks load as needed during gameplay."""
	print("Main: Quick setup starting...")
	
	# Give chunk system more time to initialize properly
	await get_tree().create_timer(0.5).timeout
	
	# Force load chunks around new spawn area (100, 0, 100) and wait for them
	if game_manager and game_manager.chunk_manager:
		var chunk_manager = game_manager.chunk_manager
		
		print("Main: Pre-loading chunks around spawn area (100, 0, 100)...")
		
		# Add a temporary player at new spawn location to trigger chunk loading
		var temp_player_id = 999999
		var temp_player_pos = Vector3(100, 50, 100)  # Changed from (0, 50, 0) to (100, 50, 100)
		if chunk_manager.player_tracker:
			# Use update_player_position to simulate a player at spawn to trigger chunk loading
			chunk_manager.player_tracker.update_player_position(temp_player_id, temp_player_pos)
		
		# Wait longer for chunks to actually generate
		await get_tree().create_timer(1.0).timeout
		print("Main: Chunks should be loaded around spawn area")
		
		# Clean up temporary player
		if chunk_manager.player_tracker:
			chunk_manager.player_tracker.remove_player(temp_player_id)
		
		print("Main: Initial chunks loaded around new spawn area")
	else:
		print("Main: WARNING - No chunk manager found for preloading!")
	
	# Position campfire on terrain with proper timing
	await _position_campfire_on_terrain()
	
	# Start the game
	game_manager.start_game()
	print("Main: Game started with quick setup")


func _position_campfire_on_terrain() -> void:
	"""Position the campfire on the terrain surface at world spawn location."""
	var campfire = environment_node.get_node_or_null("Campfire")
	if not campfire:
		print("Main: ERROR - Campfire not found in Environment!")
		return
	
	print("Main: Positioning campfire on terrain...")
	
	# Get the chunk manager to query terrain height
	var chunk_manager = game_manager.chunk_manager
	if not chunk_manager:
		print("Main: ERROR - ChunkManager not found!")
		return
	
	# Position campfire at new spawn location (100, 0, 100) instead of world center
	var campfire_world_pos = Vector3(100, 0, 100)
	
	# Wait a moment to ensure chunks are generated at this location
	await get_tree().create_timer(0.5).timeout
	
	var terrain_height = chunk_manager.get_height_at_position(campfire_world_pos)
	print("Main: Terrain height at (100,0,100): ", terrain_height)
	
	# Ensure terrain height is reasonable (not negative or extremely high)
	if terrain_height < 0 or terrain_height > 500:
		print("Main: WARNING - Suspicious terrain height (", terrain_height, "), using raycast fallback")
		# Try raycast as primary positioning method when terrain height seems wrong
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		if space_state:
			var from: Vector3 = Vector3(100, 1000, 100)  # Cast from very high above
			var to: Vector3 = Vector3(100, -100, 100)   # Cast down deep
			var query = PhysicsRayQueryParameters3D.create(from, to)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			var result = space_state.intersect_ray(query)
			
			if result:
				var ground_height = result.position.y
				print("Main: Raycast found ground at height: ", ground_height)
				campfire.global_position = Vector3(100, ground_height + 0.5, 100)  # Use 0.5 offset for safety
				print("Main: Campfire positioned via raycast at: ", campfire.global_position)
				return
			else:
				print("Main: Raycast found no ground! Using emergency fallback")
				# Emergency fallback: use a reasonable height
				campfire.global_position = Vector3(100, 50, 100)
				print("Main: Campfire positioned at emergency fallback: ", campfire.global_position)
				return
	
	# Terrain height seems reasonable, use it
	campfire.global_position = Vector3(100, terrain_height + 0.5, 100)  # Increased offset for visibility
	print("Main: Campfire positioned at: ", campfire.global_position, " (terrain height: ", terrain_height, ")") 
