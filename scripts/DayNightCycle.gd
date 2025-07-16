class_name DayNightCycle
extends Node3D

# --- Constants ---
const CYCLE_DURATION: float = 360.0         # Full rotation in 6 minutes (360 seconds)
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
const MOON_ENERGY: float = 0.4                     # Reduced intensity to balance with sun lighting
const MOON_SHADOW_ENABLED: bool = false            # Moon doesn't cast shadows for performance
const MOON_SPHERE_RADIUS: float = 2.0              # Visual size of moon sphere (smaller than sun)
const MOON_SPHERE_COLOR: Color = Color(0.9, 0.9, 1.0)  # Pale blue-white for moon sphere

# --- Properties ---
var sun_light: DirectionalLight3D
var moon_light: DirectionalLight3D
var sun_sphere: MeshInstance3D                     # Visual representation of sun
var moon_sphere: MeshInstance3D                    # Visual representation of moon
var current_time: float = 0.0                      # Current position in the cycle (0-1)
var is_completely_dark: bool = false               # Track complete darkness state

# --- Signals ---
signal day_started
signal night_started
signal complete_darkness_started
signal complete_darkness_ended


func _ready() -> void:
	"""Initialize the day/night cycle system."""
	print("DayNightCycle: Initializing sun and moon system...")
	_create_light_sources()
	_position_lights()
	
	# Debug: Verify sun configuration for terrain illumination
	print("DayNightCycle: Sun configuration - Energy: %.1f, Color: %s, Shadows: %s" % [SUN_ENERGY, SUN_COLOR, SUN_SHADOW_ENABLED])
	print("DayNightCycle: Moon configuration - Energy: %.1f, Color: %s" % [MOON_ENERGY, MOON_COLOR])
	
	print("DayNightCycle: Sun and moon system ready")


func _process(delta: float) -> void:
	"""Update the sun and moon positions each frame."""
	# Advance time
	current_time += delta / CYCLE_DURATION
	
	# Keep time in 0-1 range (wrap around after full cycle)
	if current_time >= 1.0:
		current_time -= 1.0
	
	# Update light positions
	_update_light_positions()
	
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
	
	# Convert elevation to height factor (0 to 1, where 1 is directly overhead)
	var sun_height_factor: float = max(0.0, sun_elevation)
	var moon_height_factor: float = max(0.0, moon_elevation)
	
	# Apply intensity based on height (lights fade out as they approach horizon)
	sun_light.light_energy = SUN_ENERGY * sun_height_factor
	moon_light.light_energy = MOON_ENERGY * moon_height_factor
	
	# Enable/disable lights when they're below horizon for performance and complete darkness
	var sun_is_up: bool = sun_height_factor > 0.01
	var moon_is_up: bool = moon_height_factor > 0.01
	
	sun_light.visible = sun_is_up
	moon_light.visible = moon_is_up
	
	# Track complete darkness state and emit signals
	var current_darkness_state: bool = not sun_is_up and not moon_is_up
	
	if current_darkness_state and not is_completely_dark:
		is_completely_dark = true
		complete_darkness_started.emit()
	elif not current_darkness_state and is_completely_dark:
		is_completely_dark = false
		complete_darkness_ended.emit()
	
	# Control sphere visibility and brightness based on height
	sun_sphere.visible = sun_is_up
	moon_sphere.visible = moon_is_up
	
	# Adjust sphere material brightness based on height for smooth transitions
	if sun_sphere.visible and sun_sphere.material_override:
		var sun_mat: StandardMaterial3D = sun_sphere.material_override as StandardMaterial3D
		if sun_mat:
			# Fade the emission intensity as sun approaches horizon
			sun_mat.emission_energy = 1.5 * sun_height_factor
	
	if moon_sphere.visible and moon_sphere.material_override:
		var moon_mat: StandardMaterial3D = moon_sphere.material_override as StandardMaterial3D
		if moon_mat:
			# Fade the emission intensity as moon approaches horizon
			moon_mat.emission_energy = 0.5 * moon_height_factor


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