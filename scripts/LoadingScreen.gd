# LoadingScreen.gd
class_name LoadingScreen
extends Control

# --- Constants ---
const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const RESOURCE_LOAD_TIME := 2.0  # Time for loading the scene resource
const CHUNK_PRELOAD_TIME := 3.0  # Time for chunk preloading
const TOTAL_LOAD_TIME := RESOURCE_LOAD_TIME + CHUNK_PRELOAD_TIME

# --- Nodes ---
@onready var progress_bar := $LoadingContainer/ProgressBarContainer/ProgressBar
@onready var loading_label := $LoadingContainer/LoadingLabel

# --- Engine Callbacks ---
func _ready() -> void:
	# Check if we're the host who just transitioned from main menu
	if NetworkManager.is_host and multiplayer.has_multiplayer_peer():
		print("LoadingScreen: Host mode - waiting for NetworkManager setup...")
		loading_label.text = "Setting up server..."
		progress_bar.value = 10.0
		
		# Wait for NetworkManager to finish setting up (from MainMenu's deferred call)
		await get_tree().create_timer(0.5).timeout
		progress_bar.value = 20.0
		
		# Now wait for the game to be ready to start
		loading_label.text = "Starting world..."
		await get_tree().create_timer(0.5).timeout
		
		# The NetworkManager should handle the rest
		return
	
	# Check if we're a client waiting for world state
	if multiplayer.has_multiplayer_peer() and not NetworkManager.is_host:
		print("LoadingScreen: Client mode - waiting for world state...")
		loading_label.text = "Connecting to server..."
		progress_bar.value = 10.0
		
		# Wait for connection to stabilize
		await get_tree().create_timer(0.5).timeout
		progress_bar.value = 30.0
		loading_label.text = "Receiving world data..."
		
		# The NetworkManager will trigger the scene transition when ready
		return
	
	# Normal loading process for single player only
	# Start loading the main scene in the background
	ResourceLoader.load_threaded_request(MAIN_SCENE_PATH)
	loading_label.text = "Loading world..."
	
	# Phase 1: Load scene resource (2 seconds)
	var timer := get_tree().create_timer(RESOURCE_LOAD_TIME)
	var progress_array := []
	
	while ResourceLoader.load_threaded_get_status(MAIN_SCENE_PATH, progress_array) != ResourceLoader.THREAD_LOAD_LOADED:
		# Update progress bar based on loading status (0-40% for resource loading)
		if not progress_array.is_empty():
			progress_bar.value = progress_array[0] * 40.0
		await get_tree().process_frame

	await timer.timeout
	
	# Phase 2: Simulate chunk preloading (3 seconds)
	loading_label.text = "Generating terrain..."
	progress_bar.value = 40.0
	
	# Simulate chunk loading progress
	var chunk_timer_start := Time.get_time_dict_from_system()
	while true:
		var elapsed := _get_elapsed_time(chunk_timer_start)
		var chunk_progress := elapsed / CHUNK_PRELOAD_TIME
		
		if chunk_progress >= 1.0:
			break
			
		# Update progress bar (40-90% for chunk loading)
		progress_bar.value = 40.0 + (chunk_progress * 50.0)
		
		# Update loading text based on progress
		if chunk_progress < 0.33:
			loading_label.text = "Generating terrain..."
		elif chunk_progress < 0.66:
			loading_label.text = "Placing trees and rocks..."
		else:
			loading_label.text = "Preparing world..."
			
		await get_tree().process_frame
	
	# Only transition for single player
	if not multiplayer.has_multiplayer_peer():
		_transition_to_main_scene()

func _get_elapsed_time(start_time: Dictionary) -> float:
	"""Calculate elapsed time since start_time."""
	var current_time := Time.get_time_dict_from_system()
	var start_seconds: int = start_time.hour * 3600 + start_time.minute * 60 + start_time.second
	var current_seconds: int = current_time.hour * 3600 + current_time.minute * 60 + current_time.second
	return float(current_seconds - start_seconds)

func _transition_to_main_scene() -> void:
	# Update loading label to show completion
	loading_label.text = "Ready!"
	progress_bar.value = 100
	
	# Wait a brief moment to show the completion state
	await get_tree().create_timer(0.2).timeout
	
	# Use Godot's proper scene transition to avoid gray screen
	var packed_scene = ResourceLoader.load_threaded_get(MAIN_SCENE_PATH) as PackedScene
	get_tree().change_scene_to_packed(packed_scene)


func update_client_progress(message: String, progress: float) -> void:
	"""Update loading screen for clients waiting for server."""
	loading_label.text = message
	progress_bar.value = progress 
