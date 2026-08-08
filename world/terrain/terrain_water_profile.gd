extends RefCounted # Defines the shared continuous water-height profile used by terrain shaping, rendering, and gameplay queries.
class_name TerrainWaterProfile # Exposes one deterministic conversion from regional terrain elevation to seamless water elevation.

static func get_continuous_level(regional_height: float) -> float: # Converts broad regional elevation into a continuous tier-compatible water surface without vertical jumps.
    var highest_tier_index: float = float(TerrainHeightSampler.TIER_LEVEL_COUNT - 1) # Converts the geological water-band count into the highest valid zero-based coordinate.
    var raw_water_coordinate: float = (regional_height - TerrainConfiguration.WATER_LEVEL_CLEARANCE - TerrainConfiguration.WATER_LEVEL_OFFSET) / TerrainHeightSampler.TIER_HEIGHT # Maps regional elevation into the same water-band coordinate used by the previous tiered implementation.
    var water_coordinate: float = clampf(raw_water_coordinate, 0.0, highest_tier_index) # Keeps water within the established geological elevation range at extreme world heights.
    var lower_tier_index: float = floor(water_coordinate) # Finds the lower geological water band surrounding the current continuous coordinate.
    var tier_fraction: float = water_coordinate - lower_tier_index # Measures progress from the lower band toward the next shared band elevation.
    var transition_weight: float = smoothstep(TerrainHeightSampler.TIER_TRANSITION_START, 1.0, tier_fraction) # Spreads each elevation change across the broad geological transition and reaches the next band with zero edge discontinuity.
    return (lower_tier_index + transition_weight) * TerrainHeightSampler.TIER_HEIGHT + TerrainConfiguration.WATER_LEVEL_OFFSET # Returns the continuous world-space water elevation while retaining the established tier range and offset.
