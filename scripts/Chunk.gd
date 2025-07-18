class_name Chunk
extends Node3D

# --- Signals ---
signal ready_for_display()

# --- Constants ---
const CHUNK_SIZE := Vector2(64, 64)
const TERRAIN_RESOLUTION := 32

# --- Enums ---
enum State { UNLOADED, LOADING, LOADED, UNLOADING }
enum LOD { HIGH, MEDIUM, LOW, NONE }

# --- Properties ---
var chunk_pos: Vector2i
var current_state := State.UNLOADED
var current_lod := LOD.NONE

var terrain_data: Dictionary
var object_data: Dictionary

var terrain_mesh_instance: MeshInstance3D
var terrain_collision: StaticBody3D
var objects_root: Node3D

# Material passed from ChunkManager
var _terrain_material: ShaderMaterial = null

var _reference_count := 0
var _mutex := Mutex.new()

# --- Public Methods ---
func initialize(pos: Vector2i) -> void:
	chunk_pos = pos
	position = Vector3(pos.x * CHUNK_SIZE.x, 0, pos.y * CHUNK_SIZE.y)
	name = "Chunk_%d_%d" % [pos.x, pos.y]
	
	# Add to group for cleanup purposes
	add_to_group("chunks")

func load_data(data: Dictionary) -> void:
	current_state = State.LOADING
	terrain_data = data["terrain"]
	object_data = data["objects"]
	
	_build_terrain()
	_build_objects()
	
	current_state = State.LOADED
	ready_for_display.emit()

func unload() -> void:
	current_state = State.UNLOADING
	queue_free()

func set_lod(lod: LOD) -> void:
	if current_lod == lod:
		return
	current_lod = lod
	
	if not is_inside_tree() or not objects_root:
		return
		
	match lod:
		LOD.HIGH:
			objects_root.show()
			for child in objects_root.get_children():
				if "grass" in child.name.to_lower():
					child.show()
		LOD.MEDIUM:
			objects_root.show()
			for child in objects_root.get_children():
				if "grass" in child.name.to_lower():
					child.hide()
		LOD.LOW:
			objects_root.hide()
		LOD.NONE:
			objects_root.hide()

func add_reference() -> void:
	_mutex.lock()
	_reference_count += 1
	_mutex.unlock()

func remove_reference() -> int:
	_mutex.lock()
	_reference_count = max(0, _reference_count - 1)
	var count = _reference_count
	_mutex.unlock()
	return count

# --- Private Methods ---
func _build_terrain() -> void:
	if not terrain_data:
		print("Chunk: No terrain data for chunk at ", chunk_pos)
		return
	
	print("Chunk: Building terrain for chunk at ", chunk_pos)
	print("  Vertices: ", terrain_data.vertices.size())
	print("  Indices: ", terrain_data.indices.size())
	print("  Colors sample: ", terrain_data.colors[0] if terrain_data.colors.size() > 0 else "No colors")
		
	# Create Mesh
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = terrain_data.vertices
	arrays[Mesh.ARRAY_NORMAL] = terrain_data.normals
	arrays[Mesh.ARRAY_TEX_UV] = terrain_data.uvs
	arrays[Mesh.ARRAY_COLOR] = terrain_data.colors
	arrays[Mesh.ARRAY_INDEX] = terrain_data.indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	terrain_mesh_instance = MeshInstance3D.new()
	terrain_mesh_instance.mesh = mesh
	terrain_mesh_instance.name = "TerrainMesh_" + str(chunk_pos.x) + "_" + str(chunk_pos.y)
	
	# Apply the terrain material
	if _terrain_material:
		terrain_mesh_instance.material_override = _terrain_material
		print("Chunk: Applied terrain material to chunk at ", chunk_pos, " (passed from ChunkManager)")
	else:
		# Fallback: Try to get from parent ChunkManager
		var chunk_manager = get_parent()
		if chunk_manager and chunk_manager.has_method("get_terrain_material"):
			var terrain_material = chunk_manager.get_terrain_material()
			if terrain_material:
				terrain_mesh_instance.material_override = terrain_material
				print("Chunk: Applied terrain material to chunk at ", chunk_pos, " (fallback from ChunkManager)")
			else:
				print("Chunk: No terrain material available from ChunkManager")
				# Create a basic colored material as ultimate fallback
				var fallback_mat = StandardMaterial3D.new()
				fallback_mat.albedo_color = Color(0.3, 0.6, 0.2)  # Green terrain color
				fallback_mat.vertex_color_use_as_albedo = true
				terrain_mesh_instance.material_override = fallback_mat
				print("Chunk: Using fallback colored material")
		else:
			print("Chunk: ChunkManager not found or no get_terrain_material method")
			# Create a basic colored material as ultimate fallback
			var fallback_mat = StandardMaterial3D.new()
			fallback_mat.albedo_color = Color(0.3, 0.6, 0.2)  # Green terrain color
			fallback_mat.vertex_color_use_as_albedo = true
			terrain_mesh_instance.material_override = fallback_mat
			print("Chunk: Using fallback colored material (no parent)")
	
	add_child(terrain_mesh_instance)
	
	# Create Collision
	terrain_collision = StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = mesh.create_trimesh_shape()
	terrain_collision.add_child(collision_shape)
	add_child(terrain_collision)

func _build_objects() -> void:
	if not object_data:
		return
		
	objects_root = Node3D.new()
	objects_root.name = "Objects"
	add_child(objects_root)

	for tree in object_data.trees:
		_create_tree(tree)
	for rock in object_data.rocks:
		_create_rock(rock)
	for grass in object_data.grass:
		_create_grass(grass)

func _create_tree(data: Dictionary) -> void:
	# Check if it's a scene file or a mesh file
	if data.mesh_path.ends_with(".tscn"):
		# Load as PackedScene
		var scene: PackedScene = load(data.mesh_path)
		if not scene:
			return
		var instance := scene.instantiate()
		instance.position = data.position
		instance.rotation.y = data.rotation
		instance.scale = Vector3.ONE * data.scale
		objects_root.add_child(instance)
	else:
		# Load as Mesh (for .obj, .glb, .gltf files)
		var mesh: Mesh = load(data.mesh_path)
		if not mesh:
			return
		
		# Create a basic tree node structure
		var tree_body := StaticBody3D.new()
		var mesh_instance := MeshInstance3D.new()
		var collision_shape := CollisionShape3D.new()
		
		# Set up the mesh
		mesh_instance.mesh = mesh
		
		# Create collision shape from mesh
		collision_shape.shape = mesh.create_trimesh_shape()
		
		# Build the tree structure
		tree_body.add_child(mesh_instance)
		tree_body.add_child(collision_shape)
		
		# Apply transform data
		tree_body.position = data.position
		tree_body.rotation.y = data.rotation
		tree_body.scale = Vector3.ONE * data.scale
		
		# Add to objects root
		objects_root.add_child(tree_body)

func _create_rock(data: Dictionary) -> void:
	# Rocks are simple meshes
	var mesh: Mesh = load(data.mesh_path)
	if not mesh:
		return
	
	var body := StaticBody3D.new()
	var mesh_instance := MeshInstance3D.new()
	var collision_shape := CollisionShape3D.new()
	
	mesh_instance.mesh = mesh
	collision_shape.shape = mesh.create_trimesh_shape()
	
	body.add_child(mesh_instance)
	body.add_child(collision_shape)
	
	body.position = data.position
	body.rotation.y = data.rotation
	body.scale = Vector3.ONE * data.scale
	objects_root.add_child(body)

func _create_grass(data: Dictionary) -> void:
	var scene: PackedScene = load("res://scenes/Grass.tscn")
	if not scene:
		return
	var instance := scene.instantiate()
	instance.name = "Grass"
	instance.position = data.position
	instance.rotation.y = data.rotation
	instance.scale = Vector3.ONE * data.scale
	objects_root.add_child(instance) 
