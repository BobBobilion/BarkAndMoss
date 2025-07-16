class_name CloudManager
extends Node3D

# --- Constants ---
const CLOUD_ASSET_PATH: String = "res://assets/environment/Cloud Set.glb"
const CLOUD_HEIGHT_BASE: float = 80.0       # Base height for clouds
const CLOUD_HEIGHT_VARIATION: float = 20.0  # Random height variation range
const CLOUD_SPAWN_RADIUS: float = max(100.0, 300.0 * GameConstants.WORLD_SCALE_MULTIPLIER)  # Large radius scaled with world size, minimum 100 units
const CLOUD_COUNT: int = GameConstants.WORLD.CLOUD_COUNT  # Number of clouds scaled with world size
const CLOUD_MOVE_SPEED: float = 2.0         # Base cloud movement speed
const CLOUD_MOVE_VARIATION: float = 1.0     # Random speed variation
const CLOUD_SCALE_WIDTH: float = 100.0      # Width scaling factor (increased 10x)
const CLOUD_SCALE_HEIGHT: float = 10.0      # Height scaling factor (increased 10x, maintains 10:1 ratio)
const CLOUD_UPDATE_INTERVAL: float = 0.1    # How often to update cloud positions

# --- Properties ---
var cloud_scene: PackedScene
var cloud_meshes: Array[Mesh] = []           # Array of individual cloud meshes
var active_clouds: Array[Node3D] = []        # Currently spawned clouds
var cloud_move_direction: Vector3           # Global cloud movement direction
var update_timer: float = 0.0

# --- Cloud Data ---
var player_reference: Node3D                # Reference to player for positioning


func _ready() -> void:
	"""Initialize the cloud system."""
	print("CloudManager: Initializing cloud system...")
	
	# Set random cloud movement direction (mostly horizontal)
	var angle: float = randf() * TAU
	cloud_move_direction = Vector3(cos(angle), 0.1, sin(angle)).normalized()
	print("CloudManager: Clouds will move in direction: ", cloud_move_direction)
	
	# Load cloud assets
	_load_cloud_assets()
	
	# Find player reference (try both human and dog players)
	call_deferred("_find_player_reference")
	
	# Spawn initial clouds
	call_deferred("_spawn_initial_clouds")


func _process(delta: float) -> void:
	"""Update cloud positions and manage cloud system."""
	update_timer += delta
	
	if update_timer >= CLOUD_UPDATE_INTERVAL:
		update_timer = 0.0
		_update_cloud_positions()
		_manage_cloud_culling()


func _load_cloud_assets() -> void:
	"""Load the cloud asset and extract individual cloud meshes."""
	if not ResourceLoader.exists(CLOUD_ASSET_PATH):
		printerr("CloudManager: Cloud asset not found at: ", CLOUD_ASSET_PATH)
		return
	
	cloud_scene = load(CLOUD_ASSET_PATH)
	if not cloud_scene:
		printerr("CloudManager: Failed to load cloud scene")
		return
	
	# Instantiate the cloud scene to examine its structure
	var cloud_instance: Node3D = cloud_scene.instantiate()
	_extract_cloud_meshes(cloud_instance)
	cloud_instance.queue_free()
	
	print("CloudManager: Extracted ", cloud_meshes.size(), " cloud meshes from asset")


func _extract_cloud_meshes(node: Node3D) -> void:
	"""Recursively extract all mesh instances from the cloud scene."""
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance.mesh:
			cloud_meshes.append(mesh_instance.mesh)
			print("CloudManager: Found cloud mesh: ", node.name)
	
	# Recursively check child nodes
	for child in node.get_children():
		if child is Node3D:
			_extract_cloud_meshes(child as Node3D)


func _find_player_reference() -> void:
	"""Find a player node to use as reference for cloud positioning."""
	var human_players: Array[Node] = get_tree().get_nodes_in_group("human_player")
	var dog_players: Array[Node] = get_tree().get_nodes_in_group("dog_player")
	
	if not human_players.is_empty():
		player_reference = human_players[0] as Node3D
		print("CloudManager: Using human player as reference")
	elif not dog_players.is_empty():
		player_reference = dog_players[0] as Node3D
		print("CloudManager: Using dog player as reference")
	else:
		print("CloudManager: No player found, using world origin as reference")


func _spawn_initial_clouds() -> void:
	"""Spawn the initial set of clouds around the player."""
	if cloud_meshes.is_empty():
		print("CloudManager: No cloud meshes available for spawning")
		return
	
	for i in range(CLOUD_COUNT):
		_spawn_single_cloud()
	
	print("CloudManager: Spawned ", active_clouds.size(), " clouds")


func _spawn_single_cloud() -> Node3D:
	"""Spawn a single cloud with random properties."""
	# Choose random cloud mesh
	var cloud_mesh: Mesh = cloud_meshes[randi() % cloud_meshes.size()]
	
	# Create cloud instance
	var cloud_instance: MeshInstance3D = MeshInstance3D.new()
	cloud_instance.mesh = cloud_mesh
	cloud_instance.name = "Cloud_" + str(active_clouds.size())
	
	# Set cloud material properties (no collision, just visual)
	var cloud_material: StandardMaterial3D = StandardMaterial3D.new()
	cloud_material.albedo_color = Color(1.0, 1.0, 1.0, 0.8)  # Slightly transparent white
	cloud_material.roughness = 1.0
	cloud_material.metallic = 0.0
	cloud_material.flags_unshaded = false
	cloud_material.flags_receive_shadows = false
	cloud_material.flags_cast_shadow = false
	cloud_material.flags_do_not_receive_shadows = true
	cloud_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_instance.material_override = cloud_material
	
	# Set position relative to player (or world origin)
	var spawn_position: Vector3 = _get_random_cloud_position()
	cloud_instance.global_position = spawn_position
	
	# Set scale (10:1 width to height ratio)
	var base_scale: float = randf_range(0.8, 1.5)  # Random size variation
	cloud_instance.scale = Vector3(
		CLOUD_SCALE_WIDTH * base_scale,
		CLOUD_SCALE_HEIGHT * base_scale, 
		CLOUD_SCALE_WIDTH * base_scale
	)
	
	# Set random rotation (yaw only)
	cloud_instance.rotation.y = randf() * TAU
	
	# Store individual cloud movement data
	var random_speed: float = CLOUD_MOVE_SPEED + randf_range(-CLOUD_MOVE_VARIATION, CLOUD_MOVE_VARIATION)
	var random_direction: Vector3 = cloud_move_direction + Vector3(
		randf_range(-0.2, 0.2),
		randf_range(-0.05, 0.05),
		randf_range(-0.2, 0.2)
	).normalized()
	
	cloud_instance.set_meta("move_speed", random_speed)
	cloud_instance.set_meta("move_direction", random_direction)
	
	# Add to scene and tracking
	add_child(cloud_instance)
	active_clouds.append(cloud_instance)
	
	print("CloudManager: Spawned cloud at ", spawn_position, " (Total: ", active_clouds.size(), "/", CLOUD_COUNT, ")")
	
	return cloud_instance


func _get_random_cloud_position() -> Vector3:
	"""Get a random position for cloud spawning around the player reference."""
	var center_position: Vector3 = Vector3.ZERO
	if player_reference:
		center_position = player_reference.global_position
	
	# Random position in a large circle around the player
	var angle: float = randf() * TAU
	var distance: float = randf_range(CLOUD_SPAWN_RADIUS * 0.5, CLOUD_SPAWN_RADIUS)
	
	var x: float = center_position.x + cos(angle) * distance
	var z: float = center_position.z + sin(angle) * distance
	var y: float = CLOUD_HEIGHT_BASE + randf_range(-CLOUD_HEIGHT_VARIATION, CLOUD_HEIGHT_VARIATION)
	
	return Vector3(x, y, z)


func _update_cloud_positions() -> void:
	"""Update positions of all active clouds."""
	for cloud in active_clouds:
		if not is_instance_valid(cloud):
			continue
			
		var move_speed: float = cloud.get_meta("move_speed", CLOUD_MOVE_SPEED)
		var move_direction: Vector3 = cloud.get_meta("move_direction", cloud_move_direction)
		
		# Move cloud
		cloud.global_position += move_direction * move_speed * CLOUD_UPDATE_INTERVAL


func _manage_cloud_culling() -> void:
	"""Remove clouds that are too far from player and spawn new ones."""
	if not player_reference:
		return
	
	var player_pos: Vector3 = player_reference.global_position
	var cull_distance: float = CLOUD_SPAWN_RADIUS * 1.2  # Slightly smaller culling distance for more responsive culling
	var clouds_removed: int = 0
	
	# Check each cloud for culling
	for i in range(active_clouds.size() - 1, -1, -1):
		var cloud: Node3D = active_clouds[i]
		
		if not is_instance_valid(cloud):
			active_clouds.remove_at(i)
			continue
		
		var distance_to_player: float = cloud.global_position.distance_to(player_pos)
		
		if distance_to_player > cull_distance:
			# Remove this cloud
			cloud.queue_free()
			active_clouds.remove_at(i)
			clouds_removed += 1
			print("CloudManager: Culled cloud at distance ", distance_to_player)
	
	# Spawn replacement clouds to maintain target count
	for i in range(clouds_removed):
		_spawn_single_cloud()
		
	# Also ensure we always have the target number of clouds
	while active_clouds.size() < CLOUD_COUNT:
		_spawn_single_cloud()


func get_cloud_count() -> int:
	"""Get the current number of active clouds."""
	return active_clouds.size()


func set_cloud_direction(new_direction: Vector3) -> void:
	"""Change the global cloud movement direction."""
	cloud_move_direction = new_direction.normalized()
	print("CloudManager: Updated cloud direction to: ", cloud_move_direction)


func debug_cloud_status() -> void:
	"""Print debug information about current cloud status."""
	if not player_reference:
		print("CloudManager: No player reference found")
		return
		
	var player_pos: Vector3 = player_reference.global_position
	print("CloudManager Debug Status:")
	print("  Target cloud count: ", CLOUD_COUNT)
	print("  Active clouds: ", active_clouds.size())
	print("  Spawn radius: ", CLOUD_SPAWN_RADIUS)
	print("  Player position: ", player_pos)
	
	for i in range(active_clouds.size()):
		var cloud: Node3D = active_clouds[i]
		if is_instance_valid(cloud):
			var distance: float = cloud.global_position.distance_to(player_pos)
			print("    Cloud ", i, ": distance=", distance, " pos=", cloud.global_position) 
