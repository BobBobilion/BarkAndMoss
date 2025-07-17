shader_type spatial;
render_mode unshaded, cull_back;

// --- Color Properties ---
uniform vec3 top_color : source_color = vec3(0.3, 0.7, 0.2);    // Forest green tip color
uniform vec3 bottom_color : source_color = vec3(0.1, 0.4, 0.1); // Darker forest base color

// --- Wind Animation Properties ---
uniform float wind_strength : hint_range(0.0, 1.0) = 0.15;      // Wind bend distance
uniform float wind_speed : hint_range(0.0, 5.0) = 1.2;          // Wind wave speed  
uniform float bend_strength : hint_range(0.0, 3.0) = 1.8;       // How much the top of the grass bends
uniform vec2 wind_direction = vec2(1.0, 0.3); // Wind movement direction (normalized vector)

// --- Terrain Adaptation Properties ---
uniform float slope_lean_factor : hint_range(0.0, 2.0) = 0.6;   // How much slope affects grass lean
uniform float height_scale : hint_range(0.0, 5.0) = 1.5;        // Height reference for color gradient

// --- Additional Visual Properties ---
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.1;        // Alpha scissor threshold
uniform float slope_darkness : hint_range(0.0, 1.0) = 0.3;      // Darkening factor on slopes

void vertex() {
	// Get the original vertex height for bend calculations
	float height = VERTEX.y;
	
	// --- Wind Sway Animation ---
	// Create layered wind effect with multiple frequencies for more natural movement
	float primary_sway = sin(TIME * wind_speed + VERTEX.x * 3.0 + VERTEX.z * 2.0) * wind_strength;
	float secondary_sway = sin(TIME * wind_speed * 1.7 + VERTEX.z * 4.0 + VERTEX.x * 1.5) * wind_strength * 0.3;
	float total_sway = primary_sway + secondary_sway;
	
	// Apply bend strength - only the top portion of grass bends significantly
	float bend_factor = clamp(height * bend_strength, 0.0, 1.0);
	total_sway *= bend_factor;
	
	// --- Terrain Slope Adaptation ---
	// Use surface normal to determine slope and lean direction
	float slope_amount = 1.0 - NORMAL.y; // 0 on flat terrain, 1 on vertical surfaces
	vec2 slope_direction = normalize(NORMAL.xz); // Direction grass should lean away from surface normal
	
	// Calculate slope lean effect (stronger at the top of grass blades)
	vec2 slope_lean = slope_direction * slope_amount * slope_lean_factor * height;
	
	// --- Apply All Transformations ---
	// Combine wind sway and slope adaptation
	VERTEX.xz += wind_direction * total_sway + slope_lean;
	
	// Pass height factor to fragment shader for color gradient
	UV.y = height / height_scale;
}

void fragment() {
	// --- Height-Based Color Gradient ---
	// Create smooth transition from bottom to top color based on vertex height
	float height_factor = clamp(UV.y + 0.5, 0.0, 1.0);
	vec3 base_color = mix(bottom_color, top_color, height_factor);
	
	// --- Slope-Based Shading ---
	// Slightly darken grass on steep slopes for more realistic shading
	float slope_factor = 1.0 - NORMAL.y;
	vec3 final_color = base_color * mix(1.0, 1.0 - slope_darkness, slope_factor);
	
	// --- Wind Variation Effect ---
	// Add subtle color variation based on wind movement for dynamic feel
	float wind_variation = sin(TIME * wind_speed * 0.5 + VERTEX.x * 2.0) * 0.05 + 1.0;
	final_color *= wind_variation;
	
	// Set final albedo color
	ALBEDO = final_color;
	
	// Basic alpha for cutout if needed (can be used with alpha scissor)
	ALPHA = 1.0;
} 