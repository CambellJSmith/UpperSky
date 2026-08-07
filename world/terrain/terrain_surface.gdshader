shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec4 terrain_vertex_colour;

float hash_2d(vec2 coordinate) {
    return fract(sin(dot(coordinate, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 coordinate) {
    vec2 cell = floor(coordinate);
    vec2 fraction = fract(coordinate);
    vec2 blend = fraction * fraction * (3.0 - 2.0 * fraction);
    float bottom_left = hash_2d(cell);
    float bottom_right = hash_2d(cell + vec2(1.0, 0.0));
    float top_left = hash_2d(cell + vec2(0.0, 1.0));
    float top_right = hash_2d(cell + vec2(1.0, 1.0));
    return mix(mix(bottom_left, bottom_right, blend.x), mix(top_left, top_right, blend.x), blend.y);
}

void vertex() {
    terrain_vertex_colour = COLOR;
}

void fragment() {
    vec3 base_colour = terrain_vertex_colour.rgb;
    float sand_mask = clamp(terrain_vertex_colour.a, 0.0, 1.0);

    vec2 surface_coordinates = UV * 64.0;
    float broad_grain = value_noise(surface_coordinates * 0.45);
    float fine_grain = value_noise(surface_coordinates * 3.2);

    float green_bias = base_colour.g - base_colour.r;
    float vegetation_mask = (1.0 - sand_mask) * smoothstep(0.015, 0.11, green_bias);
    float vegetation_value = 0.90 + broad_grain * 0.12 + (fine_grain - 0.5) * 0.06;
    vec3 vegetation_tint = base_colour * vec3(0.90, 1.075, 0.84) * vegetation_value;
    vec3 vegetated_colour = mix(base_colour, vegetation_tint, vegetation_mask * 0.78);

    float grain_variation = (broad_grain - 0.5) * 0.10 + (fine_grain - 0.5) * 0.14;
    vec3 textured_sand = base_colour * (1.0 + grain_variation);

    ALBEDO = mix(vegetated_colour, textured_sand, sand_mask);
    float base_roughness = mix(0.96, 0.99, vegetation_mask);
    ROUGHNESS = mix(base_roughness, clamp(0.88 + (1.0 - fine_grain) * 0.09, 0.0, 1.0), sand_mask);
    METALLIC = 0.0;
    SPECULAR = mix(0.24, 0.22, sand_mask);
}
