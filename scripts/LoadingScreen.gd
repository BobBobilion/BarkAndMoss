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
var world_generator: WorldGenerator = null
var main_scene_instance: Node3D = null
var current_progress: float = 0.0

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
	"""Initialize the loading screen and start the world generation process."""
	print("LoadingScreen: Starting world generation process...")
	
	# Start with initial values
	progress_bar.value = 0.0
	loading_timer = 0.0
	current_progress = 0.0
	is_loading_complete = false
	world_generation_complete = false
	
	# Get character role from NetworkManager and set appropriate loading message
	_set_character_specific_loading_message()
	
	# Start world generation
	_start_world_generation()
	
	print("LoadingScreen: Ready and world generation started!")


func _process(delta: float) -> void:
	"""Update the loading progress display each frame."""
	if is_loading_complete:
		return
	
	# Update progress bar based on actual world generation progress
	progress_bar.value = current_progress * 100.0
	
	# Also increment timer for visual effects (dots animation)
	loading_timer += delta
	
	# Check if world generation is complete
	if world_generation_complete:
		_finish_loading()


# --- Private Methods ---

func _start_world_generation() -> void:
	"""Start the world generation process by loading and setting up the main scene."""
	print("LoadingScreen: Loading main scene and starting world generation...")
	
	# Load the main scene (contains WorldGenerator)
	var main_scene: PackedScene = load(MAIN_SCENE_PATH)
	if not main_scene:
		printerr("LoadingScreen: Failed to load main scene!")
		return
	
	# Instantiate the main scene but don't add it to the tree yet
	main_scene_instance = main_scene.instantiate()
	
	# Find the WorldGenerator in the main scene
	world_generator = main_scene_instance.get_node("WorldGenerator") as WorldGenerator
	if not world_generator:
		printerr("LoadingScreen: Could not find WorldGenerator in main scene!")
		return
	
	# Connect to world generation progress signals
	world_generator.world_generation_progress.connect(_on_world_generation_progress)
	world_generator.terrain_generation_complete.connect(_on_world_generation_complete)
	
	# Add main scene to tree and start generation
	get_tree().current_scene.add_child(main_scene_instance)
	
	# Start world generation
	world_generator.start_generation()
	
	print("LoadingScreen: World generation started!")


func _on_world_generation_progress(step_name: String, progress: float) -> void:
	"""Handle world generation progress updates."""
	print("LoadingScreen: Generation progress - %s: %.1f%%" % [step_name, progress * 100.0])
	current_progress = progress
	progress_label.text = step_name
	
	# Add dots animation
	var dots_count: int = int((loading_timer * 2.0)) % 4  # Cycle through 0-3 dots
	var dots: String = ""
	for i in range(dots_count):
		dots += "."
	progress_label.text = step_name + dots


func _on_world_generation_complete() -> void:
	"""Handle world generation completion."""
	print("LoadingScreen: World generation complete!")
	world_generation_complete = true
	current_progress = 1.0


func _update_loading_message(progress: float) -> void:
	"""Legacy function - now handled by progress signals."""
	pass


func _finish_loading() -> void:
	"""Called when the world generation is complete."""
	if is_loading_complete:
		return
		
	print("LoadingScreen: World generation complete! Transitioning to game...")
	is_loading_complete = true
	
	# Update final message
	progress_label.text = "Ready!"
	loading_label.text = "Welcome to Bark & Moss!"
	
	# Brief pause before transition for polish
	await get_tree().create_timer(0.5).timeout
	
	# Transition to the generated world
	_transition_to_main_scene()


func _transition_to_main_scene() -> void:
	"""Transition to the main game scene (which is already loaded and generated)."""
	print("LoadingScreen: Transitioning to generated world...")
	
	if not main_scene_instance:
		printerr("LoadingScreen: No main scene instance available!")
		return
	
	# Remove the main scene from its current parent
	if main_scene_instance.get_parent():
		main_scene_instance.get_parent().remove_child(main_scene_instance)
	
	# Get the current scene tree root
	var scene_tree: SceneTree = get_tree()
	var root: Node = scene_tree.root
	
	# Remove the current scene (loading screen) from root
	var current_scene: Node = scene_tree.current_scene
	if current_scene:
		root.remove_child(current_scene)
		current_scene.queue_free()
	
	# Add the main scene to root and set it as current
	root.add_child(main_scene_instance)
	scene_tree.current_scene = main_scene_instance
	
	print("LoadingScreen: Transition complete!")


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