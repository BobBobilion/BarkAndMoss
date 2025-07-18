# LoadingScreen.gd
class_name LoadingScreen
extends Control

# --- Constants ---
const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const MIN_LOAD_TIME := 2.0 # Minimum time to show the loading screen

# --- Nodes ---
@onready var progress_bar := $LoadingContainer/ProgressBarContainer/ProgressBar
@onready var loading_label := $LoadingContainer/LoadingLabel

# --- Properties ---
var main_scene: Node

# --- Engine Callbacks ---
func _ready() -> void:
	# Start loading the main scene in the background
	ResourceLoader.load_threaded_request(MAIN_SCENE_PATH)
	
	var timer := get_tree().create_timer(MIN_LOAD_TIME)
	var progress_array := []
	
	while ResourceLoader.load_threaded_get_status(MAIN_SCENE_PATH, progress_array) != ResourceLoader.THREAD_LOAD_LOADED:
		# Update progress bar based on loading status
		if not progress_array.is_empty():
			progress_bar.value = progress_array[0] * 100
		await get_tree().process_frame

	main_scene = ResourceLoader.load_threaded_get(MAIN_SCENE_PATH).instantiate()
	
	await timer.timeout
	_transition_to_main_scene()

func _transition_to_main_scene() -> void:
	get_tree().root.add_child(main_scene)
	queue_free() 
