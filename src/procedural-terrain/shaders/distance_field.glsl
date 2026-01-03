#[compute]
#version 450

// Compute shader for generating Distance Field from binary density map
// Implements equation (7) from the paper: φ = 1 - saturate((δ - τ) / (ZOI - τ))
// where δ is euclidean distance to nearest plant, τ is trunk radius, ZOI is Zone of Influence

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Input: binary density map (0 or 1) from position evaluation
layout(set = 0, binding = 0, r32f) uniform restrict readonly image2D binary_density_map;

// Output: distance field density map
layout(set = 0, binding = 1, r32f) uniform restrict writeonly image2D distance_field_map;

// Parameters
layout(set = 0, binding = 2, std140) uniform DistanceFieldParams {
    vec2 map_size;
    float trunk_radius;      // τ: trunk radius
    float zone_of_influence; // ZOI: Zone of Influence
    int search_radius;       // Maximum search distance (for optimization)
};

void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    
    // Check bounds
    if (pixel.x >= int(map_size.x) || pixel.y >= int(map_size.y)) {
        return;
    }
    
    // Read binary density value at this pixel
    float binary_value = imageLoad(binary_density_map, pixel).r;
    
    // If this pixel has a plant (binary_value = 1), calculate distance field
    if (binary_value > 0.5) {
        // This pixel is at the plant position, so δ = 0
        // φ = 1 - saturate((0 - τ) / (ZOI - τ)) = 1 - saturate(-τ / (ZOI - τ))
        // Since δ < τ, the influence is maximum (1.0)
        float phi = 1.0;
        imageStore(distance_field_map, pixel, vec4(phi, 0.0, 0.0, 1.0));
        return;
    }
    
    // Find nearest plant position (binary_value = 1)
    float min_distance = float(search_radius) + 1.0;  // Initialize to max search distance
    
    int search = int(search_radius);
    for (int dy = -search; dy <= search; dy++) {
        for (int dx = -search; dx <= search; dx++) {
            ivec2 neighbor = pixel + ivec2(dx, dy);
            
            // Check bounds
            if (neighbor.x < 0 || neighbor.x >= int(map_size.x) || 
                neighbor.y < 0 || neighbor.y >= int(map_size.y)) {
                continue;
            }
            
            float neighbor_value = imageLoad(binary_density_map, neighbor).r;
            
            // If neighbor has a plant, calculate distance
            if (neighbor_value > 0.5) {
                float dx_f = float(dx);
                float dy_f = float(dy);
                float distance = sqrt(dx_f * dx_f + dy_f * dy_f);
                
                if (distance < min_distance) {
                    min_distance = distance;
                }
            }
        }
    }
    
    // Calculate distance field value using equation (7)
    // φ = 1 - saturate((δ - τ) / (ZOI - τ))
    float delta = min_distance;  // δ: euclidean distance to nearest plant
    float tau = trunk_radius;    // τ: trunk radius
    float zoi = zone_of_influence; // ZOI: Zone of Influence
    
    // If no plant found within search radius, influence is 0
    if (min_distance > float(search_radius)) {
        imageStore(distance_field_map, pixel, vec4(0.0, 0.0, 0.0, 1.0));
        return;
    }
    
    // Apply equation (7)
    float numerator = delta - tau;
    float denominator = zoi - tau;
    
    // Avoid division by zero
    if (denominator <= 0.0) {
        imageStore(distance_field_map, pixel, vec4(0.0, 0.0, 0.0, 1.0));
        return;
    }
    
    float ratio = numerator / denominator;
    float phi = 1.0 - clamp(ratio, 0.0, 1.0);  // saturate = clamp(0, 1)
    
    imageStore(distance_field_map, pixel, vec4(phi, 0.0, 0.0, 1.0));
}
