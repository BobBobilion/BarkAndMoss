class_name ChunkLoader
extends Node

# --- Properties ---
var chunk_manager: ChunkManager = null  # Set by ChunkManager

# Terrain material (will be loaded once and reused)
var terrain_material: Material = null

# Resource paths
const TREE_SCENE_PATH: String = "res://scenes/Tree.tscn"
const GRASS_SCENE_PATH: String = "res://scenes/Grass.tscn"

# --- Engine Callbacks ---
func _ready() -> void:
	"""Initialize the chunk loader."""
	_load_terrain_material()
	print("ChunkLoader: Initialized")

# --- Public Methods ---
func instantiate_chunk_objects(chunk: Chunk) -> void:
	"""Instantiate all objects for a chunk based on its LOD level."""
	if not chunk.object_data:
		return
	
	# Get the chunk pool for object reuse
	var pool := chunk_manager.chunk_pool if chunk_manager else null
	
	match chunk.current_lod:
		Chunk.LODLevel.HIGH:
			_instantiate_trees(chunk, pool)
			_instantiate_rocks(chunk, pool)
			_instantiate_grass(chunk, pool)
		Chunk.LODLevel.MEDIUM:
			_instantiate_trees(chunk, pool)
			_instantiate_rocks(chunk, pool)
		Chunk.LODLevel.LOW:
			# Terrain only
			pass

func apply_terrain_material(chunk: Chunk) -> void:
	"""Apply the terrain material to a chunk's terrain mesh."""
	if chunk.terrain_instance and terrain_material:
		chunk.terrain_instance.material_override = terrain_material

# --- Private Methods ---
func _load_terrain_material() -> void:
	"""Load the terrain blend shader material."""
	# Create a shader material using our custom terrain blending shader
	var shader_material := ShaderMaterial.new()
	var terrain_shader := load("res://shaders/terrain_blend.gdshader")
	
	if not terrain_shader:
		push_error("ChunkLoader: Failed to load terrain blend shader!")
		terrain_material = _create_fallback_terrain_material()
		return
	
	shader_material.shader = terrain_shader
	
	# Load textures for each biome
	var default_texture := _create_default_texture(Color(0.5, 0.5, 0.5))
	var default_normal := _create_default_normal_texture()
	
	# Forest biome textures
	var forest_albedo := load("res://assets/textures/grass terrain/textures/rocky_terrain_02_diff_4k.jpg")
	
	# Autumn biome textures
	var autumn_albedo := load("res://assets/textures/leaves terrain/textures/leaves_forest_ground_diff_4k.jpg")
	
	# Snow biome textures
	var snow_albedo := load("res://assets/textures/snow terrain/Snow002_4K_Color.jpg")
	var snow_normal := load("res://assets/textures/snow terrain/Snow002_4K_NormalGL.jpg")
	var snow_roughness := load("res://assets/textures/snow terrain/Snow002_4K_Roughness.jpg")
	
	# Mountain biome textures
	var mountain_albedo := load("res://assets/textures/rock terrain/textures/rocks_ground_05_diff_4k.jpg")
	var mountain_roughness := load("res://assets/textures/rock terrain/textures/rocks_ground_05_rough_4k.jpg")
	
	# Set shader parameters
	shader_material.set_shader_parameter("forest_albedo", forest_albedo if forest_albedo else default_texture)
	shader_material.set_shader_parameter("forest_normal", default_normal)
	shader_material.set_shader_parameter("forest_roughness", default_texture)
	
	shader_material.set_shader_parameter("autumn_albedo", autumn_albedo if autumn_albedo else default_texture)
	shader_material.set_shader_parameter("autumn_normal", default_normal)
	shader_material.set_shader_parameter("autumn_roughness", default_texture)
	
	shader_material.set_shader_parameter("snow_albedo", snow_albedo if snow_albedo else default_texture)
	shader_material.set_shader_parameter("snow_normal", snow_normal if snow_normal else default_normal)
	shader_material.set_shader_parameter("snow_roughness", snow_roughness if snow_roughness else default_texture)
	
	shader_material.set_shader_parameter("mountain_albedo", mountain_albedo if mountain_albedo else default_texture)
	shader_material.set_shader_parameter("mountain_normal", default_normal)
	shader_material.set_shader_parameter("mountain_roughness", mountain_roughness if mountain_roughness else default_texture)
	
	# Set other parameters
	shader_material.set_shader_parameter("texture_scale", 10.0)
	shader_material.set_shader_parameter("autumn_texture_scale", 10.0)
	shader_material.set_shader_parameter("blend_sharpness", 2.0)
	shader_material.set_shader_parameter("roughness_multiplier", 1.0)
	shader_material.set_shader_parameter("normal_strength", 0.5)
	
	terrain_material = shader_material

func _create_default_texture(color: Color) -> ImageTexture:
	"""Create a simple default texture with the given color."""
	var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
	image.fill(color)
	return ImageTexture.create_from_image(image)

func _create_default_normal_texture() -> ImageTexture:
	"""Create a default normal map texture."""
	var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
	image.fill(Color(0.5, 0.5, 1.0))  # Neutral normal map color
	return ImageTexture.create_from_image(image)

func _create_fallback_terrain_material() -> StandardMaterial3D:
	"""Create a basic fallback material if shader loading fails."""
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.7, 0.4)
	material.roughness = 0.7
	material.metallic = 0.0
	material.vertex_color_use_as_albedo = false
	return material

func _instantiate_trees(chunk: Chunk, pool: ChunkPool) -> void:
	"""Instantiate tree objects for a chunk."""
	if not chunk.object_data.trees:
		return
	
	# Create container if needed
	if not chunk.objects_container:
		chunk.objects_container = Node3D.new()
		chunk.objects_container.name = "Objects"
		chunk.add_child(chunk.objects_container)
	
	# Load tree scene once
	var tree_scene := load(TREE_SCENE_PATH)
	if not tree_scene:
		return
	
	# Instantiate each tree
	for tree_data in chunk.object_data.trees:
		var tree_instance: Node3D = null
		
		# Try to get from pool if available
		if pool:
			tree_instance = pool.get_tree_instance()
		
		# Create new if not pooled
		if not tree_instance:
			tree_instance = tree_scene.instantiate()
		
		# Configure tree
		_configure_tree_instance(tree_instance, tree_data, pool)
		
		# Position and add to chunk
		tree_instance.position = tree_data["position"]
		tree_instance.rotation.y = tree_data["rotation"]
		tree_instance.visible = true
		
		chunk.objects_container.add_child(tree_instance)

func _configure_tree_instance(tree: Node3D, tree_data: Dictionary, pool: ChunkPool) -> void:
	"""Configure a tree instance with appropriate mesh and collision."""
	# Get mesh path and load it
	var mesh_path: String = tree_data.get("mesh_path", "")
	if mesh_path.is_empty():
		return
	
	# Get mesh from pool or load it
	var mesh: Mesh = null
	if pool:
		mesh = pool.get_mesh(mesh_path)
	else:
		mesh = load(mesh_path) as Mesh
	
	if not mesh:
		return
	
	# Update visual mesh
	var visuals_node := tree.get_node("Visuals")
	if visuals_node:
		# Clear existing meshes
		for child in visuals_node.get_children():
			child.queue_free()
		
		# Create new mesh instance
		var mesh_instance: MeshInstance3D = null
		if pool:
			mesh_instance = pool.get_mesh_instance()
		else:
			mesh_instance = MeshInstance3D.new()
		
		mesh_instance.mesh = mesh
		mesh_instance.scale = Vector3.ONE * tree_data.get("scale", 2.5)
		visuals_node.add_child(mesh_instance)
	
	# Update collision based on mesh
	_update_tree_collision(tree, mesh, tree_data)

func _update_tree_collision(tree: Node3D, mesh: Mesh, tree_data: Dictionary) -> void:
	"""Update tree collision shape based on its mesh."""
	var collision_shape := tree.get_node("CollisionShape") as CollisionShape3D
	var interactable_collision := tree.get_node("Interactable/CollisionShape3D") as CollisionShape3D
	
	if not collision_shape or not interactable_collision:
		return
	
	# Try to create accurate collision from mesh
	var shape: Shape3D = null
	
	# Try convex shape first
	var convex_shape := mesh.create_convex_shape()
	if convex_shape:
		shape = convex_shape
	else:
		# Fallback to trimesh
		var trimesh_shape := mesh.create_trimesh_shape()
		if trimesh_shape:
			shape = trimesh_shape
	
	if shape:
		collision_shape.shape = shape
		interactable_collision.shape = shape
		
		# Scale collision to match visual scale
		var scale_factor: float = tree_data.get("scale", 2.5)
		collision_shape.scale = Vector3.ONE * scale_factor
		interactable_collision.scale = Vector3.ONE * scale_factor

func _instantiate_rocks(chunk: Chunk, pool: ChunkPool) -> void:
	"""Instantiate rock objects for a chunk."""
	if not chunk.object_data.rocks:
		return
	
	# Create container if needed
	if not chunk.objects_container:
		chunk.objects_container = Node3D.new()
		chunk.objects_container.name = "Objects"
		chunk.add_child(chunk.objects_container)
	
	# Instantiate each rock
	for rock_data in chunk.object_data.rocks:
		var rock_instance: StaticBody3D = null
		
		# Try to get from pool if available
		if pool:
			rock_instance = pool.get_rock_instance()
		else:
			rock_instance = StaticBody3D.new()
			rock_instance.collision_layer = 2
			rock_instance.collision_mask = 0
		
		# Configure rock
		_configure_rock_instance(rock_instance, rock_data, pool)
		
		# Position and add to chunk
		rock_instance.position = rock_data["position"]
		rock_instance.rotation.y = rock_data["rotation"]
		rock_instance.scale = Vector3.ONE * rock_data.get("scale", 1.0)
		rock_instance.visible = true
		
		chunk.objects_container.add_child(rock_instance)

func _configure_rock_instance(rock: StaticBody3D, rock_data: Dictionary, pool: ChunkPool) -> void:
	"""Configure a rock instance with mesh and collision."""
	# Get mesh path and load it
	var mesh_path: String = rock_data.get("mesh_path", "")
	if mesh_path.is_empty():
		return
	
	# Get mesh from pool or load it
	var mesh: Mesh = null
	if pool:
		mesh = pool.get_mesh(mesh_path)
	else:
		mesh = load(mesh_path) as Mesh
	
	if not mesh:
		return
	
	# Create mesh instance
	var mesh_instance: MeshInstance3D = null
	if pool:
		mesh_instance = pool.get_mesh_instance()
	else:
		mesh_instance = MeshInstance3D.new()
	
	mesh_instance.mesh = mesh
	rock.add_child(mesh_instance)
	
	# Create collision shape
	var collision_shape := CollisionShape3D.new()
	
	# Try to create accurate collision
	var shape: Shape3D = mesh.create_trimesh_shape()
	if not shape:
		shape = mesh.create_convex_shape()
	if not shape:
		# Fallback to box
		var box_shape := BoxShape3D.new()
		box_shape.size = mesh.get_aabb().size
		shape = box_shape
	
	collision_shape.shape = shape
	rock.add_child(collision_shape)

func _instantiate_grass(chunk: Chunk, pool: ChunkPool) -> void:
	"""Instantiate grass objects for a chunk."""
	if not chunk.object_data.grass or chunk.current_lod != Chunk.LODLevel.HIGH:
		return
	
	# Create container if needed
	if not chunk.grass_container:
		chunk.grass_container = Node3D.new()
		chunk.grass_container.name = "Grass"
		chunk.add_child(chunk.grass_container)
	
	# Load grass scene once
	var grass_scene := load(GRASS_SCENE_PATH)
	if not grass_scene:
		return
	
	# Instantiate each grass clump
	for grass_data in chunk.object_data.grass:
		var grass_instance: Node3D = null
		
		# Try to get from pool if available
		if pool:
			grass_instance = pool.get_grass_instance()
		
		# Create new if not pooled
		if not grass_instance:
			grass_instance = grass_scene.instantiate()
		
		# Configure grass
		if grass_instance.has_method("set_grass_density"):
			grass_instance.set_grass_density(grass_data.get("density", 1.0))
		
		# Position and add to chunk
		grass_instance.position = grass_data["position"]
		grass_instance.rotation.y = grass_data["rotation"]
		grass_instance.scale = Vector3.ONE * grass_data.get("scale", 1.0)
		grass_instance.visible = true
		
		chunk.grass_container.add_child(grass_instance) 