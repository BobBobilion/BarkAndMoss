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
# LOD OPTIMIZATION
# =============================================================================

## LOD state tracking
var lod_level: int = 0
var ai_update_timer: float = 0.0
var animations_enabled: bool = true
var ai_enabled: bool = true

## Animation cache for performance
var animation_player: AnimationPlayer
var current_animation: String = ""
var animation_cache: Dictionary = {}  # Cache animation lookups

# =============================================================================
# MULTIPLAYER SYNC
# =============================================================================

## Network properties
var is_remote: bool = false
var interpolation_speed: float = 10.0

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
	
	# Cache animation player for performance
	_cache_animation_player()
	
	# Set up detection area signals if it exists
	_setup_detection_signals()
	
	# Initialize AI state
	_choose_new_target()
	
	print(GameUtils.format_log(get_class(), "%s ready at position %s" % [name, global_position]))

func _physics_process(delta: float) -> void:
	"""Optimized physics process with LOD awareness."""
	# Check if we should process based on LOD
	var lod_meta = get_meta("current_lod", 0)
	if lod_meta >= 3:  # Disabled LOD
		return
	
	# Handle gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Handle remote interpolation for multiplayer
	if is_remote or has_meta("target_position"):
		_interpolate_remote_position(delta)
		return
	
	# Check if AI should update based on LOD timer
	var should_update_ai = false
	if ai_enabled:
		ai_update_timer += delta
		var update_interval = _get_ai_update_interval()
		if ai_update_timer >= update_interval:
			should_update_ai = true
			ai_update_timer = 0.0
	
	# Update AI behavior only when needed
	if should_update_ai:
		_update_ai_behavior(delta * ai_update_timer)  # Pass accumulated time
	
	# Apply movement
	move_and_slide()
	
	# Update animations if enabled
	if animations_enabled and get_meta("animations_enabled", true):
		_update_movement_animation()

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
	
	# Spawn corpse if available (only if not a synced death)
	if not get_meta("synced_death", false):
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
		"flee_target": flee_target.name if is_instance_valid(flee_target) else "None",
		"lod_level": lod_level,
		"ai_enabled": ai_enabled,
		"animations_enabled": animations_enabled
	}

# =============================================================================
# LOD OPTIMIZATION METHODS
# =============================================================================

func _cache_animation_player() -> void:
	"""Cache the animation player for performance."""
	animation_player = _find_animation_player_recursive(self)
	
	if animation_player:
		# Cache all animation names for faster lookup
		var animations = animation_player.get_animation_list()
		for anim_name in animations:
			animation_cache[anim_name.to_lower()] = anim_name

func _find_animation_player_recursive(node: Node) -> AnimationPlayer:
	"""Recursively find AnimationPlayer in children."""
	if node is AnimationPlayer:
		return node
	
	for child in node.get_children():
		var result = _find_animation_player_recursive(child)
		if result:
			return result
	
	return null

func _get_ai_update_interval() -> float:
	"""Get AI update interval based on LOD level."""
	match get_meta("current_lod", 0):
		0:
			return 0.1  # Close - 10Hz
		1:
			return 0.3  # Medium - ~3Hz
		2:
			return 1.0  # Far - 1Hz
		_:
			return 999.0  # Effectively disabled

func _interpolate_remote_position(delta: float) -> void:
	"""Smoothly interpolate remote animal position."""
	if has_meta("target_position"):
		var target_pos = get_meta("target_position")
		global_position = global_position.lerp(target_pos, interpolation_speed * delta)
	
	if has_meta("target_rotation"):
		var target_rot = get_meta("target_rotation")
		rotation.y = lerp_angle(rotation.y, target_rot, interpolation_speed * delta)

func _update_movement_animation() -> void:
	"""Update animations based on movement. Override in subclasses."""
	pass

func play_animation_optimized(animation_name: String, blend_time: float = 0.2) -> void:
	"""Play animation with caching and LOD awareness."""
	if not animation_player or not animations_enabled:
		return
	
	# Skip if already playing
	if current_animation == animation_name and animation_player.is_playing():
		return
	
	# Try direct name first
	if animation_player.has_animation(animation_name):
		animation_player.play(animation_name, blend_time)
		current_animation = animation_name
		return
	
	# Try cached lowercase lookup
	var lower_name = animation_name.to_lower()
	if animation_cache.has(lower_name):
		animation_player.play(animation_cache[lower_name], blend_time)
		current_animation = animation_cache[lower_name]
		return

func set_lod_level(level: int) -> void:
	"""Set LOD level for this animal."""
	lod_level = level
	set_meta("current_lod", level)
	
	# Adjust behavior based on LOD
	match level:
		0:  # Close
			ai_enabled = true
			animations_enabled = true
			set_physics_process(true)
		1:  # Medium
			ai_enabled = true
			animations_enabled = true
			set_physics_process(true)
		2:  # Far
			ai_enabled = true
			animations_enabled = false
			set_physics_process(true)
		3:  # Disabled
			ai_enabled = false
			animations_enabled = false
			set_physics_process(false)

# =============================================================================
# MULTIPLAYER SYNC METHODS
# =============================================================================

func get_state_string() -> String:
	"""Get current state as string for network sync."""
	match current_state:
		AnimalState.IDLE:
			return "IDLE"
		AnimalState.WANDERING:
			return "WANDERING"
		AnimalState.FLEEING:
			return "FLEEING"
		AnimalState.DEAD:
			return "DEAD"
		_:
			return "UNKNOWN"

func set_state_from_string(state: String) -> void:
	"""Set state from string for network sync."""
	match state:
		"IDLE":
			current_state = AnimalState.IDLE
		"WANDERING":
			current_state = AnimalState.WANDERING
		"FLEEING":
			current_state = AnimalState.FLEEING
		"DEAD":
			current_state = AnimalState.DEAD
