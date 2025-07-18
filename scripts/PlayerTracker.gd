class_name PlayerTracker
extends Node

# --- Constants ---
const UPDATE_INTERVAL: float = 0.1  # How often to recalculate required chunks

# --- Properties ---
var chunk_manager: ChunkManager = null  # Set by ChunkManager
var player_positions: Dictionary = {}    # player_id -> PlayerData
var required_chunks: Array = []          # Array of chunk requirements
var update_timer: float = 0.0

# --- Inner Classes ---
class PlayerData:
	var position: Vector3
	var velocity: Vector3
	var last_chunk_pos: Vector2i
	var is_active: bool = true

# --- Engine Callbacks ---
func _ready() -> void:
	"""Initialize the player tracker."""
	print("PlayerTracker: Initialized")

func _process(delta: float) -> void:
	"""Periodically update required chunks based on player positions."""
	update_timer += delta
	
	if update_timer >= UPDATE_INTERVAL:
		update_timer = 0.0
		_update_required_chunks()

# --- Public Methods ---
func update_player_position(player_id: int, position: Vector3, velocity: Vector3 = Vector3.ZERO) -> void:
	"""Update a player's position and velocity."""
	if not player_positions.has(player_id):
		player_positions[player_id] = PlayerData.new()
	
	var player_data: PlayerData = player_positions[player_id]
	player_data.position = position
	player_data.velocity = velocity
	player_data.is_active = true
	
	# Track chunk changes for debugging
	var new_chunk_pos := _world_to_chunk_position(position)
	if player_data.last_chunk_pos != new_chunk_pos:
		player_data.last_chunk_pos = new_chunk_pos
		print("PlayerTracker: Player %d moved to chunk %v" % [player_id, new_chunk_pos])

func remove_player(player_id: int) -> void:
	"""Remove a player from tracking."""
	if player_positions.has(player_id):
		player_positions.erase(player_id)
		print("PlayerTracker: Removed player %d" % player_id)

func get_required_chunks() -> Array:
	"""Get the list of all chunks required by all players."""
	return required_chunks

func get_min_distance_to_chunk(chunk_pos: Vector2i) -> float:
	"""Get the minimum distance from any player to a chunk."""
	var min_distance := INF
	
	for player_data in player_positions.values():
		if not player_data.is_active:
			continue
			
		var player_chunk_pos := _world_to_chunk_position(player_data.position)
		var distance := float((chunk_pos - player_chunk_pos).length())
		min_distance = min(min_distance, distance)
	
	return min_distance

func get_active_player_count() -> int:
	"""Get the number of active players being tracked."""
	var count := 0
	for player_data in player_positions.values():
		if player_data.is_active:
			count += 1
	return count

# --- Private Methods ---
func _update_required_chunks() -> void:
	"""Recalculate which chunks are needed based on all player positions."""
	var new_required_chunks: Array = []
	var chunk_requirements: Dictionary = {}  # chunk_pos -> {lod, priority}
	
	# Process each player
	for player_id in player_positions:
		var player_data: PlayerData = player_positions[player_id]
		if not player_data.is_active:
			continue
		
		var player_chunk_pos := _world_to_chunk_position(player_data.position)
		
		# Add chunks in concentric rings around the player
		_add_chunks_for_player(player_chunk_pos, player_data, chunk_requirements)
		
		# Add predictive chunks based on movement direction
		if player_data.velocity.length() > 0.1:
			_add_predictive_chunks(player_chunk_pos, player_data, chunk_requirements)
	
	# Convert requirements dictionary to array
	for chunk_pos in chunk_requirements:
		var req = chunk_requirements[chunk_pos]
		new_required_chunks.append({
			"position": chunk_pos,
			"lod": req["lod"],
			"priority": req["priority"]
		})
	
	# Sort by priority (highest first)
	new_required_chunks.sort_custom(func(a, b): return a["priority"] > b["priority"])
	
	required_chunks = new_required_chunks

func _add_chunks_for_player(center_chunk: Vector2i, player_data: PlayerData, requirements: Dictionary) -> void:
	"""Add chunk requirements for a single player."""
	# Process chunks in expanding rings
	for radius in range(ChunkManager.UNLOAD_DISTANCE + 1):
		var chunks_in_ring := _get_chunks_in_ring(center_chunk, radius)
		
		for chunk_pos in chunks_in_ring:
			var lod := _calculate_lod_for_distance(radius)
			var priority := _calculate_chunk_priority(chunk_pos, center_chunk, player_data, radius)
			
			# Only add if within load distance
			if lod != Chunk.LODLevel.UNLOADED:
				if not requirements.has(chunk_pos):
					requirements[chunk_pos] = {"lod": lod, "priority": priority}
				else:
					# Use highest detail level if multiple players need the chunk
					var existing = requirements[chunk_pos]
					if lod < existing["lod"]:  # Lower enum value = higher detail
						existing["lod"] = lod
					existing["priority"] = max(existing["priority"], priority)

func _add_predictive_chunks(player_chunk: Vector2i, player_data: PlayerData, requirements: Dictionary) -> void:
	"""Add chunks in the player's movement direction for predictive loading."""
	var move_dir := player_data.velocity.normalized()
	if move_dir.length() < 0.1:
		return
	
	# Convert movement direction to chunk space
	var chunk_dir := Vector2(move_dir.x, move_dir.z).normalized()
	
	# Add chunks in movement direction
	for distance in range(1, ChunkManager.PREDICTIVE_LOAD_DISTANCE + 1):
		var predicted_chunk := player_chunk + Vector2i(
			int(round(chunk_dir.x * distance)),
			int(round(chunk_dir.y * distance))
		)
		
		# Calculate appropriate LOD for predicted chunks
		var actual_distance := (predicted_chunk - player_chunk).length()
		var lod := _calculate_lod_for_distance(actual_distance)
		
		if lod != Chunk.LODLevel.UNLOADED:
			var priority := 50.0 + (10.0 / distance)  # High priority for predictive loading
			
			if not requirements.has(predicted_chunk):
				requirements[predicted_chunk] = {"lod": lod, "priority": priority}
			else:
				var existing = requirements[predicted_chunk]
				existing["priority"] = max(existing["priority"], priority)

func _get_chunks_in_ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	"""Get all chunk positions at a specific radius from center."""
	var chunks: Array[Vector2i] = []
	
	if radius == 0:
		chunks.append(center)
		return chunks
	
	# Add chunks in a square ring
	for x in range(-radius, radius + 1):
		# Top and bottom edges
		chunks.append(center + Vector2i(x, -radius))
		chunks.append(center + Vector2i(x, radius))
	
	# Left and right edges (excluding corners to avoid duplicates)
	for y in range(-radius + 1, radius):
		chunks.append(center + Vector2i(-radius, y))
		chunks.append(center + Vector2i(radius, y))
	
	return chunks

func _calculate_lod_for_distance(distance: float) -> Chunk.LODLevel:
	"""Calculate appropriate LOD level based on distance from player."""
	if distance <= ChunkManager.LOAD_DISTANCE_HIGH:
		return Chunk.LODLevel.HIGH
	elif distance <= ChunkManager.LOAD_DISTANCE_MEDIUM:
		return Chunk.LODLevel.MEDIUM
	elif distance <= ChunkManager.LOAD_DISTANCE_LOW:
		return Chunk.LODLevel.LOW
	else:
		return Chunk.LODLevel.UNLOADED

func _calculate_chunk_priority(chunk_pos: Vector2i, player_chunk: Vector2i, player_data: PlayerData, distance: float) -> float:
	"""Calculate loading priority for a chunk."""
	var priority: float = 100.0 / max(distance, 1.0)  # Base priority from distance
	
	# Boost priority for chunks in movement direction
	if player_data.velocity.length() > 0.1:
		var move_dir := Vector2(player_data.velocity.x, player_data.velocity.z).normalized()
		var chunk_dir := Vector2(chunk_pos - player_chunk).normalized()
		
		if chunk_dir.length() > 0.1:
			var alignment := move_dir.dot(chunk_dir)
			if alignment > 0.5:  # Moving towards chunk
				priority += 20.0 * alignment
	
	# Boost priority for chunks at higher detail levels
	var lod := _calculate_lod_for_distance(distance)
	match lod:
		Chunk.LODLevel.HIGH:
			priority += 30.0
		Chunk.LODLevel.MEDIUM:
			priority += 15.0
		Chunk.LODLevel.LOW:
			priority += 5.0
	
	return priority

func _world_to_chunk_position(world_pos: Vector3) -> Vector2i:
	"""Convert world position to chunk coordinates."""
	return Vector2i(
		int(floor(world_pos.x / Chunk.CHUNK_SIZE.x)),
		int(floor(world_pos.z / Chunk.CHUNK_SIZE.y))
	) 
