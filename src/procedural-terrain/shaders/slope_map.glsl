#[compute]
#version 450

// Compute shader for generating Slope Map
// Calculates local variation of terrain height along x and y directions
// Based on paper equation (3) with parameterized distance

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Input height map (read-only)
layout(set = 0, binding = 0) uniform texture2D height_map;
layout(set = 0, binding = 1) uniform sampler height_sampler;

// Output slope map (write-only)
layout(set = 0, binding = 2, r32f) uniform restrict writeonly image2D slope_map;

// Parameters
layout(set = 0, binding = 3, std140) uniform SlopeParams {
    vec2 map_size;      // Width, Height of the map
    float distance;     // Parameterized distance for slope calculation (default: 12 pixels)
    float height_scale; // Height scale factor
};

void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    
    // Check bounds
    if (pixel.x >= int(map_size.x) || pixel.y >= int(map_size.y)) {
        return;
    }
    
    vec2 uv = (vec2(pixel) + 0.5) / map_size;
    
    // Sample center height
    float center_height = texture(sampler2D(height_map, height_sampler), uv).r * height_scale;
    
    // Sample heights at distance offsets (x and y directions)
    float dist_normalized = distance / map_size.x; // Normalize distance to UV space
    
    // X direction slope
    vec2 uv_x_plus = uv + vec2(dist_normalized, 0.0);
    vec2 uv_x_minus = uv - vec2(dist_normalized, 0.0);
    uv_x_plus = clamp(uv_x_plus, vec2(0.0), vec2(1.0));
    uv_x_minus = clamp(uv_x_minus, vec2(0.0), vec2(1.0));
    
    float height_x_plus = texture(sampler2D(height_map, height_sampler), uv_x_plus).r * height_scale;
    float height_x_minus = texture(sampler2D(height_map, height_sampler), uv_x_minus).r * height_scale;
    float slope_x = abs(height_x_plus - height_x_minus) / (2.0 * distance);
    
    // Y direction slope
    vec2 uv_y_plus = uv + vec2(0.0, dist_normalized);
    vec2 uv_y_minus = uv - vec2(0.0, dist_normalized);
    uv_y_plus = clamp(uv_y_plus, vec2(0.0), vec2(1.0));
    uv_y_minus = clamp(uv_y_minus, vec2(0.0), vec2(1.0));
    
    float height_y_plus = texture(sampler2D(height_map, height_sampler), uv_y_plus).r * height_scale;
    float height_y_minus = texture(sampler2D(height_map, height_sampler), uv_y_minus).r * height_scale;
    float slope_y = abs(height_y_plus - height_y_minus) / (2.0 * distance);
    
    // Combined slope magnitude (normalized to 0-1 range)
    float slope_magnitude = sqrt(slope_x * slope_x + slope_y * slope_y);
    
    // Normalize to 0-1 range (assuming max reasonable slope is 1.0)
    float normalized_slope = clamp(slope_magnitude, 0.0, 1.0);
    
    imageStore(slope_map, pixel, vec4(normalized_slope, 0.0, 0.0, 1.0));
}

