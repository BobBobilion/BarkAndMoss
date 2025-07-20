class_name ChunkManager
extends Node

# --- Properties ---
var active_chunks: Dictionary = {} # { Vector2i: Chunk }
var world_node: Node3D
var chunk_generator: ChunkGenerator
var player_tracker: PlayerTracker

# Cached terrain material for all chunks
var cached_terrain_material: ShaderMaterial = null

# Preload textures at compile time for better reliability
const FOREST_ALBEDO_PATH = "res://assets/textures/grass terrain/textures/rocky_terrain_02_diff_4k.jpg"
const AUTUMN_ALBEDO_PATH = "res://assets/textures/leaves terrain/textures/leaves_forest_ground_diff_4k.jpg"  
const SNOW_ALBEDO_PATH = "res://assets/textures/snow terrain/Snow002_4K_Color.jpg"
const SNOW_NORMAL_PATH = "res://assets/textures/snow terrain/Snow002_4K_NormalGL.jpg"
const SNOW_ROUGHNESS_PATH = "res://assets/textures/snow terrain/Snow002_4K_Roughness.jpg"
const MOUNTAIN_ALBEDO_PATH = "res://assets/textures/rock terrain/textures/rocks_ground_05_diff_4k.jpg"
const MOUNTAIN_ROUGHNESS_PATH = "res://assets/textures/rock terrain/textures/rocks_ground_05_rough_4k.jpg"

var generation_threads: Array[Thread] = []
var chunks_to_generate: Array[Vector2i] = []
var generated_chunk_data: Dictionary = {}

var _mutex := Mutex.new()
var _semaphore := Semaphore.new()
var _is_running := true

# --- Engine Callbacks ---
func _ready() -> void:
	name = "ChunkManager"
	_setup_subsystems()
	_start_generation_threads()

func _exit_tree() -> void:
	# Signal all threads to stop
	_is_running = false
	
	# Wake up all threads by posting the semaphore once for each thread
	# This ensures every thread can exit their wait loop
	for i in range(generation_threads.size()):
		_semaphore.post()
	
	# Now safely wait for all threads to finish
	for thread in generation_threads:
		thread.wait_to_finish()

func _process(_delta: float) -> void:
	# Skip processing if shutting down
	if not _is_running:
		return
	_process_generated_data()

# --- Public Methods ---
func initialize(world: Node3D, seed: int) -> void:
	world_node = world
	print("ChunkManager: Initializing with world seed: ", seed)
	chunk_generator.initialize(seed)

func get_height_at_position(world_pos: Vector3) -> float:
	"""Get terrain height at a position using the chunk generator."""
	if chunk_generator:
		return chunk_generator.biome_manager.get_terrain_height_at_position(world_pos)
	return 0.0

func get_terrain_material() -> ShaderMaterial:
	"""Get the cached terrain material for chunks, creating it if needed."""
	if not cached_terrain_material:
		_create_terrain_material()
	return cached_terrain_material


func cleanup() -> void:
	"""Clean up the chunk manager when returning to main menu."""
	
	# Stop all processing
	_is_running = false
	
	# Wake up all threads so they can exit
	for i in range(generation_threads.size()):
		_semaphore.post()
	
	# Clear all chunk tracking
	_mutex.lock()
	chunks_to_generate.clear()
	generated_chunk_data.clear()
	_mutex.unlock()
	
	# Remove all active chunks
	for chunk_pos in active_chunks.keys():
		var chunk = active_chunks[chunk_pos]
		if is_instance_valid(chunk):
			chunk.queue_free()
	active_chunks.clear()
	
	# Clear player tracking if player_tracker exists
	if player_tracker:
		player_tracker.clear_all_players()

# --- Private Methods ---
func _setup_subsystems() -> void:
	chunk_generator = ChunkGenerator.new()
	add_child(chunk_generator)
	
	# PlayerTracker is an autoload singleton, reference it directly
	player_tracker = PlayerTracker
	player_tracker.required_chunks_changed.connect(_on_required_chunks_changed)

func _start_generation_threads() -> void:
	var thread_count = OS.get_processor_count() - 1
	for i in range(thread_count):
		var thread := Thread.new()
		thread.start(_generation_thread_loop)
		generation_threads.append(thread)

func _generation_thread_loop() -> void:
	while _is_running:
		_semaphore.wait()
		if not _is_running:
			return
			
		_mutex.lock()
		if chunks_to_generate.is_empty():
			_mutex.unlock()
			continue
		var chunk_pos = chunks_to_generate.pop_front()
		_mutex.unlock()
		
		var data = chunk_generator.generate_chunk_data(chunk_pos)
		
		_mutex.lock()
		generated_chunk_data[chunk_pos] = data
		_mutex.unlock()

func _process_generated_data() -> void:
	_mutex.lock()
	if generated_chunk_data.is_empty():
		_mutex.unlock()
		return
	var data_copy = generated_chunk_data.duplicate()
	generated_chunk_data.clear()
	_mutex.unlock()
	
	for chunk_pos in data_copy:
		if active_chunks.has(chunk_pos):
			var chunk = active_chunks[chunk_pos]
		
			chunk.load_data(data_copy[chunk_pos])
		else:
			pass

func _on_required_chunks_changed(required_chunks: Dictionary) -> void:
	# Skip processing if chunk manager is being cleaned up
	if not _is_running:
		return
	
	# Unload old chunks
	for chunk_pos in active_chunks:
		if not required_chunks.has(chunk_pos):
			var chunk = active_chunks[chunk_pos]
			if is_instance_valid(chunk) and not chunk.is_queued_for_deletion():
				chunk.unload()
			active_chunks.erase(chunk_pos)
			
	# Load new chunks and update LOD
	for chunk_pos in required_chunks:
		if active_chunks.has(chunk_pos):
			var chunk = active_chunks[chunk_pos]
			# Check if chunk is still valid before calling methods on it
			if is_instance_valid(chunk) and not chunk.is_queued_for_deletion():
				chunk.set_lod(required_chunks[chunk_pos])
			else:
				# Chunk was freed, remove from tracking
				active_chunks.erase(chunk_pos)
		else:
			# Ensure material is created before adding chunks
			if not cached_terrain_material:
				_create_terrain_material()
			
			var new_chunk := Chunk.new()
			new_chunk.initialize(chunk_pos)
			# Pass the terrain material directly to the chunk
			new_chunk.set("_terrain_material", cached_terrain_material)
			active_chunks[chunk_pos] = new_chunk
			world_node.add_child(new_chunk)
			
			_mutex.lock()
			chunks_to_generate.push_back(chunk_pos)
			_mutex.unlock()
			_semaphore.post()

func _create_terrain_material() -> void:
	"""Create the terrain blend material using the same logic as WorldGenerator."""
	if not chunk_generator or not chunk_generator.biome_manager:
		return
	
	# First, let's create a simple colored material for testing
	var use_simple_material = false  # Changed back to false to use textures
	
	if use_simple_material:
		_create_simple_biome_material()
		return
	
	# Create a shader material using our custom terrain blending shader
	cached_terrain_material = ShaderMaterial.new()
	var terrain_shader: Shader = load("res://shaders/terrain_blend.gdshader")
	
	if not terrain_shader:
		push_error("ChunkManager: Failed to load terrain blend shader! Using simple material instead.")
		_create_simple_biome_material()
		return
	
	cached_terrain_material.shader = terrain_shader
	
	# Create default textures for fallback
	var default_albedo: ImageTexture = _create_default_texture(Color(0.5, 0.5, 0.5))
	var default_normal: ImageTexture = _create_default_normal_texture()
	var default_roughness: ImageTexture = _create_default_texture(Color(0.5, 0.5, 0.5))
	
	# Create test textures with distinct colors
	var test_forest: ImageTexture = _create_solid_color_texture(Color(0.2, 0.8, 0.2))  # Green
	var test_autumn: ImageTexture = _create_solid_color_texture(Color(0.8, 0.4, 0.1))  # Orange
	var test_snow: ImageTexture = _create_solid_color_texture(Color(0.9, 0.9, 0.95))  # White
	var test_mountain: ImageTexture = _create_solid_color_texture(Color(0.5, 0.45, 0.4)) # Grey
	
	# Load and assign textures for each biome - SAME PATHS AS WORLDGENERATOR
	# Forest biome textures (grass terrain)
	var forest_albedo: Texture2D = ResourceLoader.load(FOREST_ALBEDO_PATH, "Texture2D")
	if not forest_albedo:
		forest_albedo = default_albedo
	else:
		var image = forest_albedo.get_image()
		if image:
			pass
		else:
			pass
	
	# Autumn biome textures (leaves terrain)
	var autumn_albedo: Texture2D = ResourceLoader.load(AUTUMN_ALBEDO_PATH, "Texture2D")
	if not autumn_albedo:
		autumn_albedo = default_albedo
	else:
		var image = autumn_albedo.get_image()
		if image:
			pass
		else:
			pass
	
	# Snow biome textures
	var snow_albedo: Texture2D = ResourceLoader.load(SNOW_ALBEDO_PATH, "Texture2D")
	var snow_normal: Texture2D = ResourceLoader.load(SNOW_NORMAL_PATH, "Texture2D")
	var snow_roughness: Texture2D = ResourceLoader.load(SNOW_ROUGHNESS_PATH, "Texture2D")
	
	if not snow_albedo:
		snow_albedo = default_albedo
	else:
		pass
	
	if not snow_normal:
		snow_normal = default_normal
	else:
		pass
	
	if not snow_roughness:
		snow_roughness = default_roughness
	else:
		pass
	
	# Mountain biome textures (rock terrain)
	var mountain_albedo: Texture2D = ResourceLoader.load(MOUNTAIN_ALBEDO_PATH, "Texture2D")
	var mountain_roughness: Texture2D = ResourceLoader.load(MOUNTAIN_ROUGHNESS_PATH, "Texture2D")
	
	if not mountain_albedo:
		mountain_albedo = default_albedo
	else:
		pass
		
	if not mountain_roughness:
		mountain_roughness = default_roughness
	else:
		pass
	
	# Set shader parameters
	cached_terrain_material.set_shader_parameter("forest_albedo", forest_albedo)
	cached_terrain_material.set_shader_parameter("forest_normal", default_normal)
	cached_terrain_material.set_shader_parameter("forest_roughness", default_roughness)
	
	cached_terrain_material.set_shader_parameter("autumn_albedo", autumn_albedo)
	cached_terrain_material.set_shader_parameter("autumn_normal", default_normal)
	cached_terrain_material.set_shader_parameter("autumn_roughness", default_roughness)
	
	cached_terrain_material.set_shader_parameter("snow_albedo", snow_albedo)
	cached_terrain_material.set_shader_parameter("snow_normal", snow_normal)
	cached_terrain_material.set_shader_parameter("snow_roughness", snow_roughness)
	
	cached_terrain_material.set_shader_parameter("mountain_albedo", mountain_albedo)
	cached_terrain_material.set_shader_parameter("mountain_normal", default_normal)
	cached_terrain_material.set_shader_parameter("mountain_roughness", mountain_roughness)
	
	# TEMPORARY: Override with test textures to verify shader works
	var use_test_textures = false  # Changed to false to use real textures
	if use_test_textures:
		cached_terrain_material.set_shader_parameter("forest_albedo", test_forest)
		cached_terrain_material.set_shader_parameter("autumn_albedo", test_autumn)
		cached_terrain_material.set_shader_parameter("snow_albedo", test_snow)
		cached_terrain_material.set_shader_parameter("mountain_albedo", test_mountain)
	
	# Set other shader parameters
	cached_terrain_material.set_shader_parameter("texture_scale", 15.0)  # Tripled from 5.0 for even more detailed textures
	cached_terrain_material.set_shader_parameter("autumn_texture_scale", 15.0)  # Tripled from 5.0
	cached_terrain_material.set_shader_parameter("blend_sharpness", 2.0)
	cached_terrain_material.set_shader_parameter("roughness_multiplier", 1.0)
	cached_terrain_material.set_shader_parameter("normal_strength", 0.5)
	
	# Enable debug mode to test texture loading
	cached_terrain_material.set_shader_parameter("debug_mode", 0.0)  # Changed to 0.0 to see blending
	
	# Debug: Verify shader parameters were set
	# Debug: Verify shader parameters were set
	# Debug: Verify shader parameters were set
	# Debug: Verify shader parameters were set
	# Debug: Verify shader parameters were set

func _create_simple_biome_material() -> void:
	"""Create a simple colored material that shows biomes using vertex colors."""
	
	# Create a simple shader that uses vertex colors
	var shader_code = """
shader_type spatial;

void vertex() {
	// Pass vertex color to fragment shader
	COLOR = COLOR;
}

void fragment() {
	// Decode biome weights from vertex color
	vec4 biome_weights = COLOR;
	
	// Define biome colors
	vec3 forest_color = vec3(0.2, 0.6, 0.1);   // Green
	vec3 autumn_color = vec3(0.8, 0.4, 0.1);   // Orange
	vec3 snow_color = vec3(0.9, 0.9, 0.95);    // White
	vec3 mountain_color = vec3(0.5, 0.45, 0.4); // Grey-brown
	
	// Blend colors based on weights
	vec3 final_color = forest_color * biome_weights.r +
					   autumn_color * biome_weights.g +
					   snow_color * biome_weights.b +
					   mountain_color * biome_weights.a;
	
	// Apply some basic shading
	ALBEDO = final_color;
	ROUGHNESS = 0.8;
	METALLIC = 0.0;
}
"""
	
	var shader = Shader.new()
	shader.code = shader_code
	
	cached_terrain_material = ShaderMaterial.new()
	cached_terrain_material.shader = shader
	

func _create_default_texture(color: Color) -> ImageTexture:
	"""Create a simple default texture with the given color."""
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGB8)
	
	# Create a checkerboard pattern for debugging
	for y in range(64):
		for x in range(64):
			var checker_color: Color
			if (x / 8 + y / 8) % 2 == 0:
				checker_color = color
			else:
				checker_color = color.darkened(0.3)
			image.set_pixel(x, y, checker_color)
	
	return ImageTexture.create_from_image(image)

func _create_default_normal_texture() -> ImageTexture:
	"""Create a default normal map texture (neutral normal pointing up)."""
	var image: Image = Image.create(4, 4, false, Image.FORMAT_RGB8)
	image.fill(Color(0.5, 0.5, 1.0))  # Neutral normal map color
	return ImageTexture.create_from_image(image)

func _create_solid_color_texture(color: Color) -> ImageTexture:
	"""Create a solid color texture for testing."""
	var image: Image = Image.create(256, 256, false, Image.FORMAT_RGB8)
	image.fill(color)
	return ImageTexture.create_from_image(image) 
