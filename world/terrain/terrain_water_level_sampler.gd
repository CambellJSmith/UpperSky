extends RefCounted # Selects deterministic local water elevations that follow the world's major terrain tiers.
class_name TerrainWaterLevelSampler # Makes tier-aware water levels available to mesh generation and future gameplay systems.

const WATER_LEVEL_OFFSET: float = -120.0 # Places each water surface below its surrounding regional shelf so only valleys and basins flood.
const WATER_LEVEL_CLEARANCE: float = 96.0 # Requires the general regional surface to sit safely above the next higher water band before switching levels.
const REGIONAL_PLATEAU_INFLUENCE: float = 0.24 # Lets broad local uplands influence water-band selection without making individual lakes slope.
const REGIONAL_BASIN_INFLUENCE: float = 0.22 # Lets enormous basins select an appropriate lower water band without following every terrain depression.

var _warp_x_noise: FastNoiseLite # Reproduces the terrain generator's continental x-axis distortion.
var _warp_z_noise: FastNoiseLite # Reproduces the terrain generator's independent continental z-axis distortion.
var _continent_noise: FastNoiseLite # Reproduces the broad continental elevation tendency.
var _tier_noise: FastNoiseLite # Reproduces the dominant macro elevation shelf selector.
var _tier_breakup_noise: FastNoiseLite # Reproduces the smaller-scale shelf-boundary breakup field.
var _plateau_noise: FastNoiseLite # Reproduces broad plateau relief for local water-band selection.
var _basin_noise: FastNoiseLite # Reproduces enormous basin placement for local water-band selection.

func _init() -> void: # Builds the low-frequency deterministic fields shared conceptually with the terrain hierarchy.
    _warp_x_noise = _create_noise(11, 0.00013, 3, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Matches the terrain's slow x-axis coordinate distortion.
    _warp_z_noise = _create_noise(23, 0.00013, 3, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Matches the terrain's slow z-axis coordinate distortion.
    _continent_noise = _create_noise(37, 0.000035, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Matches continental rises spanning many kilometres.
    _tier_noise = _create_noise(41, 0.000075, 4, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Matches the huge regional elevation shelves.
    _tier_breakup_noise = _create_noise(53, 0.00018, 3, 0.48, 2.0, FastNoiseLite.FRACTAL_FBM) # Matches complex shelf-boundary shapes.
    _plateau_noise = _create_noise(59, 0.00045, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Matches broad rolling relief within each shelf.
    _basin_noise = _create_noise(61, 0.00016, 3, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Matches kilometre-scale depressed regions between highlands.

func sample_water_level(world_x: float, world_z: float) -> float: # Returns one flat local water band appropriate to the surrounding macro terrain height.
    var warp_x: float = _warp_x_noise.get_noise_2d(world_x, world_z) * TerrainHeightSampler.WORLD_WARP_DISTANCE # Calculates the terrain-matching x-axis distortion.
    var warp_z: float = _warp_z_noise.get_noise_2d(world_x, world_z) * TerrainHeightSampler.WORLD_WARP_DISTANCE # Calculates the terrain-matching z-axis distortion.
    var sample_x: float = world_x + warp_x # Applies the shared macro distortion before selecting the water level.
    var sample_z: float = world_z + warp_z # Applies the shared macro distortion independently along z.
    var continent_value: float = _sample_normalized(_continent_noise, sample_x, sample_z) # Reads the continental elevation tendency.
    var tier_value: float = _sample_normalized(_tier_noise, sample_x, sample_z) # Reads the primary shelf selector.
    var tier_breakup_value: float = _sample_normalized(_tier_breakup_noise, sample_x, sample_z) # Reads the shelf-boundary breakup field.
    var macro_elevation: float = clampf(continent_value * 0.52 + tier_value * 0.36 + tier_breakup_value * 0.12, 0.0, 1.0) # Reconstructs the terrain's stable regional elevation coordinate.
    macro_elevation = smoothstep(0.08, 0.92, macro_elevation) # Matches the terrain's broad lowland and highland expansion.
    var tier_height: float = _get_tier_height(macro_elevation) # Reconstructs the continuous regional shelf elevation.
    var plateau_relief: float = _plateau_noise.get_noise_2d(sample_x, sample_z) * TerrainHeightSampler.PLATEAU_UNDULATION_HEIGHT # Reads broad local shelf relief.
    var basin_value: float = _sample_normalized(_basin_noise, sample_x, sample_z) # Reads the regional basin field.
    var basin_mask: float = smoothstep(0.62, 0.88, 1.0 - basin_value) # Selects the deepest broad basin regions.
    var basin_cut: float = basin_mask * TerrainHeightSampler.BASIN_DEPTH # Reconstructs the basin's broad elevation reduction.
    var regional_height: float = tier_height + plateau_relief * REGIONAL_PLATEAU_INFLUENCE - basin_cut * REGIONAL_BASIN_INFLUENCE # Estimates the general local land height without following mountains or individual valleys.
    var water_coordinate: float = (regional_height - WATER_LEVEL_CLEARANCE - WATER_LEVEL_OFFSET) / TerrainHeightSampler.TIER_HEIGHT # Finds the highest water band that remains safely beneath the surrounding region.
    var water_tier_index: int = clampi(floori(water_coordinate), 0, TerrainHeightSampler.TIER_LEVEL_COUNT - 1) # Restricts water to the six established world elevation tiers.
    return float(water_tier_index) * TerrainHeightSampler.TIER_HEIGHT + WATER_LEVEL_OFFSET # Returns one of six flat deterministic water elevations.

func _get_tier_height(macro_elevation: float) -> float: # Reconstructs the terrain's continuous broad elevation shelves.
    var highest_tier_index: float = float(TerrainHeightSampler.TIER_LEVEL_COUNT - 1) # Converts the available shelf count into the highest valid index.
    var tier_coordinate: float = clampf(macro_elevation, 0.0, 1.0) * highest_tier_index # Maps the macro coordinate across every shelf.
    var lower_tier_index: float = floor(tier_coordinate) # Selects the shelf beneath the current regional coordinate.
    var tier_fraction: float = tier_coordinate - lower_tier_index # Measures progress toward the next shelf.
    var tier_transition: float = smoothstep(TerrainHeightSampler.TIER_TRANSITION_START, 1.0, tier_fraction) # Matches the terrain's broad continuous climb between shelves.
    return (lower_tier_index + tier_transition) * TerrainHeightSampler.TIER_HEIGHT # Returns the reconstructed regional shelf height.

func _sample_normalized(noise: FastNoiseLite, sample_x: float, sample_z: float) -> float: # Converts one signed noise sample into a defensive zero-to-one range.
    return clampf((noise.get_noise_2d(sample_x, sample_z) + 1.0) * 0.5, 0.0, 1.0) # Normalizes and clamps the field output.

func _create_noise(seed_offset: int, frequency: float, octaves: int, gain: float, lacunarity: float, fractal_type: int) -> FastNoiseLite: # Creates one terrain-compatible deterministic noise resource.
    var noise: FastNoiseLite = FastNoiseLite.new() # Allocates an independent noise generator for one water-level role.
    noise.seed = TerrainHeightSampler.WORLD_SEED + seed_offset # Uses the same world seed and role offset as the terrain generator.
    noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH # Matches the terrain's coherent smooth simplex fields.
    noise.frequency = frequency # Sets the physical scale represented by the field.
    noise.fractal_type = fractal_type # Selects the same fractal accumulation mode used by the matching terrain field.
    noise.fractal_octaves = octaves # Sets the number of accumulated detail layers.
    noise.fractal_gain = gain # Controls the strength of each finer octave.
    noise.fractal_lacunarity = lacunarity # Controls the frequency increase between octaves.
    return noise # Returns the configured deterministic field.
