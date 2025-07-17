# scripts/HUD.gd

class_name HUD
extends Control

# --- Scripts ---
const PlayerScript: Script = preload("res://scripts/Player.gd")
const HotbarScript: Script = preload("res://scripts/Hotbar.gd")
const InventoryScript: Script = preload("res://scripts/Inventory.gd")

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
	print("HUD: Initializing...")
	add_to_group("hud")
	
	# Ensure HUD renders on top of other UI elements
	z_index = 100
	visible = true
	modulate = Color.WHITE
	
	_setup_crosshair()
	
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
	if not players.is_empty():
		for p in players:
			# Check if multiplayer peer exists before checking authority
			if multiplayer and multiplayer.multiplayer_peer and p.is_multiplayer_authority():
				player = p
				return


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
		return
		
	var interaction_controller = player.get_interaction_controller()
	if not interaction_controller:
		return

	# Always get the current closest interactable from the player's controller.
	# The controller's function is responsible for cleaning up invalid nodes.
	var closest: Node = interaction_controller.get_closest_interactable()

	# Case 1: The closest interactable is new or different.
	if closest and closest != current_interactable:
		current_interactable = closest
		_update_crosshair(true)
		
		# Try to get interaction prompt - first try method, then property
		var prompt: String = ""
		if current_interactable.has_method("get_interaction_prompt"):
			prompt = current_interactable.get_interaction_prompt()
		else:
			var property_value = current_interactable.get("interaction_prompt")
			prompt = property_value if property_value else "Interact"
		
		_show_interaction_prompt(prompt if prompt else "Interact")
	# Case 2: There is no longer a closest interactable, but we thought there was.
	elif not closest and current_interactable:
		# This handles both looking away and the object being destroyed.
		_clear_current_interactable()


func _clear_current_interactable() -> void:
	"""Clears the current interactable and resets the UI."""
	if current_interactable != null:
		current_interactable = null
		_update_crosshair(false)
		_hide_interaction_prompt()


# --- UI Updates ---

func _update_crosshair(can_interact: bool) -> void:
	"""Updates the crosshair color to indicate interactability."""
	# Only update crosshair if it should be visible
	if not should_show_crosshair or not crosshair.visible:
		return
		
	var style: StyleBoxFlat = crosshair.get_theme_stylebox("panel") as StyleBoxFlat
	if can_interact:
		style.bg_color = CROSSHAIR_COLOR_INTERACT
		style.border_color = CROSSHAIR_BORDER_INTERACT
	else:
		style.bg_color = CROSSHAIR_COLOR_DEFAULT
		style.border_color = CROSSHAIR_BORDER_DEFAULT


func _show_interaction_prompt(prompt_text: String) -> void:
	"""Shows the interaction prompt with the given text."""
	# Only show interaction prompt if crosshair should be visible
	if not should_show_crosshair:
		return
		
	interaction_prompt.text = prompt_text
	interaction_prompt.visible = true


func _hide_interaction_prompt() -> void:
	"""Hides the interaction prompt."""
	interaction_prompt.visible = false


# --- Public Methods ---

func update_crosshair_visibility(equipped_item: String) -> void:
	"""Updates crosshair visibility based on the currently equipped item."""
	# Only show crosshair when holding a bow
	should_show_crosshair = (equipped_item == "Bow")
	
	# Update the crosshair visibility
	if crosshair:
		crosshair.visible = should_show_crosshair
		
	# Also hide interaction prompt if crosshair is hidden
	if not should_show_crosshair and interaction_prompt:
		_hide_interaction_prompt()
		
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
