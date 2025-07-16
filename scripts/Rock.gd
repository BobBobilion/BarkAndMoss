class_name Rock
extends StaticBody3D

# --- Constants ---
const COLLISION_LAYER_ENVIRONMENT: int = 2  # Environment objects layer

# --- Properties ---
@export var rock_type: String = "default"
@export var hardness: float = 1.0  # How hard the rock is (affects mining/breaking)


func _ready() -> void:
	"""Initialize the rock with proper collision settings."""
	# Set collision layers - rocks are environment objects
	collision_layer = COLLISION_LAYER_ENVIRONMENT
	collision_mask = 0  # Rocks don't need to detect anything
	
	# Ensure the rock can cast shadows
	var mesh_instance: MeshInstance3D = get_node("MeshInstance3D")
	if mesh_instance:
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	print("Rock: Initialized rock of type: ", rock_type)


func get_rock_type() -> String:
	"""Returns the type of rock for identification purposes."""
	return rock_type


func get_hardness() -> float:
	"""Returns the hardness value of the rock."""
	return hardness


func set_rock_model(model_scene: PackedScene) -> void:
	"""Sets the visual model for this rock instance."""
	var mesh_instance: MeshInstance3D = get_node("MeshInstance3D")
	if mesh_instance and model_scene:
		# Clear existing mesh
		mesh_instance.mesh = null
		
		# Instantiate the model and add it as a child
		var model_instance: Node3D = model_scene.instantiate()
		mesh_instance.add_child(model_instance)
		
		# Adjust collision shape if needed based on the model
		_adjust_collision_for_model(model_instance)


func _adjust_collision_for_model(model_instance: Node3D) -> void:
	"""Adjusts the collision shape to better match the rock model (legacy method)."""
	var collision_shape: CollisionShape3D = get_node("CollisionShape3D")
	if not collision_shape:
		return
	
	# Note: This method is for backward compatibility with manually placed rocks
	# Auto-generated rocks now use accurate mesh-based collision
	if model_instance.has_method("get_aabb"):
		var aabb: AABB = model_instance.get_aabb()
		if aabb.size.length() > 0:
			var box_shape: BoxShape3D = collision_shape.shape as BoxShape3D
			if box_shape:
				box_shape.size = aabb.size * 0.9  # Slightly smaller than visual for better feel
				collision_shape.position = aabb.get_center()


func get_collision_type() -> String:
	"""Returns the type of collision shape being used."""
	var collision_shape: CollisionShape3D = get_node("CollisionShape3D")
	if not collision_shape or not collision_shape.shape:
		return "none"
	
	if collision_shape.shape is ConcavePolygonShape3D:
		return "trimesh (accurate)"
	elif collision_shape.shape is ConvexPolygonShape3D:
		return "convex (approximate)"
	elif collision_shape.shape is BoxShape3D:
		return "box (simple)"
	else:
		return "unknown"


func destroy() -> void:
	"""Safely destroys the rock instance."""
	print("Rock: Destroying rock of type: ", rock_type)
	queue_free() 