class_name Dog
extends CharacterBody3D


# --- Constants ---
const WALK_SPEED: float = 4.0  # Added walk speed for normal movement
const RUN_SPEED: float = 8.0
const JUMP_VELOCITY: float = 5.0
const MOUSE_SENSITIVITY: float = 0.002
const CAMERA_PITCH_MIN: float = -1.5
const CAMERA_PITCH_MAX: float = 1.5
const CAMERA_COLLISION_BIAS: float = 0.2

# Bite attack
const BITE_RANGE: float = 2.0
const BITE_HITBOX_SIZE: float = 1.5
const BITE_COOLDOWN: float = 0.5
# Attack animation duration (approximate time for attack animation to complete)
const ATTACK_ANIMATION_DURATION: float = 1.0

# Bark
const BARK_COOLDOWN: float = 1.0
# Bark animation duration (approximate time for bark behavior to complete)
const BARK_ANIMATION_DURATION: float = 1.0

# Animation constants
const ANIMATION_BLEND_TIME: float = 0.2  # Time to blend between animations

# Available animation names from the Dog.glb model
const ANIM_ATTACK: String = "DogArmature|Attack"                     # Bite attack animation
const ANIM_DEATH: String = "DogArmature|Death"                       # Death animation
const ANIM_EATING: String = "DogArmature|Eating"                     # Eating raw meat animation
const ANIM_GALLOP: String = "DogArmature|Gallop"                     # Fast running animation
const ANIM_GALLOP_JUMP: String = "DogArmature|Gallop_Jump"           # Jumping while running
const ANIM_IDLE_HIT_REACT_LEFT: String = "DogArmature|Idle_HitReact_Left"   # Left hit reaction
const ANIM_IDLE_HIT_REACT_RIGHT: String = "DogArmature|Idle_HitReact_Right" # Right hit reaction
const ANIM_JUMP_TO_IDLE: String = "DogArmature|Jump_ToIdle"          # Landing from jump
const ANIM_WALK: String = "DogArmature|Walk"                         # Walking animation
const ANIM_IDLE_2: String = "DogArmature|Idle_2"                     # Alternative idle
const ANIM_IDLE_2_HEAD_LOW: String = "DogArmature|Idle_2_HeadLow"    # Head down idle
const ANIM_IDLE: String = "DogArmature|Idle"                         # Default idle pose

# Movement speed thresholds for animation selection
const WALK_THRESHOLD: float = 0.1                        # Minimum speed to trigger walk
const GALLOP_THRESHOLD: float = 6.0                      # Speed threshold for gallop vs walk (adjusted for walk/run system)


# --- Properties ---
# Physics
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Movement
var current_speed: float = WALK_SPEED  # Default to walking speed

# Camera
@onready var camera: Camera3D = $CameraRootOffset/HorizontalPivot/VerticalPivot/SpringArm3D/Camera3D
@onready var horizontal_pivot: Node3D = $CameraRootOffset/HorizontalPivot
@onready var vertical_pivot: Node3D = $CameraRootOffset/HorizontalPivot/VerticalPivot
@onready var spring_arm: SpringArm3D = $CameraRootOffset/HorizontalPivot/VerticalPivot/SpringArm3D
var mouse_delta: Vector2 = Vector2.ZERO
var camera_pitch: float = 0.0
var base_camera_position: Vector3

# Bite Attack
var is_biting: bool = false
var bite_timer: float = 0.0
# New variables for proper animation handling
var is_attack_animation_playing: bool = false
var attack_animation_timer: float = 0.0

# Bark
var bark_timer: float = 0.0
# New variables for proper animation handling  
var is_bark_animation_playing: bool = false
var bark_animation_timer: float = 0.0

# Corpse dragging
var grabbed_corpse: Node3D = null
var corpse_offset: Vector3 = Vector3(0, 0, 1.5)  # Position corpse behind dog

# Animation system
@onready var dog_model: Node3D = $DogModel
var animation_player: AnimationPlayer
var current_animation: String = ""
var is_attacking: bool = false
var is_eating: bool = false
var was_moving: bool = false  # Track previous movement state to detect transitions


func _ready() -> void:
	# Set up collision layers for proper terrain interaction
	collision_layer = 2      # Dog is on layer 2
	collision_mask = 1 | 2 | 8   # Dog collides with terrain (1), players/environment (2), and animals (8)
	
	# This check is the key to fixing camera and input issues.
	if is_multiplayer_authority():
		# This is MY character. Enable my camera and capture my mouse.
		camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
		# Add global UI for FPS counter and game code display
		call_deferred("add_global_ui")
		
		# Register with PauseManager for pause functionality
		if PauseManager:
			PauseManager.register_player(self)
	else:
		# This is a networked copy of another player. Disable its camera.
		camera.enabled = false
	
	# Add to group for identification
	add_to_group("dog_player")

	# Configure SpringArm3D for dog-appropriate camera distance
	if spring_arm:
		spring_arm.spring_length = 2.5  # Slightly closer than player
		spring_arm.collision_mask = 1   # Terrain collision
	
	# Initialize animation system
	_setup_animations()
	
	# Configure MultiplayerSynchronizer for animations
	_configure_multiplayer_sync()


func _exit_tree() -> void:
	"""Clean up when dog is removed from scene."""
	# Unregister from PauseManager
	if multiplayer and multiplayer.multiplayer_peer and is_multiplayer_authority() and PauseManager:
		PauseManager.unregister_player(self)


func _unhandled_input(event: InputEvent) -> void:
	# Check if multiplayer peer exists before checking authority
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion:
		mouse_delta += event.relative


func _input(event: InputEvent) -> void:
	# Check if multiplayer peer exists before checking authority
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	# ESC key handling removed - let PauseManager handle pause menu functionality
	# Mouse cursor will be freed when pause menu opens


func _process(delta: float) -> void:
	# Only process input for our own player - check if multiplayer peer exists first
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
		
	# Handle mouse look
	if mouse_delta != Vector2.ZERO:
		_handle_camera_rotation(mouse_delta)
		mouse_delta = Vector2.ZERO
	
	# Handle camera collision
	handle_camera_collision()
	
	# Handle bite attack and corpse dragging
	if Input.is_action_just_pressed("attack"):
		# Single-click attack (for animals) or start dragging (for corpses)
		if bite_timer <= 0 and not is_attack_animation_playing:
			start_bite_attack()
	elif Input.is_action_pressed("attack") and grabbed_corpse:
		# Continue dragging corpse while holding attack button
		# (corpse position is updated in _update_corpse_dragging)
		pass
	elif Input.is_action_just_released("attack") and grabbed_corpse:
		# Release corpse when attack button is released
		release_corpse()
	
	# Handle corpse dragging
	_update_corpse_dragging()
	
	# Handle bark (single-click, check if not already barking)
	if Input.is_action_just_pressed("bark") and bark_timer <= 0 and not is_bark_animation_playing:
		perform_bark()
	
	# Handle corpse release (Q key as alternative release method)
	if Input.is_action_just_pressed("ui_cancel") and grabbed_corpse:
		release_corpse()
	
	# Update timers
	if bite_timer > 0:
		bite_timer -= delta
	if bark_timer > 0:
		bark_timer -= delta
		
	# Update animation completion timers
	if attack_animation_timer > 0:
		attack_animation_timer -= delta
		if attack_animation_timer <= 0:
			# Attack animation finished
			is_attack_animation_playing = false
			is_attacking = false
			is_biting = false
			# Return to movement animation
			_update_movement_animation()
	
	if bark_animation_timer > 0:
		bark_animation_timer -= delta
		if bark_animation_timer <= 0:
			# Bark animation finished
			is_bark_animation_playing = false
			# Return to movement animation
			_update_movement_animation()


func _physics_process(delta: float) -> void:
	# Only process input for our own player - check if multiplayer peer exists first
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	
	# Add the gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Handle run/walk switching (like player) [[memory:3259606]]
	if Input.is_action_pressed("run"):
		current_speed = RUN_SPEED
	else:
		current_speed = WALK_SPEED

	# Handle movement input
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		# Use current_speed (walk or run based on input)
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()
	
	# Update chunk system with our position
	_update_chunk_position()
	
	# Update animations based on movement and state
	_update_movement_animation()


func _setup_animations() -> void:
	"""Initialize the animation system by finding the AnimationPlayer in the dog model."""
	# Look for AnimationPlayer in the dog model
	if dog_model:
		animation_player = _find_animation_player_recursive(dog_model)
		if animation_player:
			# DEBUG: Print all available animations
			print("Dog: Available animations:")
			var animation_list: PackedStringArray = animation_player.get_animation_list()
			for anim_name in animation_list:
				print("  - ", anim_name)
			
			# Check if our idle variants exist
			print("Dog: Checking idle animations:")
			print("  ANIM_IDLE (", ANIM_IDLE, "): ", animation_player.has_animation(ANIM_IDLE))
			print("  ANIM_IDLE_2 (", ANIM_IDLE_2, "): ", animation_player.has_animation(ANIM_IDLE_2))
			print("  ANIM_IDLE_2_HEAD_LOW (", ANIM_IDLE_2_HEAD_LOW, "): ", animation_player.has_animation(ANIM_IDLE_2_HEAD_LOW))
			
			# Start with idle animation
			_play_animation(ANIM_IDLE)


func _find_animation_player_recursive(node: Node) -> AnimationPlayer:
	"""Recursively search for an AnimationPlayer node in the dog model."""
	if node is AnimationPlayer:
		return node as AnimationPlayer
	
	for child in node.get_children():
		var result: AnimationPlayer = _find_animation_player_recursive(child)
		if result:
			return result
	
	return null


func _update_movement_animation() -> void:
	"""Update dog animations based on current state and movement."""
	if not animation_player:
		return
	
	# Calculate movement speed first
	var speed: float = Vector2(velocity.x, velocity.z).length()
	var target_animation: String = ""
	var is_currently_moving: bool = speed > WALK_THRESHOLD
	
	# Check if jumping (in air) - jumping takes priority over other actions
	if not is_on_floor():
		target_animation = ANIM_GALLOP_JUMP
	# Don't override eating, attacking, or barking animations with movement animations
	elif is_eating:
		return
	elif is_attack_animation_playing:  # CHANGED: use new animation completion flag
		return
	elif is_bark_animation_playing:   # CHANGED: use new animation completion flag
		return
	# Check movement speed
	elif is_currently_moving:
		if speed >= GALLOP_THRESHOLD:
			target_animation = ANIM_GALLOP
		else:
			target_animation = ANIM_WALK
	else:
		# Only select a new idle animation when transitioning from movement to idle
		# or if no animation is currently playing
		# FIXED: Also check if current animation is NOT an idle animation (e.g., after attack)
		var is_current_idle: bool = current_animation in [ANIM_IDLE, ANIM_IDLE_2, ANIM_IDLE_2_HEAD_LOW]
		
		if was_moving or current_animation.is_empty() or not is_current_idle:
			# FIXED: Only select new idle animation when transitioning, not every frame
			# Use default idle to avoid rapid switching
			target_animation = ANIM_IDLE
		else:
			# Stay with current idle animation if already idle and let it finish
			target_animation = current_animation
	
	# Update movement state tracking
	was_moving = is_currently_moving
	
	# Play the appropriate animation - but be careful with idle animation restarts
	# FIXED: Only restart if we're switching to a different animation, not when idle animations finish
	if target_animation != current_animation:
		_play_animation(target_animation)
	elif not animation_player.is_playing():
		# Handle animation finishing cases
		if target_animation in [ANIM_IDLE, ANIM_IDLE_2, ANIM_IDLE_2_HEAD_LOW]:
			# 30% chance to switch to a different idle animation when current idle finishes
			if randf() < 0.30:
				var idle_variants: Array[String] = [ANIM_IDLE, ANIM_IDLE_2, ANIM_IDLE_2_HEAD_LOW]
				# Remove current animation from options to ensure we get a different one
				idle_variants.erase(current_animation)
				var new_idle: String = idle_variants[randi() % idle_variants.size()]
				print("Dog: Switching from '", current_animation, "' to '", new_idle, "' (30% chance triggered)")
				_play_animation(new_idle)
			else:
				# 70% chance to continue with same idle animation
				print("Dog: Continuing with '", target_animation, "' (70% chance - no variation)")
				_play_animation(target_animation)
		else:
			# Restart non-idle animations when they finish
			_play_animation(target_animation)


func _play_animation(anim_name: String) -> void:
	"""Play an animation on the AnimationPlayer."""
	if animation_player and animation_player.has_animation(anim_name):
		if current_animation != anim_name:
			animation_player.play(anim_name)
			current_animation = anim_name
			
			# Sync animation to other players
			if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
				_sync_animation_rpc.rpc(anim_name)
	else:
		# print("Dog: Animation not found: ", anim_name)
		pass


@rpc("any_peer", "call_local", "unreliable")
func _sync_animation_rpc(anim_name: String) -> void:
	"""RPC to sync animation on remote players."""
	# Debug: Log when receiving RPC
	
	# Don't process on the authority (they already played it)
	if is_multiplayer_authority():
		return
		
	# Play the animation on remote copies
	if animation_player and animation_player.has_animation(anim_name):
		animation_player.play(anim_name)
		current_animation = anim_name


func _handle_camera_rotation(relative_mouse_motion: Vector2) -> void:
	"""Handles the rotation of the player and camera based on mouse movement."""
	# Rotate the dog body left/right (yaw) - essential for movement direction
	rotate_y(-relative_mouse_motion.x * MOUSE_SENSITIVITY)
	
	# Update camera pitch on vertical pivot
	camera_pitch += -relative_mouse_motion.y * MOUSE_SENSITIVITY
	camera_pitch = clamp(camera_pitch, CAMERA_PITCH_MIN, CAMERA_PITCH_MAX)
	
	# Apply pitch to vertical pivot
	if vertical_pivot:
		vertical_pivot.rotation.x = camera_pitch


func handle_camera_collision() -> void:
	"""
	Camera collision is now handled automatically by SpringArm3D in the new camera system.
	This function is kept for compatibility but no longer needed.
	"""
	# SpringArm3D handles collision automatically
	pass


func _update_corpse_dragging() -> void:
	"""Update the position of any grabbed corpse to follow the dog."""
	if grabbed_corpse and is_instance_valid(grabbed_corpse):
		# Position the corpse behind the dog
		var target_position: Vector3 = global_position + global_transform.basis * corpse_offset
		grabbed_corpse.global_position = target_position


func start_bite_attack() -> void:
	"""Starts the bite attack - checks what we're attacking and responds appropriately."""
	# First check what we're about to bite/grab
	var target_type: String = _check_bite_target()
	
	if target_type == "animal":
		# Attacking an animal - play full attack animation
		is_attacking = true
		is_biting = true
		bite_timer = BITE_COOLDOWN
		
		# Play attack animation
		_play_animation(ANIM_ATTACK)
		is_attack_animation_playing = true
		attack_animation_timer = ATTACK_ANIMATION_DURATION
		
		# Perform the actual attack (damage)
		perform_bite_attack()
	elif target_type == "corpse":
		# Grabbing a corpse - no attack animation, just grab immediately
		bite_timer = BITE_COOLDOWN
		perform_bite_attack()  # This will grab the corpse
	else:
		# Nothing to attack/grab - play attack animation anyway (missed attack)
		is_attacking = true
		is_biting = true
		bite_timer = BITE_COOLDOWN
		
		# Play attack animation
		_play_animation(ANIM_ATTACK)
		is_attack_animation_playing = true
		attack_animation_timer = ATTACK_ANIMATION_DURATION


func _check_bite_target() -> String:
	"""Check what type of target is in bite range. Returns 'animal', 'corpse', or 'none'."""
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var bite_center: Vector3 = global_position + global_transform.basis * Vector3(0, 0, -BITE_RANGE)
	
	# Use sphere shape for bite detection
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = BITE_HITBOX_SIZE
	
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = bite_center
	query.collision_mask = 8 | 16  # Animals (8) and corpses (16)
	
	var results: Array[Dictionary] = space_state.intersect_shape(query)
	
	for result in results:
		var collider: Node = result.collider
		
		# Check for animals first (higher priority)
		if collider.is_in_group("animals") and collider.has_method("take_damage"):
			return "animal"
		
		# Check for corpses (only if no animals and not already carrying one)
		elif collider.is_in_group("corpses") and not grabbed_corpse:
			return "corpse"
	
	return "none"


func perform_bite_attack() -> void:
	"""
	Performs the bite attack - damages animals or grabs corpses.
	"""
	if not is_biting:
		return
	
	# Create a detection area in front of the dog
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var bite_center: Vector3 = global_position + global_transform.basis * Vector3(0, 0, -BITE_RANGE)
	
	# Use sphere shape for bite detection
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = BITE_HITBOX_SIZE
	
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = bite_center
	query.collision_mask = 8 | 16  # Animals (8) and corpses (16)
	
	var results: Array[Dictionary] = space_state.intersect_shape(query)
	
	for result in results:
		var collider: Node = result.collider
		
		# Check if it's an animal we can damage
		if collider.is_in_group("animals") and collider.has_method("take_damage"):
			collider.take_damage(100.0)  # Instant kill for dog bite
			print("Dog bit ", collider.name)
			return  # Only bite one thing at a time
		
		# Check if it's a corpse we can grab
		elif collider.is_in_group("corpses") and not grabbed_corpse:
			_grab_corpse(collider)
			return


func _grab_corpse(corpse: Node3D) -> void:
	"""Grab a corpse for dragging."""
	if grabbed_corpse:
		return  # Already carrying something
	
	grabbed_corpse = corpse
	print("Dog grabbed corpse: ", corpse.name, " (hold attack button to drag, release to drop)")
	
	# Tell the corpse it's being grabbed
	if corpse.has_method("_grab_corpse"):
		corpse._grab_corpse(self)


func release_corpse() -> void:
	"""Release the currently grabbed corpse."""
	if not grabbed_corpse:
		return
	
	print("Dog released corpse: ", grabbed_corpse.name)
	
	# Tell the corpse it's being released
	if grabbed_corpse.has_method("release"):
		grabbed_corpse.release()
	
	grabbed_corpse = null


func perform_bark() -> void:
	"""
	Performs the bark action, starts cooldown, and notifies nearby birds.
	"""
	bark_timer = BARK_COOLDOWN
	print("Dog barked!")
	
	# Play bark behavior animation (head low listening pose)
	_play_animation(ANIM_IDLE_2_HEAD_LOW)
	
	# Set up animation completion tracking
	is_bark_animation_playing = true
	bark_animation_timer = BARK_ANIMATION_DURATION
	
	# Notify nearby birds about the bark
	_notify_birds_of_bark()


func start_eating_animation() -> void:
	"""Start the eating animation when the dog eats raw meat."""
	if not animation_player:
		return
	
	is_eating = true
	_play_animation(ANIM_EATING)
	
	# Set up a timer to stop eating animation after a duration
	var eat_duration: float = 2.0  # 2 second eating animation
	var timer: Timer = Timer.new()
	add_child(timer)
	timer.wait_time = eat_duration
	timer.timeout.connect(func():
		timer.queue_free()
		is_eating = false
		_update_movement_animation()
		print("Dog finished eating animation")
	)
	timer.start()
	
	print("Dog started eating animation")


func _notify_birds_of_bark() -> void:
	"""Find nearby birds and tell them about the bark so they can flee."""
	var birds: Array[Node] = get_tree().get_nodes_in_group("birds")
	
	for bird in birds:
		if is_instance_valid(bird) and bird.has_method("respond_to_bark"):
			bird.respond_to_bark(self)


func _update_camera_position() -> void:
	"""
	Camera position is now handled by the SpringArm3D system.
	This function is kept for compatibility but no longer needed.
	"""
	# SpringArm3D handles camera positioning automatically
	pass

func _update_chunk_position() -> void:
	"""Update our position in the chunk system for loading/unloading chunks."""
	# Find GameManager and update our position
	var game_managers := get_tree().get_nodes_in_group("game_manager")
	if game_managers.size() > 0:
		var game_manager = game_managers[0]
		if game_manager.has_method("update_player_chunk_position"):
			game_manager.update_player_chunk_position(self)


func add_global_ui() -> void:
	"""Add global UI elements that should be visible to both human and dog players."""
	print("Dog: add_global_ui() called")
	
	# Get the root viewport
	var viewport = get_viewport()
	if not viewport:
		print("Dog: ERROR - No viewport available")
		return
		
	# Check if GlobalUILayer already exists (might be created by human player)
	var global_ui_layer = viewport.get_node_or_null("GlobalUILayer")
	
	if global_ui_layer:
		print("Dog: GlobalUILayer already exists, updating player reference")
		# Update the player reference
		global_ui_layer.set_meta("player_ref", self)
		return
	else:
		print("Dog: Creating new GlobalUILayer")
		global_ui_layer = CanvasLayer.new()
		global_ui_layer.name = "GlobalUILayer"
		global_ui_layer.layer = 5  # Lower than HUD (10) but above background
		viewport.add_child(global_ui_layer)
		print("Dog: GlobalUILayer created and added to viewport")
	
	# Store player reference
	global_ui_layer.set_meta("player_ref", self)
	
	# Create FPS counter
	var fps_counter = Label.new()
	fps_counter.name = "FPSCounter"
	fps_counter.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	fps_counter.offset_left = -120
	fps_counter.offset_top = 10
	fps_counter.offset_right = -10
	fps_counter.offset_bottom = 35
	fps_counter.add_theme_font_size_override("font_size", 16)
	fps_counter.add_theme_color_override("font_color", Color(0.918, 0.878, 0.835, 1))
	fps_counter.add_theme_color_override("font_shadow_color", Color(0.137, 0.2, 0.165, 1))
	fps_counter.add_theme_constant_override("shadow_offset_x", 1)
	fps_counter.add_theme_constant_override("shadow_offset_y", 1)
	fps_counter.text = "FPS: 60"
	fps_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fps_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	global_ui_layer.add_child(fps_counter)
	
	# Create position display
	var position_display = Label.new()
	position_display.name = "PositionDisplay"
	position_display.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	position_display.offset_left = -200
	position_display.offset_top = 40  # Below FPS counter
	position_display.offset_right = -10
	position_display.offset_bottom = 65
	position_display.add_theme_font_size_override("font_size", 14)
	position_display.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	position_display.add_theme_color_override("font_shadow_color", Color(0.137, 0.2, 0.165, 1))
	position_display.add_theme_constant_override("shadow_offset_x", 1)
	position_display.add_theme_constant_override("shadow_offset_y", 1)
	position_display.text = "X: 0.0 Y: 0.0 Z: 0.0"
	position_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	position_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	position_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	global_ui_layer.add_child(position_display)
	
	# Create game code display
	var game_code_display = Label.new()
	game_code_display.name = "GameCodeDisplay"
	game_code_display.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	game_code_display.offset_left = 10
	game_code_display.offset_top = 10
	game_code_display.offset_right = 150
	game_code_display.offset_bottom = 35
	game_code_display.add_theme_font_size_override("font_size", 16)
	game_code_display.add_theme_color_override("font_color", Color(0.918, 0.878, 0.835, 1))
	game_code_display.add_theme_color_override("font_shadow_color", Color(0.137, 0.2, 0.165, 1))
	game_code_display.add_theme_constant_override("shadow_offset_x", 1)
	game_code_display.add_theme_constant_override("shadow_offset_y", 1)
	game_code_display.text = "Code: Loading..."  # Start with loading text
	game_code_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	game_code_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_code_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	global_ui_layer.add_child(game_code_display)
	
	# Create world seed display (for dog player)
	var seed_display = Label.new()
	seed_display.name = "SeedDisplay"
	seed_display.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	seed_display.offset_left = 10
	seed_display.offset_top = 40  # Below game code
	seed_display.offset_right = 200
	seed_display.offset_bottom = 65
	seed_display.add_theme_font_size_override("font_size", 14)
	seed_display.add_theme_color_override("font_color", Color.YELLOW)
	seed_display.add_theme_color_override("font_shadow_color", Color(0.137, 0.2, 0.165, 1))
	seed_display.add_theme_constant_override("shadow_offset_x", 1)
	seed_display.add_theme_constant_override("shadow_offset_y", 1)
	seed_display.text = "World Seed: Loading..."
	seed_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	seed_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seed_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	global_ui_layer.add_child(seed_display)
	
	# Create update timer directly on the layer
	var update_timer = Timer.new()
	update_timer.name = "UpdateTimer"
	update_timer.wait_time = 0.1  # Update every 100ms
	update_timer.autostart = true
	update_timer.timeout.connect(func():
		# Update FPS
		if fps_counter:
			fps_counter.text = "FPS: %d" % Engine.get_frames_per_second()
		
		# Update position
		var player = global_ui_layer.get_meta("player_ref", null)
		if position_display and is_instance_valid(player):
			var pos = player.global_position
			position_display.text = "X: %.1f Y: %.1f Z: %.1f" % [pos.x, pos.y, pos.z]
		
		# Update lobby code
		if game_code_display and is_instance_valid(NetworkManager):
			var lobby_code = NetworkManager.get_lobby_code()
			if lobby_code != "":
				game_code_display.text = "Code: %s" % lobby_code
			else:
				if multiplayer.has_multiplayer_peer():
					game_code_display.text = "Code: Waiting..."
				else:
					game_code_display.text = "Code: Offline"
		else:
			game_code_display.text = "Code: N/A"
		
		# Update world seed (for dog player)
		if seed_display:
			var game_manager = get_tree().get_first_node_in_group("game_manager")
			if game_manager and game_manager.chunk_manager and game_manager.chunk_manager.chunk_generator:
				var seed = game_manager.chunk_manager.chunk_generator.world_seed
				seed_display.text = "World Seed: %d" % seed
			else:
				seed_display.text = "World Seed: Unknown"
	)
	global_ui_layer.add_child(update_timer)
	
	print("Dog: Global UI created successfully")

# Add new method to configure multiplayer synchronization
func _configure_multiplayer_sync() -> void:
	"""Configure the MultiplayerSynchronizer to include animation state."""
	if not multiplayer.has_multiplayer_peer():
		return  # Skip in single player mode
		
	var sync = $MultiplayerSynchronizer
	if not sync:
		print("Dog: Warning - MultiplayerSynchronizer not found!")
		return
		
	# For now, just log that we would configure animation sync
	# The actual animation sync needs to be configured in the scene file
	# or through a different approach since SceneReplicationConfig API is limited
	print("Dog: Animation sync should be configured in the scene file")
	
	# Alternative approach: sync animation manually via RPC
	# This will be handled by the animation update methods
