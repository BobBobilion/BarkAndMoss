# GameConstants.gd
# Centralized constants for the Bark & Moss game
# This file contains all shared constants to improve maintainability and consistency

class_name GameConstants
extends RefCounted

# =============================================================================
# SCENE PATHS
# =============================================================================

const SCENES := {
	"MAIN_MENU": "res://scenes/MainMenu.tscn",
	"LOBBY": "res://scenes/Lobby.tscn",
	"MAIN_GAME": "res://scenes/Main.tscn",
	"PLAYER": "res://scenes/Player.tscn",
	"DOG": "res://scenes/Dog.tscn",
	"TREE": "res://scenes/Tree.tscn",
	"RABBIT": "res://scenes/Rabbit.tscn",
	"BIRD": "res://scenes/Bird.tscn",
	"DEER": "res://scenes/Deer.tscn",
	"RABBIT_CORPSE": "res://scenes/RabbitCorpse.tscn",
	"BIRD_CORPSE": "res://scenes/BirdCorpse.tscn",
	"DEER_CORPSE": "res://scenes/DeerCorpse.tscn",
	"ARROW": "res://scenes/Arrow.tscn"
}

# =============================================================================
# NETWORK SETTINGS
# =============================================================================

const NETWORK := {
	"DEFAULT_PORT": 8080,
	"MAX_PLAYERS": 2,
	"SERVER_ID": 1,
	"TICK_RATE": 30,
	"CONNECTION_TIMEOUT": 10.0
}

# =============================================================================
# PLAYER CONSTANTS
# =============================================================================

const PLAYER := {
	"WALK_SPEED": 3.0,
	"RUN_SPEED": 6.0,
	"JUMP_VELOCITY": 4.5,
	"MOUSE_SENSITIVITY": 0.002,
	"CAMERA_PITCH_MIN": -1.5,
	"CAMERA_PITCH_MAX": 1.5,
	"CAMERA_COLLISION_BIAS": 0.2,
	"BASE_CAMERA_DISTANCE": 3.0,
	"MAX_CAMERA_DISTANCE": 8.0
}

# =============================================================================
# DOG CONSTANTS
# =============================================================================

const DOG := {
	"RUN_SPEED": 8.0,
	"JUMP_VELOCITY": 5.0,
	"BITE_RANGE": 2.0,
	"BITE_HITBOX_SIZE": 1.5,
	"BITE_COOLDOWN": 0.5,
	"BARK_COOLDOWN": 1.0,
	"BARK_RANGE": 10.0
}

# =============================================================================
# WEAPON CONSTANTS
# =============================================================================

const BOW := {
	"CHARGE_TIME": 2.0,
	"MIN_POWER": 0.3,
	"MAX_POWER": 1.0,
	"ZOOM_FOV": 45.0,
	"NORMAL_FOV": 90.0,
	"ZOOM_SPEED": 5.0
}

const ARROW := {
	"SPEED": 20.0,
	"LIFETIME": 10.0,
	"DAMAGE": 100.0,
	"GRAVITY_SCALE": 0.5
}

# =============================================================================
# ANIMAL CONSTANTS
# =============================================================================

const RABBIT := {
	"WANDER_SPEED": 2.0,
	"FLEE_SPEED": 4.0,
	"WANDER_RADIUS": 10.0,
	"FLEE_DISTANCE": 8.0,
	"DIRECTION_CHANGE_TIME": 3.0,
	"FLEE_DETECTION_RANGE": 6.0,
	"MAX_HEALTH": 1.0
}

const BIRD := {
	"FLY_SPEED": 3.0,
	"FLEE_SPEED": 6.0,
	"HOVER_HEIGHT": 4.0,
	"PATROL_RADIUS": 15.0,
	"FLEE_DISTANCE": 12.0,
	"DIRECTION_CHANGE_TIME": 4.0,
	"BARK_DETECTION_RANGE": 10.0,
	"HEIGHT_VARIANCE": 2.0,
	"MAX_HEALTH": 1.0
}

const DEER := {
	"WALK_SPEED": 2.5,
	"RUN_SPEED": 7.0,
	"GRAZE_RADIUS": 8.0,
	"FLEE_DISTANCE": 15.0,
	"DETECTION_RANGE": 12.0,
	"DIRECTION_CHANGE_TIME": 5.0,
	"MAX_HEALTH": 2.0
}

# =============================================================================
# WORLD SCALING SYSTEM
# =============================================================================

# Master scale multiplier for the entire game world
# 
# HOW TO USE:
# Change WORLD_SCALE_MULTIPLIER to adjust the entire game size:
# - 1.0  = Small world (100×100, 50 trees, 8 animals)
# - 5.0  = Medium world (500×500, 1,250 trees, 40 animals) 
# - 10.0 = Large world (1000×1000, 5,000 trees, 80 animals)
# - 20.0 = Huge world (2000×2000, 20,000 trees, 160 animals)
#
# SCALING BEHAVIOR:
# - World Size: Linear scaling (multiplier × base size)
# - Trees & Rocks: Area scaling (multiplier² × base count)
# - Animals: Linear scaling (multiplier × base count)
# - Clouds: Linear scaling (multiplier × base count)
# - Spawn distances: Automatically adjusted
#
# Use GameConstants.print_world_info() to see current values
const WORLD_SCALE_MULTIPLIER: float = 5.0

# =============================================================================
# WORLD GENERATION
# =============================================================================

const WORLD := {
	"TERRAIN_RESOLUTION": 256,  # Increased for larger world
	"HILL_HEIGHT": 8.0,
	"HILL_FREQUENCY": 0.02,
	"BASE_WORLD_SIZE": Vector2(100, 100),  # Original world size
	"WORLD_SIZE": Vector2(100, 100) * WORLD_SCALE_MULTIPLIER,  # Scaled world size
	"TREE_SPACING": 5.0,  # Increased spacing for larger world
	"BASE_TREE_COUNT": 50,  # Original tree count
	"TREE_COUNT": int(50 * WORLD_SCALE_MULTIPLIER * WORLD_SCALE_MULTIPLIER),  # Scaled by area (multiplier squared)
	"BASE_ROCK_COUNT": 20,  # Base rock count for original world
	"ROCK_COUNT": int(20 * WORLD_SCALE_MULTIPLIER * WORLD_SCALE_MULTIPLIER),  # Scaled by area
	"BASE_CLOUD_COUNT": 25,  # Base cloud count (increased for better sky coverage)
	"CLOUD_COUNT": int(25 * WORLD_SCALE_MULTIPLIER)  # Clouds scale linearly, not by area
}

# =============================================================================
# SPAWNING SYSTEM
# =============================================================================

const SPAWN := {
	# Proximity-based spawning distances
	"DISTANCE_MIN": 20.0,  # Minimum distance from player to spawn animals
	"DISTANCE_MAX": 60.0,  # Maximum distance from player to spawn animals  
	"DESPAWN_RADIUS": 72.0,  # 120% of max distance - animals despawn beyond this
	
	# Animal limits per proximity area (around each player)
	"MAX_ANIMALS_PER_AREA": 12,  # Maximum animals within proximity area per player
	"BASE_MAX_ANIMALS": 8,  # Original animal count (legacy)
	"MAX_ANIMALS": int(8 * WORLD_SCALE_MULTIPLIER),  # Scaled animal count (legacy)
	
	# Spawn timing and checks
	"CHECK_INTERVAL": 3.0,  # How often to check for spawning (reduced for better responsiveness)
	"DESPAWN_CHECK_INTERVAL": 2.0,  # How often to check for despawning
	
	# World positioning
	"TERRAIN_HEIGHT_OFFSET": 1.0,
	"PLAYER_SPAWN_OFFSET": 2.0,
	"SPAWN_HEIGHT_CLEARANCE": 5.0,
	
	# Individual animal type counts per proximity area
	"RABBIT_COUNT_PER_AREA": 4,  # Max rabbits per player proximity area
	"BIRD_COUNT_PER_AREA": 4,    # Max birds per player proximity area
	"DEER_COUNT_PER_AREA": 3,    # Max deer per player proximity area
	
	# Legacy individual animal type counts (scaled globally)
	"RABBIT_COUNT": int(3 * WORLD_SCALE_MULTIPLIER),
	"BIRD_COUNT": int(3 * WORLD_SCALE_MULTIPLIER),
	"DEER_COUNT": int(2 * WORLD_SCALE_MULTIPLIER)
}

# =============================================================================
# CAMPFIRE SYSTEM
# =============================================================================

const CAMPFIRE := {
	"COOK_TIME": 10.0,
	"RAW_MEAT_HUNGER_RESTORE": 60.0,
	"BASE_LIGHT_RANGE": 8.0,
	"MAX_LIGHT_ENERGY": 1.5,
	"MIN_LIGHT_ENERGY": 0.3,
	"MAX_CHOPS": 3
}

# =============================================================================
# UI CONSTANTS
# =============================================================================

const UI := {
	"HOTBAR_SLOT_COUNT": 5,
	"INVENTORY_GRID_COLUMNS": 3,
	"INVENTORY_GRID_ROWS": 4,
	"SLOT_SIZE": Vector2(64, 64),
	"ANIMATION_BLEND_TIME": 0.2
}

# =============================================================================
# PHYSICS LAYERS (for consistency)
# =============================================================================

const PHYSICS_LAYERS := {
	"TERRAIN": 1,           # Ground, terrain mesh
	"ENVIRONMENT": 2,       # Trees, rocks, players - solid objects
	"INTERACTABLE": 4,      # Interaction areas, arrows
	"ANIMAL": 8,            # Living animals
	"CORPSE": 16            # Dead animal corpses
}

# Common collision masks for easy reference
const COLLISION_MASKS := {
	"PLAYER": 3,            # Terrain (1) + Environment (2) = 3
	"ANIMAL": 11,           # Terrain (1) + Environment (2) + Animals (8) = 11
	"ANIMAL_DETECTION": 2,  # Detect players/environment objects
	"AXE_HITBOX": 10,       # Environment (2) + Animals (8) = 10
	"ARROW": 9,             # Terrain (1) + Animals (8) = 9
	"TERRAIN_ONLY": 1       # Just terrain
}

# =============================================================================
# GAME ROLES
# =============================================================================

const ROLES := {
	"HUMAN": "human",
	"DOG": "dog",
	"UNASSIGNED": "unassigned"
}

# =============================================================================
# ITEM NAMES (for consistency)
# =============================================================================

const ITEMS := {
	"HATCHET": "Hatchet",
	"BOW": "Bow",
	"WOOD": "Wood",
	"SINEW": "Sinew",
	"RAW_MEAT": "Raw Meat",
	"COOKED_MEAT": "Cooked Meat",
	"EMPTY_SLOT": ""
}

# =============================================================================
# ANIMATION NAMES
# =============================================================================

const ANIMATIONS := {
	"PLAYER": {
		"IDLE": "CharacterArmature|Idle_Neutral",
		"WALK": "CharacterArmature|Walk",
		"RUN": "CharacterArmature|Run",
		"JUMP": "CharacterArmature|Roll",
		"CHOP": "CharacterArmature|Sword_Slash",
		"INTERACT": "CharacterArmature|Interact",
		"HIT_RECEIVE": "CharacterArmature|HitRecieve",
		"DEATH": "CharacterArmature|Death"
	},
	"DOG": {
		"IDLE": "DogArmature|Idle",
		"WALK": "DogArmature|Walk",
		"GALLOP": "DogArmature|Gallop",
		"JUMP": "DogArmature|Gallop_Jump",
		"ATTACK": "DogArmature|Attack",
		"EATING": "DogArmature|Eating",
		"DEATH": "DogArmature|Death"
	}
}

# =============================================================================
# THEME COLORS (for UI consistency)
# =============================================================================

const COLORS := {
	"BACKGROUND_DARK": Color(0.137, 0.2, 0.165, 0.85),
	"BUTTON_FONT": Color(0.3, 0.4, 0.35, 1),
	"BUTTON_FONT_HOVER": Color(0.137, 0.2, 0.165, 1),
	"BUTTON_FONT_PRESSED": Color(0.545, 0.357, 0.169, 1),
	"LIGHT_CREAM": Color(0.918, 0.878, 0.835, 1),
	"RUSTIC_BROWN": Color(0.545, 0.357, 0.169, 1),
	"SLOT_NORMAL": Color(0.8, 0.75, 0.7, 0.9),
	"SLOT_SELECTED": Color(0.98, 0.94, 0.89, 1),
	"TEXT_SHADOW": Color(0.137, 0.2, 0.165, 1)
}

# =============================================================================
# WORLD SCALING UTILITIES
# =============================================================================

## Get the current world scale multiplier for debugging/display
static func get_world_scale() -> float:
	return WORLD_SCALE_MULTIPLIER

## Get scaled world information for debugging
static func get_world_info() -> Dictionary:
	return {
		"scale_multiplier": WORLD_SCALE_MULTIPLIER,
		"world_size": WORLD.WORLD_SIZE,
		"tree_count": WORLD.TREE_COUNT,
		"rock_count": WORLD.ROCK_COUNT,
		"cloud_count": WORLD.CLOUD_COUNT,
		"max_animals": SPAWN.MAX_ANIMALS,
		"animal_breakdown": {
			"rabbits": SPAWN.RABBIT_COUNT,
			"birds": SPAWN.BIRD_COUNT,
			"deer": SPAWN.DEER_COUNT
		}
	}

## Print world scaling information to console
static func print_world_info() -> void:
	var info = get_world_info()
	print("=== WORLD SCALE INFO ===")
	print("Scale Multiplier: ", info.scale_multiplier, "x")
	print("World Size: ", info.world_size)
	print("Trees: ", info.tree_count)
	print("Rocks: ", info.rock_count) 
	print("Clouds: ", info.cloud_count)
	print("Max Animals: ", info.max_animals)
	print("  - Rabbits: ", info.animal_breakdown.rabbits)
	print("  - Birds: ", info.animal_breakdown.birds)
	print("  - Deer: ", info.animal_breakdown.deer)
	print("========================")

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

## Gets a nested dictionary value safely with a default fallback
static func get_nested_value(dict: Dictionary, keys: Array, default_value = null):
	var current = dict
	for key in keys:
		if current.has(key):
			current = current[key]
		else:
			return default_value
	return current

## Validates if a scene path exists and can be loaded
static func validate_scene_path(scene_path: String) -> bool:
	return ResourceLoader.exists(scene_path)

## Gets the appropriate animation name with fallback
static func get_animation_name(character_type: String, animation_name: String) -> String:
	var anims = get_nested_value(ANIMATIONS, [character_type.to_upper()], {})
	return anims.get(animation_name.to_upper(), "") 