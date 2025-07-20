class_name BiomeManager
extends RefCounted

# --- Biome Types ---
enum BiomeType {
	MOUNTAIN,   # High altitude, rocky terrain, dead trees, stone material
	FOREST,     # Normal altitude, green trees, green grass
	AUTUMN,     # Normal altitude, autumn trees, yellow/orange grass  
	SNOW        # Varied altitude, snow trees, white snow with grass patches
}

# --- Biome Configuration ---
class BiomeConfig:
	var type: BiomeType
	var name: String
	var altitude_min: float
	var altitude_max: float
	var temperature_min: float
	var temperature_max: float
	var humidity_min: float
	var humidity_max: float
	var terrain_material: StandardMaterial3D
	var tree_density: float
	var rock_density: float
	var tree_assets: Array[String] = []
	var rock_assets: Array[String] = []
	var grass_color: Color
	var blend_factor: float  # How much this biome blends with others
	
	func _init(biome_type: BiomeType, biome_name: String):
		type = biome_type
		name = biome_name

# --- Constants ---
const BIOME_TRANSITION_DISTANCE: float = 5.0  # Reduced from 50.0 for extremely sharp transitions
const NOISE_SCALE_ALTITUDE: float = 0.002      # Scale for altitude noise (adjusted for Minecraft-like terrain)
const NOISE_SCALE_TEMPERATURE: float = 0.0008  # Scale for temperature noise (further reduced for much larger temperature zones)
const NOISE_SCALE_HUMIDITY: float = 0.001      # Scale for humidity noise (further reduced for much larger humidity zones)
const MAX_MOUNTAIN_HEIGHT: float = 200.0       # Reference height for terrain calculations - terrain can exceed this
const BASE_TERRAIN_HEIGHT: float = 50.0        # Base terrain level - Standard rolling hills height

# --- Tree Asset Paths by Category ---
const TREE_ASSETS_NORMAL: Array[String] = [
	# BirchTree normal variants (1-5)
	"res://assets/trees/UltimatePack/OBJ/BirchTree_1.obj",
	"res://assets/trees/UltimatePack/OBJ/BirchTree_2.obj", 
	"res://assets/trees/UltimatePack/OBJ/BirchTree_3.obj",
	"res://assets/trees/UltimatePack/OBJ/BirchTree_4.obj",
	"res://assets/trees/UltimatePack/OBJ/BirchTree_5.obj",
	# CommonTree normal variants (1-5)
	"res://assets/trees/UltimatePack/OBJ/CommonTree_1.obj",
	"res://assets/trees/UltimatePack/OBJ/CommonTree_2.obj",
	"res://assets/trees/UltimatePack/OBJ/CommonTree_3.obj", 
	"res://assets/trees/UltimatePack/OBJ/CommonTree_4.obj",
	"res://assets/trees/UltimatePack/OBJ/CommonTree_5.obj",
	# PineTree normal variants (1-3)
	"res://assets/trees/UltimatePack/OBJ/PineTree_1.obj",
	"res://assets/trees/UltimatePack/OBJ/PineTree_2.obj",
	"res://assets/trees/UltimatePack/OBJ/PineTree_3.obj"
]

const TREE_ASSETS_AUTUMN: Array[String] = [
	# BirchTree autumn variants (1-5)
	"res://assets/trees/UltimatePack/OBJ/BirchTree_Autumn_1.obj",
	"res://assets/trees/UltimatePack/OBJ/BirchTree_Autumn_2.obj",
	"res://assets/trees/UltimatePack/OBJ/BirchTree_Autumn_3.obj", 
	"res://assets/trees/UltimatePack/OBJ/BirchTree_Autumn_4.obj",
	"res://assets/trees/UltimatePack/OBJ/BirchTree_Autumn_5.obj",
	# CommonTree autumn variants (1-5)
	"res://assets/trees/UltimatePack/OBJ/CommonTree_Autumn_1.obj",
	"res://assets/trees/UltimatePack/OBJ/CommonTree_Autumn_2.obj",
	"res://assets/trees/UltimatePack/OBJ/CommonTree_Autumn_3.obj",
	"res://assets/trees/UltimatePack/OBJ/CommonTree_Autumn_4.obj", 
	"res://assets/trees/UltimatePack/OBJ/CommonTree_Autumn_5.obj",
	# PineTree autumn variants (1-3)
	"res://assets/trees/UltimatePack/OBJ/PineTree_Autumn_1.obj",
	"res://assets/trees/UltimatePack/OBJ/PineTree_Autumn_2.obj",
	"res://assets/trees/UltimatePack/OBJ/PineTree_Autumn_3.obj"
]

const TREE_ASSETS_SNOW: Array[String] = [
	# BirchTree snow variants (1-5)
	"res://assets/trees/UltimatePack/OBJ/BirchTree_Snow_1.obj",
	"res://assets/trees/UltimatePack/OBJ/BirchTree_Snow_2.obj",
	"res://assets/trees/UltimatePack/OBJ/BirchTree_Snow_3.obj",
	"res://assets/trees/UltimatePack/OBJ/BirchTree_Snow_4.obj", 
	"res://assets/trees/UltimatePack/OBJ/BirchTree_Snow_5.obj",
	# CommonTree snow variants (1-5)
	"res://assets/trees/UltimatePack/OBJ/CommonTree_Snow_1.obj",
	"res://assets/trees/UltimatePack/OBJ/CommonTree_Snow_2.obj",
	"res://assets/trees/UltimatePack/OBJ/CommonTree_Snow_3.obj",
	"res://assets/trees/UltimatePack/OBJ/CommonTree_Snow_4.obj",
	"res://assets/trees/UltimatePack/OBJ/CommonTree_Snow_5.obj",
	# PineTree snow variants (1-3)
	"res://assets/trees/UltimatePack/OBJ/PineTree_Snow_1.obj",
	"res://assets/trees/UltimatePack/OBJ/PineTree_Snow_2.obj", 
	"res://assets/trees/UltimatePack/OBJ/PineTree_Snow_3.obj"
]

const TREE_ASSETS_DEAD: Array[String] = [
	# BirchTree dead variants (1-5)
	"res://assets/trees/UltimatePack/OBJ/BirchTree_Dead_1.obj",
	"res://assets/trees/UltimatePack/OBJ/BirchTree_Dead_2.obj",
	"res://assets/trees/UltimatePack/OBJ/BirchTree_Dead_3.obj",
	"res://assets/trees/UltimatePack/OBJ/BirchTree_Dead_4.obj",
	"res://assets/trees/UltimatePack/OBJ/BirchTree_Dead_5.obj",
	# CommonTree dead variants (1-5)
	"res://assets/trees/UltimatePack/OBJ/CommonTree_Dead_1.obj",
	"res://assets/trees/UltimatePack/OBJ/CommonTree_Dead_2.obj",
	"res://assets/trees/UltimatePack/OBJ/CommonTree_Dead_3.obj",
	"res://assets/trees/UltimatePack/OBJ/CommonTree_Dead_4.obj",
	"res://assets/trees/UltimatePack/OBJ/CommonTree_Dead_5.obj"
]

# --- Rock Asset Paths by Category ---
const ROCK_ASSETS_NORMAL: Array[String] = [
	"res://assets/trees/UltimatePack/OBJ/Rock_1.obj",
	"res://assets/trees/UltimatePack/OBJ/Rock_2.obj", 
	"res://assets/trees/UltimatePack/OBJ/Rock_3.obj",
	"res://assets/trees/UltimatePack/OBJ/Rock_4.obj",
	"res://assets/trees/UltimatePack/OBJ/Rock_5.obj",
	"res://assets/trees/UltimatePack/OBJ/Rock_6.obj",
	"res://assets/trees/UltimatePack/OBJ/Rock_7.obj"
]

const ROCK_ASSETS_MOSS: Array[String] = [
	"res://assets/trees/UltimatePack/OBJ/Rock_Moss_1.obj",
	"res://assets/trees/UltimatePack/OBJ/Rock_Moss_2.obj",
	"res://assets/trees/UltimatePack/OBJ/Rock_Moss_3.obj",
	"res://assets/trees/UltimatePack/OBJ/Rock_Moss_4.obj",
	"res://assets/trees/UltimatePack/OBJ/Rock_Moss_5.obj", 
	"res://assets/trees/UltimatePack/OBJ/Rock_Moss_6.obj",
	"res://assets/trees/UltimatePack/OBJ/Rock_Moss_7.obj"
]

const ROCK_ASSETS_SNOW: Array[String] = [
	"res://assets/trees/UltimatePack/OBJ/Rock_Snow_1.obj",
	"res://assets/trees/UltimatePack/OBJ/Rock_Snow_2.obj",
	"res://assets/trees/UltimatePack/OBJ/Rock_Snow_3.obj",
	"res://assets/trees/UltimatePack/OBJ/Rock_Snow_4.obj",
	"res://assets/trees/UltimatePack/OBJ/Rock_Snow_5.obj",
	"res://assets/trees/UltimatePack/OBJ/Rock_Snow_6.obj",
	"res://assets/trees/UltimatePack/OBJ/Rock_Snow_7.obj"
]


# --- Biome Settings Configuration Dictionary ---
# Centralized place for all biome settings - can be modified at runtime for debugging/tuning
static var BIOME_SETTINGS: Dictionary = {
	BiomeType.MOUNTAIN: {
		"name": "Mountain",
		"altitude_threshold": 0.55,  # Primary threshold for biome detection
		"altitude_min": 0.55,        # Configuration min range
		"altitude_max": 1.0,         # Configuration max range
		"temperature_min": 0.0,
		"temperature_max": 1.0,
		"humidity_min": 0.0,
		"humidity_max": 1.0,
		"tree_density": 0.3,         # Sparse tree coverage
		"rock_density": 2.0,         # High rock density
		"grass_color": Color(0.55, 0.55, 0.55),  # Grey rocky color
		"tree_assets": TREE_ASSETS_DEAD,
		"rock_assets": ROCK_ASSETS_NORMAL,
		"terrain_textures": {
			"albedo": "res://assets/textures/rock terrain/textures/rocks_ground_05_diff_4k.jpg",
			"normal": null,
			"roughness": "res://assets/textures/rock terrain/textures/rocks_ground_05_rough_4k.jpg"
		},
		"material_properties": {
			"albedo_color": Color(0.85, 0.85, 0.85),
			"roughness": 0.9,
			"metallic": 0.0,
			"specular": 0.1,
			"uv_scale": Vector3(50.0, 50.0, 1.0),
			"triplanar_sharpness": 1.0
		}
	},
	BiomeType.FOREST: {
		"name": "Forest", 
		"altitude_threshold": null,  # No primary threshold (default biome)
		"altitude_min": 0.2,
		"altitude_max": 0.8,
		"temperature_min": 0.4,      # Above snow threshold
		"temperature_max": 0.65,     # Below autumn threshold  
		"humidity_min": 0.5,         # Above autumn threshold
		"humidity_max": 1.0,
		"tree_density": 1.5,         # Dense tree coverage
		"rock_density": 0.2,         # Low rock density
		"grass_color": Color(0.3, 0.7, 0.2),  # Rich green
		"tree_assets": TREE_ASSETS_NORMAL,
		"rock_assets": ROCK_ASSETS_MOSS,
		"terrain_textures": {
			"albedo": "res://assets/textures/grass terrain/textures/rocky_terrain_02_diff_4k.jpg",
			"normal": null,
			"roughness": null
		},
		"material_properties": {
			"albedo_color": Color(0.6, 0.85, 0.5),
			"roughness": 0.75,
			"metallic": 0.0,
			"specular": 0.2,
			"uv_scale": Vector3(60.0, 60.0, 1.0),
			"triplanar_sharpness": 0.5
		}
	},
	BiomeType.AUTUMN: {
		"name": "Autumn",
		"altitude_threshold": null,  # No primary threshold (secondary conditions)
		"altitude_min": 0.2,
		"altitude_max": 0.7,
		"temperature_min": 0.65,     # Above forest threshold
		"temperature_max": 1.0,
		"humidity_min": 0.0,
		"humidity_max": 0.5,         # Below forest threshold
		"tree_density": 1.2,         # Moderate tree coverage
		"rock_density": 0.1,         # Very low rock density
		"grass_color": Color(0.8, 0.6, 0.2),  # Golden autumn color
		"tree_assets": TREE_ASSETS_AUTUMN,
		"rock_assets": ROCK_ASSETS_NORMAL,
		"terrain_textures": {
			"albedo": "res://assets/textures/leaves terrain/textures/leaves_forest_ground_diff_4k.jpg",
			"normal": null,
			"roughness": null
		},
		"material_properties": {
			"albedo_color": Color(1.0, 0.9, 0.7),
			"roughness": 0.65,
			"metallic": 0.0,
			"specular": 0.3,
			"uv_scale": Vector3(450.0, 450.0, 1.0),
			"triplanar_sharpness": 0.3
		}
	},
	BiomeType.SNOW: {
		"name": "Snow",
		"altitude_threshold": null,  # No primary threshold (temperature based)
		"altitude_min": 0.0,
		"altitude_max": 1.0,
		"temperature_min": 0.0,
		"temperature_max": 0.4,      # Cold temperature threshold
		"humidity_min": 0.0,
		"humidity_max": 1.0,
		"tree_density": 0.8,         # Moderate tree coverage
		"rock_density": 0.4,         # Moderate rock density
		"grass_color": Color(0.95, 0.95, 0.95),  # Pure white snow color
		"tree_assets": TREE_ASSETS_SNOW,
		"rock_assets": ROCK_ASSETS_SNOW,
		"terrain_textures": {
			"albedo": "res://assets/textures/snow terrain/Snow002_4K_Color.jpg",
			"normal": "res://assets/textures/snow terrain/Snow002_4K_NormalGL.jpg",
			"roughness": "res://assets/textures/snow terrain/Snow002_4K_Roughness.jpg"
		},
		"material_properties": {
			"albedo_color": Color(1.0, 1.0, 1.0),
			"roughness": 0.35,
			"metallic": 0.0,
			"specular": 0.7,
			"uv_scale": Vector3(40.0, 40.0, 1.0),
			"triplanar_sharpness": 0.8
		}
	}
}

# --- Biome Detection Thresholds ---
# Controls how biomes are detected at world positions
# Note: Using static var instead of const to allow runtime modification for debugging/tuning
static var BIOME_DETECTION: Dictionary = {
	"blend_radius": 0.05,           # Transition smoothness (0.05 = sharp, 0.1 = smooth)
	"mountain_threshold": 0.55,     # Altitude factor for mountain biome
	"snow_threshold": 0.4,          # Temperature factor for snow biome
	"autumn_temperature": 0.65,     # Temperature factor for autumn biome
	"autumn_humidity": 0.5          # Humidity factor for autumn biome
}

# --- Properties ---
var biome_configs: Dictionary = {}
var noise_altitude: FastNoiseLite
var noise_temperature: FastNoiseLite
var noise_humidity: FastNoiseLite
var world_seed: int = 12345

# --- Public Methods ---

func _init():
	"""Initialize the biome manager with noise generators and biome configurations."""
	_ensure_static_dictionaries_initialized()
	_initialize_noise_generators()
	_create_biome_configurations()
	print("BiomeManager: Initialized with ", biome_configs.size(), " biome types")
	# Debug: Print biome distribution
	_debug_biome_distribution()


func set_world_seed(seed_value: int) -> void:
	"""Set the world generation seed."""
	print("BiomeManager: Setting world seed from ", world_seed, " to ", seed_value)
	world_seed = seed_value
	_initialize_noise_generators()
	print("BiomeManager: Noise generators re-initialized with seed: ", seed_value)

func get_biome_at_position(world_pos: Vector3) -> BiomeType:
	"""Determine the primary biome type at a given world position."""
	var altitude_factor: float = _get_altitude_factor(world_pos)
	var temperature_factor: float = _get_temperature_factor(world_pos) 
	var humidity_factor: float = _get_humidity_factor(world_pos)
	
	# Mountain biome has priority at high altitudes
	if altitude_factor > BIOME_DETECTION["mountain_threshold"]:
		return BiomeType.MOUNTAIN
	
	# Use temperature and humidity to determine other biomes
	if temperature_factor < BIOME_DETECTION["snow_threshold"]:
		return BiomeType.SNOW
	elif temperature_factor > BIOME_DETECTION["autumn_temperature"] and humidity_factor < BIOME_DETECTION["autumn_humidity"]:
		return BiomeType.AUTUMN
	else:
		return BiomeType.FOREST


func get_biome_blend_weights(world_pos: Vector3) -> Dictionary:
	"""Get the blend weights for all biomes at a position for smooth transitions."""
	var weights: Dictionary = {}
	
	# Calculate base factors
	var altitude_factor: float = _get_altitude_factor(world_pos)
	var temperature_factor: float = _get_temperature_factor(world_pos)
	var humidity_factor: float = _get_humidity_factor(world_pos)
	
	# Initialize all weights to 0
	weights[BiomeType.MOUNTAIN] = 0.0
	weights[BiomeType.SNOW] = 0.0
	weights[BiomeType.AUTUMN] = 0.0
	weights[BiomeType.FOREST] = 0.0
	
	# Define blend radius for smoother transitions
	var blend_radius: float = BIOME_DETECTION["blend_radius"]
	var mountain_threshold: float = BIOME_DETECTION["mountain_threshold"]
	var snow_threshold: float = BIOME_DETECTION["snow_threshold"]
	var autumn_temp: float = BIOME_DETECTION["autumn_temperature"]
	var autumn_humid: float = BIOME_DETECTION["autumn_humidity"]
	
	# Mountain biome blending
	if altitude_factor > mountain_threshold - blend_radius:
		if altitude_factor >= mountain_threshold:
			weights[BiomeType.MOUNTAIN] = 1.0
		else:
			# Blend zone
			weights[BiomeType.MOUNTAIN] = (altitude_factor - (mountain_threshold - blend_radius)) / blend_radius
	
	# Snow biome blending
	if temperature_factor < snow_threshold + blend_radius and weights[BiomeType.MOUNTAIN] < 1.0:
		if temperature_factor <= snow_threshold:
			weights[BiomeType.SNOW] = 1.0 - weights[BiomeType.MOUNTAIN]
		else:
			# Blend zone
			var snow_blend: float = (snow_threshold + blend_radius - temperature_factor) / blend_radius
			weights[BiomeType.SNOW] = snow_blend * (1.0 - weights[BiomeType.MOUNTAIN])
	
	# Autumn biome blending
	if temperature_factor > autumn_temp - blend_radius and humidity_factor < autumn_humid + blend_radius:
		if weights[BiomeType.MOUNTAIN] < 1.0 and weights[BiomeType.SNOW] < 1.0:
			var temp_blend: float = 1.0
			var humid_blend: float = 1.0
			
			# Temperature blend
			if temperature_factor < autumn_temp:
				temp_blend = (temperature_factor - (autumn_temp - blend_radius)) / blend_radius
			
			# Humidity blend
			if humidity_factor > autumn_humid:
				humid_blend = (autumn_humid + blend_radius - humidity_factor) / blend_radius
			
			weights[BiomeType.AUTUMN] = temp_blend * humid_blend * (1.0 - weights[BiomeType.MOUNTAIN] - weights[BiomeType.SNOW])
	
	# Forest biome fills the rest
	var total_weight: float = weights[BiomeType.MOUNTAIN] + weights[BiomeType.SNOW] + weights[BiomeType.AUTUMN]
	weights[BiomeType.FOREST] = max(0.0, 1.0 - total_weight)
	
	# Normalize to ensure weights sum to 1.0
	total_weight = weights[BiomeType.MOUNTAIN] + weights[BiomeType.SNOW] + weights[BiomeType.AUTUMN] + weights[BiomeType.FOREST]
	if total_weight > 0.0:
		for biome_type in weights:
			weights[biome_type] /= total_weight
	
	return weights


func get_terrain_height_at_position(world_pos: Vector3) -> float:
	"""Calculate terrain height at position using Minecraft-style multi-layer noise."""
	# Get noise values from all layers - use much larger offset to completely avoid origin artifacts
	var x: float = world_pos.x + 50000.0  # Increased offset to avoid origin artifacts and (0,0) spikes
	var z: float = world_pos.z + 50000.0  # Increased offset to avoid origin artifacts and (0,0) spikes
	
	# Get raw noise values (-1 to 1)
	var continentalness: float = noise_continentalness.get_noise_2d(x, z)
	var erosion: float = noise_erosion.get_noise_2d(x, z)
	var peaks_valleys: float = noise_peaks_valleys.get_noise_2d(x, z)
	var base_noise: float = noise_altitude.get_noise_2d(x, z)
	
	# FULL TERRAIN HEIGHT CALCULATION WITH PROPER VARIATION
	var base_height: float = BASE_TERRAIN_HEIGHT  # Use the 50.0 constant
	
	# Continental influence - determines if this is ocean, land, or mountain
	var continental_factor: float = (continentalness + 1.0) * 0.5  # Convert -1,1 to 0,1
	
	# Erosion affects height dramatically
	var erosion_factor: float = (erosion + 1.0) * 0.5  # Convert -1,1 to 0,1
	
	# Peaks and valleys create dramatic height variation
	var peaks_factor: float = peaks_valleys  # Keep -1 to 1 range for valleys/peaks
	
	# Base terrain variation
	var base_variation: float = base_noise * 40.0  # Increased from 30.0
	
	# Calculate continental height (0 = sea level, 1 = high continental)
	var continental_height: float = continental_factor * MAX_MOUNTAIN_HEIGHT * 0.6
	
	# Erosion reduces height (inverted - high erosion = lower terrain)
	var erosion_height: float = (1.0 - erosion_factor) * MAX_MOUNTAIN_HEIGHT * 0.4
	
	# Peaks create dramatic spikes and valleys
	var peaks_height: float = peaks_factor * MAX_MOUNTAIN_HEIGHT * 0.8
	
	# Combine all factors
	var final_height: float = base_height + base_variation + continental_height + erosion_height + peaks_height
	
	# Debug: Check final height at origin occasionally
	if abs(world_pos.x) < 1.0 and abs(world_pos.z) < 1.0:
		print("Debug terrain at origin: base=", base_height, " variation=", base_variation, " continental=", continental_height, " erosion=", erosion_height, " peaks=", peaks_height, " FINAL=", final_height)
	
	# No height clamping - allow unlimited terrain height generation
	# Previously: final_height = clamp(final_height, 0.0, MAX_MOUNTAIN_HEIGHT + BASE_TERRAIN_HEIGHT)
	final_height = max(final_height, 0.0)  # Only prevent negative heights (underground terrain)
	
	return final_height


func get_terrain_material_for_biome(biome_type: BiomeType) -> StandardMaterial3D:
	"""Get the appropriate terrain material for a biome type."""
	if biome_configs.has(biome_type):
		return biome_configs[biome_type].terrain_material
	return _create_default_material()


func get_tree_assets_for_biome(biome_type: BiomeType) -> Array[String]:
	"""Get the tree asset paths for a specific biome."""
	if biome_configs.has(biome_type):
		return biome_configs[biome_type].tree_assets
	return []


func get_rock_assets_for_biome(biome_type: BiomeType) -> Array[String]:
	"""Get the rock asset paths for a specific biome.""" 
	if biome_configs.has(biome_type):
		return biome_configs[biome_type].rock_assets
	return []


func get_tree_density_for_biome(biome_type: BiomeType) -> float:
	"""Get the tree density modifier for a specific biome."""
	if biome_configs.has(biome_type):
		return biome_configs[biome_type].tree_density
	return 1.0


func get_rock_density_for_biome(biome_type: BiomeType) -> float:
	"""Get the rock density modifier for a specific biome."""
	if biome_configs.has(biome_type):
		return biome_configs[biome_type].rock_density
	return 0.0


func get_biome_settings(biome_type: BiomeType) -> Dictionary:
	"""Get the complete settings dictionary for a biome type."""
	if BIOME_SETTINGS.has(biome_type):
		return BIOME_SETTINGS[biome_type].duplicate(true)
	return {}


func get_biome_detection_settings() -> Dictionary:
	"""Get the current biome detection settings."""
	return BIOME_DETECTION.duplicate(true)


func update_biome_setting(biome_type: BiomeType, setting_key: String, new_value) -> bool:
	"""Update a specific biome setting at runtime (for debugging/tuning)."""
	if not BIOME_SETTINGS.has(biome_type):
		push_error("BiomeManager: Invalid biome type: " + str(biome_type))
		return false
	
	if not BIOME_SETTINGS[biome_type].has(setting_key):
		push_error("BiomeManager: Invalid setting key: " + setting_key + " for biome: " + str(biome_type))
		return false
	
	# Note: This only updates the constant dictionary, not the biome_configs
	# You would need to call _create_biome_configurations() again to apply changes
	var old_value = BIOME_SETTINGS[biome_type][setting_key]
	BIOME_SETTINGS[biome_type][setting_key] = new_value
	print("BiomeManager: Updated ", BIOME_SETTINGS[biome_type]["name"], ".", setting_key, " from ", old_value, " to ", new_value)
	return true


func update_detection_setting(setting_key: String, new_value: float) -> bool:
	"""Update a biome detection threshold at runtime (for debugging/tuning)."""
	if not BIOME_DETECTION.has(setting_key):
		push_error("BiomeManager: Invalid detection setting key: " + setting_key)
		return false
	
	var old_value = BIOME_DETECTION[setting_key]
	BIOME_DETECTION[setting_key] = new_value
	print("BiomeManager: Updated detection.", setting_key, " from ", old_value, " to ", new_value)
	return true


func reload_biome_configurations() -> void:
	"""Reload all biome configurations from the dictionary (useful after runtime changes)."""
	biome_configs.clear()
	_create_biome_configurations()
	print("BiomeManager: Reloaded all biome configurations from dictionary")


func print_all_biome_settings() -> void:
	"""Print all current biome settings for debugging."""
	print("=== BIOME SETTINGS DICTIONARY ===")
	for biome_type in BIOME_SETTINGS:
		var settings: Dictionary = BIOME_SETTINGS[biome_type]
		print("--- ", settings["name"], " Biome (", biome_type, ") ---")
		for key in settings:
			if key != "tree_assets" and key != "rock_assets" and key != "terrain_textures" and key != "material_properties":
				print("  ", key, ": ", settings[key])
		print("  tree_assets: ", settings["tree_assets"].size(), " assets")
		print("  rock_assets: ", settings["rock_assets"].size(), " assets")
		print("  terrain_textures: ", settings["terrain_textures"])
		print("  material_properties: ", settings["material_properties"])
	
	print("=== BIOME DETECTION SETTINGS ===")
	for key in BIOME_DETECTION:
		print("  ", key, ": ", BIOME_DETECTION[key])
	print("==================================")


func example_runtime_modifications() -> void:
	"""Example of how to modify biome settings at runtime for debugging/tuning."""
	print("=== BIOME MODIFICATION EXAMPLES ===")
	
	# Example 1: Make mountains appear at even lower altitudes
	print("Example 1: Lowering mountain threshold from 0.55 to 0.45")
	update_detection_setting("mountain_threshold", 0.45)
	
	# Example 2: Increase mountain tree density
	print("Example 2: Increasing mountain tree density from 0.3 to 0.5")
	update_biome_setting(BiomeType.MOUNTAIN, "tree_density", 0.5)
	
	# Example 3: Change autumn grass color
	print("Example 3: Changing autumn grass color to deeper gold")
	update_biome_setting(BiomeType.AUTUMN, "grass_color", Color(0.9, 0.7, 0.1))
	
	# Example 4: Adjust blending sharpness
	print("Example 4: Making biome transitions smoother (0.05 -> 0.1)")
	update_detection_setting("blend_radius", 0.1)
	
	# Apply changes (you would call this to regenerate the world)
	print("To apply these changes, call: reload_biome_configurations()")
	print("Then regenerate the world in WorldGenerator")
	print("===================================")

# --- Private Methods ---

func _ensure_static_dictionaries_initialized() -> void:
	"""Ensure static dictionaries are properly initialized (GDScript static var safety check)."""
	# BIOME_SETTINGS should already be initialized by the static var declaration
	if BIOME_SETTINGS.is_empty():
		push_error("BiomeManager: BIOME_SETTINGS dictionary failed to initialize properly!")
	
	# BIOME_DETECTION should already be initialized by the static var declaration  
	if BIOME_DETECTION.is_empty():
		push_error("BiomeManager: BIOME_DETECTION dictionary failed to initialize properly!")
	
	print("BiomeManager: Static dictionaries verified - BIOME_SETTINGS: ", BIOME_SETTINGS.size(), " biomes, BIOME_DETECTION: ", BIOME_DETECTION.size(), " settings")


func _initialize_noise_generators() -> void:
	"""Initialize all noise generators with different seeds and properties."""
	# Use a base seed that can be randomized but ensures consistent patterns
	var base_seed: int = world_seed
	
	# Altitude noise - NOW USING MINECRAFT-STYLE PERLIN WITH MULTIPLE OCTAVES
	# This is the main terrain height generator
	noise_altitude = FastNoiseLite.new()
	noise_altitude.seed = base_seed
	noise_altitude.frequency = NOISE_SCALE_ALTITUDE * 0.5  # Lower frequency for larger features
	noise_altitude.noise_type = FastNoiseLite.TYPE_PERLIN  # Changed back to Perlin from Cellular
	noise_altitude.fractal_type = FastNoiseLite.FRACTAL_FBM  # Fractal Brownian Motion like Minecraft
	noise_altitude.fractal_octaves = 8  # Minecraft typically uses 8-16 octaves
	noise_altitude.fractal_gain = 0.5  # Standard gain for FBM
	noise_altitude.fractal_lacunarity = 2.0  # Standard lacunarity (frequency multiplier per octave)
	noise_altitude.fractal_weighted_strength = 0.0  # Standard FBM, not weighted
	
	# Temperature noise - controls hot/cold regions (for biome variation)
	noise_temperature = FastNoiseLite.new()
	noise_temperature.seed = base_seed + 1000
	noise_temperature.frequency = NOISE_SCALE_TEMPERATURE 
	noise_temperature.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_temperature.fractal_octaves = 3
	# Adjust gain to create more variation in temperature
	noise_temperature.fractal_gain = 0.6  # More pronounced hot/cold areas
	
	# Humidity noise - controls wet/dry regions
	noise_humidity = FastNoiseLite.new()
	noise_humidity.seed = base_seed + 2000
	noise_humidity.frequency = NOISE_SCALE_HUMIDITY
	noise_humidity.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise_humidity.fractal_octaves = 2
	
	# Initialize additional noise generators for Minecraft-style terrain
	_initialize_minecraft_noise_layers()


# New member variables for Minecraft-style terrain generation
var noise_continentalness: FastNoiseLite  # Large-scale terrain features (continents vs oceans)
var noise_erosion: FastNoiseLite  # Controls terrain smoothness/roughness
var noise_peaks_valleys: FastNoiseLite  # Creates variation between peaks and valleys
var noise_mountain_ridge: FastNoiseLite  # For sharp mountain ridges


func _initialize_minecraft_noise_layers() -> void:
	"""Initialize additional noise layers for Minecraft-style terrain generation."""
	var base_seed: int = world_seed
	
	# Continentalness - determines large-scale elevation (ocean floor vs highlands)
	noise_continentalness = FastNoiseLite.new()
	noise_continentalness.seed = base_seed + 3000
	noise_continentalness.frequency = 0.0002  # Very low frequency for continent-sized features
	noise_continentalness.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_continentalness.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_continentalness.fractal_octaves = 4
	noise_continentalness.fractal_gain = 0.5
	noise_continentalness.fractal_lacunarity = 2.5
	
	# Erosion - affects terrain roughness
	noise_erosion = FastNoiseLite.new()
	noise_erosion.seed = base_seed + 4000
	noise_erosion.frequency = 0.0008  # Medium frequency
	noise_erosion.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_erosion.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_erosion.fractal_octaves = 5
	noise_erosion.fractal_gain = 0.45
	noise_erosion.fractal_lacunarity = 2.0
	
	# Peaks and Valleys - creates local height variation
	noise_peaks_valleys = FastNoiseLite.new()
	noise_peaks_valleys.seed = base_seed + 5000
	noise_peaks_valleys.frequency = 0.001  # Medium-high frequency
	noise_peaks_valleys.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_peaks_valleys.fractal_type = FastNoiseLite.FRACTAL_RIDGED  # Ridged for more dramatic peaks
	noise_peaks_valleys.fractal_octaves = 6
	noise_peaks_valleys.fractal_gain = 0.5
	noise_peaks_valleys.fractal_lacunarity = 2.0
	
	# Mountain ridge noise - for sharp mountain peaks
	noise_mountain_ridge = FastNoiseLite.new()
	noise_mountain_ridge.seed = base_seed + 6000
	noise_mountain_ridge.frequency = 0.002
	noise_mountain_ridge.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_mountain_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise_mountain_ridge.fractal_octaves = 4
	noise_mountain_ridge.fractal_gain = 0.6
	noise_mountain_ridge.fractal_lacunarity = 2.0


func _create_biome_configurations() -> void:
	"""Create and configure all biome types with their properties from the centralized dictionary."""
	for biome_type in BIOME_SETTINGS:
		var settings: Dictionary = BIOME_SETTINGS[biome_type]
		var config: BiomeConfig = BiomeConfig.new(biome_type, settings["name"])
		
		# Apply settings from dictionary
		config.altitude_min = settings["altitude_min"]
		config.altitude_max = settings["altitude_max"]
		config.temperature_min = settings["temperature_min"]
		config.temperature_max = settings["temperature_max"]
		config.humidity_min = settings["humidity_min"]
		config.humidity_max = settings["humidity_max"]
		config.tree_density = settings["tree_density"]
		config.rock_density = settings["rock_density"]
		config.grass_color = settings["grass_color"]
		config.tree_assets = settings["tree_assets"]
		config.rock_assets = settings["rock_assets"]
		
		# Create terrain material based on settings
		config.terrain_material = _create_terrain_material(biome_type, settings)
		
		biome_configs[biome_type] = config
		print("BiomeManager: Configured ", settings["name"], " biome from dictionary")


func _get_altitude_factor(world_pos: Vector3) -> float:
	"""Get altitude factor (0-1) at world position using standard Perlin noise."""
	# Get raw Perlin noise with offset to avoid origin artifacts
	var raw_noise: float = noise_altitude.get_noise_2d(world_pos.x + 50000.0, world_pos.z + 50000.0)
	
	# Normalize to 0-1 range
	var normalized: float = (raw_noise + 1.0) * 0.5
	
	# No power transformation - let the height calculation handle non-linearity
	return normalized


func _get_temperature_factor(world_pos: Vector3) -> float:
	"""Get temperature factor (0-1) at world position."""
	return (noise_temperature.get_noise_2d(world_pos.x + 50000.0, world_pos.z + 50000.0) + 1.0) * 0.5


func _get_humidity_factor(world_pos: Vector3) -> float:
	"""Get humidity factor (0-1) at world position."""
	return (noise_humidity.get_noise_2d(world_pos.x + 50000.0, world_pos.z + 50000.0) + 1.0) * 0.5


func _create_terrain_material(biome_type: BiomeType, settings: Dictionary) -> StandardMaterial3D:
	"""Create material for any biome type using dictionary settings."""
	var material: StandardMaterial3D = StandardMaterial3D.new()
	
	# Load textures from settings
	var textures: Dictionary = settings["terrain_textures"]
	var material_props: Dictionary = settings["material_properties"]
	
	# Apply albedo texture
	if textures["albedo"]:
		var albedo_texture: Texture2D = load(textures["albedo"])
		if albedo_texture:
			material.albedo_texture = albedo_texture
			print("BiomeManager: Loaded ", settings["name"], " albedo texture")
	
	# Apply normal texture  
	if textures["normal"]:
		var normal_texture: Texture2D = load(textures["normal"])
		if normal_texture:
			material.normal_texture = normal_texture
			print("BiomeManager: Loaded ", settings["name"], " normal texture")
	
	# Apply roughness texture
	if textures["roughness"]:
		var roughness_texture: Texture2D = load(textures["roughness"])
		if roughness_texture:
			material.roughness_texture = roughness_texture
			print("BiomeManager: Loaded ", settings["name"], " roughness texture")
	
	# Apply material properties from dictionary
	material.albedo_color = material_props["albedo_color"]
	material.roughness = material_props["roughness"]
	material.metallic = material_props["metallic"]
	material.specular = material_props["specular"]
	
	# Set texture properties
	material.texture_repeat = true
	material.uv1_scale = material_props["uv_scale"]
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = material_props["triplanar_sharpness"]
	
	# Standard shadow settings
	material.flags_receive_shadows = true
	material.flags_cast_shadow = true
	
	return material


# --- DEPRECATED MATERIAL FUNCTIONS ---
# These functions are kept for reference but are no longer used.
# All materials are now created through _create_terrain_material() using the BIOME_SETTINGS dictionary.

# func _create_mountain_material() -> StandardMaterial3D:
# func _create_forest_material() -> StandardMaterial3D:
# func _create_autumn_material() -> StandardMaterial3D:
# func _create_snow_material() -> StandardMaterial3D:


func _create_default_material() -> StandardMaterial3D:
	"""Create a default material for fallback cases."""
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.5, 0.5)
	material.roughness = 0.5
	material.metallic = 0.0
	material.specular = 0.5
	material.flags_receive_shadows = true
	material.flags_cast_shadow = true
	return material


func _debug_biome_distribution() -> void:
	"""Debug function to check biome distribution across the map."""
	var biome_counts: Dictionary = {
		BiomeType.MOUNTAIN: 0,
		BiomeType.FOREST: 0,
		BiomeType.AUTUMN: 0,
		BiomeType.SNOW: 0
	}
	
	# Sample the world at regular intervals
	var sample_size: int = 50
	for x in range(sample_size):
		for z in range(sample_size):
			var world_x: float = (float(x) / sample_size - 0.5) * 200.0  # Sample 200x200 area
			var world_z: float = (float(z) / sample_size - 0.5) * 200.0
			var pos: Vector3 = Vector3(world_x, 0, world_z)
			var biome: BiomeType = get_biome_at_position(pos)
			biome_counts[biome] += 1
	
	var total_samples: int = sample_size * sample_size
	print("BiomeManager: Biome distribution (", total_samples, " samples):")
	print("  - SNOW: ", biome_counts[BiomeType.SNOW], " (", biome_counts[BiomeType.SNOW] * 100.0 / total_samples, "%)")
	print("  - FOREST: ", biome_counts[BiomeType.FOREST], " (", biome_counts[BiomeType.FOREST] * 100.0 / total_samples, "%)")
	print("  - AUTUMN: ", biome_counts[BiomeType.AUTUMN], " (", biome_counts[BiomeType.AUTUMN] * 100.0 / total_samples, "%)")
	print("  - MOUNTAIN: ", biome_counts[BiomeType.MOUNTAIN], " (", biome_counts[BiomeType.MOUNTAIN] * 100.0 / total_samples, "%)") 
