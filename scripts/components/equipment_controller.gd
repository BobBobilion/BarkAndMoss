class_name EquipmentController
extends Node

# --- Constants ---
const BOW_CHARGE_TIME: float = 4.0  # Total time for full charge (beyond minimum draw time)
const BOW_MIN_POWER: float = 0.3
const BOW_MAX_POWER: float = 1.0
const BOW_MIN_DRAW_TIME: float = 2.0  # Minimum time required to draw bow before it can shoot

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
var animation_controller: AnimationController  # Reference to animation controller

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
	
	# Get reference to animation controller
	if player_body and player_body.has_node("AnimationController"):
		animation_controller = player_body.get_node("AnimationController") as AnimationController
	
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
func _has_arrows() -> bool:
	"""Check if player has arrows available in inventory."""
	var player_inventory = null
	if player_body and player_body.has_method("get_inventory"):
		player_inventory = player_body.get_inventory()
	
	if not player_inventory or not player_inventory.has_method("get_item_count"):
		return false
	
	return player_inventory.get_item_count("Arrow") > 0


func handle_equipment_input(delta: float, closest_interactable: Node) -> String:
	var action_to_perform: String = ""
	equipped_item = get_equipped_item_from_hud()
	
	if Input.is_action_just_pressed("attack"):
		match equipped_item:
			"Axe":
				# Always allow axe swing with left-click, regardless of nearby interactables
				# Processing corpses should be done with the interact key (E), not attack
				action_to_perform = "chop"
			"Bow":
				# Only start charging if arrows are available
				if _has_arrows():
					_start_bow_charge()
				else:
					print("Cannot use bow - no arrows available!")
			_:
				action_to_perform = "punch_right" # Default unarmed attack

	if Input.is_action_pressed("attack") and equipped_item == "Bow" and is_charging_bow:
		_update_bow_charge(delta)

	if Input.is_action_just_released("attack") and equipped_item == "Bow" and is_charging_bow:
		_shoot_arrow()
		_stop_bow_charge()
		
	return action_to_perform

func on_hotbar_selection_changed(slot_index: int, item_name: String) -> void:
	"""Handle hotbar selection changes and update tool visibility."""
	equipped_item = item_name
	_update_tool_visibility(item_name)
	_update_crosshair_visibility(item_name)
	
	# Stop aiming and gun-aim animations when switching away from bow
	if item_name != "Bow" and is_aiming:
		_stop_aiming()
		
		# Force stop any ongoing bow charging
		if is_charging_bow:
			_stop_bow_charge()
		
		# Reset crosshair when switching away from bow
		if is_instance_valid(hud_instance) and hud_instance.has_method("reset_crosshair_to_default"):
			hud_instance.reset_crosshair_to_default()
	
	print("Equipment changed to: ", item_name)

func _update_tool_visibility(item: String) -> void:
	# Hide all tools first
	if axe_model: axe_model.visible = false
	if bow_model: bow_model.visible = false
	if quiver_model: quiver_model.visible = false

	match item:
		"Axe":
			# Since you're handling attachment manually in humanModel.tscn,
			# we just need to make the axe visible
			if axe_model: 
				axe_model.visible = true
				# Connect to the axe's hit_something signal instead of the hitbox directly
				if axe_model.has_signal("hit_something") and not axe_model.is_connected("hit_something", _on_axe_hit):
					axe_model.hit_something.connect(_on_axe_hit)
		"Bow":
			if bow_model: bow_model.visible = true
			if quiver_model: quiver_model.visible = true

func toggle_axe_hitbox(is_enabled: bool):
	if is_instance_valid(axe_model) and axe_model.has_method("set_hitbox_enabled"):
		# Use the axe's method to enable/disable the hitbox
		axe_model.set_hitbox_enabled(is_enabled)

func _on_axe_hit(body: Node3D):
	# Log every axe hit with detailed information
	print("🪓 AXE HIT! Target: ", body.name, " | Type: ", body.get_class(), " | Groups: ", body.get_groups())
	print("   -> Player body reference: ", player_body.name if player_body else "None")
	
	# Handle hitting animals - instant kill with axe
	if body.is_in_group("animals") and body.has_method("take_damage"):
		print("   -> Dealing fatal damage to ", body.name)
		body.take_damage(100.0)  # Instant kill for animals
		return
	
	# Handle hitting corpses - process them
	if body.is_in_group("corpses"):
		print("   -> Processing corpse: ", body.name)
		_process_corpse_with_axe(body)
		return
	
	# Handle other objects that can take damage (like trees)
	if body.has_method("take_damage"):
		print("   -> Dealing 1 damage to ", body.name, " | Groups: ", body.get_groups())
		# Pass the player reference for trees so they can reward the chopper with wood
		# Check for TreeStump (the actual node name in the scene)
		if body.is_in_group("interactable") or "TreeStump" in body.name or "Tree" in body.name:
			print("   -> Detected as tree, passing player reference")
			body.take_damage(1, player_body)
		else:
			print("   -> Detected as non-tree, using default damage")
			body.take_damage(1) # Default damage for other objects (animals, etc.)
	else:
		print("   -> Target has no take_damage method")

func _process_corpse_with_axe(corpse: Node3D) -> void:
	"""Process a corpse when hit with the axe."""
	# Call the corpse's interaction method directly, passing the player
	if corpse.has_method("_on_interacted") and player_body:
		corpse._on_interacted(player_body)

# --- Bow Mechanics ---
func _start_bow_charge() -> void:
	"""Start bow charging with gun-aim animation."""
	is_charging_bow = true
	is_aiming = true
	bow_charge_level = 0.0
	aiming_status_changed.emit(true)
	action_started.emit()
	
	# Start gun-aim animation sequence
	if animation_controller:
		animation_controller.start_gun_aim()
	
	# Update crosshair to show loading state (red)
	if is_instance_valid(hud_instance) and hud_instance.has_method("update_bow_charge_crosshair"):
		hud_instance.update_bow_charge_crosshair(true, false)  # Charging but not ready
	
	print("Started gun-aim bow charging")

func _update_bow_charge(delta: float) -> void:
	"""Update bow charge level while maintaining gun-aim stance."""
	if is_charging_bow:
		var previous_charge: float = bow_charge_level
		bow_charge_level = min(bow_charge_level + delta, BOW_CHARGE_TIME)
		
		# Check if we just reached the minimum draw time
		if previous_charge < BOW_MIN_DRAW_TIME and bow_charge_level >= BOW_MIN_DRAW_TIME:
			print("Bow ready to fire! (", BOW_MIN_DRAW_TIME, " seconds reached)")
			
			# Update crosshair to show ready state (green)
			if is_instance_valid(hud_instance) and hud_instance.has_method("update_bow_charge_crosshair"):
				hud_instance.update_bow_charge_crosshair(true, true)  # Charging and ready

func is_bow_ready_to_fire() -> bool:
	"""Check if the bow has been drawn long enough to fire."""
	return is_charging_bow and bow_charge_level >= BOW_MIN_DRAW_TIME

func get_bow_charge_percentage() -> float:
	"""Get the current bow charge as a percentage of total charge time."""
	if not is_charging_bow:
		return 0.0
	return bow_charge_level / BOW_CHARGE_TIME

func get_minimum_draw_progress() -> float:
	"""Get the progress towards minimum draw time (0.0 to 1.0)."""
	if not is_charging_bow:
		return 0.0
	return min(bow_charge_level / BOW_MIN_DRAW_TIME, 1.0)

func _shoot_arrow() -> void:
	"""Shoot an arrow from the bow position with proper trajectory calculation."""
	# Check if minimum draw time has been met
	if bow_charge_level < BOW_MIN_DRAW_TIME:
		print("Bow not drawn long enough! Need ", BOW_MIN_DRAW_TIME, " seconds, only had ", bow_charge_level)
		# Don't shoot - just stop charging and return to normal stance
		_stop_bow_charge()
		return
	
	# Get player inventory (simplified since we checked arrows before charging)
	var player_inventory = player_body.get_inventory() if player_body and player_body.has_method("get_inventory") else null
	
	if not player_inventory:
		print("Cannot access player inventory!")
		_stop_bow_charge()
		return
	
	# Final safety check for arrows (edge case: arrows removed while charging)
	var arrow_count: int = player_inventory.get_item_count("Arrow") if player_inventory.has_method("get_item_count") else 0
	if arrow_count <= 0:
		print("No arrows available! (arrows were removed while charging)")
		_stop_bow_charge()
		return
	
	# Consume 1 arrow from inventory
	if not player_inventory.remove_item_by_name("Arrow", 1):
		print("Failed to consume arrow from inventory!")
		_stop_bow_charge()
		return
	
	print("Consumed 1 arrow. Arrows remaining: ", player_inventory.get_item_count("Arrow"))
	
	# Update hotbar to show new arrow count
	if is_instance_valid(hud_instance) and hud_instance.has_node("Hotbar"):
		var hotbar = hud_instance.get_node("Hotbar")
		if hotbar and hotbar.has_method("refresh_visuals"):
			hotbar.refresh_visuals()
	
	var charge_percentage: float = bow_charge_level / BOW_CHARGE_TIME
	var arrow_power: float = lerp(BOW_MIN_POWER, BOW_MAX_POWER, charge_percentage)
	
	# Play gun-aim fire animation
	if animation_controller:
		animation_controller.fire_gun_aim()
	
	# Calculate shoot direction from camera for aiming accuracy
	var shoot_direction: Vector3 = -camera.global_transform.basis.z
	
	# Calculate spawn position from bow instead of camera
	var spawn_position: Vector3
	if bow_model and is_instance_valid(bow_model):
		# Get the bow's global position
		spawn_position = bow_model.global_position
		
		# Add a small offset forward from the bow to avoid collision with the character
		# Use the bow's forward direction (negative Z) for proper orientation
		var bow_forward: Vector3 = -bow_model.global_transform.basis.z.normalized()
		spawn_position += bow_forward * 0.3  # 0.3 meters forward from bow
		
		# Add a slight upward offset to simulate arrow nocking point
		spawn_position += Vector3.UP * 0.1  # 0.1 meters up
		
		# Adjust position slightly to the left to center the arrow better
		var bow_left: Vector3 = -bow_model.global_transform.basis.x.normalized()
		spawn_position += bow_left * 0.15  # 0.15 meters to the left
	else:
		# Fallback to camera position if bow model is not available
		print("Warning: Bow model not found, falling back to camera spawn position")
		spawn_position = camera.global_position + shoot_direction * 0.5
	
	# Create and configure the arrow
	var arrow: RigidBody3D = arrow_scene.instantiate()
	get_tree().current_scene.add_child(arrow)
	arrow.global_position = spawn_position
	
	# Set the shooter to avoid self-collision
	if arrow.has_method("set_shooter"):
		arrow.set_shooter(player_body)
	
	# Launch the arrow with calculated power and direction
	var arrow_speed: float = 30.0  # From Arrow.gd constant
	arrow.launch(shoot_direction, arrow_speed * arrow_power)
	
	_stop_bow_charge()
	print("Arrow shot from bow position with gun-aim animation: ", spawn_position)

func _stop_bow_charge() -> void:
	"""Stop bow charging and return to normal stance."""
	is_charging_bow = false
	bow_charge_level = 0.0
	action_finished.emit()
	
	# Stop aiming to reset zoom and camera
	_stop_aiming()
	
	# End gun-aim animation sequence
	if animation_controller:
		animation_controller.stop_gun_aim()
	
	# Reset crosshair to default color
	if is_instance_valid(hud_instance) and hud_instance.has_method("reset_crosshair_to_default"):
		hud_instance.reset_crosshair_to_default()
	
	print("Stopped gun-aim bow charging and returned zoom to normal")

func _stop_aiming() -> void:
	"""Stop aiming and ensure gun-aim animations are properly ended."""
	is_aiming = false
	aiming_status_changed.emit(false)
	
	# Make sure gun-aim animations are stopped
	if animation_controller and animation_controller.is_in_gun_aim_mode():
		animation_controller.stop_gun_aim()

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

func _update_crosshair_visibility(item_name: String) -> void:
	"""Updates the HUD crosshair visibility based on equipped item."""
	if is_instance_valid(hud_instance) and hud_instance.has_method("update_crosshair_visibility"):
		hud_instance.update_crosshair_visibility(item_name)

func _set_initial_tool_visibility() -> void:
	var item = get_equipped_item_from_hud()
	_update_tool_visibility(item)
	_update_crosshair_visibility(item) 
