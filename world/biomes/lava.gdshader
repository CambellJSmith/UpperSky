shader_type spatial;
render_mode cull_disabled;
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
    vec2 p = UV * 12.0 + vec2(sin(TIME * 0.07), cos(TIME * 0.06)) * 0.12;
    vec2 cell = floor(p);
    vec2 f = fract(p);
    float nearest = 10.0;
    float second = 10.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 offset = vec2(float(x), float(y));
            vec2 seed = vec2(hash(cell + offset), hash(cell + offset + vec2(19.0, 7.0)));
            float distance = length(offset + seed - f);
            if (distance < nearest) { second = nearest; nearest = distance; }
            else { second = min(second, distance); }
        }
    }
    float crack = 1.0 - smoothstep(0.045, 0.17, second - nearest);
    vec3 crust = vec3(0.13, 0.095, 0.09);
    vec3 molten = mix(vec3(0.86, 0.16, 0.025), vec3(1.0, 0.49, 0.07), crack);
    ALBEDO = mix(crust, molten, crack);
    EMISSION = molten * crack * 1.1;
    ROUGHNESS = 0.9;
}
