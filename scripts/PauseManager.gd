# scripts/PauseManager.gd
# Global pause manager with window management features

extends Node

# --- Constants ---
const PAUSE_MENU_SCENE_PATH: String = "res://ui/PauseMenu.tscn"

# --- Signals ---
signal game_paused
signal game_resumed
signal pause_menu_opened
signal pause_menu_closed

# --- Properties ---
var is_game_paused: bool = false
var pause_menu_instance: Control = null
var pause_menu_scene: PackedScene = preload(PAUSE_MENU_SCENE_PATH)

# --- Players management ---
var players: Array[Node] = []  # Keep track of players for input handling

# --- Day/Night Controls ---
var hud_reference: Control = null
var day_night_controls: Control = null


# --- Engine Callbacks ---

func _ready() -> void:
	"""Initialize the pause manager."""
	print("PauseManager: Initializing...")
	
	# Set process mode to always so this works when paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	print("PauseManager: Ready!")


func toggle_fullscreen() -> void:
	"""Toggle between fullscreen and windowed mode."""
	var current_mode: int = DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		print("PauseManager: Switched to windowed mode")
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		print("PauseManager: Switched to fullscreen mode")


func _input(event: InputEvent) -> void:
	"""Handle global input for pause functionality and window management."""
	# Handle F11 fullscreen toggle globally (works anywhere in the game)
	if event.is_action_pressed("toggle_fullscreen"):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	
	# Handle F1 key to toggle day/night controls
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		toggle_day_night_controls()
		get_viewport().set_input_as_handled()
		return
	
	# Only handle pause input if we're in the main game scene
	if not _is_in_game():
		return
		
	# Handle escape key to toggle pause menu
	if event.is_action_pressed("ui_cancel"):
		toggle_pause()
		get_viewport().set_input_as_handled()


# --- Public Methods ---

func toggle_pause() -> void:
	"""Toggle the game pause state."""
	if is_game_paused:
		resume_game()
	else:
		pause_game()


func pause_game() -> void:
	"""Pause the game and show the pause menu."""
	if is_game_paused:
		return
		
	print("PauseManager: Pausing game...")
	is_game_paused = true
	
	# Create and show pause menu if it doesn't exist
	if not pause_menu_instance:
		_create_pause_menu()
	
	if pause_menu_instance:
		pause_menu_instance.show_pause_menu()
		pause_menu_opened.emit()
	
	game_paused.emit()


func resume_game() -> void:
	"""Resume the game and hide the pause menu."""
	if not is_game_paused:
		return
		
	print("PauseManager: Resuming game...")
	is_game_paused = false
	
	if pause_menu_instance:
		pause_menu_instance.hide_pause_menu()
		pause_menu_closed.emit()
	
	game_resumed.emit()


func cleanup_pause_menu() -> void:
	"""Clean up the pause menu instance."""
	if pause_menu_instance:
		pause_menu_instance.queue_free()
		pause_menu_instance = null
		
	# Also cleanup the pause layer if it exists and is empty
	var viewport = get_viewport()
	if viewport:
		var pause_layer = viewport.get_node_or_null("PauseLayer")
		if pause_layer and pause_layer.get_child_count() == 0:
			pause_layer.queue_free()


func register_player(player: Node) -> void:
	"""Register a player for pause functionality."""
	if player not in players:
		players.append(player)
		print("PauseManager: Registered player: ", player.name)
		
		# Try to find HUD when registering player
		_find_hud_references()


func _is_in_game() -> bool:
	"""Check if we're currently in an active game state."""
	# Method 1: Check if we have registered players (indicates active game)
	if players.size() > 0:
		return true
		
	# Method 2: Check if current scene is the main game scene
	var current_scene = get_tree().current_scene
	if current_scene and current_scene.scene_file_path.ends_with("Main.tscn"):
		return true
		
	return false


func unregister_player(player: Node) -> void:
	"""Unregister a player from pause functionality."""
	if player in players:
		players.erase(player)
		print("PauseManager: Unregistered player: ", player.name)


func clear_all_players() -> void:
	"""Clear all registered players (used when returning to main menu)."""
	print("PauseManager: Clearing all registered players...")
	players.clear()
	
	# Clear HUD references
	hud_reference = null
	day_night_controls = null
	
	# Ensure game is unpaused and cleanup pause menu
	if is_game_paused:
		is_game_paused = false
		get_tree().paused = false
	cleanup_pause_menu()


func is_pause_available() -> bool:
	"""Check if pause functionality is available (i.e., we're in game)."""
	# Pause is available if we have at least one registered player
	return players.size() > 0


func toggle_day_night_controls() -> void:
	"""Toggle the visibility of day/night cycle controls."""
	if not _is_in_game():
		return
		
	# Try to find HUD if not already cached
	if not hud_reference:
		_find_hud_references()
	
	if day_night_controls:
		day_night_controls.visible = !day_night_controls.visible
		print("PauseManager: Day/Night controls %s" % ("shown" if day_night_controls.visible else "hidden"))
		print("PauseManager: Press F1 to toggle Day/Night controls")
	else:
		print("PauseManager: Day/Night controls not found - trying to locate...")
		_find_hud_references()


# --- Private Methods ---

func _find_hud_references() -> void:
	"""Find HUD and day/night controls in the scene."""
	# Try to find HUD in the viewport
	var viewport = get_viewport()
	if not viewport:
		return
		
	# Look for HUD canvas layer
	for child in viewport.get_children():
		if child is CanvasLayer and child.name == "HUDLayer":
			# Find HUD in the HUD layer
			for hud_child in child.get_children():
				if hud_child.name == "HUD":
					hud_reference = hud_child
					day_night_controls = hud_reference.get_node_or_null("DayNightControls")
					if day_night_controls:
						print("PauseManager: Found Day/Night controls in HUD")
					break
			break
	
	# If not found in HUDLayer, try direct search
	if not hud_reference:
		var main = get_tree().get_root().get_node_or_null("Main")
		if main:
			for child in main.get_children():
				if child.name == "HUD":
					hud_reference = child
					day_night_controls = hud_reference.get_node_or_null("DayNightControls")
					if day_night_controls:
						print("PauseManager: Found Day/Night controls in Main scene")
					break


func _create_pause_menu() -> void:
	"""Create and set up the pause menu instance."""
	if pause_menu_instance:
		return
		
	print("PauseManager: Creating pause menu...")
	
	# Get the viewport to add the pause menu with proper layering
	var viewport = get_viewport()
	if not viewport:
		print("PauseManager: Error - No viewport found!")
		return
	
	# Look for existing pause UI layer or create one with higher priority than HUD
	var pause_layer = viewport.get_node_or_null("PauseLayer")
	if not pause_layer:
		print("PauseManager: Creating PauseLayer for pause menu")
		pause_layer = CanvasLayer.new()
		pause_layer.name = "PauseLayer"
		pause_layer.layer = 20  # Higher than HUD layer (10) to render on top
		viewport.add_child(pause_layer)
	else:
		print("PauseManager: Found existing PauseLayer")
	
	# Create the pause menu instance
	pause_menu_instance = pause_menu_scene.instantiate()
	
	# Add it to the pause layer to ensure it renders above everything else
	pause_layer.add_child(pause_menu_instance)
	
	# Connect pause menu signals
	_connect_pause_menu_signals()
	
	print("PauseManager: Pause menu created and added to PauseLayer (layer 20)")


func _connect_pause_menu_signals() -> void:
	"""Connect pause menu signals to handle events."""
	if not pause_menu_instance:
		return
		
	# Connect the pause menu's signals
	if not pause_menu_instance.resume_requested.is_connected(_on_pause_menu_resume_requested):
		pause_menu_instance.resume_requested.connect(_on_pause_menu_resume_requested)
	
	if not pause_menu_instance.settings_requested.is_connected(_on_pause_menu_settings_requested):
		pause_menu_instance.settings_requested.connect(_on_pause_menu_settings_requested)
	
	if not pause_menu_instance.quit_to_menu_requested.is_connected(_on_pause_menu_quit_to_menu_requested):
		pause_menu_instance.quit_to_menu_requested.connect(_on_pause_menu_quit_to_menu_requested)
	
	if not pause_menu_instance.quit_game_requested.is_connected(_on_pause_menu_quit_game_requested):
		pause_menu_instance.quit_game_requested.connect(_on_pause_menu_quit_game_requested)


# --- Signal Handlers ---

func _on_pause_menu_resume_requested() -> void:
	"""Handle resume request from pause menu."""
	print("PauseManager: Resume requested from pause menu")
	resume_game()


func _on_pause_menu_settings_requested() -> void:
	"""Handle settings request from pause menu."""
	print("PauseManager: Settings requested from pause menu")
	# TODO: Implement settings handling
	pass


func _on_pause_menu_quit_to_menu_requested() -> void:
	"""Handle quit to menu request from pause menu."""
	print("PauseManager: Quit to menu requested from pause menu")
	# The pause menu handles the actual scene change


func _on_pause_menu_quit_game_requested() -> void:
	"""Handle quit game request from pause menu."""
	print("PauseManager: Quit game requested from pause menu")
	# The pause menu handles the actual game quit


# --- Utility Methods ---

func get_pause_menu() -> Control:
	"""Get the current pause menu instance."""
	return pause_menu_instance


func force_cleanup() -> void:
	"""Force cleanup of all pause-related resources."""
	print("PauseManager: Force cleanup requested")
	cleanup_pause_menu()
	players.clear()
	is_game_paused = false
	get_tree().paused = false
	
	# Force cleanup of pause layer
	var viewport = get_viewport()
	if viewport:
		var pause_layer = viewport.get_node_or_null("PauseLayer")
		if pause_layer:
			pause_layer.queue_free() 
