class_name Deer
extends CharacterBody3D

# --- Constants ---
const GRAZE_SPEED: float = 1.0       # Slow movement while grazing
const FLEE_SPEED: float = 9.0        # Faster than dog (8.0) but not too fast
const GRAZE_RADIUS: float = 15.0     # Area to graze within
const FLEE_DISTANCE: float = 12.0    # Flees earlier than rabbits
const DIRECTION_CHANGE_TIME: float = 4.0
const FLEE_DETECTION_RANGE: float = 10.0  # Detects threats from farther away
const GRAZE_TIME: float = 3.0        # How long to graze in one spot

# Animation constants
const ANIMATION_BLEND_TIME: float = 0.2  # Time to blend between animations

# Available animation names from the Deer model
const ANIM_ATTACK_HEADBUTT: String = "Attack_Headbutt"     # Headbutt attack
const ANIM_ATTACK_KICK: String = "Attack_Kick"             # Kick attack
const ANIM_DEATH: String = "Death"                         # Death animation
const ANIM_EATING: String = "Eating"                       # Eating/grazing animation
const ANIM_GALLOP: String = "Gallop"                       # Fast running animation
const ANIM_GALLOP_JUMP: String = "Gallop_Jump"             # Jumping while running
const ANIM_IDLE_HIT_REACT_LEFT: String = "Idle_HitReact_Left"   # Left hit reaction
const ANIM_IDLE_HIT_REACT_RIGHT: String = "Idle_HitReact_Right" # Right hit reaction
const ANIM_JUMP_TO_IDLE: String = "Jump_ToIdle"            # Landing from jump
const ANIM_WALK: String = "Walk"                           # Walking animation
const ANIM_IDLE_HEAD_LOW: String = "Idle_Headlow"          # Head down grazing pose
const ANIM_IDLE_2: String = "Idle_2"                       # Alternative idle
const ANIM_IDLE: String = "Idle"                           # Default idle pose

# Movement speed thresholds for animation selection
const WALK_THRESHOLD: float = 0.1                          # Minimum speed to trigger walk
const GALLOP_THRESHOLD: float = 6.0                        # Speed threshold for gallop vs walk

# --- Node References ---
@onready var deer_model: Node3D = $DeerModel
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var detection_area: Area3D = $DetectionArea
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

# --- State Management ---
enum State {
	GRAZING,
	WANDERING,
	FLEEING,
	DEAD
}

var current_state: State = State.GRAZING
var target_position: Vector3
var graze_center: Vector3
var direction_timer: float = 0.0
var graze_timer: float = 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var flee_target: Node3D = null

# --- Health ---
var max_health: float = 1.0  # Deer die in one hit from arrows
var current_health: float = max_health

# --- Corpse system ---
var corpse_scene: PackedScene = preload("res://scenes/DeerCorpse.tscn")

# --- Animation system ---
var animation_player: AnimationPlayer
var current_animation: String = ""
var is_grazing: bool = false
var is_attacking: bool = false


func _ready() -> void:
	"""Initialize the deer with proper collision layers and AI setup."""
	# Set up collision layers - deer are on animal layer
	collision_layer = 8     # Animal layer
	collision_mask = 11     # Terrain (1) + Environment (2) + Animals (8) = 11
	
	# Add to animals group for identification
	add_to_group("animals")
	add_to_group("deer")
	
	# Store the starting position as graze center
	graze_center = global_position
	
	# Set up detection area for player proximity
	if detection_area:
		detection_area.body_entered.connect(_on_detection_area_body_entered)
		detection_area.body_exited.connect(_on_detection_area_body_exited)
	
	# Initialize animation system
	_setup_animations()
	
	# Initialize grazing
	graze_timer = GRAZE_TIME
	_choose_new_graze_spot()
	



func _physics_process(delta: float) -> void:
	"""Handle deer physics and AI updates."""
	if current_state == State.DEAD:
		return
	
	# Add gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Update AI state
	_update_ai(delta)
	
	# Move the deer
	move_and_slide()
	
	# Update animations based on movement and state
	_update_movement_animation()


func _setup_animations() -> void:
	"""Initialize the animation system by finding the AnimationPlayer in the deer model."""
	# Look for AnimationPlayer in the deer model
	if deer_model:
		animation_player = _find_animation_player_recursive(deer_model)
		if animation_player:
			# Start with idle animation
			_play_animation(ANIM_IDLE)


func _find_animation_player_recursive(node: Node) -> AnimationPlayer:
	"""Recursively search for an AnimationPlayer node in the deer model."""
	if node is AnimationPlayer:
		return node as AnimationPlayer
	
	for child in node.get_children():
		var result: AnimationPlayer = _find_animation_player_recursive(child)
		if result:
			return result
	
	return null


func _update_movement_animation() -> void:
	"""Update deer animations based on current state and movement."""
	if not animation_player:
		return
	
	# Calculate movement speed first
	var speed: float = Vector2(velocity.x, velocity.z).length()
	var target_animation: String = ""
	
	# Animation based on deer state and movement - prioritize current state
	match current_state:
		State.GRAZING:
			# Use eating animation when actively grazing, only if we're actually in grazing mode
			if is_grazing:
				target_animation = ANIM_EATING
			else:
				# Transitioning to grazing, use idle for now
				target_animation = ANIM_IDLE
		State.WANDERING:
			# Reset grazing and attacking flags during wandering
			is_grazing = false
			is_attacking = false
			
			if speed > WALK_THRESHOLD:
				target_animation = ANIM_WALK
			else:
				# Use a simple idle instead of random variants to avoid conflicts
				target_animation = ANIM_IDLE
		State.FLEEING:
			# Reset all action flags during fleeing - this is crucial!
			is_grazing = false
			is_attacking = false
			
			if not is_on_floor():
				target_animation = ANIM_GALLOP_JUMP
			elif speed > GALLOP_THRESHOLD:
				target_animation = ANIM_GALLOP
			else:
				target_animation = ANIM_WALK
		State.DEAD:
			target_animation = ANIM_DEATH
	
	# Always try to play the appropriate animation - allow restarts if animation finished
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
		if animation_name in [ANIM_WALK, ANIM_GALLOP, ANIM_IDLE, ANIM_IDLE_2, ANIM_EATING]:
			var animation_resource: Animation = animation_player.get_animation(animation_name)
			if animation_resource:
				animation_resource.loop_mode = Animation.LOOP_LINEAR
	else:

		
		# Try fallback alternatives for common animations
		var alternatives: Array[String] = []
		match animation_name:
			ANIM_IDLE:
				alternatives = ["Idle", "idle", "Default", "default"]
			ANIM_IDLE_2:
				alternatives = ["Idle_2", "idle_2", "Idle2", "idle2"]
			ANIM_IDLE_HEAD_LOW:
				alternatives = ["Idle_Headlow", "idle_headlow", "grazing", "Grazing"]
			ANIM_WALK:
				alternatives = ["Walk", "walking", "walk", "Walking"]
			ANIM_GALLOP:
				alternatives = ["Gallop", "gallop", "Run", "run", "Running", "running", "Sprint", "sprint", "FastRun", "fastrun"]
			ANIM_EATING:
				alternatives = ["Eating", "Eat", "eat", "grazing", "graze", "Grazing", "Graze"]
			ANIM_DEATH:
				alternatives = ["Death", "Die", "die", "death"]
			ANIM_ATTACK_HEADBUTT:
				alternatives = ["Attack_Headbutt", "headbutt", "attack", "Attack", "Headbutt"]
			ANIM_ATTACK_KICK:
				alternatives = ["Attack_Kick", "kick", "Kick", "attack", "Attack"]
			ANIM_GALLOP_JUMP:
				alternatives = ["Gallop_Jump", "gallop_jump", "Jump", "jump", "Jumping", "jumping", "Run_Jump", "run_jump"]
		
		# Try to find an alternative
		var found_alternative: bool = false
		for alt in alternatives:
			if animation_player.has_animation(alt):
				animation_player.play(alt, ANIMATION_BLEND_TIME)
				current_animation = alt
				
				# Ensure fallback movement animations loop properly too
				if alt.to_lower().contains("walk") or alt.to_lower().contains("gallop") or alt.to_lower().contains("idle") or alt.to_lower().contains("eat"):
					var animation_resource: Animation = animation_player.get_animation(alt)
					if animation_resource:
						animation_resource.loop_mode = Animation.LOOP_LINEAR
				
				found_alternative = true
				break
		
		if not found_alternative:
			# If no animation found, try to play the first available animation
			var animation_list: PackedStringArray = animation_player.get_animation_list()
			if animation_list.size() > 0:
				animation_player.play(animation_list[0], ANIMATION_BLEND_TIME)
				current_animation = animation_list[0]
	



func _update_ai(delta: float) -> void:
	"""Update the deer's AI behavior based on current state."""
	match current_state:
		State.GRAZING:
			_handle_grazing(delta)
		State.WANDERING:
			_handle_wandering(delta)
		State.FLEEING:
			_handle_fleeing(delta)


func _handle_grazing(delta: float) -> void:
	"""Handle grazing behavior - deer stay in one spot eating."""
	graze_timer -= delta
	is_grazing = true  # Set grazing state for animation
	
	# Stay still while grazing
	velocity.x = 0.0
	velocity.z = 0.0
	
	# Occasionally look around by rotating slightly
	var look_rotation: float = sin(Time.get_unix_time_from_system() * 2.0) * 0.3
	rotation.y = look_rotation
	
	# After grazing time, move to a new spot
	if graze_timer <= 0.0:
		is_grazing = false  # Stop grazing animation state
		current_state = State.WANDERING
		_choose_new_graze_spot()
		direction_timer = DIRECTION_CHANGE_TIME


func _handle_wandering(delta: float) -> void:
	"""Handle wandering behavior - deer move slowly around their graze area."""
	direction_timer -= delta
	is_grazing = false  # Ensure grazing state is off
	
	# Move towards target
	var direction: Vector3 = (target_position - global_position).normalized()
	direction.y = 0  # Keep movement horizontal
	
	velocity.x = direction.x * GRAZE_SPEED
	velocity.z = direction.z * GRAZE_SPEED
	
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
	
	# Check if reached target or need new direction
	if global_position.distance_to(target_position) < 2.0 or direction_timer <= 0.0:
		current_state = State.GRAZING
		graze_timer = GRAZE_TIME
		direction_timer = DIRECTION_CHANGE_TIME


func _handle_fleeing(delta: float) -> void:
	"""Handle fleeing behavior - deer run away from threats."""
	is_grazing = false  # Stop grazing when fleeing
	is_attacking = false  # Stop attacking when fleeing
	
	if flee_target and is_instance_valid(flee_target):
		# Calculate escape direction (away from threat)
		var escape_direction: Vector3 = (global_position - flee_target.global_position).normalized()
		escape_direction.y = 0  # Keep movement horizontal
		
		# Move away from the threat
		velocity.x = escape_direction.x * FLEE_SPEED
		velocity.z = escape_direction.z * FLEE_SPEED
		
		# Face flee direction - avoid colinear vectors and same position
		if escape_direction.length() > 0.1:
			var target_look_pos: Vector3 = global_position + escape_direction
			
			# Ensure target position is sufficiently different from current position
			if global_position.distance_to(target_look_pos) > 0.01:
				var up_vector: Vector3 = Vector3.UP
				
				# Check if escape direction is parallel to up vector (avoid colinear warning)
				if abs(escape_direction.dot(up_vector)) > 0.99:
					up_vector = Vector3.FORWARD  # Use forward as up vector instead
				
				look_at(target_look_pos, up_vector)
		
		# Check if far enough away to stop fleeing
		var distance_to_threat: float = global_position.distance_to(flee_target.global_position)
		if distance_to_threat > FLEE_DISTANCE * 2.0:  # Stop fleeing when twice the detection distance
			current_state = State.GRAZING
			flee_target = null
			graze_timer = GRAZE_TIME
			is_grazing = false  # Will be set to true when grazing starts
	else:
		# No valid threat, return to grazing
		current_state = State.GRAZING
		flee_target = null
		graze_timer = GRAZE_TIME
		is_grazing = false  # Will be set to true when grazing starts


func _choose_new_graze_spot() -> void:
	"""Choose a new position within the grazing area."""
	var angle: float = randf() * TAU
	var distance: float = randf() * GRAZE_RADIUS
	
	target_position = graze_center + Vector3(
		cos(angle) * distance,
		0,
		sin(angle) * distance
	)


func _on_detection_area_body_entered(body: Node3D) -> void:
	"""Detect when a player approaches."""
	if body.is_in_group("human_player") or body.is_in_group("dog_player"):
		flee_target = body
		current_state = State.FLEEING


func _on_detection_area_body_exited(body: Node3D) -> void:
	"""Handle when a player moves away."""
	if body == flee_target:
		# Don't immediately stop fleeing, let the flee handler decide
		pass


func take_damage(damage: float) -> void:
	"""Handle taking damage and death."""
	if current_state == State.DEAD:
		return
	
	current_health -= damage
	
	# Play hit reaction animation (randomly choose left or right)
	if current_health > 0:
		var hit_reaction: String = ANIM_IDLE_HIT_REACT_LEFT if randi() % 2 == 0 else ANIM_IDLE_HIT_REACT_RIGHT
		_play_animation(hit_reaction)
		
		# Return to normal animation after a short delay
		var hit_duration: float = 0.5
		get_tree().create_timer(hit_duration).timeout.connect(func(): _update_movement_animation())

	else:
		# Death
		_die()


func _die() -> void:
	"""Handle deer death with animation and corpse spawning."""
	current_state = State.DEAD
	current_health = 0.0
	is_grazing = false
	
	# Play death animation
	_play_animation(ANIM_DEATH)
	
	# Disable collision
	collision_layer = 0
	collision_mask = 0
	
	# Spawn corpse after death animation
	var death_duration: float = 2.0  # Duration of death animation
	var timer: Timer = Timer.new()
	add_child(timer)
	timer.wait_time = death_duration
	timer.timeout.connect(func():
		_spawn_corpse()
		queue_free()
	)
	timer.start()


func _spawn_corpse() -> void:
	"""Spawn a deer corpse at the current position."""
	if corpse_scene:
		var corpse: Node3D = corpse_scene.instantiate()
		get_tree().current_scene.add_child(corpse)
		corpse.global_position = global_position
		corpse.global_rotation = global_rotation


func get_state_string() -> String:
	"""Get human-readable state for debugging."""
	match current_state:
		State.GRAZING:
			return "GRAZING"
		State.WANDERING:
			return "WANDERING" 
		State.FLEEING:
			return "FLEEING"
		State.DEAD:
			return "DEAD"
		_:
			return "UNKNOWN" 
