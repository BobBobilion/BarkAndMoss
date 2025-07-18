# scripts/HUD.gd

class_name HUD
extends Control

# --- Scripts ---
const PlayerScript: Script = preload("res://scripts/Player.gd")
const HotbarScript: Script = preload("res://scripts/Hotbar.gd")
# const InventoryScript: Script = preload("res://scripts/Inventory.gd")
# If the above line causes issues, try loading the inventory scene directly when needed

# --- Constants ---
const CROSSHAIR_COLOR_DEFAULT: Color = Color.WHITE
const CROSSHAIR_BORDER_DEFAULT: Color = Color.BLACK
const CROSSHAIR_COLOR_INTERACT: Color = Color.GREEN
const CROSSHAIR_BORDER_INTERACT: Color = Color.DARK_GREEN
const CROSSHAIR_COLOR_BOW_LOADING: Color = Color.RED      # Red while bow is charging but not ready
const CROSSHAIR_BORDER_BOW_LOADING: Color = Color.DARK_RED
const CROSSHAIR_COLOR_BOW_READY: Color = Color.GREEN      # Green when bow is ready to fire
const CROSSHAIR_BORDER_BOW_READY: Color = Color.DARK_GREEN
const CROSSHAIR_CORNER_RADIUS: int = 3
const CROSSHAIR_BORDER_WIDTH: int = 1

# --- Node References ---
@onready var crosshair: Panel = $Crosshair/InteractionDot
@onready var interaction_prompt: Label = $InteractionPrompt
@onready var hotbar: Control = $Hotbar
@onready var inventory: Control = $Inventory

# --- State ---
var player: CharacterBody3D
var current_interactable: Node = null
var should_show_crosshair: bool = false  # Track if crosshair should be visible based on equipment


# --- Engine Callbacks ---

func _ready() -> void:
	print("HUD: Ready started")
	# Ensure clean state
	current_interactable = null
	
	# Add to groups
	add_to_group("hud")
	
	# Initialize nodes
	_setup_crosshair()
	
	# Ensure HUD renders on top of other UI elements
	z_index = 100
	visible = true
	modulate = Color.WHITE
	
	# Debug: Check hotbar visibility and positioning
	if hotbar:
		print("HUD: Hotbar found - Position: ", hotbar.position, " Size: ", hotbar.size, " Visible: ", hotbar.visible)
		print("HUD: Hotbar script attached: ", hotbar.get_script() != null)
		
		# Check the correct node path for HBoxContainer
		if hotbar.has_node("HotbarBackground/HBoxContainer"):
			var container = hotbar.get_node("HotbarBackground/HBoxContainer")
			print("HUD: HBoxContainer found - Position: ", container.position, " Size: ", container.size, " Children: ", container.get_child_count())
		else:
			print("HUD: Error - HBoxContainer not found at expected path!")
			print("HUD: Hotbar children: ")
			for child in hotbar.get_children():
				print("  - ", child.name, " (", child.get_class(), ")")
	else:
		print("HUD: Error - Hotbar node not found!")
	
	# Wait for the scene tree to be ready before finding the player
	await get_tree().process_frame
	_find_player()
	
	# Debug HUD nodes
	print("HUD: interaction_prompt node = ", interaction_prompt)
	print("HUD: interaction_prompt valid = ", is_instance_valid(interaction_prompt))
	if interaction_prompt:
		print("HUD: interaction_prompt position = ", interaction_prompt.position)
		print("HUD: interaction_prompt visible = ", interaction_prompt.visible)
	
	print("HUD: Ready!")


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		_find_player()
		return

	# Only the local player should perform interaction checks
	# Check if player is still in tree and multiplayer peer exists before checking authority
	if not player.is_inside_tree() or not multiplayer or not multiplayer.multiplayer_peer:
		return
	
	if not player.is_multiplayer_authority():
		return
	
	_check_for_interactable()


func _input(_event: InputEvent) -> void:
	# HUD should not handle interaction input - Player script handles this
	# Removing interaction input handling to avoid conflicts with Player script
	pass


# --- Initialization ---

func _find_player() -> void:
	"""Finds the local human player in the scene tree."""
	var players: Array[Node] = get_tree().get_nodes_in_group("human_player")
	print("HUD: Found ", players.size(), " players in human_player group")
	if not players.is_empty():
		for p in players:
			# In single player mode (no multiplayer peer) or if this is the authority
			if not multiplayer.has_multiplayer_peer() or p.is_multiplayer_authority():
				player = p
				print("HUD: Assigned player = ", player.name)
				return
	print("HUD: No suitable player found!")


func _setup_crosshair() -> void:
	"""Initializes the style of the crosshair."""
	var style := StyleBoxFlat.new()
	style.bg_color = CROSSHAIR_COLOR_DEFAULT
	style.border_color = CROSSHAIR_BORDER_DEFAULT
	style.border_width_left = CROSSHAIR_BORDER_WIDTH
	style.border_width_right = CROSSHAIR_BORDER_WIDTH
	style.border_width_top = CROSSHAIR_BORDER_WIDTH
	style.border_width_bottom = CROSSHAIR_BORDER_WIDTH
	style.set_corner_radius_all(CROSSHAIR_CORNER_RADIUS)
	crosshair.add_theme_stylebox_override("panel", style)


# --- Interaction Logic ---

func _check_for_interactable() -> void:
	"""
	Checks for the closest interactable object and updates the UI accordingly.
	"""
	if not player.has_method("get_interaction_controller"):
		print("HUD: Player has no get_interaction_controller method")
		return
		
	var interaction_controller = player.get_interaction_controller()
	if not interaction_controller:
		print("HUD: No interaction controller")
		return
	
	# print("HUD: Using InteractionController instance: ", interaction_controller.get_instance_id())  # Too spammy

	# Always get the current closest interactable from the player's controller.
	# The controller's function is responsible for cleaning up invalid nodes.
	var closest: Node = interaction_controller.get_closest_interactable()
	
	# Debug print - commented out as it's too frequent
	# if closest:
	# 	print("HUD: Closest interactable = ", closest.name)
	# else:
	# 	print("HUD: No closest interactable")
	
	# print("HUD: current_interactable = ", current_interactable.name if current_interactable else "None")  # Too spammy

	# Case 1: The closest interactable is new or different.
	if closest and closest != current_interactable:
		print("HUD: New interactable detected: ", closest.name)  # Keep this - it's an event
		current_interactable = closest
		_update_crosshair(true)
		
		# Try to get interaction prompt - first try method, then property
		var prompt: String = ""
		if current_interactable.has_method("get_interaction_prompt"):
			prompt = current_interactable.get_interaction_prompt()
			print("HUD: Showing prompt: ", prompt)  # Keep this - it's an event
		else:
			var property_value = current_interactable.get("interaction_prompt")
			prompt = property_value if property_value else "Interact"
			print("HUD: Showing prompt from property: ", prompt)  # Keep this - it's an event
		
		_show_interaction_prompt(prompt if prompt else "Interact")
	# Case 2: There is no longer a closest interactable, but we thought there was.
	elif not closest and current_interactable:
		print("HUD: Clearing interactable")  # Keep this - it's an event
		# This handles both looking away and the object being destroyed.
		_clear_current_interactable()
	# Case 3: We have the same interactable but the prompt might not be visible
	elif closest and closest == current_interactable:
		# Check if the prompt is actually visible
		if not interaction_prompt.visible:
			print("HUD: Re-showing prompt for: ", current_interactable.name)  # Keep this - it's an event
			var prompt: String = ""
			if current_interactable.has_method("get_interaction_prompt"):
				prompt = current_interactable.get_interaction_prompt()
			else:
				var property_value = current_interactable.get("interaction_prompt")
				prompt = property_value if property_value else "Interact"
			_show_interaction_prompt(prompt if prompt else "Interact")
		# else:
		# 	print("HUD: No change in interactable state")  # Too spammy


func _clear_current_interactable() -> void:
	"""Clears the current interactable and resets the UI."""
	if current_interactable != null:
		current_interactable = null
		_update_crosshair(false)
		_hide_interaction_prompt()


# --- UI Updates ---

func _update_crosshair(can_interact: bool) -> void:
	"""Updates the crosshair color to indicate interactability."""
	# Only update crosshair color if it's visible
	if not crosshair.visible:
		return
		
	# Get the current style and update colors
	var style: StyleBoxFlat = crosshair.get_theme_stylebox("panel")
	if not style:
		return
		
	if can_interact:
		style.bg_color = CROSSHAIR_COLOR_INTERACT
		style.border_color = CROSSHAIR_BORDER_INTERACT
	else:
		style.bg_color = CROSSHAIR_COLOR_DEFAULT
		style.border_color = CROSSHAIR_BORDER_DEFAULT


func _show_interaction_prompt(prompt_text: String) -> void:
	"""Shows the interaction prompt with the given text."""
	# print("HUD: _show_interaction_prompt called with: ", prompt_text)  # Already logged when detected
	
	# Always show interaction prompts - they're not tied to crosshair visibility
	interaction_prompt.text = prompt_text
	interaction_prompt.visible = true
	# print("HUD: Set interaction_prompt.visible = true")  # Too detailed
	# print("HUD: interaction_prompt node valid = ", is_instance_valid(interaction_prompt))  # Too detailed


func _hide_interaction_prompt() -> void:
	"""Hides the interaction prompt."""
	interaction_prompt.visible = false


# --- Public Methods ---

func update_crosshair_visibility(equipped_item: String) -> void:
	"""Updates crosshair visibility based on the currently equipped item."""
	# Only show crosshair when bow is equipped
	should_show_crosshair = (equipped_item == "Bow")
	
	# Update crosshair visibility
	crosshair.visible = should_show_crosshair
	
	# Don't hide interaction prompt when crosshair is hidden - interactions should always be available
	# (removed the code that was hiding interaction_prompt)
	
	print("HUD: Crosshair visibility updated - equipped: ", equipped_item, " visible: ", should_show_crosshair)

func update_bow_charge_crosshair(is_charging: bool, is_ready: bool) -> void:
	"""Updates crosshair color based on bow charge state."""
	if not should_show_crosshair or not crosshair.visible:
		return
		
	var style: StyleBoxFlat = crosshair.get_theme_stylebox("panel") as StyleBoxFlat
	
	if is_charging:
		if is_ready:
			# Bow is ready to fire - green crosshair
			style.bg_color = CROSSHAIR_COLOR_BOW_READY
			style.border_color = CROSSHAIR_BORDER_BOW_READY
		else:
			# Bow is charging but not ready - red crosshair
			style.bg_color = CROSSHAIR_COLOR_BOW_LOADING
			style.border_color = CROSSHAIR_BORDER_BOW_LOADING
	else:
		# Not charging - return to default white
		style.bg_color = CROSSHAIR_COLOR_DEFAULT
		style.border_color = CROSSHAIR_BORDER_DEFAULT

func reset_crosshair_to_default() -> void:
	"""Resets crosshair to default white color."""
	if not should_show_crosshair or not crosshair.visible:
		return
		
	var style: StyleBoxFlat = crosshair.get_theme_stylebox("panel") as StyleBoxFlat
	style.bg_color = CROSSHAIR_COLOR_DEFAULT
	style.border_color = CROSSHAIR_BORDER_DEFAULT
