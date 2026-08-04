extends RefCounted # Provides a lightweight deterministic terrain-height service without scene-tree ownership.
class_name TerrainHeightSampler # Makes the sampler available to terrain generation and future world tools.

const WORLD_SEED: int = 742_913 # Keeps the generated landscape stable between playthroughs and builds.
const SPAWN_INNER_RADIUS: float = 110.0 # Keeps the immediate starting area comparatively gentle and traversable.
const SPAWN_OUTER_RADIUS: float = 320.0 # Blends the starting area into the full terrain profile over distance.
const WARP_DISTANCE: float = 170.0 # Bends noise coordinates so landforms avoid obvious straight procedural bands.
const MOUNTAIN_HEIGHT: float = 235.0 # Sets the maximum contribution from the primary mountain system.
const MOUNTAIN_DETAIL_HEIGHT: float = 58.0 # Adds secondary ridges and shoulders to mountain silhouettes.
const VALLEY_DEPTH: float = 82.0 # Carves broad drainage-like valleys through hills and mountain regions.
const CREVASSE_DEPTH: float = 48.0 # Carves narrow steep channels where the crevasse-region mask permits them.
const TERRACE_MINIMUM_STEP: float = 9.0 # Sets the smallest vertical interval used by mountain terraces.
const TERRACE_STEP_RANGE: float = 8.0 # Varies terrace spacing to prevent mechanically repeated tiers.

var _warp_x_noise: FastNoiseLite # Distorts horizontal sampling along the world x axis.
var _warp_z_noise: FastNoiseLite # Distorts horizontal sampling along the world z axis.
var _continent_noise: FastNoiseLite # Produces the broadest rises and depressions across the landscape.
var _rolling_hill_noise: FastNoiseLite # Produces long rolling hills between major terrain features.
var _hill_detail_noise: FastNoiseLite # Breaks broad hills into smaller shoulders and folds.
var _mountain_region_noise: FastNoiseLite # Determines where large mountain systems are allowed to form.
var _mountain_ridge_noise: FastNoiseLite # Produces the main sharp ridge structure inside mountain regions.
var _mountain_detail_noise: FastNoiseLite # Adds secondary mountain ridges and broken slopes.
var _terrace_noise: FastNoiseLite # Varies the strength and spacing of mountain tiers.
var _valley_noise: FastNoiseLite # Produces broad winding valley centre lines.
var _crevasse_region_noise: FastNoiseLite # Restricts narrow crevasses to selected geological regions.
var _crevasse_noise: FastNoiseLite # Produces narrow high-frequency crevasse centre lines.
var _surface_detail_noise: FastNoiseLite # Adds small terrain variation after the major landforms are combined.

func _init() -> void: # Builds every deterministic noise source used by the height function.
    _warp_x_noise = _create_noise(11, 0.0018, 3, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates slowly varying x-axis coordinate distortion.
    _warp_z_noise = _create_noise(23, 0.0018, 3, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates independently varying z-axis coordinate distortion.
    _continent_noise = _create_noise(37, 0.00042, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates landforms spanning several kilometres.
    _rolling_hill_noise = _create_noise(41, 0.00135, 5, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates long slopes and rolling highlands.
    _hill_detail_noise = _create_noise(53, 0.0042, 4, 0.48, 2.1, FastNoiseLite.FRACTAL_FBM) # Creates smaller folds without overwhelming broad hills.
    _mountain_region_noise = _create_noise(67, 0.0007, 3, 0.54, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates large coherent mountain provinces.
    _mountain_ridge_noise = _create_noise(71, 0.00155, 5, 0.5, 2.05, FastNoiseLite.FRACTAL_RIDGED) # Creates high primary mountain ridges.
    _mountain_detail_noise = _create_noise(83, 0.0055, 4, 0.5, 2.2, FastNoiseLite.FRACTAL_RIDGED) # Creates sharper secondary mountain structures.
    _terrace_noise = _create_noise(97, 0.0026, 3, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Varies mountain tier spacing and blend strength.
    _valley_noise = _create_noise(101, 0.00105, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates broad meandering valley paths.
    _crevasse_region_noise = _create_noise(113, 0.0019, 3, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates patches where narrow fissures can appear.
    _crevasse_noise = _create_noise(127, 0.0068, 3, 0.52, 2.15, FastNoiseLite.FRACTAL_FBM) # Creates narrow winding crevasse lines.
    _surface_detail_noise = _create_noise(139, 0.014, 3, 0.45, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates small-scale ground variation visible near the player.

func sample_height(world_x: float, world_z: float) -> float: # Returns the deterministic terrain height at one world-space horizontal position.
    var warp_x: float = _warp_x_noise.get_noise_2d(world_x, world_z) * WARP_DISTANCE # Calculates horizontal distortion from the first warp field.
    var warp_z: float = _warp_z_noise.get_noise_2d(world_x, world_z) * WARP_DISTANCE # Calculates horizontal distortion from the second warp field.
    var sample_x: float = world_x + warp_x # Applies the x-axis distortion before sampling landforms.
    var sample_z: float = world_z + warp_z # Applies the z-axis distortion before sampling landforms.
    var continental_height: float = _continent_noise.get_noise_2d(sample_x, sample_z) * 52.0 # Establishes broad regional elevation changes.
    var rolling_height: float = _rolling_hill_noise.get_noise_2d(sample_x, sample_z) * 31.0 # Adds long rolling hills to the regional elevation.
    var hill_detail: float = _hill_detail_noise.get_noise_2d(sample_x, sample_z) * 12.0 # Adds secondary folds to rolling terrain.
    var mountain_region_value: float = (_mountain_region_noise.get_noise_2d(sample_x, sample_z) + 1.0) * 0.5 # Converts the mountain-region field into a normalized mask input.
    var mountain_mask: float = smoothstep(0.48, 0.79, mountain_region_value) # Restricts mountains to broad coherent regions with soft boundaries.
    var primary_ridge: float = clampf((_mountain_ridge_noise.get_noise_2d(sample_x, sample_z) + 1.0) * 0.5, 0.0, 1.0) # Normalizes the primary ridged field.
    var secondary_ridge: float = clampf((_mountain_detail_noise.get_noise_2d(sample_x, sample_z) + 1.0) * 0.5, 0.0, 1.0) # Normalizes the secondary ridged field.
    var mountain_height: float = mountain_mask * (pow(primary_ridge, 1.55) * MOUNTAIN_HEIGHT + pow(secondary_ridge, 2.1) * MOUNTAIN_DETAIL_HEIGHT) # Builds tall layered mountain masses.
    var terrace_value: float = (_terrace_noise.get_noise_2d(sample_x, sample_z) + 1.0) * 0.5 # Produces a normalized local terrace-control value.
    var terrace_step: float = TERRACE_MINIMUM_STEP + terrace_value * TERRACE_STEP_RANGE # Varies vertical tier spacing across each mountain system.
    var terraced_height: float = snappedf(mountain_height, terrace_step) # Produces discrete mountain shelves before blending.
    var terrace_strength: float = mountain_mask * lerpf(0.12, 0.34, terrace_value) # Keeps tiers visible while preserving continuous climbable slopes.
    mountain_height = lerpf(mountain_height, terraced_height, terrace_strength) # Blends terraces into the mountain rather than creating full vertical steps.
    var valley_line: float = 1.0 - clampf(absf(_valley_noise.get_noise_2d(sample_x, sample_z)) * 2.9, 0.0, 1.0) # Finds areas close to broad valley centre lines.
    var valley_cut: float = pow(valley_line, 3.2) * VALLEY_DEPTH * lerpf(0.72, 1.0, mountain_mask) # Carves deep valleys that continue through mountain regions.
    var crevasse_region_value: float = (_crevasse_region_noise.get_noise_2d(sample_x, sample_z) + 1.0) * 0.5 # Converts the fissure-region field into a normalized mask input.
    var crevasse_region_mask: float = smoothstep(0.57, 0.76, crevasse_region_value) # Limits fissures to selected areas instead of covering every biome.
    var crevasse_line: float = 1.0 - clampf(absf(_crevasse_noise.get_noise_2d(sample_x, sample_z)) * 8.5, 0.0, 1.0) # Finds narrow positions close to crevasse centre lines.
    var crevasse_cut: float = pow(crevasse_line, 5.0) * CREVASSE_DEPTH * crevasse_region_mask # Carves steep narrow channels into the height field.
    var surface_detail: float = _surface_detail_noise.get_noise_2d(sample_x, sample_z) * 4.5 # Adds restrained close-range variation to the final surface.
    var full_height: float = continental_height + rolling_height + hill_detail + mountain_height - valley_cut - crevasse_cut + surface_detail # Combines every major and minor landform into one continuous height.
    var spawn_distance: float = Vector2(world_x, world_z).length() # Measures distance from the initial player start.
    var spawn_blend: float = smoothstep(SPAWN_INNER_RADIUS, SPAWN_OUTER_RADIUS, spawn_distance) # Gradually introduces extreme landforms outside the starting area.
    var spawn_height: float = continental_height * 0.28 + rolling_height * 0.58 + hill_detail * 0.35 + surface_detail * 0.25 # Creates a gently varied but non-flat starting landscape.
    return lerpf(spawn_height, full_height, spawn_blend) # Returns a safe start that transitions continuously into the full terrain system.

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
