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

# Movement speed thresholds
const WALK_THRESHOLD: float = 0.1
const RUN_THRESHOLD: float = 4.0

# --- Properties ---
var adventurer_model: Node3D
var animation_player: AnimationPlayer
var current_animation: String = ""

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
	if not animation_player: return

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
		_:
			push_warning("AnimationController: Unknown action requested: " + action_name)

func get_animation_player() -> AnimationPlayer:
	return animation_player 