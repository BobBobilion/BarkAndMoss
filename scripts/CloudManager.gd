# scripts/CloudManager.gd

class_name CloudManager
extends Node3D

# Cloud generation constants (static values)
const CLOUD_HEIGHT_MIN: float = 200.0  # Minimum cloud height - much higher in sky
const CLOUD_HEIGHT_MAX: float = 350.0  # Maximum cloud height - much higher in sky
const CLOUD_SPEED_MIN: float = 0.05    # Minimum cloud movement speed - much slower
const CLOUD_SPEED_MAX: float = 0.15    # Maximum cloud movement speed - much slower
const CLOUD_COUNT_MIN: int = 10        # Minimum number of clouds
const CLOUD_COUNT_MAX: int = 20        # Maximum number of clouds
const CLOUD_SCALE_MIN: float = 250.0   # Minimum cloud scale multiplier (5x larger)
const CLOUD_SCALE_MAX: float = 750.0   # Maximum cloud scale multiplier (5x larger)

# Cloud model paths
const CLOUD_MODEL_PATH: String = "res://assets/environment/Cloud Set.glb"

# Runtime properties (calculated based on current world scale)
var cloud_spawn_radius: float  # Large radius scaled with world size, minimum 100 units
var cloud_count: int           # Number of clouds scaled with world size
var cloud_instances: Array[Node3D] = []
var cloud_speeds: Array[float] = []  # Movement speeds for each cloud
var cloud_model: Mesh

# Rotation center and radius for cloud movement
var world_center: Vector3 = Vector3.ZERO
var movement_radius: float  # Clouds move within 80% of spawn radius

# Player reference for culling
var player_character: CharacterBody3D


# --- Engine Callbacks ---

func _ready() -> void:
	"""Initialize the cloud manager and generate clouds."""
	print("CloudManager: Initializing cloud system...")
	add_to_group("cloud_manager")
	
	# Calculate dynamic values based on current world scale
	cloud_spawn_radius = max(100.0, 300.0 * GameConstants.get_world_scale_multiplier())
	cloud_count = randi_range(CLOUD_COUNT_MIN, CLOUD_COUNT_MAX)  # Random count between 10-20
	movement_radius = cloud_spawn_radius * 0.8  # Clouds move within 80% of spawn radius
	
	# Load cloud model
	_load_cloud_model()
	
	# Generate initial clouds
	_generate_clouds()
	
	# Find player for potential culling (optional)
	call_deferred("_find_player")
	
	print("CloudManager: Generated ", cloud_instances.size(), " large, high-altitude clouds for natural sun filtering")


func _process(delta: float) -> void:
	"""Update cloud positions for realistic movement."""
	_update_cloud_movement(delta)


# --- Cloud Generation ---

func _load_cloud_model() -> void:
	"""Load the cloud 3D model from assets."""
	if ResourceLoader.exists(CLOUD_MODEL_PATH):
		var cloud_scene = load(CLOUD_MODEL_PATH)
		# Extract mesh from the loaded scene
		if cloud_scene is PackedScene:
			var temp_instance = cloud_scene.instantiate()
			if temp_instance.has_method("get_children") and temp_instance.get_child_count() > 0:
				var mesh_instance = temp_instance.get_child(0)
				if mesh_instance is MeshInstance3D:
					cloud_model = mesh_instance.mesh
			temp_instance.queue_free()
		print("CloudManager: Loaded cloud model successfully")
	else:
		print("CloudManager: Warning - Cloud model not found at ", CLOUD_MODEL_PATH)


func _generate_clouds() -> void:
	"""Generate clouds around the world with realistic distribution."""
	var clouds_to_generate = cloud_count
	print("CloudManager: Generating ", clouds_to_generate, " clouds...")
	
	for i in range(clouds_to_generate):
		var cloud_position = _get_random_cloud_position()
		var cloud_instance = _create_cloud_instance(cloud_position)
		
		if cloud_instance:
			add_child(cloud_instance)
			cloud_instances.append(cloud_instance)
			
			# Assign random movement speed to each cloud
			var speed = randf_range(CLOUD_SPEED_MIN, CLOUD_SPEED_MAX)
			cloud_speeds.append(speed)


func _get_random_cloud_position() -> Vector3:
	"""Generate a random position for a cloud around the player/world center."""
	# Use a smaller, more focused cloud area around the player/center
	var cloud_area_radius = 200.0  # Focused area around player instead of entire world
	
	# Try to use player position if available, otherwise use world center
	var center_position = world_center
	if player_character and is_instance_valid(player_character):
		center_position = player_character.global_position
	
	# Random position in a circle around the center position
	var angle = randf() * 2.0 * PI
	var distance = randf_range(cloud_area_radius * 0.3, cloud_area_radius)  # Between 30% and 100% of radius
	
	var x = center_position.x + cos(angle) * distance
	var z = center_position.z + sin(angle) * distance
	var y = randf_range(CLOUD_HEIGHT_MIN, CLOUD_HEIGHT_MAX)  # Much higher in the sky
	
	return Vector3(x, y, z)


func _create_cloud_instance(position: Vector3) -> MeshInstance3D:
	"""Create a single cloud instance at the specified position."""
	if not cloud_model:
		return null
	
	var cloud_instance = MeshInstance3D.new()
	cloud_instance.mesh = cloud_model
	cloud_instance.position = position
	
	# Add random rotation and large scale for realistic cloud appearance
	cloud_instance.rotation.y = randf() * 2.0 * PI
	var scale_factor = randf_range(CLOUD_SCALE_MIN, CLOUD_SCALE_MAX)  # Much larger clouds (50x-150x)
	cloud_instance.scale = Vector3(scale_factor, scale_factor, scale_factor)
	
	# Set up material properties for realistic cloud appearance with sun filtering
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.4)  # More transparent for sun filtering
	material.flags_transparent = true
	material.flags_use_point_size = false
	material.no_depth_test = false
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from all angles
	cloud_instance.material_override = material
	
	return cloud_instance


# --- Cloud Movement ---

func _update_cloud_movement(delta: float) -> void:
	"""Update cloud positions for realistic drifting movement."""
	for i in range(cloud_instances.size()):
		if i >= cloud_speeds.size():
			continue
			
		var cloud = cloud_instances[i]
		var speed = cloud_speeds[i]
		
		# Move clouds in a slow orbital pattern around the world center
		var current_distance = Vector2(cloud.position.x - world_center.x, cloud.position.z - world_center.z).length()
		var angle = atan2(cloud.position.z - world_center.z, cloud.position.x - world_center.x)
		
		# Slowly rotate around center
		angle += speed * delta * 0.1  # Very slow rotation
		
		# Update position
		cloud.position.x = world_center.x + cos(angle) * current_distance
		cloud.position.z = world_center.z + sin(angle) * current_distance
		
		# Add subtle vertical bobbing
		cloud.position.y += sin(Time.get_time_dict_from_system().second * 0.01 + i) * 0.02


# --- Utility Functions ---

func _find_player() -> void:
	"""Find the player character for potential optimizations."""
	var players = get_tree().get_nodes_in_group("human_player")
	if not players.is_empty():
		for p in players:
			# Check if multiplayer peer exists before checking authority
			if multiplayer and multiplayer.multiplayer_peer and p.is_multiplayer_authority():
				player_character = p
				break


func get_cloud_count() -> int:
	"""Return the current number of active clouds."""
	return cloud_instances.size()


func regenerate_clouds() -> void:
	"""Regenerate all clouds (useful when world size changes)."""
	print("CloudManager: Regenerating clouds for new world size...")
	
	# Clear existing clouds
	for cloud in cloud_instances:
		if is_instance_valid(cloud):
			cloud.queue_free()
	
	cloud_instances.clear()
	cloud_speeds.clear()
	
	# Recalculate cloud parameters for new world size
	cloud_spawn_radius = max(100.0, 300.0 * GameConstants.get_world_scale_multiplier())
	cloud_count = randi_range(CLOUD_COUNT_MIN, CLOUD_COUNT_MAX)  # Random count between 10-20
	movement_radius = cloud_spawn_radius * 0.8
	
	# Generate new clouds with updated world size
	_generate_clouds()
	
	print("CloudManager: Cloud regeneration complete - ", cloud_instances.size(), " large, high-altitude clouds") 
