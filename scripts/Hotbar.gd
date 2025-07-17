class_name Hotbar
extends Control

# Emitted when the selected slot changes.
signal selection_changed(slot_index: int, item_name: String)

# --- Constants ---
const SLOT_COUNT: int = 5
const STARTER_ITEM: String = "Hatchet"
const EMPTY_SLOT: String = ""

# Style Constants - Rustic Bark & Moss Theme
const FONT_SIZE_ITEM: int = 14
const FONT_SIZE_SLOT_NUMBER: int = 12
const COLOR_SLOT_NORMAL: Color = Color(0.8, 0.75, 0.7, 0.9)
const COLOR_SLOT_SELECTED: Color = Color(0.98, 0.94, 0.89, 1)
const COLOR_BORDER: Color = Color(0.545, 0.357, 0.169, 1)
const COLOR_SLOT_NUMBER: Color = Color(0.918, 0.878, 0.835, 1)
const COLOR_TEXT: Color = Color(0.204, 0.306, 0.255, 1)
const COLOR_TEXT_SHADOW: Color = Color(0.918, 0.878, 0.835, 0.3)


# --- Properties ---
@export var slot_size: Vector2 = Vector2(64, 64)

var slots: Array[Panel] = []
var selected_slot: int = 0
var items: Array[String] = []

@onready var slot_container: HBoxContainer = $HotbarBackground/HBoxContainer


func _ready() -> void:
	print("Hotbar: Initializing...")
	_initialize_items()
	_create_slots()
	select_slot(0) # Select the first slot by default
	print("Hotbar: Ready! Created ", slots.size(), " slots with items: ", items)


func _input(event: InputEvent) -> void:
	# Handle number key selection
	for i in range(SLOT_COUNT):
		if event.is_action_pressed("slot_" + str(i + 1)):
			select_slot(i)
			return
	
	# Handle scroll wheel
	if event.is_action_pressed("scroll_up"):
		# Using % for proper wrapping with negative numbers
		var new_slot = (selected_slot - 1 + SLOT_COUNT) % SLOT_COUNT
		select_slot(new_slot)
	elif event.is_action_pressed("scroll_down"):
		var new_slot = (selected_slot + 1) % SLOT_COUNT
		select_slot(new_slot)


func _initialize_items() -> void:
	"""Sets up the initial state of the items array."""
	items.resize(SLOT_COUNT)
	items.fill(EMPTY_SLOT)
	items[0] = STARTER_ITEM


func _create_slots() -> void:
	"""Creates the visual slot elements for the hotbar with rustic Bark & Moss styling."""
	print("Hotbar: Creating ", SLOT_COUNT, " slots...")
	for i in range(SLOT_COUNT):
		var slot := Panel.new()
		slot.custom_minimum_size = slot_size
		slot.name = "Slot" + str(i)
		
		# Create rustic styled slot with shadows and rounded corners
		var style := StyleBoxFlat.new()
		style.bg_color = COLOR_SLOT_NORMAL
		style.border_color = COLOR_BORDER
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.shadow_color = Color(0.137, 0.2, 0.165, 0.4)
		style.shadow_size = 2
		style.shadow_offset = Vector2(1, 2)
		slot.add_theme_stylebox_override("panel", style)
		
		# Add item label with rustic styling
		var label := Label.new()
		label.text = ""
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.add_theme_font_size_override("font_size", FONT_SIZE_ITEM)
		label.add_theme_color_override("font_color", COLOR_TEXT)
		label.add_theme_color_override("font_shadow_color", COLOR_TEXT_SHADOW)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		slot.add_child(label)
		
		# Add slot number with rustic styling
		var number_label := Label.new()
		number_label.text = str(i + 1)
		number_label.position = Vector2(4, 4)
		number_label.add_theme_font_size_override("font_size", FONT_SIZE_SLOT_NUMBER)
		number_label.add_theme_color_override("font_color", COLOR_SLOT_NUMBER)
		number_label.add_theme_color_override("font_shadow_color", COLOR_TEXT_SHADOW)
		number_label.add_theme_constant_override("shadow_offset_x", 1)
		number_label.add_theme_constant_override("shadow_offset_y", 1)
		slot.add_child(number_label)
		
		slot_container.add_child(slot)
		slots.append(slot)
	
	print("Hotbar: Successfully created ", slots.size(), " slot panels")
	_update_hotbar_visuals()


func select_slot(index: int) -> void:
	"""Selects a hotbar slot, updates visuals, and emits a signal."""
	if index < 0 or index >= SLOT_COUNT:
		return
		
	selected_slot = index
	_update_hotbar_visuals()
	
	emit_signal("selection_changed", selected_slot, items[selected_slot])


func _update_hotbar_visuals() -> void:
	"""Updates the visual representation of the hotbar slots and items."""
	for i in range(slots.size()):
		var slot: Panel = slots[i]
		var label: Label = slot.get_child(0) as Label
		var style: StyleBoxFlat = slot.get_theme_stylebox("panel") as StyleBoxFlat
		
		# Show item names, but only if the slot is not empty
		var item: String = items[i]
		if item != EMPTY_SLOT:
			label.text = item
		else:
			label.text = ""
		
		# Update selection highlight with enhanced rustic styling
		if i == selected_slot:
			style.bg_color = COLOR_SLOT_SELECTED
			style.set_border_width_all(3)
			style.shadow_size = 4
			style.shadow_offset = Vector2(0, 2)
		else:
			style.bg_color = COLOR_SLOT_NORMAL
			style.set_border_width_all(2)
			style.shadow_size = 2
			style.shadow_offset = Vector2(1, 2)


func add_item(item_name: String) -> bool:
	"""
	Adds an item to the first available empty slot in the hotbar.
	Returns true if the item was added, false otherwise.
	"""
	for i in range(items.size()):
		if items[i] == EMPTY_SLOT:
			items[i] = item_name
			_update_hotbar_visuals()
			return true
	return false


func remove_item(slot_index: int) -> void:
	"""Removes an item from a specific slot."""
	if slot_index >= 0 and slot_index < items.size():
		items[slot_index] = EMPTY_SLOT
		_update_hotbar_visuals()


func get_selected_item() -> String:
	"""Returns the name of the item in the currently selected slot."""
	return items[selected_slot]


func get_item_at_slot(slot_index: int) -> String:
	"""Returns the name of the item at a specific slot index."""
	if slot_index >= 0 and slot_index < items.size():
		return items[slot_index]
	return EMPTY_SLOT 
