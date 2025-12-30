#[compute]
#version 450

// Compute shader for generating Water Spread Map
// Represents moisture that spreads through soil from water bodies
// Based on paper equation (5)

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Input maps (read-only)
layout(set = 0, binding = 0) uniform texture2D water_map;
layout(set = 0, binding = 1) uniform sampler water_sampler;
layout(set = 0, binding = 2) uniform texture2D relative_height_map;
layout(set = 0, binding = 3) uniform sampler relative_height_sampler;

// Output water spread map (write-only)
layout(set = 0, binding = 4, r32f) uniform restrict writeonly image2D water_spread_map;

// Parameters
layout(set = 0, binding = 5, std140) uniform WaterSpreadParams {
    vec2 map_size;      // Width, Height of the map
    float radius;       // Radius for water spread calculation (default: 32 pixels)
    float spread_factor; // Factor controlling spread intensity
};

void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    
    // Check bounds
    if (pixel.x >= int(map_size.x) || pixel.y >= int(map_size.y)) {
        return;
    }
    
    vec2 uv = (vec2(pixel) + 0.5) / map_size;
    
    // Sample water map at current position
    float water_value = texture(sampler2D(water_map, water_sampler), uv).r;
    
    // Sample relative height for vertical spread evaluation
    float relative_height = texture(sampler2D(relative_height_map, relative_height_sampler), uv).r;
    
    // Calculate water spread from nearby water sources
    float spread_sum = 0.0;
    float total_weight = 0.0;
    
    int radius_int = int(ceil(radius));
    for (int dy = -radius_int; dy <= radius_int; dy++) {
        for (int dx = -radius_int; dx <= radius_int; dx++) {
            float dist = length(vec2(dx, dy));
            if (dist > radius || dist == 0.0) {
                continue;
            }
            
            vec2 sample_uv = uv + vec2(float(dx), float(dy)) / map_size;
            sample_uv = clamp(sample_uv, vec2(0.0), vec2(1.0));
            
            float sample_water = texture(sampler2D(water_map, water_sampler), sample_uv).r;
            
            if (sample_water > 0.5) { // Water source found
                // Weight decreases with distance
                float weight = 1.0 / (1.0 + dist * spread_factor);
                
                // Evaluate vertical spread based on relative height
                // Lower relative height (depressions) allow more spread
                float vertical_factor = 1.0 - relative_height; // More spread in depressions
                
                spread_sum += weight * vertical_factor;
                total_weight += weight;
            }
        }
    }
    
    // Calculate water spread value
    // WSxy = Wmapxy + WSmapxy × eval(CurvewsVert, RHmapxy)
    // Simplified: water value + spread contribution
    float spread_contribution = total_weight > 0.0 ? (spread_sum / total_weight) : 0.0;
    float water_spread = water_value + spread_contribution * (1.0 - relative_height);
    water_spread = clamp(water_spread, 0.0, 1.0);
    
    imageStore(water_spread_map, pixel, vec4(water_spread, 0.0, 0.0, 1.0));
}

