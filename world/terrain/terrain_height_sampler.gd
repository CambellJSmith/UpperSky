extends RefCounted # Provides a lightweight deterministic terrain-height service without scene-tree ownership.
class_name TerrainHeightSampler # Makes the sampler available to terrain generation and future world tools.

const WORLD_SEED: int = 742_913 # Keeps the generated landscape stable between playthroughs and builds.
const SPAWN_FLAT_HEIGHT: float = 0.0 # Defines the exact world elevation of the circular initial spawn platform.
const SPAWN_FLAT_RADIUS: float = 8.0 # Keeps several metres around world origin completely level for safe spawning.
const SPAWN_FLAT_BLEND_RADIUS: float = 32.0 # Blends the flat platform smoothly into nearby procedural terrain.
const SPAWN_INNER_RADIUS: float = 320.0 # Keeps the immediate starting region especially gentle before full world variation appears.
const SPAWN_OUTER_RADIUS: float = 1200.0 # Introduces the complete world over a long low-gradient transition.
const WORLD_WARP_DISTANCE: float = 700.0 # Bends broad landforms and access corridors without creating abrupt local distortion.
const TIER_LEVEL_COUNT: int = 6 # Retains six broad water-compatible elevation bands across the world.
const TIER_HEIGHT: float = 110.0 # Keeps neighbouring regional elevation bands close enough for long walkable transitions.
const TIER_TRANSITION_START: float = 0.0 # Uses the complete macro interval for each smooth ascent instead of long shelves ending in steep climbs.
const PLATEAU_UNDULATION_HEIGHT: float = 24.0 # Adds restrained rolling relief across predominantly flat land.
const BASIN_DEPTH: float = 48.0 # Creates shallow broad lowlands without enclosing the player behind severe walls.
const MOUNTAIN_PROVINCE_START: float = 0.66 # Allows mountains only in the upper tail of the province field.
const MOUNTAIN_PROVINCE_FULL: float = 0.84 # Reaches full mountain weighting only in rare regional cores.
const MOUNTAIN_MASS_START: float = 0.56 # Requires an additional broad mass field before mountain relief can appear.
const MOUNTAIN_MASS_FULL: float = 0.80 # Gives full relief only to the strongest overlap of both rare mountain fields.
const MOUNTAIN_BASE_HEIGHT: float = 220.0 # Raises rare mountain provinces above the surrounding plains.
const MOUNTAIN_RIDGE_HEIGHT: float = 1050.0 # Preserves exceptional high ranges while keeping their footprint broad.
const MOUNTAIN_SHOULDER_HEIGHT: float = 260.0 # Adds readable mountain structure without roughening ordinary terrain.
const MOUNTAIN_TERRACE_MINIMUM_STEP: float = 70.0 # Defines broad alpine shelf spacing inside rare mountain regions.
const MOUNTAIN_TERRACE_STEP_RANGE: float = 50.0 # Varies mountain shelf spacing without creating repetitive bands.
const MOUNTAIN_WIDTH_SAMPLE_DISTANCE: float = 1050.0 # Requires ridge support across more than two kilometres before granting major relief.
const MOUNTAIN_WIDTH_EXCESS_START: float = 0.04 # Begins suppressing narrow ridge protrusions early.
const MOUNTAIN_WIDTH_EXCESS_END: float = 0.16 # Fully replaces unsupported narrow maxima with the broad surrounding ridge level.
const MOUNTAIN_WIDTH_SUPPORT_START: float = 0.46 # Prevents weak ridge fields from creating steep isolated hills.
const MOUNTAIN_WIDTH_SUPPORT_END: float = 0.68 # Grants full ridge height only where a very broad mountain body exists.
const ACCESS_CORRIDOR_SPACING: float = 4096.0 # Places a connected world-spanning pass network through every large region.
const ACCESS_CORRIDOR_CORE_RADIUS: float = 240.0 # Keeps the central route of each warped pass broad and nearly level.
const ACCESS_CORRIDOR_BLEND_RADIUS: float = 760.0 # Blends mountain relief back in over a long traversable foothill ramp.
const ACCESS_CORRIDOR_MOUNTAIN_REDUCTION: float = 0.96 # Removes almost all mountain relief from the centre of guaranteed pass routes.
const PRIMARY_VALLEY_BASE_DEPTH: float = 80.0 # Gives broad drainage corridors visible but easily traversable relief.
const PRIMARY_VALLEY_TIER_DEPTH: float = 120.0 # Adds only restrained extra depth on upper regional bands.
const PRIMARY_VALLEY_MOUNTAIN_DEPTH: float = 180.0 # Lets major valleys form organic passes through rare ranges.
const SECONDARY_VALLEY_BASE_DEPTH: float = 38.0 # Keeps tributaries shallow across ordinary land.
const SECONDARY_VALLEY_TIER_DEPTH: float = 58.0 # Slightly deepens tributaries on higher terrain without forming ravines.
const SECONDARY_VALLEY_MOUNTAIN_DEPTH: float = 90.0 # Lets tributaries enter mountain foothills without cutting impassable walls.
const LOWEST_VALLEY_FLOOR: float = -180.0 # Prevents combined lowlands from descending into extreme pits.
const SURFACE_DETAIL_HEIGHT: float = 5.0 # Adds subtle ground variation while keeping the eight-metre mesh broadly walkable.
const SUMMIT_DETAIL_FADE_START: float = 0.68 # Begins suppressing secondary detail before the primary crest.
const SUMMIT_DETAIL_FADE_END: float = 0.92 # Removes small-scale detail around rounded summits.
const UNDERWATER_DETAIL_FADE_START_DEPTH: float = 6.0 # Preserves shoreline texture before seabed smoothing begins.
const UNDERWATER_DETAIL_FADE_END_DEPTH: float = 96.0 # Reaches full local-detail reduction only in clearly submerged terrain.
const UNDERWATER_DETAIL_MINIMUM_WEIGHT: float = 0.42 # Retains some seabed texture instead of making underwater terrain featureless.
const UNDERWATER_FLATTEN_START_DEPTH: float = 12.0 # Avoids changing the immediate shoreline while beginning mild depth compression offshore.
const UNDERWATER_FLATTEN_FULL_DEPTH: float = 180.0 # Reaches maximum seabed flattening only in deep water.
const UNDERWATER_MAXIMUM_DEPTH_COMPRESSION: float = 0.14 # Limits underwater relief reduction to a restrained fourteen percent.

var _warp_x_noise: FastNoiseLite # Distorts world sampling along the x axis at continental scale.
var _warp_z_noise: FastNoiseLite # Distorts world sampling along the z axis independently.
var _continent_noise: FastNoiseLite # Establishes the broadest continental elevation tendency.
var _tier_noise: FastNoiseLite # Adds secondary broad regional elevation variation.
var _tier_breakup_noise: FastNoiseLite # Prevents regional elevation contours from following one simple field.
var _plateau_noise: FastNoiseLite # Adds restrained rolling relief across broad plains.
var _basin_noise: FastNoiseLite # Creates shallow kilometre-scale lowlands.
var _mountain_province_noise: FastNoiseLite # Determines where rare mountain systems may exist.
var _mountain_mass_noise: FastNoiseLite # Controls the broad footprint inside each rare mountain province.
var _mountain_ridge_noise: FastNoiseLite # Produces the primary broad mountain chain structure.
var _mountain_detail_noise: FastNoiseLite # Produces restrained secondary mountain shoulders.
var _mountain_terrace_noise: FastNoiseLite # Varies broad alpine shelf spacing and strength.
var _primary_valley_noise: FastNoiseLite # Produces the longest broad drainage and mountain-pass network.
var _secondary_valley_noise: FastNoiseLite # Produces branching shallow tributary valleys.
var _valley_width_noise: FastNoiseLite # Varies valley widths over long distances.
var _surface_detail_noise: FastNoiseLite # Adds restrained local ground variation.

func _init() -> void: # Builds every deterministic noise source used by the flatter terrain hierarchy.
    _warp_x_noise = _create_noise(11, 0.00009, 3, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates slow x-axis distortion for broad landforms and access corridors.
    _warp_z_noise = _create_noise(23, 0.00009, 3, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates independent slow z-axis distortion.
    _continent_noise = _create_noise(37, 0.000025, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates extremely broad continental rises.
    _tier_noise = _create_noise(41, 0.000045, 4, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Adds long regional elevation variation.
    _tier_breakup_noise = _create_noise(53, 0.00010, 3, 0.48, 2.0, FastNoiseLite.FRACTAL_FBM) # Breaks broad contours without introducing local cliffs.
    _plateau_noise = _create_noise(59, 0.00028, 3, 0.48, 2.0, FastNoiseLite.FRACTAL_FBM) # Adds gentle rolling relief across plains.
    _basin_noise = _create_noise(61, 0.00010, 3, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates shallow broad lowland regions.
    _mountain_province_noise = _create_noise(67, 0.000025, 3, 0.54, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates rare mountain provinces many kilometres across.
    _mountain_mass_noise = _create_noise(71, 0.000055, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Shapes broad mountain mass inside each province.
    _mountain_ridge_noise = _create_noise(83, 0.00011, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_RIDGED) # Creates wide rounded primary ridges.
    _mountain_detail_noise = _create_noise(97, 0.00024, 3, 0.46, 2.0, FastNoiseLite.FRACTAL_RIDGED) # Creates large secondary shoulders only inside mountains.
    _mountain_terrace_noise = _create_noise(101, 0.00010, 3, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Varies broad mountain shelves.
    _primary_valley_noise = _create_noise(113, 0.00007, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates very broad winding lowland and pass corridors.
    _secondary_valley_noise = _create_noise(127, 0.00016, 3, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates shallow branching tributaries.
    _valley_width_noise = _create_noise(139, 0.000055, 3, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Changes corridor width gradually over kilometres.
    _surface_detail_noise = _create_noise(149, 0.0012, 2, 0.38, 2.0, FastNoiseLite.FRACTAL_FBM) # Adds inexpensive subtle local ground variation.

func sample_height(world_x: float, world_z: float) -> float: # Returns the deterministic terrain height at one world-space horizontal position.
    var warp_x: float = _warp_x_noise.get_noise_2d(world_x, world_z) * WORLD_WARP_DISTANCE # Calculates broad x-axis distortion.
    var warp_z: float = _warp_z_noise.get_noise_2d(world_x, world_z) * WORLD_WARP_DISTANCE # Calculates independent broad z-axis distortion.
    var sample_x: float = world_x + warp_x # Applies coordinate distortion before sampling large terrain systems.
    var sample_z: float = world_z + warp_z # Applies independent z distortion before sampling large terrain systems.
    var continent_value: float = _sample_normalized(_continent_noise, sample_x, sample_z) # Reads the broad continental elevation tendency.
    var tier_value: float = _sample_normalized(_tier_noise, sample_x, sample_z) # Reads secondary regional elevation variation.
    var tier_breakup_value: float = _sample_normalized(_tier_breakup_noise, sample_x, sample_z) # Reads smaller broad-contour breakup.
    var macro_elevation: float = clampf(continent_value * 0.62 + tier_value * 0.28 + tier_breakup_value * 0.10, 0.0, 1.0) # Lets the slowest field dominate regional height.
    macro_elevation = lerpf(0.16, 0.84, smoothstep(0.08, 0.92, macro_elevation)) # Compresses extreme regional elevations into a broadly traversable range.
    var tier_height: float = _get_tier_height(macro_elevation) # Converts the macro coordinate into low, smoothly connected elevation bands.
    var plateau_relief: float = _plateau_noise.get_noise_2d(sample_x, sample_z) * PLATEAU_UNDULATION_HEIGHT # Adds gentle rolling relief across the current region.
    var basin_value: float = _sample_normalized(_basin_noise, sample_x, sample_z) # Reads the broad shallow-basin field.
    var basin_mask: float = smoothstep(0.68, 0.90, 1.0 - basin_value) # Selects only the strongest lowland regions.
    var basin_cut: float = basin_mask * BASIN_DEPTH # Lowers selected regions without forming deep bowls.
    var base_height: float = tier_height + plateau_relief - basin_cut # Resolves the predominantly flat ordinary terrain.
    var regional_water_height: float = tier_height + plateau_relief * TerrainConfiguration.WATER_REGIONAL_PLATEAU_INFLUENCE - basin_cut * TerrainConfiguration.WATER_REGIONAL_BASIN_INFLUENCE # Reconstructs the same broad height used by water-band selection.
    var local_water_level: float = _get_local_water_level(regional_water_height) # Selects the exact flat local water elevation.
    var mountain_province_value: float = _sample_normalized(_mountain_province_noise, sample_x, sample_z) # Reads rare mountain-province placement.
    var mountain_province_mask: float = smoothstep(MOUNTAIN_PROVINCE_START, MOUNTAIN_PROVINCE_FULL, mountain_province_value) # Restricts mountains to exceptional large regions.
    var mountain_mass_value: float = _sample_normalized(_mountain_mass_noise, sample_x, sample_z) # Reads broad internal mountain mass.
    var mountain_mass_mask: float = smoothstep(MOUNTAIN_MASS_START, MOUNTAIN_MASS_FULL, mountain_mass_value) # Requires strong overlapping mountain support.
    var mountain_presence: float = mountain_province_mask * mountain_mass_mask # Combines both rare fields into the complete mountain footprint.
    var mountain_height: float = 0.0 # Keeps ordinary terrain free of all mountain sampling and relief.
    if mountain_presence > 0.001: # Performs expensive ridge work only inside the small fraction of terrain that can contain mountains.
        var primary_ridge_value: float = _sample_normalized(_mountain_ridge_noise, sample_x, sample_z) # Reads the primary ridged mountain field.
        var broad_primary_ridge: float = _sample_broad_ridge_support(sample_x, sample_z, primary_ridge_value) # Measures kilometre-scale support around the ridge.
        var unsupported_ridge_excess: float = maxf(primary_ridge_value - broad_primary_ridge, 0.0) # Detects narrow protrusions above the broad mountain body.
        var ridge_width_weight: float = 1.0 - smoothstep(MOUNTAIN_WIDTH_EXCESS_START, MOUNTAIN_WIDTH_EXCESS_END, unsupported_ridge_excess) # Suppresses relief as a ridge becomes too narrow.
        var supported_primary_ridge: float = lerpf(broad_primary_ridge, primary_ridge_value, ridge_width_weight) # Replaces thin peaks with their surrounding support height.
        var broad_ridge_support: float = smoothstep(MOUNTAIN_WIDTH_SUPPORT_START, MOUNTAIN_WIDTH_SUPPORT_END, broad_primary_ridge) # Requires a substantial surrounding ridge field.
        var secondary_ridge_value: float = _sample_normalized(_mountain_detail_noise, sample_x, sample_z) # Reads secondary mountain shoulders.
        var rounded_primary_ridge: float = sin(supported_primary_ridge * PI * 0.5) # Gives the primary ridge a rounded zero-slope crest.
        var rounded_secondary_ridge: float = sin(secondary_ridge_value * PI * 0.5) # Rounds secondary maxima before adding relief.
        var primary_ridge_shape: float = pow(rounded_primary_ridge, 1.42) * broad_ridge_support # Keeps primary relief broad enough for climbable approaches.
        var secondary_width_support: float = lerpf(0.20, 1.0, broad_ridge_support) * ridge_width_weight # Prevents unsupported side ridges.
        var secondary_ridge_shape: float = pow(rounded_secondary_ridge, 2.2) * secondary_width_support # Restricts sharper detail to supported mountain interiors.
        var summit_detail_weight: float = 1.0 - smoothstep(SUMMIT_DETAIL_FADE_START, SUMMIT_DETAIL_FADE_END, rounded_primary_ridge) # Removes rough secondary detail around summits.
        var mountain_base: float = mountain_presence * MOUNTAIN_BASE_HEIGHT # Raises the complete rare province gradually.
        var mountain_ridge: float = mountain_presence * primary_ridge_shape * MOUNTAIN_RIDGE_HEIGHT # Adds broad primary relief.
        var mountain_shoulders: float = mountain_presence * secondary_ridge_shape * MOUNTAIN_SHOULDER_HEIGHT * summit_detail_weight # Adds restrained side structure.
        mountain_height = mountain_base + mountain_ridge + mountain_shoulders # Resolves the continuous rare mountain profile.
        var mountain_terrace_value: float = _sample_normalized(_mountain_terrace_noise, sample_x, sample_z) # Reads broad shelf-control variation.
        var mountain_terrace_step: float = MOUNTAIN_TERRACE_MINIMUM_STEP + mountain_terrace_value * MOUNTAIN_TERRACE_STEP_RANGE # Varies shelf spacing.
        var terraced_mountain_height: float = snappedf(mountain_height, mountain_terrace_step) # Calculates a broad shelf target.
        var mountain_terrace_strength: float = mountain_presence * lerpf(0.02, 0.06, mountain_terrace_value) # Keeps shelves subtle enough to preserve continuous slopes.
        mountain_height = lerpf(mountain_height, terraced_mountain_height, mountain_terrace_strength) # Blends restrained shelves into the mountain body.
        var access_corridor_mask: float = _get_access_corridor_mask(sample_x, sample_z) # Reads the guaranteed connected pass network crossing every region.
        mountain_height *= 1.0 - access_corridor_mask * ACCESS_CORRIDOR_MOUNTAIN_REDUCTION # Carves broad low-gradient routes completely through mountain systems.
    var uncarved_height: float = base_height + mountain_height # Resolves plains and rare mountains before shallow drainage shaping.
    var valley_width_value: float = _sample_normalized(_valley_width_noise, sample_x, sample_z) # Reads slowly changing valley-width control.
    var primary_valley_width: float = lerpf(0.18, 0.34, valley_width_value) # Makes major valleys broad travel corridors.
    var secondary_valley_width: float = lerpf(0.10, 0.18, 1.0 - valley_width_value) # Keeps tributaries visibly narrower but still gentle.
    var primary_valley_line: float = _get_valley_line(_primary_valley_noise.get_noise_2d(sample_x, sample_z), primary_valley_width) # Finds positions near the major winding corridor network.
    var secondary_valley_line: float = _get_valley_line(_secondary_valley_noise.get_noise_2d(sample_x, sample_z), secondary_valley_width) # Finds positions near shallow tributary corridors.
    var primary_valley_shape: float = pow(primary_valley_line, 1.18) # Keeps major floors and side slopes broad.
    var secondary_valley_shape: float = pow(secondary_valley_line, 1.52) # Keeps tributaries restrained and smooth.
    var primary_valley_depth: float = PRIMARY_VALLEY_BASE_DEPTH + macro_elevation * PRIMARY_VALLEY_TIER_DEPTH + mountain_presence * PRIMARY_VALLEY_MOUNTAIN_DEPTH # Deepens major routes modestly according to surrounding scale.
    var primary_valley_floor: float = maxf(LOWEST_VALLEY_FLOOR, tier_height - 150.0 + plateau_relief * 0.10) # Keeps the floor close enough to its region for walkable approaches.
    var primary_carved_height: float = maxf(primary_valley_floor, uncarved_height - primary_valley_depth) # Calculates the deepest permitted major corridor.
    var height_after_primary_valley: float = lerpf(uncarved_height, primary_carved_height, primary_valley_shape) # Blends gradually into the broad valley floor.
    var secondary_valley_weight: float = secondary_valley_shape * (1.0 - primary_valley_shape * 0.70) # Prevents tributaries from stacking excessive cuts at major centres.
    var secondary_valley_depth: float = SECONDARY_VALLEY_BASE_DEPTH + macro_elevation * SECONDARY_VALLEY_TIER_DEPTH + mountain_presence * SECONDARY_VALLEY_MOUNTAIN_DEPTH # Adds only shallow secondary relief.
    var secondary_valley_floor: float = maxf(LOWEST_VALLEY_FLOOR, tier_height - 105.0 + plateau_relief * 0.08) # Keeps tributary floors near the regional plain height.
    var secondary_carved_height: float = maxf(secondary_valley_floor, height_after_primary_valley - secondary_valley_depth) # Calculates the tributary target surface.
    var valley_height: float = lerpf(height_after_primary_valley, secondary_carved_height, secondary_valley_weight) # Blends shallow tributaries into plains and mountains.
    var valley_suppression: float = clampf(maxf(primary_valley_shape, secondary_valley_shape) * 0.88, 0.0, 1.0) # Suppresses local noise on broad travel corridors.
    var mountain_detail_weight: float = lerpf(1.0, 0.42, mountain_presence) # Removes small roughness from mountain approaches and summits.
    var surface_detail: float = _surface_detail_noise.get_noise_2d(sample_x, sample_z) * SURFACE_DETAIL_HEIGHT * (1.0 - valley_suppression) * mountain_detail_weight # Adds only subtle local variation away from routes.
    var full_height: float = _shape_underwater_height(valley_height, surface_detail, local_water_level) # Smooths and mildly flattens submerged terrain.
    var spawn_distance: float = Vector2(world_x, world_z).length() # Measures distance from the world-origin spawn centre.
    var spawn_blend: float = smoothstep(SPAWN_INNER_RADIUS, SPAWN_OUTER_RADIUS, spawn_distance) # Introduces full world variation gradually outside the start.
    var spawn_height: float = plateau_relief * 0.12 + surface_detail * 0.20 # Keeps the initial region nearly flat and readable.
    var procedural_height: float = lerpf(spawn_height, full_height, spawn_blend) # Blends the safe start into the complete world.
    var flat_blend: float = smoothstep(SPAWN_FLAT_RADIUS, SPAWN_FLAT_BLEND_RADIUS, spawn_distance) # Keeps the innermost spawn circle exactly level.
    return lerpf(SPAWN_FLAT_HEIGHT, procedural_height, flat_blend) # Returns the final deterministic predominantly traversable world height.

func _sample_broad_ridge_support(sample_x: float, sample_z: float, centre_ridge: float) -> float: # Measures broad ridge support so narrow protrusions cannot receive full mountain height.
    var east_ridge: float = _sample_normalized(_mountain_ridge_noise, sample_x + MOUNTAIN_WIDTH_SAMPLE_DISTANCE, sample_z) # Samples ridge support to the east.
    var west_ridge: float = _sample_normalized(_mountain_ridge_noise, sample_x - MOUNTAIN_WIDTH_SAMPLE_DISTANCE, sample_z) # Samples ridge support to the west.
    var north_ridge: float = _sample_normalized(_mountain_ridge_noise, sample_x, sample_z - MOUNTAIN_WIDTH_SAMPLE_DISTANCE) # Samples ridge support to the north.
    var south_ridge: float = _sample_normalized(_mountain_ridge_noise, sample_x, sample_z + MOUNTAIN_WIDTH_SAMPLE_DISTANCE) # Samples ridge support to the south.
    var surrounding_average: float = (east_ridge + west_ridge + north_ridge + south_ridge) * 0.25 # Measures the broad ridge body independently of one centre maximum.
    return centre_ridge * 0.16 + surrounding_average * 0.84 # Lets kilometre-scale width dominate the retained ridge shape.

func _get_access_corridor_mask(sample_x: float, sample_z: float) -> float: # Creates a connected warped lattice of broad mountain passes covering the complete world.
    var half_spacing: float = ACCESS_CORRIDOR_SPACING * 0.5 # Calculates the centred repeat interval.
    var distance_to_x_corridor: float = absf(fposmod(sample_x + half_spacing, ACCESS_CORRIDOR_SPACING) - half_spacing) # Measures distance to the nearest north-south pass.
    var distance_to_z_corridor: float = absf(fposmod(sample_z + half_spacing, ACCESS_CORRIDOR_SPACING) - half_spacing) # Measures distance to the nearest east-west pass.
    var x_corridor: float = 1.0 - smoothstep(ACCESS_CORRIDOR_CORE_RADIUS, ACCESS_CORRIDOR_BLEND_RADIUS, distance_to_x_corridor) # Builds a broad blended north-south route.
    var z_corridor: float = 1.0 - smoothstep(ACCESS_CORRIDOR_CORE_RADIUS, ACCESS_CORRIDOR_BLEND_RADIUS, distance_to_z_corridor) # Builds a broad blended east-west route.
    return maxf(x_corridor, z_corridor) # Joins both route families into one connected world-spanning network.

func _get_local_water_level(regional_height: float) -> float: # Selects the same flat tiered water elevation used by water mesh generation.
    var water_coordinate: float = (regional_height - TerrainConfiguration.WATER_LEVEL_CLEARANCE - TerrainConfiguration.WATER_LEVEL_OFFSET) / TIER_HEIGHT # Finds the highest water band safely below the surrounding region.
    var water_tier_index: int = clampi(floori(water_coordinate), 0, TIER_LEVEL_COUNT - 1) # Restricts water to the established world elevation bands.
    return float(water_tier_index) * TIER_HEIGHT + TerrainConfiguration.WATER_LEVEL_OFFSET # Returns the exact shared local water elevation.

func _shape_underwater_height(base_terrain_height: float, surface_detail: float, water_level: float) -> float: # Reduces submerged roughness and relief without changing dry land or immediate shorelines.
    var detailed_height: float = base_terrain_height + surface_detail # Resolves the original terrain height before underwater smoothing.
    if detailed_height >= water_level: # Detects land at or above the local water surface.
        return detailed_height # Preserves every dry terrain height exactly.
    var initial_depth: float = water_level - detailed_height # Measures depth before local surface detail is reduced.
    var detail_fade: float = smoothstep(UNDERWATER_DETAIL_FADE_START_DEPTH, UNDERWATER_DETAIL_FADE_END_DEPTH, initial_depth) # Strengthens smoothing gradually after leaving the shoreline.
    var detail_weight: float = lerpf(1.0, UNDERWATER_DETAIL_MINIMUM_WEIGHT, detail_fade) # Retains less high-frequency relief as depth increases.
    var smoothed_height: float = base_terrain_height + surface_detail * detail_weight # Reduces only the local detail layer while preserving broad lowlands.
    var smoothed_depth: float = maxf(water_level - smoothed_height, 0.0) # Recalculates positive water depth after local smoothing.
    var flatten_weight: float = smoothstep(UNDERWATER_FLATTEN_START_DEPTH, UNDERWATER_FLATTEN_FULL_DEPTH, smoothed_depth) # Introduces mild broad relief compression away from shore.
    var depth_scale: float = 1.0 - flatten_weight * UNDERWATER_MAXIMUM_DEPTH_COMPRESSION # Limits the final seabed flattening.
    return water_level - smoothed_depth * depth_scale # Returns a slightly shallower, smoother submerged surface.

func _get_tier_height(macro_elevation: float) -> float: # Converts a normalized macro value into continuous low-gradient regional elevation bands.
    var highest_tier_index: float = float(TIER_LEVEL_COUNT - 1) # Converts the number of bands into the highest valid zero-based index.
    var tier_coordinate: float = clampf(macro_elevation, 0.0, 1.0) * highest_tier_index # Maps the macro value across every band.
    var lower_tier_index: float = floor(tier_coordinate) # Selects the band beneath the current macro coordinate.
    var tier_fraction: float = tier_coordinate - lower_tier_index # Measures progress toward the next band.
    var tier_transition: float = smoothstep(TIER_TRANSITION_START, 1.0, tier_fraction) # Uses the complete interval for a broad smooth ascent.
    return (lower_tier_index + tier_transition) * TIER_HEIGHT # Returns a continuous regional height without discontinuous steps.

func _get_valley_line(noise_value: float, width: float) -> float: # Converts a signed noise contour into one broad winding corridor centre line.
    var distance_from_line: float = absf(noise_value) # Treats the zero contour as the corridor centre.
    var inner_width: float = width * 0.30 # Keeps a broad central floor before side slopes begin.
    return 1.0 - smoothstep(inner_width, width, distance_from_line) # Returns one at the floor centre and zero outside the corridor sides.

func _sample_normalized(noise: FastNoiseLite, sample_x: float, sample_z: float) -> float: # Converts one noise sample into a stable zero-to-one range.
    return clampf((noise.get_noise_2d(sample_x, sample_z) + 1.0) * 0.5, 0.0, 1.0) # Normalizes and clamps the noise output defensively.

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
