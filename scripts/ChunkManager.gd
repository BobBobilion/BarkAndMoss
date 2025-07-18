class_name ChunkManager
extends Node

# --- Signals ---
signal chunk_loaded(chunk_pos: Vector2i)
signal chunk_unloaded(chunk_pos: Vector2i)
signal all_chunks_ready()

# --- Constants ---
# Loading distances (in chunks)
const LOAD_DISTANCE_HIGH: int = 3      # Full detail radius
const LOAD_DISTANCE_MEDIUM: int = 5    # Reduced detail radius
const LOAD_DISTANCE_LOW: int = 7       # Terrain only radius
const UNLOAD_DISTANCE: int = 9         # Beyond this, unload
const PREDICTIVE_LOAD_DISTANCE: int = 2  # Extra chunks in movement direction

# Performance settings
const MAX_CHUNKS_PER_FRAME: int = 2    # Max chunks to process per frame
const CHUNK_UPDATE_INTERVAL: float = 0.1  # How often to check chunk states

# --- Properties ---
var active_chunks: Dictionary = {}      # Vector2i -> Chunk
var chunk_generation_queue: Array[Vector2i] = []
var chunk_loading_queue: Array[Vector2i] = []
var chunk_unloading_queue: Array[Vector2i] = []

# Components (will be created as children)
var chunk_generator: ChunkGenerator = null
var chunk_loader: ChunkLoader = null
var player_tracker: PlayerTracker = null
var chunk_pool: ChunkPool = null

# Performance tracking
var chunks_generated_count: int = 0
var chunks_loaded_count: int = 0
var update_timer: float = 0.0

# Thread management
var generation_thread: Thread = null
var is_running: bool = true
var generation_mutex: Mutex = Mutex.new()
var generation_semaphore: Semaphore = Semaphore.new()

# World reference
var world_node: Node3D = null

# Chunk scene path
const CHUNK_SCENE_PATH: String = "res://scenes/Chunk.tscn"

# --- Engine Callbacks ---
func _ready() -> void:
	"""Initialize the chunk manager and its subsystems."""
	name = "ChunkManager"
	
	# Create subsystems
	_create_subsystems()
	
	# Start background thread for chunk generation
	generation_thread = Thread.new()
	generation_thread.start(_generation_thread_func)
	
	print("ChunkManager: Initialized with chunk distances - High:%d, Medium:%d, Low:%d, Unload:%d" % 
		[LOAD_DISTANCE_HIGH, LOAD_DISTANCE_MEDIUM, LOAD_DISTANCE_LOW, UNLOAD_DISTANCE])

func _exit_tree() -> void:
	"""Clean up threads and resources."""
	is_running = false
	generation_semaphore.post()  # Wake up thread to exit
	if generation_thread:
		generation_thread.wait_to_finish()

func _process(delta: float) -> void:
	"""Update chunk states and process queues."""
	update_timer += delta
	
	if update_timer >= CHUNK_UPDATE_INTERVAL:
		update_timer = 0.0
		_update_chunks()
		_process_loading_queue()
		_process_unloading_queue()

# --- Public Methods ---
func initialize_world(world: Node3D) -> void:
	"""Set the world node where chunks will be added."""
	world_node = world

func request_chunk(chunk_pos: Vector2i, priority: float = 0.0) -> void:
	"""Request a chunk to be loaded at the given position."""
	# Check if chunk already exists
	if active_chunks.has(chunk_pos):
		var chunk: Chunk = active_chunks[chunk_pos]
		chunk.add_reference()
		return
	
	# Check if chunk data is already cached
	if chunk_pool.has_chunk_data(chunk_pos):
		# Data is ready, add directly to loading queue
		generation_mutex.lock()
		if not chunk_pos in chunk_loading_queue:
			chunk_loading_queue.append(chunk_pos)
		generation_mutex.unlock()
		return
	
	# Add to generation queue if not already queued
	generation_mutex.lock()
	if not chunk_pos in chunk_generation_queue and not chunk_pos in chunk_loading_queue:
		chunk_generation_queue.append(chunk_pos)
		# Sort by priority (implement priority queue later)
		generation_semaphore.post()  # Wake up generation thread
	generation_mutex.unlock()

func release_chunk(chunk_pos: Vector2i) -> void:
	"""Release a reference to a chunk."""
	if active_chunks.has(chunk_pos):
		var chunk: Chunk = active_chunks[chunk_pos]
		chunk.remove_reference()
		
		# Add to unload queue if no references
		if chunk.should_unload() and not chunk_pos in chunk_unloading_queue:
			chunk_unloading_queue.append(chunk_pos)

func get_chunk_at_position(world_pos: Vector3) -> Chunk:
	"""Get the chunk containing the given world position."""
	var chunk_pos := world_to_chunk_position(world_pos)
	return active_chunks.get(chunk_pos)

func world_to_chunk_position(world_pos: Vector3) -> Vector2i:
	"""Convert world position to chunk coordinates."""
	return Vector2i(
		int(floor(world_pos.x / Chunk.CHUNK_SIZE.x)),
		int(floor(world_pos.z / Chunk.CHUNK_SIZE.y))
	)

func get_height_at_position(world_pos: Vector3) -> float:
	"""Get terrain height at any world position."""
	var chunk := get_chunk_at_position(world_pos)
	if chunk and chunk.current_state == Chunk.ChunkState.LOADED:
		return chunk.get_height_at_position(world_pos)
	
	# Fallback to procedural generation for unloaded chunks
	if chunk_generator:
		return chunk_generator.get_height_at_position(world_pos)
	
	return 0.0

func update_player_position(player_id: int, position: Vector3) -> void:
	"""Update a player's position for chunk loading."""
	if player_tracker:
		player_tracker.update_player_position(player_id, position)

func get_loaded_chunk_count() -> int:
	"""Get the number of currently loaded chunks."""
	return active_chunks.size()

func get_generation_queue_size() -> int:
	"""Get the number of chunks waiting to be generated."""
	generation_mutex.lock()
	var size := chunk_generation_queue.size()
	generation_mutex.unlock()
	return size

# --- Private Methods ---
func _create_subsystems() -> void:
	"""Create and initialize subsystem nodes."""
	# Create chunk generator
	chunk_generator = ChunkGenerator.new()
	chunk_generator.name = "ChunkGenerator"
	add_child(chunk_generator)
	
	# Create chunk loader
	chunk_loader = ChunkLoader.new()
	chunk_loader.name = "ChunkLoader"
	chunk_loader.chunk_manager = self
	add_child(chunk_loader)
	
	# Create player tracker
	player_tracker = PlayerTracker.new()
	player_tracker.name = "PlayerTracker"
	player_tracker.chunk_manager = self
	add_child(player_tracker)
	
	# Create chunk pool
	chunk_pool = ChunkPool.new()
	chunk_pool.name = "ChunkPool"
	add_child(chunk_pool)

func _update_chunks() -> void:
	"""Update chunk states based on player positions."""
	if not player_tracker:
		return
	
	var required_chunks := player_tracker.get_required_chunks()
	
	# Request new chunks
	for chunk_data in required_chunks:
		var chunk_pos: Vector2i = chunk_data["position"]
		var priority: float = chunk_data["priority"]
		var lod: Chunk.LODLevel = chunk_data["lod"]
		
		if active_chunks.has(chunk_pos):
			# Update LOD if needed
			var chunk: Chunk = active_chunks[chunk_pos]
			chunk.update_lod(lod)
		else:
			# Request new chunk
			request_chunk(chunk_pos, priority)
	
	# Check for chunks to unload
	for chunk_pos in active_chunks.keys():
		if not _is_chunk_required(chunk_pos, required_chunks):
			release_chunk(chunk_pos)

func _is_chunk_required(chunk_pos: Vector2i, required_chunks: Array) -> bool:
	"""Check if a chunk position is in the required chunks list."""
	for chunk_data in required_chunks:
		if chunk_data["position"] == chunk_pos:
			return true
	return false

func _generation_thread_func() -> void:
	"""Background thread function for chunk generation."""
	while is_running:
		generation_semaphore.wait()  # Wait for work
		
		if not is_running:
			break
		
		# Get next chunk to generate
		generation_mutex.lock()
		if chunk_generation_queue.size() > 0:
			var chunk_pos: Vector2i = chunk_generation_queue.pop_front()
			generation_mutex.unlock()
			
			# Generate chunk data
			var chunk_data := chunk_generator.generate_chunk(chunk_pos)
			
			# Add to loading queue (main thread will handle instantiation)
			generation_mutex.lock()
			chunk_loading_queue.append(chunk_pos)
			# Store generated data temporarily
			chunk_pool.store_chunk_data(chunk_pos, chunk_data)
			generation_mutex.unlock()
		else:
			generation_mutex.unlock()

func _process_loading_queue() -> void:
	"""Process chunks waiting to be loaded into the scene."""
	var chunks_processed: int = 0
	
	generation_mutex.lock()
	while chunk_loading_queue.size() > 0 and chunks_processed < MAX_CHUNKS_PER_FRAME:
		var chunk_pos: Vector2i = chunk_loading_queue.pop_front()
		generation_mutex.unlock()
		
		_load_chunk(chunk_pos)
		chunks_processed += 1
		
		generation_mutex.lock()
	generation_mutex.unlock()

func _load_chunk(chunk_pos: Vector2i) -> void:
	"""Load a chunk into the scene."""
	if active_chunks.has(chunk_pos):
		return  # Already loaded
	
	# Get chunk data from pool
	var chunk_data = chunk_pool.get_chunk_data(chunk_pos)
	if not chunk_data or chunk_data.is_empty():
		# Data not ready yet, put it back in the loading queue
		generation_mutex.lock()
		if not chunk_pos in chunk_loading_queue:
			chunk_loading_queue.push_back(chunk_pos)
		generation_mutex.unlock()
		return
	
	# Create chunk instance
	var chunk := Chunk.new()
	chunk.initialize(chunk_pos)
	
	# Set generated data
	chunk.set_terrain_data(chunk_data["terrain"])
	chunk.set_object_data(chunk_data["objects"])
	
	# Create visual elements
	chunk.create_terrain_mesh()
	chunk.create_terrain_collision()
	
	# Apply terrain material
	if chunk_loader:
		chunk_loader.apply_terrain_material(chunk)
	
	# Add to world
	if world_node:
		world_node.add_child(chunk)
	
	# Store in active chunks
	active_chunks[chunk_pos] = chunk
	chunk.current_state = Chunk.ChunkState.LOADED
	
	# Initial LOD based on nearest player
	var lod := _calculate_chunk_lod(chunk_pos)
	chunk.update_lod(lod)
	
	# Instantiate objects through ChunkLoader
	if chunk_loader:
		chunk_loader.instantiate_chunk_objects(chunk)
	
	chunks_loaded_count += 1
	chunk_loaded.emit(chunk_pos)

func _process_unloading_queue() -> void:
	"""Process chunks waiting to be unloaded."""
	var chunks_processed: int = 0
	
	while chunk_unloading_queue.size() > 0 and chunks_processed < MAX_CHUNKS_PER_FRAME:
		var chunk_pos: Vector2i = chunk_unloading_queue.pop_front()
		_unload_chunk(chunk_pos)
		chunks_processed += 1

func _unload_chunk(chunk_pos: Vector2i) -> void:
	"""Unload a chunk from the scene."""
	if not active_chunks.has(chunk_pos):
		return
	
	var chunk: Chunk = active_chunks[chunk_pos]
	
	# Only unload if truly not needed
	if not chunk.should_unload():
		return
	
	# Remove from scene
	chunk.queue_free()
	active_chunks.erase(chunk_pos)
	
	chunk_unloaded.emit(chunk_pos)

func _calculate_chunk_lod(chunk_pos: Vector2i) -> Chunk.LODLevel:
	"""Calculate appropriate LOD level for a chunk based on player distances."""
	if not player_tracker:
		return Chunk.LODLevel.LOW
	
	var min_distance := player_tracker.get_min_distance_to_chunk(chunk_pos)
	
	if min_distance <= LOAD_DISTANCE_HIGH:
		return Chunk.LODLevel.HIGH
	elif min_distance <= LOAD_DISTANCE_MEDIUM:
		return Chunk.LODLevel.MEDIUM
	elif min_distance <= LOAD_DISTANCE_LOW:
		return Chunk.LODLevel.LOW
	else:
		return Chunk.LODLevel.UNLOADED 
