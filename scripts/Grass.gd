extends MultiMeshInstance3D

# --- Imports ---
const BiomeManagerClass = preload("res://scripts/BiomeManager.gd")

# --- Constants ---
const GRASS_BLADE_COUNT: int = 150         # Number of grass blades per clump
const GRASS_VARIATION_RANGE: float = 0.4   # Random height variation (±40%)
const GRASS_SPREAD_RADIUS: float = 0.7     # Radius of grass clump spread
const GRASS_SCALE: float = 0.2             # Overall scale of the grass blades (1.0 / 5.0)

# --- Export Properties ---
@export var biome_type: BiomeManagerClass.BiomeType = BiomeManagerClass.BiomeType.FOREST
@export var grass_density: float = 1.0      # Density multiplier for this clump
@export var noise_scale: float = 20.0       # Noise scale for color variation in the shader
@export var color_variation: float = 0.1    # Color variation amount

# --- Private Properties ---
var grass_material: ShaderMaterial
var placement_noise: FastNoiseLite
var color_noise: FastNoiseLite

# --- Signals ---
signal grass_clump_ready    # Emitted when grass clump is fully initialized


# --- Engine Callbacks ---

func _ready() -> void:
	"""Initialize the grass clump with proper mesh, material, and placement."""
	_initialize_noise_generator()
	_setup_grass_mesh()
	_setup_grass_material()
	_generate_grass_instances()

	grass_clump_ready.emit()


# --- Private Methods ---

func _initialize_noise_generator() -> void:
	"""Set up noise generators for placement and color variation."""
	placement_noise = FastNoiseLite.new()
	placement_noise.seed = randi()
	placement_noise.frequency = 0.8
	placement_noise.noise_type = FastNoiseLite.TYPE_PERLIN

	color_noise = FastNoiseLite.new()
	color_noise.seed = randi()
	color_noise.frequency = 0.5


func _setup_grass_mesh() -> void:
	"""Create and configure the MultiMesh for grass blade instances."""
	# Create MultiMesh if it doesn't exist
	if not multimesh:
		multimesh = MultiMesh.new()

	# Set up MultiMesh properties
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = GRASS_BLADE_COUNT

	# Load the grass mesh from the new assets
	var glb_scene = load("res://assets/environment/grassMeshes/grass.glb")
	if glb_scene:
		var mesh_instance = glb_scene.instantiate().get_child(0)
		if mesh_instance is MeshInstance3D:
			multimesh.mesh = mesh_instance.mesh

	# Note: Grass is purely visual and doesn't need collision detection


func _setup_grass_material() -> void:
	"""Create and apply the grass shader material."""
	# Create shader material
	grass_material = ShaderMaterial.new()

	# Load the new grass shader
	var grass_shader: Shader = load("res://assets/environment/grassShader/grass.gdshader")
	if grass_shader:
		grass_material.shader = grass_shader

		# Create noise texture for color variation
		var noise_texture := NoiseTexture2D.new()
		noise_texture.noise = color_noise

		# Set shader parameters
		grass_material.set_shader_parameter("noise", noise_texture)
		grass_material.set_shader_parameter("noiseScale", noise_scale)

		# Set biome-specific properties
		_configure_material_for_biome()

		# Apply material to MultiMesh
		material_override = grass_material
		print("Grass: New shader material applied successfully")
	else:
		printerr("Grass: Failed to load grass shader from new assets!")


func _configure_material_for_biome() -> void:
	"""Configure material properties based on the biome type."""
	var color1: Color
	var color2: Color

	match biome_type:
		BiomeManagerClass.BiomeType.FOREST:
			# Rich forest green colors
			color1 = Color(0.2, 0.5, 0.15)
			color2 = Color(0.05, 0.2, 0.05)
		BiomeManagerClass.BiomeType.AUTUMN:
			# Autumn yellowing grass
			color1 = Color(0.4, 0.4, 0.1)
			color2 = Color(0.2, 0.2, 0.05)
		BiomeManagerClass.BiomeType.SNOW:
			# Sparse, winter grass with snow tinting
			color1 = Color(0.3, 0.4, 0.2)
			color2 = Color(0.1, 0.2, 0.05)
		BiomeManagerClass.BiomeType.MOUNTAIN:
			# Hardy mountain grass
			color1 = Color(0.3, 0.5, 0.2)
			color2 = Color(0.1, 0.2, 0.05)

	grass_material.set_shader_parameter("color", color1)
	grass_material.set_shader_parameter("color2", color2)


func _generate_grass_instances() -> void:
	"""Generate individual grass blade instances with variation."""
	var instance_count: int = int(GRASS_BLADE_COUNT * grass_density)
	multimesh.instance_count = instance_count
	
	for i in range(instance_count):
		var transform: Transform3D = _create_grass_blade_transform(i)
		multimesh.set_instance_transform(i, transform)


func _create_grass_blade_transform(blade_index: int) -> Transform3D:
	"""Create a transform for an individual grass blade with natural variation."""
	var transform: Transform3D = Transform3D.IDENTITY
	
	# --- Position Variation ---
	# Distribute blades within the clump radius using noise for natural clustering
	var angle: float = randf() * TAU
	var distance: float = sqrt(randf()) * GRASS_SPREAD_RADIUS  # Square root for uniform distribution
	
	# Add noise-based clustering
	var noise_offset: Vector2 = Vector2(
		placement_noise.get_noise_2d(blade_index * 0.1, 0.0) * 0.5,
		placement_noise.get_noise_2d(0.0, blade_index * 0.1) * 0.5
	)
	
	var blade_position: Vector3 = Vector3(
		cos(angle) * distance + noise_offset.x,
		0.0,  # Will be adjusted to terrain height
		sin(angle) * distance + noise_offset.y
	)
	
	# --- Rotation Variation ---
	# Random Y rotation for natural blade orientation
	var y_rotation: float = randf() * TAU
	transform = transform.rotated(Vector3.UP, y_rotation)
	
	# Slight random tilt for natural look
	var tilt_amount: float = randf_range(-0.1, 0.1)
	transform = transform.rotated(Vector3.RIGHT, tilt_amount)
	
	# --- Scale Variation ---
	# Vary height and width slightly for natural diversity
	var height_variation: float = 1.0 + randf_range(-GRASS_VARIATION_RANGE, GRASS_VARIATION_RANGE)
	var width_variation: float = randf_range(0.8, 1.2)
	
	transform = transform.scaled(Vector3(width_variation, height_variation, width_variation) * GRASS_SCALE)
	
	# --- Apply Position ---
	transform.origin = blade_position
	
	return transform


func _connect_to_wind_system() -> void:
	"""Connect to any global wind or weather systems if they exist."""
	# This function is now empty as the new shader does not support wind.
	# Kept for compatibility with any scripts that might call it.
	pass


# --- Public Methods ---

func set_biome_type(new_biome_type: BiomeManagerClass.BiomeType) -> void:
	"""Update the biome type and reconfigure material accordingly."""
	biome_type = new_biome_type
	if grass_material:
		_configure_material_for_biome()


func set_wind_intensity(new_intensity: float) -> void:
	"""Update the wind intensity for this grass clump."""
	# This function is now empty as the new shader does not support wind.
	# Kept for compatibility with any scripts that might call it.
	pass


func apply_seasonal_variation(season_factor: float) -> void:
	"""Apply seasonal color changes to the grass (0.0 = spring, 1.0 = winter)."""
	if not grass_material:
		return
	
	# Interpolate colors based on season
	var spring_top: Vector3 = Vector3(0.3, 0.8, 0.2)     # Vibrant green
	var winter_top: Vector3 = Vector3(0.4, 0.5, 0.3)     # Muted green
	var spring_bottom: Vector3 = Vector3(0.1, 0.5, 0.1)  # Dark green
	var winter_bottom: Vector3 = Vector3(0.2, 0.3, 0.1)  # Brown-green
	
	var current_top: Vector3 = spring_top.lerp(winter_top, season_factor)
	var current_bottom: Vector3 = spring_bottom.lerp(winter_bottom, season_factor)
	
	grass_material.set_shader_parameter("color", current_top)
	grass_material.set_shader_parameter("color2", current_bottom)


# --- Signal Handlers ---

func _on_wind_changed(wind_direction: Vector2, wind_strength: float) -> void:
	"""Handle global wind changes and update grass accordingly."""
	# This function is now empty as the new shader does not support wind.
	pass


# --- Debug Methods ---

func _get_debug_info() -> Dictionary:
	"""Return debug information about this grass clump."""
	return {
		"biome_type": biome_type,
		"blade_count": multimesh.instance_count if multimesh else 0,
		"wind_intensity": 0.0, # No wind intensity in new shader
		"grass_density": grass_density,
		"position": global_position
	} 
