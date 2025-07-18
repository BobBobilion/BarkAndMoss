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
	
	# Add to group for easy finding by other scripts
	add_to_group("main")
	
	# Initialize game manager with this as the world node
	if game_manager:
		print("Main: GameManager found, initializing world...")
		var world_seed = GameConstants.WORLD.get("SEED", 12345)
		game_manager.initialize_world(self, world_seed)
		
		# Start the game after a short delay to ensure everything is initialized
		await get_tree().create_timer(0.1).timeout
		print("Main: Starting game...")
		game_manager.start_game()
	else:
		print("Main: ERROR - GameManager not found!")
	
	# The chunk system will handle terrain and object generation
	# as players move around
	
	# Add debug UI
	var debug_ui := ChunkDebugUI.new()
	debug_ui.name = "ChunkDebugUI"
	add_child(debug_ui)
	
	print("Main: Chunk system initialized")
	
	# Debug: Check children after setup
	await get_tree().create_timer(1.0).timeout
	print("Main: Children after setup:")
	for child in get_children():
		print("  - ", child.name, " (", child.get_class(), ")")
		if child.name == "GameManager":
			var gm = child as GameManager
			if gm.chunk_manager:
				print("    Has ChunkManager: ", gm.chunk_manager.name)
				print("    Active chunks: ", gm.chunk_manager.active_chunks.size())
			else:
				print("    ChunkManager is null!")
				
	# Check for actual terrain meshes after delay
	await get_tree().create_timer(3.0).timeout
	print("Main: Checking for terrain meshes...")
	var mesh_count = 0
	for child in get_children():
		if child.has_method("get_class") and child.get_class() == "MeshInstance3D":
			mesh_count += 1
			print("  Found mesh: ", child.name)
	print("Main: Total MeshInstance3D nodes: ", mesh_count)

# --- Public Methods ---
func get_terrain_height_at_position(world_pos: Vector3) -> float:
	"""Get terrain height at a position using the chunk system."""
	if game_manager:
		var chunk_manager := game_manager.get_chunk_manager()
		if chunk_manager:
			return chunk_manager.get_height_at_position(world_pos)
	
	return 0.0

func _input(event: InputEvent) -> void:
	"""Handle debug input for testing."""
	# Debug input handling removed - was causing conflicts with pause menu
	pass

# Debug spawn function removed - was causing unintended character spawning 
