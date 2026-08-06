extends RefCounted # Selects deterministic local water elevations that follow the world's broad geological provinces.
class_name TerrainWaterLevelSampler # Makes terrain-compatible water levels available to mesh generation and gameplay systems.

var _warp_x_noise: FastNoiseLite # Reproduces the terrain generator's continental x-axis distortion.
var _warp_z_noise: FastNoiseLite # Reproduces the terrain generator's independent z-axis distortion.
var _continent_noise: FastNoiseLite # Reproduces the broad continental elevation tendency.
var _tier_noise: FastNoiseLite # Reproduces secondary regional elevation variation.
var _tier_breakup_noise: FastNoiseLite # Reproduces broad province-contour breakup.
var _plateau_noise: FastNoiseLite # Reproduces rolling plain and upland relief for water-band selection.
var _basin_noise: FastNoiseLite # Reproduces broad sedimentary basin placement.

func _init() -> void: # Builds the low-frequency deterministic fields shared with the geological terrain hierarchy.
    _warp_x_noise = _create_noise(11, 0.000075, 3, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Matches terrain x-axis continental distortion.
    _warp_z_noise = _create_noise(23, 0.000075, 3, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Matches terrain z-axis continental distortion.
    _continent_noise = _create_noise(37, 0.000020, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Matches extremely broad continental rises and depressions.
    _tier_noise = _create_noise(41, 0.000038, 4, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Matches long regional elevation provinces.
    _tier_breakup_noise = _create_noise(53, 0.000085, 3, 0.48, 2.0, FastNoiseLite.FRACTAL_FBM) # Matches broad province-contour breakup.
    _plateau_noise = _create_noise(59, 0.00022, 4, 0.48, 2.0, FastNoiseLite.FRACTAL_FBM) # Matches rolling plains, plateaus, and uplands.
    _basin_noise = _create_noise(61, 0.000075, 3, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Matches broad sedimentary basin regions.

func sample_water_level(world_x: float, world_z: float) -> float: # Returns one flat local water band appropriate to the surrounding geological province.
    var warp_x: float = _warp_x_noise.get_noise_2d(world_x, world_z) * TerrainHeightSampler.WORLD_WARP_DISTANCE # Calculates terrain-matching x-axis distortion.
    var warp_z: float = _warp_z_noise.get_noise_2d(world_x, world_z) * TerrainHeightSampler.WORLD_WARP_DISTANCE # Calculates terrain-matching z-axis distortion.
    var sample_x: float = world_x + warp_x # Applies shared distortion before selecting water height.
    var sample_z: float = world_z + warp_z # Applies independent shared z distortion.
    var continent_value: float = _sample_normalized(_continent_noise, sample_x, sample_z) # Reads the continental elevation tendency.
    var tier_value: float = _sample_normalized(_tier_noise, sample_x, sample_z) # Reads secondary regional variation.
    var tier_breakup_value: float = _sample_normalized(_tier_breakup_noise, sample_x, sample_z) # Reads broad province-contour breakup.
    var macro_elevation: float = clampf(continent_value * 0.60 + tier_value * 0.30 + tier_breakup_value * 0.10, 0.0, 1.0) # Matches terrain's continental and regional weighting.
    macro_elevation = lerpf(0.08, 0.92, smoothstep(0.05, 0.95, macro_elevation)) # Matches terrain's retained high and low regional range.
    var tier_height: float = _get_tier_height(macro_elevation) # Reconstructs continuous regional elevation.
    var plateau_relief: float = _plateau_noise.get_noise_2d(sample_x, sample_z) * TerrainHeightSampler.PLATEAU_UNDULATION_HEIGHT # Reads rolling local relief.
    var basin_value: float = _sample_normalized(_basin_noise, sample_x, sample_z) # Reads sedimentary basin placement.
    var basin_mask: float = smoothstep(0.62, 0.90, 1.0 - basin_value) # Matches terrain's coherent lowland regions.
    var basin_cut: float = basin_mask * TerrainHeightSampler.BASIN_DEPTH # Reconstructs broad elevation reduction.
    var regional_height: float = tier_height + plateau_relief * TerrainConfiguration.WATER_REGIONAL_PLATEAU_INFLUENCE - basin_cut * TerrainConfiguration.WATER_REGIONAL_BASIN_INFLUENCE # Estimates surrounding land without following mountains or individual valleys.
    var water_coordinate: float = (regional_height - TerrainConfiguration.WATER_LEVEL_CLEARANCE - TerrainConfiguration.WATER_LEVEL_OFFSET) / TerrainHeightSampler.TIER_HEIGHT # Finds the highest water band safely below the region.
    var water_tier_index: int = clampi(floori(water_coordinate), 0, TerrainHeightSampler.TIER_LEVEL_COUNT - 1) # Restricts water to established geological elevation provinces.
    return float(water_tier_index) * TerrainHeightSampler.TIER_HEIGHT + TerrainConfiguration.WATER_LEVEL_OFFSET # Returns the shared deterministic water elevation.

func _get_tier_height(macro_elevation: float) -> float: # Reconstructs the terrain's continuous regional elevation provinces.
    var highest_tier_index: float = float(TerrainHeightSampler.TIER_LEVEL_COUNT - 1) # Converts province count into the highest valid index.
    var tier_coordinate: float = clampf(macro_elevation, 0.0, 1.0) * highest_tier_index # Maps the macro coordinate across every province.
    var lower_tier_index: float = floor(tier_coordinate) # Selects the province beneath the current coordinate.
    var tier_fraction: float = tier_coordinate - lower_tier_index # Measures progress toward the next province.
    var tier_transition: float = smoothstep(TerrainHeightSampler.TIER_TRANSITION_START, 1.0, tier_fraction) # Matches the long ascent used by terrain generation.
    return (lower_tier_index + tier_transition) * TerrainHeightSampler.TIER_HEIGHT # Returns the reconstructed regional height.

func _sample_normalized(noise: FastNoiseLite, sample_x: float, sample_z: float) -> float: # Converts one signed noise sample into a defensive zero-to-one range.
    return clampf((noise.get_noise_2d(sample_x, sample_z) + 1.0) * 0.5, 0.0, 1.0) # Normalizes and clamps the field output.

func _create_noise(seed_offset: int, frequency: float, octaves: int, gain: float, lacunarity: float, fractal_type: int) -> FastNoiseLite: # Creates one terrain-compatible deterministic noise resource.
    var noise: FastNoiseLite = FastNoiseLite.new() # Allocates an independent noise generator for one water-level role.
    noise.seed = TerrainHeightSampler.WORLD_SEED + seed_offset # Uses the same world seed and role offset as terrain.
    noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH # Matches terrain's coherent smooth simplex fields.
    noise.frequency = frequency # Sets the physical scale represented by the field.
    noise.fractal_type = fractal_type # Selects the same fractal accumulation mode as terrain.
    noise.fractal_octaves = octaves # Sets the number of accumulated detail layers.
    noise.fractal_gain = gain # Controls the strength of each finer octave.
    noise.fractal_lacunarity = lacunarity # Controls the frequency increase between octaves.
    return noise # Returns the configured deterministic field.
