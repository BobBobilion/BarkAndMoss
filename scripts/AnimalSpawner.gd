class_name AnimalSpawner
extends Node

# --- Imports ---
const BiomeManagerClass = preload("res://scripts/BiomeManager.gd")

# --- Constants ---
const SPAWN_DISTANCE_MIN: float = GameConstants.SPAWN.DISTANCE_MIN
const SPAWN_DISTANCE_MAX: float = GameConstants.SPAWN.DISTANCE_MAX
const MAX_ANIMALS: int = GameConstants.SPAWN.MAX_ANIMALS
const SPAWN_CHECK_INTERVAL: float = GameConstants.SPAWN.CHECK_INTERVAL
const TERRAIN_HEIGHT_OFFSET: float = GameConstants.SPAWN.TERRAIN_HEIGHT_OFFSET

# --- Animal Types and Biome Preferences ---
var animal_scenes: Dictionary = {
	"rabbit": {
		"scene": preload("res://scenes/Rabbit.tscn"),
		"weight": 5,
		"max_count": GameConstants.SPAWN.RABBIT_COUNT,  # Scaled with world size
		"biome_preferences": {
			BiomeManagerClass.BiomeType.FOREST: 1.0,    # Loves forests
			BiomeManagerClass.BiomeType.AUTUMN: 0.8,    # Likes autumn areas
			BiomeManagerClass.BiomeType.SNOW: 0.3,      # Rare in snow
			BiomeManagerClass.BiomeType.MOUNTAIN: 0.1   # Very rare in mountains
		}
	},
	"bird": {
		"scene": preload("res://scenes/Bird.tscn"),
		"weight": 4,
		"max_count": GameConstants.SPAWN.BIRD_COUNT,  # Scaled with world size
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
		"max_count": GameConstants.SPAWN.DEER_COUNT,  # Scaled with world size
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
	#     "max_count": 2,
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

# --- State ---
var spawn_timer: float = 0.0
var current_animals: Dictionary = {}  # Track spawned animals by type


func _ready() -> void:
	"""Initialize the animal spawner and find required components."""
	# Find the world generator for terrain height checks and biome data
	world_generator = get_node("../WorldGenerator") as WorldGenerator
	if not world_generator:
		printerr("AnimalSpawner: Could not find WorldGenerator!")
		return
	
	# Get biome manager from world generator
	biome_manager = world_generator.biome_manager
	if not biome_manager:
		printerr("AnimalSpawner: Could not find BiomeManager!")
		return
	
	# Start the spawn timer
	spawn_timer = SPAWN_CHECK_INTERVAL
	
	print("AnimalSpawner: Ready to spawn biome-aware animals")


func _process(delta: float) -> void:
	"""Update the spawning system."""
	spawn_timer -= delta
	
	if spawn_timer <= 0.0:
		spawn_timer = SPAWN_CHECK_INTERVAL
		_update_player_list()
		_attempt_spawn_animals()


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
	"""Attempt to spawn animals if conditions are met."""
	if players.is_empty():
		return
	
	# Clean up invalid animals from tracking
	_cleanup_invalid_animals()
	
	# Check if we need to spawn more animals
	var total_animals: int = _count_total_animals()
	if total_animals >= MAX_ANIMALS:
		return
	
	# Try to spawn each type of animal
	for animal_type: String in animal_scenes.keys():
		var animal_data: Dictionary = animal_scenes[animal_type]
		var current_count: int = _count_animals_of_type(animal_type)
		
		if current_count < animal_data.max_count:
			_try_spawn_animal(animal_type, animal_data)


func _try_spawn_animal(animal_type: String, animal_data: Dictionary) -> void:
	"""Try to spawn a specific type of animal with biome preference consideration."""
	var spawn_attempt_count: int = 0
	var max_spawn_attempts: int = 10
	
	while spawn_attempt_count < max_spawn_attempts:
		spawn_attempt_count += 1
		
		var spawn_position: Vector3 = _find_valid_spawn_position(animal_type)
		if spawn_position == Vector3.ZERO:
			continue  # Try again with different position
		
		# Check biome preference for this animal type
		var biome_type: BiomeManagerClass.BiomeType = biome_manager.get_biome_at_position(spawn_position)
		var biome_preference: float = _get_biome_preference(animal_type, biome_type, animal_data)
		
		# Use biome preference as spawn chance (higher preference = higher chance)
		if randf() > biome_preference:
			continue  # This biome isn't preferred, try different location
		
		# Spawn the animal
		var animal_scene: PackedScene = animal_data.scene
		var animal: Node3D = animal_scene.instantiate()
		
		# Add to the scene
		get_tree().current_scene.add_child(animal)
		animal.global_position = spawn_position
		
		# Track the spawned animal
		if not current_animals.has(animal_type):
			current_animals[animal_type] = []
		current_animals[animal_type].append(animal)
		
		print("AnimalSpawner: Spawned ", animal_type, " in ", biome_type, " biome at ", spawn_position)
		return  # Successfully spawned
	
	# Failed to find suitable biome after max attempts
	print("AnimalSpawner: Failed to find suitable biome for ", animal_type, " after ", max_spawn_attempts, " attempts")


func _find_valid_spawn_position(animal_type: String = "") -> Vector3:
	"""Find a valid position to spawn an animal outside player view."""
	var attempts: int = 10  # Maximum attempts to find a valid position
	
	while attempts > 0:
		attempts -= 1
		
		# Pick a random player as reference
		var reference_player: Node3D = players[randi() % players.size()]
		
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
		if position.distance_to(player.global_position) < SPAWN_DISTANCE_MIN:
			return false
	return true


func _cleanup_invalid_animals() -> void:
	"""Remove invalid/destroyed animals from tracking."""
	for animal_type: String in current_animals.keys():
		var animal_list: Array = current_animals[animal_type]
		
		# Remove invalid animals
		for i in range(animal_list.size() - 1, -1, -1):
			if not is_instance_valid(animal_list[i]):
				animal_list.remove_at(i)


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


func add_animal_type(type_name: String, scene: PackedScene, weight: int = 1, max_count: int = 5) -> void:
	"""Add a new animal type that can be spawned."""
	animal_scenes[type_name] = {
		"scene": scene,
		"weight": weight,
		"max_count": max_count
	}
	print("AnimalSpawner: Added animal type: ", type_name)


func remove_animal_type(type_name: String) -> void:
	"""Remove an animal type from spawning."""
	if animal_scenes.has(type_name):
		animal_scenes.erase(type_name)
		if current_animals.has(type_name):
			current_animals.erase(type_name)
		print("AnimalSpawner: Removed animal type: ", type_name)


func get_animal_counts() -> Dictionary:
	"""Get the current count of each animal type for debugging."""
	var counts: Dictionary = {}
	for animal_type: String in animal_scenes.keys():
		counts[animal_type] = _count_animals_of_type(animal_type)
	return counts


func _get_biome_preference(animal_type: String, biome_type: BiomeManagerClass.BiomeType, animal_data: Dictionary) -> float:
	"""Get the preference value for an animal type in a specific biome."""
	if not animal_data.has("biome_preferences"):
		return 0.5  # Default neutral preference if no biome data
	
	var biome_preferences: Dictionary = animal_data.biome_preferences
	if biome_preferences.has(biome_type):
		return biome_preferences[biome_type]
	
	return 0.1  # Very low preference for unspecified biomes 