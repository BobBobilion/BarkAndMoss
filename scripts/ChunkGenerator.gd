class_name ChunkGenerator
extends Node

# --- Imports ---
const BiomeManagerClass = preload("res://scripts/BiomeManager.gd")
const Chunk = preload("res://scripts/Chunk.gd")

# --- Properties ---
var biome_manager: BiomeManagerClass
var noise_generators: Dictionary = {}
var world_seed: int

# --- Public Methods ---
func initialize(seed: int) -> void:
	world_seed = seed
	biome_manager = BiomeManagerClass.new()
	biome_manager.set_world_seed(world_seed)
	_initialize_noise_generators()

func generate_chunk_data(chunk_pos: Vector2i) -> Dictionary:
	var terrain_data := _generate_terrain(chunk_pos)
	var object_data := _generate_objects(chunk_pos, terrain_data)
	
	return {
		"terrain": terrain_data,
		"objects": object_data
	}

# --- Private Methods ---
func _initialize_noise_generators() -> void:
	# Add specific noise generators if needed, e.g., for object placement
	pass

func _generate_terrain(chunk_pos: Vector2i) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	
	var resolution := Chunk.TERRAIN_RESOLUTION
	for z in range(resolution + 1):
		for x in range(resolution + 1):
			var local_pos := Vector3(float(x) / resolution * Chunk.CHUNK_SIZE.x, 0, float(z) / resolution * Chunk.CHUNK_SIZE.y)
			var world_pos := local_pos + Vector3(chunk_pos.x * Chunk.CHUNK_SIZE.x, 0, chunk_pos.y * Chunk.CHUNK_SIZE.y)
			
			var height := biome_manager.get_terrain_height_at_position(world_pos)
			vertices.append(Vector3(local_pos.x, height, local_pos.z))
			uvs.append(Vector2(float(x) / resolution, float(z) / resolution))
			
			var biome_weights := biome_manager.get_biome_blend_weights(world_pos)
			colors.append(Color(
				biome_weights.get(BiomeManagerClass.BiomeType.FOREST, 0.0),
				biome_weights.get(BiomeManagerClass.BiomeType.AUTUMN, 0.0),
				biome_weights.get(BiomeManagerClass.BiomeType.SNOW, 0.0),
				biome_weights.get(BiomeManagerClass.BiomeType.MOUNTAIN, 0.0)
			))

	for z in range(resolution):
		for x in range(resolution):
			var i = z * (resolution + 1) + x
			indices.append(i)
			indices.append(i + 1)
			indices.append(i + resolution + 1)
			indices.append(i + 1)
			indices.append(i + resolution + 2)
			indices.append(i + resolution + 1)

	normals = _calculate_normals(vertices, indices)

	return {
		"vertices": vertices, "normals": normals, "uvs": uvs, "colors": colors, "indices": indices
	}

func _generate_objects(chunk_pos: Vector2i, terrain_data) -> Dictionary:
	var objects := { "trees": [], "rocks": [], "grass": [] }
	var chunk_world_pos := Vector3(chunk_pos.x * Chunk.CHUNK_SIZE.x, 0, chunk_pos.y * Chunk.CHUNK_SIZE.y)

	# Generate trees based on biome density
	var tree_base_count := 10  # Base number of tree spawn attempts per chunk
	for i in range(tree_base_count):
		var local_x := randf() * Chunk.CHUNK_SIZE.x
		var local_z := randf() * Chunk.CHUNK_SIZE.y
		var local_pos := Vector3(local_x, 0, local_z)
		var world_pos := chunk_world_pos + local_pos
		
		# Get the terrain height at this position
		var terrain_height := biome_manager.get_terrain_height_at_position(world_pos)
		local_pos.y = terrain_height
		
		# Get biome and check tree density
		var biome := biome_manager.get_biome_at_position(world_pos)
		var tree_density := biome_manager.get_tree_density_for_biome(biome)
		
		# Spawn tree based on biome density
		if randf() < tree_density:
			var tree_assets := biome_manager.get_tree_assets_for_biome(biome)
			if not tree_assets.is_empty():
				var world_constants := GameConstants.get_world_constants()
				objects.trees.append({
					"scene_path": "res://scenes/Tree.tscn",  # Use Tree scene instead of mesh path
					"mesh_path": tree_assets[randi() % tree_assets.size()],  # Store mesh for visuals
					"position": local_pos,
					"rotation": randf() * TAU,
					"scale": world_constants.TREE_BASE_SCALE * randf_range(world_constants.TREE_MIN_SCALE, world_constants.TREE_MAX_SCALE)
				})
	
	# Generate rocks based on biome density
	var rock_base_count := 8  # Base number of rock spawn attempts per chunk
	for i in range(rock_base_count):
		var local_x := randf() * Chunk.CHUNK_SIZE.x
		var local_z := randf() * Chunk.CHUNK_SIZE.y
		var local_pos := Vector3(local_x, 0, local_z)
		var world_pos := chunk_world_pos + local_pos
		
		# Get the terrain height at this position
		var terrain_height := biome_manager.get_terrain_height_at_position(world_pos)
		local_pos.y = terrain_height
		
		# Get biome and check rock density
		var biome := biome_manager.get_biome_at_position(world_pos)
		var rock_density := biome_manager.get_rock_density_for_biome(biome)
		
		# Spawn rock based on biome density
		if randf() < rock_density:
			var rock_assets := biome_manager.get_rock_assets_for_biome(biome)
			if not rock_assets.is_empty():
				var world_constants := GameConstants.get_world_constants()
				objects.rocks.append({
					"mesh_path": rock_assets[randi() % rock_assets.size()],
					"position": local_pos,
					"rotation": randf() * TAU,
					"scale": randf_range(world_constants.ROCK_MIN_SCALE, world_constants.ROCK_MAX_SCALE)
				})
	
	# TODO: Add grass generation here if needed
	
	return objects

func _calculate_normals(vertices, indices) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in range(0, indices.size(), 3):
		var i0 = indices[i]
		var i1 = indices[i+1]
		var i2 = indices[i+2]
		var v0 = vertices[i0]
		var v1 = vertices[i1]
		var v2 = vertices[i2]
		var normal = (v1 - v0).cross(v2 - v0).normalized()
		normals[i0] += normal
		normals[i1] += normal
		normals[i2] += normal
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()
	return normals 
