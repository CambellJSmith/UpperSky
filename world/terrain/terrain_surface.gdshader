shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec4 terrain_vertex_colour;
void vertex() {
    terrain_vertex_colour = COLOR;
}
void fragment() {
    // Flat face lighting without duplicating the streamed terrain vertices.
    vec3 face_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
    if (dot(face_normal, NORMAL) < 0.0) { face_normal = -face_normal; }
    NORMAL = face_normal;
    ALBEDO = terrain_vertex_colour.rgb;
    ROUGHNESS = 0.94;
    METALLIC = 0.0;
    SPECULAR = 0.12;
}
