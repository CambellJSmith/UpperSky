shader_type canvas_item; // Applies a full-screen post-process to the rendered player view.
render_mode unshaded; // Prevents interface lighting from changing the underwater colour treatment.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear; // Reads the completed viewport image behind the overlay.
uniform float depth_factor : hint_range(0.0, 1.0) = 0.0; // Strengthens distortion and colour absorption as the camera moves deeper.

void fragment() { // Distorts and colours the current screen pixel while the camera is underwater.
    vec2 screen_uv = SCREEN_UV; // Reads the undistorted viewport coordinate for this fragment.
    float horizontal_wave = sin(screen_uv.y * 46.0 + TIME * 1.85); // Produces slow horizontal refraction bands across the view.
    float vertical_wave = cos(screen_uv.x * 34.0 - TIME * 1.35); // Produces an independent vertical wobble so distortion does not move uniformly.
    float fine_wave = sin((screen_uv.x + screen_uv.y) * 79.0 + TIME * 2.55); // Adds restrained smaller refraction detail between the broad waves.
    float distortion_strength = mix(0.0028, 0.0085, depth_factor); // Increases refraction gradually with underwater depth.
    vec2 distortion = vec2(horizontal_wave + fine_wave * 0.25, vertical_wave + fine_wave * 0.18) * distortion_strength; // Combines the waves into one bounded screen offset.
    vec2 distorted_uv = clamp(screen_uv + distortion, vec2(0.001), vec2(0.999)); // Keeps screen sampling inside the valid viewport texture.
    vec3 scene_colour = texture(screen_texture, distorted_uv).rgb; // Samples the world through the animated refraction field.
    vec3 absorption_colour = vec3(0.36, 0.68, 0.82); // Defines the desaturated blue-green light retained underwater.
    float absorption_strength = mix(0.32, 0.66, depth_factor); // Removes more warm light as the camera descends.
    scene_colour = mix(scene_colour, scene_colour * absorption_colour + vec3(0.0, 0.035, 0.075), absorption_strength); // Applies blue absorption while retaining readable scene contrast.
    float caustic = sin(screen_uv.x * 61.0 + TIME * 1.7 + sin(screen_uv.y * 43.0 - TIME)) * 0.5 + 0.5; // Produces a faint moving brightness variation suggestive of refracted surface light.
    scene_colour += vec3(0.015, 0.035, 0.045) * caustic * (1.0 - depth_factor) * 0.55; // Keeps caustics subtle and strongest near the surface.
    float edge_distance = distance(screen_uv, vec2(0.5)); // Measures distance from the centre for a mild peripheral darkening effect.
    float vignette = smoothstep(0.34, 0.76, edge_distance); // Builds a soft edge mask without obscuring the central view.
    scene_colour *= mix(1.0, 0.82, vignette * mix(0.45, 0.75, depth_factor)); // Darkens peripheral vision slightly more in deeper water.
    COLOR = vec4(scene_colour, 1.0); // Outputs an opaque post-processed view while the overlay is visible.
}