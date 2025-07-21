# MainMenu.gd
class_name MainMenu
extends Control

# --- Constants ---
const DEFAULT_IP: String = "127.0.0.1"
const LOBBY_SCENE_PATH: String = "res://scenes/Lobby.tscn"
const MAIN_SCENE_PATH: String = "res://scenes/Main.tscn"
const LOADING_SCENE_PATH: String = "res://scenes/LoadingScreen.tscn"

# --- Preloads ---
const SettingsManager = preload("res://scripts/SettingsManager.gd")

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
@onready var code_input: LineEdit = $JoinModal/VBoxContainer/CodeInput
@onready var cancel_button: Button = $JoinModal/VBoxContainer/HBoxContainer/CancelButton
@onready var connect_button: Button = $JoinModal/VBoxContainer/HBoxContainer/ConnectButton
@onready var join_by_code_button: Button = $JoinModal/VBoxContainer/HBoxContainer/JoinByCodeButton

# Settings modal elements
@onready var volume_slider: HSlider = $SettingsModal/MarginContainer/VBoxContainer/VolumeSlider
@onready var volume_label: Label = $SettingsModal/MarginContainer/VBoxContainer/VolumeLabel
@onready var music_slider: HSlider = $SettingsModal/MarginContainer/VBoxContainer/SubVolumeContainer/VBoxContainer/MusicSlider
@onready var music_label: Label = $SettingsModal/MarginContainer/VBoxContainer/SubVolumeContainer/VBoxContainer/MusicLabel
@onready var sfx_slider: HSlider = $SettingsModal/MarginContainer/VBoxContainer/SubVolumeContainer/VBoxContainer/SFXSlider
@onready var sfx_label: Label = $SettingsModal/MarginContainer/VBoxContainer/SubVolumeContainer/VBoxContainer/SFXLabel
@onready var render_slider: HSlider = $SettingsModal/MarginContainer/VBoxContainer/RenderSlider
@onready var render_label: Label = $SettingsModal/MarginContainer/VBoxContainer/RenderLabel
@onready var close_button: Button = $SettingsModal/MarginContainer/VBoxContainer/HBoxContainer/CloseButton

# --- State Variables ---
var selected_character: String = ""  # "bark" or "moss"
var is_hosting: bool = false  # Flag to prevent connection logic from interfering
var is_connecting: bool = false  # Flag to track active connection attempts


# --- Engine Callbacks ---

func _ready() -> void:
	"""Initializes the main menu, connects signals, and loads settings."""
	# Ensure mouse is visible for main menu (safety check for scene transitions)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("MainMenu: Set mouse mode to visible")
	
	# Clean up any leftover UI from previous scenes
	if PauseManager:
		PauseManager.force_cleanup()
	
	# Clean up leftover UI layers
	_cleanup_leftover_ui()
	
	# Reset hosting flag
	is_hosting = false
	is_connecting = false
	
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
	render_slider.value_changed.connect(_on_render_distance_changed)
	
	# Connect join modal signals (not defined in .tscn)
	join_by_code_button.pressed.connect(_on_join_by_code_pressed)
	
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
	
	# Set flag to indicate we're hosting
	is_hosting = true
	is_connecting = false  # Cancel any pending connection attempts
	
	# Determine role before transitioning
	var role: String = "human" if selected_character == "moss" else "dog"
	
	# IMMEDIATELY transition to loading screen to avoid freeze
	print("MainMenu: Transitioning to loading screen...")
	get_tree().change_scene_to_file(LOADING_SCENE_PATH)
	
	# Use call_deferred to set up networking after scene transition starts
	call_deferred("_setup_host_after_transition", role)


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
	is_hosting = false  # Reset hosting flag
	is_connecting = false  # Reset connecting flag
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
	is_connecting = false  # Stop any pending connection
	join_modal.hide()
	ip_input.text = ""
	code_input.text = ""


func _on_connect_pressed() -> void:
	"""
	Handles the connect button in the join modal. Attempts to join
	a game using the provided IP address.
	"""
	var ip: String = ip_input.text.strip_edges()
	if ip.is_empty():
		ip = DEFAULT_IP
	
	print("Attempting to join game at: ", ip)
	
	# First transition to loading screen
	get_tree().change_scene_to_file(LOADING_SCENE_PATH)
	
	# Then initiate connection after scene change
	call_deferred("_connect_to_ip_after_transition", ip)

func _on_join_by_code_pressed() -> void:
	"""
	Handles the join by code button in the join modal. Attempts to join
	a game using the provided lobby code.
	"""
	var code: String = code_input.text.strip_edges().to_upper()
	if code.is_empty():
		print("No lobby code provided")
		return
	
	if code.length() != 6:
		print("Invalid lobby code length: ", code.length())
		return
	
	print("MainMenu: Attempting to join game with code: ", code)
	
	# Set connecting flag
	is_connecting = true
	
	# Connect to NetworkManager's connection failed signal
	if not NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.connect(_on_connection_failed)
	
	# First transition to loading screen
	get_tree().change_scene_to_file(LOADING_SCENE_PATH)
	
	# Then initiate connection after scene change
	call_deferred("_join_by_code_after_transition", code)

func _wait_for_discovery_connection() -> void:
	"""Wait for discovery to find host and establish connection."""
	# Connect to multiplayer peer_connected signal to know when we actually connect
	if not multiplayer.peer_connected.is_connected(_on_discovery_peer_connected):
		multiplayer.peer_connected.connect(_on_discovery_peer_connected)
	
	# Also set a timeout for discovery
	var timeout_timer = Timer.new()
	timeout_timer.wait_time = 20.0  # Give discovery 20 seconds
	timeout_timer.one_shot = true
	timeout_timer.timeout.connect(func(): 
		if is_connecting:
			print("MainMenu: Discovery timeout")
			_on_connection_failed("Discovery timeout - could not find host")
			if multiplayer.peer_connected.is_connected(_on_discovery_peer_connected):
				multiplayer.peer_connected.disconnect(_on_discovery_peer_connected)
		timeout_timer.queue_free()
	)
	add_child(timeout_timer)
	timeout_timer.start()

func _on_discovery_peer_connected(id: int) -> void:
	"""Called when we actually connect to a peer after discovery."""
	print("MainMenu: Connected to peer ID: ", id)
	# Disconnect the signal since we only need it once
	if multiplayer.peer_connected.is_connected(_on_discovery_peer_connected):
		multiplayer.peer_connected.disconnect(_on_discovery_peer_connected)
	
	# Only proceed if we're still in connecting state and this is the server
	if is_connecting and id == 1:  # Server ID is always 1
		print("MainMenu: Successfully connected to server, transitioning to lobby")
		is_connecting = false
		get_tree().change_scene_to_file(LOBBY_SCENE_PATH)

func _wait_for_actual_connection() -> void:
	"""Wait for actual connection when using direct IP."""
	var wait_time = 0.0
	var max_wait_time = 10.0  # Timeout for direct connection
	
	while wait_time < max_wait_time:
		await get_tree().create_timer(0.1).timeout
		wait_time += 0.1
		
		# Stop if we're now hosting or scene is changing
		if is_hosting or not is_connecting:
			print("MainMenu: Canceling connection attempt (hosting=%s, connecting=%s)" % [is_hosting, is_connecting])
			return
		
		# Check for actual connection to server
		if multiplayer.has_multiplayer_peer():
			var peer = multiplayer.get_multiplayer_peer()
			var status = peer.get_connection_status()
			
			# For clients, we need to verify we're connected to the server (ID 1)
			if status == MultiplayerPeer.CONNECTION_CONNECTED:
				# Additional check - see if we have any connected peers
				var connected_peers = peer.get_peers()
				if connected_peers.size() > 0:
					print("MainMenu: Connected to %d peers: %s" % [connected_peers.size(), connected_peers])
					print("MainMenu: Successfully connected, transitioning to lobby")
					is_connecting = false
					get_tree().change_scene_to_file(LOBBY_SCENE_PATH)
					return
				else:
					# Status says connected but no peers - wait more
					if int(wait_time * 10) % 10 == 0:  # Log every second
						print("MainMenu: Status CONNECTED but no peers yet (", wait_time, "s)")
			elif int(wait_time * 10) % 10 == 0:  # Log every second
				print("MainMenu: Connection status: ", status, " (", wait_time, "s)")
		else:
			if int(wait_time * 10) % 10 == 0:  # Log every second
				print("MainMenu: No multiplayer peer yet (", wait_time, "s)")
	
	print("MainMenu: Connection timeout after ", wait_time, " seconds")
	_on_connection_failed("Connection timeout")

func _on_connection_failed(reason: String) -> void:
	"""Handle connection failure when joining by code."""
	print("Connection failed: ", reason)
	# Could show an error dialog here

func _is_ip_address(text: String) -> bool:
	"""Check if text looks like an IP address (for testing purposes)."""
	var ip_regex = RegEx.new()
	ip_regex.compile("^(\\d{1,3}\\.){3}\\d{1,3}$")
	return ip_regex.search(text) != null


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
	SettingsManager.apply_master_volume_setting(value)
	# Update the label text with percentage
	_update_volume_label_text()
	# Update effective volumes by applying the master multiplier
	_update_effective_volumes()


func _on_music_volume_changed(value: float) -> void:
	"""
	Handles music volume slider changes. Updates effective music volume.
	"""
	SettingsManager.apply_music_volume_setting(value)
	# Update the label text with percentage
	_update_volume_label_text()
	_update_effective_volumes()


func _on_sfx_volume_changed(value: float) -> void:
	"""
	Handles SFX volume slider changes. Updates effective SFX volume.
	"""
	SettingsManager.apply_sfx_volume_setting(value)
	# Update the label text with percentage
	_update_volume_label_text()
	_update_effective_volumes()


func _on_render_distance_changed(value: float) -> void:
	"""
	Handles render distance slider changes. Updates chunk loading distance.
	"""
	var distance_int = int(value)
	SettingsManager.apply_render_distance_setting(distance_int)
	# Update the label text
	_update_volume_label_text()


func _update_volume_label_text() -> void:
	"""
	Updates the volume label text to show percentages and render distance value.
	"""
	volume_label.text = str(int(volume_slider.value)) + "% Master Volume"
	music_label.text = str(int(music_slider.value)) + "% Music Volume"
	sfx_label.text = str(int(sfx_slider.value)) + "% SFX Volume"
	render_label.text = "Render Distance: " + str(int(render_slider.value)) + " chunks"


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
	SettingsManager.apply_effective_music_volume(effective_music)
	SettingsManager.apply_effective_sfx_volume(effective_sfx)





# --- Settings Management ---

func _load_settings() -> void:
	"""
	Loads saved settings from the config file and applies them.
	"""
	var settings = SettingsManager.load_settings()
	
	# Apply volume settings
	volume_slider.value = settings.get("master_volume", 75.0)
	music_slider.value = settings.get("music_volume", 75.0)
	sfx_slider.value = settings.get("sfx_volume", 75.0)
	
	# Apply render distance setting
	render_slider.value = float(settings.get("render_distance", GameConstants.RENDER_DISTANCE.DEFAULT))
	
	# Update label texts
	_update_volume_label_text()
	
	SettingsManager.apply_master_volume_setting(volume_slider.value)
	SettingsManager.apply_music_volume_setting(music_slider.value)
	SettingsManager.apply_sfx_volume_setting(sfx_slider.value)
	SettingsManager.apply_render_distance_setting(int(render_slider.value))
	_update_effective_volumes()


func _save_settings() -> void:
	"""
	Saves current settings to the config file.
	"""
	# Save all settings including render distance
	SettingsManager.save_all_settings(
		volume_slider.value,
		music_slider.value,
		sfx_slider.value,
		false,  # No fullscreen setting anymore
		int(render_slider.value)  # Render distance
	)
	
	print("MainMenu: Settings saved")


func _ensure_clean_game_state() -> void:
	"""Ensure completely clean state before starting a new game."""
	print("MainMenu: Ensuring clean game state before starting new game...")
	
	# Force cleanup PauseManager
	if PauseManager:
		PauseManager.force_cleanup()
	
	# Only disconnect from network if we're connected to someone else's game
	# Don't disconnect if we're hosting or about to host a new game
	if NetworkManager and multiplayer.has_multiplayer_peer() and not NetworkManager.is_host:
		print("MainMenu: Disconnecting from existing game before hosting new one")
		NetworkManager.disconnect_from_game()
	elif NetworkManager and NetworkManager.is_host:
		print("MainMenu: Already hosting - keeping existing multiplayer peer")
	else:
		print("MainMenu: No existing multiplayer connection to clean up")
	
	# Clean up any leftover UI layers
	_cleanup_leftover_ui()
	
	# Remove any leftover player instances from the scene tree
	var all_players = get_tree().get_nodes_in_group("human_player")
	all_players.append_array(get_tree().get_nodes_in_group("dog_player"))
	for player in all_players:
		if is_instance_valid(player):
			print("MainMenu: Removing leftover player: %s" % player.name)
			player.queue_free()
	
	# Wait a frame to ensure cleanup completes
	await get_tree().process_frame
	
	print("MainMenu: Game state cleaned for fresh start")


func _cleanup_leftover_ui() -> void:
	"""Clean up any leftover UI layers from previous game sessions."""
	print("MainMenu: Cleaning up leftover UI layers...")
	
	var viewport = get_viewport()
	if not viewport:
		return
	
	# Remove UILayer (contains HUD/hotbar)
	var ui_layer = viewport.get_node_or_null("UILayer")
	if ui_layer:
		print("MainMenu: Removing leftover UILayer with %d children" % ui_layer.get_child_count())
		ui_layer.queue_free()
	
	# Remove HUDLayer if it exists
	var hud_layer = viewport.get_node_or_null("HUDLayer")
	if hud_layer:
		print("MainMenu: Removing leftover HUDLayer with %d children" % hud_layer.get_child_count())
		hud_layer.queue_free()
	
	# Remove PauseLayer if it exists (should already be cleaned but just in case)
	var pause_layer = viewport.get_node_or_null("PauseLayer")
	if pause_layer:
		print("MainMenu: Removing leftover PauseLayer with %d children" % pause_layer.get_child_count())
		pause_layer.queue_free()
	
	print("MainMenu: UI cleanup complete")


func _transition_to_loading_screen(character_role: String) -> void:
	"""Transition to the loading screen with character role information."""
	print("MainMenu: Transitioning to loading screen for role: %s" % character_role)
	
	# Clear all flags to prevent lingering async code from interfering
	is_connecting = false
	is_hosting = false
	
	# Change to loading screen - the LoadingScreen will get character role from NetworkManager
	var error: Error = get_tree().change_scene_to_file(LOADING_SCENE_PATH)
	if error != OK:
		printerr("MainMenu: Failed to change scene to LoadingScreen.tscn (error: %d)" % error)

func _show_lobby_code_in_modal(code: String) -> void:
	"""Display the lobby code in the character selection modal."""
	# Check if lobby code label already exists
	var lobby_code_label = character_select_modal.get_node_or_null("VBoxContainer/LobbyCodeLabel")
	
	if not lobby_code_label:
		# Create new label
		lobby_code_label = Label.new()
		lobby_code_label.name = "LobbyCodeLabel"
		lobby_code_label.add_theme_font_size_override("font_size", 24)
		lobby_code_label.add_theme_color_override("font_color", Color(0.918, 0.878, 0.835, 1))
		lobby_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		
		# Insert it at the top of the VBoxContainer
		var vbox = character_select_modal.get_node("VBoxContainer")
		vbox.add_child(lobby_code_label)
		vbox.move_child(lobby_code_label, 0)  # Move to top
		
		# Add some spacing
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(0, 10)
		vbox.add_child(spacer)
		vbox.move_child(spacer, 1)
		
		# Add test code info
		var test_label = Label.new()
		test_label.name = "TestCodeLabel"
		test_label.add_theme_font_size_override("font_size", 14)
		test_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
		test_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		test_label.text = "(Other players can use 'TEST' to connect on same machine)"
		vbox.add_child(test_label)
		vbox.move_child(test_label, 2)
		
		# Add more spacing
		var spacer2 = Control.new()
		spacer2.custom_minimum_size = Vector2(0, 10)
		vbox.add_child(spacer2)
		vbox.move_child(spacer2, 3)
	
	# Update the text
	lobby_code_label.text = "Lobby Code: " + code
	lobby_code_label.visible = true


func _setup_host_after_transition(role: String) -> void:
	"""Set up host networking after transitioning to loading screen."""
	print("MainMenu: Setting up host after transition...")
	
	# Clean up any leftover game state before starting new game
	_ensure_clean_game_state()
	
	# Wait for loading screen to be ready
	await get_tree().create_timer(0.1).timeout
	
	# Set up networking
	NetworkManager.host_game()
	print("MainMenu: host_game() called, players should contain host")
	
	# Wait a frame to ensure host is registered
	await get_tree().process_frame
	
	# Claim the chosen role
	NetworkManager.claim_role(role)
	print("MainMenu: claim_role() called")
	
	# Request to start the game
	NetworkManager.request_start_game()


func _connect_to_ip_after_transition(ip: String) -> void:
	"""Connect to a server after transitioning to loading screen."""
	print("MainMenu: Connecting to IP after transition: ", ip)
	
	# Wait for loading screen to be ready
	await get_tree().create_timer(0.1).timeout
	
	# Now connect
	NetworkManager.join_game(ip)
	
	# After a moment, transition to lobby
	await get_tree().create_timer(1.0).timeout
	
	# Check if connection was successful
	if multiplayer.has_multiplayer_peer():
		var peer = multiplayer.get_multiplayer_peer()
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			get_tree().change_scene_to_file(LOBBY_SCENE_PATH)


func _join_by_code_after_transition(code: String) -> void:
	"""Join a game by code after transitioning to loading screen."""
	print("MainMenu: Joining by code after transition: ", code)
	
	# Wait for loading screen to be ready
	await get_tree().create_timer(0.1).timeout
	
	# For debugging - check if code looks like an IP address (for testing)
	if _is_ip_address(code):
		print("MainMenu: Code looks like IP address, trying direct connection")
		NetworkManager.join_game(code)
		_wait_for_actual_connection()
	else:
		print("MainMenu: Using discovery system for lobby code")
		NetworkManager.join_game_by_code(code)
		# Don't wait for connection here - let discovery complete first
		# The discovery process will call join_game() when it finds the host
		# We'll detect the connection via peer_connected signal
		_wait_for_discovery_connection()
