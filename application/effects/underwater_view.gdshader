shader_type canvas_item; // Applies a full-screen post-process to the rendered player view.
render_mode unshaded; // Prevents interface lighting from changing the underwater colour treatment.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear; // Reads the completed viewport image behind the overlay.
uniform float camera_depth : hint_range(0.0, 400.0) = 0.0; // Measures the camera's actual world-space depth below the local water surface.
uniform float depth_factor : hint_range(0.0, 1.0) = 0.0; // Strengthens distortion and peripheral darkening before saturating at moderate depth.
uniform float blackout_start_depth : hint_range(0.0, 400.0) = 70.0; // Begins the final fade after wavelength attenuation has removed most visible light.
uniform float blackout_full_depth : hint_range(1.0, 600.0) = 220.0; // Defines the depth where the view becomes completely black.

void fragment() { // Distorts and attenuates the current screen pixel while the camera is underwater.
    vec2 screen_uv = SCREEN_UV; // Reads the undistorted viewport coordinate for this fragment.
    float horizontal_wave = sin(screen_uv.y * 46.0 + TIME * 1.85); // Produces slow horizontal refraction bands across the view.
    float vertical_wave = cos(screen_uv.x * 34.0 - TIME * 1.35); // Produces an independent vertical wobble so distortion does not move uniformly.
    float fine_wave = sin((screen_uv.x + screen_uv.y) * 79.0 + TIME * 2.55); // Adds restrained smaller refraction detail between the broad waves.
    float distortion_strength = mix(0.0028, 0.0085, depth_factor); // Increases refraction gradually before reaching a bounded maximum.
    vec2 distortion = vec2(horizontal_wave + fine_wave * 0.25, vertical_wave + fine_wave * 0.18) * distortion_strength; // Combines the waves into one bounded screen offset.
    vec2 distorted_uv = clamp(screen_uv + distortion, vec2(0.001), vec2(0.999)); // Keeps screen sampling inside the valid viewport texture.
    vec3 scene_colour = texture(screen_texture, distorted_uv).rgb; // Samples the world through the animated refraction field.
    vec3 attenuation_coefficient = vec3(0.070, 0.036, 0.018); // Absorbs red fastest, green next, and blue slowest as physical water depth increases.
    vec3 direct_transmittance = exp(-attenuation_coefficient * camera_depth); // Calculates wavelength-dependent surviving environmental light at the current depth.
    float scatter_fade = exp(-camera_depth * 0.022); // Removes the remaining blue-green scattered light progressively with depth.
    vec3 scattered_light = vec3(0.0, 0.030, 0.072) * scatter_fade; // Adds restrained blue-green ambient scatter while some surface light still reaches the camera.
    float scattered_fraction = 1.0 - direct_transmittance.b; // Introduces ambient scatter as direct blue light becomes attenuated.
    scene_colour = scene_colour * direct_transmittance + scattered_light * scattered_fraction; // Applies depth attenuation without replacing shallow water with a flat colour wash.
    float caustic = sin(screen_uv.x * 61.0 + TIME * 1.7 + sin(screen_uv.y * 43.0 - TIME)) * 0.5 + 0.5; // Produces a faint moving brightness variation suggestive of refracted surface light.
    float caustic_visibility = exp(-camera_depth * 0.12); // Restricts caustics to shallow water where direct surface light remains plausible.
    scene_colour += vec3(0.015, 0.035, 0.045) * caustic * caustic_visibility * 0.55; // Adds subtle near-surface illumination that vanishes quickly with depth.
    float edge_distance = distance(screen_uv, vec2(0.5)); // Measures distance from the centre for a mild peripheral darkening effect.
    float vignette = smoothstep(0.34, 0.76, edge_distance); // Builds a soft edge mask without obscuring the central view.
    scene_colour *= mix(1.0, 0.78, vignette * mix(0.45, 0.82, depth_factor)); // Darkens peripheral vision increasingly as the camera descends.
    float blackout_factor = smoothstep(blackout_start_depth, blackout_full_depth, camera_depth); // Converts extreme depth into a continuous final loss of all remaining light.
    scene_colour = mix(scene_colour, vec3(0.0), blackout_factor); // Reaches exact black at and below the configured full-black depth.
    COLOR = vec4(scene_colour, 1.0); // Outputs an opaque post-processed view while the overlay is visible.
}
