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

# Debug grid visualization
@export var show_borders: bool = false
var border_mesh_instance: MeshInstance3D = null

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
	
	# Add chunk borders for visualization
	if show_borders:
		_build_chunk_borders()
	
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
		return
	

		
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
		
	else:
		# Fallback: Try to get from parent ChunkManager
		var chunk_manager = get_parent()
		if chunk_manager and chunk_manager.has_method("get_terrain_material"):
			var terrain_material = chunk_manager.get_terrain_material()
			if terrain_material:
				terrain_mesh_instance.material_override = terrain_material
	
			else:
				# Create a basic colored material as ultimate fallback
				var fallback_mat = StandardMaterial3D.new()
				fallback_mat.albedo_color = Color(0.3, 0.6, 0.2)  # Green terrain color
				fallback_mat.vertex_color_use_as_albedo = true
				terrain_mesh_instance.material_override = fallback_mat
		else:
			# Create a basic colored material as ultimate fallback
			var fallback_mat = StandardMaterial3D.new()
			fallback_mat.albedo_color = Color(0.3, 0.6, 0.2)  # Green terrain color
			fallback_mat.vertex_color_use_as_albedo = true
			terrain_mesh_instance.material_override = fallback_mat
	
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
	# Check if we have a scene_path (new method for trees with scripts)
	if data.has("scene_path") and data.scene_path != null and not data.scene_path.is_empty():
		# Load as PackedScene (Tree.tscn with TreeStump script)
		var scene: PackedScene = load(data.scene_path)
		if not scene:
			push_error("Chunk: Failed to load tree scene: %s" % data.scene_path)
			return
		
		var tree_instance := scene.instantiate()
		
		# Set transform
		tree_instance.position = data.position
		tree_instance.rotation.y = data.rotation
		tree_instance.scale = Vector3.ONE * data.scale
		
		# Ensure proper collision layer setup (matching Tree.tscn)
		if tree_instance is StaticBody3D:
			tree_instance.collision_layer = 2  # Environment layer for axe detection
			tree_instance.collision_mask = 0   # Trees don't need to detect anything
		
		# Apply biome-specific mesh if provided
		if data.has("mesh_path") and data.mesh_path != null and not data.mesh_path.is_empty():
			if ResourceLoader.exists(data.mesh_path):
				var tree_mesh: Mesh = load(data.mesh_path)
				if tree_mesh:
					# Add the tree mesh to the visuals node
					var visuals_node: Node3D = tree_instance.get_node("Visuals")
					if visuals_node:
						# Clear existing placeholder meshes
						for child in visuals_node.get_children():
							child.queue_free()
						# Create and add mesh instance with the biome-appropriate mesh
						var mesh_instance: MeshInstance3D = MeshInstance3D.new()
						mesh_instance.mesh = tree_mesh
						mesh_instance.scale = Vector3(2.5, 2.5, 2.5)  # Scale to match WorldGenerator
						visuals_node.add_child(mesh_instance)
						
						# Update collision shapes to match the mesh
						_update_tree_collision_for_mesh(tree_instance, tree_mesh)
		
		objects_root.add_child(tree_instance)
		return
	
	# Fallback: validate mesh_path for legacy method
	if not data.has("mesh_path") or data.mesh_path == null or data.mesh_path.is_empty():
		push_error("Chunk: Invalid mesh_path for tree: %s" % data)
		return
	
	# Check if the file actually exists
	if not ResourceLoader.exists(data.mesh_path):
		push_warning("Chunk: Tree mesh file not found: %s" % data.mesh_path)
		return
	
	# Check if it's a scene file or a mesh file
	if data.mesh_path.ends_with(".tscn"):
		# Load as PackedScene
		var scene: PackedScene = load(data.mesh_path)
		if not scene:
			push_error("Chunk: Failed to load tree scene: %s" % data.mesh_path)
			return
		var instance := scene.instantiate()
		instance.position = data.position
		instance.rotation.y = data.rotation
		instance.scale = Vector3.ONE * data.scale
		objects_root.add_child(instance)
	else:
		# Legacy method: Load as Mesh (for .obj, .glb, .gltf files)
		# WARNING: These trees won't be interactive since they lack TreeStump script
		var mesh: Mesh = load(data.mesh_path)
		if not mesh:
			push_error("Chunk: Failed to load tree mesh: %s" % data.mesh_path)
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

func _update_tree_collision_for_mesh(tree_instance: Node3D, tree_mesh: Mesh) -> void:
	"""Update tree collision shapes to match the provided mesh."""
	var collision_shape: CollisionShape3D = tree_instance.get_node_or_null("CollisionShape")
	var interactable_collision: CollisionShape3D = tree_instance.get_node_or_null("Interactable/CollisionShape3D")
	
	if not collision_shape or not interactable_collision:
		return
	
	# Create accurate collision shape from the tree mesh
	var accurate_shape: Shape3D = null
	
	# Try convex shape first (good balance of accuracy and performance for trees)
	var convex_shape: ConvexPolygonShape3D = tree_mesh.create_convex_shape()
	if convex_shape:
		accurate_shape = convex_shape
	else:
		# Fallback to trimesh for maximum accuracy
		var trimesh_shape: ConcavePolygonShape3D = tree_mesh.create_trimesh_shape()
		if trimesh_shape:
			accurate_shape = trimesh_shape
		else:
			# Keep existing cylinder collision as last resort
			return
	
	# Apply the accurate collision shape to both collision areas
	if accurate_shape:
		collision_shape.shape = accurate_shape
		interactable_collision.shape = accurate_shape
		
		# Scale collision shape to match the 2.5x visual scaling
		collision_shape.scale = Vector3(2.5, 2.5, 2.5)
		interactable_collision.scale = Vector3(2.5, 2.5, 2.5)
		
		# Position collision shapes properly (trees are usually centered at base)
		collision_shape.position = Vector3.ZERO
		interactable_collision.position = Vector3.ZERO

func _create_rock(data: Dictionary) -> void:
	# Validate mesh_path first
	if not data.has("mesh_path") or data.mesh_path == null or data.mesh_path.is_empty():
		push_error("Chunk: Invalid mesh_path for rock: %s" % data)
		return
	
	# Check if the file actually exists
	if not ResourceLoader.exists(data.mesh_path):
		push_warning("Chunk: Rock mesh file not found: %s" % data.mesh_path)
		return
	
	# Rocks are simple meshes
	var mesh: Mesh = load(data.mesh_path)
	if not mesh:
		push_error("Chunk: Failed to load rock mesh: %s" % data.mesh_path)
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


func _build_chunk_borders() -> void:
	"""Creates a visual border around the chunk for debugging purposes."""
	# Create a simple line mesh for the borders
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	
	# Define border height offset (slightly above terrain)
	var height_offset := 0.5
	
	# Get average terrain height for border placement
	var avg_height := 0.0
	if terrain_data.vertices.size() > 0:
		for vertex in terrain_data.vertices:
			avg_height += vertex.y
		avg_height /= terrain_data.vertices.size()
	avg_height += height_offset
	
	# Define chunk corners
	var corner_positions := [
		Vector3(0, avg_height, 0),                                      # Top-left
		Vector3(CHUNK_SIZE.x, avg_height, 0),                          # Top-right
		Vector3(CHUNK_SIZE.x, avg_height, CHUNK_SIZE.y),              # Bottom-right
		Vector3(0, avg_height, CHUNK_SIZE.y)                          # Bottom-left
	]
	
	# Create line segments for the border (only the outer square)
	# Top edge
	vertices.append(corner_positions[0])
	vertices.append(corner_positions[1])
	# Right edge
	vertices.append(corner_positions[1])
	vertices.append(corner_positions[2])
	# Bottom edge
	vertices.append(corner_positions[2])
	vertices.append(corner_positions[3])
	# Left edge
	vertices.append(corner_positions[3])
	vertices.append(corner_positions[0])
	
	# Set colors for all vertices (faint white/gray)
	var border_color := Color(0.8, 0.8, 0.8, 0.3)  # Faint white with transparency
	for i in range(vertices.size()):
		colors.append(border_color)
	
	# Create the mesh
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	
	# Create mesh instance
	border_mesh_instance = MeshInstance3D.new()
	border_mesh_instance.mesh = mesh
	border_mesh_instance.name = "ChunkBorder"
	
	# Create an unshaded material for the borders
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.grow_amount = 0.001  # Slight grow to prevent z-fighting
	
	border_mesh_instance.material_override = material
	add_child(border_mesh_instance) 
