#[compute]
#version 450

// Position evaluation compute shader
// Implements EVALUATEPOSITION(x,y) from the paper (Figure 9)

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Input maps
layout(set = 0, binding = 0) uniform texture2D height_map;      // Hmap
layout(set = 0, binding = 1) uniform texture2D water_map;       // Wmap
layout(set = 0, binding = 2) uniform texture2D slope_map;         // Smap
layout(set = 0, binding = 3) uniform texture2D moisture_map;     // Mmap
layout(set = 0, binding = 4) uniform sampler linear_sampler;

// Density map from upper layer (for multi-layer interaction, Phase 4)
// For Phase 3 (single layer), this is not used but structure is here
layout(set = 0, binding = 5) uniform texture2D density_map_upper;

// Position tile (input)
layout(set = 0, binding = 6, std430) restrict readonly buffer PositionTile {
    vec2 positions[];
};

// Output: valid positions and plant types
layout(set = 0, binding = 7, std430) restrict writeonly buffer ValidPositions {
    vec4 valid_positions[];  // x, y, plant_type, probability
};

// Output: density map for current layer (for Phase 4)
layout(set = 0, binding = 8, r32f) uniform restrict writeonly image2D density_map;

// Parameters
layout(set = 0, binding = 9, std140) uniform EvaluationParams {
    vec2 map_size;
    vec2 tile_offset;  // Offset of this tile in map coordinates
    float tile_size;
    int num_positions;
    int plant_type;
    int current_layer;  // l: index of the current layer
    float threshold;
    float height_scale;
};

// Adaptability curve evaluation functions
// TODO: Replace with proper curve sampling from texture or uniform buffer
// For now, using simplified functions matching the paper's structure

// eval(Curves_height, Hmap_xy) - Line 11
float evaluate_height_curve(float height_value) {
    // Height map values are already normalized (0-1) from the texture
    float normalized = clamp(height_value, 0.0, 1.0);
    // Accept most heights, with slight preference for mid-range
    // More restrictive: reject very low (< 0.15) and very high (> 0.85)
    if (normalized < 0.15 || normalized > 0.85) {
        return 0.0;
    }
    // Return a value that decreases towards edges
    return 1.0 - abs(normalized - 0.5) * 1.2;
}

// eval(Curves_slope, Smap_xy) - Line 12
float evaluate_slope_curve(float slope_value) {
    // Prefer flatter areas
    // TODO: Implement proper curve sampling
    if (slope_value > 0.6) {
        return 0.0;  // Reject steep slopes
    }
    // Linear decrease from 1.0 at slope 0 to 0.0 at slope 0.6
    return 1.0 - slope_value / 0.6;
}

// eval(Curves_moisture, Mmap_xy) - Line 13
float evaluate_moisture_curve(float moisture_value) {
    // Favor higher moisture (near water) but still allow plants in drier areas
    // Higher moisture = higher probability, but not exclusive
    // TODO: Implement proper curve sampling
    
    // Reject only extreme values
    if (moisture_value < 0.05 || moisture_value > 0.98) {
        return 0.0;  // Very dry or submerged
    }
    
    // Balanced smooth curve: favors high moisture but allows viable probability in drier areas
    // Uses a power curve for smooth falloff: probability = (moisture/0.98)^0.7 * 0.7 + 0.3
    // This gives:
    // - High moisture (0.8): ~0.85 probability (dense near water)
    // - Moderate moisture (0.5): ~0.65 probability (good distribution)
    // - Lower moisture (0.3): ~0.50 probability (sparse but present)
    // - Low moisture (0.15): ~0.40 probability (rare but possible)
    
    float normalized = clamp(moisture_value, 0.05, 0.98);
    float base_prob = pow(normalized / 0.98, 0.7);  // Power curve for smooth falloff
    return base_prob * 0.7 + 0.3;  // Scale to range [0.3, 1.0]
}

// eval(Curves_interact, DensityMap^l-1_xy) - Line 8
float evaluate_interaction_curve(float density_value) {
    // Simplified: prefer areas with some existing density (for Phase 4)
    // TODO: Implement proper curve sampling
    return 1.0;  // For Phase 3 (single layer), always 1.0
}

void main() {
    uint index = gl_GlobalInvocationID.x;
    
    if (index >= uint(num_positions)) {
        return;
    }
    
    // Get position in tile coordinates (already in pixel space, 0 to tile_size)
    vec2 tile_pos = positions[index];
    
    // Convert to map coordinates (tile_pos is already in pixels, just add offset)
    vec2 map_pos = tile_offset + tile_pos;
    
    // Clamp to valid range
    map_pos = clamp(map_pos, vec2(0.0), map_size - vec2(1.0));
    
    // Normalize for texture sampling (0-1)
    vec2 uv = map_pos / map_size;
    
    // Sample maps
    float height_value = texture(sampler2D(height_map, linear_sampler), uv).r;      // Hmap_xy
    float water_value = texture(sampler2D(water_map, linear_sampler), uv).r;         // Wmap_xy
    float slope_value = texture(sampler2D(slope_map, linear_sampler), uv).r;         // Smap_xy
    float moisture_value = texture(sampler2D(moisture_map, linear_sampler), uv).r;     // Mmap_xy
    
    // Line 2: P ← 1
    float P = 1.0;
    
    // Line 3: P ← P × (1 – Wmap_xy)
    // Note: water_value should be 0-1, where 1 = water (blocked)
    // If water map is binary (0 or 1), this works correctly
    P *= (1.0 - water_value);
    
    // Early exit if already zero (in water)
    if (P <= 0.0) {
        valid_positions[index] = vec4(map_pos.x, map_pos.y, -1.0, 0.0);
        ivec2 pixel_coord = ivec2(map_pos);
        if (pixel_coord.x >= 0 && pixel_coord.x < int(map_size.x) && 
            pixel_coord.y >= 0 && pixel_coord.y < int(map_size.y)) {
            imageStore(density_map, pixel_coord, vec4(0.0, 0.0, 0.0, 1.0));
        }
        return;
    }
    
    // Line 4: Plant ← getPlant() (handled by plant_type parameter)
    // Line 5: Curves ← getCurves(Plant) (handled by curve functions)
    
    // Line 6: l ← index of the current layer
    int l = current_layer;
    
    // Lines 7-10: Multi-layer interaction (if l > 1)
    if (l > 1) {
        // Line 8: P ← P × eval(Curves_interact, DensityMap^l-1_xy)
        float density_upper = texture(sampler2D(density_map_upper, linear_sampler), uv).r;
        float interaction_mult = evaluate_interaction_curve(density_upper);
        P *= interaction_mult;
        
        // Line 9: P ← P × (1 – [DensityMap^l-1_xy])
        // This prevents placement where upper layers have plants
        float avoidance_mult = (1.0 - density_upper);
        P *= avoidance_mult;
        
        // Early exit if probability is zero due to upper layer collision
        if (P <= 0.0) {
            valid_positions[index] = vec4(map_pos.x, map_pos.y, -1.0, 0.0);
            ivec2 pixel_coord = ivec2(map_pos);
            if (pixel_coord.x >= 0 && pixel_coord.x < int(map_size.x) && 
                pixel_coord.y >= 0 && pixel_coord.y < int(map_size.y)) {
                imageStore(density_map, pixel_coord, vec4(0.0, 0.0, 0.0, 1.0));
            }
            return;
        }
    }
    
    // Line 11: P ← P × eval(Curves_height, Hmap_xy)
    P *= evaluate_height_curve(height_value);
    
    // Line 12: P ← P × eval(Curves_slope, Smap_xy)
    P *= evaluate_slope_curve(slope_value);
    
    // Line 13: P ← P × eval(Curves_moisture, Mmap_xy)
    P *= evaluate_moisture_curve(moisture_value);
    
    // Line 14: threshold ← getThreshold()
    float placement_threshold = threshold;
    
    // Lines 15-20: Placement decision
    ivec2 pixel_coord = ivec2(map_pos);
    
    if (P >= placement_threshold) {
        // Line 16: update the Position Buffers
        valid_positions[index] = vec4(map_pos.x, map_pos.y, float(plant_type), P);
        
        // Line 17: DensityMap^l_xy ← 1
        if (pixel_coord.x >= 0 && pixel_coord.x < int(map_size.x) && 
            pixel_coord.y >= 0 && pixel_coord.y < int(map_size.y)) {
            imageStore(density_map, pixel_coord, vec4(1.0, 0.0, 0.0, 1.0));
        }
    } else {
        // Line 19: DensityMap^l_xy ← 0
        if (pixel_coord.x >= 0 && pixel_coord.x < int(map_size.x) && 
            pixel_coord.y >= 0 && pixel_coord.y < int(map_size.y)) {
            imageStore(density_map, pixel_coord, vec4(0.0, 0.0, 0.0, 1.0));
        }
        
        // Mark as invalid position
        valid_positions[index] = vec4(map_pos.x, map_pos.y, -1.0, P);
    }
}

