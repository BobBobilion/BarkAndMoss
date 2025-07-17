# LoadingScreen.gd
class_name LoadingScreen
extends Control

# --- Constants ---
const MAIN_SCENE_PATH: String = "res://scenes/Main.tscn"
const LOADING_DURATION: float = 12.0  # 12 seconds total loading time

# --- Node References ---
@onready var progress_bar: ProgressBar = $LoadingContainer/ProgressBarContainer/ProgressBar
@onready var loading_label: Label = $LoadingContainer/LoadingLabel
@onready var progress_label: Label = $LoadingContainer/ProgressLabel

# --- Properties ---
var loading_timer: float = 0.0
var is_loading_complete: bool = false
var world_generation_complete: bool = false

# --- Loading messages for different progress stages ---
var loading_messages: Array[String] = [
	"Generating terrain...",
	"Placing trees and rocks...",
	"Spawning wildlife...",
	"Setting up environment...", 
	"Preparing world...",
	"Almost ready..."
]


# --- Engine Callbacks ---

func _ready() -> void:
	"""Initialize the loading screen and start the loading process."""
	print("LoadingScreen: Starting loading process...")
	
	# Start with initial values
	progress_bar.value = 0.0
	loading_timer = 0.0
	is_loading_complete = false
	world_generation_complete = false
	
	# Get character role from NetworkManager and set appropriate loading message
	_set_character_specific_loading_message()
	
	# Update initial message
	_update_loading_message(0.0)
	
	print("LoadingScreen: Ready!")


func _process(delta: float) -> void:
	"""Update the loading progress animation each frame."""
	if is_loading_complete:
		return
	
	# Increment loading timer
	loading_timer += delta
	
	# Calculate progress (0.0 to 1.0)
	var progress: float = clamp(loading_timer / LOADING_DURATION, 0.0, 1.0)
	
	# Update progress bar (0 to 100)
	progress_bar.value = progress * 100.0
	
	# Update loading message based on progress
	_update_loading_message(progress)
	
	# Check if loading is complete
	if progress >= 1.0:
		_finish_loading()


# --- Private Methods ---

func _update_loading_message(progress: float) -> void:
	"""Update the loading message based on current progress."""
	# Calculate which message to show based on progress
	var message_index: int = int(progress * loading_messages.size())
	message_index = clamp(message_index, 0, loading_messages.size() - 1)
	
	# Update the progress label with current message
	progress_label.text = loading_messages[message_index]
	
	# Add some visual flair with dots animation
	var dots_count: int = int((loading_timer * 2.0)) % 4  # Cycle through 0-3 dots
	var dots: String = ""
	for i in range(dots_count):
		dots += "."
	
	progress_label.text = loading_messages[message_index] + dots


func _finish_loading() -> void:
	"""Called when the loading progress is complete."""
	if is_loading_complete:
		return
		
	print("LoadingScreen: Loading complete! Transitioning to main scene...")
	is_loading_complete = true
	
	# Update final message
	progress_label.text = "Ready!"
	loading_label.text = "Welcome to Bark & Moss!"
	
	# Brief pause before transition for polish
	await get_tree().create_timer(0.5).timeout
	
	# Transition to main scene
	_transition_to_main_scene()


func _transition_to_main_scene() -> void:
	"""Transition to the main game scene."""
	print("LoadingScreen: Transitioning to main scene...")
	
	# Change to the main scene
	var error: Error = get_tree().change_scene_to_file(MAIN_SCENE_PATH)
	if error != OK:
		printerr("LoadingScreen: Failed to change scene to Main.tscn (error: %d)" % error)


# --- Public Methods ---

func _set_character_specific_loading_message() -> void:
	"""Set character-specific loading message based on NetworkManager role data."""
	var character_role: String = ""
	
	# Get the current player's role from NetworkManager
	if NetworkManager and NetworkManager.players.size() > 0:
		var server_id: int = 1  # Server/host is always ID 1
		if NetworkManager.players.has(server_id):
			character_role = NetworkManager.players[server_id].get("role", "")
	
	print("LoadingScreen: Loading game for character role: %s" % character_role)
	
	# Set character-specific loading message
	match character_role:
		"bark":
			loading_label.text = "Preparing Bark's Adventure..."
		"moss":
			loading_label.text = "Preparing Moss's Adventure..."
		_:
			loading_label.text = "Loading World..."


func set_loading_data(character_role: String) -> void:
	"""Legacy method for setting loading data (now handled automatically)."""
	print("LoadingScreen: set_loading_data called with role: %s (handled automatically now)" % character_role) 