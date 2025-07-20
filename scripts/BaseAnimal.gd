# BaseAnimal.gd
# Base class for all animal AI behaviors in the Bark & Moss game
# This provides common functionality for animals like rabbits, birds, deer, etc.

class_name BaseAnimal
extends CharacterBody3D

# =============================================================================
# COMMON ANIMAL STATES
# =============================================================================

enum AnimalState {
	IDLE,
	WANDERING,
	FLEEING,
	DEAD
}

# =============================================================================
# SHARED PROPERTIES
# =============================================================================

## Current AI state of the animal
var current_state: AnimalState = AnimalState.WANDERING

## Health system
var max_health: float = 1.0
var current_health: float = max_health

## Movement and AI
var target_position: Vector3
var movement_center: Vector3  # Where the animal originated/patrols around
var direction_timer: float = 0.0
var flee_target: Node3D = null

## Physics
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

## Scene references for corpse spawning
var corpse_scene: PackedScene

# =============================================================================
# ABSTRACT PROPERTIES (to be overridden by subclasses)
# =============================================================================

## Movement speeds (override in subclasses)
var wander_speed: float = 2.0
var flee_speed: float = 4.0

## AI behavior parameters (override in subclasses)
var wander_radius: float = 10.0
var flee_distance: float = 8.0
var direction_change_time: float = 3.0
var detection_range: float = 6.0

# =============================================================================
# COMMON SIGNALS
# =============================================================================

signal animal_died(animal: BaseAnimal)
signal state_changed(old_state: AnimalState, new_state: AnimalState)

# =============================================================================
# NODE REFERENCES (to be set up by subclasses)
# =============================================================================

@onready var detection_area: Area3D
@onready var collision_shape: CollisionShape3D

# =============================================================================
# ENGINE CALLBACKS
# =============================================================================

func _ready() -> void:
	"""Initialize common animal setup. Call super._ready() in subclasses."""
	print(GameUtils.format_log(get_class(), "Initializing %s" % name))
	
	# Set up collision layers for animals
	GameUtils.setup_collision_layers(self, 
		GameConstants.PHYSICS_LAYERS.ANIMAL, 
		GameConstants.PHYSICS_LAYERS.TERRAIN,
		"BaseAnimal setup")
	
	# Add to animals group for identification
	add_to_group("animals")
	
	# Store the starting position as movement center
	movement_center = global_position
	
	# Initialize health
	current_health = max_health
	
	# Set up detection area signals if it exists
	_setup_detection_signals()
	
	# Initialize AI state
	_choose_new_target()
	
	print(GameUtils.format_log(get_class(), "%s ready at position %s" % [name, global_position]))

func _physics_process(delta: float) -> void:
	"""Handle movement and physics. Override movement logic in subclasses."""
	# Handle gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Update AI behavior
	_update_ai_behavior(delta)
	
	# Apply movement
	move_and_slide()

# =============================================================================
# AI BEHAVIOR SYSTEM
# =============================================================================

func _update_ai_behavior(delta: float) -> void:
	"""Main AI update loop. Can be overridden in subclasses for specialized behavior."""
	match current_state:
		AnimalState.IDLE:
			_handle_idle_state(delta)
		AnimalState.WANDERING:
			_handle_wandering_state(delta)
		AnimalState.FLEEING:
			_handle_fleeing_state(delta)
		AnimalState.DEAD:
			_handle_dead_state(delta)

func _handle_idle_state(delta: float) -> void:
	"""Handle idle behavior. Override in subclasses if needed."""
	velocity.x = 0
	velocity.z = 0
	
	direction_timer += delta
	if direction_timer >= direction_change_time * 0.5:  # Shorter idle time
		change_state(AnimalState.WANDERING)

func _handle_wandering_state(delta: float) -> void:
	"""Handle wandering behavior. Override in subclasses for specialized movement."""
	direction_timer += delta
	
	# Move towards target
	var direction = (target_position - global_position).normalized()
	velocity.x = direction.x * wander_speed
	velocity.z = direction.z * wander_speed
	
	# Check if we've reached the target or need to change direction
	if global_position.distance_to(target_position) < 2.0 or direction_timer >= direction_change_time:
		_choose_new_target()

func _handle_fleeing_state(delta: float) -> void:
	"""Handle fleeing behavior. Override in subclasses for specialized escape patterns."""
	if not is_instance_valid(flee_target):
		change_state(AnimalState.WANDERING)
		return
	
	# Check if we're far enough away to stop fleeing
	var distance_to_threat = GameUtils.safe_distance_to(self, flee_target)
	if distance_to_threat > flee_distance * 2:  # Stop fleeing when far enough
		change_state(AnimalState.WANDERING)
		return
	
	# Move away from the threat
	var flee_direction = (global_position - flee_target.global_position).normalized()
	velocity.x = flee_direction.x * flee_speed
	velocity.z = flee_direction.z * flee_speed

func _handle_dead_state(delta: float) -> void:
	"""Handle dead state. Should not normally be called since dead animals are removed."""
	velocity = Vector3.ZERO

# =============================================================================
# STATE MANAGEMENT
# =============================================================================

func change_state(new_state: AnimalState) -> void:
	"""Safely change the animal's state with proper cleanup."""
	if current_state == new_state:
		return
	
	var old_state = current_state
	current_state = new_state
	direction_timer = 0.0
	
	# Emit state change signal
	state_changed.emit(old_state, new_state)
	
	# Handle state entry logic
	_on_state_entered(new_state)
	
	print(GameUtils.format_log(get_class(), "%s changed state from %s to %s" % [
		name, 
		GameUtils.enum_to_string(AnimalState, old_state),
		GameUtils.enum_to_string(AnimalState, new_state)
	]))

func _on_state_entered(state: AnimalState) -> void:
	"""Called when entering a new state. Override in subclasses for specialized behavior."""
	match state:
		AnimalState.FLEEING:
			# When starting to flee, choose an escape target immediately
			if is_instance_valid(flee_target):
				_choose_flee_target()
		AnimalState.WANDERING:
			# When returning to wandering, clear flee target and choose new destination
			flee_target = null
			_choose_new_target()

# =============================================================================
# TARGET SELECTION (to be overridden by subclasses)
# =============================================================================

func _choose_new_target() -> void:
	"""Choose a new movement target. Override in subclasses for specialized behavior."""
	var angle: float = randf() * TAU
	var distance: float = randf() * wander_radius
	
	target_position = movement_center + Vector3(
		cos(angle) * distance,
		0,
		sin(angle) * distance
	)
	
	direction_timer = 0.0

func _choose_flee_target() -> void:
	"""Choose where to flee to. Override in subclasses for specialized escape patterns."""
	if not is_instance_valid(flee_target):
		return
	
	# Flee directly away from the threat
	var flee_direction = (global_position - flee_target.global_position).normalized()
	target_position = global_position + flee_direction * flee_distance

# =============================================================================
# THREAT DETECTION
# =============================================================================

func _setup_detection_signals() -> void:
	"""Set up detection area signals. Override in subclasses if needed."""
	if detection_area:
		GameUtils.safe_connect_signal(detection_area, "body_entered", self, "_on_detection_area_body_entered", "BaseAnimal detection")
		GameUtils.safe_connect_signal(detection_area, "body_exited", self, "_on_detection_area_body_exited", "BaseAnimal detection")

func _on_detection_area_body_entered(body: Node3D) -> void:
	"""Handle when a potential threat enters detection range."""
	if _is_threat(body) and current_state != AnimalState.DEAD:
		flee_target = body
		change_state(AnimalState.FLEEING)
		print(GameUtils.format_log(get_class(), "%s detected threat: %s" % [name, body.name]))

func _on_detection_area_body_exited(body: Node3D) -> void:
	"""Handle when a threat leaves detection range."""
	if body == flee_target:
		# Don't immediately stop fleeing - let the flee handler decide when it's safe
		pass

func _is_threat(body: Node3D) -> bool:
	"""Determine if a body is a threat. Override in subclasses for specialized threat detection."""
	return body.is_in_group("human_player") or body.is_in_group("dog_player")

# =============================================================================
# DAMAGE AND DEATH SYSTEM
# =============================================================================

func take_damage(amount: float) -> void:
	"""Handle taking damage. Can be overridden in subclasses for specialized damage handling."""
	if current_state == AnimalState.DEAD:
		return
	
	current_health -= amount
	print(GameUtils.format_log(get_class(), "%s took %s damage, health: %s/%s" % [name, amount, current_health, max_health]))
	
	if current_health <= 0:
		die()

func die() -> void:
	"""Handle animal death. Can be overridden in subclasses for specialized death behavior."""
	if current_state == AnimalState.DEAD:
		return
	
	print(GameUtils.format_log(get_class(), "%s died at position %s" % [name, global_position]))
	change_state(AnimalState.DEAD)
	
	# Spawn corpse if available
	_spawn_corpse()
	
	# Emit death signal
	animal_died.emit(self)
	
	# Remove the animal
	queue_free()

func _spawn_corpse() -> void:
	"""Spawn a corpse at the animal's location. Override in subclasses to set corpse_scene."""
	if not corpse_scene:
		print(GameUtils.format_log(get_class(), "No corpse scene set for %s" % name, "WARNING"))
		return
	
	var corpse: Node3D = GameUtils.safe_instantiate_scene(corpse_scene.resource_path, "BaseAnimal corpse spawning")
	if corpse:
		get_tree().current_scene.add_child(corpse)
		corpse.global_position = global_position
		print(GameUtils.format_log(get_class(), "Spawned corpse for %s" % name))

# =============================================================================
# UTILITY METHODS
# =============================================================================

func get_state_name() -> String:
	"""Get the current state as a string for debugging."""
	return GameUtils.enum_to_string(AnimalState, current_state)

func is_alive() -> bool:
	"""Check if the animal is alive."""
	return current_state != AnimalState.DEAD and current_health > 0

func get_movement_speed() -> float:
	"""Get the current movement speed based on state."""
	match current_state:
		AnimalState.FLEEING:
			return flee_speed
		AnimalState.WANDERING:
			return wander_speed
		_:
			return 0.0

## Responds to bark sounds - implement in subclasses if the animal should react to barking
func respond_to_bark(bark_source: Node3D) -> void:
	pass

## Returns debug information about the animal
func get_debug_info() -> Dictionary:
	return {
		"name": name,
		"state": get_state_name(),
		"health": "%s/%s" % [current_health, max_health],
		"position": global_position,
		"target": target_position,
		"movement_center": movement_center,
		"flee_target": flee_target.name if is_instance_valid(flee_target) else "None"
	} 
