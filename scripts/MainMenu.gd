# MainMenu.gd
class_name MainMenu
extends Control

# --- Constants ---
const DEFAULT_IP: String = "127.0.0.1"
const LOBBY_SCENE_PATH: String = "res://scenes/Lobby.tscn"
const MAIN_SCENE_PATH: String = "res://scenes/Main.tscn"

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

# Join modal elements
@onready var ip_input: LineEdit = $JoinModal/VBoxContainer/IPInput
@onready var cancel_button: Button = $JoinModal/VBoxContainer/HBoxContainer/CancelButton
@onready var connect_button: Button = $JoinModal/VBoxContainer/HBoxContainer/ConnectButton

# Settings modal elements
@onready var volume_slider: HSlider = $SettingsModal/VBoxContainer/VolumeSlider
@onready var fullscreen_checkbox: CheckBox = $SettingsModal/VBoxContainer/FullscreenCheckbox
@onready var close_button: Button = $SettingsModal/VBoxContainer/HBoxContainer/CloseButton

# --- State Variables ---
var selected_character: String = ""  # "bark" or "moss"


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
	fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)
	
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
	ip_input.grab_focus()


func _on_settings_pressed() -> void:
	"""
	Handles the settings button press. Shows the settings modal.
	"""
	settings_modal.show()


func _on_exit_pressed() -> void:
	"""
	Handles the exit button press. Quits the application.
	"""
	print("Exiting game...")
	get_tree().quit()


# --- Character Selection Modal Handlers ---

func _on_bark_panel_clicked(event: InputEvent) -> void:
	"""
	Handles clicking on the Bark character panel to select it.
	"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("Selected Bark (dog) character...")
		selected_character = "bark"
		_update_character_selection_ui()


func _on_moss_panel_clicked(event: InputEvent) -> void:
	"""
	Handles clicking on the Moss character panel to select it.
	"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("Selected Moss (human) character...")
		selected_character = "moss"
		_update_character_selection_ui()


func _on_play_character_pressed() -> void:
	"""
	Handles the Play button press. Starts the game with the selected character.
	"""
	if selected_character == "bark":
		print("Starting game as Bark (dog)...")
		NetworkManager.host_game()
		# Wait a frame for the host setup to complete, then assign dog role
		await get_tree().process_frame
		NetworkManager.claim_role("dog")
		get_tree().change_scene_to_file(MAIN_SCENE_PATH)
	elif selected_character == "moss":
		print("Starting game as Moss (human)...")
		NetworkManager.host_game()
		# Wait a frame for the host setup to complete, then assign human role
		await get_tree().process_frame
		NetworkManager.claim_role("human")
		get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _update_character_selection_ui() -> void:
	"""
	Updates the visual state of the character selection UI based on the selected character.
	"""
	# Create visual styles for selected and normal states
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.918, 0.878, 0.835, 0.9)  # Normal panel background
	normal_style.border_color = Color(0.545, 0.357, 0.169, 1)  # Border color
	normal_style.set_border_width_all(2)
	normal_style.set_corner_radius_all(8)
	
	var selected_style = StyleBoxFlat.new()
	selected_style.bg_color = Color(0.545, 0.357, 0.169, 0.9)  # Selected panel background (darker)
	selected_style.border_color = Color(0.918, 0.878, 0.835, 1)  # Highlighted border
	selected_style.set_border_width_all(4)
	selected_style.set_corner_radius_all(8)
	selected_style.shadow_color = Color(0.545, 0.357, 0.169, 0.6)
	selected_style.shadow_size = 6
	
	# Apply styles based on selection
	if selected_character == "bark":
		bark_panel.add_theme_stylebox_override("panel", selected_style)
		moss_panel.add_theme_stylebox_override("panel", normal_style)
		# Reset hover effects on selected panel
		bark_panel.scale = Vector2(1.0, 1.0)
		bark_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
	elif selected_character == "moss":
		bark_panel.add_theme_stylebox_override("panel", normal_style)
		moss_panel.add_theme_stylebox_override("panel", selected_style)
		# Reset hover effects on selected panel
		moss_panel.scale = Vector2(1.0, 1.0)
		moss_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
	else:
		# No selection - both panels normal
		bark_panel.add_theme_stylebox_override("panel", normal_style)
		moss_panel.add_theme_stylebox_override("panel", normal_style)
		# Reset hover effects on both panels
		bark_panel.scale = Vector2(1.0, 1.0)
		bark_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
		moss_panel.scale = Vector2(1.0, 1.0)
		moss_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
	
	# Enable/disable the play button based on whether a character is selected
	play_character_button.disabled = selected_character.is_empty()


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
	Handles volume slider changes. Updates the master volume.
	"""
	var volume_db: float = linear_to_db(value / 100.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), volume_db)


func _on_fullscreen_toggled(toggled_on: bool) -> void:
	"""
	Handles fullscreen checkbox toggle. Switches between fullscreen and windowed mode.
	"""
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


# --- Settings Management ---

func _load_settings() -> void:
	"""
	Loads saved settings from the config file and applies them.
	"""
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	
	if err != OK:
		# Use default settings if no config file exists
		volume_slider.value = 75.0
		fullscreen_checkbox.button_pressed = false
		return
	
	# Load volume setting
	var volume = config.get_value("audio", "master_volume", 75.0)
	volume_slider.value = volume
	_on_volume_changed(volume)
	
	# Load fullscreen setting
	var fullscreen = config.get_value("display", "fullscreen", false)
	fullscreen_checkbox.button_pressed = fullscreen
	_on_fullscreen_toggled(fullscreen)


func _save_settings() -> void:
	"""
	Saves current settings to the config file.
	"""
	var config = ConfigFile.new()
	
	# Save volume setting
	config.set_value("audio", "master_volume", volume_slider.value)
	
	# Save fullscreen setting
	config.set_value("display", "fullscreen", fullscreen_checkbox.button_pressed)
	
	# Save to file
	config.save("user://settings.cfg")
