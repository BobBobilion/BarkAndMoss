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

# Crafting recipes
const CRAFTING_RECIPES: Dictionary = {
	"Bow": {
		"Wood": 1,
		"Sinew": 1
	}
}

# --- Node References ---
@onready var bonfire_model: Node3D = $BonfireModel
@onready var campfire_light: OmniLight3D = $CampfireLight
@onready var fire_particles: CPUParticles3D = $FireParticles
@onready var interaction_area: Area3D = $InteractionArea
@onready var safe_zone: Area3D = $SafeZone
@onready var cooking_timer: Timer = $CookingTimer
@onready var ui_prompt: Label3D = $UIPrompt

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
	
	# Initialize campfire state
	_update_campfire_state()
	_update_ui_prompt()
	
	# Add to groups for identification
	add_to_group("campfire")
	add_to_group("interactable")
	
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

func _handle_player_interaction() -> void:
	"""Handle player interaction with the campfire."""
	var player: Node = _get_nearby_player()
	if not player:
		return
	
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
	
	# TODO: Implement proper UI menu
	# For now, automatically try to cook raw meat if available
	if player.has_method("get_inventory"):
		var inventory = player.get_inventory()
		if inventory and inventory.has_method("has_item"):
			if inventory.has_item("Raw Meat"):
				_start_cooking(["Raw Meat"])
				return
	
	print("Campfire: No raw meat to cook")

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
	"""Create cooked items near the campfire for pickup."""
	print("Campfire: Creating cooked items: ", items)
	
	# TODO: Implement item spawning system
	# For now, just log the items that would be created
	for item in items:
		print("Campfire: Created ", item, " near campfire")

func can_craft_item(item_name: String, player_inventory) -> bool:
	"""Check if the given item can be crafted with available materials."""
	if not CRAFTING_RECIPES.has(item_name):
		return false
	
	var recipe = CRAFTING_RECIPES[item_name]
	
	for material in recipe:
		var required_amount: int = recipe[material]
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
	
	var recipe = CRAFTING_RECIPES[item_name]
	
	# Remove materials from inventory
	for material in recipe:
		var required_amount: int = recipe[material]
		if player_inventory.has_method("remove_item"):
			player_inventory.remove_item(material, required_amount)
	
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
	var body = area.get_parent()
	if body and body.is_in_group("human_player"):
		print("Campfire: Player entered interaction range")
		players_in_range.append(body)
		is_player_nearby = true
		_update_ui_prompt()

func _on_interaction_area_exited(area: Area3D) -> void:
	"""Handle player leaving interaction range."""
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
