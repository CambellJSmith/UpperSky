extends TerrainWaterLevelSampler # Reuses the established deterministic regional noise fields while replacing hard water-band jumps with continuous elevation transitions.
class_name SeamlessTerrainWaterLevelSampler # Supplies the exact seamless world-space water-height function consumed by rendering and gameplay queries.

func sample_water_level(world_x: float, world_z: float) -> float: # Returns one continuous terrain-compatible water elevation at an absolute horizontal world coordinate.
    var warp_x: float = _warp_x_noise.get_noise_2d(world_x, world_z) * TerrainHeightSampler.WORLD_WARP_DISTANCE # Reproduces the terrain generator's broad x-axis continental distortion.
    var warp_z: float = _warp_z_noise.get_noise_2d(world_x, world_z) * TerrainHeightSampler.WORLD_WARP_DISTANCE # Reproduces the terrain generator's independent z-axis continental distortion.
    var sample_x: float = world_x + warp_x # Applies the shared x distortion before regional elevation sampling.
    var sample_z: float = world_z + warp_z # Applies the shared z distortion before regional elevation sampling.
    var continent_value: float = _sample_normalized(_continent_noise, sample_x, sample_z) # Reads the same broad continental elevation tendency as terrain generation.
    var tier_value: float = _sample_normalized(_tier_noise, sample_x, sample_z) # Reads the same secondary regional elevation field as terrain generation.
    var tier_breakup_value: float = _sample_normalized(_tier_breakup_noise, sample_x, sample_z) # Reads the same broad contour-breakup field as terrain generation.
    var macro_elevation: float = clampf(continent_value * TerrainHeightSampler.MACRO_CONTINENT_WEIGHT + tier_value * TerrainHeightSampler.MACRO_TIER_WEIGHT + tier_breakup_value * TerrainHeightSampler.MACRO_BREAKUP_WEIGHT, 0.0, 1.0) # Reconstructs the exact terrain generator weighting from shared constants.
    macro_elevation = lerpf(TerrainHeightSampler.MACRO_ELEVATION_MINIMUM, TerrainHeightSampler.MACRO_ELEVATION_MAXIMUM, smoothstep(TerrainHeightSampler.MACRO_SMOOTH_START, TerrainHeightSampler.MACRO_SMOOTH_END, macro_elevation)) # Reconstructs the exact terrain generator high-low regional remapping.
    var tier_height: float = _get_tier_height(macro_elevation) # Reconstructs the continuous broad geological province elevation.
    var plateau_relief: float = _plateau_noise.get_noise_2d(sample_x, sample_z) * TerrainHeightSampler.PLATEAU_UNDULATION_HEIGHT # Reads the same rolling local relief used by regional water selection.
    var basin_value: float = _sample_normalized(_basin_noise, sample_x, sample_z) # Reads the same broad sedimentary basin placement field.
    var basin_mask: float = smoothstep(0.62, 0.90, 1.0 - basin_value) # Reconstructs the terrain generator's coherent lowland mask.
    var basin_cut: float = basin_mask * TerrainHeightSampler.BASIN_DEPTH # Reconstructs the broad regional basin elevation reduction.
    var regional_height: float = tier_height + plateau_relief * TerrainConfiguration.WATER_REGIONAL_PLATEAU_INFLUENCE - basin_cut * TerrainConfiguration.WATER_REGIONAL_BASIN_INFLUENCE # Reconstructs the broad terrain elevation used to position water independently from mountains and individual valley cuts.
    return TerrainWaterProfile.get_continuous_level(regional_height) # Converts the regional height into the shared seamless water surface with no tier-boundary jump.