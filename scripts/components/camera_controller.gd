class_name CameraController
extends Node

# --- Export Variables for Tuning ---
@export_range(0.0, 0.01, 0.001) var mouse_sensitivity: float = 0.002
@export_range(0.0, 3.14, 0.1) var tilt_limit: float = deg_to_rad(75.0)  # Convert to radians
@export_range(1.0, 10.0, 0.5) var spring_arm_length: float = 2.4
@export_range(0.0, 1.0, 0.1) var camera_collision_bias: float = 0.2
@export_range(30.0, 120.0, 5.0) var normal_fov: float = 90.0
@export_range(1.0, 10.0, 0.5) var zoom_speed: float = 5.0
@export_range(20.0, 60.0, 5.0) var bow_zoom_fov: float = 45.0
@export var collision_layers: int = 1  # Which layers SpringArm3D should collide with
@export_range(0.1, 1.0, 0.05) var collision_sphere_radius: float = 0.2

# --- Camera Polish Settings ---
@export var enable_camera_smoothing: bool = true
@export_range(1.0, 20.0, 0.5) var camera_smoothing_speed: float = 10.0
@export var enable_auto_recenter: bool = false
@export_range(1.0, 10.0, 0.5) var auto_recenter_delay: float = 3.0
@export_range(1.0, 10.0, 0.5) var auto_recenter_speed: float = 2.0
@export var invert_vertical_input: bool = false

# --- Legacy Constants (for compatibility with Dog/other scenes) ---
const MOUSE_SENSITIVITY: float = 0.002
const CAMERA_PITCH_MIN: float = -1.5
const CAMERA_PITCH_MAX: float = 1.5
const CAMERA_COLLISION_BIAS: float = 0.2
const NORMAL_FOV: float = 90.0
const ZOOM_SPEED: float = 5.0
const BOW_ZOOM_FOV: float = 45.0

# --- Properties ---
var camera: Camera3D
var player_body: CharacterBody3D
var horizontal_pivot: Node3D
var vertical_pivot: Node3D

var mouse_delta: Vector2 = Vector2.ZERO
var camera_pitch: float = 0.0
var base_camera_position: Vector3
var default_fov: float

# Smoothing and auto-recenter properties
var target_horizontal_rotation: float = 0.0
var target_vertical_rotation: float = 0.0
var idle_timer: float = 0.0
var is_input_active: bool = false

func setup(p_camera: Camera3D, p_player_body: CharacterBody3D, p_horizontal_pivot: Node3D = null, p_vertical_pivot: Node3D = null):
	self.camera = p_camera
	self.player_body = p_player_body
	self.horizontal_pivot = p_horizontal_pivot
	self.vertical_pivot = p_vertical_pivot
	
	if camera:
		base_camera_position = camera.position
		default_fov = camera.fov
		
		# Set initial FOV from export variable
		camera.fov = normal_fov
	else:
		push_error("CameraController: Camera3D node not assigned.")
	if not player_body:
		push_error("CameraController: Player CharacterBody3D node not assigned.")
	
	# Configure SpringArm3D if using new camera system
	if vertical_pivot:
		var spring_arm: SpringArm3D = vertical_pivot.get_node_or_null("SpringArm3D")
		if spring_arm:
			spring_arm.spring_length = spring_arm_length
			spring_arm.collision_mask = collision_layers
			
			# Configure collision shape if it exists
			if spring_arm.shape:
				if spring_arm.shape is SphereShape3D:
					(spring_arm.shape as SphereShape3D).radius = collision_sphere_radius
			
			print("✓ SpringArm3D configured: length=", spring_arm_length, ", collision_mask=", collision_layers)
	
	# Initialize target rotations for smoothing
	if horizontal_pivot and vertical_pivot:
		target_horizontal_rotation = horizontal_pivot.rotation.y
		target_vertical_rotation = vertical_pivot.rotation.x

func process_camera(delta: float) -> void:
	if mouse_delta != Vector2.ZERO:
		_handle_camera_rotation(mouse_delta)
		mouse_delta = Vector2.ZERO
	
	# Handle camera smoothing for new pivot system
	if horizontal_pivot and vertical_pivot and enable_camera_smoothing:
		_update_smooth_camera(delta)
	
	# Handle auto-recentering
	if enable_auto_recenter:
		_update_auto_recenter(delta)
	
	if camera:
		# Only use manual collision/positioning when not using SpringArm3D
		if not horizontal_pivot or not vertical_pivot:
			_handle_camera_collision()
			_update_camera_position()
		# SpringArm3D handles collision automatically when using new pivot system

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var relative_motion: Vector2 = event.relative
		
		# Apply vertical inversion if enabled
		if invert_vertical_input:
			relative_motion.y = -relative_motion.y
		
		mouse_delta += relative_motion
		is_input_active = true
		idle_timer = 0.0

func _handle_camera_rotation(relative_mouse_motion: Vector2) -> void:
	if not player_body:
		return

	# Use new pivot system if available, otherwise fall back to old method
	if horizontal_pivot and vertical_pivot:
		# ALWAYS rotate player body for movement direction
		player_body.rotate_y(-relative_mouse_motion.x * mouse_sensitivity)
		
		# Update camera pitch
		if enable_camera_smoothing:
			# Update target rotations for smooth camera movement
			target_vertical_rotation += -relative_mouse_motion.y * mouse_sensitivity
			target_vertical_rotation = clamp(target_vertical_rotation, -tilt_limit, tilt_limit)
		else:
			# Direct rotation (immediate)
			camera_pitch += -relative_mouse_motion.y * mouse_sensitivity
			camera_pitch = clamp(camera_pitch, -tilt_limit, tilt_limit)
			
			# Apply pitch to vertical pivot
			vertical_pivot.rotation.x = camera_pitch
	else:
		# Fallback to old method for compatibility (Dog scene, etc.)
		player_body.rotate_y(-relative_mouse_motion.x * MOUSE_SENSITIVITY)
		
		camera_pitch += -relative_mouse_motion.y * MOUSE_SENSITIVITY
		camera_pitch = clamp(camera_pitch, CAMERA_PITCH_MIN, CAMERA_PITCH_MAX)
		
		if camera:
			camera.rotation.x = camera_pitch

func _handle_camera_collision() -> void:
	if not camera or not player_body:
		return
		
	var space_state: PhysicsDirectSpaceState3D = player_body.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player_body.global_position, camera.global_position)
	query.exclude = [player_body]
	
	var result: Dictionary = space_state.intersect_ray(query)
	if result:
		var collision_point: Vector3 = result.position
		var direction_to_cam: Vector3 = player_body.global_position.direction_to(camera.global_position)
		var safe_distance: float = player_body.global_position.distance_to(collision_point) - camera_collision_bias
		camera.global_position = player_body.global_position + direction_to_cam * safe_distance
	else:
		_update_camera_position()

func _update_camera_position() -> void:
	if not camera:
		return

	var pitch_factor: float = -camera_pitch / 1.5
	
	var height_offset: float = 0.0
	var distance_offset: float = 0.0
	
	if camera_pitch < 0:
		height_offset = abs(pitch_factor) * 2.0
		distance_offset = abs(pitch_factor) * 1.0
	
	var new_y: float = base_camera_position.y + height_offset
	var new_z: float = base_camera_position.z - distance_offset
	
	camera.position = Vector3(base_camera_position.x, new_y, new_z)

func set_aiming(is_aiming: bool) -> void:
	if not camera:
		return

	var target_fov: float = bow_zoom_fov if is_aiming else normal_fov
	var tween: Tween = create_tween()
	tween.tween_property(camera, "fov", target_fov, 1.0 / zoom_speed)

# --- Camera Polish Methods ---

func _update_smooth_camera(delta: float) -> void:
	"""Apply smooth interpolation to camera rotations."""
	if not horizontal_pivot or not vertical_pivot:
		return
	
	# Only smooth vertical rotation (pitch) - horizontal is handled by player body
	var current_x: float = vertical_pivot.rotation.x
	var new_x: float = lerp(current_x, target_vertical_rotation, camera_smoothing_speed * delta)
	vertical_pivot.rotation.x = new_x
	camera_pitch = new_x

func _update_auto_recenter(delta: float) -> void:
	"""Handle automatic camera recentering when idle."""
	if not is_input_active:
		idle_timer += delta
		
		if idle_timer >= auto_recenter_delay:
			# Auto-recenter is now handled by rotating player body back to forward
			# This could be implemented if desired, but typically not needed for player rotation
			pass
	else:
		# Reset idle timer when input is active
		is_input_active = false

# --- Additional Helper Methods ---

func set_camera_offset(offset: Vector3) -> void:
	"""Set positional offset for the camera root (useful for special camera angles)."""
	if player_body:
		var camera_root: Node3D = player_body.get_node_or_null("CameraRootOffset")
		if camera_root:
			camera_root.position = offset

func reset_camera_offset() -> void:
	"""Reset camera root to default position."""
	set_camera_offset(Vector3(0, 1.5, 0))

func get_camera_forward() -> Vector3:
	"""Get the forward direction of the camera for gameplay purposes."""
	if camera:
		return -camera.global_transform.basis.z
	return Vector3.FORWARD 