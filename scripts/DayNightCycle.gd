class_name DayNightCycle
extends Node3D

# --- Constants ---
const CYCLE_DURATION: float = 60.0          # Full rotation in 1 minute (60 seconds) - changed from 360
const LIGHT_RADIUS: float = 50.0            # Distance from center for sun/moon orbit
const LIGHT_HEIGHT: float = 30.0            # Height above terrain for the lights

# Sun properties
const SUN_COLOR: Color = Color(1.0, 0.9, 0.7)     # Warm yellow light
const SUN_ENERGY: float = 1.5                      # Reduced intensity to prevent overly bright models
const SUN_SHADOW_ENABLED: bool = true              # Sun casts shadows
const SUN_SPHERE_RADIUS: float = 3.0               # Visual size of sun sphere
const SUN_SPHERE_COLOR: Color = Color(1.0, 0.8, 0.4)  # Bright yellow for sun sphere

# Moon properties  
const MOON_COLOR: Color = Color(0.7, 0.8, 1.0)    # Cool blue light
const MOON_ENERGY: float = 0.8                     # Increased from 0.4 to make night less dark
const MOON_SHADOW_ENABLED: bool = false            # Moon doesn't cast shadows for performance
const MOON_SPHERE_RADIUS: float = 2.0              # Visual size of moon sphere (smaller than sun)
const MOON_SPHERE_COLOR: Color = Color(0.9, 0.9, 1.0)  # Pale blue-white for moon sphere

# --- Exportable Sky and Atmosphere Colors ---
@export_group("Sky Colors")
@export var day_sky_color: Color = Color(0.3, 0.6, 1.0)        # Light blue sky
@export var dawn_dusk_sky_color: Color = Color(1.0, 0.5, 0.3)  # Orange/pink sunset
@export var night_sky_color: Color = Color(0.05, 0.1, 0.15)    # Dark blue night

@export_group("Ground Horizon Colors")
@export var day_ground_color: Color = Color(0.6, 0.7, 0.8)      # Light ground horizon
@export var dawn_dusk_ground_color: Color = Color(0.8, 0.4, 0.2) # Warm horizon
@export var night_ground_color: Color = Color(0.1, 0.15, 0.2)   # Dark ground

@export_group("Fog Colors")
@export var day_fog_color: Color = Color(0.7, 0.8, 0.9)
@export var dawn_dusk_fog_color: Color = Color(0.9, 0.6, 0.4)
@export var night_fog_color: Color = Color(0.1, 0.15, 0.2)

@export_group("Fog Settings")
@export var fog_depth_begin: float = 100.0        # Distance where fog starts
@export var fog_depth_end: float = 500.0          # Distance where fog reaches full density
@export var fog_density: float = 0.002            # Base fog density

@export_group("Brightness Settings")
@export var day_brightness: float = 1.0
@export var twilight_brightness: float = 0.8      # During dawn/dusk transitions
@export var night_brightness: float = 0.7         # Night scene brightness

@export_group("Ambient Light Settings")
@export var day_ambient_energy: float = 0.3
@export var twilight_ambient_energy: float = 0.35  # Enhanced during transitions
@export var night_ambient_energy: float = 0.4     # Night ambient strength

@export_group("Sun/Moon Positioning")
@export var horizon_start_elevation: float = -0.5   # How far below horizon to start appearing (more negative = lower)
@export var sphere_visibility_elevation: float = -0.3  # When spheres become visible
@export var complete_darkness_elevation: float = -0.6  # When complete darkness occurs

# --- Properties ---
var sun_light: DirectionalLight3D
var moon_light: DirectionalLight3D
var sun_sphere: MeshInstance3D                     # Visual representation of sun
var moon_sphere: MeshInstance3D                    # Visual representation of moon
var current_time: float = 0.0                      # Current position in the cycle (0-1)
var is_completely_dark: bool = false               # Track complete darkness state
var world_environment: WorldEnvironment = null     # Reference to WorldEnvironment node
var environment: Environment = null                # Reference to Environment resource

# --- Signals ---
signal day_started
signal night_started
signal complete_darkness_started
signal complete_darkness_ended


func _ready() -> void:
	"""Initialize the day/night cycle system."""
	print("DayNightCycle: Initializing sun and moon system...")
	
	# Add to group for easy finding by other nodes
	add_to_group("day_night_cycle")
	
	# Find WorldEnvironment in parent or siblings
	_find_world_environment()
	
	_create_light_sources()
	_position_lights()
	
	# Set initial time to sunrise (0.25 = 6 AM)
	current_time = 0.25
	
	# Debug: Verify sun configuration for terrain illumination
	print("DayNightCycle: Sun configuration - Energy: %.1f, Color: %s, Shadows: %s" % [SUN_ENERGY, SUN_COLOR, SUN_SHADOW_ENABLED])
	print("DayNightCycle: Moon configuration - Energy: %.1f, Color: %s" % [MOON_ENERGY, MOON_COLOR])
	
	if world_environment:
		print("DayNightCycle: Environment found and configured")
		_setup_environment()
	else:
		print("DayNightCycle: Warning - No WorldEnvironment found, sky transitions will not work")
	
	print("DayNightCycle: Sun and moon system ready")


func _find_world_environment() -> void:
	"""Find the WorldEnvironment node in the scene tree."""
	# Check parent
	var parent = get_parent()
	if parent:
		world_environment = parent.find_child("WorldEnvironment", false) as WorldEnvironment
		
	# Check if we found it
	if world_environment:
		environment = world_environment.environment
	else:
		# Try to find it in the entire scene tree (less efficient but more thorough)
		var root = get_tree().get_root()
		var world_env_nodes = _find_nodes_of_type(root, "WorldEnvironment")
		if world_env_nodes.size() > 0:
			world_environment = world_env_nodes[0] as WorldEnvironment
			environment = world_environment.environment


func _find_nodes_of_type(node: Node, type_name: String) -> Array[Node]:
	"""Recursively find all nodes of a specific type."""
	var found_nodes: Array[Node] = []
	
	if node.get_class() == type_name:
		found_nodes.append(node)
	
	for child in node.get_children():
		found_nodes.append_array(_find_nodes_of_type(child, type_name))
	
	return found_nodes


func _setup_environment() -> void:
	"""Configure the environment for day/night cycle."""
	if not environment:
		return
		
	# Enable fog if not already enabled - starting disabled for less foggy world
	environment.fog_enabled = false  # Changed to false - enable manually if desired
	environment.fog_light_color = day_fog_color
	environment.fog_light_energy = 0.5  # Reduced from 1.0
	environment.fog_sun_scatter = 0.2   # Reduced from 0.5
	environment.fog_density = fog_density
	environment.fog_depth_begin = fog_depth_begin
	environment.fog_depth_end = fog_depth_end
	
	# Set initial ambient light based on starting time
	environment.ambient_light_color = day_sky_color
	environment.ambient_light_energy = day_ambient_energy
	
	# Ensure we're using a sky for background
	if environment.background_mode != Environment.BG_SKY:
		# Keep current background mode but we'll adjust colors
		pass


func _process(delta: float) -> void:
	"""Update the sun and moon positions each frame."""
	# Advance time
	current_time += delta / CYCLE_DURATION
	
	# Keep time in 0-1 range (wrap around after full cycle)
	if current_time >= 1.0:
		current_time -= 1.0
	
	# Update light positions
	_update_light_positions()
	
	# Update sky and atmosphere
	_update_sky_and_atmosphere()
	
	# Check for day/night transitions
	_check_transitions()


func _create_light_sources() -> void:
	"""Create the sun and moon DirectionalLight3D nodes with their visual representations."""
	# Create sun light
	sun_light = DirectionalLight3D.new()
	sun_light.name = "SunLight"
	sun_light.light_color = SUN_COLOR
	sun_light.light_energy = SUN_ENERGY
	sun_light.shadow_enabled = SUN_SHADOW_ENABLED
	
	# Configure enhanced sun shadow quality for better terrain illumination
	if SUN_SHADOW_ENABLED:
		sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun_light.directional_shadow_max_distance = 150.0  # Increased for larger terrain coverage
		sun_light.shadow_bias = 0.05  # Reduced bias for sharper shadows
		sun_light.shadow_normal_bias = 0.1  # Add normal bias to reduce shadow acne
		sun_light.shadow_blur = 1.0  # Slight blur for softer shadows
	
	add_child(sun_light)
	
	# Create moon light
	moon_light = DirectionalLight3D.new()
	moon_light.name = "MoonLight"
	moon_light.light_color = MOON_COLOR
	moon_light.light_energy = MOON_ENERGY
	moon_light.shadow_enabled = MOON_SHADOW_ENABLED
	
	add_child(moon_light)
	
	# Create sun sphere visual
	sun_sphere = MeshInstance3D.new()
	sun_sphere.name = "SunSphere"
	
	# Create sun sphere mesh
	var sun_mesh: SphereMesh = SphereMesh.new()
	sun_mesh.radius = SUN_SPHERE_RADIUS
	sun_mesh.height = SUN_SPHERE_RADIUS * 2.0
	sun_sphere.mesh = sun_mesh
	
	# Create sun material with emission for glowing effect
	var sun_material: StandardMaterial3D = StandardMaterial3D.new()
	sun_material.albedo_color = SUN_SPHERE_COLOR
	sun_material.emission_enabled = true
	sun_material.emission = SUN_SPHERE_COLOR * 0.8  # Bright glow
	sun_material.emission_energy = 1.5
	sun_material.flags_unshaded = true  # Always bright, not affected by lighting
	sun_material.flags_do_not_receive_shadows = true
	sun_material.flags_cast_shadow = false  # Sun sphere doesn't cast shadows
	sun_sphere.material_override = sun_material
	
	add_child(sun_sphere)
	
	# Create moon sphere visual
	moon_sphere = MeshInstance3D.new()
	moon_sphere.name = "MoonSphere"
	
	# Create moon sphere mesh
	var moon_mesh: SphereMesh = SphereMesh.new()
	moon_mesh.radius = MOON_SPHERE_RADIUS
	moon_mesh.height = MOON_SPHERE_RADIUS * 2.0
	moon_sphere.mesh = moon_mesh
	
	# Create moon material with subtle emission
	var moon_material: StandardMaterial3D = StandardMaterial3D.new()
	moon_material.albedo_color = MOON_SPHERE_COLOR
	moon_material.emission_enabled = true
	moon_material.emission = MOON_SPHERE_COLOR * 0.3  # Subtle glow
	moon_material.emission_energy = 0.5
	moon_material.flags_unshaded = true  # Always visible, not affected by lighting
	moon_material.flags_do_not_receive_shadows = true
	moon_material.flags_cast_shadow = false  # Moon sphere doesn't cast shadows
	moon_sphere.material_override = moon_material
	
	add_child(moon_sphere)
	
	print("DayNightCycle: Sun and moon lights with visual spheres created")


func _position_lights() -> void:
	"""Position the sun and moon 180 degrees apart on their orbital circle."""
	_update_light_positions()


func _update_light_positions() -> void:
	"""Update sun and moon positions based on current time."""
	# Calculate angles (sun and moon are 180 degrees apart)
	var sun_angle: float = current_time * TAU  # Full rotation (0 to 2π)
	var moon_angle: float = sun_angle + PI     # Moon is 180 degrees behind sun
	
	# Calculate sun position for visual sphere (not for lighting)
	var sun_x: float = cos(sun_angle) * LIGHT_RADIUS
	var sun_y: float = sin(sun_angle) * LIGHT_RADIUS + LIGHT_HEIGHT
	var sun_z: float = 0.0
	
	# Calculate moon position for visual sphere (not for lighting)
	var moon_x: float = cos(moon_angle) * LIGHT_RADIUS  
	var moon_y: float = sin(moon_angle) * LIGHT_RADIUS + LIGHT_HEIGHT
	var moon_z: float = 0.0
	
	# Set sphere positions to match orbital positions
	sun_sphere.position = Vector3(sun_x, sun_y, sun_z)
	moon_sphere.position = Vector3(moon_x, moon_y, moon_z)
	
	# For DirectionalLight3D, we need to set rotation, not position
	# Calculate the angle to point toward the ground (downward direction)
	var sun_elevation: float = sin(sun_angle)  # -1 to 1, where 1 is directly overhead
	var moon_elevation: float = sin(moon_angle)
	
	# Convert elevation to rotation angles
	# When elevation is 1 (overhead), we want the light pointing straight down (90 degrees)
	# When elevation is 0 (horizon), we want the light pointing horizontal (0 degrees)
	var sun_x_rotation: float = -sun_elevation * (PI / 2)  # 0 to -90 degrees
	var moon_x_rotation: float = -moon_elevation * (PI / 2)
	
	# Set directional light rotations (position doesn't matter for DirectionalLight3D)
	sun_light.rotation.x = sun_x_rotation
	sun_light.rotation.y = 0.0  # Keep pointing along X-Z plane
	sun_light.rotation.z = 0.0
	
	moon_light.rotation.x = moon_x_rotation
	moon_light.rotation.y = 0.0
	moon_light.rotation.z = 0.0
	
	# Position lights at origin (position doesn't affect DirectionalLight3D lighting)
	sun_light.position = Vector3.ZERO
	moon_light.position = Vector3.ZERO
	
	# Adjust light intensity based on height (lights are dimmer when below horizon)
	_adjust_light_intensity()


func _adjust_light_intensity() -> void:
	"""Adjust light intensity and sphere visibility based on height above horizon."""
	# Calculate angles for current time
	var sun_angle: float = current_time * TAU
	var moon_angle: float = sun_angle + PI
	
	# Calculate elevation (-1 to 1, where 1 is directly overhead)
	var sun_elevation: float = sin(sun_angle)
	var moon_elevation: float = sin(moon_angle)
	
	# Convert elevation to height factor with smooth transitions below horizon
	# Allow lights to be visible even when below horizon for natural rising/setting
	var sun_height_factor: float = smoothstep(horizon_start_elevation, 1.0, sun_elevation)  # Start fading in at horizon_start_elevation
	var moon_height_factor: float = smoothstep(horizon_start_elevation, 1.0, moon_elevation)  # Start fading in at horizon_start_elevation
	
	# Apply intensity based on height with smoother curves
	sun_light.light_energy = SUN_ENERGY * sun_height_factor
	moon_light.light_energy = MOON_ENERGY * moon_height_factor
	
	# Enable/disable lights with lower thresholds so they appear below horizon
	var sun_is_up: bool = sun_height_factor > 0.01  # Very low threshold for early appearance
	var moon_is_up: bool = moon_height_factor > 0.01  # Very low threshold for early appearance
	
	sun_light.visible = sun_is_up
	moon_light.visible = moon_is_up
	
	# Track complete darkness state - only when both are well below horizon
	var current_darkness_state: bool = sun_elevation < complete_darkness_elevation and moon_elevation < complete_darkness_elevation
	
	if current_darkness_state and not is_completely_dark:
		is_completely_dark = true
		complete_darkness_started.emit()
	elif not current_darkness_state and is_completely_dark:
		is_completely_dark = false
		complete_darkness_ended.emit()
	
	# Control sphere visibility with early appearance below horizon
	sun_sphere.visible = sun_elevation > sphere_visibility_elevation  # Show sphere when approaching horizon
	moon_sphere.visible = moon_elevation > sphere_visibility_elevation  # Show sphere when approaching horizon
	
	# Adjust sphere material brightness based on height for smooth transitions
	if sun_sphere.visible and sun_sphere.material_override:
		var sun_mat: StandardMaterial3D = sun_sphere.material_override as StandardMaterial3D
		if sun_mat:
			# Fade the emission intensity as sun approaches horizon
			var sphere_brightness = max(0.1, sun_height_factor)  # Minimum brightness for visibility
			sun_mat.emission_energy = 1.5 * sphere_brightness
	
	if moon_sphere.visible and moon_sphere.material_override:
		var moon_mat: StandardMaterial3D = moon_sphere.material_override as StandardMaterial3D
		if moon_mat:
			# Fade the emission intensity as moon approaches horizon
			var sphere_brightness = max(0.1, moon_height_factor)  # Minimum brightness for visibility
			moon_mat.emission_energy = 0.5 * sphere_brightness


func _update_sky_and_atmosphere() -> void:
	"""Update sky colors, fog, and atmosphere based on sun position."""
	if not environment:
		return
		
	# Calculate sun height for blending
	var sun_angle: float = current_time * TAU
	var sun_height: float = sin(sun_angle)  # -1 to 1
	var sun_height_normalized: float = (sun_height + 1.0) * 0.5  # 0 to 1
	
	# Create smooth transitions based on sun height
	var sun_transition = smoothstep(-0.4, 0.4, sun_height)  # Smooth curve from -0.4 to 0.4 sun height
	
	# Determine if we're in dawn/dusk transition periods
	var is_dawn_dusk = abs(sun_height) < 0.4  # Transition zone when sun is near horizon
	
	# Calculate blend factors for fog density
	var night_factor: float = smoothstep(-0.1, -0.5, sun_height)
	
	# Update background color with smooth continuous transitions (matching ambient light logic)
	if environment.background_mode == Environment.BG_COLOR:
		var sky_color: Color
		
		if is_dawn_dusk:
			# During dawn/dusk, blend between day and night with special twilight effects
			var twilight_boost = 1.0 - abs(sun_height / 0.4)  # 1.0 at horizon, 0.0 at edges
			
			if sun_height >= 0:
				# Dawn/morning or evening - blend day with twilight colors
				sky_color = day_sky_color.lerp(dawn_dusk_sky_color, twilight_boost * 0.8)
			else:
				# Dusk/night approach - blend twilight with night colors
				sky_color = dawn_dusk_sky_color.lerp(night_sky_color, -sun_height / 0.4)
		else:
			# Pure day or pure night - simple interpolation
			sky_color = night_sky_color.lerp(day_sky_color, sun_transition)
		
		environment.background_color = sky_color
	
	# Update ambient light with smooth continuous transitions
	var ambient_color: Color
	var ambient_energy: float
	
	if is_dawn_dusk:
		# During dawn/dusk, blend between day and night with special twilight boost
		var twilight_boost = 1.0 - abs(sun_height / 0.4)  # 1.0 at horizon, 0.0 at edges
		
		# Color transitions
		if sun_height >= 0:
			# Dawn/morning or evening - blend day with twilight colors
			ambient_color = day_sky_color.lerp(dawn_dusk_sky_color, twilight_boost * 0.6)
		else:
			# Dusk/night approach - blend twilight with night colors
			ambient_color = dawn_dusk_sky_color.lerp(night_sky_color, -sun_height / 0.4)
		
		# Energy transitions with twilight boost
		var base_energy = lerp(night_ambient_energy, day_ambient_energy, sun_transition)
		ambient_energy = base_energy + (twilight_ambient_energy - base_energy) * twilight_boost
	else:
		# Pure day or pure night - simple interpolation
		ambient_color = night_sky_color.lerp(day_sky_color, sun_transition)
		ambient_energy = lerp(night_ambient_energy, day_ambient_energy, sun_transition)
	
	environment.ambient_light_color = ambient_color
	environment.ambient_light_energy = ambient_energy
	
	# Update fog with smooth continuous transitions
	var fog_color: Color
	
	if is_dawn_dusk:
		# During dawn/dusk, blend fog colors smoothly
		var twilight_boost = 1.0 - abs(sun_height / 0.4)
		
		if sun_height >= 0:
			# Dawn/morning or evening - blend day with twilight fog colors
			fog_color = day_fog_color.lerp(dawn_dusk_fog_color, twilight_boost * 0.7)
		else:
			# Dusk/night approach - blend twilight with night fog colors
			fog_color = dawn_dusk_fog_color.lerp(night_fog_color, -sun_height / 0.4)
	else:
		# Pure day or pure night - simple interpolation
		fog_color = night_fog_color.lerp(day_fog_color, sun_transition)
		
	environment.fog_light_color = fog_color
	environment.fog_density = fog_density * (1.0 + night_factor * 0.2)  # Slightly denser fog at night
	
	# Update brightness/exposure with smooth transitions
	var brightness: float
	
	if is_dawn_dusk:
		# During dawn/dusk, use special twilight brightness with smooth blending
		var twilight_boost = 1.0 - abs(sun_height / 0.4)
		var base_brightness = lerp(night_brightness, day_brightness, sun_transition)
		brightness = base_brightness + (twilight_brightness - base_brightness) * twilight_boost
	else:
		# Smooth interpolation between day and night brightness
		brightness = lerp(night_brightness, day_brightness, sun_transition)
		
	environment.adjustment_enabled = true
	environment.adjustment_brightness = brightness
	
	# Update glow intensity based on time of day with smooth transitions
	if environment.glow_enabled:
		# Use sun_height to determine glow - negative values = night, positive = day
		var night_glow_factor = smoothstep(0.2, -0.2, sun_height)  # 0 at day, 1 at night
		environment.glow_intensity = lerp(0.4, 0.8, night_glow_factor)  # 0.4 for day, 0.8 for night
		environment.glow_bloom = lerp(0.2, 0.6, night_glow_factor)     # 0.2 for day, 0.6 for night


func _check_transitions() -> void:
	"""Check for day/night transitions and emit signals."""
	# Day starts when sun is rising (around 0.0 in the cycle)
	# Night starts when sun is setting (around 0.5 in the cycle)
	
	var previous_time: float = current_time - get_process_delta_time() / CYCLE_DURATION
	if previous_time < 0.0:
		previous_time += 1.0
	
	# Check for day start (sun rising)
	if previous_time > 0.9 and current_time <= 0.1:
		day_started.emit()
	
	# Check for night start (sun setting)  
	if previous_time > 0.4 and current_time >= 0.5 and previous_time < 0.5:
		night_started.emit()


func get_current_time_of_day() -> float:
	"""Returns the current time as a value between 0.0 and 1.0."""
	return current_time


func is_day_time() -> bool:
	"""Returns true if it's currently day time (sun is up)."""
	return sun_light.visible and sun_light.light_energy > 0.1


func is_night_time() -> bool:
	"""Returns true if it's currently night time (moon is up)."""
	return moon_light.visible and moon_light.light_energy > 0.1


func is_complete_darkness() -> bool:
	"""Returns true if both sun and moon are below horizon (complete darkness)."""
	return is_completely_dark


func get_sun_light() -> DirectionalLight3D:
	"""Returns reference to the sun light for external access."""
	return sun_light


func get_moon_light() -> DirectionalLight3D:
	"""Returns reference to the moon light for external access."""
	return moon_light 


func set_time_of_day(time: float) -> void:
	"""Set the current time of day (0.0 to 1.0)."""
	current_time = clamp(time, 0.0, 1.0)
	_update_light_positions()
	_update_sky_and_atmosphere()


func get_phase_of_day() -> String:
	"""Returns a string describing the current phase of day."""
	var sun_angle: float = current_time * TAU
	var sun_height: float = sin(sun_angle)
	
	if sun_height > 0.5:
		return "day"
	elif sun_height > 0.0:
		return "morning" if current_time < 0.5 else "evening"
	elif sun_height > -0.3:
		return "dawn" if current_time < 0.5 else "dusk"
	else:
		return "night" 
