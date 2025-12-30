#[compute]
#version 450

// Compute shader for generating Mean Height Map
// Represents weighted mean of height values in an area adjacent to a point
// Weight decreases linearly as distance increases

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Input height map (read-only)
layout(set = 0, binding = 0) uniform texture2D height_map;
layout(set = 0, binding = 1) uniform sampler height_sampler;

// Output mean height map (write-only)
layout(set = 0, binding = 2, r32f) uniform restrict writeonly image2D mean_height_map;

// Parameters
layout(set = 0, binding = 3, std140) uniform MeanHeightParams {
    vec2 map_size;      // Width, Height of the map
    float radius;       // Radius of the area to consider (default: 32 pixels)
    float height_scale; // Height scale factor
};

void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    
    // Check bounds
    if (pixel.x >= int(map_size.x) || pixel.y >= int(map_size.y)) {
        return;
    }
    
    vec2 uv = (vec2(pixel) + 0.5) / map_size;
    float radius_normalized = radius / map_size.x; // Normalize radius to UV space
    
    float weighted_sum = 0.0;
    float weight_sum = 0.0;
    
    // Sample in a circular area around the pixel
    int radius_int = int(ceil(radius));
    for (int dy = -radius_int; dy <= radius_int; dy++) {
        for (int dx = -radius_int; dx <= radius_int; dx++) {
            float dist = length(vec2(dx, dy));
            if (dist > radius) {
                continue;
            }
            
            vec2 sample_uv = uv + vec2(float(dx), float(dy)) / map_size;
            sample_uv = clamp(sample_uv, vec2(0.0), vec2(1.0));
            
            float height = texture(sampler2D(height_map, height_sampler), sample_uv).r * height_scale;
            
            // Weight decreases linearly with distance
            float weight = 1.0 - (dist / radius);
            weight = max(weight, 0.0);
            
            weighted_sum += height * weight;
            weight_sum += weight;
        }
    }
    
    // Calculate weighted mean and normalize to 0-1 range
    float mean_height = weight_sum > 0.0 ? weighted_sum / weight_sum : 0.0;
    float normalized_mean = mean_height / height_scale; // Normalize back to 0-1
    
    imageStore(mean_height_map, pixel, vec4(normalized_mean, 0.0, 0.0, 1.0));
}

