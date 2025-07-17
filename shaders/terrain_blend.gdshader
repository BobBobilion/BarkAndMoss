shader_type spatial;

// Texture samplers for each biome
uniform sampler2D forest_albedo : filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_roughness : filter_linear_mipmap, repeat_enable;

uniform sampler2D autumn_albedo : filter_linear_mipmap, repeat_enable;
uniform sampler2D autumn_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D autumn_roughness : filter_linear_mipmap, repeat_enable;

uniform sampler2D snow_albedo : filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_roughness : filter_linear_mipmap, repeat_enable;

uniform sampler2D mountain_albedo : filter_linear_mipmap, repeat_enable;
uniform sampler2D mountain_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D mountain_roughness : filter_linear_mipmap, repeat_enable;

// UV scaling for texture tiling
uniform float texture_scale : hint_range(1.0, 100.0) = 20.0;
uniform float autumn_texture_scale : hint_range(1.0, 500.0) = 200.0; // Separate scale for autumn leaves

// Blend sharpness
uniform float blend_sharpness : hint_range(0.1, 10.0) = 2.0;

// Material properties
uniform float roughness_multiplier : hint_range(0.0, 1.0) = 1.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
    // Pass world position and normal to fragment shader
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    // Get UV coordinates scaled for texture tiling
    // Use absolute world position to ensure continuous tiling
    vec2 uv = world_position.xz / texture_scale;
    vec2 autumn_uv = world_position.xz / autumn_texture_scale; // Special UV for autumn texture
    
    // Calculate triplanar UVs for steep slopes
    vec2 uv_x = world_position.zy / texture_scale;
    vec2 uv_y = world_position.xz / texture_scale;
    vec2 uv_z = world_position.xy / texture_scale;
    
    // Autumn triplanar UVs
    vec2 autumn_uv_x = world_position.zy / autumn_texture_scale;
    vec2 autumn_uv_y = world_position.xz / autumn_texture_scale;
    vec2 autumn_uv_z = world_position.xy / autumn_texture_scale;
    
    // Triplanar blending weights
    vec3 blend_weights = abs(world_normal);
    blend_weights = pow(blend_weights, vec3(blend_sharpness));
    blend_weights = blend_weights / (blend_weights.x + blend_weights.y + blend_weights.z);
    
    // Sample textures for each biome with triplanar mapping
    // Forest
    vec3 forest_col = texture(forest_albedo, uv_y).rgb * blend_weights.y +
                      texture(forest_albedo, uv_x).rgb * blend_weights.x +
                      texture(forest_albedo, uv_z).rgb * blend_weights.z;
    vec3 forest_norm = texture(forest_normal, uv_y).rgb * blend_weights.y +
                       texture(forest_normal, uv_x).rgb * blend_weights.x +
                       texture(forest_normal, uv_z).rgb * blend_weights.z;
    float forest_rough = texture(forest_roughness, uv_y).r * blend_weights.y +
                         texture(forest_roughness, uv_x).r * blend_weights.x +
                         texture(forest_roughness, uv_z).r * blend_weights.z;
    
    // Autumn - using special autumn UVs for smaller texture
    vec3 autumn_col = texture(autumn_albedo, autumn_uv_y).rgb * blend_weights.y +
                      texture(autumn_albedo, autumn_uv_x).rgb * blend_weights.x +
                      texture(autumn_albedo, autumn_uv_z).rgb * blend_weights.z;
    vec3 autumn_norm = texture(autumn_normal, autumn_uv_y).rgb * blend_weights.y +
                       texture(autumn_normal, autumn_uv_x).rgb * blend_weights.x +
                       texture(autumn_normal, autumn_uv_z).rgb * blend_weights.z;
    float autumn_rough = texture(autumn_roughness, autumn_uv_y).r * blend_weights.y +
                         texture(autumn_roughness, autumn_uv_x).r * blend_weights.x +
                         texture(autumn_roughness, autumn_uv_z).r * blend_weights.z;
    
    // Snow
    vec3 snow_col = texture(snow_albedo, uv_y).rgb * blend_weights.y +
                    texture(snow_albedo, uv_x).rgb * blend_weights.x +
                    texture(snow_albedo, uv_z).rgb * blend_weights.z;
    vec3 snow_norm = texture(snow_normal, uv_y).rgb * blend_weights.y +
                     texture(snow_normal, uv_x).rgb * blend_weights.x +
                     texture(snow_normal, uv_z).rgb * blend_weights.z;
    float snow_rough = texture(snow_roughness, uv_y).r * blend_weights.y +
                       texture(snow_roughness, uv_x).r * blend_weights.x +
                       texture(snow_roughness, uv_z).r * blend_weights.z;
    
    // Mountain
    vec3 mountain_col = texture(mountain_albedo, uv_y).rgb * blend_weights.y +
                        texture(mountain_albedo, uv_x).rgb * blend_weights.x +
                        texture(mountain_albedo, uv_z).rgb * blend_weights.z;
    vec3 mountain_norm = texture(mountain_normal, uv_y).rgb * blend_weights.y +
                         texture(mountain_normal, uv_x).rgb * blend_weights.x +
                         texture(mountain_normal, uv_z).rgb * blend_weights.z;
    float mountain_rough = texture(mountain_roughness, uv_y).r * blend_weights.y +
                           texture(mountain_roughness, uv_x).r * blend_weights.x +
                           texture(mountain_roughness, uv_z).r * blend_weights.z;
    
    // Use vertex color to determine biome blending
    // R = Forest, G = Autumn, B = Snow, A = Mountain
    vec4 biome_weights = COLOR;
    
    // No need for extreme sharpening anymore since weights are already binary
    // Just normalize to ensure they sum to 1.0
    float total_weight = biome_weights.r + biome_weights.g + biome_weights.b + biome_weights.a;
    if (total_weight > 0.0) {
        biome_weights /= total_weight;
    } else {
        biome_weights = vec4(1.0, 0.0, 0.0, 0.0); // Default to forest
    }
    
    // Blend textures based on biome weights
    vec3 final_albedo = forest_col * biome_weights.r +
                        autumn_col * biome_weights.g +
                        snow_col * biome_weights.b +
                        mountain_col * biome_weights.a;
    
    vec3 final_normal = forest_norm * biome_weights.r +
                        autumn_norm * biome_weights.g +
                        snow_norm * biome_weights.b +
                        mountain_norm * biome_weights.a;
    
    float final_roughness = forest_rough * biome_weights.r +
                            autumn_rough * biome_weights.g +
                            snow_rough * biome_weights.b +
                            mountain_rough * biome_weights.a;
    
    // Apply final values
    ALBEDO = final_albedo;
    ROUGHNESS = final_roughness * roughness_multiplier;
    
    // Convert normal map to world space
    final_normal = final_normal * 2.0 - 1.0;
    final_normal.xy *= normal_strength;
    NORMAL_MAP = normalize(final_normal);
    
    // Set metallic to 0 for all terrain
    METALLIC = 0.0;
    
    // Add some ambient occlusion based on vertex color darkness
    float ao = clamp(length(biome_weights.rgb), 0.5, 1.0);
    AO = ao;
} 