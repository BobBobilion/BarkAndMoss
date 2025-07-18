class_name Chunk
extends Node3D

# --- Signals ---
signal generation_complete()
signal loading_complete()
signal unloading_complete()

# --- Constants ---
# Chunk dimensions in world units
const CHUNK_SIZE: Vector2 = Vector2(64, 64)  # Optimal balance between generation time and overhead
const CHUNK_HEIGHT: float = 128.0            # Vertical size for generation
const TERRAIN_RESOLUTION_PER_CHUNK: int = 32 # Vertices per chunk edge

# --- Enums ---
enum ChunkState {
	UNLOADED,      # Not in memory
	QUEUED,        # Waiting for generation
	GENERATING,    # Being generated (thread)
	GENERATED,     # Data ready, not instantiated
	LOADING,       # Being added to scene
	LOADED,        # Fully loaded and visible
	UNLOADING      # Being removed
}

enum LODLevel {
	HIGH,          # Full detail with all objects
	MEDIUM,        # Terrain + large objects only
	LOW,           # Terrain only
	UNLOADED       # Not visible
}

# --- Properties ---
@export var chunk_position: Vector2i  # Chunk coordinates (not world position)
@export var current_state: ChunkState = ChunkState.UNLOADED
@export var current_lod: LODLevel = LODLevel.UNLOADED
@export var reference_count: int = 0  # Number of players needing this chunk

# Generation data (stored for quick re-loading)
var terrain_data: ChunkTerrainData = null
var object_data: ChunkObjectData = null
var is_data_generated: bool = false

# Scene nodes
var terrain_instance: MeshInstance3D = null
var terrain_collision: StaticBody3D = null
var objects_container: Node3D = null
var grass_container: Node3D = null

# Performance tracking
var generation_time: float = 0.0
var last_accessed_time: float = 0.0

# Thread safety
var _mutex: Mutex = Mutex.new()

# --- Inner Classes ---
class ChunkTerrainData:
	var vertices: PackedVector3Array
	var normals: PackedVector3Array
	var uvs: PackedVector2Array
	var colors: PackedColorArray  # For biome blending
	var indices: PackedInt32Array
	var height_map: PackedFloat32Array  # For quick height lookups

class ChunkObjectData:
	var trees: Array[Dictionary] = []      # {position, rotation, scale, mesh_path, biome_type}
	var rocks: Array[Dictionary] = []      # {position, rotation, scale, mesh_path, biome_type}
	var grass: Array[Dictionary] = []      # {position, rotation, scale, density}
	var animals: Array[Dictionary] = []    # {position, type, spawn_data}

# --- Engine Callbacks ---
func _ready() -> void:
	add_to_group("chunks")
	name = "Chunk_%d_%d" % [chunk_position.x, chunk_position.y]

# --- Public Methods ---
func initialize(pos: Vector2i) -> void:
	"""Initialize chunk with its grid position."""
	chunk_position = pos
	position = get_world_position_from_chunk_pos(pos)
	last_accessed_time = Time.get_ticks_msec() / 1000.0

func get_world_position_from_chunk_pos(chunk_pos: Vector2i) -> Vector3:
	"""Convert chunk coordinates to world position (center of chunk)."""
	return Vector3(
		chunk_pos.x * CHUNK_SIZE.x,
		0,
		chunk_pos.y * CHUNK_SIZE.y
	)

func get_chunk_bounds() -> AABB:
	"""Get the axis-aligned bounding box for this chunk."""
	var world_pos := get_world_position_from_chunk_pos(chunk_position)
	var half_size := Vector3(CHUNK_SIZE.x * 0.5, CHUNK_HEIGHT * 0.5, CHUNK_SIZE.y * 0.5)
	return AABB(world_pos - half_size, half_size * 2.0)

func add_reference() -> void:
	"""Called when a player needs this chunk."""
	_mutex.lock()
	reference_count += 1
	_mutex.unlock()

func remove_reference() -> void:
	"""Called when a player no longer needs this chunk."""
	_mutex.lock()
	reference_count = max(0, reference_count - 1)
	_mutex.unlock()

func should_unload() -> bool:
	"""Check if this chunk should be unloaded."""
	return reference_count <= 0 and current_state == ChunkState.LOADED

func update_lod(new_lod: LODLevel) -> void:
	"""Update the level of detail for this chunk."""
	if current_lod == new_lod:
		return
		
	var old_lod := current_lod
	current_lod = new_lod
	
	# Apply LOD changes
	match new_lod:
		LODLevel.HIGH:
			_show_all_objects()
		LODLevel.MEDIUM:
			_show_large_objects_only()
		LODLevel.LOW:
			_show_terrain_only()
		LODLevel.UNLOADED:
			_hide_everything()

func set_terrain_data(data: ChunkTerrainData) -> void:
	"""Store generated terrain data for this chunk."""
	terrain_data = data
	is_data_generated = true

func set_object_data(data: ChunkObjectData) -> void:
	"""Store generated object data for this chunk."""
	object_data = data

func create_terrain_mesh() -> void:
	"""Create the visual mesh from terrain data."""
	if not terrain_data:
		return
		
	# Create mesh instance
	terrain_instance = MeshInstance3D.new()
	terrain_instance.name = "TerrainMesh"
	
	# Build the mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = terrain_data.vertices
	arrays[Mesh.ARRAY_NORMAL] = terrain_data.normals
	arrays[Mesh.ARRAY_TEX_UV] = terrain_data.uvs
	arrays[Mesh.ARRAY_COLOR] = terrain_data.colors
	arrays[Mesh.ARRAY_INDEX] = terrain_data.indices
	
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	terrain_instance.mesh = mesh
	
	# Enable shadows
	terrain_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	add_child(terrain_instance)

func create_terrain_collision() -> void:
	"""Create collision shape for the terrain."""
	if not terrain_instance or not terrain_instance.mesh:
		return
		
	terrain_collision = StaticBody3D.new()
	terrain_collision.name = "TerrainCollision"
	terrain_collision.collision_layer = 1  # Terrain layer
	terrain_collision.collision_mask = 0   # Terrain doesn't detect anything
	
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "TerrainCollisionShape"
	
	# Create trimesh collision from mesh
	var shape: ConcavePolygonShape3D = terrain_instance.mesh.create_trimesh_shape()
	if shape:
		collision_shape.shape = shape
		terrain_collision.add_child(collision_shape)
		add_child(terrain_collision)
	else:
		push_error("Chunk: Failed to create terrain collision for chunk %v" % chunk_position)

func instantiate_objects(lod: LODLevel) -> void:
	"""Create object instances based on LOD level."""
	if not object_data:
		return
		
	# Create containers if needed
	if not objects_container:
		objects_container = Node3D.new()
		objects_container.name = "Objects"
		add_child(objects_container)
		
	if not grass_container and lod == LODLevel.HIGH:
		grass_container = Node3D.new()
		grass_container.name = "Grass"
		add_child(grass_container)
	
	# Instantiate objects based on LOD
	match lod:
		LODLevel.HIGH:
			_instantiate_trees()
			_instantiate_rocks()
			_instantiate_grass()
		LODLevel.MEDIUM:
			_instantiate_trees()
			_instantiate_rocks()
		LODLevel.LOW:
			# Terrain only, no objects
			pass

func clear_objects() -> void:
	"""Remove all instantiated objects."""
	if objects_container:
		objects_container.queue_free()
		objects_container = null
	if grass_container:
		grass_container.queue_free()
		grass_container = null

func get_height_at_position(world_pos: Vector3) -> float:
	"""Get terrain height at a world position within this chunk."""
	if not terrain_data or not terrain_data.height_map:
		return 0.0
		
	# Convert world position to chunk-local position
	var chunk_world_pos := get_world_position_from_chunk_pos(chunk_position)
	var local_pos := world_pos - chunk_world_pos
	
	# Convert to terrain grid coordinates
	var grid_x := int((local_pos.x / CHUNK_SIZE.x + 0.5) * TERRAIN_RESOLUTION_PER_CHUNK)
	var grid_z := int((local_pos.z / CHUNK_SIZE.y + 0.5) * TERRAIN_RESOLUTION_PER_CHUNK)
	
	# Clamp to valid range
	grid_x = clamp(grid_x, 0, TERRAIN_RESOLUTION_PER_CHUNK)
	grid_z = clamp(grid_z, 0, TERRAIN_RESOLUTION_PER_CHUNK)
	
	# Get height from height map
	var index := grid_z * (TERRAIN_RESOLUTION_PER_CHUNK + 1) + grid_x
	if index < terrain_data.height_map.size():
		return terrain_data.height_map[index]
	
	return 0.0

# --- Private Methods ---
func _show_all_objects() -> void:
	"""Show all objects for high LOD."""
	if terrain_instance:
		terrain_instance.visible = true
	if objects_container:
		objects_container.visible = true
	if grass_container:
		grass_container.visible = true

func _show_large_objects_only() -> void:
	"""Show only large objects for medium LOD."""
	if terrain_instance:
		terrain_instance.visible = true
	if objects_container:
		objects_container.visible = true
	if grass_container:
		grass_container.visible = false

func _show_terrain_only() -> void:
	"""Show only terrain for low LOD."""
	if terrain_instance:
		terrain_instance.visible = true
	if objects_container:
		objects_container.visible = false
	if grass_container:
		grass_container.visible = false

func _hide_everything() -> void:
	"""Hide all chunk content."""
	if terrain_instance:
		terrain_instance.visible = false
	if objects_container:
		objects_container.visible = false
	if grass_container:
		grass_container.visible = false

func _instantiate_trees() -> void:
	"""Create tree instances from object data."""
	# Tree instantiation is now handled by ChunkLoader
	# This method is kept for backwards compatibility
	pass

func _instantiate_rocks() -> void:
	"""Create rock instances from object data."""
	# Rock instantiation is now handled by ChunkLoader
	# This method is kept for backwards compatibility
	pass

func _instantiate_grass() -> void:
	"""Create grass instances from object data."""
	# Grass instantiation is now handled by ChunkLoader
	# This method is kept for backwards compatibility
	pass 