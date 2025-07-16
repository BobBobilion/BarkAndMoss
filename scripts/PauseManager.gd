# scripts/PauseManager.gd

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


# --- Engine Callbacks ---

func _ready() -> void:
	"""Initialize the pause manager."""
	print("PauseManager: Initializing...")
	
	# Set process mode to always so this works when paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	print("PauseManager: Ready!")


func _input(event: InputEvent) -> void:
	"""Handle global input for pause functionality."""
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


func register_player(player: Node) -> void:
	"""Register a player for pause functionality."""
	if player not in players:
		players.append(player)
		print("PauseManager: Registered player: ", player.name)


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
	
	# Ensure game is unpaused and cleanup pause menu
	if is_game_paused:
		is_game_paused = false
		get_tree().paused = false
	cleanup_pause_menu()


func is_pause_available() -> bool:
	"""Check if pause functionality is available (i.e., we're in game)."""
	# Pause is available if we have at least one registered player
	return players.size() > 0


# --- Private Methods ---

func _create_pause_menu() -> void:
	"""Create and set up the pause menu instance."""
	if pause_menu_instance:
		return
		
	print("PauseManager: Creating pause menu...")
	
	# Get the current scene to add the pause menu to
	var current_scene: Node = get_tree().current_scene
	if not current_scene:
		print("PauseManager: Error - No current scene found!")
		return
	
	# Create the pause menu instance
	pause_menu_instance = pause_menu_scene.instantiate()
	
	# Add it to the current scene
	current_scene.add_child(pause_menu_instance)
	
	# Connect pause menu signals
	_connect_pause_menu_signals()
	
	print("PauseManager: Pause menu created and added to scene")


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
