class_name ChunkPool
extends Node

# --- Constants ---
const MAX_CACHED_CHUNKS: int = 100      # Maximum chunks to keep in memory
const MAX_POOLED_OBJECTS: int = 500     # Maximum pooled objects per type

# --- Properties ---
# Chunk data cache (LRU)
var chunk_data_cache: Dictionary = {}   # Vector2i -> {terrain, objects, timestamp}
var cache_order: Array[Vector2i] = []   # LRU order tracking

# Object pools for reuse
var tree_pool: Array[Node3D] = []
var rock_pool: Array[Node3D] = []
var grass_pool: Array[Node3D] = []
var mesh_instance_pool: Array[MeshInstance3D] = []

# Resource caches
var loaded_meshes: Dictionary = {}      # path -> Mesh resource
var loaded_materials: Dictionary = {}   # path -> Material resource

# Thread safety
var _mutex: Mutex = Mutex.new()

# Statistics
var cache_hits: int = 0
var cache_misses: int = 0
var objects_pooled: int = 0
var objects_created: int = 0

# --- Engine Callbacks ---
func _ready() -> void:
	"""Initialize the chunk pool."""
	print("ChunkPool: Initialized with max cache size: %d chunks" % MAX_CACHED_CHUNKS)

func _exit_tree() -> void:
	"""Clean up pooled objects."""
	_clear_all_pools()

# --- Public Methods - Chunk Data ---
func store_chunk_data(chunk_pos: Vector2i, data: Dictionary) -> void:
	"""Store generated chunk data in the cache."""
	_mutex.lock()
	
	# Add to cache with timestamp
	chunk_data_cache[chunk_pos] = {
		"terrain": data.get("terrain"),
		"objects": data.get("objects"),
		"timestamp": Time.get_ticks_msec(),
		"generation_time": data.get("generation_time", 0.0)
	}
	
	# Update LRU order
	if chunk_pos in cache_order:
		cache_order.erase(chunk_pos)
	cache_order.push_back(chunk_pos)
	
	# Evict oldest if over limit
	while cache_order.size() > MAX_CACHED_CHUNKS:
		var oldest: Vector2i = cache_order.pop_front()
		chunk_data_cache.erase(oldest)
		print("ChunkPool: Evicted chunk %v from cache" % oldest)
	
	_mutex.unlock()

func get_chunk_data(chunk_pos: Vector2i) -> Dictionary:
	"""Retrieve chunk data from cache if available."""
	_mutex.lock()
	
	if chunk_data_cache.has(chunk_pos):
		# Update access time and LRU order
		var data = chunk_data_cache[chunk_pos]
		data["timestamp"] = Time.get_ticks_msec()
		
		cache_order.erase(chunk_pos)
		cache_order.push_back(chunk_pos)
		
		cache_hits += 1
		_mutex.unlock()
		return data
	
	cache_misses += 1
	_mutex.unlock()
	return {}

func has_chunk_data(chunk_pos: Vector2i) -> bool:
	"""Check if chunk data is cached."""
	_mutex.lock()
	var has_data := chunk_data_cache.has(chunk_pos)
	_mutex.unlock()
	return has_data

func clear_chunk_data(chunk_pos: Vector2i) -> void:
	"""Remove specific chunk data from cache."""
	_mutex.lock()
	chunk_data_cache.erase(chunk_pos)
	cache_order.erase(chunk_pos)
	_mutex.unlock()

# --- Public Methods - Object Pooling ---
func get_tree_instance() -> Node3D:
	"""Get a tree instance from the pool or create a new one."""
	_mutex.lock()
	
	if tree_pool.size() > 0:
		var tree: Node3D = tree_pool.pop_back()
		objects_pooled += 1
		_mutex.unlock()
		return tree
	
	_mutex.unlock()
	
	# Create new tree instance if pool is empty
	var tree_scene: PackedScene = load(ChunkGenerator.TREE_SCENE_PATH)
	if tree_scene:
		var tree: Node3D = tree_scene.instantiate()
		objects_created += 1
		return tree
	
	return null

func return_tree_instance(tree: Node3D) -> void:
	"""Return a tree instance to the pool."""
	if not is_instance_valid(tree):
		return
	
	# Reset tree state
	tree.visible = false
	if tree.get_parent():
		tree.get_parent().remove_child(tree)
	
	_mutex.lock()
	if tree_pool.size() < MAX_POOLED_OBJECTS:
		tree_pool.append(tree)
	else:
		tree.queue_free()
	_mutex.unlock()

func get_rock_instance() -> StaticBody3D:
	"""Get a rock instance from the pool or create a new one."""
	_mutex.lock()
	
	if rock_pool.size() > 0:
		var rock := rock_pool.pop_back() as StaticBody3D
		objects_pooled += 1
		_mutex.unlock()
		return rock
	
	_mutex.unlock()
	
	# Create new rock instance
	var rock := StaticBody3D.new()
	rock.collision_layer = 2  # Environment layer
	rock.collision_mask = 0
	objects_created += 1
	
	return rock

func return_rock_instance(rock: StaticBody3D) -> void:
	"""Return a rock instance to the pool."""
	if not is_instance_valid(rock):
		return
	
	# Reset rock state
	rock.visible = false
	if rock.get_parent():
		rock.get_parent().remove_child(rock)
	
	# Clear children (mesh and collision shape)
	for child in rock.get_children():
		child.queue_free()
	
	_mutex.lock()
	if rock_pool.size() < MAX_POOLED_OBJECTS:
		rock_pool.append(rock)
	else:
		rock.queue_free()
	_mutex.unlock()

func get_grass_instance() -> Node3D:
	"""Get a grass instance from the pool or create a new one."""
	_mutex.lock()
	
	if grass_pool.size() > 0:
		var grass: Node3D = grass_pool.pop_back()
		objects_pooled += 1
		_mutex.unlock()
		return grass
	
	_mutex.unlock()
	
	# Create new grass instance if pool is empty
	var grass_scene: PackedScene = load(ChunkGenerator.GRASS_SCENE_PATH)
	if grass_scene:
		var grass: Node3D = grass_scene.instantiate()
		objects_created += 1
		return grass
	
	return null

func return_grass_instance(grass: Node3D) -> void:
	"""Return a grass instance to the pool."""
	if not is_instance_valid(grass):
		return
	
	# Reset grass state
	grass.visible = false
	if grass.get_parent():
		grass.get_parent().remove_child(grass)
	
	_mutex.lock()
	if grass_pool.size() < MAX_POOLED_OBJECTS:
		grass_pool.append(grass)
	else:
		grass.queue_free()
	_mutex.unlock()

func get_mesh_instance() -> MeshInstance3D:
	"""Get a mesh instance from the pool or create a new one."""
	_mutex.lock()
	
	if mesh_instance_pool.size() > 0:
		var instance: MeshInstance3D = mesh_instance_pool.pop_back()
		objects_pooled += 1
		_mutex.unlock()
		return instance
	
	_mutex.unlock()
	
	# Create new mesh instance
	var instance := MeshInstance3D.new()
	objects_created += 1
	return instance

func return_mesh_instance(instance: MeshInstance3D) -> void:
	"""Return a mesh instance to the pool."""
	if not is_instance_valid(instance):
		return
	
	# Reset mesh instance state
	instance.mesh = null
	instance.visible = false
	if instance.get_parent():
		instance.get_parent().remove_child(instance)
	
	_mutex.lock()
	if mesh_instance_pool.size() < MAX_POOLED_OBJECTS:
		mesh_instance_pool.append(instance)
	else:
		instance.queue_free()
	_mutex.unlock()

# --- Public Methods - Resource Management ---
func get_mesh(path: String) -> Mesh:
	"""Get a cached mesh resource."""
	_mutex.lock()
	
	if loaded_meshes.has(path):
		_mutex.unlock()
		return loaded_meshes[path]
	
	_mutex.unlock()
	
	# Load mesh if not cached
	if ResourceLoader.exists(path):
		var mesh := load(path) as Mesh
		if mesh:
			_mutex.lock()
			loaded_meshes[path] = mesh
			_mutex.unlock()
			return mesh
	
	return null

func get_material(path: String) -> Material:
	"""Get a cached material resource."""
	_mutex.lock()
	
	if loaded_materials.has(path):
		_mutex.unlock()
		return loaded_materials[path]
	
	_mutex.unlock()
	
	# Load material if not cached
	if ResourceLoader.exists(path):
		var material := load(path) as Material
		if material:
			_mutex.lock()
			loaded_materials[path] = material
			_mutex.unlock()
			return material
	
	return null

func preload_resources(paths: Array[String]) -> void:
	"""Preload a list of resources into cache."""
	for path in paths:
		if path.ends_with(".tscn") or path.ends_with(".glb") or path.ends_with(".gltf"):
			get_mesh(path)
		elif path.ends_with(".tres") or path.ends_with(".material"):
			get_material(path)

# --- Public Methods - Statistics ---
func get_statistics() -> Dictionary:
	"""Get pool statistics for debugging."""
	_mutex.lock()
	var stats := {
		"cached_chunks": chunk_data_cache.size(),
		"cache_hits": cache_hits,
		"cache_misses": cache_misses,
		"cache_hit_rate": float(cache_hits) / max(cache_hits + cache_misses, 1),
		"pooled_trees": tree_pool.size(),
		"pooled_rocks": rock_pool.size(),
		"pooled_grass": grass_pool.size(),
		"pooled_mesh_instances": mesh_instance_pool.size(),
		"total_objects_pooled": objects_pooled,
		"total_objects_created": objects_created,
		"loaded_meshes": loaded_meshes.size(),
		"loaded_materials": loaded_materials.size()
	}
	_mutex.unlock()
	return stats

func print_statistics() -> void:
	"""Print pool statistics to console."""
	var stats := get_statistics()
	print("ChunkPool Statistics:")
	print("  Cached chunks: %d / %d" % [stats["cached_chunks"], MAX_CACHED_CHUNKS])
	print("  Cache hit rate: %.1f%%" % (stats["cache_hit_rate"] * 100))
	print("  Pooled objects: Trees=%d, Rocks=%d, Grass=%d, Meshes=%d" % 
		[stats["pooled_trees"], stats["pooled_rocks"], stats["pooled_grass"], stats["pooled_mesh_instances"]])
	print("  Object reuse rate: %.1f%%" % (float(stats["total_objects_pooled"]) / 
		max(stats["total_objects_pooled"] + stats["total_objects_created"], 1) * 100))

# --- Private Methods ---
func _clear_all_pools() -> void:
	"""Clear all object pools and free resources."""
	_mutex.lock()
	
	# Free all pooled objects
	for tree in tree_pool:
		if is_instance_valid(tree):
			tree.queue_free()
	tree_pool.clear()
	
	for rock in rock_pool:
		if is_instance_valid(rock):
			rock.queue_free()
	rock_pool.clear()
	
	for grass in grass_pool:
		if is_instance_valid(grass):
			grass.queue_free()
	grass_pool.clear()
	
	for instance in mesh_instance_pool:
		if is_instance_valid(instance):
			instance.queue_free()
	mesh_instance_pool.clear()
	
	# Clear caches
	chunk_data_cache.clear()
	cache_order.clear()
	loaded_meshes.clear()
	loaded_materials.clear()
	
	_mutex.unlock()
	
	print("ChunkPool: All pools cleared") 
