class_name ChunkDebugUI
extends Control

# --- Properties ---
@onready var info_label: Label = Label.new()
var chunk_manager: ChunkManager = null
var update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.5
var show_chunk_borders: bool = true  # Toggle for chunk borders

# --- Engine Callbacks ---
func _ready() -> void:
	"""Initialize the debug UI."""
	# Set up UI
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(400, 200)
	position = Vector2(10, 10)
	
	# Create background
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# Set up label
	info_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	info_label.add_theme_color_override("font_color", Color.WHITE)
	info_label.add_theme_font_size_override("font_size", 14)
	info_label.position = Vector2(10, 10)
	add_child(info_label)
	
	# Find chunk manager
	_find_chunk_manager()
	
	# Hide by default, toggle with F3
	visible = false

func _input(event: InputEvent) -> void:
	"""Handle debug toggle input."""
	if event.is_action_pressed("ui_page_down"):  # F3 key
		visible = !visible
	
	# Toggle chunk borders with F4
	if event.is_action_pressed("ui_home") and visible:  # F4 key
		show_chunk_borders = !show_chunk_borders
		_update_chunk_border_visibility()

func _process(delta: float) -> void:
	"""Update debug display."""
	if not visible:
		return
		
	update_timer += delta
	if update_timer >= UPDATE_INTERVAL:
		update_timer = 0.0
		_update_display()

# --- Private Methods ---
func _find_chunk_manager() -> void:
	"""Find the chunk manager in the scene."""
	var game_managers := get_tree().get_nodes_in_group("game_manager")
	if game_managers.size() > 0:
		var game_manager = game_managers[0]
		if game_manager.has_method("get_chunk_manager"):
			chunk_manager = game_manager.get_chunk_manager()

func _update_display() -> void:
	"""Update the debug information display."""
	if not chunk_manager:
		_find_chunk_manager()
		if not chunk_manager:
			info_label.text = "Chunk System: Not Found"
			return
	
	var text := "=== Chunk System Debug ===\n"
	
	# Basic stats
	text += "Active Chunks: %d\n" % chunk_manager.active_chunks.size()
	text += "Generation Queue: %d\n" % chunk_manager.chunks_to_generate.size()
	text += "Generated Data: %d\n" % chunk_manager.generated_chunk_data.size()
	text += "Chunk Borders: %s (F4 to toggle)\n\n" % ("ON" if show_chunk_borders else "OFF")
	
	# Player positions
	if chunk_manager.player_tracker:
		text += "Players Tracked: %d\n" % chunk_manager.player_tracker.player_positions.size()
		
		# Get local player position
		var local_player := _get_local_player()
		if local_player:
			var player_pos := local_player.global_position
			var chunk_pos := Vector2i(
				floor(player_pos.x / Chunk.CHUNK_SIZE.x),
				floor(player_pos.z / Chunk.CHUNK_SIZE.y)
			)
			text += "Player Chunk: [%d, %d]\n" % [chunk_pos.x, chunk_pos.y]
			text += "World Pos: (%.1f, %.1f, %.1f)\n" % [player_pos.x, player_pos.y, player_pos.z]
	
	# Thread information
	text += "\n=== Generation ===\n"
	text += "Generation Threads: %d\n" % chunk_manager.generation_threads.size()
	text += "Is Running: %s" % chunk_manager._is_running
	
	info_label.text = text

func _get_local_player() -> Node3D:
	"""Find the local player in the scene."""
	# In single player mode (no multiplayer peer), any player is the local player
	if not multiplayer.has_multiplayer_peer():
		# Try human player first
		var human_players = get_tree().get_nodes_in_group("human_player")
		if human_players.size() > 0:
			return human_players[0]
		# Try dog player
		var dog_players = get_tree().get_nodes_in_group("dog_player")
		if dog_players.size() > 0:
			return dog_players[0]
		# Try generic player
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			return players[0]
	
	# Multiplayer mode - find authority player
	# Try to find local player
	for node in get_tree().get_nodes_in_group("human_player"):
		if node.is_multiplayer_authority():
			return node
	
	# Try dog player
	for node in get_tree().get_nodes_in_group("dog_player"):
		if node.is_multiplayer_authority():
			return node
	
	# Try generic player
	for node in get_tree().get_nodes_in_group("player"):
		if node.is_multiplayer_authority():
			return node
	
	return null


func _update_chunk_border_visibility() -> void:
	"""Update the visibility of chunk borders for all active chunks."""
	if not chunk_manager:
		return
		
	for chunk_pos in chunk_manager.active_chunks:
		var chunk = chunk_manager.active_chunks[chunk_pos]
		if is_instance_valid(chunk) and chunk.has_method("set"):
			chunk.set("show_borders", show_chunk_borders)
			# If chunk is already loaded, rebuild borders
			if chunk.current_state == Chunk.State.LOADED:
				if show_chunk_borders and not chunk.border_mesh_instance:
					chunk._build_chunk_borders()
				elif not show_chunk_borders and chunk.border_mesh_instance:
					chunk.border_mesh_instance.queue_free()
					chunk.border_mesh_instance = null 