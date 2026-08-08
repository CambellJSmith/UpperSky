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
    var macro_elevation: float = clampf(continent_value * 0.60 + tier_value * 0.30 + tier_breakup_value * 0.10, 0.0, 1.0) # Reconstructs the terrain generator's weighted regional elevation coordinate.
    macro_elevation = lerpf(0.08, 0.92, smoothstep(0.05, 0.95, macro_elevation)) # Retains the same compressed geological high and low range as the terrain generator.
    var tier_height: float = _get_tier_height(macro_elevation) # Reconstructs the continuous broad geological province elevation.
    var plateau_relief: float = _plateau_noise.get_noise_2d(sample_x, sample_z) * TerrainHeightSampler.PLATEAU_UNDULATION_HEIGHT # Reads the same rolling local relief used by regional water selection.
    var basin_value: float = _sample_normalized(_basin_noise, sample_x, sample_z) # Reads the same broad sedimentary basin placement field.
    var basin_mask: float = smoothstep(0.62, 0.90, 1.0 - basin_value) # Reconstructs the terrain generator's coherent lowland mask.
    var basin_cut: float = basin_mask * TerrainHeightSampler.BASIN_DEPTH # Reconstructs the broad regional basin elevation reduction.
    var regional_height: float = tier_height + plateau_relief * TerrainConfiguration.WATER_REGIONAL_PLATEAU_INFLUENCE - basin_cut * TerrainConfiguration.WATER_REGIONAL_BASIN_INFLUENCE # Reconstructs the broad terrain elevation used to position water independently from mountains and individual valley cuts.
    return TerrainWaterProfile.get_continuous_level(regional_height) # Converts the regional height into the shared seamless water surface with no tier-boundary jump.
