# MainMenu.gd
class_name MainMenu
extends Control

# --- Constants ---
const DEFAULT_IP: String = "127.0.0.1"
const LOBBY_SCENE_PATH: String = "res://scenes/Lobby.tscn"
const MAIN_SCENE_PATH: String = "res://scenes/Main.tscn"
const LOADING_SCENE_PATH: String = "res://scenes/LoadingScreen.tscn"

# World size multiplier options that can be cycled through
const WORLD_SIZE_OPTIONS: Array[float] = [1.0, 3.0, 5.0, 10.0]

# --- Node References ---
# Main menu buttons
@onready var play_button: Button = $VBoxContainer/PlayButton
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton
@onready var exit_button: Button = $VBoxContainer/ExitButton

# Modals
@onready var character_select_modal: PanelContainer = $CharacterSelectModal
@onready var join_modal: PanelContainer = $JoinModal
@onready var settings_modal: PanelContainer = $SettingsModal

# Character selection modal elements
@onready var bark_panel: PanelContainer = $CharacterSelectModal/VBoxContainer/CharacterContainer/BarkPanel
@onready var moss_panel: PanelContainer = $CharacterSelectModal/VBoxContainer/CharacterContainer/MossPanel
@onready var play_character_button: Button = $CharacterSelectModal/VBoxContainer/PlayButton
@onready var character_back_button: Button = $CharacterSelectModal/VBoxContainer/BackButton

# World size elements
@onready var world_size_button: Button = $CharacterSelectModal/VBoxContainer/WorldSizeContainer/WorldSizeButton
@onready var world_size_description: Label = $CharacterSelectModal/VBoxContainer/WorldSizeContainer/WorldSizeDescription

# Join modal elements
@onready var ip_input: LineEdit = $JoinModal/VBoxContainer/IPInput
@onready var cancel_button: Button = $JoinModal/VBoxContainer/HBoxContainer/CancelButton
@onready var connect_button: Button = $JoinModal/VBoxContainer/HBoxContainer/ConnectButton

# Settings modal elements
@onready var volume_slider: HSlider = $SettingsModal/MarginContainer/VBoxContainer/VolumeSlider
@onready var volume_label: Label = $SettingsModal/MarginContainer/VBoxContainer/VolumeLabel
@onready var music_slider: HSlider = $SettingsModal/MarginContainer/VBoxContainer/SubVolumeContainer/VBoxContainer/MusicSlider
@onready var music_label: Label = $SettingsModal/MarginContainer/VBoxContainer/SubVolumeContainer/VBoxContainer/MusicLabel
@onready var sfx_slider: HSlider = $SettingsModal/MarginContainer/VBoxContainer/SubVolumeContainer/VBoxContainer/SFXSlider
@onready var sfx_label: Label = $SettingsModal/MarginContainer/VBoxContainer/SubVolumeContainer/VBoxContainer/SFXLabel
@onready var close_button: Button = $SettingsModal/MarginContainer/VBoxContainer/HBoxContainer/CloseButton

# --- State Variables ---
var selected_character: String = ""  # "bark" or "moss"
var current_world_size_index: int = 2  # Default to 5x (index 2 in WORLD_SIZE_OPTIONS)


# --- Engine Callbacks ---

func _ready() -> void:
	"""Initializes the main menu, connects signals, and loads settings."""
	# Hide modals initially
	character_select_modal.hide()
	join_modal.hide()
	settings_modal.hide()
	
	# Set pivot points to center for character panels so they scale from center
	# Both panels have minimum size of 180x200, so center is at (90, 100)
	bark_panel.pivot_offset = Vector2(90, 100)
	moss_panel.pivot_offset = Vector2(90, 100)
	
	# Connect panel hover handlers (new functionality not in .tscn)
	bark_panel.mouse_entered.connect(_on_bark_panel_hover_entered)
	bark_panel.mouse_exited.connect(_on_bark_panel_hover_exited)
	moss_panel.mouse_entered.connect(_on_moss_panel_hover_entered)
	moss_panel.mouse_exited.connect(_on_moss_panel_hover_exited)
	
	# Connect settings signals (not defined in .tscn)
	volume_slider.value_changed.connect(_on_volume_changed)
	music_slider.value_changed.connect(_on_music_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	
	# Load saved settings
	_load_settings()
	
	# Allow ESC key to close modals
	set_process_input(true)


func _input(event: InputEvent) -> void:
	"""Handles input events for closing modals with ESC."""
	if event.is_action_pressed("ui_cancel"):
		if character_select_modal.visible:
			_on_character_back_pressed()
		elif join_modal.visible:
			_on_join_cancel_pressed()
		elif settings_modal.visible:
			_on_settings_close_pressed()


# --- Main Menu Button Handlers ---

func _on_play_pressed() -> void:
	"""
	Handles the play button press. Shows the character selection modal.
	"""
	print("Opening character selection...")
	character_select_modal.show()
	# Reset character selection
	selected_character = ""
	_update_character_selection_ui()


func _on_join_pressed() -> void:
	"""
	Handles the join button press. Shows the join game modal.
	"""
	join_modal.show()


func _on_settings_pressed() -> void:
	"""
	Handles the settings button press. Shows the settings modal.
	"""
	settings_modal.show()


func _on_exit_pressed() -> void:
	"""
	Handles the exit button press. Quits the game.
	"""
	get_tree().quit()


# --- Character Selection Handlers ---

func _on_bark_panel_clicked(event: InputEvent) -> void:
	"""
	Handles mouse clicks on the Bark character panel.
	"""
	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		selected_character = "bark"
		_update_character_selection_ui()


func _on_moss_panel_clicked(event: InputEvent) -> void:
	"""
	Handles mouse clicks on the Moss character panel.
	"""
	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		selected_character = "moss"
		_update_character_selection_ui()


func _on_play_character_pressed() -> void:
	"""
	Handles the play button in the character selection modal. Starts hosting a game
	with the selected character.
	"""
	if selected_character.is_empty():
		return
	
	print("Starting game with character: ", selected_character)
	
	# Apply the world size setting before starting the game
	var world_size_multiplier = WORLD_SIZE_OPTIONS[current_world_size_index]
	GameConstants.set_world_scale_multiplier(world_size_multiplier)
	print("MainMenu: Starting game with world size: ", world_size_multiplier, "x")
	
	# Set up networking
	NetworkManager.host_game()
	
	# Claim the chosen role
	var role: String = "human" if selected_character == "moss" else "dog"
	NetworkManager.claim_role(role)
	
	# Start the game
	_transition_to_loading_screen(role)


# --- World Size Handlers ---

func _on_world_size_pressed() -> void:
	"""Handle world size button press - cycles through size options."""
	print("MainMenu: World size button pressed")
	
	# Cycle to the next world size option
	current_world_size_index = (current_world_size_index + 1) % WORLD_SIZE_OPTIONS.size()
	
	# Update the button text and description
	_update_world_size_display()
	
	# Show info about the change
	print("MainMenu: World size changed to ", WORLD_SIZE_OPTIONS[current_world_size_index], "x")


func _update_world_size_display() -> void:
	"""Update the world size button text and description to show current selection."""
	var current_size: float = WORLD_SIZE_OPTIONS[current_world_size_index]
	
	# Format the text to show the multiplier
	if current_size == 1.0:
		world_size_button.text = "1x (Small)"
		world_size_description.text = "Compact world perfect for quick exploration and cozy survival."
	elif current_size == 3.0:
		world_size_button.text = "3x (Medium)"
		world_size_description.text = "Balanced world size with plenty of resources and room to roam."
	elif current_size == 5.0:
		world_size_button.text = "5x (Large)"
		world_size_description.text = "Expansive world with abundant wildlife and vast wilderness to explore."
	elif current_size == 10.0:
		world_size_button.text = "10x (Huge)"
		world_size_description.text = "Massive world for epic adventures and endless exploration."
	else:
		world_size_button.text = str(current_size) + "x"
		world_size_description.text = "Custom world size with scaled resources and terrain."


func _update_character_selection_ui() -> void:
	"""
	Updates the character selection UI based on the currently selected character.
	"""
	# Reset all panels to normal state first
	_animate_panel_hover(bark_panel, false)
	_animate_panel_hover(moss_panel, false)
	
	# Constants for selection styling
	const SELECTED_COLOR: Color = Color(0.85, 0.95, 0.85, 1)  # Light pastel leaf green background
	const NORMAL_COLOR: Color = Color(0.8, 0.75, 0.7, 1)  # Default panel color
	const BORDER_COLOR: Color = Color(0.204, 0.306, 0.255, 1)
	
	# Highlight the selected character panel
	if selected_character == "bark":
		bark_panel.scale = Vector2(1.05, 1.05)
		bark_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_set_panel_background_color(bark_panel, SELECTED_COLOR)
		_set_panel_text_colors(bark_panel, true)  # Dark text for selected
		
		moss_panel.scale = Vector2(1.0, 1.0)
		moss_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_set_panel_background_color(moss_panel, NORMAL_COLOR)
		_set_panel_text_colors(moss_panel, false)  # Normal text colors
	elif selected_character == "moss":
		moss_panel.scale = Vector2(1.05, 1.05)
		moss_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_set_panel_background_color(moss_panel, SELECTED_COLOR)
		_set_panel_text_colors(moss_panel, true)  # Dark text for selected
		
		bark_panel.scale = Vector2(1.0, 1.0)
		bark_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_set_panel_background_color(bark_panel, NORMAL_COLOR)
		_set_panel_text_colors(bark_panel, false)  # Normal text colors
	else:
		# No character selected
		bark_panel.scale = Vector2(1.0, 1.0)
		bark_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_set_panel_background_color(bark_panel, NORMAL_COLOR)
		_set_panel_text_colors(bark_panel, false)  # Normal text colors
		
		moss_panel.scale = Vector2(1.0, 1.0)
		moss_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_set_panel_background_color(moss_panel, NORMAL_COLOR)
		_set_panel_text_colors(moss_panel, false)  # Normal text colors
	
	# Enable/disable the play button based on whether a character is selected
	play_character_button.disabled = selected_character.is_empty()


func _set_panel_background_color(panel: PanelContainer, bg_color: Color) -> void:
	"""
	Sets the background color of a character selection panel.
	"""
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = bg_color
	style_box.border_color = Color(0.204, 0.306, 0.255, 1)
	style_box.set_border_width_all(3)
	style_box.set_corner_radius_all(12)
	style_box.shadow_color = Color(0.137, 0.2, 0.165, 0.6)
	style_box.shadow_size = 8
	style_box.shadow_offset = Vector2(2, 4)
	
	panel.add_theme_stylebox_override("panel", style_box)


func _set_panel_text_colors(panel: PanelContainer, is_selected: bool) -> void:
	"""
	Sets the text colors for all labels in a character panel based on selection state.
	"""
	const SELECTED_NAME_COLOR: Color = Color(0.1, 0.1, 0.1, 1)        # Dark gray/black for names
	const SELECTED_DESC_COLOR: Color = Color(0.2, 0.2, 0.2, 1)        # Slightly lighter for descriptions
	const NORMAL_NAME_COLOR: Color = Color(0.098, 0.145, 0.118, 1)    # Original green
	const NORMAL_DESC_COLOR: Color = Color(0.204, 0.306, 0.255, 1)    # Original darker green
	
	var vbox = panel.get_node("VBoxContainer")
	if not vbox:
		return
	
	# Update character name label
	var name_label = vbox.get_node("CharacterName")
	if name_label and name_label is Label:
		if is_selected:
			name_label.add_theme_color_override("font_color", SELECTED_NAME_COLOR)
		else:
			name_label.add_theme_color_override("font_color", NORMAL_NAME_COLOR)
	
	# Update character type label
	var type_label = vbox.get_node("CharacterType")
	if type_label and type_label is Label:
		if is_selected:
			type_label.add_theme_color_override("font_color", SELECTED_DESC_COLOR)
		else:
			type_label.add_theme_color_override("font_color", NORMAL_DESC_COLOR)
	
	# Update description label
	var desc_label = vbox.get_node("Description")
	if desc_label and desc_label is Label:
		if is_selected:
			desc_label.add_theme_color_override("font_color", SELECTED_DESC_COLOR)
		else:
			desc_label.add_theme_color_override("font_color", NORMAL_DESC_COLOR)


func _animate_panel_hover(panel: PanelContainer, is_hovering: bool) -> void:
	"""
	Animates a character panel on hover with subtle scale and glow effects.
	"""
	if not is_instance_valid(panel):
		return
	
	# Create a smooth tween for the hover animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	if is_hovering:
		# Scale up slightly and add glow effect on hover
		tween.parallel().tween_property(panel, "scale", Vector2(1.05, 1.05), 0.2)
		tween.parallel().tween_property(panel, "modulate", Color(1.1, 1.1, 1.0, 1.0), 0.2)
	else:
		# Scale back to normal and remove glow effect
		tween.parallel().tween_property(panel, "scale", Vector2(1.0, 1.0), 0.2)
		tween.parallel().tween_property(panel, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2)


func _on_character_back_pressed() -> void:
	"""
	Handles the back button in the character selection modal. Hides the modal.
	"""
	selected_character = ""  # Reset selection when going back
	character_select_modal.hide()


# --- Character Panel Hover Handlers ---

func _on_bark_panel_hover_entered() -> void:
	"""
	Handles mouse hover enter on the Bark character panel.
	"""
	if selected_character != "bark":  # Don't animate if already selected
		_animate_panel_hover(bark_panel, true)


func _on_bark_panel_hover_exited() -> void:
	"""
	Handles mouse hover exit on the Bark character panel.
	"""
	if selected_character != "bark":  # Don't animate if already selected
		_animate_panel_hover(bark_panel, false)


func _on_moss_panel_hover_entered() -> void:
	"""
	Handles mouse hover enter on the Moss character panel.
	"""
	if selected_character != "moss":  # Don't animate if already selected
		_animate_panel_hover(moss_panel, true)


func _on_moss_panel_hover_exited() -> void:
	"""
	Handles mouse hover exit on the Moss character panel.
	"""
	if selected_character != "moss":  # Don't animate if already selected
		_animate_panel_hover(moss_panel, false)


# --- Join Modal Handlers ---

func _on_join_cancel_pressed() -> void:
	"""
	Handles the cancel button in the join modal. Hides the modal.
	"""
	join_modal.hide()
	ip_input.text = ""


func _on_connect_pressed() -> void:
	"""
	Handles the connect button in the join modal. Attempts to join
	a game using the provided IP address.
	"""
	var ip: String = ip_input.text.strip_edges()
	if ip.is_empty():
		ip = DEFAULT_IP
	
	print("Attempting to join game at: ", ip)
	NetworkManager.join_game(ip)
	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)


# --- Settings Modal Handlers ---

func _on_settings_close_pressed() -> void:
	"""
	Handles the close button in the settings modal. Saves settings and hides the modal.
	"""
	_save_settings()
	settings_modal.hide()


func _on_volume_changed(value: float) -> void:
	"""
	Handles master volume slider changes. Updates the effective volumes for music and SFX.
	"""
	GameConstants.SettingsManager.apply_master_volume_setting(value)
	# Update the label text with percentage
	_update_volume_label_text()
	# Update effective volumes by applying the master multiplier
	_update_effective_volumes()


func _on_music_volume_changed(value: float) -> void:
	"""
	Handles music volume slider changes. Updates effective music volume.
	"""
	GameConstants.SettingsManager.apply_music_volume_setting(value)
	# Update the label text with percentage
	_update_volume_label_text()
	_update_effective_volumes()


func _on_sfx_volume_changed(value: float) -> void:
	"""
	Handles SFX volume slider changes. Updates effective SFX volume.
	"""
	GameConstants.SettingsManager.apply_sfx_volume_setting(value)
	# Update the label text with percentage
	_update_volume_label_text()
	_update_effective_volumes()


func _update_volume_label_text() -> void:
	"""
	Updates the volume label text to show percentages in front of the text.
	"""
	volume_label.text = str(int(volume_slider.value)) + "% Master Volume"
	music_label.text = str(int(music_slider.value)) + "% Music Volume"
	sfx_label.text = str(int(sfx_slider.value)) + "% SFX Volume"


func _update_effective_volumes() -> void:
	"""
	Updates the effective volumes using master * specific multipliers.
	"""
	var master_volume = volume_slider.value
	var music_volume = music_slider.value
	var sfx_volume = sfx_slider.value
	
	# Calculate effective volumes (master * specific)
	var effective_music = (master_volume / 100.0) * (music_volume / 100.0) * 100.0
	var effective_sfx = (master_volume / 100.0) * (sfx_volume / 100.0) * 100.0
	
	# Apply the effective volumes to audio buses
	GameConstants.SettingsManager.apply_effective_music_volume(effective_music)
	GameConstants.SettingsManager.apply_effective_sfx_volume(effective_sfx)





# --- Settings Management ---

func _load_settings() -> void:
	"""
	Loads saved settings from the config file and applies them.
	"""
	var settings = GameConstants.SettingsManager.load_settings()
	
	# Apply volume settings
	volume_slider.value = settings.get("master_volume", 75.0)
	music_slider.value = settings.get("music_volume", 75.0)
	sfx_slider.value = settings.get("sfx_volume", 75.0)
	
	# Update volume label text with percentages
	_update_volume_label_text()
	
	GameConstants.SettingsManager.apply_master_volume_setting(volume_slider.value)
	GameConstants.SettingsManager.apply_music_volume_setting(music_slider.value)
	GameConstants.SettingsManager.apply_sfx_volume_setting(sfx_slider.value)
	_update_effective_volumes()
	
	# Load world size setting specifically for character selection
	var world_size_multiplier = settings.get("world_size_multiplier", 5.0)
	
	# Find the index that matches the saved world size
	for i in range(WORLD_SIZE_OPTIONS.size()):
		if abs(WORLD_SIZE_OPTIONS[i] - world_size_multiplier) < 0.1:  # Allow for small floating point differences
			current_world_size_index = i
			break
	
	_update_world_size_display()


func _save_settings() -> void:
	"""
	Saves current settings to the config file.
	"""
	# Save all volume settings through shared system
	GameConstants.SettingsManager.save_volume_settings(
		volume_slider.value,
		music_slider.value,
		sfx_slider.value,
		false  # No fullscreen setting anymore
	)
	
	print("MainMenu: Settings saved")


func _transition_to_loading_screen(character_role: String) -> void:
	"""Transition to the loading screen with character role information."""
	print("MainMenu: Transitioning to loading screen for role: %s" % character_role)
	
	# Change to loading screen - the LoadingScreen will get character role from NetworkManager
	var error: Error = get_tree().change_scene_to_file(LOADING_SCENE_PATH)
	if error != OK:
		printerr("MainMenu: Failed to change scene to LoadingScreen.tscn (error: %d)" % error)
