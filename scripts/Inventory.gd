class_name Inventory
extends Control

# --- Scripts ---
const PlayerScript: Script = preload("res://scripts/Player.gd")

# --- Signals ---
signal item_used(item_name: String)
signal item_equipped(item_name: String)

# --- Constants ---
const GRID_COLUMNS: int = 3
const GRID_ROWS: int = 4
const SLOT_SIZE: Vector2 = Vector2(64, 64)
const SLOT_SPACING: Vector2 = Vector2(8, 8)
const EMPTY_SLOT: String = ""

# Style Constants - Rustic Bark & Moss Theme
const FONT_SIZE_ITEM: int = 12
const FONT_SIZE_TOOLTIP: int = 14
const COLOR_BACKGROUND: Color = Color(0.137, 0.2, 0.165, 0.85)
const COLOR_SLOT_NORMAL: Color = Color(0.8, 0.75, 0.7, 0.9)
const COLOR_SLOT_SELECTED: Color = Color(0.98, 0.94, 0.89, 1)
const COLOR_SLOT_BORDER: Color = Color(0.545, 0.357, 0.169, 1)
const COLOR_TEXT: Color = Color(0.918, 0.878, 0.835, 1)
const COLOR_TEXT_SHADOW: Color = Color(0.137, 0.2, 0.165, 1)

# --- Node References ---
@onready var background: ColorRect = $Background
@onready var inventory_panel: PanelContainer = $CenterContainer/InventoryPanel
@onready var grid_container: GridContainer = $CenterContainer/InventoryPanel/VBoxContainer/GridContainer
@onready var tooltip: PanelContainer = $Tooltip
@onready var tooltip_label: Label = $Tooltip/TooltipLabel

# --- State ---
var inventory_items: Array[String] = []
var slot_controls: Array[Control] = []
var is_open: bool = false
var player: CharacterBody3D

# --- Item Definitions ---
var item_descriptions: Dictionary = {
	"Hatchet": "A trusty wooden axe. Perfect for chopping trees and clearing a path.",
	"Bow": "A simple but effective hunting bow. Great for taking down prey from a distance.",
	"Wood": "Freshly cut timber. Useful for crafting and building.",
	"Sinew": "Tough animal tendon. Essential for crafting more advanced tools.",
	"Raw Meat": "A bit too chewy to eat. If only I had a way to cook it...",
	"Cooked Meat": "A hearty meal that'll keep me going. Restores hunger when consumed.",
	EMPTY_SLOT: "An empty slot. Ready to hold treasures."
}


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
	if not is_instance_valid(player) or not player.is_multiplayer_authority():
		return
	
	# Handle inventory toggle (hold Tab)
	if event.is_action_pressed("inventory"):
		open_inventory()
	elif event.is_action_released("inventory"):
		close_inventory()


# --- Public Methods ---

func add_item(item_name: String) -> bool:
	"""Adds an item to the first available empty slot."""
	for i in range(inventory_items.size()):
		if inventory_items[i] == EMPTY_SLOT:
			inventory_items[i] = item_name
			_update_inventory_display()
			return true
	return false


func remove_item(slot_index: int) -> void:
	"""Removes an item from a specific slot index."""
	if slot_index >= 0 and slot_index < inventory_items.size():
		inventory_items[slot_index] = EMPTY_SLOT
		_update_inventory_display()


func get_item_at_slot(slot_index: int) -> String:
	"""Returns the item at a given slot index."""
	if slot_index >= 0 and slot_index < inventory_items.size():
		return inventory_items[slot_index]
	return EMPTY_SLOT


func has_item(item_name: String) -> bool:
	"""Checks if the inventory contains a specific item."""
	return inventory_items.has(item_name)


func get_item_count(item_name: String) -> int:
	"""Returns the count of a specific item in the inventory."""
	return inventory_items.count(item_name)


# --- Private Methods (Setup) ---

func _initialize_inventory() -> void:
	"""Initializes the inventory array with empty slots."""
	inventory_items.resize(GRID_COLUMNS * GRID_ROWS)
	inventory_items.fill(EMPTY_SLOT)


func _find_player() -> void:
	"""Finds the local player node."""
	var players: Array[Node] = get_tree().get_nodes_in_group("human_player")
	for p in players:
		if p.is_multiplayer_authority():
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
	"""Creates a single inventory slot panel with rustic Bark & Moss styling."""
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
	
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", FONT_SIZE_ITEM)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.add_theme_color_override("font_shadow_color", COLOR_TEXT_SHADOW)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	slot.add_child(label)
	
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
		var label: Label = slot.get_child(0) as Label
		# Show item names, but only if the slot is not empty
		var item: String = inventory_items[i]
		if item != EMPTY_SLOT:
			label.text = item
		else:
			label.text = ""


# --- Private Methods (Event Handlers) ---

func _on_slot_mouse_entered(slot_index: int) -> void:
	"""Shows the item tooltip when the mouse enters a slot."""
	if not is_open:
		return
	
	var item: String = inventory_items[slot_index]
	var description: String = item_descriptions.get(item, "")
	
	if not description.is_empty():
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
	
	var item: String = inventory_items[slot_index]
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
	var item: String = inventory_items[slot_index]
	if item == "Cooked Meat":
		emit_signal("item_used", item)
		remove_item(slot_index)


func _equip_to_hotbar(item_name: String, slot_index: int) -> void:
	"""Tries to add an item to the hotbar."""
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_node("Hotbar"):
		var hotbar := hud.get_node("Hotbar")
		if hotbar.add_item(item_name):
			remove_item(slot_index)
			emit_signal("item_equipped", item_name)


func _clamp_tooltip_to_screen() -> void:
	"""Ensures the tooltip stays within the viewport boundaries."""
	var viewport_rect: Rect2 = get_viewport_rect()
	var tooltip_rect: Rect2 = tooltip.get_global_rect()

	if tooltip_rect.end.x > viewport_rect.end.x:
		tooltip.global_position.x = viewport_rect.end.x - tooltip_rect.size.x
	if tooltip_rect.end.y > viewport_rect.end.y:
		tooltip.global_position.y = viewport_rect.end.y - tooltip_rect.size.y 
