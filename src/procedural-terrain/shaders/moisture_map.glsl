#[compute]
#version 450

// Compute shader for generating Moisture Map
// Final soil moisture value compiled from multiple maps
// Based on paper equations (1) through (6)

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Input maps (read-only)
layout(set = 0, binding = 0) uniform texture2D height_map;
layout(set = 0, binding = 1) uniform sampler height_sampler;
layout(set = 0, binding = 2) uniform texture2D relative_height_map;
layout(set = 0, binding = 3) uniform sampler relative_height_sampler;
layout(set = 0, binding = 4) uniform texture2D slope_map;
layout(set = 0, binding = 5) uniform sampler slope_sampler;
layout(set = 0, binding = 6) uniform texture2D water_map;
layout(set = 0, binding = 7) uniform sampler water_sampler;
layout(set = 0, binding = 8) uniform texture2D water_spread_map;
layout(set = 0, binding = 9) uniform sampler water_spread_sampler;

// Output moisture map (write-only)
layout(set = 0, binding = 10, r32f) uniform restrict writeonly image2D moisture_map;

// Parameters
layout(set = 0, binding = 11, std140) uniform MoistureParams {
    vec2 map_size;           // Width, Height of the map
    float weight_height;     // Weight for height influence
    float weight_slope;      // Weight for slope influence
    float weight_relative_height; // Weight for relative height influence
    float omega;             // Attenuation factor for relative height (0-1)
};

void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    
    // Check bounds
    if (pixel.x >= int(map_size.x) || pixel.y >= int(map_size.y)) {
        return;
    }
    
    vec2 uv = (vec2(pixel) + 0.5) / map_size;
    
    // Sample all input maps
    float height = texture(sampler2D(height_map, height_sampler), uv).r;
    float relative_height = texture(sampler2D(relative_height_map, relative_height_sampler), uv).r;
    float slope = texture(sampler2D(slope_map, slope_sampler), uv).r;
    float water = texture(sampler2D(water_map, water_sampler), uv).r;
    float water_spread = texture(sampler2D(water_spread_map, water_spread_sampler), uv).r;
    
    // Equation (1): Base Moisture from height
    // BMxy = eval(Curveh, Hmapxy) × Weighth
    // Simplified: height influence (lower height = more moisture)
    float base_moisture = (1.0 - height) * weight_height;
    
    // Equation (2): Slope Influence
    // Slopexy = eval(Curveslope, Smapxy) × Weightslope
    // Steeper slopes = less moisture retention
    float slope_influence = (1.0 - slope) * weight_slope;
    
    // Equation (3): Relative Height Influence
    // RHxy = eval(Curverh, RHmapxy) × Weightrh
    // Depressions (lower relative height) = more moisture
    float relative_height_influence = (1.0 - relative_height) * weight_relative_height;
    
    // Equation (4): Relative Moisture
    // RMxy = RHxy - Slopexy + 1
    float relative_moisture = relative_height_influence - slope_influence + 1.0;
    
    // Equation (5): Water Spread (already calculated in water_spread_map)
    // WSxy = Wmapxy + WSmapxy × eval(CurvewsVert, RHmapxy)
    // This is handled in the water_spread_map shader
    
    // Equation (6): Final Moisture Map
    // Mmapxy = saturate((BMxy + WSxy) × RMxy + (RHxy × ω)) + WSxy
    float moisture = (base_moisture + water_spread) * relative_moisture + (relative_height_influence * omega);
    moisture += water_spread;
    moisture = clamp(moisture, 0.0, 1.0);
    
    imageStore(moisture_map, pixel, vec4(moisture, 0.0, 0.0, 1.0));
}

