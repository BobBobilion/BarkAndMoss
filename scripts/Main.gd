class_name Main
extends Node3D

# --- Properties ---
@onready var game_manager: GameManager = $GameManager
@onready var world_generator: WorldGenerator = $WorldGenerator
@onready var animal_spawner: Node = $AnimalSpawner
@onready var environment_node: Node3D = $Environment
@onready var day_night_cycle: Node3D = $DayNightCycle
@onready var cloud_manager: Node3D = $CloudManager

var is_chunk_system_enabled: bool = true  # Toggle between old and new system

# --- Engine Callbacks ---
func _ready() -> void:
	"""Initialize the main scene with chunk system."""
	print("Main: Initializing world...")
	
	if is_chunk_system_enabled:
		_setup_chunk_system()
	else:
		_setup_legacy_system()

# --- Private Methods ---
func _setup_chunk_system() -> void:
	"""Set up the new chunk-based infinite world system."""
	print("Main: Setting up chunk-based world system")
	
	# Disable the old world generator
	if world_generator:
		world_generator.visible = false
		world_generator.set_process(false)
		world_generator.set_physics_process(false)
	
	# Initialize game manager with this as the world node
	if game_manager:
		game_manager.initialize_world(self)
		
		# Start the game after a short delay to ensure everything is initialized
		await get_tree().create_timer(0.1).timeout
		game_manager.start_game()
	
	# The chunk system will handle terrain and object generation
	# as players move around
	
	# Add debug UI
	var debug_ui := ChunkDebugUI.new()
	debug_ui.name = "ChunkDebugUI"
	add_child(debug_ui)
	
	print("Main: Chunk system initialized")

func _setup_legacy_system() -> void:
	"""Set up the old finite world system (fallback)."""
	print("Main: Setting up legacy world system")
	
	# Use the existing WorldGenerator
	if world_generator:
		# Wait for terrain to be ready
		if not world_generator.terrain_generation_complete.is_connected(_on_legacy_terrain_ready):
			world_generator.terrain_generation_complete.connect(_on_legacy_terrain_ready)
		
		# Start generation
		world_generator.call_deferred("start_generation")

func _on_legacy_terrain_ready() -> void:
	"""Called when legacy terrain is ready."""
	print("Main: Legacy terrain ready")
	
	# In legacy mode, GameManager handles spawning when terrain is ready
	# (it has its own connection to terrain_generation_complete)

# --- Public Methods ---
func get_terrain_height_at_position(world_pos: Vector3) -> float:
	"""Get terrain height at a position, works with both systems."""
	if is_chunk_system_enabled and game_manager:
		var chunk_manager := game_manager.get_chunk_manager()
		if chunk_manager:
			return chunk_manager.get_height_at_position(world_pos)
	else:
		# Use legacy world generator
		if world_generator and world_generator.has_method("get_terrain_height_at_position"):
			return world_generator.get_terrain_height_at_position(world_pos)
	
	return 0.0 
