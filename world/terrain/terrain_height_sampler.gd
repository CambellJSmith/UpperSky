extends RefCounted # Provides a lightweight deterministic terrain-height service without scene-tree ownership.
class_name TerrainHeightSampler # Makes the sampler available to terrain generation and future world tools.

const WORLD_SEED: int = 742_913 # Keeps the generated landscape stable between playthroughs and builds.
const SPAWN_FLAT_HEIGHT: float = 0.0 # Defines the exact world elevation of the circular initial spawn platform.
const SPAWN_FLAT_RADIUS: float = 8.0 # Keeps several metres around world origin completely level for safe spawning.
const SPAWN_FLAT_BLEND_RADIUS: float = 32.0 # Blends the flat platform smoothly into nearby procedural terrain.
const SPAWN_INNER_RADIUS: float = 320.0 # Keeps the immediate starting region gentle before complete geological relief appears.
const SPAWN_OUTER_RADIUS: float = 1400.0 # Introduces the complete world through a long traversable transition.
const WORLD_WARP_DISTANCE: float = 900.0 # Bends continental provinces, ranges, drainage, and passes without abrupt local distortion.
const TIER_LEVEL_COUNT: int = 6 # Retains six broad water-compatible elevation provinces across the world.
const TIER_HEIGHT: float = 230.0 # Produces clearly higher and lower regions while keeping transitions continental in scale.
const TIER_TRANSITION_START: float = 0.12 # Preserves broad regional interiors while using most of each interval for gradual ascent.
const PLATEAU_UNDULATION_HEIGHT: float = 58.0 # Adds realistic rolling uplands and plains without dominating regional relief.
const BASIN_DEPTH: float = 150.0 # Creates substantial broad basins and lowlands with gradual margins.
const MOUNTAIN_PROVINCE_START: float = 0.55 # Allows long mountain systems in the upper portion of the province field.
const MOUNTAIN_PROVINCE_FULL: float = 0.79 # Reaches full tectonic-province strength only in coherent regional cores.
const MOUNTAIN_MASS_START: float = 0.40 # Requires broad supporting crustal mass before major relief develops.
const MOUNTAIN_MASS_FULL: float = 0.73 # Gives full relief to the strongest overlap of both geological fields.
const MOUNTAIN_BASE_HEIGHT: float = 430.0 # Raises complete mountain provinces above their surrounding piedmont.
const MOUNTAIN_RIDGE_HEIGHT: float = 1800.0 # Builds exceptional long mountain ranges above broad regional uplands.
const MOUNTAIN_SHOULDER_HEIGHT: float = 520.0 # Adds secondary ridges, foothills, and structural mountain shoulders.
const MOUNTAIN_TERRACE_MINIMUM_STEP: float = 95.0 # Defines broad alpine benches rather than small repetitive steps.
const MOUNTAIN_TERRACE_STEP_RANGE: float = 70.0 # Varies alpine bench spacing between mountain provinces.
const MOUNTAIN_WIDTH_SAMPLE_DISTANCE: float = 900.0 # Requires ridge support across nearly two kilometres before major relief is retained.
const MOUNTAIN_WIDTH_EXCESS_START: float = 0.05 # Begins suppressing unsupported narrow protrusions early.
const MOUNTAIN_WIDTH_EXCESS_END: float = 0.18 # Fully replaces needle-like maxima with the surrounding mountain body.
const MOUNTAIN_WIDTH_SUPPORT_START: float = 0.40 # Prevents weak ridge fields from producing isolated severe hills.
const MOUNTAIN_WIDTH_SUPPORT_END: float = 0.65 # Grants full ridge height only where a broad range genuinely exists.
const COASTAL_CLEARANCE_START: float = 24.0 # Treats terrain only slightly above its drainage water band as active shoreline country.
const COASTAL_CLEARANCE_END: float = 185.0 # Completes the transition from coastal plain to unrestricted inland relief.
const COASTAL_PLAIN_MAXIMUM_HEIGHT: float = 34.0 # Keeps ordinary water margins low enough for swimmers to reach traversable land.
const COASTAL_MOUNTAIN_REDUCTION: float = 0.985 # Removes almost all mountain uplift from ordinary coastal and lakeside plains.
const COASTAL_FJORD_START: float = 0.91 # Allows steep mountain-water contact only in the rare upper tail of a separate field.
const COASTAL_FJORD_FULL: float = 0.985 # Reserves complete fjord or cliff-coast behaviour for exceptional locations.
const ACCESS_CORRIDOR_SPACING: float = 8192.0 # Provides a sparse hidden connected fallback through the largest mountain systems.
const ACCESS_CORRIDOR_CORE_RADIUS: float = 170.0 # Defines the low central saddle of each geological fallback corridor.
const ACCESS_CORRIDOR_BLEND_RADIUS: float = 1250.0 # Blends the fallback through broad foothills so it does not read as a road cut.
const ACCESS_CORRIDOR_MOUNTAIN_REDUCTION: float = 0.90 # Preserves surrounding range identity while guaranteeing a lower crossing.
const PRIMARY_VALLEY_BASE_DEPTH: float = 145.0 # Gives major drainage valleys substantial but broadly graded relief.
const PRIMARY_VALLEY_TIER_DEPTH: float = 270.0 # Deepens trunk valleys through higher regional provinces.
const PRIMARY_VALLEY_MOUNTAIN_DEPTH: float = 650.0 # Lets major rivers and glacial valleys cut realistic passes through mountain systems.
const SECONDARY_VALLEY_BASE_DEPTH: float = 58.0 # Gives tributaries visible drainage relief across ordinary land.
const SECONDARY_VALLEY_TIER_DEPTH: float = 115.0 # Deepens tributaries moderately on high regional ground.
const SECONDARY_VALLEY_MOUNTAIN_DEPTH: float = 210.0 # Lets tributaries enter mountain flanks without becoming impassable ravines.
const LOWEST_VALLEY_FLOOR: float = -280.0 # Prevents combined basins and valleys from descending without a controlled floor.
const SURFACE_DETAIL_HEIGHT: float = 10.0 # Adds local geological texture without overwhelming the eight-metre terrain grid.
const SUMMIT_DETAIL_FADE_START: float = 0.70 # Begins suppressing secondary detail before primary mountain crests.
const SUMMIT_DETAIL_FADE_END: float = 0.94 # Removes small-scale roughness around rounded summits.
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
var _plateau_noise: FastNoiseLite # Adds rolling relief across plains and uplands.
var _basin_noise: FastNoiseLite # Creates broad sedimentary basins and lowlands.
var _mountain_province_noise: FastNoiseLite # Determines where large tectonic mountain systems may exist.
var _mountain_mass_noise: FastNoiseLite # Controls the broad supporting mass inside each mountain province.
var _mountain_ridge_noise: FastNoiseLite # Produces primary long mountain-chain structure.
var _mountain_detail_noise: FastNoiseLite # Produces secondary mountain shoulders and side ridges.
var _mountain_terrace_noise: FastNoiseLite # Varies broad alpine benches and structural levels.
var _primary_valley_noise: FastNoiseLite # Produces the longest drainage valleys and natural mountain passes.
var _secondary_valley_noise: FastNoiseLite # Produces branching tributary valleys.
var _valley_width_noise: FastNoiseLite # Varies drainage width over long distances.
var _surface_detail_noise: FastNoiseLite # Adds restrained local ground variation.
var _coastal_relief_noise: FastNoiseLite # Selects rare fjords and cliff coasts within otherwise accessible water margins.

func _init() -> void: # Builds every deterministic field used by the geological terrain hierarchy.
    _warp_x_noise = _create_noise(11, 0.000075, 3, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates slow x-axis continental distortion.
    _warp_z_noise = _create_noise(23, 0.000075, 3, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates independent slow z-axis distortion.
    _continent_noise = _create_noise(37, 0.000020, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates extremely broad continental rises and depressions.
    _tier_noise = _create_noise(41, 0.000038, 4, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Adds long regional elevation provinces.
    _tier_breakup_noise = _create_noise(53, 0.000085, 3, 0.48, 2.0, FastNoiseLite.FRACTAL_FBM) # Breaks broad province contours without local cliffs.
    _plateau_noise = _create_noise(59, 0.00022, 4, 0.48, 2.0, FastNoiseLite.FRACTAL_FBM) # Adds rolling plains, plateaus, and uplands.
    _basin_noise = _create_noise(61, 0.000075, 3, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates large sedimentary basin regions.
    _mountain_province_noise = _create_noise(67, 0.000022, 3, 0.54, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates mountain provinces tens of kilometres long.
    _mountain_mass_noise = _create_noise(71, 0.000048, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Shapes broad mountain mass inside each province.
    _mountain_ridge_noise = _create_noise(83, 0.000105, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_RIDGED) # Creates wide rounded primary ranges.
    _mountain_detail_noise = _create_noise(97, 0.00023, 3, 0.46, 2.0, FastNoiseLite.FRACTAL_RIDGED) # Creates supported secondary ridges and shoulders.
    _mountain_terrace_noise = _create_noise(101, 0.00009, 3, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Varies broad alpine bench structure.
    _primary_valley_noise = _create_noise(113, 0.000065, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates long trunk valleys crossing regional and mountain terrain.
    _secondary_valley_noise = _create_noise(127, 0.00015, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates branching tributary drainage.
    _valley_width_noise = _create_noise(139, 0.00005, 3, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Changes drainage width gradually over kilometres.
    _surface_detail_noise = _create_noise(149, 0.00135, 2, 0.40, 2.0, FastNoiseLite.FRACTAL_FBM) # Adds restrained local ground texture.
    _coastal_relief_noise = _create_noise(157, 0.000075, 3, 0.50, 2.0, FastNoiseLite.FRACTAL_FBM) # Selects rare coherent fjord and cliff-coast provinces.

func sample_height(world_x: float, world_z: float) -> float: # Returns the deterministic terrain height at one world-space horizontal position.
    var warp_x: float = _warp_x_noise.get_noise_2d(world_x, world_z) * WORLD_WARP_DISTANCE # Calculates broad x-axis distortion.
    var warp_z: float = _warp_z_noise.get_noise_2d(world_x, world_z) * WORLD_WARP_DISTANCE # Calculates independent broad z-axis distortion.
    var sample_x: float = world_x + warp_x # Applies coordinate distortion before sampling geological systems.
    var sample_z: float = world_z + warp_z # Applies independent z distortion before sampling geological systems.
    var continent_value: float = _sample_normalized(_continent_noise, sample_x, sample_z) # Reads the broad continental elevation tendency.
    var tier_value: float = _sample_normalized(_tier_noise, sample_x, sample_z) # Reads secondary regional elevation variation.
    var tier_breakup_value: float = _sample_normalized(_tier_breakup_noise, sample_x, sample_z) # Reads smaller broad-contour breakup.
    var macro_elevation: float = clampf(continent_value * 0.60 + tier_value * 0.30 + tier_breakup_value * 0.10, 0.0, 1.0) # Lets continental and regional fields dominate height.
    macro_elevation = lerpf(0.08, 0.92, smoothstep(0.05, 0.95, macro_elevation)) # Retains meaningful high and low provinces without using absolute extremes everywhere.
    var tier_height: float = _get_tier_height(macro_elevation) # Converts the macro coordinate into broad connected elevation provinces.
    var plateau_relief: float = _plateau_noise.get_noise_2d(sample_x, sample_z) * PLATEAU_UNDULATION_HEIGHT # Adds rolling relief across the current province.
    var basin_value: float = _sample_normalized(_basin_noise, sample_x, sample_z) # Reads the broad basin field.
    var basin_mask: float = smoothstep(0.62, 0.90, 1.0 - basin_value) # Selects coherent lowland and sedimentary basin regions.
    var basin_cut: float = basin_mask * BASIN_DEPTH # Lowers selected provinces through broad gradual margins.
    var base_height: float = tier_height + plateau_relief - basin_cut # Resolves ordinary plains, uplands, plateaus, and basins.
    var regional_water_height: float = tier_height + plateau_relief * TerrainConfiguration.WATER_REGIONAL_PLATEAU_INFLUENCE - basin_cut * TerrainConfiguration.WATER_REGIONAL_BASIN_INFLUENCE # Reconstructs the broad height used by water-band selection.
    var local_water_level: float = _get_local_water_level(regional_water_height) # Selects the exact flat local water elevation.

    var valley_width_value: float = _sample_normalized(_valley_width_noise, sample_x, sample_z) # Reads slowly changing drainage-width control.
    var primary_valley_width: float = lerpf(0.14, 0.30, valley_width_value) # Makes trunk valleys broad enough to carry rivers and travel routes.
    var secondary_valley_width: float = lerpf(0.075, 0.16, 1.0 - valley_width_value) # Gives tributaries complementary changing width.
    var primary_valley_line: float = _get_valley_line(_primary_valley_noise.get_noise_2d(sample_x, sample_z), primary_valley_width) # Finds positions near the main drainage network.
    var secondary_valley_line: float = _get_valley_line(_secondary_valley_noise.get_noise_2d(sample_x, sample_z), secondary_valley_width) # Finds positions near tributary drainage.
    var primary_valley_shape: float = pow(primary_valley_line, 1.25) # Keeps trunk valley floors and walls broad.
    var secondary_valley_shape: float = pow(secondary_valley_line, 1.65) # Keeps tributaries narrower while retaining graded sides.

    var preview_primary_depth: float = PRIMARY_VALLEY_BASE_DEPTH + macro_elevation * PRIMARY_VALLEY_TIER_DEPTH # Estimates drainage depth before mountain uplift.
    var preview_primary_floor: float = maxf(LOWEST_VALLEY_FLOOR, tier_height - 250.0 + plateau_relief * 0.10) # Keeps preview trunk valleys tied to regional elevation.
    var preview_primary_height: float = lerpf(base_height, maxf(preview_primary_floor, base_height - preview_primary_depth), primary_valley_shape) # Estimates the pre-mountain drainage surface.
    var preview_secondary_weight: float = secondary_valley_shape * (1.0 - primary_valley_shape * 0.68) # Prevents preview tributaries from stacking at trunk valley centres.
    var preview_secondary_depth: float = SECONDARY_VALLEY_BASE_DEPTH + macro_elevation * SECONDARY_VALLEY_TIER_DEPTH # Estimates tributary depth before mountain uplift.
    var preview_secondary_floor: float = maxf(LOWEST_VALLEY_FLOOR, tier_height - 155.0 + plateau_relief * 0.08) # Keeps preview tributaries near their regional province.
    var preview_drainage_height: float = lerpf(preview_primary_height, maxf(preview_secondary_floor, preview_primary_height - preview_secondary_depth), preview_secondary_weight) # Estimates where water and low valley land can occur.
    var drainage_clearance: float = maxf(preview_drainage_height - local_water_level, 0.0) # Measures vertical room between likely drainage terrain and water.
    var coastal_plain_weight: float = 1.0 - smoothstep(COASTAL_CLEARANCE_START, COASTAL_CLEARANCE_END, drainage_clearance) # Selects coastlines, lakesides, and broad river margins.
    var fjord_exception: float = smoothstep(COASTAL_FJORD_START, COASTAL_FJORD_FULL, _sample_normalized(_coastal_relief_noise, sample_x, sample_z)) # Selects rare coherent steep-water geology.
    var coastal_protection: float = coastal_plain_weight * (1.0 - fjord_exception) # Protects ordinary water margins while preserving exceptional fjords.

    var mountain_province_value: float = _sample_normalized(_mountain_province_noise, sample_x, sample_z) # Reads long tectonic-province placement.
    var mountain_province_mask: float = smoothstep(MOUNTAIN_PROVINCE_START, MOUNTAIN_PROVINCE_FULL, mountain_province_value) # Selects coherent mountain belts.
    var mountain_mass_value: float = _sample_normalized(_mountain_mass_noise, sample_x, sample_z) # Reads broad internal mountain mass.
    var mountain_mass_mask: float = smoothstep(MOUNTAIN_MASS_START, MOUNTAIN_MASS_FULL, mountain_mass_value) # Requires broad supporting mass before relief appears.
    var mountain_presence: float = mountain_province_mask * mountain_mass_mask # Combines tectonic belt and supporting mass.
    mountain_presence *= 1.0 - coastal_protection * COASTAL_MOUNTAIN_REDUCTION # Moves ordinary ranges inland behind coastal plains and piedmont.
    var mountain_height: float = 0.0 # Keeps non-mountain terrain free of expensive ridge work.
    if mountain_presence > 0.001: # Performs ridge sampling only where a genuine range can exist.
        var primary_ridge_value: float = _sample_normalized(_mountain_ridge_noise, sample_x, sample_z) # Reads the primary ridged mountain field.
        var broad_primary_ridge: float = _sample_broad_ridge_support(sample_x, sample_z, primary_ridge_value) # Measures kilometre-scale support around the ridge.
        var unsupported_ridge_excess: float = maxf(primary_ridge_value - broad_primary_ridge, 0.0) # Detects narrow protrusions above the broad range.
        var ridge_width_weight: float = 1.0 - smoothstep(MOUNTAIN_WIDTH_EXCESS_START, MOUNTAIN_WIDTH_EXCESS_END, unsupported_ridge_excess) # Suppresses relief as a ridge becomes too narrow.
        var supported_primary_ridge: float = lerpf(broad_primary_ridge, primary_ridge_value, ridge_width_weight) # Replaces thin peaks with their broad support height.
        var broad_ridge_support: float = smoothstep(MOUNTAIN_WIDTH_SUPPORT_START, MOUNTAIN_WIDTH_SUPPORT_END, broad_primary_ridge) # Requires a substantial surrounding mountain body.
        var secondary_ridge_value: float = _sample_normalized(_mountain_detail_noise, sample_x, sample_z) # Reads secondary shoulders and side ridges.
        var rounded_primary_ridge: float = sin(supported_primary_ridge * PI * 0.5) # Gives primary ridges rounded crests.
        var rounded_secondary_ridge: float = sin(secondary_ridge_value * PI * 0.5) # Rounds secondary maxima before adding relief.
        var primary_ridge_shape: float = pow(rounded_primary_ridge, 1.46) * broad_ridge_support # Retains broad high primary ranges.
        var secondary_width_support: float = lerpf(0.22, 1.0, broad_ridge_support) * ridge_width_weight # Prevents unsupported side ridges.
        var secondary_ridge_shape: float = pow(rounded_secondary_ridge, 2.10) * secondary_width_support # Restricts detailed relief to supported mountain interiors.
        var summit_detail_weight: float = 1.0 - smoothstep(SUMMIT_DETAIL_FADE_START, SUMMIT_DETAIL_FADE_END, rounded_primary_ridge) # Removes rough detail around summits.
        var mountain_base: float = mountain_presence * MOUNTAIN_BASE_HEIGHT # Raises the complete mountain belt gradually above its piedmont.
        var mountain_ridge: float = mountain_presence * primary_ridge_shape * MOUNTAIN_RIDGE_HEIGHT # Adds broad primary range relief.
        var mountain_shoulders: float = mountain_presence * secondary_ridge_shape * MOUNTAIN_SHOULDER_HEIGHT * summit_detail_weight # Adds supported side structure.
        mountain_height = mountain_base + mountain_ridge + mountain_shoulders # Resolves the continuous mountain profile.
        var mountain_terrace_value: float = _sample_normalized(_mountain_terrace_noise, sample_x, sample_z) # Reads broad alpine bench-control variation.
        var mountain_terrace_step: float = MOUNTAIN_TERRACE_MINIMUM_STEP + mountain_terrace_value * MOUNTAIN_TERRACE_STEP_RANGE # Varies bench spacing.
        var terraced_mountain_height: float = snappedf(mountain_height, mountain_terrace_step) # Calculates a broad geological bench target.
        var mountain_terrace_strength: float = mountain_presence * lerpf(0.03, 0.09, mountain_terrace_value) # Keeps structural benches visible without producing walls.
        mountain_height = lerpf(mountain_height, terraced_mountain_height, mountain_terrace_strength) # Blends broad benches into the range.
        var natural_pass_weight: float = maxf(primary_valley_shape * 0.88, secondary_valley_shape * 0.38) # Uses drainage valleys as the principal realistic mountain crossings.
        var fallback_pass_weight: float = _get_access_corridor_mask(sample_x, sample_z) * ACCESS_CORRIDOR_MOUNTAIN_REDUCTION # Adds a sparse hidden crossing only where drainage does not provide one.
        mountain_height *= 1.0 - clampf(maxf(natural_pass_weight, fallback_pass_weight), 0.0, 0.96) # Lowers range relief through broad connected passes.

    var uncarved_height: float = base_height + mountain_height # Resolves regional terrain and mountain uplift before erosion.
    var primary_valley_depth: float = PRIMARY_VALLEY_BASE_DEPTH + macro_elevation * PRIMARY_VALLEY_TIER_DEPTH + mountain_presence * PRIMARY_VALLEY_MOUNTAIN_DEPTH # Deepens trunk valleys through highlands and ranges.
    var primary_valley_floor: float = maxf(LOWEST_VALLEY_FLOOR, tier_height - 250.0 + plateau_relief * 0.10) # Gives each trunk valley a broad regional floor.
    var primary_carved_height: float = maxf(primary_valley_floor, uncarved_height - primary_valley_depth) # Calculates the deepest permitted trunk-valley surface.
    var height_after_primary_valley: float = lerpf(uncarved_height, primary_carved_height, primary_valley_shape) # Blends mountain walls and uplands into broad valley floors.
    var secondary_valley_weight: float = secondary_valley_shape * (1.0 - primary_valley_shape * 0.68) # Prevents tributaries from stacking extreme cuts at trunk valley centres.
    var secondary_valley_depth: float = SECONDARY_VALLEY_BASE_DEPTH + macro_elevation * SECONDARY_VALLEY_TIER_DEPTH + mountain_presence * SECONDARY_VALLEY_MOUNTAIN_DEPTH # Deepens tributaries according to surrounding geology.
    var secondary_valley_floor: float = maxf(LOWEST_VALLEY_FLOOR, tier_height - 155.0 + plateau_relief * 0.08) # Keeps tributary floors tied to regional elevation.
    var secondary_carved_height: float = maxf(secondary_valley_floor, height_after_primary_valley - secondary_valley_depth) # Calculates the tributary target surface.
    var valley_height: float = lerpf(height_after_primary_valley, secondary_carved_height, secondary_valley_weight) # Blends tributaries into plains, uplands, and ranges.
    if valley_height > local_water_level: # Applies accessible coastal grading only to dry terrain.
        var coastal_plain_target: float = local_water_level + COASTAL_PLAIN_MAXIMUM_HEIGHT + plateau_relief * 0.10 # Keeps ordinary shore country low but naturally varied.
        var coastal_grade_weight: float = coastal_protection * 0.92 # Preserves a small amount of local relief while strongly grading water exits.
        valley_height = lerpf(valley_height, minf(valley_height, coastal_plain_target), coastal_grade_weight) # Forms beaches, floodplains, lake margins, and coastal piedmont before mountains begin.
    var valley_suppression: float = clampf(maxf(primary_valley_shape, secondary_valley_shape) * 0.84, 0.0, 1.0) # Suppresses local noise on broad drainage floors.
    var mountain_detail_weight: float = lerpf(1.0, 0.48, mountain_presence) # Reduces small roughness on mountain approaches and summits.
    var coastal_detail_weight: float = lerpf(1.0, 0.32, coastal_protection) # Keeps ordinary water margins smooth enough to leave the water.
    var surface_detail: float = _surface_detail_noise.get_noise_2d(sample_x, sample_z) * SURFACE_DETAIL_HEIGHT * (1.0 - valley_suppression) * mountain_detail_weight * coastal_detail_weight # Adds restrained local geological texture.
    var full_height: float = _shape_underwater_height(valley_height, surface_detail, local_water_level) # Smooths and mildly flattens submerged terrain.
    var spawn_distance: float = Vector2(world_x, world_z).length() # Measures distance from the world-origin spawn centre.
    var spawn_blend: float = smoothstep(SPAWN_INNER_RADIUS, SPAWN_OUTER_RADIUS, spawn_distance) # Introduces complete geological relief gradually outside the start.
    var spawn_height: float = plateau_relief * 0.14 + surface_detail * 0.20 # Keeps the initial region gently rolling without mountain walls.
    var procedural_height: float = lerpf(spawn_height, full_height, spawn_blend) # Blends the safe start into the complete world.
    var flat_blend: float = smoothstep(SPAWN_FLAT_RADIUS, SPAWN_FLAT_BLEND_RADIUS, spawn_distance) # Keeps the innermost spawn circle exactly level.
    var terrain_height: float = lerpf(SPAWN_FLAT_HEIGHT, procedural_height, flat_blend) # Resolves the original deterministic geological terrain height.
    var path_wear_offset: float = TerrainPathSampler.get_height_offset(Vector2(world_x, world_z)) * flat_blend # Adds shallow compacted wear while preserving the exact flat spawn centre.
    return terrain_height + path_wear_offset # Returns terrain with the shared worn-path depression applied.

func _sample_broad_ridge_support(sample_x: float, sample_z: float, centre_ridge: float) -> float: # Measures broad ridge support so narrow protrusions cannot receive full mountain height.
    var east_ridge: float = _sample_normalized(_mountain_ridge_noise, sample_x + MOUNTAIN_WIDTH_SAMPLE_DISTANCE, sample_z) # Samples ridge support to the east.
    var west_ridge: float = _sample_normalized(_mountain_ridge_noise, sample_x - MOUNTAIN_WIDTH_SAMPLE_DISTANCE, sample_z) # Samples ridge support to the west.
    var north_ridge: float = _sample_normalized(_mountain_ridge_noise, sample_x, sample_z - MOUNTAIN_WIDTH_SAMPLE_DISTANCE) # Samples ridge support to the north.
    var south_ridge: float = _sample_normalized(_mountain_ridge_noise, sample_x, sample_z + MOUNTAIN_WIDTH_SAMPLE_DISTANCE) # Samples ridge support to the south.
    var surrounding_average: float = (east_ridge + west_ridge + north_ridge + south_ridge) * 0.25 # Measures the broad ridge body independently of one centre maximum.
    return centre_ridge * 0.18 + surrounding_average * 0.82 # Lets kilometre-scale width dominate retained ridge shape.

func _get_access_corridor_mask(sample_x: float, sample_z: float) -> float: # Creates a sparse warped connected fallback of broad geological saddles.
    var half_spacing: float = ACCESS_CORRIDOR_SPACING * 0.5 # Calculates the centred repeat interval.
    var distance_to_x_corridor: float = absf(fposmod(sample_x + half_spacing, ACCESS_CORRIDOR_SPACING) - half_spacing) # Measures distance to the nearest north-south saddle family.
    var distance_to_z_corridor: float = absf(fposmod(sample_z + half_spacing, ACCESS_CORRIDOR_SPACING) - half_spacing) # Measures distance to the nearest east-west saddle family.
    var x_corridor: float = 1.0 - smoothstep(ACCESS_CORRIDOR_CORE_RADIUS, ACCESS_CORRIDOR_BLEND_RADIUS, distance_to_x_corridor) # Builds a broad blended north-south crossing.
    var z_corridor: float = 1.0 - smoothstep(ACCESS_CORRIDOR_CORE_RADIUS, ACCESS_CORRIDOR_BLEND_RADIUS, distance_to_z_corridor) # Builds a broad blended east-west crossing.
    return maxf(x_corridor, z_corridor) # Joins both sparse families into one connected fallback network.

func _get_local_water_level(regional_height: float) -> float: # Selects the same flat tiered water elevation used by water mesh generation.
    var water_coordinate: float = (regional_height - TerrainConfiguration.WATER_LEVEL_CLEARANCE - TerrainConfiguration.WATER_LEVEL_OFFSET) / TIER_HEIGHT # Finds the highest water band safely below the surrounding region.
    var water_tier_index: int = clampi(floori(water_coordinate), 0, TIER_LEVEL_COUNT - 1) # Restricts water to the established elevation provinces.
    return float(water_tier_index) * TIER_HEIGHT + TerrainConfiguration.WATER_LEVEL_OFFSET # Returns the exact shared local water elevation.

func _shape_underwater_height(base_terrain_height: float, surface_detail: float, water_level: float) -> float: # Reduces submerged roughness and relief without changing dry land or immediate shorelines.
    var detailed_height: float = base_terrain_height + surface_detail # Resolves the original terrain height before underwater smoothing.
    if detailed_height >= water_level: # Detects land at or above the local water surface.
        return detailed_height # Preserves every dry terrain height exactly.
    var initial_depth: float = water_level - detailed_height # Measures depth before local surface detail is reduced.
    var detail_fade: float = smoothstep(UNDERWATER_DETAIL_FADE_START_DEPTH, UNDERWATER_DETAIL_FADE_END_DEPTH, initial_depth) # Strengthens smoothing gradually after leaving the shoreline.
    var detail_weight: float = lerpf(1.0, UNDERWATER_DETAIL_MINIMUM_WEIGHT, detail_fade) # Retains less high-frequency relief as depth increases.
    var smoothed_height: float = base_terrain_height + surface_detail * detail_weight # Reduces only the local detail layer while preserving broad submerged geology.
    var smoothed_depth: float = maxf(water_level - smoothed_height, 0.0) # Recalculates positive water depth after local smoothing.
    var flatten_weight: float = smoothstep(UNDERWATER_FLATTEN_START_DEPTH, UNDERWATER_FLATTEN_FULL_DEPTH, smoothed_depth) # Introduces mild broad relief compression away from shore.
    var depth_scale: float = 1.0 - flatten_weight * UNDERWATER_MAXIMUM_DEPTH_COMPRESSION # Limits final seabed flattening.
    return water_level - smoothed_depth * depth_scale # Returns a slightly shallower, smoother submerged surface.

func _get_tier_height(macro_elevation: float) -> float: # Converts a normalized macro value into continuous regional elevation provinces.
    var highest_tier_index: float = float(TIER_LEVEL_COUNT - 1) # Converts the number of provinces into the highest valid zero-based index.
    var tier_coordinate: float = clampf(macro_elevation, 0.0, 1.0) * highest_tier_index # Maps the macro value across every province.
    var lower_tier_index: float = floor(tier_coordinate) # Selects the province beneath the current coordinate.
    var tier_fraction: float = tier_coordinate - lower_tier_index # Measures progress toward the next province.
    var tier_transition: float = smoothstep(TIER_TRANSITION_START, 1.0, tier_fraction) # Uses a long smooth ascent between regional interiors.
    return (lower_tier_index + tier_transition) * TIER_HEIGHT # Returns a continuous regional height without discontinuous steps.

func _get_valley_line(noise_value: float, width: float) -> float: # Converts a signed noise contour into one broad winding drainage centre line.
    var distance_from_line: float = absf(noise_value) # Treats the zero contour as the drainage centre.
    var inner_width: float = width * 0.27 # Keeps a broad central floor before valley sides begin.
    return 1.0 - smoothstep(inner_width, width, distance_from_line) # Returns one at the floor centre and zero outside the valley sides.

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
