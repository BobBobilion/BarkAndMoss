class_name Hotbar
extends Control

# Emitted when the selected slot changes.
signal selection_changed(slot_index: int, item_name: String)

# --- Constants ---
const SLOT_COUNT: int = 5
const STARTER_ITEM: String = "Axe"
const EMPTY_SLOT: String = ""

# Using shared style constants from GameConstants.UI
const ICON_SIZE: int = GameConstants.UI.SLOT_ICON_SIZE
const FONT_SIZE_SLOT_NUMBER: int = GameConstants.UI.FONT_SIZE_SLOT_NUMBER
const FONT_SIZE_TOOLTIP: int = GameConstants.UI.FONT_SIZE_TOOLTIP
const COLOR_SLOT_NORMAL: Color = GameConstants.UI.COLOR_SLOT_NORMAL
const COLOR_SLOT_SELECTED: Color = GameConstants.UI.COLOR_SLOT_SELECTED
const COLOR_BORDER: Color = GameConstants.UI.COLOR_SLOT_BORDER
const COLOR_SLOT_NUMBER: Color = GameConstants.UI.COLOR_SLOT_NUMBER
const COLOR_BACKGROUND: Color = GameConstants.UI.COLOR_BACKGROUND
const COLOR_TEXT: Color = GameConstants.UI.COLOR_TEXT
const COLOR_TEXT_SHADOW: Color = GameConstants.UI.COLOR_TEXT_SHADOW


# --- Properties ---
@export var slot_size: Vector2 = Vector2(64, 64)

var slots: Array[Panel] = []
var selected_slot: int = 0
# Changed to support quantities: Array of dictionaries with item_name and count
var items: Array[Dictionary] = []

@onready var slot_container: HBoxContainer = $HotbarBackground/HBoxContainer

# Add tooltip functionality (similar to inventory)
var tooltip: PanelContainer
var tooltip_label: Label


func _ready() -> void:
	print("Hotbar: Initializing...")
	print("Hotbar: slot_container path check: ", has_node("HotbarBackground/HBoxContainer"))
	
	# Manually get the slot_container if @onready failed
	if not slot_container:
		print("Hotbar: @onready slot_container failed, trying manual reference...")
		if has_node("HotbarBackground/HBoxContainer"):
			slot_container = get_node("HotbarBackground/HBoxContainer")
			print("Hotbar: Manual slot_container reference successful")
		else:
			print("Hotbar: Error - Cannot find HBoxContainer! Checking node structure...")
			print("Hotbar: Available children:")
			for child in get_children():
				print("  - ", child.name, " (", child.get_class(), ")")
				if child.has_method("get_children"):
					for subchild in child.get_children():
						print("    - ", subchild.name, " (", subchild.get_class(), ")")
			return
	
	_initialize_items()
	_create_slots()
	_create_tooltip()
	
	# Ensure hotbar is visible and properly styled
	visible = true
	modulate = Color.WHITE  # Ensure it's not transparent
	
	select_slot(0) # Select the first slot by default
	print("Hotbar: Ready! Created ", slots.size(), " slots with items: ", items)
	print("Hotbar: Final visibility: ", visible, " modulate: ", modulate)
	print("Hotbar: Slot container children: ", slot_container.get_child_count() if slot_container else "None")


func _input(event: InputEvent) -> void:
	# Handle number key selection
	for i in range(SLOT_COUNT):
		if event.is_action_pressed("slot_" + str(i + 1)):
			print("Hotbar: Slot ", i + 1, " key pressed!")
			select_slot(i)
			return
	
	# Handle scroll wheel
	if event.is_action_pressed("scroll_up"):
		print("Hotbar: Scroll up detected!")
		# Using % for proper wrapping with negative numbers
		var new_slot = (selected_slot - 1 + SLOT_COUNT) % SLOT_COUNT
		select_slot(new_slot)
	elif event.is_action_pressed("scroll_down"):
		print("Hotbar: Scroll down detected!")
		var new_slot = (selected_slot + 1) % SLOT_COUNT
		select_slot(new_slot)


func _initialize_items() -> void:
	"""Sets up the initial state of the items array."""
	items.resize(SLOT_COUNT)
	
	# Initialize each slot with empty item data
	for i in range(SLOT_COUNT):
		items[i] = {"item_name": EMPTY_SLOT, "count": 0}
	
	# Set starter item in first slot
	items[0] = {"item_name": STARTER_ITEM, "count": 1}


func _create_slots() -> void:
	"""Creates the visual slot elements for the hotbar with rustic Bark & Moss styling."""
	print("Hotbar: Creating ", SLOT_COUNT, " slots...")
	
	# First ensure the background is visible and styled
	var background = get_node("HotbarBackground")
	if background:
		background.visible = true
		background.modulate = Color.WHITE
		
		# Add a background style to the PanelContainer
		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = Color(0.2, 0.2, 0.2, 0.8)  # Semi-transparent dark background
		bg_style.border_color = COLOR_BORDER
		bg_style.set_border_width_all(2)
		bg_style.set_corner_radius_all(8)
		background.add_theme_stylebox_override("panel", bg_style)
		
		print("Hotbar: Background set to visible with styling")
	
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
		
		# Add TextureRect for item icon that fills the entire slot with rounded corners
		var texture_rect := TextureRect.new()
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # Allow texture to expand/shrink to fill
		texture_rect.stretch_mode = TextureRect.STRETCH_SCALE  # Scale texture to fill entire rect, making it square
		
		# Make it fill the entire slot area minus the border
		var border_width = 2
		texture_rect.position = Vector2(border_width, border_width)
		texture_rect.size = Vector2(slot_size.x - border_width * 2, slot_size.y - border_width * 2)
		
		# Add rounded corners to match the slot style - clip the texture
		var texture_style := StyleBoxFlat.new()
		texture_style.bg_color = Color.TRANSPARENT  # Keep transparent background
		texture_style.set_corner_radius_all(4)  # Slightly smaller radius than slot (6 - border = 4)
		texture_rect.add_theme_stylebox_override("normal", texture_style)
		
		# Set clip contents to true so the rounded corners actually clip the image
		texture_rect.clip_contents = true
		
		slot.add_child(texture_rect)
		
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
		
		# Add count label for item quantities (bottom-left corner)
		var count_label := Label.new()
		count_label.name = "CountLabel"
		count_label.text = ""
		count_label.position = Vector2(4, slot_size.y - 16)  # Bottom-left
		count_label.add_theme_font_size_override("font_size", FONT_SIZE_SLOT_NUMBER)
		count_label.add_theme_color_override("font_color", COLOR_SLOT_NUMBER)
		count_label.add_theme_color_override("font_shadow_color", COLOR_TEXT_SHADOW)
		count_label.add_theme_constant_override("shadow_offset_x", 1)
		count_label.add_theme_constant_override("shadow_offset_y", 1)
		count_label.visible = false  # Hidden by default
		slot.add_child(count_label)
		
		# Add mouse event handlers for tooltip functionality
		slot.mouse_entered.connect(_on_slot_mouse_entered.bind(i))
		slot.mouse_exited.connect(_on_slot_mouse_exited)
		
		slot_container.add_child(slot)
		slots.append(slot)
		print("Hotbar: Created slot ", i, " with size ", slot.custom_minimum_size)
	
	print("Hotbar: Successfully created ", slots.size(), " slot panels")
	_update_hotbar_visuals()


func select_slot(index: int) -> void:
	"""Selects a hotbar slot, updates visuals, and emits a signal."""
	if index < 0 or index >= SLOT_COUNT:
		return
		
	selected_slot = index
	_update_hotbar_visuals()
	
	emit_signal("selection_changed", selected_slot, items[selected_slot].item_name)


func _update_hotbar_visuals() -> void:
	"""Updates the visual representation of the hotbar slots and items."""
	for i in range(slots.size()):
		var slot: Panel = slots[i]
		var texture_rect: TextureRect = slot.get_child(0) as TextureRect
		var count_label: Label = slot.get_node("CountLabel") as Label
		var style: StyleBoxFlat = slot.get_theme_stylebox("panel") as StyleBoxFlat
		
		# Show item icons using the centralized icon manager, or clear if slot is empty
		var item: String = items[i].item_name
		var count: int = items[i].count
		
		if item != EMPTY_SLOT and count > 0:
			texture_rect.texture = GameConstants.ItemIconManager.get_item_icon(item)
			
			# Show count if > 1
			if count > 1:
				count_label.text = str(count)
				count_label.visible = true
			else:
				count_label.visible = false
		else:
			texture_rect.texture = null
			count_label.visible = false
		
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
			style.shadow_offset = Vector2(0, 1)


func add_item(item_name: String, quantity: int = 1) -> bool:
	"""
	Adds an item to the hotbar with stacking support.
	First tries to stack with existing items, then finds an empty slot.
	Returns true if the item was added, false otherwise.
	"""
	if item_name == EMPTY_SLOT:
		return false
	
	var remaining_quantity: int = quantity
	
	# First pass: try to stack with existing items of the same type
	for i in range(items.size()):
		if items[i].item_name == item_name:
			# Stack with existing item
			items[i].count += remaining_quantity
			_update_hotbar_visuals()
			print("Hotbar: Stacked ", remaining_quantity, " ", item_name, " in slot ", i, " (total: ", items[i].count, ")")
			return true
	
	# Second pass: find an empty slot
	for i in range(items.size()):
		if items[i].item_name == EMPTY_SLOT:
			items[i].item_name = item_name
			items[i].count = remaining_quantity
			_update_hotbar_visuals()
			print("Hotbar: Added ", remaining_quantity, " ", item_name, " to slot ", i)
			return true
	
	print("Hotbar: Failed to add ", item_name, " - hotbar is full")
	return false


func remove_item(slot_index: int) -> void:
	"""Removes an item from a specific slot."""
	if slot_index >= 0 and slot_index < items.size():
		items[slot_index].item_name = EMPTY_SLOT
		items[slot_index].count = 0
		_update_hotbar_visuals()


func get_selected_item() -> String:
	"""Returns the name of the item in the currently selected slot."""
	return items[selected_slot].item_name


func get_item_at_slot(slot_index: int) -> String:
	"""Returns the name of the item at a specific slot index."""
	if slot_index >= 0 and slot_index < items.size():
		return items[slot_index].item_name
	return EMPTY_SLOT


# --- Tooltip System ---

func _create_tooltip() -> void:
	"""Creates the tooltip for displaying item names."""
	tooltip = PanelContainer.new()
	tooltip.name = "HotbarTooltip"
	tooltip.visible = false
	tooltip.z_index = 1000  # Ensure it appears on top
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Style the tooltip background
	var tooltip_style := StyleBoxFlat.new()
	tooltip_style.bg_color = COLOR_BACKGROUND
	tooltip_style.border_color = COLOR_BORDER
	tooltip_style.set_border_width_all(1)
	tooltip_style.set_corner_radius_all(4)
	tooltip.add_theme_stylebox_override("panel", tooltip_style)
	
	# Create the label
	tooltip_label = Label.new()
	tooltip_label.add_theme_font_size_override("font_size", FONT_SIZE_TOOLTIP)
	tooltip_label.add_theme_color_override("font_color", COLOR_TEXT)
	tooltip_label.add_theme_color_override("font_shadow_color", COLOR_TEXT_SHADOW)
	tooltip_label.add_theme_constant_override("shadow_offset_x", 1)
	tooltip_label.add_theme_constant_override("shadow_offset_y", 1)
	
	tooltip.add_child(tooltip_label)
	add_child(tooltip)


func _on_slot_mouse_entered(slot_index: int) -> void:
	"""Shows the item tooltip when the mouse enters a slot."""
	var item: String = items[slot_index].item_name
	if item != EMPTY_SLOT:
		# Get description from GameConstants
		var description: String = GameConstants.ITEM_DESCRIPTIONS.get(item, item)
		tooltip_label.text = description
		
		# Position tooltip above the slot
		var slot: Panel = slots[slot_index]
		var slot_global_pos: Vector2 = slot.global_position
		tooltip.position = Vector2(slot_global_pos.x, slot_global_pos.y - tooltip.size.y - 10)
		
		# Clamp tooltip to screen
		_clamp_tooltip_to_screen()
		tooltip.visible = true


func _on_slot_mouse_exited() -> void:
	"""Hides the tooltip when the mouse leaves a slot."""
	tooltip.visible = false


func _clamp_tooltip_to_screen() -> void:
	"""Ensures the tooltip stays within the viewport boundaries."""
	var viewport_rect: Rect2 = get_viewport_rect()
	var tooltip_rect: Rect2 = tooltip.get_global_rect()

	if tooltip_rect.end.x > viewport_rect.end.x:
		tooltip.global_position.x = viewport_rect.end.x - tooltip_rect.size.x
	if tooltip_rect.position.x < 0:
		tooltip.global_position.x = 0
	if tooltip_rect.position.y < 0:
		tooltip.global_position.y = tooltip_rect.size.y + 10 
