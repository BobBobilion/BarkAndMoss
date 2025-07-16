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
const BIOME_TRANSITION_DISTANCE: float = 50.0  # Distance over which biomes blend
const NOISE_SCALE_ALTITUDE: float = 0.001      # Scale for altitude noise (further reduced for much larger mountain regions)
const NOISE_SCALE_TEMPERATURE: float = 0.0008  # Scale for temperature noise (further reduced for much larger temperature zones)
const NOISE_SCALE_HUMIDITY: float = 0.001      # Scale for humidity noise (further reduced for much larger humidity zones)
const MAX_MOUNTAIN_HEIGHT: float = 80.0        # Maximum mountain height
const BASE_TERRAIN_HEIGHT: float = 10.0        # Base terrain level

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
	"res://assets/trees/UltimatePack/OBJ/CommonTree_Dead_5.obj",
	# PineTree dead variants (1-3) 
	"res://assets/trees/UltimatePack/OBJ/PineTree_Dead_1.obj",
	"res://assets/trees/UltimatePack/OBJ/PineTree_Dead_2.obj",
	"res://assets/trees/UltimatePack/OBJ/PineTree_Dead_3.obj"
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

# --- Properties ---
var biome_configs: Dictionary = {}
var noise_altitude: FastNoiseLite
var noise_temperature: FastNoiseLite
var noise_humidity: FastNoiseLite

# --- Public Methods ---

func _init():
	"""Initialize the biome manager with noise generators and biome configurations."""
	_initialize_noise_generators()
	_create_biome_configurations()
	print("BiomeManager: Initialized with ", biome_configs.size(), " biome types")


func get_biome_at_position(world_pos: Vector3) -> BiomeType:
	"""Determine the primary biome type at a given world position."""
	var altitude_factor: float = _get_altitude_factor(world_pos)
	var temperature_factor: float = _get_temperature_factor(world_pos) 
	var humidity_factor: float = _get_humidity_factor(world_pos)
	
	# Mountain biome has priority at high altitudes
	if altitude_factor > 0.7:
		return BiomeType.MOUNTAIN
	
	# Use temperature and humidity to determine other biomes
	if temperature_factor < 0.3:
		return BiomeType.SNOW
	elif temperature_factor > 0.7 and humidity_factor < 0.4:
		return BiomeType.AUTUMN
	else:
		return BiomeType.FOREST


func get_biome_blend_weights(world_pos: Vector3) -> Dictionary:
	"""Get the blend weights for all biomes at a position for smooth transitions."""
	var weights: Dictionary = {}
	var total_weight: float = 0.0
	
	# Calculate base factors
	var altitude_factor: float = _get_altitude_factor(world_pos)
	var temperature_factor: float = _get_temperature_factor(world_pos)
	var humidity_factor: float = _get_humidity_factor(world_pos)
	
	# Calculate weight for each biome based on how well it fits the conditions
	weights[BiomeType.MOUNTAIN] = max(0.0, (altitude_factor - 0.5) * 2.0)
	weights[BiomeType.SNOW] = max(0.0, (0.5 - temperature_factor) * 2.0)
	weights[BiomeType.AUTUMN] = max(0.0, (temperature_factor - 0.5) * (0.5 - humidity_factor) * 4.0)
	weights[BiomeType.FOREST] = max(0.0, 1.0 - abs(temperature_factor - 0.5) - abs(humidity_factor - 0.5))
	
	# Normalize weights
	for biome_type in weights:
		total_weight += weights[biome_type]
	
	if total_weight > 0.0:
		for biome_type in weights:
			weights[biome_type] /= total_weight
	else:
		# Fallback to forest biome if no weights
		weights = {BiomeType.FOREST: 1.0}
	
	return weights


func get_terrain_height_at_position(world_pos: Vector3) -> float:
	"""Calculate terrain height at position including biome-specific variations."""
	var base_height: float = noise_altitude.get_noise_2d(world_pos.x, world_pos.z) * BASE_TERRAIN_HEIGHT
	var altitude_factor: float = _get_altitude_factor(world_pos)
	
	# Add mountain elevation
	if altitude_factor > 0.5:
		var mountain_height: float = pow((altitude_factor - 0.5) * 2.0, 2.0) * MAX_MOUNTAIN_HEIGHT
		base_height += mountain_height
		
		# Add cliff-like features in mountains
		var cliff_noise: float = noise_temperature.get_noise_2d(world_pos.x * 0.05, world_pos.z * 0.05)
		if cliff_noise > 0.4:
			base_height += cliff_noise * 20.0
	
	return base_height


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

# --- Private Methods ---

func _initialize_noise_generators() -> void:
	"""Initialize all noise generators with different seeds and properties."""
	# Altitude noise - controls mountain distribution
	noise_altitude = FastNoiseLite.new()
	noise_altitude.seed = randi()
	noise_altitude.frequency = NOISE_SCALE_ALTITUDE
	noise_altitude.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_altitude.fractal_octaves = 4
	
	# Temperature noise - controls hot/cold regions
	noise_temperature = FastNoiseLite.new()
	noise_temperature.seed = randi() + 1000
	noise_temperature.frequency = NOISE_SCALE_TEMPERATURE 
	noise_temperature.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_temperature.fractal_octaves = 3
	
	# Humidity noise - controls wet/dry regions
	noise_humidity = FastNoiseLite.new()
	noise_humidity.seed = randi() + 2000
	noise_humidity.frequency = NOISE_SCALE_HUMIDITY
	noise_humidity.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise_humidity.fractal_octaves = 2


func _create_biome_configurations() -> void:
	"""Create and configure all biome types with their properties."""
	# Mountain Biome - high altitude, rocky, dead trees
	var mountain_config: BiomeConfig = BiomeConfig.new(BiomeType.MOUNTAIN, "Mountain")
	mountain_config.altitude_min = 0.7
	mountain_config.altitude_max = 1.0
	mountain_config.tree_density = 0.3  # Sparse tree coverage
	mountain_config.rock_density = 2.0  # High rock density
	mountain_config.tree_assets = TREE_ASSETS_DEAD
	mountain_config.rock_assets = ROCK_ASSETS_NORMAL
	mountain_config.terrain_material = _create_mountain_material()
	mountain_config.grass_color = Color(0.4, 0.4, 0.4)  # Grey rocky color
	biome_configs[BiomeType.MOUNTAIN] = mountain_config
	
	# Forest Biome - normal altitude, green trees, lush
	var forest_config: BiomeConfig = BiomeConfig.new(BiomeType.FOREST, "Forest")
	forest_config.altitude_min = 0.2
	forest_config.altitude_max = 0.8
	forest_config.tree_density = 1.5  # Dense tree coverage
	forest_config.rock_density = 0.2  # Low rock density  
	forest_config.tree_assets = TREE_ASSETS_NORMAL
	forest_config.rock_assets = ROCK_ASSETS_MOSS
	forest_config.terrain_material = _create_forest_material()
	forest_config.grass_color = Color(0.3, 0.7, 0.2)  # Rich green
	biome_configs[BiomeType.FOREST] = forest_config
	
	# Autumn Biome - normal altitude, autumn trees, warm colors
	var autumn_config: BiomeConfig = BiomeConfig.new(BiomeType.AUTUMN, "Autumn")
	autumn_config.altitude_min = 0.2
	autumn_config.altitude_max = 0.7
	autumn_config.tree_density = 1.2  # Moderate tree coverage
	autumn_config.rock_density = 0.3  # Low to moderate rock density
	autumn_config.tree_assets = TREE_ASSETS_AUTUMN
	autumn_config.rock_assets = ROCK_ASSETS_NORMAL
	autumn_config.terrain_material = _create_autumn_material()
	autumn_config.grass_color = Color(0.8, 0.6, 0.2)  # Golden autumn color
	biome_configs[BiomeType.AUTUMN] = autumn_config
	
	# Snow Biome - varied altitude, snow trees, cold
	var snow_config: BiomeConfig = BiomeConfig.new(BiomeType.SNOW, "Snow")
	snow_config.altitude_min = 0.0
	snow_config.altitude_max = 1.0
	snow_config.tree_density = 0.8  # Moderate tree coverage
	snow_config.rock_density = 0.4  # Moderate rock density
	snow_config.tree_assets = TREE_ASSETS_SNOW
	snow_config.rock_assets = ROCK_ASSETS_SNOW
	snow_config.terrain_material = _create_snow_material()
	snow_config.grass_color = Color(0.9, 0.9, 1.0)  # Snow white with blue tint
	biome_configs[BiomeType.SNOW] = snow_config


func _get_altitude_factor(world_pos: Vector3) -> float:
	"""Get altitude factor (0-1) at world position."""
	return (noise_altitude.get_noise_2d(world_pos.x, world_pos.z) + 1.0) * 0.5


func _get_temperature_factor(world_pos: Vector3) -> float:
	"""Get temperature factor (0-1) at world position."""
	return (noise_temperature.get_noise_2d(world_pos.x, world_pos.z) + 1.0) * 0.5


func _get_humidity_factor(world_pos: Vector3) -> float:
	"""Get humidity factor (0-1) at world position."""
	return (noise_humidity.get_noise_2d(world_pos.x, world_pos.z) + 1.0) * 0.5


func _create_mountain_material() -> StandardMaterial3D:
	"""Create material for mountain biome terrain."""
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.5, 0.5)  # Grey stone color
	material.roughness = 0.8
	material.metallic = 0.1
	material.specular = 0.3
	material.flags_receive_shadows = true
	material.flags_cast_shadow = true
	return material


func _create_forest_material() -> StandardMaterial3D:
	"""Create material for forest biome terrain."""
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.7, 0.2)  # Rich green
	material.roughness = 0.6
	material.metallic = 0.0
	material.specular = 0.4
	material.flags_receive_shadows = true
	material.flags_cast_shadow = true
	return material


func _create_autumn_material() -> StandardMaterial3D:
	"""Create material for autumn biome terrain."""
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.6, 0.2)  # Golden autumn color
	material.roughness = 0.5
	material.metallic = 0.0
	material.specular = 0.5
	material.flags_receive_shadows = true
	material.flags_cast_shadow = true
	return material


func _create_snow_material() -> StandardMaterial3D:
	"""Create material for snow biome terrain."""
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.9, 1.0)  # Snow white with blue tint
	material.roughness = 0.2  # Snow is relatively smooth
	material.metallic = 0.0
	material.specular = 0.8  # Snow is quite reflective
	material.flags_receive_shadows = true
	material.flags_cast_shadow = true
	return material


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