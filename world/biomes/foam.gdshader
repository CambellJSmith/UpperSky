shader_type spatial;
render_mode cull_disabled;
void fragment() {
    vec2 p = (UV - vec2(0.5)) * 2.0;
    float ring = length(p);
    float ripple = sin(ring * 21.0 - TIME * 2.0 + p.x * 3.0);
    float fleck = step(0.48, ripple);
    ALBEDO = mix(vec3(0.32, 0.62, 0.65), vec3(0.77, 0.87, 0.85), fleck);
    EMISSION = ALBEDO * 0.08;
    ALPHA = (1.0 - smoothstep(0.65, 1.0, ring)) * (0.35 + fleck * 0.5);
    ROUGHNESS = 0.8;
}
