shader_type spatial;
render_mode cull_disabled, specular_disabled;
void fragment() {
    float lane = floor(UV.x * 17.0);
    float offset = fract(sin(lane * 18.73) * 419.2);
    float ribbon = step(0.68, fract(UV.x * 17.0));
    float flow = sin(UV.y * 12.0 - TIME * 3.0 + offset * 6.0) * 0.06;
    float splash = smoothstep(0.72, 1.0, UV.y);
    float whiteness = clamp(max(ribbon * 0.72 + flow, splash), 0.0, 1.0);
    ALBEDO = mix(vec3(0.27, 0.50, 0.57), vec3(0.65, 0.78, 0.80), whiteness);
    EMISSION = ALBEDO * 0.06;
    ROUGHNESS = 1.0;
    ALPHA = 0.84 + whiteness * 0.12;
}
