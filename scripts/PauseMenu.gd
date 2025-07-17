# scripts/PauseMenu.gd

class_name PauseMenu
extends Control

# --- Constants ---
const MAIN_MENU_SCENE_PATH: String = "res://scenes/MainMenu.tscn"

# --- Node References ---
@onready var resume_button: Button = $CenterContainer/MenuPanel/VBoxContainer/ResumeButton
@onready var settings_button: Button = $CenterContainer/MenuPanel/VBoxContainer/SettingsButton
@onready var quit_to_menu_button: Button = $CenterContainer/MenuPanel/VBoxContainer/QuitToMenuButton
@onready var quit_game_button: Button = $CenterContainer/MenuPanel/VBoxContainer/QuitGameButton
@onready var background: ColorRect = $Background

# Settings modal elements
@onready var settings_modal: PanelContainer = $SettingsModal
@onready var volume_slider: HSlider = $SettingsModal/MarginContainer/VBoxContainer/VolumeSlider
@onready var volume_label: Label = $SettingsModal/MarginContainer/VBoxContainer/VolumeLabel
@onready var music_slider: HSlider = $SettingsModal/MarginContainer/VBoxContainer/SubVolumeContainer/VBoxContainer/MusicSlider
@onready var music_label: Label = $SettingsModal/MarginContainer/VBoxContainer/SubVolumeContainer/VBoxContainer/MusicLabel
@onready var sfx_slider: HSlider = $SettingsModal/MarginContainer/VBoxContainer/SubVolumeContainer/VBoxContainer/SFXSlider
@onready var sfx_label: Label = $SettingsModal/MarginContainer/VBoxContainer/SubVolumeContainer/VBoxContainer/SFXLabel
@onready var settings_close_button: Button = $SettingsModal/MarginContainer/VBoxContainer/HBoxContainer/CloseButton

# Confirmation dialog
@onready var confirmation_dialog: ConfirmationDialog = $ConfirmationDialog

# --- Signals ---
signal resume_requested
signal settings_requested
signal quit_to_menu_requested
signal quit_game_requested

# --- Properties ---
var is_paused: bool = false


# --- Engine Callbacks ---

func _ready() -> void:
	"""Initialize the pause menu and connect signals."""
	print("PauseMenu: Initializing...")
	
	# Initially hide the pause menu and settings modal
	hide()
	settings_modal.hide()
	
	# Set up mouse filter to capture all input when visible
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Connect settings modal signals (close button already connected in scene file)
	volume_slider.value_changed.connect(_on_volume_changed)
	music_slider.value_changed.connect(_on_music_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	
	# Connect confirmation dialog
	confirmation_dialog.confirmed.connect(_on_confirmation_confirmed)
	
	# Load saved settings
	_load_settings()
	
	print("PauseMenu: Ready!")


func _input(event: InputEvent) -> void:
	"""Handle input events when the pause menu is active."""
	if not visible:
		return
		
	# Handle escape key to close pause menu or settings modal
	if event.is_action_pressed("ui_cancel"):
		if settings_modal.visible:
			_on_settings_close_pressed()
		else:
			_on_resume_pressed()
		get_viewport().set_input_as_handled()


# --- Public Methods ---

func show_pause_menu() -> void:
	"""Show the pause menu and pause the game."""
	if is_paused:
		return
		
	print("PauseMenu: Showing pause menu")
	is_paused = true
	show()
	
	# Pause the game - this stops all processing except UI
	get_tree().paused = true
	
	# Set process mode to always so this menu still works when paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Release mouse capture so player can interact with menu
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Focus the resume button for keyboard navigation
	resume_button.grab_focus()


func hide_pause_menu() -> void:
	"""Hide the pause menu and resume the game."""
	if not is_paused:
		return
		
	print("PauseMenu: Hiding pause menu")
	is_paused = false
	hide()
	
	# Also hide settings modal if it's open
	settings_modal.hide()
	
	# Resume the game
	get_tree().paused = false
	
	# Restore mouse capture for gameplay
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func toggle_pause_menu() -> void:
	"""Toggle the pause menu visibility."""
	if is_paused:
		hide_pause_menu()
	else:
		show_pause_menu()


# --- Signal Handlers ---

func _on_resume_pressed() -> void:
	"""Handle resume button press."""
	print("PauseMenu: Resume button pressed")
	hide_pause_menu()
	resume_requested.emit()


func _on_settings_pressed() -> void:
	"""Handle settings button press."""
	print("PauseMenu: Settings button pressed")
	settings_modal.show()
	settings_requested.emit()


func _on_quit_to_menu_pressed() -> void:
	"""Handle quit to main menu button press."""
	print("PauseMenu: Quit to menu button pressed")
	confirmation_dialog.dialog_text = "Are you sure you want to quit to the main menu?\nAny unsaved progress will be lost."
	confirmation_dialog.popup_centered()
	# Store what action to take when confirmed
	confirmation_dialog.set_meta("action", "quit_to_menu")


func _on_quit_game_pressed() -> void:
	"""Handle quit game button press."""
	print("PauseMenu: Quit game button pressed")
	confirmation_dialog.dialog_text = "Are you sure you want to quit the game?\nAny unsaved progress will be lost."
	confirmation_dialog.popup_centered()
	# Store what action to take when confirmed
	confirmation_dialog.set_meta("action", "quit_game")


# --- Settings Modal Handlers ---

func _on_settings_close_pressed() -> void:
	"""Handle the close button in the settings modal."""
	print("PauseMenu: Closing settings modal")
	_save_settings()
	settings_modal.hide()


func _on_volume_changed(value: float) -> void:
	"""Handle master volume slider changes. Updates the effective volumes for music and SFX."""
	GameConstants.SettingsManager.apply_master_volume_setting(value)
	# Update the label text with percentage
	_update_volume_label_text()
	# Update effective volumes by applying the master multiplier
	_update_effective_volumes()


func _on_music_volume_changed(value: float) -> void:
	"""Handle music volume slider changes. Updates effective music volume."""
	GameConstants.SettingsManager.apply_music_volume_setting(value)
	# Update the label text with percentage
	_update_volume_label_text()
	_update_effective_volumes()


func _on_sfx_volume_changed(value: float) -> void:
	"""Handle SFX volume slider changes. Updates effective SFX volume."""
	GameConstants.SettingsManager.apply_sfx_volume_setting(value)
	# Update the label text with percentage
	_update_volume_label_text()
	_update_effective_volumes()


func _update_effective_volumes() -> void:
	"""Updates the effective volumes using master * specific multipliers."""
	var master_volume = volume_slider.value
	var music_volume = music_slider.value
	var sfx_volume = sfx_slider.value
	
	# Calculate effective volumes (master * specific)
	var effective_music = (master_volume / 100.0) * (music_volume / 100.0) * 100.0
	var effective_sfx = (master_volume / 100.0) * (sfx_volume / 100.0) * 100.0
	
	# Apply the effective volumes to audio buses
	GameConstants.SettingsManager.apply_effective_music_volume(effective_music)
	GameConstants.SettingsManager.apply_effective_sfx_volume(effective_sfx)


func _update_volume_label_text() -> void:
	"""
	Updates the volume label text to show percentages in front of the text.
	"""
	volume_label.text = str(int(volume_slider.value)) + "% Master Volume"
	music_label.text = str(int(music_slider.value)) + "% Music Volume"
	sfx_label.text = str(int(sfx_slider.value)) + "% SFX Volume"





# --- Confirmation Dialog Handler ---

func _on_confirmation_confirmed() -> void:
	"""Handle confirmation dialog confirmed."""
	var action = confirmation_dialog.get_meta("action", "")
	
	match action:
		"quit_to_menu":
			_quit_to_main_menu()
		"quit_game":
			_quit_game()


# --- Private Methods ---

func _quit_to_main_menu() -> void:
	"""Quit to the main menu."""
	print("PauseMenu: Quitting to main menu...")
	
	# Resume the game first to avoid issues with scene changing
	get_tree().paused = false
	
	# Disconnect from multiplayer if connected
	if NetworkManager:
		NetworkManager.disconnect_from_game()
	
	# Change to main menu scene
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
	quit_to_menu_requested.emit()


func _quit_game() -> void:
	"""Quit the entire game."""
	print("PauseMenu: Quitting game...")
	
	# Disconnect from multiplayer if connected
	if NetworkManager:
		NetworkManager.disconnect_from_game()
	
	# Quit the application
	get_tree().quit()
	quit_game_requested.emit()


# --- Settings Management ---

func _load_settings() -> void:
	"""Load saved settings from the config file and apply them."""
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


func _save_settings() -> void:
	"""Save current settings to the config file."""
	GameConstants.SettingsManager.save_volume_settings(
		volume_slider.value,
		music_slider.value,
		sfx_slider.value,
		false  # No fullscreen setting anymore
	)
	
	print("PauseMenu: Settings saved")


# --- Utility Methods ---

func is_pause_menu_visible() -> bool:
	"""Check if the pause menu is currently visible."""
	return visible and is_paused 
