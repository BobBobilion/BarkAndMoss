class_name Campfire
extends StaticBody3D

# Campfire states
enum CampfireState {
	UNLIT,
	LIT,
	COOKING
}

# Cooking system constants
const COOK_TIME: float = 10.0
const RAW_MEAT_HUNGER_RESTORE: float = 60.0

# Light system constants
const BASE_LIGHT_RANGE: float = 8.0
const MAX_LIGHT_ENERGY: float = 1.5
const MIN_LIGHT_ENERGY: float = 0.3

# --- Node References ---
@onready var bonfire_model: Node3D = $BonfireModel
@onready var campfire_light: OmniLight3D = $CampfireLight
@onready var fire_particles: CPUParticles3D = $FireParticles
@onready var interaction_area: Area3D = $InteractionArea
@onready var safe_zone: Area3D = $SafeZone
@onready var cooking_timer: Timer = $CookingTimer
@onready var ui_prompt: Label3D = $UIPrompt
@onready var campfire_interactable: Area3D = $CampfireInteractable

# Campfire menu UI
var campfire_menu_scene: PackedScene = preload("res://ui/CampfireMenu.tscn")
var campfire_menu_instance: Control = null

# --- State Variables ---
var current_state: CampfireState = CampfireState.LIT
var cooking_queue: Array[String] = []
var players_in_range: Array[Node] = []
var is_player_nearby: bool = false
var flicker_timer: float = 0.0  # Timer for light flickering effect

# --- Signals ---
signal cooking_completed(cooked_items: Array[String])
signal crafting_completed(item_name: String)

func _ready() -> void:
	"""Initialize the campfire system."""
	print("Campfire: Initializing...")
	
	# Set up signal connections (only if not already connected)
	if not cooking_timer.timeout.is_connected(_on_cooking_timer_timeout):
		cooking_timer.timeout.connect(_on_cooking_timer_timeout)
	if not interaction_area.area_entered.is_connected(_on_interaction_area_entered):
		interaction_area.area_entered.connect(_on_interaction_area_entered)
	if not interaction_area.area_exited.is_connected(_on_interaction_area_exited):
		interaction_area.area_exited.connect(_on_interaction_area_exited)
	
	# Connect the CampfireInteractable signals for debugging
	if campfire_interactable:
		if not campfire_interactable.area_entered.is_connected(_on_campfire_interactable_entered):
			campfire_interactable.area_entered.connect(_on_campfire_interactable_entered)
		if not campfire_interactable.area_exited.is_connected(_on_campfire_interactable_exited):
			campfire_interactable.area_exited.connect(_on_campfire_interactable_exited)
	
	# Initialize campfire state
	_update_campfire_state()
	_update_ui_prompt()
	
	# Add to groups for identification
	add_to_group("campfire")
	add_to_group("interactable")
	
	# Debug info - commented out verbose details
	# print("Campfire: Groups = ", get_groups())
	# print("Campfire: Has get_interaction_prompt = ", has_method("get_interaction_prompt"))
	# if campfire_interactable:
	# 	print("Campfire: Interactable area collision layer = ", campfire_interactable.collision_layer)
	# 	print("Campfire: Interactable area collision mask = ", campfire_interactable.collision_mask)
	# 	print("Campfire: Interactable area monitoring = ", campfire_interactable.monitoring)
	# 	print("Campfire: Interactable area monitorable = ", campfire_interactable.monitorable)
	
	print("Campfire: Ready! State: ", CampfireState.keys()[current_state])

func _process(delta: float) -> void:
	"""Handle continuous campfire updates."""
	# Update light intensity based on nearby trees (simplified for now)
	_update_light_intensity()
	
	# Add realistic fire flickering when lit
	if current_state != CampfireState.UNLIT:
		_update_fire_flicker(delta)
	
	# Handle player input if nearby
	if is_player_nearby and Input.is_action_just_pressed("interact"):
		_handle_player_interaction()

func _update_fire_flicker(delta: float) -> void:
	"""Create realistic fire flickering effect."""
	flicker_timer += delta
	
	# Create subtle light energy variation using sine waves with different frequencies
	var base_energy: float = MAX_LIGHT_ENERGY
	if current_state == CampfireState.COOKING:
		base_energy *= 1.2
	
	# Combine multiple sine waves for complex flickering pattern
	var flicker_1: float = sin(flicker_timer * 3.0) * 0.1
	var flicker_2: float = sin(flicker_timer * 7.0) * 0.05
	var flicker_3: float = sin(flicker_timer * 12.0) * 0.03
	
	# Apply combined flickering to light energy
	campfire_light.light_energy = base_energy + flicker_1 + flicker_2 + flicker_3
	
	# Subtle particle amount variation for added realism
	if fire_particles and fire_particles.emitting:
		var particle_variation: float = sin(flicker_timer * 5.0) * 0.1
		var current_intensity: float = 1.0
		if current_state == CampfireState.COOKING:
			current_intensity = 1.3
		
		fire_particles.speed_scale = (1.2 * current_intensity) + particle_variation

func _update_campfire_state() -> void:
	"""Update the visual state of the campfire based on current state."""
	match current_state:
		CampfireState.UNLIT:
			campfire_light.visible = false
			campfire_light.light_energy = 0.0
			fire_particles.emitting = false
		CampfireState.LIT:
			campfire_light.visible = true
			campfire_light.light_energy = MAX_LIGHT_ENERGY
			fire_particles.emitting = true
			_set_fire_intensity(1.0)  # Normal fire intensity
		CampfireState.COOKING:
			campfire_light.visible = true
			campfire_light.light_energy = MAX_LIGHT_ENERGY * 1.2  # Slightly brighter when cooking
			fire_particles.emitting = true
			_set_fire_intensity(1.3)  # More intense fire when cooking

func _set_fire_intensity(intensity: float) -> void:
	"""Adjust the fire particle intensity based on campfire activity."""
	if not fire_particles:
		return
	
	# Adjust particle amount and speed for different intensities
	var base_amount: int = 35
	var base_speed: float = 1.2
	var base_velocity_max: float = 2.5
	
	fire_particles.amount = int(base_amount * intensity)
	fire_particles.speed_scale = base_speed * intensity
	fire_particles.initial_velocity_max = base_velocity_max * intensity
	
	# Add slight randomness to make fire feel more alive
	fire_particles.randomness = 0.3 + (intensity - 1.0) * 0.1

func _update_light_intensity() -> void:
	"""Update light intensity based on nearby trees and obstacles."""
	if current_state == CampfireState.UNLIT:
		return
		
	# TODO: Implement tree-based light blocking
	# For now, maintain full light intensity
	# This would involve raycasting to nearby trees and reducing light range/energy accordingly
	pass

func _update_ui_prompt() -> void:
	"""Update the UI prompt based on current state and available actions."""
	if not is_player_nearby:
		ui_prompt.text = ""
		return
	
	var prompt_text: String = ""
	
	match current_state:
		CampfireState.LIT:
			if cooking_queue.is_empty():
				prompt_text = "E: Cook / Craft"
			else:
				prompt_text = "E: Add to cooking queue"
		CampfireState.COOKING:
			var time_left: int = int(cooking_timer.time_left)
			prompt_text = "Cooking... (%d seconds left)" % time_left
		CampfireState.UNLIT:
			prompt_text = "E: Light campfire"
	
	ui_prompt.text = prompt_text

func _handle_player_interaction(player: Node = null) -> void:
	"""Handle player interaction with the campfire."""
	# Use provided player or try to find one
	if not player:
		player = _get_nearby_player()
	
	if not player:
		print("Campfire: No player found for interaction!")
		return
	
	print("Campfire: Handling interaction for player: ", player.name)
	
	match current_state:
		CampfireState.UNLIT:
			_light_campfire()
		CampfireState.LIT:
			_show_campfire_menu(player)
		CampfireState.COOKING:
			_add_to_cooking_queue(player)

func _light_campfire() -> void:
	"""Light the campfire."""
	print("Campfire: Lighting campfire")
	current_state = CampfireState.LIT
	_update_campfire_state()
	_update_ui_prompt()

func _show_campfire_menu(player: Node) -> void:
	"""Show cooking and crafting options to the player."""
	print("Campfire: Opening campfire menu for player")
	
	# Create menu instance if not exists
	if not campfire_menu_instance:
		campfire_menu_instance = campfire_menu_scene.instantiate()
		get_tree().root.add_child(campfire_menu_instance)
		
		# Connect menu signals
		campfire_menu_instance.menu_closed.connect(_on_menu_closed)
		campfire_menu_instance.item_crafted.connect(_on_item_crafted)
		campfire_menu_instance.item_cooked.connect(_on_item_cooked)
	
	# Open the menu
	campfire_menu_instance.open_menu(player, self)

func _add_to_cooking_queue(player: Node) -> void:
	"""Add items to the cooking queue while cooking is in progress."""
	print("Campfire: Adding to cooking queue")
	
	if player.has_method("get_inventory"):
		var inventory = player.get_inventory()
		if inventory and inventory.has_method("has_item"):
			if inventory.has_item("Raw Meat"):
				cooking_queue.append("Raw Meat")
				# TODO: Remove item from player inventory
				print("Campfire: Added Raw Meat to cooking queue")

func _start_cooking(items: Array[String]) -> void:
	"""Start the cooking process with the given items."""
	print("Campfire: Starting cooking process with items: ", items)
	
	cooking_queue.append_array(items)
	current_state = CampfireState.COOKING
	cooking_timer.start()
	
	_update_campfire_state()
	_update_ui_prompt()

# Make start_cooking public for CampfireMenu to call
func start_cooking(items: Array[String]) -> void:
	"""Public method to start cooking items."""
	_start_cooking(items)

func _on_cooking_timer_timeout() -> void:
	"""Handle cooking completion."""
	print("Campfire: Cooking completed! Cooked items: ", cooking_queue)
	
	var cooked_items: Array[String] = []
	
	# Convert all queued raw items to cooked versions
	for item in cooking_queue:
		match item:
			"Raw Meat":
				cooked_items.append("Cooked Meat")
			_:
				print("Campfire: Unknown cooking item: ", item)
	
	# TODO: Add cooked items to nearby player's inventory or create pickup items
	_create_cooked_items(cooked_items)
	
	# Reset state
	cooking_queue.clear()
	current_state = CampfireState.LIT
	_update_campfire_state()
	_update_ui_prompt()
	
	# Emit signal for other systems
	cooking_completed.emit(cooked_items)

func _create_cooked_items(items: Array[String]) -> void:
	"""Create cooked items and add them to the nearby player's inventory."""
	print("Campfire: Adding cooked items to player inventory: ", items)
	
	# Find the nearby player
	var player: Node = _get_nearby_player()
	if not player:
		# If no player in range, try to find any human player
		var players: Array[Node] = get_tree().get_nodes_in_group("human_player")
		if not players.is_empty():
			player = players[0]
	
	if not player:
		print("Campfire: No player found to give cooked items to!")
		return
	
	# Add items to player's inventory
	if player.has_method("add_item_to_inventory"):
		for item in items:
			if player.add_item_to_inventory(item):
				print("Campfire: Added ", item, " to player inventory")
			else:
				print("Campfire: Failed to add ", item, " to player inventory (full?)")
	else:
		print("Campfire: Player doesn't have add_item_to_inventory method!")

func can_craft_item(item_name: String, player_inventory) -> bool:
	"""Check if the given item can be crafted with available materials."""
	if not GameConstants.CRAFTING_RECIPES.has(item_name):
		return false
	
	var recipe_data = GameConstants.CRAFTING_RECIPES[item_name]
	var materials = recipe_data.get("materials", {})
	
	for material in materials:
		var required_amount: int = materials[material]
		if not player_inventory.has_method("get_item_count"):
			return false
		
		var available_amount: int = player_inventory.get_item_count(material)
		if available_amount < required_amount:
			return false
	
	return true

func craft_item(item_name: String, player_inventory) -> bool:
	"""Attempt to craft the specified item."""
	if not can_craft_item(item_name, player_inventory):
		print("Campfire: Cannot craft ", item_name, " - insufficient materials")
		return false
	
	var recipe_data = GameConstants.CRAFTING_RECIPES[item_name]
	var materials = recipe_data.get("materials", {})
	
	# Remove materials from inventory
	for material in materials:
		var required_amount: int = materials[material]
		if player_inventory.has_method("remove_item_by_name"):
			player_inventory.remove_item_by_name(material, required_amount)
	
	# Add crafted item to inventory
	if player_inventory.has_method("add_item"):
		player_inventory.add_item(item_name)
	
	print("Campfire: Successfully crafted ", item_name)
	crafting_completed.emit(item_name)
	return true

func is_safe_zone() -> bool:
	"""Check if this campfire provides a safe zone from bears."""
	return current_state == CampfireState.LIT

func get_light_radius() -> float:
	"""Get the current effective light radius."""
	if current_state == CampfireState.UNLIT:
		return 0.0
	
	return campfire_light.omni_range

func _get_nearby_player() -> Node:
	"""Get the first nearby player."""
	for body in players_in_range:
		if body.is_in_group("human_player"):
			return body
	return null

func _on_interaction_area_entered(area: Area3D) -> void:
	"""Handle player entering interaction range."""
	# The area is the player's InteractionArea, so we need to get its parent (the player)
	var body = area.get_parent()
	if body and body.is_in_group("human_player"):
		print("Campfire: Player entered interaction range")
		players_in_range.append(body)
		is_player_nearby = true
		_update_ui_prompt()

func _on_interaction_area_exited(area: Area3D) -> void:
	"""Handle player leaving interaction range."""
	# The area is the player's InteractionArea, so we need to get its parent (the player)
	var body = area.get_parent()
	if body and body.is_in_group("human_player"):
		print("Campfire: Player left interaction range")
		players_in_range.erase(body)
		is_player_nearby = players_in_range.size() > 0
		_update_ui_prompt()

func get_spawn_position() -> Vector3:
	"""Get a safe spawn position near the campfire."""
	# Return a position slightly offset from the campfire
	return global_position + Vector3(2.0, 0.5, 2.0) 

func get_interaction_prompt() -> String:
	"""Get the interaction prompt to display when player is nearby."""
	match current_state:
		CampfireState.LIT:
			if cooking_queue.is_empty():
				return "E: Cook / Craft"
			else:
				return "E: Add to cooking queue"
		CampfireState.COOKING:
			var time_left: int = int(cooking_timer.time_left)
			return "Cooking... (%d seconds left)" % time_left
		CampfireState.UNLIT:
			return "E: Light campfire"
	
	return ""

func _on_interacted(player: Node) -> void:
	"""Handle interaction when player presses E near the campfire."""
	print("Campfire: Interacted by player")
	_handle_player_interaction(player)

func _get_tree_shadow_count() -> int:
	"""Count how many trees are blocking the campfire light."""
	# For now, return a simple count based on nearby trees
	# TODO: Implement actual tree detection
	return 0

# --- Menu Callbacks ---
func _on_menu_closed() -> void:
	"""Handle menu close event."""
	print("Campfire: Menu closed")
	# Re-enable player controls if needed
	# The menu already handles unpausing

func _on_item_crafted(item_name: String) -> void:
	"""Handle item crafted event from menu."""
	print("Campfire: Item crafted - ", item_name)
	# Could add particle effects or sounds here
	crafting_completed.emit(item_name)

func _on_item_cooked(item_name: String) -> void:
	"""Handle item cooked event from menu."""
	print("Campfire: Item cooked - ", item_name)
	# Could add particle effects or sounds here
	# The menu handles the actual cooking logic


func close_menu() -> void:
	"""Close any open campfire menu - used during cleanup."""
	if campfire_menu_instance and is_instance_valid(campfire_menu_instance):
		print("Campfire: Closing campfire menu for cleanup")
		campfire_menu_instance.close_menu()
		campfire_menu_instance.queue_free()
		campfire_menu_instance = null

# --- Debug Methods ---
func _on_campfire_interactable_entered(area: Area3D) -> void:
	"""Debug: Log when any area enters the CampfireInteractable."""
	print("Campfire DEBUG: Area entered CampfireInteractable - ", area.name)
	print("  Area parent: ", area.get_parent().name if area.get_parent() else "None")
	print("  Area collision layer: ", area.collision_layer)

func _on_campfire_interactable_exited(area: Area3D) -> void:
	"""Debug: Log when any area exits the CampfireInteractable."""
	print("Campfire DEBUG: Area exited CampfireInteractable - ", area.name) 
