class_name Dog
extends CharacterBody3D


# --- Constants ---
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

# Bark
const BARK_COOLDOWN: float = 1.0

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
const GALLOP_THRESHOLD: float = 6.0                      # Speed threshold for gallop vs walk


# --- Properties ---
# Physics
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Camera
@onready var camera: Camera3D = $Camera3D
var mouse_delta: Vector2 = Vector2.ZERO
var camera_pitch: float = 0.0
var base_camera_position: Vector3

# Bite Attack
var is_biting: bool = false
var bite_timer: float = 0.0

# Bark
var bark_timer: float = 0.0

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
	collision_mask = 1 | 2   # Dog collides with terrain (layer 1) and other players (layer 2)
	
	# This check is the key to fixing camera and input issues.
	if is_multiplayer_authority():
		# This is MY character. Enable my camera and capture my mouse.
		camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		# This is a networked copy of another player. Disable its camera.
		camera.enabled = false
	
	# Add to group for identification
	add_to_group("dog_player")

	# Store the initial camera position
	base_camera_position = camera.position
	
	# Initialize animation system
	_setup_animations()
	



func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion:
		mouse_delta += event.relative


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(delta: float) -> void:
	# Only process input for our own player
	if not is_multiplayer_authority():
		return
		
	# Handle mouse look
	if mouse_delta != Vector2.ZERO:
		_handle_camera_rotation(mouse_delta)
		mouse_delta = Vector2.ZERO
	
	# Handle camera collision
	handle_camera_collision()
	
	# Handle bite attack (hold left click)
	if Input.is_action_pressed("attack") and bite_timer <= 0:
		if not is_biting:
			start_bite_attack()
		perform_bite_attack()
	elif Input.is_action_just_released("attack"):
		stop_bite_attack()
	
	# Handle corpse dragging
	_update_corpse_dragging()
	
	# Handle bark (right click)
	if Input.is_action_just_pressed("bark") and bark_timer <= 0:
		perform_bark()
	
	# Handle corpse release (Q key or right click when holding corpse)
	if Input.is_action_just_pressed("ui_cancel") and grabbed_corpse:
		release_corpse()
	
	# Update timers
	if bite_timer > 0:
		bite_timer -= delta
	if bark_timer > 0:
		bark_timer -= delta


func _physics_process(delta: float) -> void:
	# Only process input for our own player
	if not is_multiplayer_authority():
		return
	
	# Add the gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
		
		# If dog is in air and was attacking, stop the attack
		if is_attacking:
			stop_bite_attack()

	# Handle jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		
		# Stop any current attack when jumping
		if is_attacking:
			stop_bite_attack()

	# Handle movement input
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		# The dog always moves at RUN_SPEED
		velocity.x = direction.x * RUN_SPEED
		velocity.z = direction.z * RUN_SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, RUN_SPEED)
		velocity.z = move_toward(velocity.z, 0, RUN_SPEED)

	move_and_slide()
	
	# Update animations based on movement and state
	_update_movement_animation()


func _setup_animations() -> void:
	"""Initialize the animation system by finding the AnimationPlayer in the dog model."""
	# Look for AnimationPlayer in the dog model
	if dog_model:
		animation_player = _find_animation_player_recursive(dog_model)
		if animation_player:
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
	# Don't override eating animation, but allow jump to override attack
	elif is_eating:
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
		if was_moving or current_animation.is_empty():
			# Vary idle animations for more life
			var idle_variant: int = randi() % 3
			match idle_variant:
				0:
					target_animation = ANIM_IDLE
				1:
					target_animation = ANIM_IDLE_2
				2:
					target_animation = ANIM_IDLE_2_HEAD_LOW
		else:
			# Stay with current idle animation if already idle
			target_animation = current_animation
	
	# Update movement state tracking
	was_moving = is_currently_moving
	
	# Play the appropriate animation - allow restarts if animation finished
	if target_animation != current_animation or not animation_player.is_playing():
		_play_animation(target_animation)


func _play_animation(animation_name: String) -> void:
	"""Play the specified animation with fallback handling."""
	if not animation_player:
		return
	
	# Check if the animation exists
	if animation_player.has_animation(animation_name):
		animation_player.play(animation_name, ANIMATION_BLEND_TIME)
		current_animation = animation_name
		
		# Ensure movement animations loop properly
		if animation_name in [ANIM_WALK, ANIM_GALLOP, ANIM_IDLE, ANIM_IDLE_2, ANIM_IDLE_2_HEAD_LOW, ANIM_EATING]:
			var animation_resource: Animation = animation_player.get_animation(animation_name)
			if animation_resource:
				animation_resource.loop_mode = Animation.LOOP_LINEAR
	else:

		
		# Try fallback alternatives for common animations
		var alternatives: Array[String] = []
		match animation_name:
			ANIM_IDLE:
				alternatives = ["DogArmature|Idle", "Armature|Idle", "Dog|Idle", "Idle", "DogArmature|idle", "Armature|idle", "Dog|idle", "idle", "DogArmature|Idle_1", "Armature|Idle_1", "Dog|Idle_1", "Idle_1"]
			ANIM_WALK:
				alternatives = ["DogArmature|Walk", "Armature|Walk", "Dog|Walk", "Walk", "DogArmature|walking", "Armature|walking", "Dog|walking", "walking"]
			ANIM_GALLOP:
				alternatives = ["DogArmature|Gallop", "Armature|Gallop", "Dog|Gallop", "Gallop", "DogArmature|Run", "Armature|Run", "Dog|Run", "Run", "DogArmature|run", "Armature|run", "Dog|run", "run"]
			ANIM_GALLOP_JUMP:
				alternatives = ["DogArmature|Gallop_Jump", "Armature|Gallop_Jump", "Dog|Gallop_Jump", "Gallop_Jump", "DogArmature|Jump", "Armature|Jump", "Dog|Jump", "Jump", "DogArmature|jump", "Armature|jump", "Dog|jump", "jump", "DogArmature|Gallop", "Armature|Gallop", "Dog|Gallop", "Gallop"]
			ANIM_JUMP_TO_IDLE:
				alternatives = ["DogArmature|Jump_ToIdle", "Armature|Jump_ToIdle", "Dog|Jump_ToIdle", "Jump_ToIdle", "DogArmature|Landing", "Armature|Landing", "Dog|Landing", "Landing", "DogArmature|Idle", "Armature|Idle", "Dog|Idle", "Idle"]
			ANIM_ATTACK:
				alternatives = ["DogArmature|Attack", "Armature|Attack", "Dog|Attack", "Attack", "DogArmature|Bite", "Armature|Bite", "Dog|Bite", "Bite", "DogArmature|bite", "Armature|bite", "Dog|bite", "bite"]
			ANIM_EATING:
				alternatives = ["DogArmature|Eating", "Armature|Eating", "Dog|Eating", "Eating", "DogArmature|Eat", "Armature|Eat", "Dog|Eat", "Eat", "DogArmature|eat", "Armature|eat", "Dog|eat", "eat"]
			ANIM_DEATH:
				alternatives = ["DogArmature|Death", "Armature|Death", "Dog|Death", "Death", "DogArmature|Die", "Armature|Die", "Dog|Die", "Die", "DogArmature|die", "Armature|die", "Dog|die", "die"]
		
		# Try to find an alternative
		for alt in alternatives:
			if animation_player.has_animation(alt):
				animation_player.play(alt, ANIMATION_BLEND_TIME)
				current_animation = alt
				
				# Ensure fallback movement animations loop properly too
				if alt.to_lower().contains("walk") or alt.to_lower().contains("gallop") or alt.to_lower().contains("idle") or alt.to_lower().contains("eat"):
					var animation_resource: Animation = animation_player.get_animation(alt)
					if animation_resource:
						animation_resource.loop_mode = Animation.LOOP_LINEAR
				
				return
		
		# If no animation found, try to play the first available animation
		var animation_list: PackedStringArray = animation_player.get_animation_list()
		if animation_list.size() > 0:
			animation_player.play(animation_list[0], ANIMATION_BLEND_TIME)
			current_animation = animation_list[0]


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


func _update_corpse_dragging() -> void:
	"""Update the position of any grabbed corpse to follow the dog."""
	if grabbed_corpse and is_instance_valid(grabbed_corpse):
		# Position the corpse behind the dog
		var target_position: Vector3 = global_position + global_transform.basis * corpse_offset
		grabbed_corpse.global_position = target_position


func start_bite_attack() -> void:
	"""Starts the bite attack animation and sets up the hitbox."""
	is_attacking = true
	is_biting = true
	bite_timer = BITE_COOLDOWN
	
	# Play attack animation
	_play_animation(ANIM_ATTACK)


func stop_bite_attack() -> void:
	"""Stops the bite attack and starts the cooldown."""
	is_attacking = false
	is_biting = false
	bite_timer = BITE_COOLDOWN
	
	# Return to appropriate movement animation
	_update_movement_animation()


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
	print("Dog grabbed corpse: ", corpse.name)
	
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
	
	# Could add a bark animation here if available
	# For now, briefly show idle head low as a "listening" pose
	if not is_attacking and not is_eating:
		_play_animation(ANIM_IDLE_2_HEAD_LOW)
		
		# Return to normal animation after a short delay
		var bark_duration: float = 0.5
		var timer: Timer = Timer.new()
		add_child(timer)
		timer.wait_time = bark_duration
		timer.timeout.connect(func():
			timer.queue_free()
			_update_movement_animation()
		)
		timer.start()
	
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
