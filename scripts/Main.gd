class_name Main
extends Node3D

# --- Signals ---
signal terrain_ready()

# --- Properties ---
@onready var game_manager: GameManager = $GameManager as GameManager
@onready var animal_spawner: Node = $AnimalSpawner
@onready var environment_node: Node3D = $Environment
@onready var day_night_cycle: Node3D = $DayNightCycle
@onready var cloud_manager: Node3D = $CloudManager

var player_tracker: PlayerTracker
var player_spawner: PlayerSpawner
var multiplayer_spawner: MultiplayerSpawner

# Fallback terrain system
var terrain_generated: bool = false

# --- Engine Callbacks ---
func _ready() -> void:
	# Keep the game running on the server even if the window loses focus.
	# In Godot 4, we set the process mode to always process
	set_process_mode(Node.PROCESS_MODE_ALWAYS)
	

	# --- Setup Multiplayer Spawner ---
	# This node is responsible for replicating instances across the network.
	multiplayer_spawner = MultiplayerSpawner.new()
	multiplayer_spawner.name = "MultiplayerSpawner"
	multiplayer_spawner.process_mode = Node.PROCESS_MODE_ALWAYS  # Continue during pause
	# The root path determines where spawned objects are added as children.
	multiplayer_spawner.set_spawn_path(".") # Spawn players as children of Main
	
	# Configure spawnable scenes
	multiplayer_spawner.add_spawnable_scene("res://scenes/Player.tscn")
	multiplayer_spawner.add_spawnable_scene("res://scenes/Dog.tscn")
	
	# Add animal scenes for multiplayer spawning
	multiplayer_spawner.add_spawnable_scene("res://scenes/Rabbit.tscn")
	multiplayer_spawner.add_spawnable_scene("res://scenes/Deer.tscn")
	multiplayer_spawner.add_spawnable_scene("res://scenes/Bird.tscn")
	
	# Set spawn limit (-1 = unlimited)
	multiplayer_spawner.spawn_limit = -1

	# DISABLED: PlayerSpawner conflicts with GameManager's spawning system
	# Set the spawn function. The host calls this, and the spawner replicates it.
	# We bind our custom PlayerSpawner node to its spawn function.
	# var player_spawner_script = preload("res://scripts/PlayerSpawner.gd")
	# player_spawner = player_spawner_script.new()
	# player_spawner.name = "PlayerSpawner"
	# add_child(player_spawner)

	# multiplayer_spawner.spawn_function = Callable(player_spawner, "_spawn_player")
	add_child(multiplayer_spawner)

	# --- Setup Player Tracker ---
	# The PlayerTracker is already available as an autoload singleton
	player_tracker = PlayerTracker
	
	# Initialize the main scene with chunk system
	print("Main: Initializing world with chunk-based system")
	
	# Ensure random number generator is properly seeded
	randomize()
	
	# Add to group for easy finding by other scripts
	add_to_group("main")
	
	# Initialize game manager with this as the world node
	if game_manager:
		print("Main: GameManager found, initializing world...")
		
		# CRITICAL: Clients must wait for world state before initializing
		if not multiplayer.is_server() and multiplayer.has_multiplayer_peer():
			# Client - wait for world state from WorldStateManager
			print("Main: Client waiting for world state from host...")
			var world_state_manager = get_node("/root/WorldStateManager")
			var world_state = world_state_manager.world_state
			
			# Check if we already have the world state (joining mid-game)
			if world_state.world_seed != 0:
				print("Main: Client using received world seed: ", world_state.world_seed)
				game_manager.initialize_world(self, world_state.world_seed)
				call_deferred("_setup_and_start")
			else:
				# World state not yet received - this shouldn't happen as NetworkManager
				# should wait for world state before loading this scene
				print("Main: ERROR - Client loaded scene before receiving world state!")
				# Use fallback but log error
				game_manager.initialize_world(self, 12345)
				call_deferred("_setup_and_start")
		else:
			# Host or single player - generate new seed
			var world_seed: int = randi()
			print("Main: Host/Single player generated world seed: ", world_seed)
			
			# Initialize world state manager if host
			if multiplayer.is_server() and multiplayer.has_multiplayer_peer():
				var world_state_manager = get_node("/root/WorldStateManager")
				# Only initialize if not already done by NetworkManager
				if world_state_manager.world_state.world_seed == 0:
					world_state_manager.initialize_world_state(world_seed)
			
			game_manager.initialize_world(self, world_seed)
			
			# Start immediate chunk loading and game setup
			print("Main: Starting immediate setup...")
			call_deferred("_setup_and_start")
	else:
		print("Main: ERROR - GameManager not found!")
	
	# Ensure DayNightCycle starts properly - this is critical for sun/moon visibility
	if day_night_cycle:
		print("Main: Day/Night cycle found, ensuring it starts properly...")
		call_deferred("_ensure_day_night_cycle_working")
	else:
		print("Main: ERROR - DayNightCycle not found!")
	
	print("Main: Initialization complete")


func _setup_and_start() -> void:
	"""Setup with chunk system and fallback terrain generation."""
	print("Main: Setup starting...")
	
	# Give chunk system time to initialize properly
	await get_tree().create_timer(1.0).timeout
	
	# Try chunk-based terrain first
	var chunks_working = false
	if game_manager and game_manager.chunk_manager:
		var chunk_manager = game_manager.chunk_manager
		
		print("Main: Pre-loading chunks around spawn area...")
		
		# Add a temporary player at spawn location to trigger chunk loading
		var temp_player_id = 999999
		var temp_player_pos = Vector3(100, 50, 100)
		if chunk_manager.player_tracker:
			chunk_manager.player_tracker.update_player_position(temp_player_id, temp_player_pos)
		
		# Wait for chunks to generate
		await get_tree().create_timer(2.0).timeout
		
		# Check if chunks were created
		if chunk_manager.active_chunks.size() > 0:
			print("Main: Chunk system working - ", chunk_manager.active_chunks.size(), " chunks active")
			chunks_working = true
			terrain_generated = true
		else:
			print("Main: Chunk system failed - no chunks generated")
		
		# Clean up temporary player
		if chunk_manager.player_tracker:
			chunk_manager.player_tracker.remove_player(temp_player_id)
	
	# If chunk system failed, create fallback terrain
	if not chunks_working:
		print("Main: Creating fallback terrain due to chunk system failure...")
		_create_fallback_terrain()
	
	# Position campfire on terrain
	await _position_campfire_on_terrain()
	
	# Emit signal that terrain is ready
	print("Main: Terrain generation complete, emitting terrain_ready signal")
	terrain_ready.emit()
	
	# Start the game (this will spawn players)
	if game_manager:
		print("Main: Calling GameManager.start_game() after terrain is ready")
		game_manager.start_game()
	
	# Enable animal spawning after terrain is ready
	if animal_spawner and animal_spawner.has_method("set_spawning_enabled"):
		print("Main: Enabling animal spawner...")
		animal_spawner.set_spawning_enabled(true)
	else:
		print("Main: Warning - AnimalSpawner not found or missing set_spawning_enabled method")
	
	print("Main: Setup complete!") 


func _create_fallback_terrain() -> void:
	"""Create a fallback terrain when the chunk system fails."""
	print("Main: Creating fallback terrain...")
	
	# Create terrain mesh instance
	var terrain_mesh = MeshInstance3D.new()
	terrain_mesh.name = "FallbackTerrain"
	
	# Generate a simple heightmap terrain
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	
	# Generate terrain with simple height variation
	var resolution = 65  # 64x64 grid
	var size = 200.0     # 200x200 world units
	
	for z in range(resolution):
		for x in range(resolution):
			var world_x = (float(x) / (resolution - 1) - 0.5) * size
			var world_z = (float(z) / (resolution - 1) - 0.5) * size
			
			# Simple height calculation with rolling hills
			var height = 50.0 + sin(world_x * 0.03) * 15.0 + cos(world_z * 0.02) * 10.0
			
			vertices.append(Vector3(world_x, height, world_z))
			uvs.append(Vector2(float(x) / (resolution - 1), float(z) / (resolution - 1)))
	
	# Generate triangle indices
	for z in range(resolution - 1):
		for x in range(resolution - 1):
			var i = z * resolution + x
			
			# First triangle
			indices.append(i)
			indices.append(i + 1)
			indices.append(i + resolution)
			
			# Second triangle
			indices.append(i + 1)
			indices.append(i + resolution + 1)
			indices.append(i + resolution)
	
	# Calculate normals (simple upward normals for now)
	normals.resize(vertices.size())
	for i in range(normals.size()):
		normals[i] = Vector3.UP
	
	# Create mesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	terrain_mesh.mesh = array_mesh
	
	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.7, 0.3)  # Green grass color
	terrain_mesh.material_override = material
	
	add_child(terrain_mesh)
	
	# Create collision
	var collision_body = StaticBody3D.new()
	collision_body.name = "FallbackTerrainCollision"
	
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = array_mesh.create_trimesh_shape()
	collision_body.add_child(collision_shape)
	
	add_child(collision_body)
	
	terrain_generated = true
	print("Main: Fallback terrain created successfully")


func _position_campfire_on_terrain() -> void:
	"""Position the campfire on the terrain surface."""
	var campfire = environment_node.get_node_or_null("Campfire")
	if not campfire:
		print("Main: No campfire found")
		return
	
	print("Main: Positioning campfire on terrain...")
	
	# Wait for terrain to be ready
	await get_tree().create_timer(0.5).timeout
	
	# Get terrain height
	var campfire_pos = Vector3(100, 0, 100)
	var terrain_height = 50.0  # Default
	
	# Try to get height from chunk manager first
	if game_manager and game_manager.chunk_manager:
		terrain_height = game_manager.chunk_manager.get_height_at_position(campfire_pos)
	
	# Validate height and use raycast if needed
	if terrain_height < 0 or terrain_height > 500:
		var space_state = get_world_3d().direct_space_state
		if space_state:
			var from = Vector3(100, 1000, 100)
			var to = Vector3(100, -100, 100)
			var query = PhysicsRayQueryParameters3D.create(from, to)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			var result = space_state.intersect_ray(query)
			
			if result:
				terrain_height = result.position.y
			else:
				terrain_height = 50.0  # Safe fallback
	
	# Position campfire
	campfire.global_position = Vector3(100, terrain_height + 1.0, 100)
	print("Main: Campfire positioned at: ", campfire.global_position)


func _ensure_day_night_cycle_working() -> void:
	"""Ensure the day/night cycle is working properly - this addresses the sun/moon issue."""
	# Wait for the DayNightCycle to initialize
	await get_tree().create_timer(2.0).timeout
	
	if day_night_cycle and day_night_cycle.has_method("_ready"):
		# Check if sun and moon were created
		var sun_light = day_night_cycle.get_node_or_null("SunLight")
		var moon_light = day_night_cycle.get_node_or_null("MoonLight")
		var sun_sphere = day_night_cycle.get_node_or_null("SunSphere")
		var moon_sphere = day_night_cycle.get_node_or_null("MoonSphere")
		
		print("Main: Day/Night Cycle Status:")
		print("  - SunLight: ", "Found" if sun_light else "Missing")
		print("  - MoonLight: ", "Found" if moon_light else "Missing")
		print("  - SunSphere: ", "Found" if sun_sphere else "Missing")
		print("  - MoonSphere: ", "Found" if moon_sphere else "Missing")
		
		if sun_light:
			print("  - Sun visible: ", sun_light.visible, " Energy: ", sun_light.light_energy)
		if moon_light:
			print("  - Moon visible: ", moon_light.visible, " Energy: ", moon_light.light_energy)
			
		# Force set time to midday to ensure sun is visible
		if day_night_cycle.has_method("set_time_of_day"):
			day_night_cycle.set_time_of_day(0.5)  # Midday - sun should be bright and visible
			print("Main: Set day/night cycle to midday (0.5) to ensure sun visibility") 
