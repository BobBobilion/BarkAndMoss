class_name AnimationController
extends Node

# --- Constants ---
const ANIMATION_BLEND_TIME: float = 0.2

# Animation names from the Adventurer model
const ANIM_IDLE: String = "CharacterArmature|Idle_Neutral"
const ANIM_WALK: String = "CharacterArmature|Walk"
const ANIM_RUN: String = "CharacterArmature|Run"
const ANIM_JUMP: String = "CharacterArmature|Roll"
const ANIM_CHOP: String = "CharacterArmature|Sword_Slash"
const ANIM_INTERACT: String = "CharacterArmature|Interact"
const ANIM_HIT_RECEIVE: String = "CharacterArmature|HitRecieve"
const ANIM_HIT_RECEIVE_2: String = "CharacterArmature|HitRecieve_2"
const ANIM_DEATH: String = "CharacterArmature|Death"
const ANIM_PUNCH_LEFT: String = "CharacterArmature|Punch_Left"
const ANIM_PUNCH_RIGHT: String = "CharacterArmature|Punch_Right"
const ANIM_KICK_LEFT: String = "CharacterArmature|Kick_Left"
const ANIM_KICK_RIGHT: String = "CharacterArmature|Kick_Right"
const ANIM_WAVE: String = "CharacterArmature|Wave"

# Gun-aim style bow animations (using existing animations that look gun-like)
const ANIM_GUN_AIM_IDLE: String = "CharacterArmature|Idle_Neutral"     # Idle while aiming (gun-style)
const ANIM_GUN_AIM_DRAW: String = "CharacterArmature|Interact"         # Drawing/raising the bow (gun-style)
const ANIM_GUN_AIM_HOLD: String = "CharacterArmature|Punch_Right"      # Holding aim position (gun-style)
const ANIM_GUN_AIM_FIRE: String = "CharacterArmature|Punch_Left"       # Firing animation (gun-style)
const ANIM_GUN_AIM_LOWER: String = "CharacterArmature|Wave"            # Lowering the bow after firing

# Movement speed thresholds
const WALK_THRESHOLD: float = 0.1
const RUN_THRESHOLD: float = 4.0

# --- Properties ---
var adventurer_model: Node3D
var animation_player: AnimationPlayer
var current_animation: String = ""
var is_aiming: bool = false  # Track aiming state for gun-aim animations

# --- Initialization ---
func setup(p_adventurer_model: Node3D) -> void:
	self.adventurer_model = p_adventurer_model
	if adventurer_model:
		animation_player = _find_animation_player(adventurer_model)
		if animation_player:
			play_animation(ANIM_IDLE)
		else:
			push_error("AnimationController: No AnimationPlayer found in the adventurer model.")
	else:
		push_error("AnimationController: Adventurer model not assigned.")

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result: AnimationPlayer = _find_animation_player(child)
		if result:
			return result
	return null

# --- Public Methods ---
func update_movement_animation(velocity: Vector3, is_on_floor: bool, current_speed: float) -> void:
	"""Update movement animations, but respect gun-aim state."""
	if not animation_player: 
		return
	
	# Don't override gun-aim animations with movement animations
	if is_aiming:
		return
	
	var horizontal_velocity: Vector2 = Vector2(velocity.x, velocity.z)
	var speed: float = horizontal_velocity.length()
	var target_animation: String = ""

	if not is_on_floor:
		target_animation = ANIM_JUMP
	elif speed > WALK_THRESHOLD:
		if current_speed >= RUN_THRESHOLD:
			target_animation = ANIM_RUN
		else:
			target_animation = ANIM_WALK
	else:
		target_animation = ANIM_IDLE

	play_animation(target_animation)

func play_animation(animation_name: String) -> void:
	if not animation_player:
		return

	if animation_name == current_animation and animation_player.is_playing():
		return

	if not animation_player.has_animation(animation_name):
		# Simple fallback, can be expanded with the original's alternative names logic if needed
		var anim_list: PackedStringArray = animation_player.get_animation_list()
		if anim_list.size() > 0:
			animation_name = anim_list[0]
		else:
			push_error("AnimationController: No animations found in AnimationPlayer.")
			return
	
	animation_player.play(animation_name, ANIMATION_BLEND_TIME)
	current_animation = animation_name

	var anim_resource: Animation = animation_player.get_animation(animation_name)
	if anim_resource:
		if animation_name in [ANIM_WALK, ANIM_RUN, ANIM_IDLE]:
			anim_resource.loop_mode = Animation.LOOP_LINEAR
		else:
			anim_resource.loop_mode = Animation.LOOP_NONE

func play_action(action_name: String) -> void:
	match action_name:
		"chop":
			play_animation(ANIM_CHOP)
		"interact":
			play_animation(ANIM_INTERACT)
		"wave":
			play_animation(ANIM_WAVE)
		"punch_left":
			play_animation(ANIM_PUNCH_LEFT)
		"punch_right":
			play_animation(ANIM_PUNCH_RIGHT)
		"kick_left":
			play_animation(ANIM_KICK_LEFT)
		"kick_right":
			play_animation(ANIM_KICK_RIGHT)
		"gun_aim_draw":
			start_gun_aim()
		"gun_aim_fire":
			fire_gun_aim()
		"gun_aim_lower":
			stop_gun_aim()
		_:
			push_warning("AnimationController: Unknown action requested: " + action_name)

# --- Gun-Aim Animation Methods ---

func start_gun_aim() -> void:
	"""Start the gun-aim sequence - draw and hold aim position."""
	is_aiming = true
	play_animation(ANIM_GUN_AIM_DRAW)
	
	# After draw animation, transition to hold position
	var draw_duration: float = _get_animation_duration(ANIM_GUN_AIM_DRAW)
	var timer: Timer = Timer.new()
	add_child(timer)
	timer.wait_time = draw_duration * 0.8  # Transition slightly before animation ends
	timer.timeout.connect(func():
		if is_aiming:  # Only transition if still aiming
			play_animation(ANIM_GUN_AIM_HOLD)
		timer.queue_free()
	)
	timer.one_shot = true
	timer.start()

func fire_gun_aim() -> void:
	"""Play the firing animation while maintaining gun-aim stance."""
	if is_aiming:
		play_animation(ANIM_GUN_AIM_FIRE)
		
		# Return to hold position after firing
		var fire_duration: float = _get_animation_duration(ANIM_GUN_AIM_FIRE)
		var timer: Timer = Timer.new()
		add_child(timer)
		timer.wait_time = fire_duration * 0.9
		timer.timeout.connect(func():
			if is_aiming:  # Only return to hold if still aiming
				play_animation(ANIM_GUN_AIM_HOLD)
			timer.queue_free()
		)
		timer.one_shot = true
		timer.start()

func stop_gun_aim() -> void:
	"""Stop gun-aim and lower the weapon."""
	is_aiming = false
	play_animation(ANIM_GUN_AIM_LOWER)
	
	# Return to normal idle after lowering
	var lower_duration: float = _get_animation_duration(ANIM_GUN_AIM_LOWER)
	var timer: Timer = Timer.new()
	add_child(timer)
	timer.wait_time = lower_duration * 0.9
	timer.timeout.connect(func():
		if not is_aiming:  # Only return to idle if not aiming again
			play_animation(ANIM_IDLE)
		timer.queue_free()
	)
	timer.one_shot = true
	timer.start()

# --- Helper Methods ---

func _get_animation_duration(animation_name: String) -> float:
	"""Get the duration of a specific animation."""
	if not animation_player or not animation_player.has_animation(animation_name):
		return 1.0  # Default duration
	
	var animation_resource: Animation = animation_player.get_animation(animation_name)
	if animation_resource:
		return animation_resource.length
	return 1.0

func get_animation_player() -> AnimationPlayer:
	return animation_player

func is_in_gun_aim_mode() -> bool:
	"""Check if currently in gun-aim mode."""
	return is_aiming 