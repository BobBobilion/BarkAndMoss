class_name Rabbit
extends CharacterBody3D

# --- Constants ---
const WANDER_SPEED: float = 2.0
const FLEE_SPEED: float = 4.0
const WANDER_RADIUS: float = 10.0
const FLEE_DISTANCE: float = 8.0
const DIRECTION_CHANGE_TIME: float = 3.0
const FLEE_DETECTION_RANGE: float = 6.0

# --- Node References ---
@onready var rabbit_model: Node3D = $RabbitModel
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var detection_area: Area3D = $DetectionArea
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

# --- State Management ---
enum State {
	WANDERING,
	FLEEING,
	DEAD
}

var current_state: State = State.WANDERING
var target_position: Vector3
var wander_center: Vector3
var direction_timer: float = 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var flee_target: Node3D = null

# --- Health ---
var max_health: float = 1.0  # Rabbits die in one hit
var current_health: float = max_health

# --- Corpse system ---
var corpse_scene: PackedScene = preload("res://scenes/RabbitCorpse.tscn")


func _ready() -> void:
	"""Initialize the rabbit with proper collision layers and AI setup."""
	# Set up collision layers - rabbits are on animal layer
	collision_layer = 8     # Animal layer
	collision_mask = 1      # Collide with terrain only (layer 1)
	
	# Add to animals group for identification
	add_to_group("animals")
	
	# Store the starting position as wander center
	wander_center = global_position
	
	# Set up detection area for player proximity
	if detection_area:
		detection_area.body_entered.connect(_on_detection_area_body_entered)
		detection_area.body_exited.connect(_on_detection_area_body_exited)
	
	# Initialize wandering
	_choose_new_wander_target()
	
	print("Rabbit spawned at: ", global_position)


func _physics_process(delta: float) -> void:
	"""Handle rabbit physics and AI updates."""
	if current_state == State.DEAD:
		return
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	
	# Update AI state
	_update_ai(delta)
	
	# Move the rabbit
	move_and_slide()


func _update_ai(delta: float) -> void:
	"""Update the rabbit's AI behavior based on current state."""
	match current_state:
		State.WANDERING:
			_handle_wandering(delta)
		State.FLEEING:
			_handle_fleeing(delta)


func _handle_wandering(delta: float) -> void:
	"""Handle wandering behavior - move randomly within the wander radius."""
	direction_timer -= delta
	
	# Check if we reached our target or need a new direction
	if direction_timer <= 0 or global_position.distance_to(target_position) < 1.0:
		_choose_new_wander_target()
		direction_timer = DIRECTION_CHANGE_TIME
	
	# Move towards target
	var direction: Vector3 = (target_position - global_position).normalized()
	direction.y = 0  # Keep movement horizontal
	
	velocity.x = direction.x * WANDER_SPEED
	velocity.z = direction.z * WANDER_SPEED
	
	# Face movement direction - avoid colinear vectors and same position
	if direction.length() > 0.1:
		var target_look_pos: Vector3 = global_position + direction
		
		# Ensure target position is sufficiently different from current position
		if global_position.distance_to(target_look_pos) > 0.01:
			var up_vector: Vector3 = Vector3.UP
			
			# Check if direction is parallel to up vector (avoid colinear warning)
			if abs(direction.dot(up_vector)) > 0.99:
				up_vector = Vector3.FORWARD  # Use forward as up vector instead
			
			look_at(target_look_pos, up_vector)


func _handle_fleeing(delta: float) -> void:
	"""Handle fleeing behavior - run away from nearby threats."""
	if not is_instance_valid(flee_target):
		# No valid threat, return to wandering
		current_state = State.WANDERING
		_choose_new_wander_target()
		return
	
	# Calculate flee direction (opposite of threat)
	var flee_direction: Vector3 = (global_position - flee_target.global_position).normalized()
	flee_direction.y = 0  # Keep movement horizontal
	
	# Move away from threat
	velocity.x = flee_direction.x * FLEE_SPEED
	velocity.z = flee_direction.z * FLEE_SPEED
	
	# Face flee direction - avoid colinear vectors and same position
	if flee_direction.length() > 0.1:
		var target_look_pos: Vector3 = global_position + flee_direction
		
		# Ensure target position is sufficiently different from current position
		if global_position.distance_to(target_look_pos) > 0.01:
			var up_vector: Vector3 = Vector3.UP
			
			# Check if flee direction is parallel to up vector (avoid colinear warning)
			if abs(flee_direction.dot(up_vector)) > 0.99:
				up_vector = Vector3.FORWARD  # Use forward as up vector instead
			
			look_at(target_look_pos, up_vector)
	
	# Check if we've fled far enough
	if global_position.distance_to(flee_target.global_position) > FLEE_DISTANCE:
		current_state = State.WANDERING
		flee_target = null
		_choose_new_wander_target()


func _choose_new_wander_target() -> void:
	"""Choose a new random position to wander towards within the wander radius."""
	var random_offset: Vector3 = Vector3(
		randf_range(-WANDER_RADIUS, WANDER_RADIUS),
		0,
		randf_range(-WANDER_RADIUS, WANDER_RADIUS)
	)
	
	target_position = wander_center + random_offset


func _on_detection_area_body_entered(body: Node3D) -> void:
	"""Handle when a potential threat enters detection range."""
	# Check if this is a player that should cause the rabbit to flee
	if body.is_in_group("human_player") or body.is_in_group("dog_player"):
		current_state = State.FLEEING
		flee_target = body
		print("Rabbit detected threat: ", body.name)


func _on_detection_area_body_exited(body: Node3D) -> void:
	"""Handle when a threat leaves detection range."""
	if body == flee_target:
		# Give the rabbit a moment before returning to wandering
		# (This prevents rapid state switching)
		pass


func take_damage(amount: float) -> void:
	"""Handle taking damage from arrows or dog bites."""
	if current_state == State.DEAD:
		return
	
	current_health -= amount
	
	if current_health <= 0:
		die()


func die() -> void:
	"""Handle rabbit death - spawn corpse and remove rabbit."""
	if current_state == State.DEAD:
		return
	
	print("Rabbit died at: ", global_position)
	current_state = State.DEAD
	
	# Spawn a corpse at this location
	_spawn_corpse()
	
	# Remove the rabbit
	queue_free()


func _spawn_corpse() -> void:
	"""Spawn a rabbit corpse that can be interacted with."""
	# Try to spawn corpse if the scene exists
	if corpse_scene:
		var corpse: Node3D = corpse_scene.instantiate()
		get_tree().current_scene.add_child(corpse)
		corpse.global_position = global_position
		print("Spawned rabbit corpse")
	else:
		# Fallback: just print a message for now
		print("Would spawn rabbit corpse here (corpse scene not found)")


func get_state_name() -> String:
	"""Helper function to get the current state as a string for debugging."""
	match current_state:
		State.WANDERING:
			return "Wandering"
		State.FLEEING:
			return "Fleeing"
		State.DEAD:
			return "Dead"
		_:
			return "Unknown" 