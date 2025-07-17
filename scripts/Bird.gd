class_name Bird
extends CharacterBody3D

# --- Constants ---
const FLY_SPEED: float = 3.0
const FLEE_SPEED: float = 6.0
const HOVER_HEIGHT: float = 4.0
const PATROL_RADIUS: float = 15.0
const FLEE_DISTANCE: float = 12.0
const DIRECTION_CHANGE_TIME: float = 4.0
const BARK_DETECTION_RANGE: float = 10.0
const HEIGHT_VARIANCE: float = 2.0  # How much birds can vary in flight height

# Animation constants
const ANIMATION_BLEND_TIME: float = 0.2  # Time to blend between animations

# Available animation names (future-proofed for when bird models get animations)
const ANIM_FLY: String = "Fly"                           # Flying animation
const ANIM_IDLE: String = "Idle"                         # Idle/perched animation
const ANIM_DEATH: String = "Death"                       # Death animation
const ANIM_FLEE: String = "Flee"                         # Scared flying animation
const ANIM_GLIDE: String = "Glide"                       # Gliding animation
const ANIM_PECK: String = "Peck"                         # Pecking/eating animation
const ANIM_TAKE_OFF: String = "TakeOff"                  # Taking off animation
const ANIM_LAND: String = "Land"                         # Landing animation

# Movement speed thresholds for animation selection
const FLY_THRESHOLD: float = 0.1                         # Minimum speed to trigger flying
const FLEE_THRESHOLD: float = 4.0                        # Speed threshold for flee vs normal fly

# --- Node References ---
@onready var dove_model: Node3D = $DoveModel
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var bark_detection_area: Area3D = $BarkDetectionArea

# --- State Management ---
enum State {
	FLYING,
	FLEEING,
	DEAD
}

var current_state: State = State.FLYING
var target_position: Vector3
var patrol_center: Vector3
var direction_timer: float = 0.0
var flee_target: Node3D = null
var base_flight_height: float

# --- Health ---
var max_health: float = 1.0  # Birds die in one hit
var current_health: float = max_health

# --- Corpse system ---
var corpse_scene: PackedScene = preload("res://scenes/BirdCorpse.tscn")

# --- Animation system ---
var animation_player: AnimationPlayer
var current_animation: String = ""

# --- World reference for terrain height ---
var world_generator: WorldGenerator


func _ready() -> void:
	"""Initialize the bird with proper collision layers and flying AI setup."""
	# Set up collision layers - birds are on animal layer
	collision_layer = 8     # Animal layer
	collision_mask = 11     # Terrain (1) + Environment (2) + Animals (8) = 11
	
	# Add to animals group for identification
	add_to_group("animals")
	add_to_group("birds")
	
	# Initialize animation system
	_setup_animations()
	
	# Store the starting position as patrol center
	patrol_center = global_position
	base_flight_height = global_position.y
	
	# Set up bark detection area
	if bark_detection_area:
		# We'll connect to dog bark events through a different method
		pass
	
	# Find world generator for terrain height reference
	world_generator = get_tree().get_first_node_in_group("world_generator")
	if not world_generator:
		# Try to find it by path
		var main_scene = get_tree().current_scene
		if main_scene.has_node("WorldGenerator"):
			world_generator = main_scene.get_node("WorldGenerator")
	
	# Initialize flying pattern
	_choose_new_patrol_target()
	



func _physics_process(delta: float) -> void:
	"""Handle bird physics and AI updates."""
	if current_state == State.DEAD:
		return
	
	# Birds don't need gravity - they fly!
	velocity.y = 0.0
	
	# Update AI state
	_update_ai(delta)
	
	# Move the bird
	move_and_slide()
	
	# Update animations based on movement and state
	_update_movement_animation()


func _update_ai(delta: float) -> void:
	"""Update the bird's AI behavior based on current state."""
	match current_state:
		State.FLYING:
			_handle_flying(delta)
		State.FLEEING:
			_handle_fleeing(delta)


func _handle_flying(delta: float) -> void:
	"""Handle normal flying behavior - patrol around in the air."""
	direction_timer -= delta
	
	# Check if we reached our target or need a new direction
	if direction_timer <= 0 or global_position.distance_to(target_position) < 2.0:
		_choose_new_patrol_target()
		direction_timer = DIRECTION_CHANGE_TIME
	
	# Move towards target
	var direction: Vector3 = (target_position - global_position).normalized()
	
	velocity.x = direction.x * FLY_SPEED
	velocity.y = direction.y * FLY_SPEED * 0.5  # Slower vertical movement
	velocity.z = direction.z * FLY_SPEED
	
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
	"""Handle fleeing behavior - fly away from bark source."""
	if not is_instance_valid(flee_target):
		# No valid threat, return to flying
		current_state = State.FLYING
		_choose_new_patrol_target()
		return
	
	# Calculate flee direction (away from bark source)
	var flee_direction: Vector3 = (global_position - flee_target.global_position).normalized()
	
	# Add upward component to flee higher
	flee_direction.y = abs(flee_direction.y) + 0.5
	flee_direction = flee_direction.normalized()
	
	# Fly away from threat
	velocity.x = flee_direction.x * FLEE_SPEED
	velocity.y = flee_direction.y * FLEE_SPEED * 0.7  # Moderate upward movement
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
		current_state = State.FLYING
		flee_target = null
		_choose_new_patrol_target()


func _choose_new_patrol_target() -> void:
	"""Choose a new random position to fly towards within the patrol radius."""
	var random_offset: Vector3 = Vector3(
		randf_range(-PATROL_RADIUS, PATROL_RADIUS),
		randf_range(-HEIGHT_VARIANCE, HEIGHT_VARIANCE),
		randf_range(-PATROL_RADIUS, PATROL_RADIUS)
	)
	
	target_position = patrol_center + random_offset
	
	# Ensure we maintain a reasonable flight height above terrain
	if world_generator and world_generator.has_method("get_terrain_height_at_position"):
		var terrain_height: float = world_generator.get_terrain_height_at_position(target_position)
		var min_height: float = terrain_height + HOVER_HEIGHT
		if target_position.y < min_height:
			target_position.y = min_height + randf_range(0, HEIGHT_VARIANCE)
	else:
		# Fallback: maintain base flight height
		target_position.y = max(target_position.y, base_flight_height)


func respond_to_bark(bark_source: Node3D) -> void:
	"""Called when a dog barks nearby - birds should flee."""
	if current_state == State.DEAD:
		return
	
	var distance: float = global_position.distance_to(bark_source.global_position)
	if distance <= BARK_DETECTION_RANGE:
		current_state = State.FLEEING
		flee_target = bark_source


func take_damage(amount: float) -> void:
	"""Handle taking damage from arrows."""
	if current_state == State.DEAD:
		return
	
	current_health -= amount
	
	if current_health <= 0:
		die()


func die() -> void:
	"""Handle bird death - spawn corpse and remove bird."""
	if current_state == State.DEAD:
		return
	
	current_state = State.DEAD
	
	# Spawn a corpse at this location
	_spawn_corpse()
	
	# Remove the bird
	queue_free()


func _spawn_corpse() -> void:
	"""Spawn a bird corpse that falls to the ground."""
	# For now, let's spawn the bird corpse at ground level
	var corpse_position: Vector3 = global_position
	
	# Try to get ground height
	if world_generator and world_generator.has_method("get_terrain_height_at_position"):
		var ground_height: float = world_generator.get_terrain_height_at_position(corpse_position)
		corpse_position.y = ground_height + 0.2  # Slightly above ground
	else:
		corpse_position.y = 0.5  # Fallback height
	
	# Try to spawn corpse if the scene exists
	if corpse_scene:
		var corpse: Node3D = corpse_scene.instantiate()
		get_tree().current_scene.add_child(corpse)
		corpse.global_position = corpse_position


func get_state_name() -> String:
	"""Helper function to get the current state as a string for debugging."""
	match current_state:
		State.FLYING:
			return "Flying"
		State.FLEEING:
			return "Fleeing"
		State.DEAD:
			return "Dead"
		_:
			return "Unknown"


func _setup_animations() -> void:
	"""Initialize the animation system by finding the AnimationPlayer in the bird model."""
	# Look for AnimationPlayer in the bird model
	if dove_model:
		animation_player = _find_animation_player_recursive(dove_model)
		if animation_player:
			# Start with idle animation
			_play_animation(ANIM_IDLE)


func _find_animation_player_recursive(node: Node) -> AnimationPlayer:
	"""Recursively search for an AnimationPlayer node in the bird model."""
	if node is AnimationPlayer:
		return node as AnimationPlayer
	
	for child in node.get_children():
		var result: AnimationPlayer = _find_animation_player_recursive(child)
		if result:
			return result
	
	return null


func _update_movement_animation() -> void:
	"""Update bird animations based on current state and movement."""
	if not animation_player:
		return
	
	# Calculate movement speed first
	var speed: float = Vector2(velocity.x, velocity.z).length()
	var target_animation: String = ""
	
	# Animation based on bird state and movement
	match current_state:
		State.FLYING:
			if speed > FLEE_THRESHOLD:
				target_animation = ANIM_FLEE  # Fast evasive flying
			elif speed > FLY_THRESHOLD:
				target_animation = ANIM_FLY   # Normal flying
			else:
				target_animation = ANIM_GLIDE  # Hovering/gliding
		State.FLEEING:
			target_animation = ANIM_FLEE
		State.DEAD:
			target_animation = ANIM_DEATH
	
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
		if animation_name in [ANIM_FLY, ANIM_FLEE, ANIM_GLIDE, ANIM_IDLE, ANIM_PECK]:
			var animation_resource: Animation = animation_player.get_animation(animation_name)
			if animation_resource:
				animation_resource.loop_mode = Animation.LOOP_LINEAR
	else:
		# Try fallback alternatives for common animations
		var alternatives: Array[String] = []
		match animation_name:
			ANIM_IDLE:
				alternatives = ["Idle", "idle", "Perch", "perch", "Rest", "rest"]
			ANIM_FLY:
				alternatives = ["Fly", "fly", "Flying", "flying", "Flap", "flap", "Flight", "flight"]
			ANIM_FLEE:
				alternatives = ["Flee", "flee", "Escape", "escape", "FastFly", "fastfly", "Panic", "panic", "Fly", "fly"]
			ANIM_GLIDE:
				alternatives = ["Glide", "glide", "Hover", "hover", "Soar", "soar", "Fly", "fly"]
			ANIM_DEATH:
				alternatives = ["Death", "death", "Die", "die", "Fall", "fall"]
			ANIM_PECK:
				alternatives = ["Peck", "peck", "Eat", "eat", "Feed", "feed"]
			ANIM_TAKE_OFF:
				alternatives = ["TakeOff", "takeoff", "Launch", "launch", "Fly", "fly"]
			ANIM_LAND:
				alternatives = ["Land", "land", "Landing", "landing", "Perch", "perch"]
		
		# Try to find an alternative
		for alt in alternatives:
			if animation_player.has_animation(alt):
				animation_player.play(alt, ANIMATION_BLEND_TIME)
				current_animation = alt
				
				# Ensure fallback movement animations loop properly too
				if alt.to_lower().contains("fly") or alt.to_lower().contains("glide") or alt.to_lower().contains("idle") or alt.to_lower().contains("hover"):
					var animation_resource: Animation = animation_player.get_animation(alt)
					if animation_resource:
						animation_resource.loop_mode = Animation.LOOP_LINEAR
				
				return
		
		# If no animation found, try to play the first available animation
		var animation_list: PackedStringArray = animation_player.get_animation_list()
		if animation_list.size() > 0:
			animation_player.play(animation_list[0], ANIMATION_BLEND_TIME)
			current_animation = animation_list[0] 