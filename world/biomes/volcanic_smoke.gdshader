shader_type spatial;
render_mode cull_disabled;
void vertex() {
    VERTEX.x += sin(TIME * 0.22 + VERTEX.y * 2.0) * 0.045;
    VERTEX.z += cos(TIME * 0.17 + VERTEX.x) * 0.03;
}
void fragment() {
    ALBEDO = vec3(0.39, 0.40, 0.43);
    ALPHA = 0.23;
    ROUGHNESS = 1.0;
}
