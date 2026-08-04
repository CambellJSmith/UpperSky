extends CanvasLayer # Applies a camera-dependent underwater post-process above the rendered three-dimensional world.
class_name UnderwaterView # Makes the underwater view controller available to the game composition root through strong typing.

const UNDERWATER_SHADER: Shader = preload("res://application/effects/underwater_view.gdshader") # Loads the reusable screen-space refraction and depth-attenuation shader.
const EFFECT_LAYER: int = 80 # Places the effect above the world but beneath the developer console layer.
const ENTER_SURFACE_OFFSET: float = -0.04 # Requires the camera to pass slightly below the surface before enabling the effect.
const EXIT_SURFACE_OFFSET: float = 0.06 # Keeps the effect stable until the camera rises slightly above the surface.
const FULL_DISTORTION_DEPTH_DISTANCE: float = 18.0 # Reaches maximum refraction strength after descending this far below the local water level.
const LIGHT_BLACKOUT_START_DEPTH: float = 70.0 # Begins the final deep-water fade after most warm and green light has already been absorbed.
const LIGHT_BLACKOUT_FULL_DEPTH: float = 220.0 # Forces the remaining blue light to complete black at extreme depth.

var _player: FirstPersonPlayer # Stores the active player whose camera determines underwater state.
var _terrain: InfiniteTerrain # Supplies authoritative water existence, level, and floating-origin conversion.
var _camera: Camera3D # Stores the exact first-person camera used for waterline testing.
var _overlay: ColorRect # Covers the viewport with the underwater post-process material.
var _material: ShaderMaterial # Stores the shader parameters updated from current camera depth.
var _is_underwater: bool = false # Tracks hysteresis state so the view does not flicker at the waterline.

func _ready() -> void: # Builds the full-screen effect when the node enters the game scene.
    layer = EFFECT_LAYER # Places underwater rendering below console interface elements.
    _material = ShaderMaterial.new() # Allocates one material instance whose depth parameters can change independently.
    _material.shader = UNDERWATER_SHADER # Assigns the authored refraction and light-attenuation shader.
    _material.set_shader_parameter("blackout_start_depth", LIGHT_BLACKOUT_START_DEPTH) # Supplies the depth where final darkness begins strengthening.
    _material.set_shader_parameter("blackout_full_depth", LIGHT_BLACKOUT_FULL_DEPTH) # Supplies the depth where no environmental light remains.
    _overlay = ColorRect.new() # Allocates the viewport-sized post-process surface.
    _overlay.name = "UnderwaterOverlay" # Gives the generated overlay a stable diagnostic name.
    _overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # Stretches the overlay across the complete viewport.
    _overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE # Prevents the effect from blocking console or future interface input.
    _overlay.material = _material # Applies the screen-reading shader to the full-screen rectangle.
    _overlay.visible = false # Starts disabled until an initialized camera actually enters water.
    add_child(_overlay) # Adds the generated overlay beneath this canvas layer.

func initialize(player: FirstPersonPlayer, terrain: InfiniteTerrain) -> void: # Connects the effect to the active camera and authoritative procedural water system.
    _player = player # Stores the active player reference without global state or signals.
    _terrain = terrain # Stores the terrain controller used for exact water queries.
    _camera = _player.get_view_camera() # Retrieves the actual rendered first-person camera from the player.

func _process(_delta: float) -> void: # Updates underwater visibility, refraction strength, and depth attenuation every rendered frame.
    if _camera == null or _terrain == null: # Waits until game composition supplies both required dependencies.
        return # Leaves the effect hidden before initialization completes.
    var camera_world_position: Vector3 = _terrain.local_to_world_position(_camera.global_position) # Converts the near-origin camera transform into stable procedural-world coordinates.
    var horizontal_position: Vector2 = Vector2(camera_world_position.x, camera_world_position.z) # Extracts the horizontal coordinate used by terrain and water sampling.
    var water_exists: bool = _terrain.has_water_at(horizontal_position) # Verifies that rendered water actually occupies this horizontal location.
    var water_level: float = _terrain.get_water_level_at(horizontal_position) # Reads the exact flat local level used by the water mesh.
    var surface_offset: float = EXIT_SURFACE_OFFSET if _is_underwater else ENTER_SURFACE_OFFSET # Uses separate enter and exit thresholds to prevent waterline flicker.
    var should_be_underwater: bool = water_exists and camera_world_position.y < water_level + surface_offset # Activates only when the camera is inside a real generated water volume.
    if should_be_underwater != _is_underwater: # Detects a genuine transition across the stabilized waterline.
        _is_underwater = should_be_underwater # Stores the newly resolved camera state.
        _overlay.visible = _is_underwater # Shows or hides the complete post-process immediately.
    if not _is_underwater: # Checks whether shader depth work is currently unnecessary.
        return # Avoids parameter updates while the effect is invisible.
    var camera_depth: float = maxf(water_level - camera_world_position.y, 0.0) # Measures current depth below the local water surface in world metres.
    var depth_factor: float = clampf(camera_depth / FULL_DISTORTION_DEPTH_DISTANCE, 0.0, 1.0) # Converts shallow depth into the bounded refraction-strength range.
    _material.set_shader_parameter("camera_depth", camera_depth) # Drives wavelength-dependent light extinction and the final fade to black.
    _material.set_shader_parameter("depth_factor", depth_factor) # Strengthens wobble and peripheral darkening before they saturate at moderate depth.
