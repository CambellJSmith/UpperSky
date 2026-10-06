shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
void fragment() {
    vec2 p = UV * 128.0;
    // One irregular wave family avoids a repeated checkerboard on broad seas.
    float wave = sin(p.x * 0.078 + p.y * 0.031 + sin(p.y * 0.013) * 1.8 + TIME * 0.25);
    float streak = smoothstep(0.975, 0.999, wave);
    float broken = smoothstep(-0.2, 0.6, sin(p.y * 0.021 + sin(p.x * 0.015)));
    ALBEDO = mix(vec3(0.065, 0.245, 0.31), vec3(0.19, 0.39, 0.43), streak * broken * 0.45);
    ROUGHNESS = 1.0;
    ALPHA = 0.94;
}
