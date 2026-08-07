shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D terrain_map : filter_linear, repeat_disable;
uniform vec2 carpet_world_origin = vec2(0.0);
uniform float carpet_size = 320.0;
uniform float patch_spacing = 3.2;
uniform vec3 dry_colour = vec3(0.27, 0.34, 0.08);
uniform vec3 lush_colour = vec3(0.075, 0.42, 0.055);
uniform float wind_strength : hint_range(0.0, 0.4) = 0.13;
uniform float wind_speed : hint_range(0.0, 4.0) = 0.95;
uniform float wind_scale : hint_range(0.001, 0.2) = 0.052;
uniform float gust_scale : hint_range(0.001, 0.05) = 0.009;

varying float patch_visible;
varying vec3 grass_colour;

float hash_2d(vec2 coordinate) {
    return fract(sin(dot(coordinate, vec2(127.1, 311.7))) * 43758.5453123);
}

mat2 rotation_2d(float angle) {
    float sine_value = sin(angle);
    float cosine_value = cos(angle);
    return mat2(vec2(cosine_value, -sine_value), vec2(sine_value, cosine_value));
}

void vertex() {
    vec2 map_uv = INSTANCE_CUSTOM.xy;
    vec2 terrain_sample = textureLod(terrain_map, map_uv, 0.0).rg;
    vec2 absolute_root = carpet_world_origin + map_uv * carpet_size;
    vec2 world_cell = floor(absolute_root / patch_spacing + vec2(0.5));
    float density_random = hash_2d(world_cell + vec2(19.0, 47.0));
    float rotation_random = hash_2d(world_cell + vec2(73.0, 11.0));
    float colour_random = hash_2d(world_cell + vec2(31.0, 89.0));

    float radial_distance = length(map_uv - vec2(0.5));
    float radial_weight = 1.0 - smoothstep(0.445, 0.5, radial_distance);
    float effective_coverage = clamp(terrain_sample.g * radial_weight, 0.0, 1.0);
    float density_threshold = mix(0.02, 0.98, density_random);
    patch_visible = step(density_threshold, effective_coverage);
    grass_colour = mix(dry_colour, lush_colour, clamp(effective_coverage * 0.72 + colour_random * 0.28, 0.0, 1.0));

    if (patch_visible < 0.5) {
        VERTEX.y -= 10000.0;
    } else {
        VERTEX.xz = rotation_2d(rotation_random * TAU) * VERTEX.xz;
        VERTEX.y += terrain_sample.r;
        float tip_weight = clamp(UV.y, 0.0, 1.0);
        float sway_weight = tip_weight * tip_weight;
        float local_wave = sin(TIME * wind_speed + absolute_root.x * wind_scale + absolute_root.y * wind_scale * 0.73);
        float broad_gust = sin(TIME * wind_speed * 0.29 + absolute_root.x * gust_scale - absolute_root.y * gust_scale * 0.63);
        VERTEX.x += (local_wave * 0.68 + broad_gust * 0.32) * wind_strength * sway_weight;
        VERTEX.z += (cos(TIME * wind_speed * 0.81 + absolute_root.y * wind_scale) * 0.54 + broad_gust * 0.24) * wind_strength * sway_weight;
    }
}

void fragment() {
    if (patch_visible < 0.5) {
        discard;
    }
    ALBEDO = grass_colour;
    ROUGHNESS = 0.98;
    METALLIC = 0.0;
    SPECULAR = 0.12;
}
