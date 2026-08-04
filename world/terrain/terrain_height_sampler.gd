extends RefCounted # Provides a lightweight deterministic terrain-height service without scene-tree ownership.
class_name TerrainHeightSampler # Makes the sampler available to terrain generation and future world tools.

const WORLD_SEED: int = 742_913 # Keeps the generated landscape stable between playthroughs and builds.
const WORLD_FEATURE_SCALE: float = 1.75 # Expands every procedural landform horizontally without changing deterministic world coordinates.
const SPAWN_FLAT_HEIGHT: float = 0.0 # Defines the exact world elevation of the circular initial spawn platform.
const SPAWN_FLAT_RADIUS: float = 8.0 # Keeps several metres around world origin completely level for safe spawning.
const SPAWN_FLAT_BLEND_RADIUS: float = 24.0 # Blends the flat platform smoothly into nearby procedural terrain.
const SPAWN_INNER_RADIUS: float = 180.0 # Keeps a larger immediate starting region comparatively gentle and traversable.
const SPAWN_OUTER_RADIUS: float = 520.0 # Blends the expanded starting region into the full terrain profile over distance.
const WARP_DISTANCE: float = 170.0 # Bends scaled noise coordinates so large landforms avoid obvious straight procedural bands.
const MOUNTAIN_HEIGHT: float = 250.0 # Sets the maximum contribution from the broad primary mountain system.
const MOUNTAIN_DETAIL_HEIGHT: float = 42.0 # Adds restrained secondary ridges without creating needle-like summit spikes.
const VALLEY_DEPTH: float = 90.0 # Carves broad deep drainage-like valleys through hills and mountain regions.
const CREVASSE_DEPTH: float = 48.0 # Carves substantial channels where the crevasse-region mask permits them.
const TERRACE_MINIMUM_STEP: float = 12.0 # Sets the smallest vertical interval used by the enlarged mountain terraces.
const TERRACE_STEP_RANGE: float = 10.0 # Varies terrace spacing to prevent mechanically repeated tiers.
const PRIMARY_MOUNTAIN_EXPONENT: float = 1.7 # Shapes broad rounded primary ridges while retaining imposing mountain mass.
const SECONDARY_MOUNTAIN_EXPONENT: float = 2.25 # Restricts secondary ridge height to strong geological shoulders.
const SUMMIT_DETAIL_FADE_START: float = 0.72 # Begins suppressing high-frequency ridge detail near primary summits.
const SUMMIT_DETAIL_FADE_END: float = 0.96 # Removes secondary detail before the primary ridge reaches its rounded crest.
const SURFACE_DETAIL_HEIGHT: float = 3.0 # Keeps close-range variation visible without creating isolated coarse-grid spikes.

var _warp_x_noise: FastNoiseLite # Distorts horizontal sampling along the world x axis.
var _warp_z_noise: FastNoiseLite # Distorts horizontal sampling along the world z axis.
var _continent_noise: FastNoiseLite # Produces the broadest rises and depressions across the landscape.
var _rolling_hill_noise: FastNoiseLite # Produces long rolling hills between major terrain features.
var _hill_detail_noise: FastNoiseLite # Breaks broad hills into smaller shoulders and folds.
var _mountain_region_noise: FastNoiseLite # Determines where large mountain systems are allowed to form.
var _mountain_ridge_noise: FastNoiseLite # Produces the main rounded ridge structure inside mountain regions.
var _mountain_detail_noise: FastNoiseLite # Adds restrained secondary mountain ridges and broken slopes.
var _terrace_noise: FastNoiseLite # Varies the strength and spacing of mountain tiers.
var _valley_noise: FastNoiseLite # Produces broad winding valley centre lines.
var _crevasse_region_noise: FastNoiseLite # Restricts crevasses to selected geological regions.
var _crevasse_noise: FastNoiseLite # Produces broad winding crevasse centre lines.
var _surface_detail_noise: FastNoiseLite # Adds restrained small terrain variation after major landforms are combined.

func _init() -> void: # Builds every deterministic noise source used by the height function.
    _warp_x_noise = _create_noise(11, 0.0018, 3, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates slowly varying x-axis coordinate distortion.
    _warp_z_noise = _create_noise(23, 0.0018, 3, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates independently varying z-axis coordinate distortion.
    _continent_noise = _create_noise(37, 0.00042, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates landforms spanning several enlarged kilometres.
    _rolling_hill_noise = _create_noise(41, 0.00135, 4, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates long slopes and rolling highlands with reduced high-frequency chatter.
    _hill_detail_noise = _create_noise(53, 0.0042, 3, 0.48, 2.1, FastNoiseLite.FRACTAL_FBM) # Creates broad secondary folds suited to the coarser terrain grid.
    _mountain_region_noise = _create_noise(67, 0.0007, 3, 0.54, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates large coherent mountain provinces.
    _mountain_ridge_noise = _create_noise(71, 0.00155, 4, 0.5, 2.05, FastNoiseLite.FRACTAL_RIDGED) # Creates broad primary mountain ridges without excessive fine peaks.
    _mountain_detail_noise = _create_noise(83, 0.0055, 3, 0.48, 2.1, FastNoiseLite.FRACTAL_RIDGED) # Creates restrained secondary mountain structures.
    _terrace_noise = _create_noise(97, 0.0026, 3, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Varies mountain tier spacing and blend strength.
    _valley_noise = _create_noise(101, 0.00105, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates broad meandering valley paths.
    _crevasse_region_noise = _create_noise(113, 0.0019, 3, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates patches where enlarged fissures can appear.
    _crevasse_noise = _create_noise(127, 0.0068, 3, 0.5, 2.05, FastNoiseLite.FRACTAL_FBM) # Creates winding channels without isolated needle-like cuts.
    _surface_detail_noise = _create_noise(139, 0.014, 2, 0.42, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates restrained close-range variation for the coarser surface.

func sample_height(world_x: float, world_z: float) -> float: # Returns the deterministic terrain height at one world-space horizontal position.
    var scaled_world_x: float = world_x / WORLD_FEATURE_SCALE # Converts world x into enlarged procedural feature space.
    var scaled_world_z: float = world_z / WORLD_FEATURE_SCALE # Converts world z into enlarged procedural feature space.
    var warp_x: float = _warp_x_noise.get_noise_2d(scaled_world_x, scaled_world_z) * WARP_DISTANCE # Calculates horizontal distortion from the first warp field.
    var warp_z: float = _warp_z_noise.get_noise_2d(scaled_world_x, scaled_world_z) * WARP_DISTANCE # Calculates horizontal distortion from the second warp field.
    var sample_x: float = scaled_world_x + warp_x # Applies the x-axis distortion before sampling enlarged landforms.
    var sample_z: float = scaled_world_z + warp_z # Applies the z-axis distortion before sampling enlarged landforms.
    var continental_height: float = _continent_noise.get_noise_2d(sample_x, sample_z) * 52.0 # Establishes broad regional elevation changes.
    var rolling_height: float = _rolling_hill_noise.get_noise_2d(sample_x, sample_z) * 31.0 # Adds long rolling hills to the regional elevation.
    var hill_detail: float = _hill_detail_noise.get_noise_2d(sample_x, sample_z) * 10.0 # Adds restrained secondary folds to rolling terrain.
    var mountain_region_value: float = (_mountain_region_noise.get_noise_2d(sample_x, sample_z) + 1.0) * 0.5 # Converts the mountain-region field into a normalized mask input.
    var mountain_mask: float = smoothstep(0.48, 0.79, mountain_region_value) # Restricts mountains to broad coherent regions with soft boundaries.
    var primary_ridge: float = clampf((_mountain_ridge_noise.get_noise_2d(sample_x, sample_z) + 1.0) * 0.5, 0.0, 1.0) # Normalizes the primary ridged field.
    var secondary_ridge: float = clampf((_mountain_detail_noise.get_noise_2d(sample_x, sample_z) + 1.0) * 0.5, 0.0, 1.0) # Normalizes the secondary ridged field.
    var rounded_primary_ridge: float = sin(primary_ridge * PI * 0.5) # Flattens the derivative near ridge maxima so primary summits cannot form sharp needles.
    var rounded_secondary_ridge: float = sin(secondary_ridge * PI * 0.5) # Rounds secondary ridge maxima before they contribute to mountain height.
    var primary_mountain_height: float = pow(rounded_primary_ridge, PRIMARY_MOUNTAIN_EXPONENT) * MOUNTAIN_HEIGHT # Builds the broad primary mountain mass.
    var summit_detail_weight: float = 1.0 - smoothstep(SUMMIT_DETAIL_FADE_START, SUMMIT_DETAIL_FADE_END, rounded_primary_ridge) # Suppresses high-frequency detail as the primary ridge approaches its crest.
    var secondary_mountain_height: float = pow(rounded_secondary_ridge, SECONDARY_MOUNTAIN_EXPONENT) * MOUNTAIN_DETAIL_HEIGHT * summit_detail_weight # Adds shoulders and side ridges without stacking spikes onto summits.
    var mountain_height: float = mountain_mask * (primary_mountain_height + secondary_mountain_height) # Combines rounded primary mass and summit-safe secondary detail.
    var terrace_value: float = (_terrace_noise.get_noise_2d(sample_x, sample_z) + 1.0) * 0.5 # Produces a normalized local terrace-control value.
    var terrace_step: float = TERRACE_MINIMUM_STEP + terrace_value * TERRACE_STEP_RANGE # Varies vertical tier spacing across each mountain system.
    var terraced_height: float = snappedf(mountain_height, terrace_step) # Produces discrete mountain shelves before blending.
    var terrace_strength: float = mountain_mask * lerpf(0.14, 0.32, terrace_value) # Keeps larger tiers visible while preserving continuous climbable slopes.
    mountain_height = lerpf(mountain_height, terraced_height, terrace_strength) # Blends terraces into the mountain rather than creating full vertical steps.
    var valley_line: float = 1.0 - clampf(absf(_valley_noise.get_noise_2d(sample_x, sample_z)) * 2.45, 0.0, 1.0) # Finds areas close to broader valley centre lines.
    var valley_cut: float = pow(valley_line, 2.8) * VALLEY_DEPTH * lerpf(0.72, 1.0, mountain_mask) # Carves wide deep valleys that continue through mountain regions.
    var crevasse_region_value: float = (_crevasse_region_noise.get_noise_2d(sample_x, sample_z) + 1.0) * 0.5 # Converts the fissure-region field into a normalized mask input.
    var crevasse_region_mask: float = smoothstep(0.57, 0.76, crevasse_region_value) # Limits fissures to selected areas instead of covering every biome.
    var crevasse_line: float = 1.0 - clampf(absf(_crevasse_noise.get_noise_2d(sample_x, sample_z)) * 7.0, 0.0, 1.0) # Finds broader positions close to crevasse centre lines.
    var crevasse_cut: float = pow(crevasse_line, 4.2) * CREVASSE_DEPTH * crevasse_region_mask # Carves substantial channels without one-vertex downward spikes.
    var surface_detail: float = _surface_detail_noise.get_noise_2d(sample_x, sample_z) * SURFACE_DETAIL_HEIGHT # Adds restrained close-range variation to the final surface.
    var full_height: float = continental_height + rolling_height + hill_detail + mountain_height - valley_cut - crevasse_cut + surface_detail # Combines every major and minor landform into one continuous height.
    var spawn_distance: float = Vector2(world_x, world_z).length() # Measures distance from the world-origin spawn centre.
    var spawn_blend: float = smoothstep(SPAWN_INNER_RADIUS, SPAWN_OUTER_RADIUS, spawn_distance) # Gradually introduces extreme landforms outside the enlarged starting area.
    var spawn_height: float = continental_height * 0.28 + rolling_height * 0.58 + hill_detail * 0.35 + surface_detail * 0.25 # Creates a gently varied but non-flat starting landscape.
    var procedural_height: float = lerpf(spawn_height, full_height, spawn_blend) # Resolves the ordinary gentle-to-complex terrain profile before the spawn stamp is applied.
    var flat_blend: float = smoothstep(SPAWN_FLAT_RADIUS, SPAWN_FLAT_BLEND_RADIUS, spawn_distance) # Keeps the inner circle level and eases its edge into nearby terrain.
    return lerpf(SPAWN_FLAT_HEIGHT, procedural_height, flat_blend) # Returns exact zero-height terrain near origin with a continuous outer transition.

func _create_noise(seed_offset: int, frequency: float, octaves: int, gain: float, lacunarity: float, fractal_type: int) -> FastNoiseLite: # Creates one consistently configured noise resource.
    var noise: FastNoiseLite = FastNoiseLite.new() # Allocates an independent noise generator for one terrain role.
    noise.seed = WORLD_SEED + seed_offset # Derives a stable unique seed from the shared world seed.
    noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH # Uses smooth simplex noise for coherent natural-looking fields.
    noise.frequency = frequency # Sets the physical scale represented by the noise field.
    noise.fractal_type = fractal_type # Selects ordinary or ridged fractal accumulation for this terrain role.
    noise.fractal_octaves = octaves # Sets the number of detail layers accumulated by the field.
    noise.fractal_gain = gain # Controls how strongly each finer octave contributes.
    noise.fractal_lacunarity = lacunarity # Controls the frequency increase between successive octaves.
    return noise # Returns the configured deterministic noise resource.
