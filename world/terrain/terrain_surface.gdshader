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

    vec2 sand_coordinates = UV * 64.0;
    float broad_grain = value_noise(sand_coordinates * 0.45);
    float fine_grain = value_noise(sand_coordinates * 3.2);
    float grain_variation = (broad_grain - 0.5) * 0.10 + (fine_grain - 0.5) * 0.14;
    vec3 textured_sand = base_colour * (1.0 + grain_variation);

    ALBEDO = mix(base_colour, textured_sand, sand_mask);
    ROUGHNESS = mix(0.96, clamp(0.88 + (1.0 - fine_grain) * 0.09, 0.0, 1.0), sand_mask);
    METALLIC = 0.0;
    SPECULAR = mix(0.30, 0.22, sand_mask);
}
