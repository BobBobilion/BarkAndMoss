class_name Player
extends CharacterBody3D


# --- Constants ---
const WALK_SPEED: float = 3.0
const RUN_SPEED: float = 6.0
const JUMP_VELOCITY: float = 4.5
const MOUSE_SENSITIVITY: float = 0.002
const CAMERA_PITCH_MIN: float = -1.5
const CAMERA_PITCH_MAX: float = 1.5
const CAMERA_COLLISION_BIAS: float = 0.2

# Bow shooting constants
const BOW_CHARGE_TIME: float = 2.0  # Time to fully charge the bow
const BOW_MIN_POWER: float = 0.3    # Minimum power when barely charged
const BOW_MAX_POWER: float = 1.0    # Maximum power when fully charged
const BOW_ZOOM_FOV: float = 45.0    # FOV when aiming with bow
const NORMAL_FOV: float = 90.0      # Normal camera FOV
const ZOOM_SPEED: float = 5.0       # Speed of zoom transition

# Animation constants
const ANIMATION_BLEND_TIME: float = 0.2  # Time to blend between animations

# Available animation names from the Adventurer model
const ANIM_IDLE: String = "CharacterArmature|Idle_Neutral"           # Default idle pose
const ANIM_WALK: String = "CharacterArmature|Walk"                   # Walking animation  
const ANIM_RUN: String = "CharacterArmature|Run"                     # Running animation
const ANIM_JUMP: String = "CharacterArmature|Roll"                   # Use roll for jump since no jump animation
const ANIM_CHOP: String = "CharacterArmature|Sword_Slash"            # Use sword slash for chopping trees
const ANIM_INTERACT: String = "CharacterArmature|Interact"           # Interaction animation
const ANIM_HIT_RECEIVE: String = "CharacterArmature|HitRecieve"      # Taking damage animation
const ANIM_HIT_RECEIVE_2: String = "CharacterArmature|HitRecieve_2"  # Alternative hit animation
const ANIM_DEATH: String = "CharacterArmature|Death"                 # Death animation
const ANIM_PUNCH_LEFT: String = "CharacterArmature|Punch_Left"       # Left punch
const ANIM_PUNCH_RIGHT: String = "CharacterArmature|Punch_Right"     # Right punch
const ANIM_KICK_LEFT: String = "CharacterArmature|Kick_Left"         # Left kick
const ANIM_KICK_RIGHT: String = "CharacterArmature|Kick_Right"       # Right kick
const ANIM_WAVE: String = "CharacterArmature|Wave"                   # Greeting/wave animation

# Movement speed thresholds for animation selection
const WALK_THRESHOLD: float = 0.1                  # Minimum speed to trigger walk
const RUN_THRESHOLD: float = 4.0                   # Speed threshold for run vs walk


# --- Properties ---
# Physics
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Movement
var current_speed: float = WALK_SPEED

# Camera
@onready var camera: Camera3D = $Camera3D
var mouse_delta: Vector2 = Vector2.ZERO
var camera_pitch: float = 0.0
var base_camera_position: Vector3
var default_fov: float = NORMAL_FOV

# Interaction
@onready var interaction_area: Area3D = $InteractionArea
@onready var interaction_debug_mesh: MeshInstance3D = $InteractionArea/InteractionDebugMesh
var overlapping_interactables: Array[Node] = []

# Animation
@onready var adventurer_model: Node3D = $AdventurerModel
@onready var hatchet_model: Node3D = $HatchetModel
@onready var bow_model: Node3D = $BowModel
var animation_player: AnimationPlayer
var current_animation: String = ""
var is_chopping: bool = false

# UI
var hud_instance: Control

# Bow mechanics
var arrow_scene: PackedScene = preload("res://scenes/Arrow.tscn")
var is_charging_bow: bool = false
var bow_charge_time: float = 0.0
var is_aiming: bool = false


func _ready() -> void:
	# Set up collision layers for proper terrain interaction
	collision_layer = 2      # Player is on layer 2
	collision_mask = 1 | 2   # Player collides with terrain (layer 1) and other players (layer 2)
	
	# This check is the key to fixing camera and input issues.
	# Also handle single-player mode (when there's no multiplayer peer)
	var is_local_player: bool = is_multiplayer_authority() or not multiplayer.has_multiplayer_peer()
	
	if is_local_player:
		# This is MY character. Enable my camera and capture my mouse.
		camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
		# Add HUD for the local player only
		call_deferred("add_hud")
		
		# Register with pause manager for pause functionality
		if PauseManager:
			PauseManager.register_player(self)
			
		# Show interaction debug mesh for local player only
		if interaction_debug_mesh:
			interaction_debug_mesh.visible = true
		
		print("Player: Set up as local player (authority or single-player)")
	else:
		# This is a networked copy of another player. Disable its camera.
		camera.enabled = false
		# Hide interaction debug mesh for remote players
		if interaction_debug_mesh:
			interaction_debug_mesh.visible = false
		
		print("Player: Set up as remote player")
	
	# Add to group for identification
	add_to_group("human_player")

	# Store the initial camera position
	base_camera_position = camera.position
	default_fov = camera.fov
	
	# Initialize animation system
	_setup_animations()
	
	# Set up interaction area for detecting interactables
	if interaction_area:
		interaction_area.area_entered.connect(_on_area_entered)
		interaction_area.area_exited.connect(_on_area_exited)
		print("Player: Interaction area signals connected")
	else:
		print("Player: ERROR - No interaction area found!")
	
	print("Player: Collision layers set up - layer: %d, mask: %d" % [collision_layer, collision_mask])
	print("Player: Camera authority:", is_multiplayer_authority())
	print("Player: Interaction area - layer: %d, mask: %d" % [interaction_area.collision_layer, interaction_area.collision_mask])


func _process(delta: float) -> void:
	# Only process input for our own player (handle single-player mode too)
	var is_local_player: bool = is_multiplayer_authority() or not multiplayer.has_multiplayer_peer()
	if not is_local_player:
		return
		
	# Handle mouse look
	if mouse_delta != Vector2.ZERO:
		_handle_camera_rotation(mouse_delta)
		mouse_delta = Vector2.ZERO
	
	# Handle camera collision
	handle_camera_collision()
	
	# Handle bow mechanics
	_handle_bow_mechanics(delta)


func _physics_process(delta: float) -> void:
	# Only process input for our own player (handle single-player mode too)
	var is_local_player: bool = is_multiplayer_authority() or not multiplayer.has_multiplayer_peer()
	if not is_local_player:
		return
	
	# Handle additional input (gestures, interactions)
	_handle_input()
	
	# Add the gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Handle run [[memory:3259606]]
	if Input.is_action_pressed("run"):
		current_speed = RUN_SPEED
	else:
		current_speed = WALK_SPEED

	# Handle movement input
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()
	
	# Update animations based on movement
	_update_movement_animation()
	
	# Handle bow mechanics (already handled in _handle_input)
	# _handle_bow_mechanics(delta)  # Commented out to avoid duplication
	
	# Handle interaction input (already handled in _handle_input)
	# if Input.is_action_just_pressed("interact"):
	#	_handle_interaction()  # Commented out to avoid duplication


func _setup_animations() -> void:
	"""Initialize the animation system by finding the AnimationPlayer in the adventurer model."""
	# Look for AnimationPlayer in the adventurer model hierarchy
	if adventurer_model:
		animation_player = _find_animation_player(adventurer_model)
		
		if animation_player:
			print("Player: Found AnimationPlayer in adventurer model")
			# Start with idle animation
			_play_animation(ANIM_IDLE)
		else:
			print("Player: No AnimationPlayer found in adventurer model")


func _find_animation_player(node: Node) -> AnimationPlayer:
	"""Recursively search for an AnimationPlayer node in the given node hierarchy."""
	if node is AnimationPlayer:
		return node as AnimationPlayer
	
	for child in node.get_children():
		var result: AnimationPlayer = _find_animation_player(child)
		if result:
			return result
	
	return null


func _update_movement_animation() -> void:
	"""Update character animations based on current state and movement."""
	if not animation_player:
		return
	
	# Skip animation updates during chopping action
	if is_chopping:
		return
	
	# Determine animation based on movement
	var horizontal_velocity: Vector2 = Vector2(velocity.x, velocity.z)
	var speed: float = horizontal_velocity.length()
	
	var target_animation: String = ""
	
	# Check if jumping (in air)
	if not is_on_floor():
		target_animation = ANIM_JUMP
	# Check movement speed
	elif speed > WALK_THRESHOLD:
		if current_speed >= RUN_SPEED:
			target_animation = ANIM_RUN
		else:
			target_animation = ANIM_WALK
	else:
		target_animation = ANIM_IDLE
	
	# Play the appropriate animation
	_play_animation(target_animation)


func _play_animation(animation_name: String) -> void:
	"""Play the specified animation with blending."""
	if not animation_player:
		return
	
	# Allow restarting the same animation if it has finished
	if animation_name == current_animation and animation_player.is_playing():
		return
	
	# Check if the animation exists
	if not animation_player.has_animation(animation_name):
		# Try common alternative names
		var alternatives: Array[String] = []
		match animation_name:
			ANIM_IDLE:
				alternatives = ["CharacterArmature|Idle_Neutral", "CharacterArmature|Idle_1", "CharacterArmature|Idle_2"]
			ANIM_WALK:
				alternatives = ["CharacterArmature|Walk", "CharacterArmature|Walking"]
			ANIM_RUN:
				alternatives = ["CharacterArmature|Run", "CharacterArmature|Running", "CharacterArmature|sprint", "CharacterArmature|Sprint"]
			ANIM_JUMP:
				alternatives = ["CharacterArmature|Roll", "CharacterArmature|Jump", "CharacterArmature|Jumping"]
			ANIM_CHOP:
				alternatives = ["CharacterArmature|Sword_Slash", "CharacterArmature|Chop", "CharacterArmature|Chopping", "CharacterArmature|axe", "CharacterArmature|Axe"]
			ANIM_INTERACT:
				alternatives = ["CharacterArmature|Interact"]
			ANIM_HIT_RECEIVE:
				alternatives = ["CharacterArmature|HitRecieve"]
			ANIM_HIT_RECEIVE_2:
				alternatives = ["CharacterArmature|HitRecieve_2"]
			ANIM_DEATH:
				alternatives = ["CharacterArmature|Death"]
			ANIM_PUNCH_LEFT:
				alternatives = ["CharacterArmature|Punch_Left"]
			ANIM_PUNCH_RIGHT:
				alternatives = ["CharacterArmature|Punch_Right"]
			ANIM_KICK_LEFT:
				alternatives = ["CharacterArmature|Kick_Left"]
			ANIM_KICK_RIGHT:
				alternatives = ["CharacterArmature|Kick_Right"]
			ANIM_WAVE:
				alternatives = ["CharacterArmature|Wave"]
		
		# Try to find an alternative
		for alt_name in alternatives:
			if animation_player.has_animation(alt_name):
				animation_name = alt_name
				break
		
		# If no animation found, default to the first available animation
		if not animation_player.has_animation(animation_name):
			var animation_list: PackedStringArray = animation_player.get_animation_list()
			if animation_list.size() > 0:
				animation_name = animation_list[0]
			else:
				return
	
	# Play the animation with blending
	animation_player.play(animation_name, ANIMATION_BLEND_TIME)
	current_animation = animation_name
	
	# Ensure movement animations loop properly
	if animation_name in [ANIM_WALK, ANIM_RUN, ANIM_IDLE]:
		var animation_resource: Animation = animation_player.get_animation(animation_name)
		if animation_resource:
			animation_resource.loop_mode = Animation.LOOP_LINEAR


func _on_area_entered(area: Area3D) -> void:
	"""Handle when an interactable area is entered."""
	print("Player: Area entered - ", area.name, " from parent: ", area.get_parent().name)
	var interactable: Node = area.get_parent()
	# Check for interaction prompt method OR if it's in interactable group
	if interactable.has_method("get_interaction_prompt") or interactable.is_in_group("interactable"):
		print("Player: Adding interactable: ", interactable.name)
		overlapping_interactables.append(interactable)
	else:
		print("Player: ", interactable.name, " is not interactable - no get_interaction_prompt method and not in interactable group")


func _on_area_exited(area: Area3D) -> void:
	"""Handle when an interactable area is exited."""
	print("Player: Area exited - ", area.name, " from parent: ", area.get_parent().name)
	var interactable: Node = area.get_parent()
	if interactable in overlapping_interactables:
		print("Player: Removing interactable: ", interactable.name)
		overlapping_interactables.erase(interactable)


func _handle_bow_mechanics(delta: float) -> void:
	"""Handle bow charging, aiming, and shooting mechanics."""
	var equipped_item: String = get_equipped_item()
	
	# Only handle bow mechanics if bow is equipped
	if equipped_item != "Bow":
		if is_aiming:
			_stop_aiming()
		return
	
	# Handle bow charging and shooting
	if Input.is_action_pressed("attack"):
		if not is_charging_bow:
			_start_bow_charge()
		_update_bow_charge(delta)
	elif Input.is_action_just_released("attack") and is_charging_bow:
		_shoot_arrow()
		_stop_bow_charge()


func _start_bow_charge() -> void:
	"""Start charging the bow and begin aiming."""
	is_charging_bow = true
	is_aiming = true
	bow_charge_time = 0.0
	
	# Start zooming in for aiming
	var tween: Tween = create_tween()
	tween.tween_property(camera, "fov", BOW_ZOOM_FOV, 1.0 / ZOOM_SPEED)
	



func _update_bow_charge(delta: float) -> void:
	"""Update the bow charge amount."""
	bow_charge_time = min(bow_charge_time + delta, BOW_CHARGE_TIME)
	
	# Optional: Add visual feedback here (charging sound, crosshair changes, etc.)
	var charge_percentage: float = bow_charge_time / BOW_CHARGE_TIME
	
	# Update HUD if available to show charge progress
	if is_instance_valid(hud_instance):
		# This could trigger a charging indicator in the HUD
		pass


func _shoot_arrow() -> void:
	"""Shoot an arrow based on current charge level."""
	var charge_percentage: float = bow_charge_time / BOW_CHARGE_TIME
	var arrow_power: float = lerp(BOW_MIN_POWER, BOW_MAX_POWER, charge_percentage)
	
	# Calculate shooting direction (camera forward direction)
	var shoot_direction: Vector3 = -camera.global_transform.basis.z
	
	# Spawn arrow at a position slightly in front of the player
	var spawn_position: Vector3 = global_position + Vector3(0, 1.5, 0) + shoot_direction * 1.0
	
	# Create the arrow
	var arrow: RigidBody3D = arrow_scene.instantiate()
	get_tree().current_scene.add_child(arrow)
	arrow.global_position = spawn_position
	arrow.set_shooter(self)
	
	# Launch the arrow with calculated power
	var arrow_speed: float = arrow.ARROW_SPEED * arrow_power
	arrow.launch(shoot_direction, arrow_speed)
	



func _stop_bow_charge() -> void:
	"""Stop charging the bow."""
	is_charging_bow = false
	bow_charge_time = 0.0


func _stop_aiming() -> void:
	"""Stop aiming and return camera to normal FOV."""
	if not is_aiming:
		return
		
	is_aiming = false
	
	# Zoom out to normal FOV
	var tween: Tween = create_tween()
	tween.tween_property(camera, "fov", default_fov, 1.0 / ZOOM_SPEED)


func add_hud() -> void:
	"""Loads and adds the HUD scene to the current scene tree and adds test items."""
	print("Player: Creating HUD...")
	var hud_scene: PackedScene = preload("res://scenes/HUD.tscn")
	hud_instance = hud_scene.instantiate()
	get_tree().current_scene.add_child.call_deferred(hud_instance)
	
	print("Player: HUD instantiated, connecting to hotbar...")
	# Connect to the hotbar's selection_changed signal
	if is_instance_valid(hud_instance) and hud_instance.has_node("Hotbar"):
		var hotbar = hud_instance.get_node("Hotbar")
		if hotbar and not hotbar.is_connected("selection_changed", on_hotbar_selection_changed):
			hotbar.connect("selection_changed", on_hotbar_selection_changed)
			print("Player: Successfully connected to hotbar signals")
		else:
			print("Player: Warning - Could not connect to hotbar or already connected")
	else:
		print("Player: Error - HUD or Hotbar node not found!")

	# Add some test items to inventory after HUD is created
	call_deferred("_add_test_items")
	
	# Set initial tool visibility after hotbar is ready
	call_deferred("_set_initial_tool_visibility")
	
	print("Player: HUD setup complete!")


func _set_initial_tool_visibility() -> void:
	"""Set the initial tool visibility based on the starting hotbar selection."""
	var equipped_item: String = get_equipped_item()
	_update_tool_visibility(equipped_item)


func on_hotbar_selection_changed(slot_index: int, item_name: String) -> void:
	"""Callback for when the hotbar selection changes."""
	print("Selected slot ", slot_index, " with item: ", item_name)
	
	# Update tool visibility based on equipped item
	_update_tool_visibility(item_name)
	
	# Stop aiming if switching away from bow
	if item_name != "Bow" and is_aiming:
		_stop_aiming()
		_stop_bow_charge()


func _update_tool_visibility(equipped_item: String) -> void:
	"""Update the visibility of tool models based on the equipped item."""
	if not hatchet_model or not bow_model:
		return
	
	# Hide all tools first
	hatchet_model.visible = false
	bow_model.visible = false
	
	# Show the appropriate tool
	match equipped_item:
		"Hatchet":
			hatchet_model.visible = true
		"Bow":
			bow_model.visible = true
		_:
			# No tool or empty slot - all tools hidden
			pass


func get_equipped_item() -> String:
	"""Returns the item currently selected in the hotbar."""
	if is_instance_valid(hud_instance) and hud_instance.has_node("Hotbar"):
		var hotbar = hud_instance.get_node("Hotbar")
		if hotbar and hotbar.has_method("get_selected_item"):
			return hotbar.get_selected_item()
	return ""


func start_chopping_animation() -> void:
	"""Start the chopping animation when player uses hatchet on trees."""
	if not animation_player:
		return
	
	is_chopping = true
	_play_animation(ANIM_CHOP)
	
	# Set up a timer to stop chopping animation after a short duration
	var chop_duration: float = 1.0  # 1 second chop animation
	var timer: Timer = Timer.new()
	add_child(timer)
	timer.wait_time = chop_duration
	timer.one_shot = true
	timer.timeout.connect(_stop_chopping_animation)
	timer.start()


func _stop_chopping_animation() -> void:
	"""Stop the chopping animation and return to normal movement animations."""
	is_chopping = false
	
	# Clean up the timer
	for child in get_children():
		if child is Timer:
			child.queue_free()
	
	# Return to appropriate movement animation
	_update_movement_animation()


func _add_test_items() -> void:
	"""Finds the inventory and adds some test items. For debugging only."""
	if not OS.is_debug_build():
		return

	if is_instance_valid(hud_instance) and hud_instance.has_node("Inventory"):
		var inventory: Node = hud_instance.get_node("Inventory")
		if inventory.has_method("add_item"):
			inventory.add_item("Wood")
			inventory.add_item("Raw Meat")
			inventory.add_item("Cooked Meat")
			inventory.add_item("Sinew")
			inventory.add_item("Bow")


func _handle_camera_rotation(relative_mouse_motion: Vector2) -> void:
	"""Handles the rotation of the player and camera based on mouse movement."""
	# Rotate the player body left/right (yaw)
	rotate_y(-relative_mouse_motion.x * MOUSE_SENSITIVITY)
	
	# Update camera pitch
	camera_pitch += -relative_mouse_motion.y * MOUSE_SENSITIVITY
	camera_pitch = clamp(camera_pitch, CAMERA_PITCH_MIN, CAMERA_PITCH_MAX)
	
	# Set camera rotation and position
	camera.rotation.x = camera_pitch
	_update_camera_position()


func handle_camera_collision() -> void:
	"""
	Handles camera collision by casting a ray from the player to the camera.
	If the ray hits something, the camera is moved closer to the player.
	"""
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position, camera.global_position)
	query.exclude = [self]
	
	var result: Dictionary = space_state.intersect_ray(query)
	if result:
		# If something is blocking the camera, move it closer
		var collision_point: Vector3 = result.position
		var direction_to_cam: Vector3 = global_position.direction_to(camera.global_position)
		var safe_distance: float = global_position.distance_to(collision_point) - CAMERA_COLLISION_BIAS
		camera.global_position = global_position + direction_to_cam * safe_distance
	else:
		# Restore dynamic camera position
		_update_camera_position()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion:
		mouse_delta += event.relative


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	# Note: Escape key (ui_cancel) is now handled by PauseManager
	# No longer handling it here to avoid conflicts 


func _setup_interaction_area() -> void:
	"""Connects signals for the interaction area."""
	if interaction_area:
		interaction_area.body_entered.connect(_on_interaction_area_body_entered)
		interaction_area.body_exited.connect(_on_interaction_area_body_exited)
		interaction_area.area_entered.connect(_on_interaction_area_area_entered)
		interaction_area.area_exited.connect(_on_interaction_area_area_exited)


func _on_interaction_area_body_entered(body: Node3D) -> void:
	if _is_interactable(body):
		overlapping_interactables.append(body)


func _on_interaction_area_body_exited(body: Node3D) -> void:
	if body in overlapping_interactables:
		overlapping_interactables.erase(body)


func _on_interaction_area_area_entered(area: Area3D) -> void:
	if _is_interactable(area):
		overlapping_interactables.append(area)


func _on_interaction_area_area_exited(area: Area3D) -> void:
	if area in overlapping_interactables:
		overlapping_interactables.erase(area)


func _is_interactable(node: Node) -> bool:
	"""
	Checks if a node is interactable by checking for the 'interacted' signal 
	or if it is in the 'interactable' group.
	"""
	return node.has_signal("interacted") or node.is_in_group("interactable")


func get_closest_interactable() -> Node:
	"""
	Finds the closest interactable node from the list of overlapping interactables.
	"""
	if overlapping_interactables.is_empty():
		return null
	
	var closest: Node = null
	var closest_distance_sq: float = INF
	
	for i in range(overlapping_interactables.size() - 1, -1, -1):
		var interactable = overlapping_interactables[i]
		if not is_instance_valid(interactable):
			overlapping_interactables.remove_at(i)
			continue
			
		var distance_sq: float = global_position.distance_squared_to(interactable.global_position)
		if distance_sq < closest_distance_sq:
			closest_distance_sq = distance_sq
			closest = interactable
	
	return closest


func _update_camera_position() -> void:
	"""
	Calculates the camera's position based on its pitch. This creates a dynamic
	over-the-shoulder effect when looking up or down.
	"""
	# Calculate dynamic camera position based on pitch
	var pitch_factor: float = -camera_pitch / 1.5  # Normalize pitch to 0-1 range
	
	# When looking down (negative pitch), move camera higher and closer
	# When looking up (positive pitch), keep camera at normal position
	var height_offset: float = 0.0
	var distance_offset: float = 0.0
	
	if camera_pitch < 0:  # Looking down
		height_offset = abs(pitch_factor) * 2.0  # Move up to 2 units higher
		distance_offset = abs(pitch_factor) * 1.0  # Move 1 unit closer
	
	# Calculate new camera position
	var new_y: float = base_camera_position.y + height_offset
	var new_z: float = base_camera_position.z - distance_offset
	
	camera.position = Vector3(base_camera_position.x, new_y, new_z)


func _handle_interaction() -> void:
	"""Handle player interaction with objects in the world."""
	print("Player: Interaction attempted. Overlapping interactables: ", overlapping_interactables.size())
	for interactable in overlapping_interactables:
		print("  - ", interactable.name, " (", interactable.get_class(), ")")
	
	# Check if there are any overlapping interactables
	if overlapping_interactables.size() > 0:
		var closest_interactable: Node = get_closest_interactable()
		
		if closest_interactable:
			print("Player: Interacting with closest: ", closest_interactable.name)
			# Try signal-based interaction first
			if closest_interactable.has_signal("interacted"):
				print("Player: Using signal-based interaction")
				closest_interactable.emit_signal("interacted", self)
			# Then try method-based interaction
			elif closest_interactable.has_method("_on_interacted"):
				print("Player: Using method-based interaction")
				closest_interactable._on_interacted(self)
			else:
				print("Player: ", closest_interactable.name, " is not properly interactable")
	else:
		print("Player: No interactables nearby")


func _handle_input() -> void:
	# Only process input for our own player (handle single-player mode too)
	var is_local_player: bool = is_multiplayer_authority() or not multiplayer.has_multiplayer_peer()
	if not is_local_player:
		return

	# Handle interaction
	if Input.is_action_just_pressed("interact"):
		_handle_interaction()
	
	# Handle bow mechanics
	_handle_bow_mechanics(get_physics_process_delta_time())
	
	# Handle additional gesture animations (only when not moving and on ground)
	if is_on_floor() and velocity.length() < WALK_THRESHOLD and not is_chopping:
		if Input.is_action_just_pressed("wave"):  # Add wave key binding
			_play_animation(ANIM_WAVE)
		elif Input.is_action_just_pressed("punch_left"):  # Add punch left key binding
			_play_animation(ANIM_PUNCH_LEFT)
		elif Input.is_action_just_pressed("punch_right"):  # Add punch right key binding
			_play_animation(ANIM_PUNCH_RIGHT)
		elif Input.is_action_just_pressed("kick_left"):  # Add kick left key binding
			_play_animation(ANIM_KICK_LEFT)
		elif Input.is_action_just_pressed("kick_right"):  # Add kick right key binding
			_play_animation(ANIM_KICK_RIGHT)
	
	# Debug: Toggle interaction zone visibility (F1 key)
	if Input.is_action_just_pressed("ui_select") and interaction_debug_mesh:  # F1 key
		interaction_debug_mesh.visible = !interaction_debug_mesh.visible
		print("Player: Interaction debug mesh visibility: ", interaction_debug_mesh.visible)


func add_item_to_inventory(item_name: String) -> bool:
	"""Add an item to the player's inventory."""
	if is_instance_valid(hud_instance) and hud_instance.has_node("Inventory"):
		var inventory = hud_instance.get_node("Inventory")
		if inventory.has_method("add_item"):
			return inventory.add_item(item_name)
	return false


func get_inventory():
	"""Get the player's inventory node."""
	if is_instance_valid(hud_instance) and hud_instance.has_node("Inventory"):
		return hud_instance.get_node("Inventory")
	return null


func _exit_tree() -> void:
	"""Clean up when the player is removed from the scene."""
	# Unregister from pause manager if we're the authority
	if is_multiplayer_authority() and PauseManager:
		PauseManager.unregister_player(self)
