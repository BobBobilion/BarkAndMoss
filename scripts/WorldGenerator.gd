class_name WorldGenerator
extends Node3D

# --- Imports ---
const BiomeManagerClass = preload("res://scripts/BiomeManager.gd")

# --- Signals ---
signal terrain_generation_complete
signal world_generation_progress(step_name: String, progress: float)  # Progress from 0.0 to 1.0
signal world_generation_step_complete(step_name: String)

# --- Constants ---
const TREE_SCENE_PATH: String = "res://scenes/Tree.tscn"
const ROCK_SCENE_PATH: String = "res://scenes/Rock.tscn"  # We'll create this scene for rocks
const GRASS_SCENE_PATH: String = "res://scenes/Grass.tscn"  # Grass clumps for forest biome

# Terrain generation constants - Using centralized scaling system
const TERRAIN_CHUNKS: int = 4        # Divide terrain into chunks for better performance

# --- Properties ---
# Dynamic values that depend on current world scale (set in _ready)
var terrain_resolution: int
var tree_count: int
var rock_count: int
var world_size: Vector2
var tree_spacing: float

# Static exported properties for inspector (these get overridden at runtime)
@export var grass_count: int = 2000  # Number of grass clumps to spawn
@export var generate_grass: bool = true # Master switch for grass generation
@export var grass_spacing: float = 1.0  # Minimum distance between grass clumps

var tree_scene: PackedScene
var rock_scene: PackedScene
var grass_scene: PackedScene
var terrain_mesh: MeshInstance3D
var terrain_collision: StaticBody3D
var biome_manager: BiomeManagerClass

# Cache for terrain height lookup
var terrain_vertices: PackedFloat32Array
var terrain_size: Vector2

# Asset caches organized by biome type
var tree_models_cache: Dictionary = {}  # BiomeType -> Array[Mesh]
var rock_models_cache: Dictionary = {}  # BiomeType -> Array[Mesh]


# --- Engine Callbacks ---

func _ready() -> void:
	"""Initializes the world generator and loads resources. Call start_generation() to begin."""
	# Add to group for easy finding by other scripts
	add_to_group("world_generator")
	
	# Initialize dynamic values from current GameConstants
	terrain_resolution = GameConstants.WORLD.TERRAIN_RESOLUTION
	tree_count = GameConstants.WORLD.TREE_COUNT
	rock_count = GameConstants.WORLD.ROCK_COUNT
	world_size = GameConstants.WORLD.WORLD_SIZE
	tree_spacing = GameConstants.WORLD.TREE_SPACING
	
	_initialize_biome_manager()
	_load_resources()
	
	print("WorldGenerator: Ready and waiting for start_generation() call")
	print("WorldGenerator: Using terrain resolution: ", terrain_resolution)
	print("WorldGenerator: World size: ", world_size)
	print("WorldGenerator: Tree count: ", tree_count)


func start_generation() -> void:
	"""Start the world generation process. Called externally (e.g., from LoadingScreen)."""
	print("WorldGenerator: start_generation() called")
	# Use call_deferred to ensure terrain generation happens after scene is fully ready
	call_deferred("_generate_world")


# --- Private Methods ---

func _initialize_biome_manager() -> void:
	"""Initialize the biome manager for terrain and asset generation."""
	biome_manager = BiomeManagerClass.new()


func _load_resources() -> void:
	"""Loads necessary scenes and resources for biome-based generation."""
	# Load the base tree, rock, and grass scenes
	tree_scene = load(TREE_SCENE_PATH)
	# Note: We'll create the rock scene later if it doesn't exist
	if ResourceLoader.exists(ROCK_SCENE_PATH):
		rock_scene = load(ROCK_SCENE_PATH)
	# Load grass scene for forest biome enhancement
	if ResourceLoader.exists(GRASS_SCENE_PATH):
		grass_scene = load(GRASS_SCENE_PATH)
	
	# Preload tree and rock models for each biome type
	_load_biome_assets()


func _load_biome_assets() -> void:
	"""Load and cache all tree and rock meshes for each biome type."""
	# Load tree assets for each biome
	for biome_type in BiomeManagerClass.BiomeType.values():
		var tree_assets: Array[String] = biome_manager.get_tree_assets_for_biome(biome_type)
		var rock_assets: Array[String] = biome_manager.get_rock_assets_for_biome(biome_type)
		
		# Load tree meshes for this biome
		tree_models_cache[biome_type] = []
		for asset_path in tree_assets:
			if ResourceLoader.exists(asset_path):
				var mesh: Mesh = load(asset_path)
				if mesh:
					tree_models_cache[biome_type].append(mesh)
		
		# Load rock meshes for this biome  
		rock_models_cache[biome_type] = []
		for asset_path in rock_assets:
			if ResourceLoader.exists(asset_path):
				var mesh: Mesh = load(asset_path)
				if mesh:
					rock_models_cache[biome_type].append(mesh)
		



func _generate_world() -> void:
	"""Generates the complete world in the correct order."""
	print("WorldGenerator: Starting world generation...")
	
	# Step 1: Generate terrain (30% of total work)
	world_generation_progress.emit("Generating terrain...", 0.0)
	await _generate_terrain()
	world_generation_step_complete.emit("terrain")
	world_generation_progress.emit("Terrain complete", 0.3)
	
	# Step 2: Generate forest (40% of total work)
	world_generation_progress.emit("Placing trees...", 0.3)
	_generate_forest()
	world_generation_step_complete.emit("forest")
	world_generation_progress.emit("Trees placed", 0.7)
	
	# Step 3: Generate rocks (20% of total work)
	world_generation_progress.emit("Placing rocks...", 0.7)
	_generate_rocks()
	world_generation_step_complete.emit("rocks")
	world_generation_progress.emit("Rocks placed", 0.9)
	
	# Step 4: Generate grass (10% of total work)
	if generate_grass:
		world_generation_progress.emit("Growing grass...", 0.9)
		_generate_grass()
		world_generation_step_complete.emit("grass")
	
	# Final completion
	world_generation_progress.emit("World ready!", 1.0)
	terrain_generation_complete.emit()
	print("WorldGenerator: World generation complete!")


func _generate_terrain() -> void:
	"""Creates biome-based terrain using procedural mesh generation with noise."""
	# Create the terrain mesh
	terrain_mesh = MeshInstance3D.new()
	terrain_mesh.name = "TerrainMesh"
	
	# Generate the heightmap and mesh using biome data
	var mesh: ArrayMesh = _create_biome_terrain_mesh()
	terrain_mesh.mesh = mesh
	
	# Create a material that uses vertex colors for biome variation
	var terrain_material: StandardMaterial3D = _create_biome_aware_terrain_material()
	terrain_mesh.material_override = terrain_material
	
	# Ensure the mesh can cast shadows properly (shadow reception is automatic)
	terrain_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	add_child(terrain_mesh)
	
	# Create collision for the terrain and wait for it to be ready
	await _create_terrain_collision()


func _create_biome_terrain_mesh() -> ArrayMesh:
	"""Creates the actual mesh for the terrain using biome-based height generation."""
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()  # Add vertex colors for biome variation
	var indices: PackedInt32Array = PackedInt32Array()
	
	# Store terrain data for height lookups
	terrain_size = world_size
	terrain_vertices = PackedFloat32Array()
	
	# Generate vertices with height from biome manager
	for z in range(terrain_resolution + 1):
		for x in range(terrain_resolution + 1):
			# Convert grid coordinates to world coordinates
			var world_x: float = (float(x) / terrain_resolution - 0.5) * world_size.x
			var world_z: float = (float(z) / terrain_resolution - 0.5) * world_size.y
			
			# Use biome manager for height calculation
			var height: float = biome_manager.get_terrain_height_at_position(Vector3(world_x, 0, world_z))
			
			# Store vertex
			var vertex: Vector3 = Vector3(world_x, height, world_z)
			vertices.append(vertex)
			
			# Store height for later lookup
			terrain_vertices.append(height)
			
			# Calculate UV coordinates
			var uv: Vector2 = Vector2(float(x) / terrain_resolution, float(z) / terrain_resolution)
			uvs.append(uv)
			
			# Get biome-specific color for this vertex
			var biome_type: BiomeManagerClass.BiomeType = biome_manager.get_biome_at_position(Vector3(world_x, 0, world_z))
			var biome_color: Color = _get_biome_grass_color(biome_type)
			colors.append(biome_color)
	
	# Generate indices for triangles
	for z in range(terrain_resolution):
		for x in range(terrain_resolution):
			var top_left: int = z * (terrain_resolution + 1) + x
			var top_right: int = top_left + 1
			var bottom_left: int = (z + 1) * (terrain_resolution + 1) + x
			var bottom_right: int = bottom_left + 1
			
			# First triangle (top-left, top-right, bottom-left) - counter-clockwise when viewed from above
			indices.append(top_left)
			indices.append(top_right)
			indices.append(bottom_left)
			
			# Second triangle (top-right, bottom-right, bottom-left) - counter-clockwise when viewed from above
			indices.append(top_right)
			indices.append(bottom_right)
			indices.append(bottom_left)
	
	# Calculate normals
	normals = _calculate_normals(vertices, indices)
	
	# Create mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors  # Add vertex colors for biome variation
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	return mesh


func _calculate_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	"""Calculate smooth normals for the terrain mesh."""
	var normals: PackedVector3Array = PackedVector3Array()
	normals.resize(vertices.size())
	
	# Initialize all normals to zero
	for i in range(normals.size()):
		normals[i] = Vector3.ZERO
	
	# Calculate face normals and accumulate
	for i in range(0, indices.size(), 3):
		var i0: int = indices[i]
		var i1: int = indices[i + 1]
		var i2: int = indices[i + 2]
		
		var v0: Vector3 = vertices[i0]
		var v1: Vector3 = vertices[i1]
		var v2: Vector3 = vertices[i2]
		
		var face_normal: Vector3 = (v1 - v0).cross(v2 - v0).normalized()
		
		normals[i0] += face_normal
		normals[i1] += face_normal
		normals[i2] += face_normal
	
	# Normalize all accumulated normals
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()
	
	return normals


func _create_terrain_collision() -> void:
	"""Creates collision shape for the terrain."""

	
	terrain_collision = StaticBody3D.new()
	terrain_collision.name = "TerrainCollision"
	
	# Set collision layers - terrain should be on layer 1 (default)
	terrain_collision.collision_layer = 1  # Terrain is on layer 1
	terrain_collision.collision_mask = 0   # Terrain doesn't need to detect anything
	
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.name = "TerrainCollisionShape"
	
	# Use the mesh as collision shape
	if terrain_mesh and terrain_mesh.mesh:
		var shape: ConcavePolygonShape3D = terrain_mesh.mesh.create_trimesh_shape()
		if shape:
			collision_shape.shape = shape
		
		else:
			printerr("WorldGenerator: Failed to create terrain collision shape!")
			return
	else:
		printerr("WorldGenerator: No terrain mesh available for collision!")
		return
	
	terrain_collision.add_child(collision_shape)
	add_child(terrain_collision)

	
	# Wait a frame to ensure collision is fully registered
	await get_tree().process_frame


func _generate_forest() -> void:
	"""
	Generates biome-specific forests by placing tree instances based on biome type and density.
	This should only run on the server to ensure consistency.
	"""
	if not multiplayer.is_server():
		return

	var trees_spawned: int = 0
	var max_attempts: int = tree_count * 3  # Allow multiple attempts to find valid positions
	var attempts: int = 0

	while trees_spawned < tree_count and attempts < max_attempts:
		attempts += 1
		
		# Get a random position and determine its biome
		var world_pos: Vector3 = _get_random_world_position()
		var biome_type: BiomeManagerClass.BiomeType = biome_manager.get_biome_at_position(world_pos)
		
		# Check if we should spawn a tree in this biome (based on density)
		var tree_density: float = biome_manager.get_tree_density_for_biome(biome_type)
		if randf() > tree_density:
			continue
		
		# Get biome-appropriate tree mesh
		var tree_mesh: Mesh = _get_random_tree_mesh_for_biome(biome_type)
		if not tree_mesh:
			continue
		
		# Create tree instance
		var tree_instance: Node3D = tree_scene.instantiate()
		
		# Add the tree mesh to the visuals node
		var visuals_node: Node3D = tree_instance.get_node("Visuals")
		if visuals_node:
			# Clear existing placeholder meshes
			for child in visuals_node.get_children():
				child.queue_free()
			# Create and add mesh instance with the biome-appropriate mesh
			var mesh_instance: MeshInstance3D = MeshInstance3D.new()
			mesh_instance.mesh = tree_mesh
			mesh_instance.scale = Vector3(2.5, 2.5, 2.5)  # Increased tree size by 2.5x
			visuals_node.add_child(mesh_instance)
		
		# Create accurate collision based on the actual tree mesh
		_create_accurate_tree_collision(tree_instance, tree_mesh, biome_type)
		
		var surface_position: Vector3 = _get_surface_position(world_pos)
		var rotation_y: float = randf() * TAU
		
		# Use call_deferred to ensure nodes are added safely
		call_deferred("_add_tree_to_scene", tree_instance, surface_position, rotation_y)
		trees_spawned += 1




func _generate_rocks() -> void:
	"""
	Generates biome-specific rocks based on biome type and rock density.
	"""
	if not multiplayer.is_server():
		return

	var rocks_spawned: int = 0
	var max_attempts: int = rock_count * 3
	var attempts: int = 0

	while rocks_spawned < rock_count and attempts < max_attempts:
		attempts += 1
		
		# Get a random position and determine its biome
		var world_pos: Vector3 = _get_random_world_position()
		var biome_type: BiomeManagerClass.BiomeType = biome_manager.get_biome_at_position(world_pos)
		
		# Check if we should spawn a rock in this biome (based on density)
		var rock_density: float = biome_manager.get_rock_density_for_biome(biome_type)
		if randf() > rock_density:
			continue
		
		# Get biome-appropriate rock mesh
		var rock_mesh: Mesh = _get_random_rock_mesh_for_biome(biome_type)
		if not rock_mesh:
			continue
		
		# Create rock instance with accurate collision
		var static_body: StaticBody3D = StaticBody3D.new()
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		var collision_shape: CollisionShape3D = CollisionShape3D.new()
		
		# Set up the mesh
		mesh_instance.mesh = rock_mesh
		
		# Create accurate collision shape from the actual mesh geometry
		var trimesh_shape: ConcavePolygonShape3D = rock_mesh.create_trimesh_shape()
		if trimesh_shape:
			collision_shape.shape = trimesh_shape

		else:
			# Fallback to convex shape if trimesh fails
			var convex_shape: ConvexPolygonShape3D = rock_mesh.create_convex_shape()
			if convex_shape:
				collision_shape.shape = convex_shape
			else:
				# Last resort: use AABB-based box shape
				var box_shape: BoxShape3D = BoxShape3D.new()
				box_shape.size = rock_mesh.get_aabb().size
				collision_shape.shape = box_shape

		
		# Set collision properties for environment objects
		static_body.collision_layer = 2  # Environment layer
		static_body.collision_mask = 0   # Rocks don't need to detect anything
		
		# Assemble the rock
		static_body.add_child(mesh_instance)
		static_body.add_child(collision_shape)
		
		var surface_position: Vector3 = _get_surface_position(world_pos)
		var rotation_y: float = randf() * TAU
		var scale_factor: float = randf_range(1.0, 15.0)  # Random scale from current size (1x) to 15x larger
		
		static_body.scale = Vector3(scale_factor, scale_factor, scale_factor)
		
		# Use call_deferred to ensure nodes are added safely
		call_deferred("_add_rock_to_scene", static_body, surface_position, rotation_y)
		rocks_spawned += 1




func _generate_grass() -> void:
	"""
	Generates grass clumps specifically for forest biomes to enhance visual richness.
	Grass provides ground-level detail and movement in forested areas.
	"""
	if not multiplayer.is_server():
		return
	
	if not grass_scene:

		return

	var grass_spawned: int = 0
	var max_attempts: int = grass_count * 4  # More attempts since grass is more selective
	var attempts: int = 0

	while grass_spawned < grass_count and attempts < max_attempts:
		attempts += 1
		
		# Get a random position and determine its biome
		var world_pos: Vector3 = _get_random_world_position()
		var biome_type: BiomeManagerClass.BiomeType = biome_manager.get_biome_at_position(world_pos)
		
		# Only spawn grass in forest and autumn biomes for now
		if biome_type != BiomeManagerClass.BiomeType.FOREST and biome_type != BiomeManagerClass.BiomeType.AUTUMN:
			continue
		
		# Check grass density for the biome (higher density in forest areas)
		var grass_spawn_chance: float = 0.8 if biome_type == BiomeManagerClass.BiomeType.FOREST else 0.4
		if randf() > grass_spawn_chance:
			continue
		
		# Create grass instance
		var grass_instance: Node3D = grass_scene.instantiate()
		
		# Configure the grass for the specific biome
		if grass_instance.has_method("set_biome_type"):
			grass_instance.set_biome_type(biome_type)
		
		# Add some variation to wind intensity based on terrain
		var wind_variation: float = randf_range(0.7, 1.3)
		if grass_instance.has_method("set_wind_intensity"):
			grass_instance.set_wind_intensity(wind_variation)
		
		# Adjust grass density based on proximity to trees (less grass near trees)
		var density_factor: float = _calculate_grass_density_factor(world_pos)
		if "grass_density" in grass_instance:
			grass_instance.grass_density = density_factor
		
		# Position the grass on the terrain surface
		var surface_position: Vector3 = _get_surface_position(world_pos)
		
		# Add some random rotation for natural variation
		var rotation_y: float = randf() * TAU
		
		# Use call_deferred to ensure nodes are added safely
		call_deferred("_add_grass_to_scene", grass_instance, surface_position, rotation_y)
		grass_spawned += 1




func _calculate_grass_density_factor(pos: Vector3) -> float:
	"""Calculate grass density based on proximity to trees and terrain features."""
	# Check for nearby trees - reduce grass density near trees
	var nearby_objects: Array = []
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	
	# Simple distance-based calculation for now
	# In a more complex implementation, you could raycast to find nearby trees
	var terrain_height: float = biome_manager.get_terrain_height_at_position(pos)
	var slope_factor: float = abs(terrain_height - biome_manager.BASE_TERRAIN_HEIGHT) / biome_manager.MAX_MOUNTAIN_HEIGHT
	
	# More grass on flatter terrain, less on steep slopes
	var density: float = 1.0 - (slope_factor * 0.5)
	
	# Add some random variation
	density *= randf_range(0.6, 1.0)
	
	return clamp(density, 0.2, 1.0)


func _add_grass_to_scene(grass: Node3D, pos: Vector3, rot_y: float) -> void:
	"""Adds a grass clump instance to the scene with a given position and rotation."""
	grass.position = pos
	grass.rotation.y = rot_y
	add_child(grass)


func _add_tree_to_scene(tree: Node3D, pos: Vector3, rot_y: float) -> void:
	"""Adds a tree instance to the scene with a given position and rotation."""
	tree.position = pos
	tree.rotation.y = rot_y
	add_child(tree)


func _add_rock_to_scene(rock: Node3D, pos: Vector3, rot_y: float) -> void:
	"""Adds a rock instance to the scene with a given position and rotation."""
	rock.position = pos
	rock.rotation.y = rot_y
	add_child(rock)


func _get_random_tree_mesh_for_biome(biome_type: BiomeManagerClass.BiomeType) -> Mesh:
	"""Returns a random tree mesh appropriate for the given biome."""
	if not tree_models_cache.has(biome_type):
		return null
	
	var meshes: Array = tree_models_cache[biome_type]
	if meshes.is_empty():
		return null
	
	var random_index: int = randi() % meshes.size()
	return meshes[random_index]


func _get_random_rock_mesh_for_biome(biome_type: BiomeManagerClass.BiomeType) -> Mesh:
	"""Returns a random rock mesh appropriate for the given biome."""
	if not rock_models_cache.has(biome_type):
		return null
	
	var meshes: Array = rock_models_cache[biome_type]
	if meshes.is_empty():
		return null
	
	var random_index: int = randi() % meshes.size()
	return meshes[random_index]


func _create_accurate_tree_collision(tree_instance: Node3D, tree_mesh: Mesh, biome_type: BiomeManagerClass.BiomeType) -> void:
	"""
	Creates accurate collision shapes based on the actual tree mesh geometry.
	"""
	var collision_shape: CollisionShape3D = tree_instance.get_node("CollisionShape")
	var interactable_collision: CollisionShape3D = tree_instance.get_node("Interactable/CollisionShape3D")
	
	if not collision_shape or not interactable_collision:
		
		return
	
	# Create accurate collision shape from the actual tree mesh
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

			_adjust_collision_for_biome_tree_fallback(tree_instance, biome_type)
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


func _adjust_collision_for_biome_tree_fallback(tree_instance: Node3D, biome_type: BiomeManagerClass.BiomeType) -> void:
	"""
	Fallback collision adjustment using simple cylinder shapes (legacy method).
	"""
	var collision_shape: CollisionShape3D = tree_instance.get_node("CollisionShape")
	var interactable_collision: CollisionShape3D = tree_instance.get_node("Interactable/CollisionShape3D")
	
	if not collision_shape or not interactable_collision:
		return
	
	# Get the cylinder shape from both collision areas
	var main_shape: CylinderShape3D = collision_shape.shape as CylinderShape3D
	var interact_shape: CylinderShape3D = interactable_collision.shape as CylinderShape3D
	
	if not main_shape or not interact_shape:
		return
	
	# Adjust collision based on biome type (scaled for 2.5x tree size)
	match biome_type:
		BiomeManagerClass.BiomeType.MOUNTAIN:
			# Dead trees are typically taller and thinner
			main_shape.height = 20.0  # 8.0 * 2.5
			main_shape.radius = 2.0   # 0.8 * 2.5
			interact_shape.height = 20.0
			interact_shape.radius = 2.0
			collision_shape.position.y = 10.0  # 4.0 * 2.5
			interactable_collision.position.y = 10.0
		BiomeManagerClass.BiomeType.FOREST:
			# Forest trees are typically medium height and thickness
			main_shape.height = 15.0  # 6.0 * 2.5
			main_shape.radius = 2.5   # 1.0 * 2.5
			interact_shape.height = 15.0
			interact_shape.radius = 2.5
			collision_shape.position.y = 7.5  # 3.0 * 2.5
			interactable_collision.position.y = 7.5
		BiomeManagerClass.BiomeType.AUTUMN:
			# Autumn trees are similar to forest trees
			main_shape.height = 13.75  # 5.5 * 2.5
			main_shape.radius = 2.25   # 0.9 * 2.5
			interact_shape.height = 13.75
			interact_shape.radius = 2.25
			collision_shape.position.y = 6.875  # 2.75 * 2.5
			interactable_collision.position.y = 6.875
		BiomeManagerClass.BiomeType.SNOW:
			# Snow trees might be a bit shorter due to snow weight
			main_shape.height = 12.5  # 5.0 * 2.5
			main_shape.radius = 2.0   # 0.8 * 2.5
			interact_shape.height = 12.5
			interact_shape.radius = 2.0
			collision_shape.position.y = 6.25  # 2.5 * 2.5
			interactable_collision.position.y = 6.25


func _get_random_world_position() -> Vector3:
	"""Returns a random position within the world bounds."""
	var x: float = randf_range(-world_size.x / 2, world_size.x / 2)
	var z: float = randf_range(-world_size.y / 2, world_size.y / 2)
	return Vector3(x, 0, z)


func _get_surface_position(world_pos: Vector3) -> Vector3:
	"""Returns the surface position at a given world coordinate using raycast."""
	# Cast ray downward from high above to find terrain surface
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var max_height: float = biome_manager.MAX_MOUNTAIN_HEIGHT + biome_manager.BASE_TERRAIN_HEIGHT + 100.0  # Account for dramatically increased terrain heights
	var from: Vector3 = Vector3(world_pos.x, max_height, world_pos.z)
	var to: Vector3 = Vector3(world_pos.x, -50.0, world_pos.z)
	
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result: Dictionary = space_state.intersect_ray(query)
	if result:
		return result.position
	else:
		# Fallback to biome manager height calculation
		var height: float = biome_manager.get_terrain_height_at_position(world_pos)
		return Vector3(world_pos.x, height, world_pos.z)


func get_terrain_height_at_position(world_pos: Vector3) -> float:
	"""
	Returns the terrain height at a given world position using the biome manager.
	Useful for other objects that need to snap to terrain.
	"""
	if not biome_manager:

		return 0.0
	
	return biome_manager.get_terrain_height_at_position(world_pos)


func _get_biome_grass_color(biome_type: BiomeManagerClass.BiomeType) -> Color:
	"""Get the grass color for a specific biome type."""
	match biome_type:
		BiomeManagerClass.BiomeType.MOUNTAIN:
			return Color(0.55, 0.55, 0.55)  # More prominent grey rocky color - ENHANCED for better gray appearance
		BiomeManagerClass.BiomeType.FOREST:
			return Color(0.3, 0.7, 0.2)  # Rich green
		BiomeManagerClass.BiomeType.AUTUMN:
			return Color(0.8, 0.6, 0.2)  # Golden autumn color
		BiomeManagerClass.BiomeType.SNOW:
			return Color(0.95, 0.95, 0.95)  # Pure white snow color - CHANGED from blue-tinted to clean white
		_:
			return Color(0.5, 0.5, 0.5)  # Default grey


func _create_biome_aware_terrain_material() -> StandardMaterial3D:
	"""Create a material that uses vertex colors to show biome variation."""
	var material: StandardMaterial3D = StandardMaterial3D.new()
	
	# Enable vertex color usage
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = false
	
	# Set base material properties
	material.roughness = 0.6
	material.metallic = 0.0
	
	# Enable proper lighting (shadow properties set on mesh instance)
	material.flags_unshaded = false
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	
	return material 
