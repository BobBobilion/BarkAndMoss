class_name EquipmentController
extends Node

# --- Constants ---
const BOW_CHARGE_TIME: float = 2.0
const BOW_MIN_POWER: float = 0.3
const BOW_MAX_POWER: float = 1.0

# --- Signals ---
signal action_started
signal action_finished
signal aiming_status_changed(is_aiming: bool)

# --- Properties ---
@export var player_body: CharacterBody3D
@export var adventurer_model: Node3D
@export var camera: Camera3D
@export var hud_instance: Control

var axe_model: Node3D
var bow_model: Node3D
var quiver_model: Node3D

var arrow_scene: PackedScene = preload("res://scenes/Arrow.tscn")
var axe_scene: PackedScene = preload("res://scenes/tools/axe.tscn")
var is_charging_bow: bool = false
var bow_charge_level: float = 0.0
var is_aiming: bool = false

var equipped_item: String = ""

# --- Initialization ---
func setup(p_player_body: CharacterBody3D, p_adventurer_model: Node3D, p_camera: Camera3D) -> void:
	self.player_body = p_player_body
	self.adventurer_model = p_adventurer_model
	self.camera = p_camera
	if adventurer_model:
		bow_model = _find_node_by_name(adventurer_model, "Bow")
		quiver_model = _find_node_by_name(adventurer_model, "Quiver")
		axe_model = _find_node_by_name(adventurer_model, "Axe")
	else:
		push_error("EquipmentController: Adventurer model not assigned.")
	
	call_deferred("_set_initial_tool_visibility")

func set_hud(p_hud: Control):
	self.hud_instance = p_hud
	call_deferred("_set_initial_tool_visibility")

func _find_node_by_name(node: Node, target_name: String) -> Node3D:
	if node.name == target_name:
		return node as Node3D
	for child in node.get_children():
		var result: Node3D = _find_node_by_name(child, target_name)
		if result:
			return result
	return null

# --- Public Methods ---
func handle_equipment_input(delta: float, closest_interactable: Node) -> String:
	var action_to_perform: String = ""
	equipped_item = get_equipped_item_from_hud()
	
	if Input.is_action_just_pressed("attack"):
		match equipped_item:
			"Hatchet", "Axe":
				if closest_interactable:
					var prompt: String = _get_interaction_prompt(closest_interactable)
					if prompt.contains("Chop") or prompt.contains("Tree") or prompt.contains("Process"):
						action_to_perform = "chop"
				else:
					action_to_perform = "chop" # Still play the animation
			"Bow":
				_start_bow_charge()
			_:
				action_to_perform = "punch_right" # Default unarmed attack

	if Input.is_action_pressed("attack") and equipped_item == "Bow":
		_update_bow_charge(delta)

	if Input.is_action_just_released("attack") and equipped_item == "Bow":
		_shoot_arrow()
		_stop_bow_charge()
		
	return action_to_perform

func on_hotbar_selection_changed(slot_index: int, item_name: String) -> void:
	equipped_item = item_name
	_update_tool_visibility(item_name)
	if item_name != "Bow" and is_aiming:
		_stop_aiming()

func _update_tool_visibility(item: String) -> void:
	# Hide all tools first
	if axe_model: axe_model.visible = false
	if bow_model: bow_model.visible = false
	if quiver_model: quiver_model.visible = false

	match item:
		"Hatchet", "Axe":
			# Since you're handling attachment manually in humanModel.tscn,
			# we just need to make the axe visible
			if axe_model: 
				axe_model.visible = true
				# Connect to the hitbox if it exists
				var hitbox = axe_model.get_node_or_null("Hitbox")
				if hitbox and hitbox.has_signal("body_entered"):
					if not hitbox.is_connected("body_entered", _on_axe_hit):
						hitbox.body_entered.connect(_on_axe_hit)
		"Bow":
			if bow_model: bow_model.visible = true
			if quiver_model: quiver_model.visible = true

func toggle_axe_hitbox(is_enabled: bool):
	if is_instance_valid(axe_model):
		var hitbox = axe_model.get_node_or_null("Hitbox")
		if hitbox:
			hitbox.monitoring = is_enabled

func _on_axe_hit(body: Node3D):
	# Log every axe hit with detailed information
	print("🪓 AXE HIT! Target: ", body.name, " | Type: ", body.get_class(), " | Groups: ", body.get_groups())
	
	if body.has_method("take_damage"):
		print("   -> Dealing 1 damage to ", body.name)
		body.take_damage(1) # Or whatever damage value
	else:
		print("   -> Target has no take_damage method")

# --- Bow Mechanics ---
func _start_bow_charge() -> void:
	is_charging_bow = true
	is_aiming = true
	bow_charge_level = 0.0
	aiming_status_changed.emit(true)
	action_started.emit()

func _update_bow_charge(delta: float) -> void:
	if is_charging_bow:
		bow_charge_level = min(bow_charge_level + delta, BOW_CHARGE_TIME)

func _shoot_arrow() -> void:
	var charge_percentage: float = bow_charge_level / BOW_CHARGE_TIME
	var arrow_power: float = lerp(BOW_MIN_POWER, BOW_MAX_POWER, charge_percentage)
	
	var shoot_direction: Vector3 = -camera.global_transform.basis.z
	var spawn_position: Vector3 = camera.global_position + shoot_direction
	
	var arrow: RigidBody3D = arrow_scene.instantiate()
	get_tree().current_scene.add_child(arrow)
	arrow.global_position = spawn_position
	# arrow.set_shooter(self.get_parent()) # The player will be the shooter
	
	var arrow_speed: float = 30.0 # From Arrow.gd
	arrow.launch(shoot_direction, arrow_speed * arrow_power)
	
	_stop_bow_charge()

func _stop_bow_charge() -> void:
	is_charging_bow = false
	bow_charge_level = 0.0
	action_finished.emit()

func _stop_aiming() -> void:
	is_aiming = false
	aiming_status_changed.emit(false)

# --- Helper Methods ---
func get_equipped_item_from_hud() -> String:
	if is_instance_valid(hud_instance) and hud_instance.has_node("Hotbar"):
		var hotbar = hud_instance.get_node("Hotbar")
		if hotbar and hotbar.has_method("get_selected_item"):
			return hotbar.get_selected_item()
	return ""

func _get_interaction_prompt(interactable: Node) -> String:
	if interactable and interactable.has_method("get_interaction_prompt"):
		return interactable.get_interaction_prompt()
	return ""

func _set_initial_tool_visibility() -> void:
	var item = get_equipped_item_from_hud()
	_update_tool_visibility(item) 
