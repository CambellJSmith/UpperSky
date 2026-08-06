extends Node3D # Advances world time and keeps celestial lighting, sky, ambient light, and fog synchronized.
class_name DayNightCycle # Exposes time controls to the developer console without requiring a global singleton.

const GROUP_NAME: StringName = &"day_night_cycle" # Lets developer tools resolve the active cycle without coupling to the game scene hierarchy.
const HOURS_PER_DAY: float = 24.0 # Defines one complete solar rotation.
const DEFAULT_FULL_DAY_SECONDS: float = 1200.0 # Makes one ordinary in-game day last twenty real minutes at normal speed.
const MAXIMUM_SPEED_MULTIPLIER: float = 1000.0 # Prevents accidental values from advancing time too aggressively for stable rendering.
const SKY_UPDATE_INTERVAL: float = 0.05 # Limits procedural-sky and environment mutation to twenty updates per second.
const SUN_AZIMUTH_DEGREES: float = -32.0 # Preserves the authored horizontal sun direction while elevation changes throughout the day.
const SUN_MAXIMUM_ENERGY: float = 1.2 # Matches the original midday directional-light strength.
const MOON_MAXIMUM_ENERGY: float = 0.16 # Provides restrained night illumination without making darkness resemble daylight.

const NIGHT_SKY_TOP: Color = Color(0.008, 0.014, 0.045, 1.0) # Creates a deep blue-black upper sky at night.
const NIGHT_SKY_HORIZON: Color = Color(0.025, 0.045, 0.095, 1.0) # Keeps the night horizon faintly readable.
const NIGHT_GROUND_BOTTOM: Color = Color(0.008, 0.012, 0.018, 1.0) # Darkens the lower hemisphere beneath the world.
const NIGHT_GROUND_HORIZON: Color = Color(0.025, 0.035, 0.055, 1.0) # Prevents a hard black seam at the night horizon.
const DAY_SKY_TOP: Color = Color(0.12, 0.29, 0.55, 1.0) # Retains the original clear daytime upper sky.
const DAY_SKY_HORIZON: Color = Color(0.68, 0.79, 0.90, 1.0) # Retains the original pale daytime horizon.
const DAY_GROUND_BOTTOM: Color = Color(0.05, 0.07, 0.08, 1.0) # Retains the original lower daytime hemisphere.
const DAY_GROUND_HORIZON: Color = Color(0.40, 0.46, 0.50, 1.0) # Retains the original daytime ground horizon.
const TWILIGHT_SKY_TOP: Color = Color(0.10, 0.12, 0.28, 1.0) # Adds cool upper-atmosphere colour around dawn and dusk.
const TWILIGHT_SKY_HORIZON: Color = Color(0.92, 0.34, 0.12, 1.0) # Adds a warm sunrise and sunset band near the horizon.
const TWILIGHT_GROUND_BOTTOM: Color = Color(0.035, 0.025, 0.032, 1.0) # Warms the lower hemisphere slightly during twilight.
const TWILIGHT_GROUND_HORIZON: Color = Color(0.34, 0.16, 0.12, 1.0) # Reflects the warm horizon colour beneath the world.
const NIGHT_AMBIENT_COLOR: Color = Color(0.12, 0.18, 0.30, 1.0) # Provides dim cool ambient light during night.
const DAY_AMBIENT_COLOR: Color = Color(0.70, 0.77, 0.86, 1.0) # Retains the original daylight ambient colour.
const TWILIGHT_AMBIENT_COLOR: Color = Color(0.54, 0.30, 0.26, 1.0) # Adds warm indirect light near sunrise and sunset.
const NIGHT_FOG_COLOR: Color = Color(0.035, 0.055, 0.10, 1.0) # Keeps distant night terrain cool and dark.
const DAY_FOG_COLOR: Color = Color(0.62, 0.71, 0.80, 1.0) # Retains the original daytime fog colour.
const TWILIGHT_FOG_COLOR: Color = Color(0.56, 0.27, 0.18, 1.0) # Colours distant terrain warmly at sunrise and sunset.
const DAY_SUN_COLOR: Color = Color(1.0, 0.92, 0.80, 1.0) # Retains the original warm daylight colour.
const TWILIGHT_SUN_COLOR: Color = Color(1.0, 0.39, 0.16, 1.0) # Makes low-angle sunlight orange at dawn and dusk.
const MOON_COLOR: Color = Color(0.48, 0.58, 0.82, 1.0) # Gives moonlight a restrained cool-blue tone.

@onready var _world_environment: WorldEnvironment = $WorldEnvironment # Owns the procedural sky and environment lighting values.
@onready var _sun: DirectionalLight3D = $Sun # Provides the primary daylight and sunrise or sunset shadows.
@onready var _moon: DirectionalLight3D = $Moon # Provides low-intensity illumination while the sun is below the horizon.

var _environment: Environment # Stores the mutable environment resource used by the active world.
var _sky_material: ProceduralSkyMaterial # Stores the procedural sky colours updated through the cycle.
var _time_of_day_hours: float = 8.0 # Starts the world in clear morning light.
var _speed_multiplier: float = 1.0 # Scales the normal twenty-minute full-day duration.
var _sky_update_accumulator: float = 0.0 # Throttles comparatively expensive environment resource updates.

func _ready() -> void: # Resolves scene resources and applies the initial world time before the first rendered frame.
    add_to_group(GROUP_NAME) # Makes this cycle discoverable by the developer console.
    _environment = _world_environment.environment # Captures the world environment authored in the scene.
    if _environment != null and _environment.sky != null: # Confirms the scene contains a procedural sky resource.
        _sky_material = _environment.sky.sky_material as ProceduralSkyMaterial # Captures the mutable material used by the sky.
    _apply_cycle_state(true) # Applies initial sun, moon, sky, fog, and ambient values immediately.

func _process(delta: float) -> void: # Advances world time and keeps visible lighting synchronized.
    if _speed_multiplier > 0.0: # Allows a zero multiplier to pause the clock without stopping visual updates.
        var hours_per_second: float = HOURS_PER_DAY / DEFAULT_FULL_DAY_SECONDS # Converts real seconds into ordinary game-world hours.
        _time_of_day_hours = fposmod(_time_of_day_hours + delta * hours_per_second * _speed_multiplier, HOURS_PER_DAY) # Advances and wraps the clock continuously.
    _update_celestial_lights() # Moves the sun and moon every frame for smooth shadows and light direction.
    _sky_update_accumulator += delta # Accumulates time toward the next environment refresh.
    if _sky_update_accumulator >= SKY_UPDATE_INTERVAL: # Detects when the procedural sky and fog should be refreshed.
        _sky_update_accumulator = fposmod(_sky_update_accumulator, SKY_UPDATE_INTERVAL) # Retains any fractional excess for stable update cadence.
        _update_environment() # Updates sky colours, ambient light, and fog at a bounded rate.

func set_speed_multiplier(multiplier: float) -> void: # Changes cycle speed while keeping the accepted range safe and predictable.
    _speed_multiplier = clampf(multiplier, 0.0, MAXIMUM_SPEED_MULTIPLIER) # Supports pause at zero and very fast debugging without negative time.

func get_speed_multiplier() -> float: # Reports the active console-configurable cycle multiplier.
    return _speed_multiplier # Returns the exact stored multiplier.

func set_time_of_day_hours(hours: float) -> void: # Moves the world clock directly for testing specific lighting conditions.
    _time_of_day_hours = fposmod(hours, HOURS_PER_DAY) # Accepts arbitrary hour values while normalizing into one day.
    _apply_cycle_state(true) # Refreshes all lighting immediately rather than waiting for the next process frame.

func get_time_of_day_hours() -> float: # Reports the current normalized time for gameplay and developer tools.
    return _time_of_day_hours # Returns hours in the range from zero inclusive to twenty-four exclusive.

func get_formatted_time() -> String: # Formats the world clock as a compact twenty-four-hour time.
    var total_minutes: int = posmod(roundi(_time_of_day_hours * 60.0), 24 * 60) # Converts fractional hours into a wrapped minute count.
    var hour: int = total_minutes / 60 # Extracts the displayed hour.
    var minute: int = total_minutes % 60 # Extracts the displayed minute.
    return "%02d:%02d" % [hour, minute] # Returns a stable console-readable time string.

func get_effective_full_day_seconds() -> float: # Reports the current real-time duration of one complete in-game day.
    if is_zero_approx(_speed_multiplier): # Detects a paused clock where no finite duration exists.
        return 0.0 # Uses zero as the explicit paused sentinel for console reporting.
    return DEFAULT_FULL_DAY_SECONDS / _speed_multiplier # Converts the multiplier into the effective full-day duration.

func _apply_cycle_state(force_environment_update: bool) -> void: # Applies all visual state after initialization or direct console changes.
    _update_celestial_lights() # Updates light direction, colour, energy, visibility, and shadows.
    if force_environment_update: # Detects direct changes that should update the sky without throttling.
        _update_environment() # Updates sky, ambient light, and fog immediately.
        _sky_update_accumulator = 0.0 # Restarts the bounded environment update interval.

func _update_celestial_lights() -> void: # Rotates and fades the sun and moon based on the current solar phase.
    var solar_phase: float = (_time_of_day_hours - 6.0) / HOURS_PER_DAY * TAU # Places sunrise at 06:00, noon at 12:00, and sunset at 18:00.
    var solar_height: float = sin(solar_phase) # Produces negative night values, zero at the horizon, and one at noon.
    var sun_pitch_degrees: float = -rad_to_deg(solar_phase) # Converts solar phase into the directional-light elevation used by Godot.
    _sun.rotation_degrees = Vector3(sun_pitch_degrees, SUN_AZIMUTH_DEGREES, 0.0) # Moves sunlight continuously across the sky.
    _moon.rotation_degrees = Vector3(sun_pitch_degrees - 180.0, SUN_AZIMUTH_DEGREES + 180.0, 0.0) # Keeps moonlight opposite the sun.

    var sun_visibility: float = smoothstep(-0.08, 0.18, solar_height) # Fades sunlight smoothly through civil twilight.
    var moon_visibility: float = smoothstep(-0.08, 0.22, -solar_height) # Fades moonlight in as the sun passes below the horizon.
    var sun_colour_weight: float = smoothstep(0.0, 0.42, solar_height) # Transitions low-angle orange light into ordinary daylight.
    _sun.light_color = TWILIGHT_SUN_COLOR.lerp(DAY_SUN_COLOR, sun_colour_weight) # Applies sunrise, daylight, and sunset colour.
    _sun.light_energy = SUN_MAXIMUM_ENERGY * sun_visibility # Scales sunlight from darkness to full midday intensity.
    _sun.visible = sun_visibility > 0.002 # Avoids rendering an irrelevant directional light deep at night.
    _sun.shadow_enabled = sun_visibility > 0.04 # Avoids maintaining sun shadow maps when sunlight is effectively absent.
    _moon.light_color = MOON_COLOR # Applies the authored cool moonlight colour.
    _moon.light_energy = MOON_MAXIMUM_ENERGY * moon_visibility # Provides restrained night illumination.
    _moon.visible = moon_visibility > 0.002 # Avoids rendering an irrelevant moon light during the day.

func _update_environment() -> void: # Blends procedural sky, ambient light, and fog through night, twilight, and day.
    if _environment == null: # Handles a malformed scene without an environment resource defensively.
        return # Leaves directional lights functional even when environment data is unavailable.
    var solar_phase: float = (_time_of_day_hours - 6.0) / HOURS_PER_DAY * TAU # Reconstructs the current solar position for environment blending.
    var solar_height: float = sin(solar_phase) # Produces the signed height of the sun relative to the horizon.
    var day_weight: float = smoothstep(-0.12, 0.26, solar_height) # Fades the broad environment from night into full daylight.
    var night_weight: float = 1.0 - smoothstep(-0.30, 0.05, solar_height) # Identifies the darkest portion of the cycle.
    var twilight_weight: float = (1.0 - smoothstep(0.0, 0.42, absf(solar_height))) * (1.0 - night_weight * 0.35) # Peaks around sunrise and sunset while suppressing midnight warmth.

    if _sky_material != null: # Confirms the scene is still using its procedural sky material.
        _sky_material.sky_top_color = _blend_cycle_colour(NIGHT_SKY_TOP, DAY_SKY_TOP, TWILIGHT_SKY_TOP, day_weight, twilight_weight, 0.72) # Updates the upper sky.
        _sky_material.sky_horizon_color = _blend_cycle_colour(NIGHT_SKY_HORIZON, DAY_SKY_HORIZON, TWILIGHT_SKY_HORIZON, day_weight, twilight_weight, 0.92) # Updates the horizon band.
        _sky_material.ground_bottom_color = _blend_cycle_colour(NIGHT_GROUND_BOTTOM, DAY_GROUND_BOTTOM, TWILIGHT_GROUND_BOTTOM, day_weight, twilight_weight, 0.60) # Updates the lower sky hemisphere.
        _sky_material.ground_horizon_color = _blend_cycle_colour(NIGHT_GROUND_HORIZON, DAY_GROUND_HORIZON, TWILIGHT_GROUND_HORIZON, day_weight, twilight_weight, 0.75) # Updates the lower horizon band.

    _environment.ambient_light_color = _blend_cycle_colour(NIGHT_AMBIENT_COLOR, DAY_AMBIENT_COLOR, TWILIGHT_AMBIENT_COLOR, day_weight, twilight_weight, 0.38) # Colours indirect lighting appropriately.
    _environment.ambient_light_energy = lerpf(0.12, 0.50, day_weight) # Keeps night navigable while preserving a clear daylight contrast.
    _environment.fog_light_color = _blend_cycle_colour(NIGHT_FOG_COLOR, DAY_FOG_COLOR, TWILIGHT_FOG_COLOR, day_weight, twilight_weight, 0.72) # Colours distant terrain and atmosphere.
    _environment.fog_light_energy = lerpf(0.18, 0.58, day_weight) # Reduces fog brightness at night without disabling atmospheric depth.

func _blend_cycle_colour(night_colour: Color, day_colour: Color, twilight_colour: Color, day_weight: float, twilight_weight: float, twilight_strength: float) -> Color: # Resolves one colour through night, daylight, and horizon transitions.
    var base_colour: Color = night_colour.lerp(day_colour, day_weight) # Establishes the broad night-to-day blend.
    return base_colour.lerp(twilight_colour, clampf(twilight_weight * twilight_strength, 0.0, 1.0)) # Adds the temporary sunrise or sunset colour.
