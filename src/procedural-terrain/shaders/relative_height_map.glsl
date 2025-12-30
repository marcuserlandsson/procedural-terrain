#[compute]
#version 450

// Compute shader for generating Relative Height Map
// Calculated by subtracting Mean Height Map from Height Map
// Values below 0.5 represent depressions, above represent elevations

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Input maps (read-only)
layout(set = 0, binding = 0) uniform texture2D height_map;
layout(set = 0, binding = 1) uniform sampler height_sampler;
layout(set = 0, binding = 2) uniform texture2D mean_height_map;
layout(set = 0, binding = 3) uniform sampler mean_height_sampler;

// Output relative height map (write-only)
layout(set = 0, binding = 4, r32f) uniform restrict writeonly image2D relative_height_map;

// Parameters
layout(set = 0, binding = 5, std140) uniform RelativeHeightParams {
    vec2 map_size; // Width, Height of the map
};

void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    
    // Check bounds
    if (pixel.x >= int(map_size.x) || pixel.y >= int(map_size.y)) {
        return;
    }
    
    vec2 uv = (vec2(pixel) + 0.5) / map_size;
    
    // Sample height and mean height
    float height = texture(sampler2D(height_map, height_sampler), uv).r;
    float mean_height = texture(sampler2D(mean_height_map, mean_height_sampler), uv).r;
    
    // Calculate relative height: Height - Mean Height
    // Then normalize to 0-1 range (add 0.5 to center around 0.5)
    float relative_height = (height - mean_height) + 0.5;
    relative_height = clamp(relative_height, 0.0, 1.0);
    
    imageStore(relative_height_map, pixel, vec4(relative_height, 0.0, 0.0, 1.0));
}

