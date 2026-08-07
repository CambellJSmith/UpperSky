shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D terrain_map : filter_linear, repeat_disable;
uniform vec3 dry_colour = vec3(0.27, 0.34, 0.08);
uniform vec3 lush_colour = vec3(0.075, 0.42, 0.055);
uniform float wind_strength : hint_range(0.0, 0.4) = 0.13;
uniform float wind_speed : hint_range(0.0, 4.0) = 0.95;
uniform float wind_scale : hint_range(0.001, 0.2) = 0.052;
uniform float gust_scale : hint_range(0.001, 0.05) = 0.009;

varying float patch_visible;
varying vec3 grass_colour;

void vertex() {
    vec2 map_uv = INSTANCE_CUSTOM.xy;
    vec2 terrain_sample = textureLod(terrain_map, map_uv, 0.0).rg;
    float radial_distance = length(map_uv - vec2(0.5));
    float radial_weight = 1.0 - smoothstep(0.445, 0.5, radial_distance);
    float effective_coverage = clamp(terrain_sample.g * radial_weight, 0.0, 1.0);
    patch_visible = step(INSTANCE_CUSTOM.z, effective_coverage);

    if (patch_visible < 0.5) {
        VERTEX.y -= 10000.0;
    } else {
        VERTEX.y += terrain_sample.r;
        vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
        float tip_weight = clamp(UV.y, 0.0, 1.0);
        float sway_weight = tip_weight * tip_weight;
        float local_wave = sin(TIME * wind_speed + world_position.x * wind_scale + world_position.z * wind_scale * 0.73);
        float broad_gust = sin(TIME * wind_speed * 0.29 + world_position.x * gust_scale - world_position.z * gust_scale * 0.63);
        VERTEX.x += (local_wave * 0.68 + broad_gust * 0.32) * wind_strength * sway_weight;
        VERTEX.z += (cos(TIME * wind_speed * 0.81 + world_position.z * wind_scale) * 0.54 + broad_gust * 0.24) * wind_strength * sway_weight;
        float colour_weight = clamp(effective_coverage * 0.72 + INSTANCE_CUSTOM.w * 0.28, 0.0, 1.0);
        grass_colour = mix(dry_colour, lush_colour, colour_weight);
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
