extends Node3D # Advances world time and synchronizes celestial lighting, sky, ambient light, and fog.
class_name DayNightCycle # Exposes time controls to the developer console without a global singleton.

const GROUP_NAME: StringName = &"day_night_cycle" # Lets developer tools resolve the active cycle independently of scene hierarchy.
const HOURS_PER_DAY: float = 24.0 # Defines one complete solar rotation.
const DEFAULT_FULL_DAY_SECONDS: float = 1200.0 # Makes one ordinary in-game day last twenty real minutes at normal speed.
const MAXIMUM_SPEED_MULTIPLIER: float = 1000.0 # Bounds accelerated debugging to a predictable range.
const ENVIRONMENT_UPDATE_INTERVAL: float = 0.25 # Limits procedural-sky and radiance updates to four times per second.
const SUN_AZIMUTH_DEGREES: float = -32.0 # Preserves the original horizontal light direction.
const SUN_MAXIMUM_ENERGY: float = 1.2 # Matches the original midday light strength.
const MOON_MAXIMUM_ENERGY: float = 0.16 # Provides restrained night illumination.

const NIGHT_SKY_TOP: Color = Color(0.008, 0.014, 0.045, 1.0)
const NIGHT_SKY_HORIZON: Color = Color(0.025, 0.045, 0.095, 1.0)
const NIGHT_GROUND_BOTTOM: Color = Color(0.008, 0.012, 0.018, 1.0)
const NIGHT_GROUND_HORIZON: Color = Color(0.025, 0.035, 0.055, 1.0)
const DAY_SKY_TOP: Color = Color(0.12, 0.29, 0.55, 1.0)
const DAY_SKY_HORIZON: Color = Color(0.68, 0.79, 0.90, 1.0)
const DAY_GROUND_BOTTOM: Color = Color(0.05, 0.07, 0.08, 1.0)
const DAY_GROUND_HORIZON: Color = Color(0.40, 0.46, 0.50, 1.0)
const TWILIGHT_SKY_TOP: Color = Color(0.10, 0.12, 0.28, 1.0)
const TWILIGHT_SKY_HORIZON: Color = Color(0.92, 0.34, 0.12, 1.0)
const TWILIGHT_GROUND_BOTTOM: Color = Color(0.035, 0.025, 0.032, 1.0)
const TWILIGHT_GROUND_HORIZON: Color = Color(0.34, 0.16, 0.12, 1.0)
const NIGHT_AMBIENT_COLOR: Color = Color(0.12, 0.18, 0.30, 1.0)
const DAY_AMBIENT_COLOR: Color = Color(0.70, 0.77, 0.86, 1.0)
const TWILIGHT_AMBIENT_COLOR: Color = Color(0.54, 0.30, 0.26, 1.0)
const NIGHT_FOG_COLOR: Color = Color(0.035, 0.055, 0.10, 1.0)
const DAY_FOG_COLOR: Color = Color(0.62, 0.71, 0.80, 1.0)
const TWILIGHT_FOG_COLOR: Color = Color(0.56, 0.27, 0.18, 1.0)
const DAY_SUN_COLOR: Color = Color(1.0, 0.92, 0.80, 1.0)
const TWILIGHT_SUN_COLOR: Color = Color(1.0, 0.39, 0.16, 1.0)
const MOON_COLOR: Color = Color(0.48, 0.58, 0.82, 1.0)

@onready var _world_environment: WorldEnvironment = $WorldEnvironment # Owns the procedural sky and environment resource.
@onready var _sun: DirectionalLight3D = $Sun # Provides daylight and sun shadows.
@onready var _moon: DirectionalLight3D = $Moon # Provides low-intensity night illumination.

var _environment: Environment # Stores the mutable environment resource.
var _sky_material: ProceduralSkyMaterial # Stores the procedural sky material when available.
var _time_of_day_hours: float = 8.0 # Starts the world in morning light.
var _speed_multiplier: float = 1.0 # Scales the default twenty-minute full day.
var _environment_update_accumulator: float = 0.0 # Throttles comparatively expensive sky updates.

func _ready() -> void: # Resolves resources and applies the initial lighting state.
    add_to_group(GROUP_NAME) # Makes this cycle discoverable by the developer console.
    _environment = _world_environment.environment # Captures the environment authored in the world scene.
    if _environment != null and _environment.sky != null: # Confirms a sky resource is available.
        _sky_material = _environment.sky.sky_material as ProceduralSkyMaterial # Captures its mutable procedural material.
    _apply_cycle_state() # Applies sun, moon, sky, fog, and ambient values before the first frame.

func _process(delta: float) -> void: # Advances time and updates visible world lighting.
    if is_zero_approx(_speed_multiplier): # Detects a paused clock.
        return # Avoids repeating identical light and sky resource writes while paused.
    var hours_per_second: float = HOURS_PER_DAY / DEFAULT_FULL_DAY_SECONDS # Converts real seconds into game-world hours.
    _time_of_day_hours = fposmod(_time_of_day_hours + delta * hours_per_second * _speed_multiplier, HOURS_PER_DAY) # Advances and wraps the clock.
    _update_celestial_lights() # Moves the sun and moon every frame for smooth light direction.
    _environment_update_accumulator += delta # Accumulates time toward the next sky refresh.
    if _environment_update_accumulator >= ENVIRONMENT_UPDATE_INTERVAL: # Detects when environment resources should be refreshed.
        _environment_update_accumulator = fposmod(_environment_update_accumulator, ENVIRONMENT_UPDATE_INTERVAL) # Retains fractional excess for stable cadence.
        _update_environment() # Updates sky colours, ambient light, and fog at a bounded rate.

func set_speed_multiplier(multiplier: float) -> void: # Changes cycle speed safely.
    _speed_multiplier = clampf(multiplier, 0.0, MAXIMUM_SPEED_MULTIPLIER) # Supports pause at zero and accelerated testing.

func get_speed_multiplier() -> float: # Reports the active multiplier.
    return _speed_multiplier

func set_time_of_day_hours(hours: float) -> void: # Moves directly to a requested lighting condition.
    _time_of_day_hours = fposmod(hours, HOURS_PER_DAY) # Normalizes arbitrary input into one day.
    _apply_cycle_state() # Refreshes all visible state immediately.

func get_time_of_day_hours() -> float: # Reports the current normalized hour.
    return _time_of_day_hours

func get_formatted_time() -> String: # Formats the clock as twenty-four-hour time.
    var total_minutes: int = posmod(roundi(_time_of_day_hours * 60.0), 24 * 60) # Converts fractional hours into wrapped minutes.
    return "%02d:%02d" % [total_minutes / 60, total_minutes % 60] # Returns a stable console-readable value.

func get_effective_full_day_seconds() -> float: # Reports the real duration of one full in-game day.
    if is_zero_approx(_speed_multiplier): # Detects a paused cycle.
        return 0.0 # Uses zero as an explicit paused sentinel.
    return DEFAULT_FULL_DAY_SECONDS / _speed_multiplier # Converts multiplier into effective duration.

func _apply_cycle_state() -> void: # Applies every visual component after initialization or a direct console change.
    _update_celestial_lights() # Updates directional lights immediately.
    _update_environment() # Updates sky, ambient light, and fog immediately.
    _environment_update_accumulator = 0.0 # Restarts the bounded environment interval.

func _get_solar_height() -> float: # Returns signed sun height relative to the horizon.
    var solar_phase: float = (_time_of_day_hours - 6.0) / HOURS_PER_DAY * TAU # Places sunrise at 06:00 and sunset at 18:00.
    return sin(solar_phase) # Returns -1 at midnight, 0 at the horizon, and 1 at noon.

func _update_celestial_lights() -> void: # Rotates and fades the sun and moon through the day.
    var solar_phase: float = (_time_of_day_hours - 6.0) / HOURS_PER_DAY * TAU # Reconstructs the complete solar rotation.
    var solar_height: float = sin(solar_phase) # Measures height above or below the horizon.
    var sun_pitch_degrees: float = -rad_to_deg(solar_phase) # Converts phase into Godot directional-light rotation.
    _sun.rotation_degrees = Vector3(sun_pitch_degrees, SUN_AZIMUTH_DEGREES, 0.0) # Moves sunlight continuously across the sky.
    _moon.rotation_degrees = Vector3(sun_pitch_degrees - 180.0, SUN_AZIMUTH_DEGREES + 180.0, 0.0) # Keeps the moon opposite the sun.

    var sun_visibility: float = smoothstep(-0.08, 0.18, solar_height) # Fades sunlight smoothly through twilight.
    var moon_visibility: float = smoothstep(-0.08, 0.22, -solar_height) # Fades moonlight in after sunset.
    _sun.light_color = TWILIGHT_SUN_COLOR.lerp(DAY_SUN_COLOR, smoothstep(0.0, 0.42, solar_height)) # Transitions orange low-angle light into daylight.
    _sun.light_energy = SUN_MAXIMUM_ENERGY * sun_visibility # Scales sunlight from darkness to midday.
    _sun.visible = sun_visibility > 0.002 # Removes an irrelevant sun light deep at night.
    var sun_shadows_enabled: bool = sun_visibility > 0.04 # Determines whether sunlight is strong enough to justify shadow rendering.
    if _sun.shadow_enabled != sun_shadows_enabled: # Avoids repeatedly resetting the same shadow state.
        _sun.shadow_enabled = sun_shadows_enabled # Enables shadows only while visibly useful.
    _moon.light_color = MOON_COLOR # Applies cool moonlight.
    _moon.light_energy = MOON_MAXIMUM_ENERGY * moon_visibility # Provides restrained night visibility.
    _moon.visible = moon_visibility > 0.002 # Removes the moon light during daylight.

func _update_environment() -> void: # Blends sky, ambient light, and fog through night, twilight, and day.
    if _environment == null: # Handles a malformed scene defensively.
        return # Leaves directional lighting functional.
    var solar_height: float = _get_solar_height() # Reuses the signed sun height for all environment blends.
    var day_weight: float = smoothstep(-0.12, 0.26, solar_height) # Fades broad environment lighting into daylight.
    var night_weight: float = 1.0 - smoothstep(-0.30, 0.05, solar_height) # Identifies the darkest part of night.
    var twilight_weight: float = (1.0 - smoothstep(0.0, 0.42, absf(solar_height))) * (1.0 - night_weight * 0.35) # Peaks near sunrise and sunset.

    if _sky_material != null: # Confirms the procedural sky remains available.
        _sky_material.sky_top_color = _blend_cycle_colour(NIGHT_SKY_TOP, DAY_SKY_TOP, TWILIGHT_SKY_TOP, day_weight, twilight_weight, 0.72)
        _sky_material.sky_horizon_color = _blend_cycle_colour(NIGHT_SKY_HORIZON, DAY_SKY_HORIZON, TWILIGHT_SKY_HORIZON, day_weight, twilight_weight, 0.92)
        _sky_material.ground_bottom_color = _blend_cycle_colour(NIGHT_GROUND_BOTTOM, DAY_GROUND_BOTTOM, TWILIGHT_GROUND_BOTTOM, day_weight, twilight_weight, 0.60)
        _sky_material.ground_horizon_color = _blend_cycle_colour(NIGHT_GROUND_HORIZON, DAY_GROUND_HORIZON, TWILIGHT_GROUND_HORIZON, day_weight, twilight_weight, 0.75)

    _environment.ambient_light_color = _blend_cycle_colour(NIGHT_AMBIENT_COLOR, DAY_AMBIENT_COLOR, TWILIGHT_AMBIENT_COLOR, day_weight, twilight_weight, 0.38) # Colours indirect lighting.
    _environment.ambient_light_energy = lerpf(0.12, 0.50, day_weight) # Keeps night navigable while preserving contrast.
    _environment.fog_light_color = _blend_cycle_colour(NIGHT_FOG_COLOR, DAY_FOG_COLOR, TWILIGHT_FOG_COLOR, day_weight, twilight_weight, 0.72) # Colours distant terrain.
    _environment.fog_light_energy = lerpf(0.18, 0.58, day_weight) # Reduces fog brightness at night.

func _blend_cycle_colour(night_colour: Color, day_colour: Color, twilight_colour: Color, day_weight: float, twilight_weight: float, twilight_strength: float) -> Color: # Resolves one colour across the complete cycle.
    var base_colour: Color = night_colour.lerp(day_colour, day_weight) # Establishes the broad night-to-day blend.
    return base_colour.lerp(twilight_colour, clampf(twilight_weight * twilight_strength, 0.0, 1.0)) # Adds temporary sunrise or sunset colour.
