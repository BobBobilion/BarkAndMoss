class_name MovementController
extends Node

# --- Constants ---
const WALK_SPEED: float = 3.0
const RUN_SPEED: float = 6.0
const JUMP_VELOCITY: float = 4.5

# --- Properties ---
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_speed: float = WALK_SPEED

# --- Public Methods ---

func handle_movement(delta: float, character_body: CharacterBody3D, transform: Transform3D) -> Vector3:
	"""
	Handles player movement, including gravity, jumping, and running.
	Returns the calculated velocity for the character body.
	"""
	var velocity: Vector3 = character_body.velocity

	# Add gravity
	if not character_body.is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump
	if Input.is_action_just_pressed("jump") and character_body.is_on_floor():
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
		
	return velocity 