class_name Player
extends CharacterBody3D

# --- Script Preloads ---
const MovementController = preload("res://scripts/components/movement_controller.gd")
const CameraController = preload("res://scripts/components/camera_controller.gd")
const AnimationController = preload("res://scripts/components/animation_controller.gd")
const InteractionController = preload("res://scripts/components/interaction_controller.gd")
const EquipmentController = preload("res://scripts/components/equipment_controller.gd")

# --- Components ---
@onready var movement_controller: MovementController = $MovementController
@onready var camera_controller: CameraController = $CameraController
@onready var animation_controller: AnimationController = $AnimationController
@onready var interaction_controller: InteractionController = $InteractionController
@onready var equipment_controller: EquipmentController = $EquipmentController

# --- Properties ---
var hud_instance: Control
var is_performing_action: bool = false
var pending_interaction_target: Node = null
var chop_timer: Timer

func _ready() -> void:
	# Wire up controller dependencies - using new camera hierarchy
	var camera_node: Camera3D = $CameraRootOffset/HorizontalPivot/VerticalPivot/SpringArm3D/Camera3D
	var horizontal_pivot: Node3D = $CameraRootOffset/HorizontalPivot
	var vertical_pivot: Node3D = $CameraRootOffset/HorizontalPivot/VerticalPivot
	
	camera_controller.setup(camera_node, self, horizontal_pivot, vertical_pivot)
	animation_controller.setup($AdventurerModel)
	interaction_controller.setup($InteractionArea, self)
	equipment_controller.setup(self, $AdventurerModel, camera_node)

	var is_local_player: bool = is_multiplayer_authority() or not multiplayer.has_multiplayer_peer()
	
	if is_local_player:
		camera_node.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		call_deferred("add_hud")
		if PauseManager:
			PauseManager.register_player(self)
	else:
		camera_node.enabled = false

	add_to_group("human_player")
	
	# Connect signals between controllers
	equipment_controller.action_started.connect(func(): is_performing_action = true)
	equipment_controller.action_finished.connect(func(): is_performing_action = false)
	equipment_controller.aiming_status_changed.connect(camera_controller.set_aiming)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		return

	# Movement
	velocity = movement_controller.handle_movement(delta, self, transform)
	move_and_slide()

	# Animation
	if not is_performing_action:
		animation_controller.update_movement_animation(velocity, is_on_floor(), movement_controller.current_speed)

	# Interaction
	handle_interaction()

	# Equipment
	var action_to_perform = equipment_controller.handle_equipment_input(delta, interaction_controller.get_closest_interactable())
	if action_to_perform:
		handle_action(action_to_perform)

func _process(delta: float) -> void:
	if not is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		return
	camera_controller.process_camera(delta)

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		return
	camera_controller._unhandled_input(event)

func handle_interaction() -> void:
	var interactable = interaction_controller.handle_interaction_input()
	if interactable:
		var prompt: String = interaction_controller.get_interaction_prompt(interactable)
		var is_tree_or_corpse = "Chop" in prompt or "Process" in prompt or "Tree" in prompt
		
		if not is_tree_or_corpse:
			interaction_controller.interact_with_object(interactable, self)

func handle_action(action_name: String) -> void:
	if is_performing_action:
		return
	
	if action_name == "chop":
		equipment_controller.toggle_axe_hitbox(true)
		
	is_performing_action = true
	pending_interaction_target = interaction_controller.get_closest_interactable()
	animation_controller.play_action(action_name)
	
	var anim_player = animation_controller.get_animation_player()
	if anim_player:
		# Use a timer to wait for the animation to finish
		var anim = anim_player.get_animation(animation_controller.current_animation)
		if anim:
			var duration = anim.length
			if chop_timer and is_instance_valid(chop_timer):
				chop_timer.queue_free()

			chop_timer = Timer.new()
			add_child(chop_timer)
			chop_timer.wait_time = duration
			chop_timer.one_shot = true
			chop_timer.timeout.connect(_on_action_animation_finished)
			chop_timer.start()

func _on_action_animation_finished() -> void:
	is_performing_action = false
	
	# Disable hitbox after swing
	equipment_controller.toggle_axe_hitbox(false)
	
	if pending_interaction_target and is_instance_valid(pending_interaction_target):
		interaction_controller.interact_with_object(pending_interaction_target, self)
		pending_interaction_target = null

	# Return to idle/movement animation
	animation_controller.update_movement_animation(velocity, is_on_floor(), movement_controller.current_speed)
	
	if chop_timer and is_instance_valid(chop_timer):
		chop_timer.queue_free()
		chop_timer = null

func add_hud() -> void:
	var hud_scene: PackedScene = preload("res://scenes/HUD.tscn")
	hud_instance = hud_scene.instantiate()
	get_tree().current_scene.add_child.call_deferred(hud_instance)

	# Pass HUD instance to equipment controller
	equipment_controller.set_hud(hud_instance)

	if is_instance_valid(hud_instance) and hud_instance.has_node("Hotbar"):
		var hotbar = hud_instance.get_node("Hotbar")
		if hotbar and not hotbar.is_connected("selection_changed", equipment_controller.on_hotbar_selection_changed):
			hotbar.connect("selection_changed", equipment_controller.on_hotbar_selection_changed)

	call_deferred("_add_test_items")

func _add_test_items() -> void:
	if not OS.is_debug_build(): return
	if is_instance_valid(hud_instance) and hud_instance.has_node("Inventory"):
		var inventory: Node = hud_instance.get_node("Inventory")
		if inventory.has_method("add_item"):
			inventory.add_item("Hatchet")
			inventory.add_item("Wood")
			inventory.add_item("Raw Meat")
			inventory.add_item("Bow")

func add_item_to_inventory(item_name: String) -> bool:
	if is_instance_valid(hud_instance) and hud_instance.has_node("Inventory"):
		var inventory = hud_instance.get_node("Inventory")
		if inventory.has_method("add_item"):
			return inventory.add_item(item_name)
	return false

func get_inventory():
	if is_instance_valid(hud_instance) and hud_instance.has_node("Inventory"):
		return hud_instance.get_node("Inventory")
	return null

func get_interaction_controller() -> InteractionController:
	return interaction_controller

func _exit_tree() -> void:
	if is_multiplayer_authority() and PauseManager:
		PauseManager.unregister_player(self)
