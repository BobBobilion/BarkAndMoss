class_name AnimalSpawner
extends Node

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

# --- Animal Types and Biome Preferences ---
var animal_scenes: Dictionary = {
	"rabbit": {
		"scene": preload("res://scenes/Rabbit.tscn"),
		"weight": 5,
		"max_count_per_area": GameConstants.SPAWN.RABBIT_COUNT_PER_AREA,  # Max per proximity area
		"biome_preferences": {
			BiomeManagerClass.BiomeType.FOREST: 1.0,    # Loves forests
			BiomeManagerClass.BiomeType.AUTUMN: 0.8,    # Likes autumn areas
			BiomeManagerClass.BiomeType.SNOW: 0.9,      # Higher chance in snow (for white rabbits)
			BiomeManagerClass.BiomeType.MOUNTAIN: 0.1   # Very rare in mountains
		}
	},
	"bird": {
		"scene": preload("res://scenes/Bird.tscn"),
		"weight": 4,
		"max_count_per_area": GameConstants.SPAWN.BIRD_COUNT_PER_AREA,  # Max per proximity area
		"biome_preferences": {
			BiomeManagerClass.BiomeType.FOREST: 0.9,    # Common in forests
			BiomeManagerClass.BiomeType.AUTUMN: 0.7,    # Likes autumn areas
			BiomeManagerClass.BiomeType.SNOW: 0.6,      # Some cold-weather birds
			BiomeManagerClass.BiomeType.MOUNTAIN: 0.8   # Mountain birds exist
		}
	},
	"deer": {
		"scene": preload("res://scenes/Deer.tscn"),
		"weight": 3,
		"max_count_per_area": GameConstants.SPAWN.DEER_COUNT_PER_AREA,  # Max per proximity area
		"biome_preferences": {
			BiomeManagerClass.BiomeType.FOREST: 1.0,    # Loves forests
			BiomeManagerClass.BiomeType.AUTUMN: 0.9,    # Great in autumn
			BiomeManagerClass.BiomeType.SNOW: 0.4,      # Some winter deer
			BiomeManagerClass.BiomeType.MOUNTAIN: 0.2   # Rare in mountains
		}
	}
	# Future animals can be added here with biome preferences:
	# "bear": {
	#     "scene": preload("res://scenes/Bear.tscn"),
	#     "weight": 1,
	#     "max_count_per_area": 1,
	#     "biome_preferences": {
	#         BiomeManagerClass.BiomeType.FOREST: 0.8,
	#         BiomeManagerClass.BiomeType.MOUNTAIN: 0.6,
	#         BiomeManagerClass.BiomeType.SNOW: 0.3,
	#         BiomeManagerClass.BiomeType.AUTUMN: 0.7
	#     }
	# }
}

# --- Node References ---
var world_generator: WorldGenerator
var biome_manager: BiomeManagerClass
var players: Array[Node3D] = []
var spawn_parent: Node3D = null  # Parent node for spawned animals

# --- State ---
var spawn_timer: float = 0.0
var despawn_timer: float = 0.0
var current_animals: Dictionary = {}  # Track spawned animals by type
var proximity_animals: Dictionary = {}  # Track animals by player proximity: {player_id: {animal_type: [animals]}}


func _ready() -> void:
	"""Initialize the animal spawner and find required components."""
	# Add to group for cleanup purposes
	add_to_group("animal_spawner")
	
	# Try to find the biome manager and spawn parent - they might not be ready yet during _ready()
	_try_get_biome_manager()
	_find_spawn_parent()
	
	# Initialize timers
	spawn_timer = SPAWN_CHECK_INTERVAL
	despawn_timer = DESPAWN_CHECK_INTERVAL
	

func _process(delta: float) -> void:
	"""Update the spawning and despawning systems."""
	# Try to get biome manager and spawn parent if we don't have them yet
	if not biome_manager:
		_try_get_biome_manager()
		if not biome_manager:
			return  # Can't spawn without biome manager
	
	if not spawn_parent:
		_find_spawn_parent()
		if not spawn_parent:
			return  # Can't spawn without spawn parent
	
	# Always clean up invalid animals first to prevent freed instance errors
	_cleanup_invalid_animals()
	
	spawn_timer -= delta
	despawn_timer -= delta
	
	if spawn_timer <= 0.0:
		spawn_timer = SPAWN_CHECK_INTERVAL
		_update_player_list()
		_attempt_spawn_animals()
	
	if despawn_timer <= 0.0:
		despawn_timer = DESPAWN_CHECK_INTERVAL
		_check_for_despawns()


func _update_player_list() -> void:
	"""Update the list of active players for spawn calculations."""
	players.clear()
	
	# Find all human and dog players
	var human_players: Array[Node] = get_tree().get_nodes_in_group("human_player")
	var dog_players: Array[Node] = get_tree().get_nodes_in_group("dog_player")
	
	for player in human_players:
		if is_instance_valid(player):
			players.append(player as Node3D)
	
	for player in dog_players:
		if is_instance_valid(player):
			players.append(player as Node3D)


func _attempt_spawn_animals() -> void:
	"""Attempt to spawn animals using proximity-based spawning."""
	if players.is_empty():
		return
	
	# Update proximity tracking (cleanup already done in _process)
	_update_proximity_tracking()
	
	# Try to spawn animals for each player's proximity area
	for player in players:
		var player_id: int = player.get_instance_id()
		_attempt_spawn_for_player_area(player, player_id)


func _try_spawn_animal(animal_type: String, animal_data: Dictionary) -> void:
	"""Try to spawn a specific type of animal with biome preference consideration."""
	var spawn_attempt_count: int = 0
	var max_spawn_attempts: int = 10
	
	while spawn_attempt_count < max_spawn_attempts:
		spawn_attempt_count += 1
		
		var spawn_position: Vector3 = _find_valid_spawn_position(animal_type)
		if spawn_position == Vector3.ZERO:
			continue  # Try again with different position
		
		# Check biome preference for this animal type using ground-level position
		var ground_position: Vector3 = Vector3(spawn_position.x, 0, spawn_position.z)
		var biome_type: BiomeManagerClass.BiomeType = biome_manager.get_biome_at_position(ground_position)
		var biome_preference: float = _get_biome_preference(animal_type, biome_type, animal_data)
		
		# Use biome preference as spawn chance (higher preference = higher chance)
		if randf() > biome_preference:
			continue  # This biome isn't preferred, try different location
		
		# Spawn the animal
		var animal_scene: PackedScene = animal_data.scene
		var animal: Node3D = animal_scene.instantiate()
		
		# Add to the scene
		spawn_parent.add_child(animal)
		animal.global_position = spawn_position
		
		# Track the spawned animal
		if not current_animals.has(animal_type):
			current_animals[animal_type] = []
		current_animals[animal_type].append(animal)
		
		# Successfully spawned animal
		return  # Successfully spawned
	
	# Failed to find suitable biome after max attempts


func _find_valid_spawn_position(animal_type: String = "") -> Vector3:
	"""Find a valid position to spawn an animal outside player view."""
	var attempts: int = 10  # Maximum attempts to find a valid position
	
	while attempts > 0:
		attempts -= 1
		
		# Pick a random valid player as reference
		var reference_player: Node3D = null
		var valid_players: Array[Node3D] = []
		
		# Build list of valid players
		for player in players:
			if is_instance_valid(player) and not player.is_queued_for_deletion():
				valid_players.append(player)
		
		# If no valid players, return invalid position
		if valid_players.is_empty():
			return Vector3.INF
		
		reference_player = valid_players[randi() % valid_players.size()]
		
		# Generate a random position around the player
		var angle: float = randf() * TAU  # Random angle in radians
		var distance: float = randf_range(SPAWN_DISTANCE_MIN, SPAWN_DISTANCE_MAX)
		
		var spawn_position: Vector3 = reference_player.global_position + Vector3(
			cos(angle) * distance,
			0,
			sin(angle) * distance
		)
		
		# Check if position is valid (not too close to any player)
		if _is_position_valid(spawn_position):
			# Get terrain height at this position
			if world_generator and world_generator.has_method("get_terrain_height_at_position"):
				var terrain_height: float = world_generator.get_terrain_height_at_position(spawn_position)
				
				# Set appropriate height based on animal type
				if animal_type == "bird":
					# Birds spawn in the air
					spawn_position.y = terrain_height + randf_range(4.0, 8.0)  # 4-8 meters above ground
				else:
					# Ground animals spawn on terrain surface
					spawn_position.y = terrain_height + TERRAIN_HEIGHT_OFFSET
			else:
				# Fallback heights
				if animal_type == "bird":
					spawn_position.y = 6.0  # Default flight height
				else:
					spawn_position.y = 1.0  # Default ground height
			
			return spawn_position
	
	return Vector3.ZERO  # No valid position found


func _is_position_valid(position: Vector3) -> bool:
	"""Check if a spawn position is valid (not too close to players)."""
	for player in players:
		# Check if player is still valid before accessing its position
		if not is_instance_valid(player) or player.is_queued_for_deletion():
			continue
		
		if position.distance_to(player.global_position) < SPAWN_DISTANCE_MIN:
			return false
	return true


func _cleanup_invalid_animals() -> void:
	"""Remove invalid/destroyed animals from tracking."""
	# Clean up invalid players first
	_cleanup_invalid_players()
	
	for animal_type: String in current_animals.keys():
		var animal_list: Array = current_animals[animal_type]
		
		# Remove invalid animals
		for i in range(animal_list.size() - 1, -1, -1):
			var animal_ref = animal_list[i]
			if not is_instance_valid(animal_ref):
				animal_list.remove_at(i)
				continue
			
			var animal: Node3D = animal_ref as Node3D
			if not animal or animal.is_queued_for_deletion():
				animal_list.remove_at(i)
	
	# Also clean up proximity tracking
	for player_id in proximity_animals.keys():
		for animal_type: String in proximity_animals[player_id].keys():
			var proximity_list: Array = proximity_animals[player_id][animal_type]
			for i in range(proximity_list.size() - 1, -1, -1):
				var animal_ref = proximity_list[i]
				if not is_instance_valid(animal_ref):
					proximity_list.remove_at(i)
					continue
				
				var animal: Node3D = animal_ref as Node3D
				if not animal or animal.is_queued_for_deletion():
					proximity_list.remove_at(i)


func _count_total_animals() -> int:
	"""Count the total number of tracked animals."""
	var total: int = 0
	for animal_type: String in current_animals.keys():
		total += current_animals[animal_type].size()
	return total


func _count_animals_of_type(animal_type: String) -> int:
	"""Count the number of animals of a specific type."""
	if current_animals.has(animal_type):
		return current_animals[animal_type].size()
	return 0


func add_animal_type(type_name: String, scene: PackedScene, weight: int = 1, max_count_per_area: int = 3) -> void:
	"""Add a new animal type that can be spawned with proximity-based spawning."""
	animal_scenes[type_name] = {
		"scene": scene,
		"weight": weight,
		"max_count_per_area": max_count_per_area
	}


func remove_animal_type(type_name: String) -> void:
	"""Remove an animal type from spawning."""
	if animal_scenes.has(type_name):
		animal_scenes.erase(type_name)
		if current_animals.has(type_name):
			current_animals.erase(type_name)


func get_animal_counts() -> Dictionary:
	"""Get the current count of each animal type for debugging (total and per-player)."""
	var counts: Dictionary = {
		"total": {},
		"per_player": {}
	}
	
	# Get total counts
	for animal_type: String in animal_scenes.keys():
		counts.total[animal_type] = _count_animals_of_type(animal_type)
	
	# Get per-player proximity counts
	for player in players:
		var player_id: int = player.get_instance_id()
		counts.per_player[player_id] = {}
		
		if proximity_animals.has(player_id):
			for animal_type: String in animal_scenes.keys():
				if proximity_animals[player_id].has(animal_type):
					counts.per_player[player_id][animal_type] = proximity_animals[player_id][animal_type].size()
				else:
					counts.per_player[player_id][animal_type] = 0
		else:
			for animal_type: String in animal_scenes.keys():
				counts.per_player[player_id][animal_type] = 0
	
	return counts


func get_proximity_info() -> Dictionary:
	"""Get proximity-based spawning information for debugging."""
	var info: Dictionary = {
		"spawn_distances": {
			"min": SPAWN_DISTANCE_MIN,
			"max": SPAWN_DISTANCE_MAX,
			"despawn": DESPAWN_RADIUS
		},
		"limits": {
			"max_animals_per_area": MAX_ANIMALS_PER_AREA
		},
		"player_count": players.size(),
		"animals_by_player": {}
	}
	
	# Add animal counts per player
	for player in players:
		# Check if player is still valid before accessing its data
		if not is_instance_valid(player) or player.is_queued_for_deletion():
			continue
		
		var player_id: int = player.get_instance_id()
		var player_info: Dictionary = {
			"position": player.global_position,
			"animals": {},
			"total_in_area": _count_animals_in_proximity_area(player_id)
		}
		
		if proximity_animals.has(player_id):
			for animal_type: String in animal_scenes.keys():
				if proximity_animals[player_id].has(animal_type):
					player_info.animals[animal_type] = proximity_animals[player_id][animal_type].size()
				else:
					player_info.animals[animal_type] = 0
		
		info.animals_by_player[player_id] = player_info
	
	return info


func print_proximity_debug() -> void:
	"""Print proximity spawning debug information to console."""
	# Debug output disabled


func remove_animal_immediately(animal: Node3D) -> void:
	"""Immediately remove an animal from all tracking when it dies/is killed."""
	if not animal or not is_instance_valid(animal):
		return
	
	# Remove from current_animals tracking
	for animal_type: String in current_animals.keys():
		var animal_list: Array = current_animals[animal_type]
		
		# Use safe removal to avoid accessing freed instances
		for i in range(animal_list.size() - 1, -1, -1):
			var animal_ref = animal_list[i]
			if not is_instance_valid(animal_ref):
				animal_list.remove_at(i)
				continue
			
			if animal_ref == animal:
				animal_list.remove_at(i)
				break
	
	# Remove from proximity tracking
	for player_id in proximity_animals.keys():
		for animal_type: String in proximity_animals[player_id].keys():
			var proximity_list: Array = proximity_animals[player_id][animal_type]
			
			# Use safe removal to avoid accessing freed instances
			for i in range(proximity_list.size() - 1, -1, -1):
				var animal_ref = proximity_list[i]
				if not is_instance_valid(animal_ref):
					proximity_list.remove_at(i)
					continue
				
				if animal_ref == animal:
					proximity_list.remove_at(i)
					break


func _on_animal_died(animal: BaseAnimal) -> void:
	"""Handle immediate cleanup when an animal dies/is killed."""
	remove_animal_immediately(animal)


func _get_biome_preference(animal_type: String, biome_type: BiomeManagerClass.BiomeType, animal_data: Dictionary) -> float:
	"""Get the preference value for an animal type in a specific biome."""
	if not animal_data.has("biome_preferences"):
		return 0.5  # Default neutral preference if no biome data
	
	var biome_preferences: Dictionary = animal_data.biome_preferences
	if biome_preferences.has(biome_type):
		return biome_preferences[biome_type]
	
	return 0.1  # Very low preference for unspecified biomes


func _update_proximity_tracking() -> void:
	"""Update the proximity tracking for all players and animals."""
	# Clear proximity tracking
	proximity_animals.clear()
	
	# Initialize proximity tracking for each player
	for player in players:
		var player_id: int = player.get_instance_id()
		proximity_animals[player_id] = {}
		
		# Initialize animal type arrays for this player
		for animal_type: String in animal_scenes.keys():
			proximity_animals[player_id][animal_type] = []
	
	# Categorize existing animals by proximity to players
	for animal_type: String in current_animals.keys():
		var animal_list: Array = current_animals[animal_type]
		
		for animal_ref in animal_list:
			if not is_instance_valid(animal_ref):
				continue
			
			var animal: Node3D = animal_ref as Node3D
			if not animal or animal.is_queued_for_deletion():
				continue
			
			# Find the closest player within spawn distance
			var closest_player: Node3D = null
			var min_distance: float = SPAWN_DISTANCE_MAX
			
			for player in players:
				# Check if player is still valid before accessing its position
				if not is_instance_valid(player) or player.is_queued_for_deletion():
					continue
				
				var distance: float = animal.global_position.distance_to(player.global_position)
				if distance <= SPAWN_DISTANCE_MAX and distance < min_distance:
					closest_player = player
					min_distance = distance
			
			# Add animal to proximity tracking if within range
			if closest_player:
				var player_id: int = closest_player.get_instance_id()
				proximity_animals[player_id][animal_type].append(animal)


func _attempt_spawn_for_player_area(player: Node3D, player_id: int) -> void:
	"""Attempt to spawn animals in a specific player's proximity area."""
	if not proximity_animals.has(player_id):
		return
	
	var player_proximity: Dictionary = proximity_animals[player_id]
	var total_animals_in_area: int = _count_animals_in_proximity_area(player_id)
	
	# Check if we've reached the maximum animals for this area
	if total_animals_in_area >= MAX_ANIMALS_PER_AREA:
		return
	
	# Try to spawn each type of animal for this player area
	for animal_type: String in animal_scenes.keys():
		var animal_data: Dictionary = animal_scenes[animal_type]
		var current_count_in_area: int = player_proximity[animal_type].size()
		
		# Check if we need more of this animal type in this area
		if current_count_in_area < animal_data.max_count_per_area:
			_try_spawn_animal_for_player(animal_type, animal_data, player, player_id)


func _try_spawn_animal_for_player(animal_type: String, animal_data: Dictionary, player: Node3D, player_id: int) -> void:
	"""Try to spawn a specific type of animal near a specific player."""
	var spawn_attempt_count: int = 0
	var max_spawn_attempts: int = 10
	
	while spawn_attempt_count < max_spawn_attempts:
		spawn_attempt_count += 1
		
		var spawn_position: Vector3 = _find_valid_spawn_position_near_player(player, animal_type)
		if spawn_position == Vector3.ZERO:
			continue  # Try again with different position
		
		# Check biome preference for this animal type using ground-level position
		var ground_position: Vector3 = Vector3(spawn_position.x, 0, spawn_position.z)
		var biome_type: BiomeManagerClass.BiomeType = biome_manager.get_biome_at_position(ground_position)
		var biome_preference: float = _get_biome_preference(animal_type, biome_type, animal_data)
		
		# Use biome preference as spawn chance (higher preference = higher chance)
		if randf() > biome_preference:
			continue  # This biome isn't preferred, try different location
		
		# Spawn the animal
		var animal_scene: PackedScene = animal_data.scene
		var animal: Node3D = animal_scene.instantiate()
		
		# Add to the scene
		spawn_parent.add_child(animal)
		animal.global_position = spawn_position
		
		# Connect death signal for immediate cleanup
		if animal.has_signal("animal_died"):
			animal.animal_died.connect(_on_animal_died)
		
		# Track the spawned animal
		if not current_animals.has(animal_type):
			current_animals[animal_type] = []
		current_animals[animal_type].append(animal)
		
		# Add to proximity tracking
		proximity_animals[player_id][animal_type].append(animal)
		
		return  # Successfully spawned
	
	# Failed to find suitable spawn location after max attempts


func _find_valid_spawn_position_near_player(player: Node3D, animal_type: String = "") -> Vector3:
	"""Find a valid position to spawn an animal near a specific player."""
	# Check if player is valid before proceeding
	if not is_instance_valid(player) or player.is_queued_for_deletion():
		return Vector3.INF
	
	var attempts: int = 10  # Maximum attempts to find a valid position
	
	while attempts > 0:
		attempts -= 1
		
		# Generate a random position around the player
		var angle: float = randf() * TAU  # Random angle in radians
		var distance: float = randf_range(SPAWN_DISTANCE_MIN, SPAWN_DISTANCE_MAX)
		
		var spawn_position: Vector3 = player.global_position + Vector3(
			cos(angle) * distance,
			0,
			sin(angle) * distance
		)
		
		# Check if position is valid (not too close to any player)
		if _is_position_valid(spawn_position):
			# Get terrain height at this position
			if world_generator and world_generator.has_method("get_terrain_height_at_position"):
				var terrain_height: float = world_generator.get_terrain_height_at_position(spawn_position)
				
				# Set appropriate height based on animal type
				if animal_type == "bird":
					# Birds spawn in the air
					spawn_position.y = terrain_height + randf_range(4.0, 8.0)  # 4-8 meters above ground
				else:
					# Ground animals spawn on terrain surface
					spawn_position.y = terrain_height + TERRAIN_HEIGHT_OFFSET
			else:
				# Fallback heights
				if animal_type == "bird":
					spawn_position.y = 6.0  # Default flight height
				else:
					spawn_position.y = 1.0  # Default ground height
			
			return spawn_position
	
	return Vector3.ZERO  # No valid position found


func _count_animals_in_proximity_area(player_id: int) -> int:
	"""Count the total number of animals in a player's proximity area."""
	if not proximity_animals.has(player_id):
		return 0
	
	var total: int = 0
	var player_proximity: Dictionary = proximity_animals[player_id]
	
	for animal_type: String in player_proximity.keys():
		total += player_proximity[animal_type].size()
	
	return total


func _check_for_despawns() -> void:
	"""Check if any animals should be despawned based on distance from players."""
	for animal_type: String in current_animals.keys():
		var animal_list: Array = current_animals[animal_type]
		
		# Check each animal for despawn conditions
		for i in range(animal_list.size() - 1, -1, -1):
			# Safely check if the array element is valid before assignment
			var animal_ref = animal_list[i]
			if not is_instance_valid(animal_ref):
				animal_list.remove_at(i)
				continue
			
			var animal: Node3D = animal_ref as Node3D
			if not animal or animal.is_queued_for_deletion():
				animal_list.remove_at(i)
				continue
			
			# Check if animal is too far from all players
			var should_despawn: bool = true
			for player in players:
				# Check if player is still valid before accessing its position
				if not is_instance_valid(player) or player.is_queued_for_deletion():
					continue
				
				var distance: float = animal.global_position.distance_to(player.global_position)
				if distance <= DESPAWN_RADIUS:
					should_despawn = false
					break
			
			# Despawn the animal if it's too far from all players
			if should_despawn:
				animal.queue_free()
				animal_list.remove_at(i)

func _try_get_biome_manager() -> void:
	"""Try to get the biome manager from the game manager."""
	var game_managers := get_tree().get_nodes_in_group("game_manager")
	if game_managers.size() > 0:
		var game_manager = game_managers[0]
		if game_manager.has_method("get_biome_manager"):
			biome_manager = game_manager.get_biome_manager()
			if biome_manager:
				print("AnimalSpawner: Successfully found BiomeManager!")
			else:
				# Biome manager exists but returns null - chunk system not ready yet
				pass

func _find_spawn_parent() -> void:
	"""Find a suitable parent node for spawning animals."""
	# Try to find the main scene node (usually the root of the current scene)
	var current_scene = get_tree().current_scene
	if current_scene and current_scene is Node3D:
		spawn_parent = current_scene as Node3D
		print("AnimalSpawner: Using current_scene as spawn parent")
		return
	
	# Fallback: try to find a Main node
	var main_nodes = get_tree().get_nodes_in_group("main")
	if main_nodes.size() > 0:
		spawn_parent = main_nodes[0] as Node3D
		if spawn_parent:
			print("AnimalSpawner: Using Main node as spawn parent")
			return
	
	# Another fallback: use the parent of this AnimalSpawner
	if get_parent() and get_parent() is Node3D:
		spawn_parent = get_parent() as Node3D
		print("AnimalSpawner: Using parent node as spawn parent")
		return
	
	# Final fallback: use the current scene or create a fallback node
	var fallback_scene = get_tree().current_scene
	if fallback_scene and fallback_scene is Node3D:
		spawn_parent = fallback_scene as Node3D
		print("AnimalSpawner: Using current_scene as fallback spawn parent")
	else:
		# Last resort: create our own Node3D container
		spawn_parent = Node3D.new()
		spawn_parent.name = "AnimalContainer"
		get_tree().current_scene.add_child(spawn_parent)
		print("AnimalSpawner: Created new Node3D container as spawn parent")


func _cleanup_invalid_players() -> void:
	"""Remove invalid/destroyed players from tracking."""
	for i in range(players.size() - 1, -1, -1):
		if not is_instance_valid(players[i]) or players[i].is_queued_for_deletion():
			print("AnimalSpawner: Removing invalid player reference")
			players.remove_at(i)


func clear_all_tracking() -> void:
	"""Clear all animal and player tracking - used when returning to main menu."""
	print("AnimalSpawner: Clearing all tracking data...")
	
	# Clear all animal tracking
	current_animals.clear()
	proximity_animals.clear()
	
	# Clear player tracking
	players.clear()
	
	print("AnimalSpawner: All tracking data cleared") 
