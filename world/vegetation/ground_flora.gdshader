shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float wind_strength: hint_range(0.0, 0.4) = 0.11;
uniform float wind_speed: hint_range(0.0, 4.0) = 0.9;
uniform float wind_scale: hint_range(0.001, 0.2) = 0.045;
uniform float gust_scale: hint_range(0.001, 0.05) = 0.008;

varying vec4 flora_colour;

void vertex() {
    flora_colour = COLOR;
    vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float tip_weight = clamp(UV.y, 0.0, 1.0);
    float local_wave = sin(TIME * wind_speed + world_position.x * wind_scale + world_position.z * wind_scale * 0.73);
    float broad_gust = sin(TIME * wind_speed * 0.31 + world_position.x * gust_scale - world_position.z * gust_scale * 0.61);
    float sway_weight = tip_weight * tip_weight;
    VERTEX.x += (local_wave * 0.68 + broad_gust * 0.32) * wind_strength * sway_weight;
    VERTEX.z += (cos(TIME * wind_speed * 0.83 + world_position.z * wind_scale) * 0.55 + broad_gust * 0.22) * wind_strength * sway_weight;
}

void fragment() {
    ALBEDO = flora_colour.rgb;
    ROUGHNESS = 0.96;
    METALLIC = 0.0;
    SPECULAR = 0.18;
}
