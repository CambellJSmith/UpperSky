shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform bool grass_detail_enabled = false;
uniform sampler2D grass_map : filter_nearest, repeat_disable;
uniform vec2 grass_map_origin = vec2(0.0);
uniform vec2 grass_world_origin = vec2(0.0);
uniform vec2 grass_player_position = vec2(0.0);
varying vec4 terrain_vertex_colour;
varying vec2 grass_world_position;

float grass_hash(vec2 p) {
    return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}

float grass_coverage(vec2 p, float fallback) {
    ivec2 size = textureSize(grass_map,0);
    vec2 lattice = (p-grass_map_origin)/8.0;
    // Exact road, shore and clearing masks near the player. Beyond the map,
    // authored terrain colours provide a soft landscape-scale grass mask.
    vec2 edge = min(lattice,vec2(size-ivec2(1))-lattice);
    float map_weight = smoothstep(0.0,2.0,min(edge.x,edge.y));
    if (map_weight <= 0.0) { return fallback; }
    ivec2 cell = clamp(ivec2(floor(lattice)),ivec2(0),size-ivec2(2));
    vec2 f = clamp(lattice-vec2(cell),vec2(0.0),vec2(1.0));
    float a = texelFetch(grass_map,cell,0).g;
    float b = texelFetch(grass_map,cell+ivec2(1,0),0).g;
    float c = texelFetch(grass_map,cell+ivec2(0,1),0).g;
    float d = texelFetch(grass_map,cell+ivec2(1,1),0).g;
    float mask = f.x+f.y<=1.0 ? a+f.x*(b-a)+f.y*(c-a) : d+(1.0-f.y)*(b-d)+(1.0-f.x)*(c-d);
    return mix(fallback,mask,map_weight);
}

void vertex() {
    terrain_vertex_colour = COLOR;
    grass_world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xz+grass_world_origin;
}

void fragment() {
    vec3 face_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
    if (dot(face_normal, NORMAL) < 0.0) { face_normal = -face_normal; }
    NORMAL = face_normal;
    vec3 base = terrain_vertex_colour.rgb;
    ALBEDO = base;
    if (grass_detail_enabled) {
        float green = smoothstep(0.025,0.12,base.g-max(base.r,base.b));
        float fallback = green*(1.0-terrain_vertex_colour.a);
        float coverage = grass_coverage(grass_world_position,fallback);
        float far_weight = smoothstep(42.0,80.0,distance(grass_world_position,grass_player_position));
        // Broad, stable low-poly patches, with fine detail filtered out before
        // it can shimmer in the distance. No extra geometry or render pass.
        vec2 patch = floor(grass_world_position/12.0);
        float variation = grass_hash(patch);
        float tuft = grass_hash(floor(grass_world_position/0.7));
        float footprint = max(length(dFdx(grass_world_position)),length(dFdy(grass_world_position)));
        float detail = (tuft-0.5)*(1.0-smoothstep(0.2,0.8,footprint));
        vec3 grass_tone = mix(vec3(0.27,0.34,0.08),vec3(0.075,0.42,0.055),clamp(coverage*0.72+variation*0.28,0.0,1.0));
        grass_tone *= 0.94+variation*0.12+detail*0.12;
        ALBEDO = mix(base,grass_tone,clamp(coverage*far_weight*0.32,0.0,0.32));
    }
    ROUGHNESS = 0.94;
    METALLIC = 0.0;
    SPECULAR = 0.12;
}
