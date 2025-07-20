extends Node

# --- Signals ---
signal required_chunks_changed(required_chunks: Dictionary)

# --- Constants ---
const UPDATE_INTERVAL := 0.2

# --- Properties ---
var player_positions: Dictionary = {} # { id: Vector3 }
var _update_timer := 0.0
var tracked_players: Dictionary = {} # { id: player_node } for multiplayer tracking

# Configurable render distance settings
var load_distance: int = GameConstants.RENDER_DISTANCE.DEFAULT
var unload_distance: int = GameConstants.RENDER_DISTANCE.DEFAULT + GameConstants.RENDER_DISTANCE.UNLOAD_OFFSET

# Resume handling
var _resume_delay_timer := 0.0
var _is_resuming := false
const RESUME_DELAY := 0.5  # Wait half a second after resume before chunk updates

# --- Engine Callbacks ---
func _ready() -> void:
	# Set process mode to pausable so chunk calculations stop during pause
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _process(delta: float) -> void:
	# Skip processing if paused to avoid accumulating updates
	if get_tree().paused:
		_is_resuming = true
		_resume_delay_timer = 0.0
		return
	
	# Handle resume delay to prevent chunk calculation spike
	if _is_resuming:
		_resume_delay_timer += delta
		if _resume_delay_timer < RESUME_DELAY:
			return  # Wait before resuming chunk updates
		else:
			_is_resuming = false
			print("PlayerTracker: Resuming chunk updates after delay")
		
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_update_tracked_players()
		_calculate_required_chunks()

# --- Public Methods ---
func update_player_position(id: int, pos: Vector3) -> void:
	player_positions[id] = pos

func remove_player(id: int) -> void:
	player_positions.erase(id)

func clear_all_players() -> void:
	"""Clear all player tracking - used when returning to main menu."""
	player_positions.clear()
	tracked_players.clear()

func register_multiplayer_player(player_id: int, player_node: Node3D) -> void:
	"""Register a multiplayer player for chunk tracking."""
	tracked_players[player_id] = player_node
	print("PlayerTracker: Registered multiplayer player ", player_id)

func unregister_multiplayer_player(player_id: int) -> void:
	"""Unregister a multiplayer player."""
	tracked_players.erase(player_id)
	player_positions.erase(player_id)
	print("PlayerTracker: Unregistered multiplayer player ", player_id)

func set_render_distance(distance: int) -> void:
	"""Set the render distance for chunk loading/unloading."""
	# Clamp to valid range
	var clamped_distance = clamp(distance, GameConstants.RENDER_DISTANCE.MIN, GameConstants.RENDER_DISTANCE.MAX)
	
	load_distance = clamped_distance
	unload_distance = clamped_distance + GameConstants.RENDER_DISTANCE.UNLOAD_OFFSET
	
	print("PlayerTracker: Updated render distance - Load: %d, Unload: %d" % [load_distance, unload_distance])
	
	# Recalculate chunks immediately
	_calculate_required_chunks()

# --- Private Methods ---
func _calculate_required_chunks() -> void:
	var required_chunks := {}
	
	for id in player_positions:
		var player_pos = player_positions[id]
		var center_chunk_pos := Vector2i(
			floor(player_pos.x / Chunk.CHUNK_SIZE.x),
			floor(player_pos.z / Chunk.CHUNK_SIZE.y)
		)
		
		for z in range(-load_distance, load_distance + 1):
			for x in range(-load_distance, load_distance + 1):
				var chunk_pos = center_chunk_pos + Vector2i(x, z)
				var distance = (center_chunk_pos - chunk_pos).length()
				
				if distance > unload_distance:
					continue
					
				var lod = _get_lod_for_distance(distance)
				
				if not required_chunks.has(chunk_pos) or lod < required_chunks[chunk_pos]:
					required_chunks[chunk_pos] = lod
	
	required_chunks_changed.emit(required_chunks)

func _get_lod_for_distance(d: float) -> Chunk.LOD:
	# LOD thresholds based on render distance
	var high_threshold = max(1.0, load_distance * 0.33)
	var medium_threshold = max(2.0, load_distance * 0.66)
	var low_threshold = float(load_distance)
	
	if d <= high_threshold: return Chunk.LOD.HIGH
	if d <= medium_threshold: return Chunk.LOD.MEDIUM
	if d <= low_threshold: return Chunk.LOD.LOW
	return Chunk.LOD.NONE

func _update_tracked_players() -> void:
	"""Update positions of all tracked multiplayer players."""
	for player_id in tracked_players:
		var player_node = tracked_players[player_id]
		if is_instance_valid(player_node):
			player_positions[player_id] = player_node.global_position
		else:
			# Clean up invalid player references
			tracked_players.erase(player_id)
			player_positions.erase(player_id) 
