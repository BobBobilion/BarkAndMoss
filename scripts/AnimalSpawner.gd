class_name AnimalSpawner
extends Node

# --- Exports ---
@export var enable_spawning: bool = false

# --- Multiplayer State ---
var spawned_animals: Dictionary = {}  # {animal_id: animal_node}
var is_host: bool = false
var next_animal_id: int = 0

# --- Imports ---
const BiomeManagerClass = preload("res://scripts/BiomeManager.gd")

# --- Constants ---
const SPAWN_DISTANCE_MIN: float = GameConstants.SPAWN.DISTANCE_MIN
const SPAWN_DISTANCE_MAX: float = GameConstants.SPAWN.DISTANCE_MAX
const DESPAWN_RADIUS: float = GameConstants.SPAWN.DESPAWN_RADIUS
const MAX_ANIMALS_PER_AREA: int = GameConstants.SPAWN.MAX_ANIMALS_PER_AREA
const SPAWN_CHECK_INTERVAL: float = GameConstants.SPAWN.CHECK_INTERVAL
const DESPAWN_CHECK_INTERVAL: float = GameConstants.SPAWN.DESPAWN_CHECK_INTERVAL
const TERRAIN_HEIGHT_OFFSET: float = GameConstants.SPAWN.TERRAIN_HEIGHT_OFFSET

# --- Performance Constants ---
const AI_UPDATE_INTERVAL_CLOSE: float = 0.1  # 10Hz for nearby animals
const AI_UPDATE_INTERVAL_MEDIUM: float = 0.3  # ~3Hz for medium range
const AI_UPDATE_INTERVAL_FAR: float = 1.0    # 1Hz for far animals
const AI_DISABLE_DISTANCE: float = 100.0      # Disable AI beyond this
const ANIMATION_DISABLE_DISTANCE: float = 50.0 # Disable animations beyond this

# --- Network Sync Constants ---
const SYNC_BATCH_SIZE: int = 10              # Max animals per sync message
const SYNC_INTERVAL: float = 0.1              # 10Hz sync rate
const SYNC_DISTANCE_CLOSE: float = 30.0       # Full sync rate
const SYNC_DISTANCE_MEDIUM: float = 60.0      # Half sync rate
const SYNC_DISTANCE_FAR: float = 100.0        # Quarter sync rate

# --- Animal Types and Biome Preferences ---
var animal_scenes: Dictionary = {
	"rabbit": {
		"scene": preload("res://scenes/Rabbit.tscn"),
		"weight": 5,
		"max_count_per_area": GameConstants.SPAWN.RABBIT_COUNT_PER_AREA,
		"biome_preferences": {
			BiomeManagerClass.BiomeType.FOREST: 1.0,
			BiomeManagerClass.BiomeType.AUTUMN: 0.8,
			BiomeManagerClass.BiomeType.SNOW: 0.9,
			BiomeManagerClass.BiomeType.MOUNTAIN: 0.1
		}
	},
	"bird": {
		"scene": preload("res://scenes/Bird.tscn"),
		"weight": 4,
		"max_count_per_area": GameConstants.SPAWN.BIRD_COUNT_PER_AREA,
		"biome_preferences": {
			BiomeManagerClass.BiomeType.FOREST: 0.9,
			BiomeManagerClass.BiomeType.AUTUMN: 0.7,
			BiomeManagerClass.BiomeType.SNOW: 0.6,
			BiomeManagerClass.BiomeType.MOUNTAIN: 0.8
		}
	},
	"deer": {
		"scene": preload("res://scenes/Deer.tscn"),
		"weight": 3,
		"max_count_per_area": GameConstants.SPAWN.DEER_COUNT_PER_AREA,
		"biome_preferences": {
			BiomeManagerClass.BiomeType.FOREST: 1.0,
			BiomeManagerClass.BiomeType.AUTUMN: 0.9,
			BiomeManagerClass.BiomeType.SNOW: 0.4,
			BiomeManagerClass.BiomeType.MOUNTAIN: 0.2
		}
	}
}

# --- Node References ---
var chunk_manager: ChunkManager
var biome_manager: BiomeManagerClass
var players: Array[Node3D] = []
var spawn_parent: Node3D = null

# --- Timers ---
var spawn_timer: Timer
var despawn_timer: Timer
var sync_timer: Timer

# --- State ---
var current_animals: Dictionary = {}  # Track spawned animals by type
var proximity_animals: Dictionary = {}  # Track animals by player proximity
var animal_sync_queue: Array = []  # Queue of animals needing sync
var sync_counter: int = 0  # For staggered syncing

# --- Spatial Grid for Performance ---
var spatial_grid: Dictionary = {}  # Grid cells for spatial queries
const GRID_CELL_SIZE: float = 50.0


func _ready() -> void:
	"""Initialize the animal spawner with optimized timer-based system."""
	add_to_group("animal_spawner")
	
	# Check if we're the host
	is_host = multiplayer.is_server()
	print("AnimalSpawner: Initialization - is_host: ", is_host, ", has_peer: ", multiplayer.has_multiplayer_peer(), ", unique_id: ", multiplayer.get_unique_id())
	
	# Add debug timer to periodically check state
	if multiplayer.has_multiplayer_peer():
		var debug_timer = Timer.new()
		debug_timer.wait_time = 5.0
		debug_timer.timeout.connect(_debug_multiplayer_state)
		debug_timer.autostart = true
		add_child(debug_timer)
	
	# Enable debug input
	set_process_input(true)
	
	# Set up timers instead of per-frame updates
	_setup_timers()
	
	# Try to find required components
	_try_get_biome_manager()
	_try_get_chunk_manager()
	_find_spawn_parent()
	
	# Set up multiplayer connections if in multiplayer mode
	if multiplayer.has_multiplayer_peer():
		print("AnimalSpawner: Node path: ", get_path())
		if is_host:
			# Host listens for client requests
			multiplayer.peer_connected.connect(_on_peer_connected)
		else:
			# Client: Request sync after a delay to ensure everything is ready
			call_deferred("_delayed_sync_request")


func _setup_timers() -> void:
	"""Set up all timers for the spawning system."""
	# Spawn timer
	spawn_timer = Timer.new()
	spawn_timer.wait_time = SPAWN_CHECK_INTERVAL
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	spawn_timer.autostart = false
	add_child(spawn_timer)
	
	# Despawn timer
	despawn_timer = Timer.new()
	despawn_timer.wait_time = DESPAWN_CHECK_INTERVAL
	despawn_timer.timeout.connect(_on_despawn_timer_timeout)
	despawn_timer.autostart = false
	add_child(despawn_timer)
	
	# Sync timer (for multiplayer)
	if multiplayer.has_multiplayer_peer():
		sync_timer = Timer.new()
		sync_timer.wait_time = SYNC_INTERVAL
		sync_timer.timeout.connect(_on_sync_timer_timeout)
		sync_timer.autostart = false
		add_child(sync_timer)


func set_spawning_enabled(enabled: bool) -> void:
	"""Enable or disable the spawning system."""
	print("AnimalSpawner: set_spawning_enabled called with: ", enabled)
	enable_spawning = enabled
	
	if enabled:
		# Try to get components if not already available
		if not biome_manager:
			print("AnimalSpawner: BiomeManager not found, trying to get it...")
			_try_get_biome_manager()
		
		if not spawn_parent:
			print("AnimalSpawner: Spawn parent not found, trying to get it...")
			_find_spawn_parent()
		
		# Start timers if we have required components
		if biome_manager and spawn_parent:
			print("AnimalSpawner: Starting spawning timers...")
			print("  - BiomeManager: ", biome_manager)
			print("  - Spawn parent: ", spawn_parent)
			print("  - Is host: ", is_host)
			spawn_timer.start()
			despawn_timer.start()
			if sync_timer and is_host:
				sync_timer.start()
			print("AnimalSpawner: Spawning system activated!")
			
			# If client in multiplayer, request existing animals
			if not is_host and multiplayer.has_multiplayer_peer():
				print("AnimalSpawner: Client requesting existing animals after spawn enable...")
				# Add a small delay to ensure the host is ready
				await get_tree().create_timer(0.5).timeout
				_request_existing_animals()
		else:
			print("AnimalSpawner: ERROR - Cannot start spawning, missing components:")
			print("  - BiomeManager: ", biome_manager)
			print("  - Spawn parent: ", spawn_parent)
	else:
		# Stop all timers
		print("AnimalSpawner: Stopping spawning timers...")
		spawn_timer.stop()
		despawn_timer.stop()
		if sync_timer:
			sync_timer.stop()


func _on_spawn_timer_timeout() -> void:
	"""Handle spawn timer timeout - attempt to spawn animals."""
	if not enable_spawning or not biome_manager or not spawn_parent:
		return
	
	_cleanup_invalid_animals()
	_update_player_list()
	
	if is_host or not multiplayer.has_multiplayer_peer():
		_attempt_spawn_animals()
		# Only print spawn info on host every 10th check to reduce spam
		if spawned_animals.size() % 10 == 0:
			print("AnimalSpawner: Host has ", spawned_animals.size(), " animals spawned")


func _on_despawn_timer_timeout() -> void:
	"""Handle despawn timer timeout - check for animals to remove."""
	if not enable_spawning:
		return
	
	_check_for_despawns()


func _on_sync_timer_timeout() -> void:
	"""Handle sync timer timeout - sync animal states to clients."""
	if not is_host or not multiplayer.has_multiplayer_peer():
		return
	
	_sync_animal_batch()


func _update_player_list() -> void:
	"""Update the list of active players for spawn calculations."""
	players.clear()
	
	var human_players: Array[Node] = get_tree().get_nodes_in_group("human_player")
	var dog_players: Array[Node] = get_tree().get_nodes_in_group("dog_player")
	
	for player in human_players:
		if is_instance_valid(player):
			players.append(player as Node3D)
	
	for player in dog_players:
		if is_instance_valid(player):
			players.append(player as Node3D)


func _attempt_spawn_animals() -> void:
	"""Attempt to spawn animals using optimized proximity-based spawning."""
	if players.is_empty():
		print("AnimalSpawner: No players found, cannot spawn animals")
		return
	
	print("AnimalSpawner: Attempting to spawn animals for ", players.size(), " players")
	
	# Update spatial grid for efficient proximity queries
	_update_spatial_grid()
	
	# Update proximity tracking
	_update_proximity_tracking()
	
	# Try to spawn animals for each player's area
	for player in players:
		if not is_instance_valid(player):
			continue
		var player_id: int = player.get_instance_id()
		print("AnimalSpawner: Checking spawn for player: ", player, " (ID: ", player_id, ")")
		_attempt_spawn_for_player_area(player, player_id)


func _try_spawn_animal(animal_type: String, animal_data: Dictionary) -> void:
	"""Try to spawn a specific type of animal with multiplayer sync."""
	print("AnimalSpawner: _try_spawn_animal called for ", animal_type)
	var spawn_attempt_count: int = 0
	var max_spawn_attempts: int = 10
	
	while spawn_attempt_count < max_spawn_attempts:
		spawn_attempt_count += 1
		
		var spawn_position: Vector3 = _find_valid_spawn_position(animal_type)
		if spawn_position == Vector3.ZERO:
			print("AnimalSpawner: Failed to find valid spawn position for ", animal_type, " (attempt ", spawn_attempt_count, ")")
			continue
		
		# Check biome preference
		var ground_position: Vector3 = Vector3(spawn_position.x, 0, spawn_position.z)
		var biome_type: BiomeManagerClass.BiomeType = biome_manager.get_biome_at_position(ground_position)
		var biome_preference: float = _get_biome_preference(animal_type, biome_type, animal_data)
		
		if randf() > biome_preference:
			print("AnimalSpawner: Biome preference check failed for ", animal_type, " (pref: ", biome_preference, ")")
			continue
		
		# Generate unique animal ID
		var animal_id: int = _generate_animal_id()
		
		print("AnimalSpawner: SUCCESS! Spawning ", animal_type, " at ", spawn_position, " with ID ", animal_id)
		
		if is_host and multiplayer.has_multiplayer_peer():
			# Host spawns and syncs to clients
			_spawn_animal_local(animal_type, animal_data, spawn_position, animal_id)
			# Small delay to ensure animal is added to scene tree
			await get_tree().process_frame
			_spawn_animal_remote.rpc(animal_type, spawn_position, animal_id)
		else:
			# Single player or client-only spawn
			_spawn_animal_local(animal_type, animal_data, spawn_position, animal_id)
		
		return  # Successfully spawned


func _spawn_animal_local(animal_type: String, animal_data: Dictionary, position: Vector3, animal_id: int) -> void:
	"""Spawn an animal locally with optimizations."""
	print("AnimalSpawner: _spawn_animal_local called - Type: ", animal_type, ", ID: ", animal_id, ", Pos: ", position)
	
	var animal_scene: PackedScene = animal_data.scene
	var animal: Node3D = animal_scene.instantiate()
	
	# Set unique name for debugging
	animal.name = animal_type.capitalize() + "_" + str(animal_id)
	
	# Set animal ID
	animal.set_meta("animal_id", animal_id)
	animal.set_meta("animal_type", animal_type)
	
	# Mark as remote animal on clients
	if not is_host and multiplayer.has_multiplayer_peer():
		animal.set_meta("is_remote", true)
		# Set is_remote property if the animal script has it
		if "is_remote" in animal:
			animal.is_remote = true
		print("AnimalSpawner: Marked animal as remote on client")
	
	# Add to scene - ensure we're using the Main node
	if spawn_parent:
		spawn_parent.add_child(animal)
		animal.global_position = position
		
		# Force visibility
		animal.visible = true
		
		print("AnimalSpawner: Added ", animal.name, " to ", spawn_parent.get_path(), 
			  " at position ", position, " (actual pos: ", animal.global_position, ")")
		print("AnimalSpawner: Animal visible: ", animal.visible, ", Parent visible: ", spawn_parent.visible)
	else:
		print("AnimalSpawner: ERROR - No spawn parent available!")
		animal.queue_free()
		return
	
	# Set up LOD system
	_setup_animal_lod(animal)
	
	# Track the spawned animal
	spawned_animals[animal_id] = animal
	if not current_animals.has(animal_type):
		current_animals[animal_type] = []
	current_animals[animal_type].append(animal)
	
	# Add to spatial grid
	_add_to_spatial_grid(animal)
	
	# Connect death signal
	if animal.has_signal("animal_died"):
		animal.animal_died.connect(_on_animal_died.bind(animal_id))


@rpc("authority", "call_remote", "reliable")
func _spawn_animal_remote(animal_type: String, position: Vector3, animal_id: int) -> void:
	"""RPC to spawn an animal on clients."""
	print("\n=== CLIENT SPAWN RPC RECEIVED ===")
	print("AnimalSpawner: Client received spawn RPC for ", animal_type, " at ", position, " with ID ", animal_id)
	print("AnimalSpawner: Sender ID: ", multiplayer.get_remote_sender_id())
	print("AnimalSpawner: My peer ID: ", multiplayer.get_unique_id())
	
	if not animal_scenes.has(animal_type):
		push_error("Unknown animal type: " + animal_type)
		return
	
	print("AnimalSpawner: Animal scene found, spawning locally...")
	var animal_data = animal_scenes[animal_type]
	_spawn_animal_local(animal_type, animal_data, position, animal_id)
	print("================================\n")


func _setup_animal_lod(animal: Node3D) -> void:
	"""Set up Level of Detail system for an animal."""
	# Add LOD component as metadata
	animal.set_meta("lod_update_timer", 0.0)
	animal.set_meta("current_lod", 0)
	animal.set_meta("ai_enabled", true)
	animal.set_meta("animations_enabled", true)
	
	# Override animal's _physics_process with LOD-aware version
	if animal.has_method("_physics_process"):
		animal.set_physics_process(false)
		animal.set_meta("original_physics_process", true)


func _update_animal_lod(animal: Node3D, delta: float) -> void:
	"""Update LOD state for an animal based on distance to nearest player."""
	if not is_instance_valid(animal):
		return
	
	# Find nearest player distance
	var min_distance: float = INF
	for player in players:
		if is_instance_valid(player):
			var distance = animal.global_position.distance_to(player.global_position)
			min_distance = min(min_distance, distance)
	
	# Determine LOD level
	var lod_level: int = 0
	var ai_update_interval: float = AI_UPDATE_INTERVAL_CLOSE
	
	if min_distance > AI_DISABLE_DISTANCE:
		lod_level = 3  # Disabled
		animal.set_physics_process(false)
		animal.set_meta("ai_enabled", false)
		animal.set_meta("animations_enabled", false)
	elif min_distance > ANIMATION_DISABLE_DISTANCE:
		lod_level = 2  # Far
		ai_update_interval = AI_UPDATE_INTERVAL_FAR
		animal.set_meta("animations_enabled", false)
	elif min_distance > SYNC_DISTANCE_CLOSE:
		lod_level = 1  # Medium
		ai_update_interval = AI_UPDATE_INTERVAL_MEDIUM
		animal.set_meta("animations_enabled", true)
	else:
		lod_level = 0  # Close
		ai_update_interval = AI_UPDATE_INTERVAL_CLOSE
		animal.set_meta("animations_enabled", true)
	
	# Update LOD state
	var current_lod = animal.get_meta("current_lod", 0)
	if current_lod != lod_level:
		animal.set_meta("current_lod", lod_level)
		
		# Enable/disable physics process based on LOD
		if lod_level < 3 and animal.get_meta("original_physics_process", false):
			animal.set_physics_process(true)
	
	# Handle AI update timing
	if lod_level < 3:
		var update_timer = animal.get_meta("lod_update_timer", 0.0) + delta
		if update_timer >= ai_update_interval:
			animal.set_meta("lod_update_timer", 0.0)
			# Trigger AI update
			if animal.has_method("_update_ai"):
				animal._update_ai(update_timer)
		else:
			animal.set_meta("lod_update_timer", update_timer)


func _sync_animal_batch() -> void:
	"""Sync a batch of animals to clients."""
	if spawned_animals.is_empty():
		return
	
	var updates: Array = []
	var animals_to_sync: Array = []
	
	# Collect animals that need syncing based on proximity
	for animal_id in spawned_animals:
		var animal = spawned_animals[animal_id]
		if not is_instance_valid(animal):
			continue
		
		# Check sync frequency based on distance
		var needs_sync = _should_sync_animal(animal)
		if needs_sync:
			animals_to_sync.append(animal_id)
	
	# Process batch
	var batch_start = sync_counter % animals_to_sync.size() if animals_to_sync.size() > 0 else 0
	var batch_end = min(batch_start + SYNC_BATCH_SIZE, animals_to_sync.size())
	
	for i in range(batch_start, batch_end):
		var animal_id = animals_to_sync[i]
		var animal = spawned_animals[animal_id]
		if not is_instance_valid(animal):
			continue
		
		var update = {
			"id": animal_id,
			"pos": animal.global_position,
			"rot": animal.global_rotation.y
		}
		
		# Add state info if animal has it
		if animal.has_method("get_state_string"):
			update["state"] = animal.get_state_string()
		
		updates.append(update)
	
	sync_counter += SYNC_BATCH_SIZE
	
	# Send batch update
	if not updates.is_empty():
		print("AnimalSpawner: Host sending batch update with ", updates.size(), " animals")
		_sync_animals_batch.rpc(updates)


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_animals_batch(updates: Array) -> void:
	"""Receive batch animal updates on clients."""
	var valid_updates = 0
	var missing_animals = []
	
	for update in updates:
		if not spawned_animals.has(update.id):
			missing_animals.append(update.id)
			continue
		
		var animal = spawned_animals[update.id]
		if not is_instance_valid(animal):
			continue
		
		valid_updates += 1
		
		# Apply update with interpolation
		animal.set_meta("target_position", update.pos)
		animal.set_meta("target_rotation", update.rot)
		
		# Update state if provided
		if update.has("state") and animal.has_method("set_state_from_string"):
			animal.set_state_from_string(update.state)
	
	if missing_animals.size() > 0:
		print("AnimalSpawner: Client missing animals: ", missing_animals, " (requesting resync...)")
		# Request full sync if we're missing too many animals
		if missing_animals.size() > 5:
			_request_existing_animals()
	
	if valid_updates > 0:
		print("AnimalSpawner: Applied ", valid_updates, " / ", updates.size(), " animal updates")


func _should_sync_animal(animal: Node3D) -> bool:
	"""Determine if an animal should be synced based on player proximity."""
	var min_distance: float = INF
	
	for player in players:
		if is_instance_valid(player):
			var distance = animal.global_position.distance_to(player.global_position)
			min_distance = min(min_distance, distance)
	
	# Stagger sync based on distance
	if min_distance < SYNC_DISTANCE_CLOSE:
		return true  # Always sync
	elif min_distance < SYNC_DISTANCE_MEDIUM:
		return sync_counter % 2 == 0  # Half rate
	elif min_distance < SYNC_DISTANCE_FAR:
		return sync_counter % 4 == 0  # Quarter rate
	else:
		return false  # Don't sync


func _find_valid_spawn_position(animal_type: String = "") -> Vector3:
	"""Find a valid position to spawn an animal outside player view."""
	var attempts: int = 10
	
	while attempts > 0:
		attempts -= 1
		
		var reference_player: Node3D = null
		var valid_players: Array[Node3D] = []
		
		for player in players:
			if is_instance_valid(player) and not player.is_queued_for_deletion():
				valid_players.append(player)
		
		if valid_players.is_empty():
			return Vector3.ZERO
		
		reference_player = valid_players[randi() % valid_players.size()]
		
		var angle: float = randf() * TAU
		var distance: float = randf_range(SPAWN_DISTANCE_MIN, SPAWN_DISTANCE_MAX)
		
		var spawn_position: Vector3 = reference_player.global_position + Vector3(
			cos(angle) * distance,
			0,
			sin(angle) * distance
		)
		
		if _is_position_valid(spawn_position):
			# Get terrain height
			if chunk_manager and chunk_manager.has_method("get_height_at_position"):
				var terrain_height: float = chunk_manager.get_height_at_position(spawn_position)
				
				if animal_type == "bird":
					spawn_position.y = terrain_height + randf_range(4.0, 8.0)
				else:
					spawn_position.y = terrain_height + TERRAIN_HEIGHT_OFFSET
			else:
				var fallback_height: float = _get_fallback_terrain_height(spawn_position)
				
				if animal_type == "bird":
					spawn_position.y = fallback_height + randf_range(4.0, 8.0)
				else:
					spawn_position.y = fallback_height + TERRAIN_HEIGHT_OFFSET
			
			return spawn_position
	
	return Vector3.ZERO


func _is_position_valid(position: Vector3) -> bool:
	"""Check if a spawn position is valid."""
	for player in players:
		if not is_instance_valid(player) or player.is_queued_for_deletion():
			continue
		
		if position.distance_to(player.global_position) < SPAWN_DISTANCE_MIN:
			return false
	return true


func _cleanup_invalid_animals() -> void:
	"""Remove invalid/destroyed animals from tracking."""
	# Clean spawned_animals dictionary
	var to_remove: Array = []
	for animal_id in spawned_animals:
		if not is_instance_valid(spawned_animals[animal_id]):
			to_remove.append(animal_id)
	
	for id in to_remove:
		spawned_animals.erase(id)
	
	# Clean current_animals
	for animal_type in current_animals.keys():
		var animal_list: Array = current_animals[animal_type]
		for i in range(animal_list.size() - 1, -1, -1):
			if not is_instance_valid(animal_list[i]):
				animal_list.remove_at(i)
	
	# Clean proximity tracking
	for player_id in proximity_animals.keys():
		for animal_type in proximity_animals[player_id].keys():
			var proximity_list: Array = proximity_animals[player_id][animal_type]
			for i in range(proximity_list.size() - 1, -1, -1):
				if not is_instance_valid(proximity_list[i]):
					proximity_list.remove_at(i)


func _check_for_despawns() -> void:
	"""Check if any animals should be despawned based on distance."""
	for animal_type in current_animals.keys():
		var animal_list: Array = current_animals[animal_type]
		
		for i in range(animal_list.size() - 1, -1, -1):
			var animal = animal_list[i]
			if not is_instance_valid(animal):
				animal_list.remove_at(i)
				continue
			
			var should_despawn: bool = true
			for player in players:
				if not is_instance_valid(player):
					continue
				
				var distance: float = animal.global_position.distance_to(player.global_position)
				if distance <= DESPAWN_RADIUS:
					should_despawn = false
					break
			
			if should_despawn:
				var animal_id = animal.get_meta("animal_id", -1)
				if animal_id != -1:
					spawned_animals.erase(animal_id)
					if is_host and multiplayer.has_multiplayer_peer():
						_despawn_animal_remote.rpc(animal_id)
				
				animal.queue_free()
				animal_list.remove_at(i)


@rpc("authority", "call_remote", "reliable")
func _despawn_animal_remote(animal_id: int) -> void:
	"""RPC to despawn an animal on clients."""
	print("AnimalSpawner: Client received despawn RPC for animal ", animal_id)
	if spawned_animals.has(animal_id):
		var animal = spawned_animals[animal_id]
		if is_instance_valid(animal):
			animal.queue_free()
		spawned_animals.erase(animal_id)


func _on_animal_died(animal: Node3D, animal_id: int) -> void:
	"""Handle animal death with corpse sync."""
	if not is_instance_valid(animal):
		return
	
	var animal_type = animal.get_meta("animal_type", "unknown")
	var position = animal.global_position
	var rotation = animal.global_rotation
	
	print("AnimalSpawner: Animal died - Type: ", animal_type, ", ID: ", animal_id, ", Pos: ", position)
	
	# Remove from tracking
	remove_animal_immediately(animal)
	
	# Only sync if we're the host or the one who killed it
	if multiplayer.has_multiplayer_peer():
		if is_host:
			# Host always syncs death
			_sync_animal_death.rpc(animal_id, position, rotation)
		else:
			# Client only syncs if they killed it (arrow hit)
			var is_my_kill = animal.get_meta("killed_by_peer", -1) == multiplayer.get_unique_id()
			if is_my_kill:
				_sync_animal_death.rpc_id(1, animal_id, position, rotation)


@rpc("any_peer", "call_remote", "reliable")
func _sync_animal_death(animal_id: int, death_position: Vector3, death_rotation: Vector3) -> void:
	"""Sync animal death to all players."""
	print("AnimalSpawner: Received animal death sync for ID ", animal_id)
	
	# Remove the animal if it exists
	if spawned_animals.has(animal_id):
		var animal = spawned_animals[animal_id]
		if is_instance_valid(animal):
			# Force the animal to die without triggering another sync
			animal.set_meta("synced_death", true)
			if animal.has_method("die"):
				animal.die()
			else:
				animal.queue_free()
		spawned_animals.erase(animal_id)


func remove_animal_immediately(animal: Node3D) -> void:
	"""Immediately remove an animal from all tracking."""
	if not animal or not is_instance_valid(animal):
		return
	
	var animal_id = animal.get_meta("animal_id", -1)
	if animal_id != -1:
		spawned_animals.erase(animal_id)
	
	# Remove from current_animals
	for animal_type in current_animals.keys():
		var animal_list: Array = current_animals[animal_type]
		animal_list.erase(animal)
	
	# Remove from proximity tracking
	for player_id in proximity_animals.keys():
		for animal_type in proximity_animals[player_id].keys():
			proximity_animals[player_id][animal_type].erase(animal)
	
	# Remove from spatial grid
	_remove_from_spatial_grid(animal)


func _update_proximity_tracking() -> void:
	"""Update proximity tracking using spatial grid for performance."""
	proximity_animals.clear()
	
	for player in players:
		if not is_instance_valid(player):
			continue
			
		var player_id: int = player.get_instance_id()
		proximity_animals[player_id] = {}
		
		for animal_type in animal_scenes.keys():
			proximity_animals[player_id][animal_type] = []
		
		# Use spatial grid to find nearby animals
		var nearby_animals = _get_animals_near_position(player.global_position, SPAWN_DISTANCE_MAX)
		
		for animal in nearby_animals:
			if not is_instance_valid(animal):
				continue
				
			var animal_type = animal.get_meta("animal_type", "unknown")
			if proximity_animals[player_id].has(animal_type):
				proximity_animals[player_id][animal_type].append(animal)


func _attempt_spawn_for_player_area(player: Node3D, player_id: int) -> void:
	"""Attempt to spawn animals in a specific player's proximity area."""
	if not proximity_animals.has(player_id):
		print("AnimalSpawner: No proximity data for player ", player_id)
		return
	
	var player_proximity: Dictionary = proximity_animals[player_id]
	var total_animals_in_area: int = _count_animals_in_proximity_area(player_id)
	
	print("AnimalSpawner: Player area has ", total_animals_in_area, " animals (max: ", MAX_ANIMALS_PER_AREA, ")")
	
	if total_animals_in_area >= MAX_ANIMALS_PER_AREA:
		print("AnimalSpawner: Area full, skipping spawn")
		return
	
	for animal_type in animal_scenes.keys():
		var animal_data: Dictionary = animal_scenes[animal_type]
		var current_count_in_area: int = player_proximity[animal_type].size()
		
		print("AnimalSpawner: ", animal_type, " count: ", current_count_in_area, " / ", animal_data.max_count_per_area)
		
		if current_count_in_area < animal_data.max_count_per_area:
			print("AnimalSpawner: Trying to spawn ", animal_type)
			_try_spawn_animal(animal_type, animal_data)


func _count_animals_in_proximity_area(player_id: int) -> int:
	"""Count total animals in a player's proximity area."""
	if not proximity_animals.has(player_id):
		return 0
	
	var total: int = 0
	for animal_type in proximity_animals[player_id].keys():
		total += proximity_animals[player_id][animal_type].size()
	
	return total


# --- Spatial Grid System ---

func _update_spatial_grid() -> void:
	"""Update the spatial grid with current animal positions."""
	spatial_grid.clear()
	
	for animal_type in current_animals.keys():
		for animal in current_animals[animal_type]:
			if is_instance_valid(animal):
				_add_to_spatial_grid(animal)


func _add_to_spatial_grid(animal: Node3D) -> void:
	"""Add an animal to the spatial grid."""
	var grid_pos = _world_to_grid(animal.global_position)
	var key = _grid_key(grid_pos)
	
	if not spatial_grid.has(key):
		spatial_grid[key] = []
	
	spatial_grid[key].append(animal)
	animal.set_meta("grid_key", key)


func _remove_from_spatial_grid(animal: Node3D) -> void:
	"""Remove an animal from the spatial grid."""
	var key = animal.get_meta("grid_key", "")
	if key != "" and spatial_grid.has(key):
		spatial_grid[key].erase(animal)
		if spatial_grid[key].is_empty():
			spatial_grid.erase(key)


func _get_animals_near_position(position: Vector3, radius: float) -> Array:
	"""Get all animals within radius of position using spatial grid."""
	var results: Array = []
	var grid_radius = int(ceil(radius / GRID_CELL_SIZE))
	var center_grid = _world_to_grid(position)
	
	# Check all relevant grid cells
	for x in range(-grid_radius, grid_radius + 1):
		for z in range(-grid_radius, grid_radius + 1):
			var check_grid = center_grid + Vector2i(x, z)
			var key = _grid_key(check_grid)
			
			if spatial_grid.has(key):
				for animal in spatial_grid[key]:
					if is_instance_valid(animal):
						var distance = animal.global_position.distance_to(position)
						if distance <= radius:
							results.append(animal)
	
	return results


func _world_to_grid(world_pos: Vector3) -> Vector2i:
	"""Convert world position to grid coordinates."""
	return Vector2i(
		int(floor(world_pos.x / GRID_CELL_SIZE)),
		int(floor(world_pos.z / GRID_CELL_SIZE))
	)


func _grid_key(grid_pos: Vector2i) -> String:
	"""Generate a key for the grid position."""
	return "%d,%d" % [grid_pos.x, grid_pos.y]


# --- Multiplayer Sync for Late Joining ---

func _on_peer_connected(peer_id: int) -> void:
	"""Called when a new peer connects - sync existing animals to them."""
	print("AnimalSpawner: New peer connected: ", peer_id, ", syncing existing animals...")
	
	# Wait a moment for the client to be ready
	await get_tree().create_timer(0.5).timeout
	
	# Send all existing animals to the new client
	var animals_to_sync: Array = []
	for animal_id in spawned_animals:
		var animal = spawned_animals[animal_id]
		if is_instance_valid(animal):
			var animal_data = {
				"id": animal_id,
				"type": animal.get_meta("animal_type", "unknown"),
				"pos": animal.global_position,
				"rot": animal.global_rotation.y
			}
			
			# Add state if available
			if animal.has_method("get_state_string"):
				animal_data["state"] = animal.get_state_string()
			
			animals_to_sync.append(animal_data)
	
	if animals_to_sync.size() > 0:
		print("AnimalSpawner: Sending ", animals_to_sync.size(), " animals to peer ", peer_id)
		_sync_existing_animals.rpc_id(peer_id, animals_to_sync)


func _request_existing_animals() -> void:
	"""Client requests existing animals from host."""
	print("AnimalSpawner: Client requesting existing animals from host...")
	print("AnimalSpawner: Current spawned animals count: ", spawned_animals.size())
	_request_animal_sync.rpc_id(1)  # Send to host (ID 1)


@rpc("any_peer", "call_remote", "reliable")
func _request_animal_sync() -> void:
	"""Host receives request to sync animals to a client."""
	if not is_host:
		print("AnimalSpawner: Non-host received sync request, ignoring")
		return
		
	var sender_id = multiplayer.get_remote_sender_id()
	print("AnimalSpawner: Host received sync request from peer ", sender_id)
	print("AnimalSpawner: Host currently has ", spawned_animals.size(), " spawned animals")
	
	# Send all existing animals to the requesting client
	var animals_to_sync: Array = []
	for animal_id in spawned_animals:
		var animal = spawned_animals[animal_id]
		if is_instance_valid(animal):
			var animal_data = {
				"id": animal_id,
				"type": animal.get_meta("animal_type", "unknown"),
				"pos": animal.global_position,
				"rot": animal.global_rotation.y
			}
			
			# Add state if available
			if animal.has_method("get_state_string"):
				animal_data["state"] = animal.get_state_string()
			
			animals_to_sync.append(animal_data)
	
	if animals_to_sync.size() > 0:
		print("AnimalSpawner: Sending ", animals_to_sync.size(), " animals to peer ", sender_id)
		_sync_existing_animals.rpc_id(sender_id, animals_to_sync)


@rpc("authority", "call_remote", "reliable")
func _sync_existing_animals(animals_data: Array) -> void:
	"""Client receives all existing animals from host."""
	print("AnimalSpawner: Client received ", animals_data.size(), " existing animals")
	
	for data in animals_data:
		# Spawn each animal locally
		var animal_type = data.get("type", "unknown")
		var animal_id = data.get("id", -1)
		var position = data.get("pos", Vector3.ZERO)
		var rotation = data.get("rot", 0.0)
		
		if animal_type != "unknown" and animal_id != -1 and animal_scenes.has(animal_type):
			print("AnimalSpawner: Spawning synced animal: ", animal_type, " (ID: ", animal_id, ")")
			var animal_data = animal_scenes[animal_type]
			_spawn_animal_local(animal_type, animal_data, position, animal_id)
			
			# Apply rotation if animal was spawned
			if spawned_animals.has(animal_id):
				var animal = spawned_animals[animal_id]
				if is_instance_valid(animal):
					animal.rotation.y = rotation
					
					# Set state if provided
					if data.has("state") and animal.has_method("set_state_from_string"):
						animal.set_state_from_string(data.get("state"))


# --- Helper Methods ---

func _generate_animal_id() -> int:
	"""Generate a unique animal ID."""
	next_animal_id += 1
	return next_animal_id


func _get_biome_preference(animal_type: String, biome_type: BiomeManagerClass.BiomeType, animal_data: Dictionary) -> float:
	"""Get the preference value for an animal type in a specific biome."""
	if not animal_data.has("biome_preferences"):
		return 0.5
	
	var biome_preferences: Dictionary = animal_data.biome_preferences
	if biome_preferences.has(biome_type):
		return biome_preferences[biome_type]
	
	return 0.1


func _get_fallback_terrain_height(spawn_position: Vector3) -> float:
	"""Get a fallback terrain height when chunk_manager is not available."""
	var best_height: float = 5.0
	var min_distance: float = INF
	
	for player in players:
		if not is_instance_valid(player):
			continue
		
		var distance: float = Vector2(spawn_position.x, spawn_position.z).distance_to(
			Vector2(player.global_position.x, player.global_position.z)
		)
		if distance < min_distance:
			min_distance = distance
			best_height = player.global_position.y + 2.0
	
	return max(best_height, 3.0)


func _try_get_biome_manager() -> void:
	"""Try to get the biome manager from the game manager."""
	var game_managers := get_tree().get_nodes_in_group("game_manager")
	if game_managers.is_empty():
		return
	
	var game_manager = game_managers[0]
	if not game_manager.has_method("get_biome_manager"):
		return
	
	biome_manager = game_manager.get_biome_manager()
	print("AnimalSpawner: Got biome_manager: ", biome_manager)


func _try_get_chunk_manager() -> void:
	"""Try to get the chunk manager from the game manager."""
	var game_managers := get_tree().get_nodes_in_group("game_manager")
	if game_managers.size() > 0:
		var game_manager = game_managers[0]
		if "chunk_manager" in game_manager and game_manager.chunk_manager:
			chunk_manager = game_manager.chunk_manager
			return
	
	var all_nodes := get_tree().get_nodes_in_group("main")
	for node in all_nodes:
		if node.get_script() and node.get_script().get_global_name() == "ChunkManager":
			chunk_manager = node
			return


func _find_spawn_parent() -> void:
	"""Find a suitable parent node for spawning animals."""
	# IMPORTANT: Always use Main node for multiplayer compatibility
	var main_nodes = get_tree().get_nodes_in_group("main")
	if main_nodes.size() > 0:
		spawn_parent = main_nodes[0] as Node3D
		if spawn_parent:
			print("AnimalSpawner: Found spawn parent (main node): ", spawn_parent, " at path: ", spawn_parent.get_path())
			return
	
	# Fallback to current scene if no main node found
	var current_scene = get_tree().current_scene
	if current_scene and current_scene is Node3D:
		spawn_parent = current_scene as Node3D
		print("AnimalSpawner: WARNING - Using current scene as spawn parent (not ideal for multiplayer): ", spawn_parent)
		return
	
	# Last resort - use parent
	if get_parent() and get_parent() is Node3D:
		spawn_parent = get_parent() as Node3D
		print("AnimalSpawner: WARNING - Using parent node as spawn parent (not ideal for multiplayer): ", spawn_parent)


func _process(delta: float) -> void:
	"""Handle LOD updates for all animals."""
	if not enable_spawning:
		return
	
	# Update LOD for all animals
	for animal_id in spawned_animals:
		var animal = spawned_animals[animal_id]
		if is_instance_valid(animal):
			_update_animal_lod(animal, delta)
			
			# Handle position interpolation for remote animals
			if not is_host and animal.has_meta("target_position"):
				var target_pos = animal.get_meta("target_position")
				animal.global_position = animal.global_position.lerp(target_pos, 10.0 * delta)
				
				if animal.has_meta("target_rotation"):
					var target_rot = animal.get_meta("target_rotation")
					animal.rotation.y = lerp_angle(animal.rotation.y, target_rot, 10.0 * delta)


func _debug_multiplayer_state() -> void:
	"""Debug function to check multiplayer state and spawned animals."""
	print("\n=== AnimalSpawner Debug ===")
	print("Is Host: ", is_host)
	print("Peer ID: ", multiplayer.get_unique_id())
	print("Connected Peers: ", multiplayer.get_peers())
	print("Spawned Animals Count: ", spawned_animals.size())
	print("Spawn Parent: ", spawn_parent, " at path: ", spawn_parent.get_path() if spawn_parent else "None")
	
	if spawned_animals.size() > 0:
		print("First 3 animals:")
		var count = 0
		for animal_id in spawned_animals:
			if count >= 3:
				break
			var animal = spawned_animals[animal_id]
			if is_instance_valid(animal):
				print("  - ID: ", animal_id, ", Type: ", animal.get_meta("animal_type", "unknown"), 
					  ", Pos: ", animal.global_position, ", Parent: ", animal.get_parent().get_path())
			count += 1
	
	# Test RPC communication
	if is_host and multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		print("Host sending test ping to all clients...")
		_test_rpc_ping.rpc("Hello from host!")
	elif not is_host and multiplayer.has_multiplayer_peer():
		print("Client sending test ping to host...")
		_test_rpc_ping.rpc_id(1, "Hello from client " + str(multiplayer.get_unique_id()))
	
	print("=========================\n")


@rpc("any_peer", "call_remote", "reliable")
func _test_rpc_ping(message: String) -> void:
	"""Test RPC to verify communication is working."""
	var sender_id = multiplayer.get_remote_sender_id()
	print("AnimalSpawner: Received test ping from peer ", sender_id, ": ", message)


func _delayed_sync_request() -> void:
	"""Request sync after ensuring everything is initialized."""
	print("AnimalSpawner: Client performing delayed sync request...")
	
	# Wait for scene to be fully loaded
	await get_tree().create_timer(2.0).timeout
	
	# Ensure we have required components
	if not spawn_parent:
		_find_spawn_parent()
	
	if not biome_manager:
		_try_get_biome_manager()
	
	print("AnimalSpawner: Client ready, requesting existing animals...")
	_request_existing_animals()


func _input(event: InputEvent) -> void:
	"""Debug input handling."""
	if event is InputEventKey and event.pressed:
		# Press P to manually spawn a test rabbit
		if event.keycode == KEY_P:
			print("\n=== Manual Test Spawn (P key pressed) ===")
			# Update player list first
			_update_player_list()
			print("Found ", players.size(), " players")
			
			if not spawn_parent:
				print("ERROR: No spawn parent set!")
				_find_spawn_parent()
			
			if not biome_manager:
				print("WARNING: No biome manager, trying to get it...")
				_try_get_biome_manager()
			
			print("Spawn parent: ", spawn_parent, " at ", spawn_parent.get_path() if spawn_parent else "None")
			print("Is host: ", is_host)
			
			# Get a test position near first player
			var test_position = Vector3(100, 55, 110)  # Default position
			if players.size() > 0 and is_instance_valid(players[0]):
				test_position = players[0].global_position + Vector3(5, 0, 5)
			
			print("Test spawn position: ", test_position)
			
			# Force spawn a rabbit
			if animal_scenes.has("rabbit"):
				var animal_id = _generate_animal_id()
				print("Spawning test rabbit with ID: ", animal_id)
				
				var animal_data = animal_scenes["rabbit"]
				_spawn_animal_local("rabbit", animal_data, test_position, animal_id)
				
				if is_host and multiplayer.has_multiplayer_peer():
					print("Host sending spawn RPC to clients...")
					_spawn_animal_remote.rpc("rabbit", test_position, animal_id)
				
				print("Test spawn complete!")
			else:
				print("ERROR: No rabbit scene found!")
			print("==============================\n")
