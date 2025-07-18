# GameConstants.gd - Centralized game constants for Bark & Moss
#
# This file contains all the important constants used throughout the game.
# Modify values here to adjust game balance, spawning, networking, etc.

class_name GameConstants

# =============================================================================
# NETWORKING CONSTANTS
# =============================================================================

# NETWORK SETTINGS
const DEFAULT_PORT: int = 8000
const MAX_CLIENTS: int = 4

const PLAYER_SPAWN_DISTANCE: float = 10.0  # Distance players spawn from origin
const SYNC_INTERVAL: float = 1.0 / 30.0    # 30 times per second

# Protocol constants
const CONNECTION_TIMEOUT: float = 10.0
const HEARTBEAT_INTERVAL: float = 2.0

# Backward compatibility: NETWORK dictionary
const NETWORK := {
	"DEFAULT_PORT": DEFAULT_PORT,
	"MAX_PLAYERS": MAX_CLIENTS,
	"SERVER_ID": 1,
	"TICK_RATE": 30,
	"CONNECTION_TIMEOUT": CONNECTION_TIMEOUT
}

# =============================================================================
# ANIMAL AI CONSTANTS
# =============================================================================

# Shared constants for all animals
const ANIMAL_AI := {
	"DETECTION_RADIUS": 15.0,
	"FLEE_DISTANCE": 20.0,
	"SAFE_DISTANCE": 30.0,
	"WANDER_RADIUS": 25.0,
	"STATE_CHANGE_COOLDOWN": 2.0,
	"STUCK_THRESHOLD": 0.5,     # How long to be stuck before trying a new direction
	"STUCK_CHECK_INTERVAL": 1.0, # How often to check if stuck
	"DIRECTION_CHANGE_INTERVAL": 3.0, # How often to change direction while wandering
	"OBSTACLE_AVOIDANCE_RANGE": 3.0,  # Distance to check for obstacles ahead
	"AVOIDANCE_TURN_ANGLE": 45.0,     # Degrees to turn when avoiding obstacles
}

# Specific animal stats
const RABBIT := {
	"HEALTH": 25,
	"SPEED": 3.5,
	"ACCELERATION": 12.0,
	"JUMP_STRENGTH": 4.0,
	"SIZE_SCALE": Vector3(0.8, 0.8, 0.8)
}

const DEER := {
	"HEALTH": 75,
	"SPEED": 4.0,
	"ACCELERATION": 8.0,
	"JUMP_STRENGTH": 6.0,
	"SIZE_SCALE": Vector3(1.2, 1.2, 1.2)
}

const BIRD := {
	"HEALTH": 15,
	"SPEED": 5.0,
	"ACCELERATION": 15.0,
	"FLY_HEIGHT_MIN": 3.0,
	"FLY_HEIGHT_MAX": 8.0,
	"SIZE_SCALE": Vector3(0.6, 0.6, 0.6)
}

const DOG := {
	"HEALTH": 100,
	"SPEED": 5.0,
	"ACCELERATION": 10.0,
	"JUMP_STRENGTH": 5.0,
	"STAMINA": 100.0,
	"ENERGY_DRAIN": 20.0,      # Energy drained per second while sprinting
	"ENERGY_REGEN": 15.0,      # Energy regenerated per second while not sprinting
	"SIZE_SCALE": Vector3(1.0, 1.0, 1.0)
}

# =============================================================================
# PLAYER CONSTANTS
# =============================================================================

const PLAYER := {
	"HEALTH": 100,
	"SPEED": 5.0,
	"JUMP_VELOCITY": 4.5,
	"INTERACTION_DISTANCE": 5.0,
	"STAMINA": 100.0,
	"ENERGY_DRAIN": 25.0,      # Energy drained per second while sprinting
	"ENERGY_REGEN": 20.0,      # Energy regenerated per second while not sprinting
}

# =============================================================================
# CRAFTING CONSTANTS
# =============================================================================

const CRAFTING := {
	"AXE_DURABILITY": 100,
	"BOW_DURABILITY": 80,
	"ARROW_DAMAGE": 35,
	"AXE_DAMAGE": 25,
	"TREE_CHOP_TIME": 3.0,       # Seconds to chop down a tree
	"TREE_HEALTH": 3,            # Number of hits to chop down a tree
	"CAMPFIRE_COOK_TIME": 10.0,  # Seconds to cook an item
}

# Crafting recipes - centralized for consistency
const CRAFTING_RECIPES := {
	"Bow": {
		"name": "Bow",
		"description": "A simple hunting bow for ranged combat",
		"materials": {
			"Wood": 3,
			"Hide": 1,
			"Sinew": 1
		},
		"icon": "res://assets/ui/icons/bow.png"
	},
	# Future recipes can be added here:
	# "Arrow": {
	# 	"name": "Arrow",
	# 	"description": "Ammunition for the bow",
	# 	"materials": {
	# 		"Wood": 1,
	# 		"Stone": 1
	# 	},
	# 	"icon": "res://assets/ui/icons/arrow.png"
	# },
	# "Spear": {
	# 	"name": "Spear",
	# 	"description": "A long-range melee weapon",
	# 	"materials": {
	# 		"Wood": 2,
	# 		"Stone": 1,
	# 		"Sinew": 1
	# 	},
	# 	"icon": "res://assets/ui/icons/spear.png"
	# }
}

# Cooking recipes - what can be cooked at campfire
const COOKING_RECIPES := {
	"Raw Meat": {
		"name": "Cooked Meat",
		"description": "A hearty meal that restores hunger",
		"cook_time": 10.0,
		"hunger_restore": 60.0,
		"icon": "res://assets/ui/icons/cooked_meat.png"
	}
	# Future cooking recipes:
	# "Raw Fish": {
	# 	"name": "Cooked Fish",
	# 	"description": "Grilled fish, light but nutritious",
	# 	"cook_time": 8.0,
	# 	"hunger_restore": 40.0,
	# 	"icon": "res://assets/ui/icons/cooked_fish.png"
	# }
}

# =============================================================================
# WORLD SCALING SYSTEM
# =============================================================================

# Fixed scale multiplier for the infinite world
# 
# This affects:
# - Tree & Rock counts per chunk
# - Animal spawn counts
# - Cloud spawn radius
# - Other scaling parameters
#
# Set to 5.0 for a good balance of density and performance

const WORLD_SCALE_MULTIPLIER: float = 5.0

# =============================================================================
# WORLD GENERATION (Dynamic)
# =============================================================================

# Function to get current world constants based on fixed multiplier
static func get_world_constants() -> Dictionary:
	return {
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
		"CLOUD_COUNT": int(25 * WORLD_SCALE_MULTIPLIER),  # Clouds scale linearly, not by area
		# Tree and Rock size constants
		"TREE_BASE_SCALE": 3.0,  # Base scale multiplier for all trees
		"TREE_MIN_SCALE": 0.8,   # Minimum random scale variation (3.0 * 0.8 = 2.4x final)
		"TREE_MAX_SCALE": 1.5,   # Maximum random scale variation (3.0 * 1.5 = 4.5x final)
		"ROCK_MIN_SCALE": 1.0,   # Minimum rock scale (small pebbles)
		"ROCK_MAX_SCALE": 20.0   # Maximum rock scale (massive boulders!)
	}

# Backward compatibility: Static WORLD constant
static var WORLD: Dictionary:
	get:
		return get_world_constants()

# Function to get world scale multiplier (for backward compatibility)
static func get_world_scale_multiplier() -> float:
	"""Get the world scale multiplier."""
	return WORLD_SCALE_MULTIPLIER

# =============================================================================
# SPAWNING SYSTEM
# =============================================================================

const SPAWNING := {
	"MAX_RESPAWN_ATTEMPTS": 50,
	"MIN_SPAWN_DISTANCE_FROM_PLAYER": 20.0,
	"MAX_SPAWN_DISTANCE_FROM_PLAYER": 80.0,
	"SPAWN_HEIGHT_OFFSET": 1.0,
	"SAFE_SPAWN_RADIUS": 5.0,      # Area around spawn point that must be clear
}

# Backward compatibility: SPAWN dictionary for AnimalSpawner
const SPAWN := {
	"DISTANCE_MIN": 20.0,
	"DISTANCE_MAX": 60.0,
	"DESPAWN_RADIUS": 72.0,
	"MAX_ANIMALS_PER_AREA": 12,
	"CHECK_INTERVAL": 3.0,
	"DESPAWN_CHECK_INTERVAL": 2.0,
	"TERRAIN_HEIGHT_OFFSET": 1.0,
	"RABBIT_COUNT_PER_AREA": 4,
	"BIRD_COUNT_PER_AREA": 4,
	"DEER_COUNT_PER_AREA": 3
}

# Animal spawn counts that scale with world size
static func get_animal_spawn_counts() -> Dictionary:
	return {
		"BASE_RABBIT_COUNT": 8,
		"RABBIT_COUNT": int(8 * WORLD_SCALE_MULTIPLIER),  # Rabbits scale linearly with world size
		"BASE_DEER_COUNT": 4,
		"DEER_COUNT": int(4 * WORLD_SCALE_MULTIPLIER),    # Deer scale linearly with world size
		"BASE_BIRD_COUNT": 6,
		"BIRD_COUNT": int(6 * WORLD_SCALE_MULTIPLIER),    # Birds scale linearly with world size
		"TOTAL_ANIMALS": int((8 + 4 + 6) * WORLD_SCALE_MULTIPLIER)
	}

# Backward compatibility
static var ANIMALS: Dictionary:
	get:
		return get_animal_spawn_counts()

# =============================================================================
# BIOME SYSTEM
# =============================================================================

const BIOMES := {
	"FOREST_THRESHOLD": 0.3,    # Noise value above which forest spawns
	"MEADOW_THRESHOLD": -0.2,   # Noise value below which meadows spawn
	"HILL_THRESHOLD": 0.6,      # Noise value above which hills spawn
	"WATER_THRESHOLD": -0.5,    # Noise value below which water spawns (if implemented)
	
	"TREE_DENSITY_FOREST": 0.8,     # Chance of tree in forest areas
	"TREE_DENSITY_MEADOW": 0.1,     # Chance of tree in meadow areas
	"ROCK_DENSITY_HILLS": 0.6,      # Chance of rock in hilly areas
	"GRASS_DENSITY_MEADOW": 0.9,    # Chance of grass in meadow areas
}

# =============================================================================
# UI CONSTANTS
# =============================================================================

const UI := {
	"HOTBAR_SLOT_COUNT": 5,
	"INVENTORY_GRID_COLUMNS": 3,
	"INVENTORY_GRID_ROWS": 4,
	"SLOT_SIZE": Vector2(64, 64),
	"ANIMATION_BLEND_TIME": 0.2,
	
	# Shared UI Styling Constants - Rustic Bark & Moss Theme
	"SLOT_ICON_SIZE": 48,
	"SLOT_SPACING": Vector2(8, 8),
	"COLOR_SLOT_NORMAL": Color(0.8, 0.75, 0.7, 0.9),
	"COLOR_SLOT_SELECTED": Color(0.98, 0.94, 0.89, 1),
	"COLOR_SLOT_BORDER": Color(0.545, 0.357, 0.169, 1),
	"COLOR_BACKGROUND": Color(0.137, 0.2, 0.165, 0.85),
	"COLOR_TEXT": Color(0.918, 0.878, 0.835, 1),
	"COLOR_TEXT_SHADOW": Color(0.137, 0.2, 0.165, 1),
	"COLOR_SLOT_NUMBER": Color(0.918, 0.878, 0.835, 1),
	"FONT_SIZE_TOOLTIP": 14,
	"FONT_SIZE_SLOT_NUMBER": 12
}

# =============================================================================
# RENDER DISTANCE CONSTANTS
# =============================================================================

# Render distance presets for chunk loading
const RENDER_DISTANCE := {
	"MIN": 2,          # Minimum allowed render distance (2 chunks)
	"MAX": 8,          # Maximum allowed render distance (8 chunks)
	"DEFAULT": 3,      # Default render distance (original value)
	"UNLOAD_OFFSET": 1 # How many chunks beyond load distance to unload
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
	"AXE": "Axe",
	"BOW": "Bow",
	"WOOD": "Wood",
	"SINEW": "Sinew",
	"RAW_MEAT": "Raw Meat",
	"COOKED_MEAT": "Cooked Meat",
	"HIDE": "Hide",
	"EMPTY_SLOT": ""
}

# =============================================================================
# ITEM SYSTEM
# =============================================================================

const ITEM_ICONS := {
	"Axe": "res://assets/ui/icons/axe.png",
	"Bow": "res://assets/ui/icons/bow.png",
	"Wood": "res://assets/ui/icons/wood.png",
	"Sinew": "res://assets/ui/icons/sinew.png",
	"Raw Meat": "res://assets/ui/icons/raw_meat.png",
	"Cooked Meat": "res://assets/ui/icons/cooked_meat.png",
	"Hide": "res://assets/ui/icons/hide.png",
	"Arrow": "res://assets/ui/icons/arrow.png"
}

const ITEM_DESCRIPTIONS := {
	"Axe": "A trusty wooden axe. Perfect for chopping trees and clearing a path.",
	"Bow": "A simple but effective hunting bow. Great for taking down prey from a distance.",
	"Wood": "Freshly cut timber. Useful for crafting and building.",
	"Sinew": "Tough animal tendon. Essential for crafting more advanced tools.",
	"Raw Meat": "A bit too chewy to eat. If only I had a way to cook it...",
	"Cooked Meat": "A hearty meal that'll keep me going. Restores hunger when consumed.",
	"Hide": "Tough animal hide from a deer. Essential material for crafting leather goods and armor.",
	"Arrow": "Sharp projectile for the bow. Handle with care."
}

# Icon generation colors (fallback for when image files don't exist)
const ITEM_FALLBACK_COLORS := {
	"Axe": Color(0.6, 0.4, 0.2),          # Brown wooden handle  
	"Bow": Color(0.4, 0.25, 0.1),         # Dark brown wood
	"Wood": Color(0.8, 0.6, 0.3),         # Light brown timber
	"Sinew": Color(0.9, 0.9, 0.8),        # Off-white tendon
	"Raw Meat": Color(0.8, 0.3, 0.3),     # Red raw meat
	"Cooked Meat": Color(0.5, 0.3, 0.1),  # Dark brown cooked
	"Hide": Color(0.7, 0.5, 0.3),         # Tan/brown leather hide
	"Arrow": Color(0.7, 0.7, 0.7)         # Gray metal/wood
}

# =============================================================================
# ITEM ICON MANAGER (Singleton-like functionality)
# =============================================================================

class ItemIconManager:
	static var _icon_cache: Dictionary = {}
	static var _fallback_icon_size: int = 64
	
	static func get_item_icon(item_name: String) -> Texture2D:
		"""Gets an icon for the specified item, using cache when possible."""
		# Check cache first
		if _icon_cache.has(item_name):
			return _icon_cache[item_name]
		
		var icon_texture: Texture2D = null
		
		# Try to load from file first
		if ITEM_ICONS.has(item_name):
			var icon_path: String = ITEM_ICONS[item_name]
			if ResourceLoader.exists(icon_path):
				icon_texture = load(icon_path)
				print("ItemIconManager: Loaded icon from file: ", icon_path)
		
		# Fall back to procedural generation if file doesn't exist
		if not icon_texture:
			icon_texture = _generate_fallback_icon(item_name)
			print("ItemIconManager: Generated fallback icon for: ", item_name)
		
		# Cache the result
		_icon_cache[item_name] = icon_texture
		return icon_texture
	
	static func _generate_fallback_icon(item_name: String) -> ImageTexture:
		"""Generates a simple procedural icon as fallback."""
		var image = Image.create(_fallback_icon_size, _fallback_icon_size, false, Image.FORMAT_RGBA8)
		var base_color = ITEM_FALLBACK_COLORS.get(item_name, Color.GRAY)
		
		# Fill with transparent background
		image.fill(Color.TRANSPARENT)
		
		# Create a simple rounded rectangle with the item color
		var margin = 8
		var corner_radius = 6
		
		for x in range(margin, _fallback_icon_size - margin):
			for y in range(margin, _fallback_icon_size - margin):
				# Simple rounded corners by checking distance from corners
				var in_corner_area = false
				
				# Top-left corner
				if x < margin + corner_radius and y < margin + corner_radius:
					var dist = Vector2(x - (margin + corner_radius), y - (margin + corner_radius)).length()
					in_corner_area = dist > corner_radius
				# Top-right corner  
				elif x > _fallback_icon_size - margin - corner_radius and y < margin + corner_radius:
					var dist = Vector2(x - (_fallback_icon_size - margin - corner_radius), y - (margin + corner_radius)).length()
					in_corner_area = dist > corner_radius
				# Bottom-left corner
				elif x < margin + corner_radius and y > _fallback_icon_size - margin - corner_radius:
					var dist = Vector2(x - (margin + corner_radius), y - (_fallback_icon_size - margin - corner_radius)).length()
					in_corner_area = dist > corner_radius
				# Bottom-right corner
				elif x > _fallback_icon_size - margin - corner_radius and y > _fallback_icon_size - margin - corner_radius:
					var dist = Vector2(x - (_fallback_icon_size - margin - corner_radius), y - (_fallback_icon_size - margin - corner_radius)).length()
					in_corner_area = dist > corner_radius
				
				if not in_corner_area:
					# Add some variation based on item type
					var color_variation = base_color
					match item_name:
						"Axe":
							# Add wood grain effect
							if (x + y) % 4 == 0:
								color_variation = base_color.darkened(0.1)
						"Bow":
							# Add curved line effect
							if abs(x - _fallback_icon_size / 2) < 3:
								color_variation = base_color.darkened(0.2)
						"Wood":
							# Add grain lines
							if x % 6 == 0:
								color_variation = base_color.darkened(0.15)
						"Raw Meat", "Cooked Meat":
							# Add marbling effect
							if (x * y) % 7 == 0:
								color_variation = base_color.lightened(0.1)
						"Hide":
							# Add leather texture pattern
							if (x % 5 == 0 and y % 3 == 0) or (x % 3 == 0 and y % 5 == 0):
								color_variation = base_color.darkened(0.12)
					
					image.set_pixel(x, y, color_variation)
		
		var texture = ImageTexture.new()
		texture.set_image(image)
		return texture
	
	static func clear_cache() -> void:
		"""Clears the icon cache (useful for hot-reloading icons)."""
		_icon_cache.clear()
		print("ItemIconManager: Cache cleared")

# =============================================================================
# ANIMATION NAMES
# =============================================================================

const ANIMATIONS := {
	"IDLE": "idle",
	"WALK": "walking",
	"RUN": "running",
	"JUMP": "jumping",
	"PUNCH_LEFT": "punch_left",
	"PUNCH_RIGHT": "punch_right",
	"CHOP": "chopping",
	"BOW_IDLE": "bow_idle",
	"BOW_DRAW": "bow_draw",
	"BOW_HOLD": "bow_hold",
	"BOW_RELEASE": "bow_release"
}

# =============================================================================
# DEBUG AND UTILITY FUNCTIONS
# =============================================================================

# Print current world information (useful for debugging)
static func print_world_info() -> void:
	"""Print detailed information about current world scaling."""
	var world_info = get_world_constants()
	var animal_info = get_animal_spawn_counts()
	
	print("=== CURRENT WORLD SETTINGS ===")
	print("Scale Multiplier: ", WORLD_SCALE_MULTIPLIER, "x")
	print("World Size: ", world_info.WORLD_SIZE)
	print("Trees: ", world_info.TREE_COUNT, " (", world_info.BASE_TREE_COUNT, " base)")
	print("Rocks: ", world_info.ROCK_COUNT, " (", world_info.BASE_ROCK_COUNT, " base)")  
	print("Clouds: ", world_info.CLOUD_COUNT, " (", world_info.BASE_CLOUD_COUNT, " base)")
	print("Animals: ", animal_info.TOTAL_ANIMALS, " total")
	print("  - Rabbits: ", animal_info.RABBIT_COUNT)
	print("  - Deer: ", animal_info.DEER_COUNT)
	print("  - Birds: ", animal_info.BIRD_COUNT)
	print("===============================")

# Initialize the world scale multiplier from settings on startup
static func _static_init() -> void:
	"""Initialize static variables on startup."""
	# Try to load world scale multiplier from settings
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	
	if err == OK:
		# The world_scale_multiplier is now a constant, so this will not change it.
		# It's kept here for backward compatibility if settings are loaded.
		pass
	
	print("GameConstants: Initialized with world scale multiplier: ", WORLD_SCALE_MULTIPLIER, "x")


# =============================================================================
# SHARED SETTINGS MANAGEMENT SYSTEM
# =============================================================================

class SettingsManager:
	"""Shared settings management for consistent behavior across menus."""
	
	static func load_settings() -> Dictionary:
		"""Load all settings from config file."""
		var config = ConfigFile.new()
		var err = config.load("user://settings.cfg")
		
		var settings = {
			"master_volume": 75.0,
			"music_volume": 75.0,
			"sfx_volume": 75.0,
			"fullscreen": false,
			"render_distance": RENDER_DISTANCE.DEFAULT
		}
		
		if err == OK:
			settings.master_volume = config.get_value("audio", "master_volume", 75.0)
			settings.music_volume = config.get_value("audio", "music_volume", 75.0)
			settings.sfx_volume = config.get_value("audio", "sfx_volume", 75.0)
			settings.fullscreen = config.get_value("display", "fullscreen", false)
			settings.render_distance = config.get_value("graphics", "render_distance", RENDER_DISTANCE.DEFAULT)
		
		return settings
	
	static func save_settings(volume: float, fullscreen: bool) -> void:
		"""Save all settings to config file."""
		var config = ConfigFile.new()
		
		# Save volume and fullscreen
		config.set_value("audio", "master_volume", volume)
		config.set_value("display", "fullscreen", fullscreen)
		
		# Save to file
		config.save("user://settings.cfg")
	
	static func apply_master_volume_setting(_value: float) -> void:
		"""Apply master volume setting (for storage, not direct audio)."""
		# Master volume is applied through multiplication in the UI handlers
		pass
	
	static func apply_music_volume_setting(_value: float) -> void:
		"""Apply music volume setting (for storage, not direct audio)."""
		# Music volume is applied through multiplication in the UI handlers
		pass
	
	static func apply_sfx_volume_setting(_value: float) -> void:
		"""Apply SFX volume setting (for storage, not direct audio)."""
		# SFX volume is applied through multiplication in the UI handlers
		pass
	
	static func apply_effective_music_volume(effective_value: float) -> void:
		"""Apply the calculated effective music volume to the Music audio bus."""
		var volume_db: float = linear_to_db(effective_value / 100.0)
		var music_bus_index = AudioServer.get_bus_index("Music")
		if music_bus_index != -1:
			AudioServer.set_bus_volume_db(music_bus_index, volume_db)
		else:
			# Fallback to Master bus if Music bus doesn't exist
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), volume_db)
	
	static func apply_effective_sfx_volume(effective_value: float) -> void:
		"""Apply the calculated effective SFX volume to the SFX audio bus."""
		var volume_db: float = linear_to_db(effective_value / 100.0)
		var sfx_bus_index = AudioServer.get_bus_index("SFX")
		if sfx_bus_index != -1:
			AudioServer.set_bus_volume_db(sfx_bus_index, volume_db)
		else:
			# Fallback to Master bus if SFX bus doesn't exist
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), volume_db)
	
	static func apply_volume_setting(value: float) -> void:
		"""Legacy method for backward compatibility."""
		apply_effective_music_volume(value)
		apply_effective_sfx_volume(value)
	
	static func save_volume_settings(master_volume: float, music_volume: float, sfx_volume: float, fullscreen: bool) -> void:
		"""Save all volume settings and fullscreen to config file."""
		var config = ConfigFile.new()
		
		# Load existing settings first to preserve render distance
		var err = config.load("user://settings.cfg")
		
		# Save all volume settings
		config.set_value("audio", "master_volume", master_volume)
		config.set_value("audio", "music_volume", music_volume)
		config.set_value("audio", "sfx_volume", sfx_volume)
		config.set_value("display", "fullscreen", fullscreen)
		
		# Save to file
		config.save("user://settings.cfg")
	
	static func save_all_settings(master_volume: float, music_volume: float, sfx_volume: float, fullscreen: bool, render_distance: int) -> void:
		"""Save all settings including render distance to config file."""
		var config = ConfigFile.new()
		
		# Save all settings
		config.set_value("audio", "master_volume", master_volume)
		config.set_value("audio", "music_volume", music_volume)
		config.set_value("audio", "sfx_volume", sfx_volume)
		config.set_value("display", "fullscreen", fullscreen)
		config.set_value("graphics", "render_distance", render_distance)
		
		# Save to file
		config.save("user://settings.cfg")
	
	static func apply_render_distance_setting(distance: int) -> void:
		"""Apply render distance setting to the chunk system."""
		# Clamp the value to valid range
		var clamped_distance = clamp(distance, RENDER_DISTANCE.MIN, RENDER_DISTANCE.MAX)
		
		# Find and update PlayerTracker
		var game_managers: Array[Node] = Engine.get_main_loop().get_nodes_in_group("game_manager")
		if game_managers.size() > 0:
			var game_manager = game_managers[0]
			if game_manager.has_method("get_chunk_manager"):
				var chunk_manager = game_manager.get_chunk_manager()
				if chunk_manager and chunk_manager.player_tracker:
					chunk_manager.player_tracker.set_render_distance(clamped_distance)
					print("SettingsManager: Applied render distance: ", clamped_distance)
				else:
					print("SettingsManager: ChunkManager or PlayerTracker not found")
			else:
				print("SettingsManager: GameManager has no get_chunk_manager method")
		else:
			print("SettingsManager: No GameManager found")
	
	static func apply_fullscreen_setting(enabled: bool) -> void:
		"""Apply fullscreen setting to display system."""
		if enabled:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED) 
