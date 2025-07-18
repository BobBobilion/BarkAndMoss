class_name Inventory
extends Control

# --- Scripts ---
const PlayerScript: Script = preload("res://scripts/Player.gd")

# --- Signals ---
signal item_used(item_name: String)
signal item_equipped(item_name: String)

# --- Constants ---
const GRID_COLUMNS: int = GameConstants.UI.INVENTORY_GRID_COLUMNS
const GRID_ROWS: int = GameConstants.UI.INVENTORY_GRID_ROWS
const SLOT_SIZE: Vector2 = GameConstants.UI.SLOT_SIZE
const SLOT_SPACING: Vector2 = GameConstants.UI.SLOT_SPACING
const EMPTY_SLOT: String = ""
const ICON_SIZE: int = GameConstants.UI.SLOT_ICON_SIZE
const MAX_STACK_SIZE: int = 99  # Maximum items per stack

# Using shared style constants from GameConstants.UI
const FONT_SIZE_TOOLTIP: int = GameConstants.UI.FONT_SIZE_TOOLTIP
const FONT_SIZE_COUNT: int = 12  # Font size for item count label
const COLOR_BACKGROUND: Color = GameConstants.UI.COLOR_BACKGROUND
const COLOR_SLOT_NORMAL: Color = GameConstants.UI.COLOR_SLOT_NORMAL
const COLOR_SLOT_SELECTED: Color = GameConstants.UI.COLOR_SLOT_SELECTED
const COLOR_SLOT_BORDER: Color = GameConstants.UI.COLOR_SLOT_BORDER
const COLOR_TEXT: Color = GameConstants.UI.COLOR_TEXT
const COLOR_TEXT_SHADOW: Color = GameConstants.UI.COLOR_TEXT_SHADOW

# --- Node References ---
@onready var background: ColorRect = $Background
@onready var inventory_panel: PanelContainer = $CenterContainer/InventoryPanel
@onready var grid_container: GridContainer = $CenterContainer/InventoryPanel/VBoxContainer/GridContainer
@onready var tooltip: PanelContainer = $Tooltip
@onready var tooltip_label: Label = $Tooltip/TooltipLabel

# --- State ---
var inventory_items: Array[Dictionary] = []  # Array of {item_name: String, count: int}
var slot_controls: Array[Control] = []
var is_open: bool = false
var player: CharacterBody3D

# --- Item Definitions ---
# Using centralized item descriptions from GameConstants
func get_item_description(item_name: String) -> String:
	# Handle empty slot case without modifying the original dictionary
	if item_name == EMPTY_SLOT:
		return "An empty slot. Ready to hold treasures."
	
	# Get description from centralized constants
	return GameConstants.ITEM_DESCRIPTIONS.get(item_name, "Unknown item.")


# --- Engine Callbacks ---

func _ready() -> void:
	_initialize_inventory()
	_setup_ui()
	_create_inventory_grid()
	
	# Start hidden
	visible = false
	is_open = false
	
	# Find player
	call_deferred("_find_player")


func _input(event: InputEvent) -> void:
	# Check if player exists, is in tree, and multiplayer peer exists before checking authority
	if not is_instance_valid(player) or not player.is_inside_tree() or not multiplayer or not multiplayer.multiplayer_peer:
		return
	
	if not player.is_multiplayer_authority():
		return
	
	# Handle inventory toggle (hold Tab)
	if event.is_action_pressed("inventory"):
		print("Inventory: Tab pressed - opening inventory")
		open_inventory()
	elif event.is_action_released("inventory"):
		print("Inventory: Tab released - closing inventory")
		close_inventory()


# --- Public Methods ---

func add_item(item_name: String, quantity: int = 1) -> bool:
	"""Adds items to inventory. First tries to stack with existing items, then uses empty slots."""
	var remaining: int = quantity
	
	# First, try to fill existing stacks
	for i in range(inventory_items.size()):
		if remaining <= 0:
			break
		if inventory_items[i].item_name == item_name and inventory_items[i].count < MAX_STACK_SIZE:
			var space_in_stack: int = MAX_STACK_SIZE - inventory_items[i].count
			var to_add: int = min(remaining, space_in_stack)
			inventory_items[i].count += to_add
			remaining -= to_add
	
	# Then, use empty slots for remaining items
	while remaining > 0:
		var empty_slot_found: bool = false
		for i in range(inventory_items.size()):
			if inventory_items[i].item_name == EMPTY_SLOT:
				inventory_items[i].item_name = item_name
				inventory_items[i].count = min(remaining, MAX_STACK_SIZE)
				remaining -= inventory_items[i].count
				empty_slot_found = true
				break
		
		if not empty_slot_found:
			_update_inventory_display()
			return false  # Inventory full, couldn't add all items
	
	_update_inventory_display()
	return true  # All items added successfully


func remove_item(slot_index: int) -> void:
	"""Removes one item from a specific slot index. If count reaches 0, clears the slot."""
	if slot_index >= 0 and slot_index < inventory_items.size():
		inventory_items[slot_index].count -= 1
		if inventory_items[slot_index].count <= 0:
			inventory_items[slot_index].item_name = EMPTY_SLOT
			inventory_items[slot_index].count = 0
		_update_inventory_display()

# Method to remove items by name and quantity
func remove_item_by_name(item_name: String, quantity: int = 1) -> bool:
	"""Removes specified quantity of an item by name. Returns true if successful."""
	var remaining_to_remove: int = quantity
	
	# First pass: remove from existing stacks
	for i in range(inventory_items.size()):
		if remaining_to_remove <= 0:
			break
		if inventory_items[i].item_name == item_name:
			var remove_count: int = min(inventory_items[i].count, remaining_to_remove)
			inventory_items[i].count -= remove_count
			remaining_to_remove -= remove_count
			
			# Clear slot if empty
			if inventory_items[i].count <= 0:
				inventory_items[i].item_name = EMPTY_SLOT
				inventory_items[i].count = 0
	
	# Update display after all removals
	_update_inventory_display()
	
	# Return true if we removed everything requested
	return remaining_to_remove == 0


func get_item_at_slot(slot_index: int) -> String:
	"""Returns the item name at a given slot index."""
	if slot_index >= 0 and slot_index < inventory_items.size():
		return inventory_items[slot_index].item_name
	return EMPTY_SLOT


func get_count_at_slot(slot_index: int) -> int:
	"""Returns the item count at a given slot index."""
	if slot_index >= 0 and slot_index < inventory_items.size():
		return inventory_items[slot_index].count
	return 0


func has_item(item_name: String) -> bool:
	"""Checks if the inventory contains a specific item."""
	for slot in inventory_items:
		if slot.item_name == item_name and slot.count > 0:
			return true
	return false


func get_item_count(item_name: String) -> int:
	"""Returns the total count of a specific item across all slots."""
	var total_count: int = 0
	for slot in inventory_items:
		if slot.item_name == item_name:
			total_count += slot.count
	return total_count


# --- Private Methods (Setup) ---

func _initialize_inventory() -> void:
	"""Initializes the inventory array with empty slots."""
	inventory_items.clear()
	for i in range(GRID_COLUMNS * GRID_ROWS):
		inventory_items.append({
			"item_name": EMPTY_SLOT,
			"count": 0
		})


func _find_player() -> void:
	"""Finds the local player node."""
	var players: Array[Node] = get_tree().get_nodes_in_group("human_player")
	for p in players:
		# Check if multiplayer peer exists before checking authority
		if multiplayer and multiplayer.multiplayer_peer and p.is_multiplayer_authority():
			player = p
			return


func _setup_ui() -> void:
	"""Sets up the initial state and properties of UI elements."""
	background.color = COLOR_BACKGROUND
	background.mouse_filter = MOUSE_FILTER_STOP
	
	# Center the inventory panel
	inventory_panel.position = (get_viewport_rect().size - inventory_panel.size) / 2
	
	grid_container.columns = GRID_COLUMNS
	grid_container.add_theme_constant_override("h_separation", int(SLOT_SPACING.x))
	grid_container.add_theme_constant_override("v_separation", int(SLOT_SPACING.y))
	
	tooltip.visible = false
	tooltip_label.add_theme_font_size_override("font_size", FONT_SIZE_TOOLTIP)
	tooltip_label.add_theme_color_override("font_color", COLOR_TEXT)





func _create_inventory_grid() -> void:
	"""Creates and configures all the inventory slot controls."""
	for child in grid_container.get_children():
		child.queue_free()
	slot_controls.clear()
	
	for i in range(GRID_COLUMNS * GRID_ROWS):
		var slot: Panel = _create_inventory_slot(i)
		grid_container.add_child(slot)
		slot_controls.append(slot)


func _create_inventory_slot(index: int) -> Panel:
	"""Creates a single inventory slot panel with TextureRect for item icons."""
	var slot := Panel.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.name = "Slot" + str(index)
	
	# Create rustic styled slot with shadows and rounded corners
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_SLOT_NORMAL
	style.border_color = COLOR_SLOT_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0.137, 0.2, 0.165, 0.4)
	style.shadow_size = 2
	style.shadow_offset = Vector2(1, 2)
	slot.add_theme_stylebox_override("panel", style)
	
	# Add TextureRect for item icon that fills the entire slot with rounded corners
	var texture_rect := TextureRect.new()
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # Allow texture to expand/shrink to fill
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE  # Scale texture to fill entire rect, making it square
	
	# Make it fill the entire slot area minus the border
	var border_width = 2
	texture_rect.position = Vector2(border_width, border_width)
	texture_rect.size = Vector2(SLOT_SIZE.x - border_width * 2, SLOT_SIZE.y - border_width * 2)
	
	# Add rounded corners to match the slot style - clip the texture
	var texture_style := StyleBoxFlat.new()
	texture_style.bg_color = Color.TRANSPARENT  # Keep transparent background
	texture_style.set_corner_radius_all(4)  # Slightly smaller radius than slot (6 - border = 4)
	texture_rect.add_theme_stylebox_override("normal", texture_style)
	
	# Set clip contents to true so the rounded corners actually clip the image
	texture_rect.clip_contents = true
	
	slot.add_child(texture_rect)
	
	# Add a count label in the bottom left corner
	var count_label := Label.new()
	count_label.name = "CountLabel"
	count_label.add_theme_font_size_override("font_size", FONT_SIZE_COUNT)
	count_label.add_theme_color_override("font_color", COLOR_TEXT)
	count_label.add_theme_color_override("font_shadow_color", COLOR_TEXT_SHADOW)
	count_label.add_theme_constant_override("shadow_offset_x", 1)
	count_label.add_theme_constant_override("shadow_offset_y", 1)
	count_label.add_theme_constant_override("shadow_outline_size", 1)
	count_label.text = ""  # Start empty
	count_label.visible = false  # Hidden by default
	
	# Position the count label in bottom left corner
	count_label.set_position(Vector2(4, SLOT_SIZE.y - 18))  # Slight padding from edges
	count_label.z_index = 1  # Ensure it's above the texture
	
	slot.add_child(count_label)
	
	slot.mouse_filter = MOUSE_FILTER_PASS
	slot.mouse_entered.connect(_on_slot_mouse_entered.bind(index))
	slot.mouse_exited.connect(_on_slot_mouse_exited)
	slot.gui_input.connect(_on_slot_gui_input.bind(index))
	
	return slot


# --- Private Methods (UI Logic) ---

func open_inventory() -> void:
	"""Opens the inventory panel and captures the mouse."""
	if is_open:
		return
	
	is_open = true
	visible = true
	_update_inventory_display()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func close_inventory() -> void:
	"""Closes the inventory panel and restores mouse control."""
	if not is_open:
		return
	
	is_open = false
	visible = false
	tooltip.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _update_inventory_display() -> void:
	"""Refreshes the visual state of each slot to match the inventory data."""
	for i in range(slot_controls.size()):
		var slot: Control = slot_controls[i]
		var texture_rect: TextureRect = slot.get_child(0) as TextureRect
		var count_label: Label = slot.get_node("CountLabel") as Label
		
		# Set item icon texture using the centralized icon manager, or clear if slot is empty
		var item_data: Dictionary = inventory_items[i]
		var item_name: String = item_data.item_name
		var count: int = item_data.count
		
		if item_name != EMPTY_SLOT and count > 0:
			# Show item icon
			texture_rect.texture = GameConstants.ItemIconManager.get_item_icon(item_name)
			
			# Update count label - only show if count > 1
			if count > 1:
				count_label.text = str(count)
				count_label.visible = true
			else:
				count_label.visible = false
		else:
			# Clear the slot
			texture_rect.texture = null
			count_label.visible = false


# --- Private Methods (Event Handlers) ---

func _on_slot_mouse_entered(slot_index: int) -> void:
	"""Shows the item tooltip when the mouse enters a slot."""
	if not is_open:
		return
	
	var item_data: Dictionary = inventory_items[slot_index]
	var item_name: String = item_data.item_name
	var count: int = item_data.count
	var description: String = get_item_description(item_name)
	
	if not description.is_empty():
		# Add count to tooltip if more than 1
		if count > 1:
			tooltip_label.text = description + "\n\nCount: " + str(count)
		else:
			tooltip_label.text = description
		tooltip.position = get_global_mouse_position() + Vector2(10, 10)
		_clamp_tooltip_to_screen()
		tooltip.visible = true


func _on_slot_mouse_exited() -> void:
	"""Hides the tooltip when the mouse leaves a slot."""
	tooltip.visible = false


func _on_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	"""Handles mouse clicks on inventory slots."""
	if not is_open or not (event is InputEventMouseButton and event.is_pressed()):
		return
	
	var item: String = inventory_items[slot_index].item_name
	if item == EMPTY_SLOT:
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		_handle_left_click(item, slot_index)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_right_click(item, slot_index)


func _handle_left_click(item: String, index: int) -> void:
	"""Handles left-click actions, like using or equipping items."""
	if item == "Cooked Meat":
		_consume_item(index)
	else:
		_equip_to_hotbar(item, index)


func _handle_right_click(_item: String, _index: int) -> void:
	"""Placeholder for future right-click actions."""
	pass # e.g., drop item, split stack


func _consume_item(slot_index: int) -> void:
	"""Consumes an item and removes it from the inventory."""
	var item: String = inventory_items[slot_index].item_name
	if item == "Cooked Meat":
		emit_signal("item_used", item)
		remove_item(slot_index)


func _equip_to_hotbar(item_name: String, slot_index: int) -> void:
	"""Tries to add an item to the hotbar."""
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_node("Hotbar"):
		var hotbar := hud.get_node("Hotbar")
		
		# Get the full quantity of the item
		var item_data: Dictionary = inventory_items[slot_index]
		var quantity: int = item_data.count
		
		# Try to add the entire stack to hotbar
		if hotbar.add_item(item_name, quantity):
			# Remove entire stack from inventory
			inventory_items[slot_index].item_name = EMPTY_SLOT
			inventory_items[slot_index].count = 0
			_update_inventory_display()
			emit_signal("item_equipped", item_name)
			print("Inventory: Moved ", quantity, " x ", item_name, " to hotbar")


func _clamp_tooltip_to_screen() -> void:
	"""Ensures the tooltip stays within the viewport boundaries."""
	var viewport_rect: Rect2 = get_viewport_rect()
	var tooltip_rect: Rect2 = tooltip.get_global_rect()

	if tooltip_rect.end.x > viewport_rect.end.x:
		tooltip.global_position.x = viewport_rect.end.x - tooltip_rect.size.x
	if tooltip_rect.end.y > viewport_rect.end.y:
		tooltip.global_position.y = viewport_rect.end.y - tooltip_rect.size.y 
