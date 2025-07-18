class_name ChunkGenerator
extends Node

# --- Imports ---
const BiomeManagerClass = preload("res://scripts/BiomeManager.gd")
const ChunkClass = preload("res://scripts/Chunk.gd")

# --- Constants ---
# World generation seed
@export var world_seed: int = 12345

# Object density per chunk (adjusted for chunk size)
const TREES_PER_CHUNK: int = 15      # Average trees per chunk
const ROCKS_PER_CHUNK: int = 10      # Average rocks per chunk
const GRASS_PER_CHUNK: int = 50      # Average grass clumps per chunk

# Resource paths
const TREE_SCENE_PATH: String = "res://scenes/Tree.tscn"
const ROCK_SCENE_PATH: String = "res://scenes/Rock.tscn"
const GRASS_SCENE_PATH: String = "res://scenes/Grass.tscn"

# --- Properties ---
var biome_manager: BiomeManagerClass = null
var noise_generators: Dictionary = {}  # Cache for noise generators
var tree_models_cache: Dictionary = {}  # BiomeType -> Array[String] (mesh paths)
var rock_models_cache: Dictionary = {}  # BiomeType -> Array[String] (mesh paths)

# Thread safety
var _mutex: Mutex = Mutex.new()

# --- Engine Callbacks ---
func _ready() -> void:
	"""Initialize the chunk generator."""
	_initialize_biome_manager()
	_initialize_noise_generators()
	_load_biome_assets()
	
	print("ChunkGenerator: Initialized with seed %d" % world_seed)

# --- Public Methods ---
func generate_chunk(chunk_pos: Vector2i) -> Dictionary:
	"""Generate all data for a chunk. This runs on a background thread."""
	var start_time := Time.get_ticks_msec()
	
	# Create data containers
	var terrain_data := ChunkClass.ChunkTerrainData.new()
	var object_data := ChunkClass.ChunkObjectData.new()
	
	# Generate terrain mesh data
	_generate_terrain_data(chunk_pos, terrain_data)
	
	# Generate object placements
	_generate_objects_data(chunk_pos, object_data, terrain_data)
	
	var generation_time := (Time.get_ticks_msec() - start_time) / 1000.0
	
	return {
		"terrain": terrain_data,
		"objects": object_data,
		"generation_time": generation_time
	}

func get_height_at_position(world_pos: Vector3) -> float:
	"""Get terrain height at any world position using procedural generation."""
	if biome_manager:
		return biome_manager.get_terrain_height_at_position(world_pos)
	return 0.0

func set_world_seed(seed_value: int) -> void:
	"""Set the world generation seed."""
	world_seed = seed_value
	_initialize_noise_generators()

# --- Private Methods ---
func _initialize_biome_manager() -> void:
	"""Initialize the biome manager for terrain generation."""
	biome_manager = BiomeManagerClass.new()
	biome_manager.set_world_seed(world_seed)

func _initialize_noise_generators() -> void:
	"""Create noise generators for various generation tasks."""
	# Base terrain noise
	var terrain_noise := FastNoiseLite.new()
	terrain_noise.seed = world_seed
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	terrain_noise.frequency = 0.003
	noise_generators["terrain"] = terrain_noise
	
	# Object placement noise
	var placement_noise := FastNoiseLite.new()
	placement_noise.seed = world_seed + 1
	placement_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	placement_noise.frequency = 0.1
	noise_generators["placement"] = placement_noise
	
	# Density variation noise
	var density_noise := FastNoiseLite.new()
	density_noise.seed = world_seed + 2
	density_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	density_noise.frequency = 0.05
	noise_generators["density"] = density_noise

func _load_biome_assets() -> void:
	"""Cache paths to biome-specific assets."""
	# Get asset paths from biome manager
	for biome_type in BiomeManagerClass.BiomeType.values():
		tree_models_cache[biome_type] = biome_manager.get_tree_assets_for_biome(biome_type)
		rock_models_cache[biome_type] = biome_manager.get_rock_assets_for_biome(biome_type)

func _generate_terrain_data(chunk_pos: Vector2i, terrain_data: ChunkClass.ChunkTerrainData) -> void:
	"""Generate terrain mesh data for a chunk."""
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var height_map: PackedFloat32Array = PackedFloat32Array()
	
	# Calculate chunk world position
	var chunk_world_pos := Vector3(
		chunk_pos.x * ChunkClass.CHUNK_SIZE.x,
		0,
		chunk_pos.y * ChunkClass.CHUNK_SIZE.y
	)
	
	# Generate vertices
	var resolution := ChunkClass.TERRAIN_RESOLUTION_PER_CHUNK
	for z in range(resolution + 1):
		for x in range(resolution + 1):
			# Calculate world position for this vertex
			var local_x := (float(x) / resolution) * ChunkClass.CHUNK_SIZE.x
			var local_z := (float(z) / resolution) * ChunkClass.CHUNK_SIZE.y
			var world_x := chunk_world_pos.x + local_x
			var world_z := chunk_world_pos.z + local_z
			
			# Get height from biome manager
			var height := biome_manager.get_terrain_height_at_position(Vector3(world_x, 0, world_z))
			
			# Create vertex
			var vertex := Vector3(local_x, height, local_z)
			vertices.append(vertex)
			height_map.append(height)
			
			# UV coordinates
			var uv := Vector2(float(x) / resolution, float(z) / resolution)
			uvs.append(uv)
			
			# Get biome blend weights for vertex colors
			var biome_weights := biome_manager.get_biome_blend_weights(Vector3(world_x, 0, world_z))
			
			# Encode biome weights into vertex color
			var vertex_color := Color(0, 0, 0, 0)
			if biome_weights.has(BiomeManagerClass.BiomeType.FOREST):
				vertex_color.r = biome_weights[BiomeManagerClass.BiomeType.FOREST]
			if biome_weights.has(BiomeManagerClass.BiomeType.AUTUMN):
				vertex_color.g = biome_weights[BiomeManagerClass.BiomeType.AUTUMN]
			if biome_weights.has(BiomeManagerClass.BiomeType.SNOW):
				vertex_color.b = biome_weights[BiomeManagerClass.BiomeType.SNOW]
			if biome_weights.has(BiomeManagerClass.BiomeType.MOUNTAIN):
				vertex_color.a = biome_weights[BiomeManagerClass.BiomeType.MOUNTAIN]
			
			# Ensure at least one weight
			var total_weight := vertex_color.r + vertex_color.g + vertex_color.b + vertex_color.a
			if total_weight == 0.0:
				vertex_color.r = 1.0  # Default to forest
			
			colors.append(vertex_color)
	
	# Generate indices
	for z in range(resolution):
		for x in range(resolution):
			var top_left := z * (resolution + 1) + x
			var top_right := top_left + 1
			var bottom_left := (z + 1) * (resolution + 1) + x
			var bottom_right := bottom_left + 1
			
			# First triangle
			indices.append(top_left)
			indices.append(top_right)
			indices.append(bottom_left)
			
			# Second triangle
			indices.append(top_right)
			indices.append(bottom_right)
			indices.append(bottom_left)
	
	# Calculate normals
	normals = _calculate_normals(vertices, indices)
	
	# Store in terrain data
	terrain_data.vertices = vertices
	terrain_data.normals = normals
	terrain_data.uvs = uvs
	terrain_data.colors = colors
	terrain_data.indices = indices
	terrain_data.height_map = height_map

func _calculate_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	"""Calculate smooth normals for the terrain mesh."""
	var normals: PackedVector3Array = PackedVector3Array()
	normals.resize(vertices.size())
	
	# Initialize all normals to zero
	for i in range(normals.size()):
		normals[i] = Vector3.ZERO
	
	# Calculate face normals and accumulate
	for i in range(0, indices.size(), 3):
		var i0 := indices[i]
		var i1 := indices[i + 1]
		var i2 := indices[i + 2]
		
		var v0 := vertices[i0]
		var v1 := vertices[i1]
		var v2 := vertices[i2]
		
		var face_normal := (v1 - v0).cross(v2 - v0).normalized()
		
		normals[i0] += face_normal
		normals[i1] += face_normal
		normals[i2] += face_normal
	
	# Normalize all accumulated normals
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()
	
	return normals

func _generate_objects_data(chunk_pos: Vector2i, object_data: ChunkClass.ChunkObjectData, terrain_data: ChunkClass.ChunkTerrainData) -> void:
	"""Generate object placement data for a chunk."""
	# Calculate chunk world position
	var chunk_world_pos := Vector3(
		chunk_pos.x * ChunkClass.CHUNK_SIZE.x,
		0,
		chunk_pos.y * ChunkClass.CHUNK_SIZE.y
	)
	
	# Get density variation for this chunk
	var density_noise: FastNoiseLite = noise_generators["density"]
	var density_factor: float = (density_noise.get_noise_2d(chunk_pos.x * 10.0, chunk_pos.y * 10.0) + 1.0) * 0.5
	
	# Generate trees
	var tree_count := int(TREES_PER_CHUNK * density_factor)
	_generate_trees_for_chunk(chunk_pos, chunk_world_pos, tree_count, object_data, terrain_data)
	
	# Generate rocks
	var rock_count := int(ROCKS_PER_CHUNK * density_factor)
	_generate_rocks_for_chunk(chunk_pos, chunk_world_pos, rock_count, object_data, terrain_data)
	
	# Generate grass (only for high LOD)
	var grass_count := int(GRASS_PER_CHUNK * density_factor)
	_generate_grass_for_chunk(chunk_pos, chunk_world_pos, grass_count, object_data, terrain_data)

func _generate_trees_for_chunk(chunk_pos: Vector2i, chunk_world_pos: Vector3, count: int, object_data: ChunkClass.ChunkObjectData, terrain_data: ChunkClass.ChunkTerrainData) -> void:
	"""Generate tree placement data for a chunk."""
	var placement_noise: FastNoiseLite = noise_generators["placement"]
	
	for i in range(count):
		# Generate position within chunk
		var local_x := randf_range(-ChunkClass.CHUNK_SIZE.x * 0.5, ChunkClass.CHUNK_SIZE.x * 0.5)
		var local_z := randf_range(-ChunkClass.CHUNK_SIZE.y * 0.5, ChunkClass.CHUNK_SIZE.y * 0.5)
		var world_pos := chunk_world_pos + Vector3(local_x, 0, local_z)
		
		# Check biome suitability
		var biome_type := biome_manager.get_biome_at_position(world_pos)
		var tree_density := biome_manager.get_tree_density_for_biome(biome_type)
		
		# Use noise for placement variation
		var noise_value := placement_noise.get_noise_2d(world_pos.x, world_pos.z)
		if noise_value < tree_density - 1.0:
			continue
		
		# Get height at position
		var height := _get_height_at_local_position(Vector3(local_x, 0, local_z), terrain_data)
		
		# Select appropriate tree mesh
		var tree_assets: Array = tree_models_cache.get(biome_type, [])
		if tree_assets.is_empty():
			continue
		
		var mesh_path: String = tree_assets[randi() % tree_assets.size()]
		
		# Create tree data
		var tree_data := {
			"position": Vector3(local_x, height, local_z),
			"rotation": randf() * TAU,
			"scale": randf_range(2.0, 3.0),  # 2-3x scale
			"mesh_path": mesh_path,
			"biome_type": biome_type
		}
		
		object_data.trees.append(tree_data)

func _generate_rocks_for_chunk(chunk_pos: Vector2i, chunk_world_pos: Vector3, count: int, object_data: ChunkClass.ChunkObjectData, terrain_data: ChunkClass.ChunkTerrainData) -> void:
	"""Generate rock placement data for a chunk."""
	var placement_noise: FastNoiseLite = noise_generators["placement"]
	
	for i in range(count):
		# Generate position within chunk
		var local_x := randf_range(-ChunkClass.CHUNK_SIZE.x * 0.5, ChunkClass.CHUNK_SIZE.x * 0.5)
		var local_z := randf_range(-ChunkClass.CHUNK_SIZE.y * 0.5, ChunkClass.CHUNK_SIZE.y * 0.5)
		var world_pos := chunk_world_pos + Vector3(local_x, 0, local_z)
		
		# Check biome suitability
		var biome_type := biome_manager.get_biome_at_position(world_pos)
		var rock_density := biome_manager.get_rock_density_for_biome(biome_type)
		
		# Use noise for placement variation
		var noise_value := placement_noise.get_noise_2d(world_pos.x * 2.0, world_pos.z * 2.0)
		if noise_value < rock_density - 1.0:
			continue
		
		# Get height at position
		var height := _get_height_at_local_position(Vector3(local_x, 0, local_z), terrain_data)
		
		# Select appropriate rock mesh
		var rock_assets: Array = rock_models_cache.get(biome_type, [])
		if rock_assets.is_empty():
			continue
		
		var mesh_path: String = rock_assets[randi() % rock_assets.size()]
		
		# Create rock data
		var rock_data := {
			"position": Vector3(local_x, height, local_z),
			"rotation": randf() * TAU,
			"scale": randf_range(1.0, 15.0),  # 1-15x scale
			"mesh_path": mesh_path,
			"biome_type": biome_type
		}
		
		object_data.rocks.append(rock_data)

func _generate_grass_for_chunk(chunk_pos: Vector2i, chunk_world_pos: Vector3, count: int, object_data: ChunkClass.ChunkObjectData, terrain_data: ChunkClass.ChunkTerrainData) -> void:
	"""Generate grass placement data for a chunk."""
	for i in range(count):
		# Generate position within chunk
		var local_x := randf_range(-ChunkClass.CHUNK_SIZE.x * 0.5, ChunkClass.CHUNK_SIZE.x * 0.5)
		var local_z := randf_range(-ChunkClass.CHUNK_SIZE.y * 0.5, ChunkClass.CHUNK_SIZE.y * 0.5)
		var world_pos := chunk_world_pos + Vector3(local_x, 0, local_z)
		
		# Only spawn grass in forest and autumn biomes
		var biome_type := biome_manager.get_biome_at_position(world_pos)
		if biome_type != BiomeManagerClass.BiomeType.FOREST and biome_type != BiomeManagerClass.BiomeType.AUTUMN:
			continue
		
		# Get height at position
		var height := _get_height_at_local_position(Vector3(local_x, 0, local_z), terrain_data)
		
		# Calculate grass density based on slope
		var slope_factor: float = _calculate_slope_factor(Vector3(local_x, 0, local_z), terrain_data)
		var density: float = 1.0 - (slope_factor * 0.5)
		
		# Create grass data
		var grass_data := {
			"position": Vector3(local_x, height, local_z),
			"rotation": randf() * TAU,
			"scale": randf_range(0.8, 1.2),
			"density": clamp(density, 0.2, 1.0)
		}
		
		object_data.grass.append(grass_data)

func _get_height_at_local_position(local_pos: Vector3, terrain_data: ChunkClass.ChunkTerrainData) -> float:
	"""Get interpolated height at a local position within the chunk."""
	# Convert local position to grid coordinates
	var grid_x: float = (local_pos.x / ChunkClass.CHUNK_SIZE.x + 0.5) * ChunkClass.TERRAIN_RESOLUTION_PER_CHUNK
	var grid_z: float = (local_pos.z / ChunkClass.CHUNK_SIZE.y + 0.5) * ChunkClass.TERRAIN_RESOLUTION_PER_CHUNK
	
	# Get integer grid positions
	var x0 := int(floor(grid_x))
	var z0 := int(floor(grid_z))
	var x1: int = min(x0 + 1, ChunkClass.TERRAIN_RESOLUTION_PER_CHUNK)
	var z1: int = min(z0 + 1, ChunkClass.TERRAIN_RESOLUTION_PER_CHUNK)
	
	# Get fractional parts
	var fx: float = grid_x - x0
	var fz: float = grid_z - z0
	
	# Clamp to valid range
	x0 = clamp(x0, 0, ChunkClass.TERRAIN_RESOLUTION_PER_CHUNK)
	z0 = clamp(z0, 0, ChunkClass.TERRAIN_RESOLUTION_PER_CHUNK)
	
	# Get heights at corners
	var h00: float = terrain_data.height_map[z0 * (ChunkClass.TERRAIN_RESOLUTION_PER_CHUNK + 1) + x0]
	var h10: float = terrain_data.height_map[z0 * (ChunkClass.TERRAIN_RESOLUTION_PER_CHUNK + 1) + x1]
	var h01: float = terrain_data.height_map[z1 * (ChunkClass.TERRAIN_RESOLUTION_PER_CHUNK + 1) + x0]
	var h11: float = terrain_data.height_map[z1 * (ChunkClass.TERRAIN_RESOLUTION_PER_CHUNK + 1) + x1]
	
	# Bilinear interpolation
	var h0: float = lerp(h00, h10, fx)
	var h1: float = lerp(h01, h11, fx)
	
	return lerp(h0, h1, fz)

func _calculate_slope_factor(local_pos: Vector3, terrain_data: ChunkClass.ChunkTerrainData) -> float:
	"""Calculate slope factor at a position (0 = flat, 1 = steep)."""
	var sample_distance := 2.0
	
	# Get heights at neighboring points
	var height_center: float = _get_height_at_local_position(local_pos, terrain_data)
	var height_x_plus: float = _get_height_at_local_position(local_pos + Vector3(sample_distance, 0, 0), terrain_data)
	var height_z_plus: float = _get_height_at_local_position(local_pos + Vector3(0, 0, sample_distance), terrain_data)
	
	# Calculate slope
	var slope_x: float = abs(height_x_plus - height_center) / sample_distance
	var slope_z: float = abs(height_z_plus - height_center) / sample_distance
	var max_slope: float = max(slope_x, slope_z)
	
	# Normalize to 0-1 range (assuming max reasonable slope is 45 degrees = 1.0)
	return clamp(max_slope, 0.0, 1.0) 
