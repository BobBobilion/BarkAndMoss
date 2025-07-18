class_name CampfireMenu
extends Control

# --- Signals ---
signal item_crafted(item_name: String)
signal item_cooked(item_name: String)
signal menu_closed()

# --- Constants ---
const RECIPE_SLOT_SCENE_PATH: String = "res://ui/RecipeSlot.tscn"

# --- Node References ---
@onready var background: ColorRect = $Background
@onready var crafting_grid: GridContainer = $CenterContainer/MenuPanel/VBoxContainer/TabContainer/Crafting/CraftingGrid
@onready var cooking_grid: GridContainer = $CenterContainer/MenuPanel/VBoxContainer/TabContainer/Cooking/CookingGrid
@onready var tab_container: TabContainer = $CenterContainer/MenuPanel/VBoxContainer/TabContainer

# --- State ---
var player_inventory: Inventory = null
var campfire_ref: Node3D = null
var is_open: bool = false

# --- Engine Callbacks ---
func _ready() -> void:
	# Set process mode to always so menu works when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Start hidden
	visible = false
	is_open = false
	
	# Connect signals
	if background:
		background.gui_input.connect(_on_background_input)
	
	# Populate recipe lists
	call_deferred("_populate_recipes")

func _input(event: InputEvent) -> void:
	if not is_open:
		return
		
	# Close menu on ESC
	if event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()

# --- Public Methods ---
func open_menu(player: Node, campfire: Node3D) -> void:
	"""Open the campfire menu with reference to player and campfire."""
	if not player or not campfire:
		print("CampfireMenu: Error - invalid player or campfire reference")
		return
	
	# Get player inventory
	if player.has_method("get_inventory"):
		player_inventory = player.get_inventory()
	else:
		print("CampfireMenu: Error - player has no get_inventory method")
		return
	
	campfire_ref = campfire
	
	# Show menu
	visible = true
	is_open = true
	
	# Refresh recipes with current inventory
	_refresh_recipe_displays()
	
	# Show mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func close_menu() -> void:
	"""Close the campfire menu."""
	visible = false
	is_open = false
	
	# Hide mouse cursor (return to captured for gameplay)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Emit closed signal
	menu_closed.emit()
	
	# Clear references
	player_inventory = null
	campfire_ref = null

# --- Private Methods ---
func _populate_recipes() -> void:
	"""Populate the crafting and cooking grids with available recipes."""
	# Clear existing children
	for child in crafting_grid.get_children():
		child.queue_free()
	for child in cooking_grid.get_children():
		child.queue_free()
	
	# Add crafting recipes
	for recipe_name in GameConstants.CRAFTING_RECIPES:
		var recipe_data: Dictionary = GameConstants.CRAFTING_RECIPES[recipe_name]
		var recipe_slot: Control = _create_recipe_slot(recipe_name, recipe_data, true)
		crafting_grid.add_child(recipe_slot)
	
	# Add cooking recipes
	for item_name in GameConstants.COOKING_RECIPES:
		var recipe_data: Dictionary = GameConstants.COOKING_RECIPES[item_name]
		var recipe_slot: Control = _create_recipe_slot(item_name, recipe_data, false)
		cooking_grid.add_child(recipe_slot)

func _create_recipe_slot(recipe_name: String, recipe_data: Dictionary, is_crafting: bool) -> Control:
	"""Create a UI slot for a recipe."""
	# Create container for the recipe
	var recipe_container: PanelContainer = PanelContainer.new()
	recipe_container.custom_minimum_size = Vector2(250, 120)
	
	# Create vertical box for layout
	var vbox: VBoxContainer = VBoxContainer.new()
	recipe_container.add_child(vbox)
	
	# Recipe name
	var name_label: Label = Label.new()
	name_label.text = recipe_data.get("name", recipe_name)
	name_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(name_label)
	
	# Recipe description
	if recipe_data.has("description"):
		var desc_label: Label = Label.new()
		desc_label.text = recipe_data.description
		desc_label.add_theme_font_size_override("font_size", 12)
		desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc_label)
	
	# Materials required (for crafting) or input item (for cooking)
	var materials_container: HBoxContainer = HBoxContainer.new()
	vbox.add_child(materials_container)
	
	if is_crafting:
		# Show materials required
		var materials_label: Label = Label.new()
		materials_label.text = "Materials: "
		materials_container.add_child(materials_label)
		
		var materials: Dictionary = recipe_data.get("materials", {})
		for material_name in materials:
			var count: int = materials[material_name]
			var material_label: Label = Label.new()
			material_label.text = "%s x%d  " % [material_name, count]
			material_label.name = "Material_" + material_name
			materials_container.add_child(material_label)
	else:
		# Show input item for cooking
		var input_label: Label = Label.new()
		input_label.text = "Requires: %s" % recipe_name
		input_label.name = "Material_" + recipe_name
		materials_container.add_child(input_label)
	
	# Craft/Cook button
	var button: Button = Button.new()
	button.text = "Craft" if is_crafting else "Cook"
	button.name = "CraftButton"
	
	# Connect button signal
	if is_crafting:
		button.pressed.connect(_on_craft_button_pressed.bind(recipe_name))
	else:
		button.pressed.connect(_on_cook_button_pressed.bind(recipe_name))
	
	vbox.add_child(button)
	
	# Store recipe data in container for later use
	recipe_container.set_meta("recipe_name", recipe_name)
	recipe_container.set_meta("recipe_data", recipe_data)
	recipe_container.set_meta("is_crafting", is_crafting)
	
	return recipe_container

func _refresh_recipe_displays() -> void:
	"""Update all recipe displays based on current inventory."""
	if not player_inventory:
		return
	
	# Update crafting recipes
	for child in crafting_grid.get_children():
		_update_recipe_slot(child)
	
	# Update cooking recipes
	for child in cooking_grid.get_children():
		_update_recipe_slot(child)

func _update_recipe_slot(recipe_slot: Control) -> void:
	"""Update a single recipe slot based on inventory availability."""
	if not recipe_slot.has_meta("recipe_data"):
		return
	
	var recipe_name: String = recipe_slot.get_meta("recipe_name")
	var recipe_data: Dictionary = recipe_slot.get_meta("recipe_data")
	var is_crafting: bool = recipe_slot.get_meta("is_crafting", true)
	
	var can_craft: bool = true
	var missing_materials: Array[String] = []
	
	if is_crafting:
		# Check materials for crafting
		var materials: Dictionary = recipe_data.get("materials", {})
		for material_name in materials:
			var required_count: int = materials[material_name]
			var current_count: int = player_inventory.get_item_count(material_name)
			
			# Update material label color
			var material_label: Label = recipe_slot.find_child("Material_" + material_name, true, false)
			if material_label:
				if current_count >= required_count:
					material_label.add_theme_color_override("font_color", Color.GREEN)
					material_label.text = "%s x%d/%d  " % [material_name, current_count, required_count]
				else:
					material_label.add_theme_color_override("font_color", Color.RED)
					material_label.text = "%s x%d/%d  " % [material_name, current_count, required_count]
					can_craft = false
					missing_materials.append(material_name)
	else:
		# Check input item for cooking
		var current_count: int = player_inventory.get_item_count(recipe_name)
		var material_label: Label = recipe_slot.find_child("Material_" + recipe_name, true, false)
		if material_label:
			if current_count > 0:
				material_label.add_theme_color_override("font_color", Color.GREEN)
				material_label.text = "Requires: %s (x%d available)" % [recipe_name, current_count]
			else:
				material_label.add_theme_color_override("font_color", Color.RED)
				material_label.text = "Requires: %s (none available)" % recipe_name
				can_craft = false
	
	# Update button state
	var button: Button = recipe_slot.find_child("CraftButton", true, false)
	if button:
		button.disabled = not can_craft
		if not can_craft and missing_materials.size() > 0:
			button.tooltip_text = "Missing: " + ", ".join(missing_materials)
		else:
			button.tooltip_text = ""

func _on_craft_button_pressed(recipe_name: String) -> void:
	"""Handle crafting button press."""
	if not player_inventory or not campfire_ref:
		return
	
	var recipe_data: Dictionary = GameConstants.CRAFTING_RECIPES.get(recipe_name, {})
	var materials: Dictionary = recipe_data.get("materials", {})
	
	# Double-check we have all materials
	for material_name in materials:
		var required_count: int = materials[material_name]
		if player_inventory.get_item_count(material_name) < required_count:
			print("CampfireMenu: Cannot craft %s - insufficient %s" % [recipe_name, material_name])
			return
	
	# Remove materials from inventory
	for material_name in materials:
		var required_count: int = materials[material_name]
		player_inventory.remove_item_by_name(material_name, required_count)
	
	# Add crafted item to inventory
	player_inventory.add_item(recipe_name, 1)
	
	# Play crafting sound/effect
	print("CampfireMenu: Crafted %s!" % recipe_name)
	
	# Emit signal
	item_crafted.emit(recipe_name)
	
	# Refresh displays
	_refresh_recipe_displays()

func _on_cook_button_pressed(input_item: String) -> void:
	"""Handle cooking button press."""
	if not player_inventory or not campfire_ref:
		return
	
	# Check if we have the input item
	if player_inventory.get_item_count(input_item) < 1:
		print("CampfireMenu: Cannot cook - no %s available" % input_item)
		return
	
	# Remove input item
	player_inventory.remove_item_by_name(input_item, 1)
	
	# Start cooking on campfire
	if campfire_ref.has_method("start_cooking"):
		var items_to_cook: Array[String] = [input_item]
		campfire_ref.start_cooking(items_to_cook)
	
	# Close menu to show cooking animation
	close_menu()
	
	print("CampfireMenu: Started cooking %s!" % input_item)
	
	# Emit signal
	item_cooked.emit(input_item)

func _on_background_input(event: InputEvent) -> void:
	"""Handle clicks on background to close menu."""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_menu() 
