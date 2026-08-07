shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D terrain_map : filter_nearest, repeat_disable;
uniform vec2 carpet_world_origin = vec2(0.0);
uniform vec2 terrain_map_world_origin = vec2(0.0);
uniform float carpet_size = 320.0;
uniform float patch_spacing = 3.2;
uniform float terrain_vertex_spacing = 8.0;
uniform float root_embed_depth = 0.035;
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

vec2 sample_rendered_terrain(vec2 world_position) {
    ivec2 map_size = textureSize(terrain_map, 0);
    vec2 lattice_position = (world_position - terrain_map_world_origin) / terrain_vertex_spacing;
    ivec2 cell = ivec2(floor(lattice_position));
    cell = clamp(cell, ivec2(0), map_size - ivec2(2));
    vec2 fraction = clamp(lattice_position - vec2(cell), vec2(0.0), vec2(1.0));

    vec2 top_left = texelFetch(terrain_map, cell, 0).rg;
    vec2 top_right = texelFetch(terrain_map, cell + ivec2(1, 0), 0).rg;
    vec2 bottom_left = texelFetch(terrain_map, cell + ivec2(0, 1), 0).rg;
    vec2 bottom_right = texelFetch(terrain_map, cell + ivec2(1, 1), 0).rg;

    if (fraction.x + fraction.y <= 1.0) {
        return top_left
            + fraction.x * (top_right - top_left)
            + fraction.y * (bottom_left - top_left);
    }
    return bottom_right
        + (1.0 - fraction.y) * (top_right - bottom_right)
        + (1.0 - fraction.x) * (bottom_left - bottom_right);
}

void vertex() {
    vec2 map_uv = INSTANCE_CUSTOM.xy;
    vec2 absolute_patch_root = carpet_world_origin + map_uv * carpet_size;
    vec2 patch_terrain_sample = sample_rendered_terrain(absolute_patch_root);
    vec2 world_cell = floor(absolute_patch_root / patch_spacing + vec2(0.5));
    float density_random = hash_2d(world_cell + vec2(19.0, 47.0));
    float rotation_random = hash_2d(world_cell + vec2(73.0, 11.0));
    float colour_random = hash_2d(world_cell + vec2(31.0, 89.0));

    float radial_distance = length(map_uv - vec2(0.5));
    float radial_weight = 1.0 - smoothstep(0.445, 0.5, radial_distance);
    float effective_coverage = clamp(patch_terrain_sample.g * radial_weight, 0.0, 1.0);
    float density_threshold = mix(0.02, 0.98, density_random);
    patch_visible = step(density_threshold, effective_coverage);
    grass_colour = mix(dry_colour, lush_colour, clamp(effective_coverage * 0.72 + colour_random * 0.28, 0.0, 1.0));

    if (patch_visible < 0.5) {
        VERTEX.y -= 10000.0;
    } else {
        mat2 patch_rotation = rotation_2d(rotation_random * TAU);
        vec2 rotated_blade_root = patch_rotation * UV2;
        vec2 blade_world_root = absolute_patch_root + rotated_blade_root;
        float root_height = sample_rendered_terrain(blade_world_root).r;
        vec2 rotated_vertex_offset = patch_rotation * VERTEX.xz;
        vec2 projected_vertex_world = absolute_patch_root + rotated_vertex_offset;
        float projected_surface_height = sample_rendered_terrain(projected_vertex_world).r;
        float base_grounding_weight = 1.0 - smoothstep(0.0, 0.24, UV.y);
        float grounded_height = mix(root_height, projected_surface_height, base_grounding_weight);

        VERTEX.xz = rotated_vertex_offset;
        VERTEX.y += grounded_height - root_embed_depth;

        float tip_weight = clamp(UV.y, 0.0, 1.0);
        float sway_weight = tip_weight * tip_weight;
        float local_wave = sin(TIME * wind_speed + blade_world_root.x * wind_scale + blade_world_root.y * wind_scale * 0.73);
        float broad_gust = sin(TIME * wind_speed * 0.29 + blade_world_root.x * gust_scale - blade_world_root.y * gust_scale * 0.63);
        VERTEX.x += (local_wave * 0.68 + broad_gust * 0.32) * wind_strength * sway_weight;
        VERTEX.z += (cos(TIME * wind_speed * 0.81 + blade_world_root.y * wind_scale) * 0.54 + broad_gust * 0.24) * wind_strength * sway_weight;
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
