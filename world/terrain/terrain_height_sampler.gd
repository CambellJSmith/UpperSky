extends RefCounted # Provides a lightweight deterministic terrain-height service without scene-tree ownership.
class_name TerrainHeightSampler # Makes the sampler available to terrain generation and future world tools.

const WORLD_SEED: int = 742_913 # Keeps the generated landscape stable between playthroughs and builds.
const SPAWN_FLAT_HEIGHT: float = 0.0 # Defines the exact world elevation of the circular initial spawn platform.
const SPAWN_FLAT_RADIUS: float = 8.0 # Keeps several metres around world origin completely level for safe spawning.
const SPAWN_FLAT_BLEND_RADIUS: float = 32.0 # Blends the flat platform smoothly into nearby procedural terrain.
const SPAWN_INNER_RADIUS: float = 320.0 # Keeps the immediate starting region readable before monumental terrain fully appears.
const SPAWN_OUTER_RADIUS: float = 1200.0 # Introduces the complete tiered world over a long traversable transition.
const WORLD_WARP_DISTANCE: float = 1400.0 # Bends all macro terrain coordinates so shelves, ranges, and valleys wind organically.
const TIER_LEVEL_COUNT: int = 6 # Creates six continent-scale elevation bands across the world.
const TIER_HEIGHT: float = 360.0 # Separates neighbouring macro elevation shelves by hundreds of metres.
const TIER_TRANSITION_START: float = 0.63 # Keeps most of each macro band broad and shelf-like before the next climb begins.
const PLATEAU_UNDULATION_HEIGHT: float = 135.0 # Adds large rolling relief across otherwise broad elevation shelves.
const BASIN_DEPTH: float = 240.0 # Lowers selected regions into enormous basins between plateau systems.
const MOUNTAIN_BASE_HEIGHT: float = 850.0 # Raises entire mountain provinces before individual ridge relief is applied.
const MOUNTAIN_RIDGE_HEIGHT: float = 2300.0 # Builds kilometre-scale primary ridges above their surrounding tiers.
const MOUNTAIN_SHOULDER_HEIGHT: float = 620.0 # Adds substantial secondary ridges and traversable mountain shoulders.
const MOUNTAIN_TERRACE_MINIMUM_STEP: float = 110.0 # Creates giant alpine shelves instead of small repetitive steps.
const MOUNTAIN_TERRACE_STEP_RANGE: float = 90.0 # Varies shelf spacing across different mountain provinces.
const MOUNTAIN_WIDTH_SAMPLE_DISTANCE: float = 520.0 # Measures ridge support more than a kilometre across before allowing extreme mountain relief.
const MOUNTAIN_WIDTH_EXCESS_START: float = 0.06 # Begins reducing a ridge when its centre rises noticeably above its broad surroundings.
const MOUNTAIN_WIDTH_EXCESS_END: float = 0.22 # Fully replaces unsupported narrow ridge maxima with the broad surrounding ridge level.
const MOUNTAIN_WIDTH_SUPPORT_START: float = 0.38 # Prevents weak broad ridge fields from carrying full kilometre-scale relief.
const MOUNTAIN_WIDTH_SUPPORT_END: float = 0.62 # Grants full ridge height only where a substantial surrounding mountain body exists.
const PRIMARY_VALLEY_BASE_DEPTH: float = 700.0 # Gives the major valley network substantial depth even in lower regions.
const PRIMARY_VALLEY_TIER_DEPTH: float = 1200.0 # Lets major valleys cut through several macro elevation tiers.
const PRIMARY_VALLEY_MOUNTAIN_DEPTH: float = 850.0 # Allows long valleys to divide entire mountain systems.
const SECONDARY_VALLEY_BASE_DEPTH: float = 360.0 # Gives tributary valleys meaningful relief outside mountain terrain.
const SECONDARY_VALLEY_TIER_DEPTH: float = 650.0 # Deepens tributaries on upper shelves and high plateaus.
const SECONDARY_VALLEY_MOUNTAIN_DEPTH: float = 360.0 # Lets tributaries branch into mountain flanks without creating spikes.
const LOWEST_VALLEY_FLOOR: float = -260.0 # Prevents extreme valley combinations from descending without a controlled floor.
const SURFACE_DETAIL_HEIGHT: float = 18.0 # Adds broad local relief without overwhelming the eight-metre terrain grid.
const SUMMIT_DETAIL_FADE_START: float = 0.70 # Begins suppressing secondary ridges as the primary mountain crest rises.
const SUMMIT_DETAIL_FADE_END: float = 0.95 # Removes small-scale detail before primary ridges reach their rounded summit.
const SHORELINE_LAND_BAND_MINIMUM: float = 140.0 # Starts shoreline softening across a broad vertical approach above each local water level.
const SHORELINE_LAND_BAND_RANGE: float = 90.0 # Varies dry shoreline influence from broad beaches to still-gentle rocky approaches.
const SHORELINE_UNDERWATER_BAND_MINIMUM: float = 100.0 # Creates substantial shallow shelves beneath every local water surface.
const SHORELINE_UNDERWATER_BAND_RANGE: float = 70.0 # Varies shelf depth over long distances without changing the flat water elevation.
const SHORELINE_LAND_PROFILE_MINIMUM: float = 2.0 # Flattens the immediate dry shoreline while preserving slope continuity at the outer band.
const SHORELINE_LAND_PROFILE_RANGE: float = 0.65 # Produces broader shallow beaches in selected shoreline regions.
const SHORELINE_UNDERWATER_PROFILE_MINIMUM: float = 1.75 # Makes submerged terrain deepen gradually immediately offshore.
const SHORELINE_UNDERWATER_PROFILE_RANGE: float = 0.55 # Produces varied but consistently traversable underwater shelves.

var _warp_x_noise: FastNoiseLite # Distorts world sampling along the x axis at continental scale.
var _warp_z_noise: FastNoiseLite # Distorts world sampling along the z axis independently.
var _continent_noise: FastNoiseLite # Establishes the broadest continental elevation tendency.
var _tier_noise: FastNoiseLite # Selects the dominant macro elevation shelf.
var _tier_breakup_noise: FastNoiseLite # Prevents shelf boundaries from following one simple noise field.
var _plateau_noise: FastNoiseLite # Adds rolling relief within each large elevation shelf.
var _basin_noise: FastNoiseLite # Creates kilometre-scale depressed regions between highlands.
var _mountain_province_noise: FastNoiseLite # Determines where immense mountain systems may exist.
var _mountain_mass_noise: FastNoiseLite # Controls the broad footprint of each mountain province.
var _mountain_ridge_noise: FastNoiseLite # Produces the primary rounded mountain chain structure.
var _mountain_detail_noise: FastNoiseLite # Produces secondary mountain shoulders and side ridges.
var _mountain_terrace_noise: FastNoiseLite # Varies giant alpine shelf spacing and strength.
var _primary_valley_noise: FastNoiseLite # Produces the longest and deepest winding valley network.
var _secondary_valley_noise: FastNoiseLite # Produces branching tributary valleys at a smaller scale.
var _valley_width_noise: FastNoiseLite # Varies valley widths over long distances.
var _surface_detail_noise: FastNoiseLite # Adds restrained local terrain variation after macro shaping.
var _shoreline_profile_noise: FastNoiseLite # Varies shoreline and underwater-shelf breadth over kilometre-scale regions.

func _init() -> void: # Builds every deterministic noise source used by the terrain hierarchy.
    _warp_x_noise = _create_noise(11, 0.00013, 3, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates slow continental x-axis coordinate distortion.
    _warp_z_noise = _create_noise(23, 0.00013, 3, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates independent slow continental z-axis coordinate distortion.
    _continent_noise = _create_noise(37, 0.000035, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates continental rises spanning many kilometres.
    _tier_noise = _create_noise(41, 0.000075, 4, 0.52, 2.0, FastNoiseLite.FRACTAL_FBM) # Selects huge regional elevation shelves.
    _tier_breakup_noise = _create_noise(53, 0.00018, 3, 0.48, 2.0, FastNoiseLite.FRACTAL_FBM) # Breaks shelf boundaries into complex regional shapes.
    _plateau_noise = _create_noise(59, 0.00045, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Adds broad rolling relief across each shelf.
    _basin_noise = _create_noise(61, 0.00016, 3, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates enormous basin regions between high plateaus.
    _mountain_province_noise = _create_noise(67, 0.000055, 3, 0.54, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates mountain provinces tens of kilometres across.
    _mountain_mass_noise = _create_noise(71, 0.00012, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Shapes the broad mass inside each mountain province.
    _mountain_ridge_noise = _create_noise(83, 0.00026, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_RIDGED) # Creates huge rounded primary ridges.
    _mountain_detail_noise = _create_noise(97, 0.00062, 3, 0.46, 2.0, FastNoiseLite.FRACTAL_RIDGED) # Creates large secondary shoulders without needle peaks.
    _mountain_terrace_noise = _create_noise(101, 0.00019, 3, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Varies giant alpine shelf structure.
    _primary_valley_noise = _create_noise(113, 0.00012, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates long winding continent-scale valley centre lines.
    _secondary_valley_noise = _create_noise(127, 0.00029, 4, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Creates branching tributary valley lines.
    _valley_width_noise = _create_noise(139, 0.00008, 3, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Changes valley width gradually over several kilometres.
    _surface_detail_noise = _create_noise(149, 0.0018, 3, 0.42, 2.0, FastNoiseLite.FRACTAL_FBM) # Adds broad local detail appropriate to the coarse mesh.
    _shoreline_profile_noise = _create_noise(157, 0.00032, 3, 0.5, 2.0, FastNoiseLite.FRACTAL_FBM) # Varies broad shoreline profiles without creating small repetitive beach bands.

func sample_height(world_x: float, world_z: float) -> float: # Returns the deterministic terrain height at one world-space horizontal position.
    var warp_x: float = _warp_x_noise.get_noise_2d(world_x, world_z) * WORLD_WARP_DISTANCE # Calculates macro x-axis distortion.
    var warp_z: float = _warp_z_noise.get_noise_2d(world_x, world_z) * WORLD_WARP_DISTANCE # Calculates independent macro z-axis distortion.
    var sample_x: float = world_x + warp_x # Applies coordinate distortion before sampling all large terrain systems.
    var sample_z: float = world_z + warp_z # Applies independent z distortion before sampling all large terrain systems.
    var continent_value: float = _sample_normalized(_continent_noise, sample_x, sample_z) # Reads the broad continental elevation tendency.
    var tier_value: float = _sample_normalized(_tier_noise, sample_x, sample_z) # Reads the primary regional shelf selector.
    var tier_breakup_value: float = _sample_normalized(_tier_breakup_noise, sample_x, sample_z) # Reads shelf-boundary breakup at a smaller scale.
    var macro_elevation: float = clampf(continent_value * 0.52 + tier_value * 0.36 + tier_breakup_value * 0.12, 0.0, 1.0) # Combines three scales into one stable regional elevation coordinate.
    macro_elevation = smoothstep(0.08, 0.92, macro_elevation) # Expands the lowest and highest regions while keeping transitions continuous.
    var tier_height: float = _get_tier_height(macro_elevation) # Converts the macro coordinate into broad smoothly connected elevation shelves.
    var plateau_relief: float = _plateau_noise.get_noise_2d(sample_x, sample_z) * PLATEAU_UNDULATION_HEIGHT # Adds rolling relief across the current shelf.
    var basin_value: float = _sample_normalized(_basin_noise, sample_x, sample_z) # Reads the regional basin field.
    var basin_mask: float = smoothstep(0.62, 0.88, 1.0 - basin_value) # Selects only the deepest broad basin regions.
    var basin_cut: float = basin_mask * BASIN_DEPTH # Lowers selected shelf regions into enormous bowls and lowlands.
    var base_height: float = tier_height + plateau_relief - basin_cut # Combines the continental shelf, local plateau relief, and broad basins.
    var regional_water_height: float = tier_height + plateau_relief * TerrainConfiguration.WATER_REGIONAL_PLATEAU_INFLUENCE - basin_cut * TerrainConfiguration.WATER_REGIONAL_BASIN_INFLUENCE # Reconstructs the same broad local height used to select rendered water bands.
    var local_water_level: float = _get_local_water_level(regional_water_height) # Selects the exact tiered water elevation whose shoreline will shape nearby terrain.
    var mountain_province_value: float = _sample_normalized(_mountain_province_noise, sample_x, sample_z) # Reads the mountain-province placement field.
    var mountain_province_mask: float = smoothstep(0.44, 0.72, mountain_province_value) # Restricts mountains to large coherent provinces.
    var mountain_mass_value: float = _sample_normalized(_mountain_mass_noise, sample_x, sample_z) # Reads the broad internal mountain mass field.
    var mountain_mass_mask: float = smoothstep(0.30, 0.78, mountain_mass_value) # Widens the complete mountain body before any ridge relief is allowed above it.
    var primary_ridge_value: float = _sample_normalized(_mountain_ridge_noise, sample_x, sample_z) # Reads the primary ridged mountain field.
    var broad_primary_ridge: float = _sample_broad_ridge_support(sample_x, sample_z, primary_ridge_value) # Measures whether the ridge remains elevated across a kilometre-scale surrounding area.
    var unsupported_ridge_excess: float = maxf(primary_ridge_value - broad_primary_ridge, 0.0) # Detects narrow centre-line protrusions above the broad ridge body.
    var ridge_width_weight: float = 1.0 - smoothstep(MOUNTAIN_WIDTH_EXCESS_START, MOUNTAIN_WIDTH_EXCESS_END, unsupported_ridge_excess) # Removes relief progressively as a ridge becomes too thin.
    var supported_primary_ridge: float = lerpf(broad_primary_ridge, primary_ridge_value, ridge_width_weight) # Preserves broad ridges while replacing thin peaks with their surrounding support level.
    var broad_ridge_support: float = smoothstep(MOUNTAIN_WIDTH_SUPPORT_START, MOUNTAIN_WIDTH_SUPPORT_END, broad_primary_ridge) # Requires a substantial surrounding ridge field before granting full mountain height.
    var secondary_ridge_value: float = _sample_normalized(_mountain_detail_noise, sample_x, sample_z) # Reads the secondary ridged mountain field.
    var rounded_primary_ridge: float = sin(supported_primary_ridge * PI * 0.5) # Gives width-supported primary ridges a zero-slope rounded crest.
    var rounded_secondary_ridge: float = sin(secondary_ridge_value * PI * 0.5) # Rounds secondary ridge maxima before they influence height.
    var primary_ridge_shape: float = pow(rounded_primary_ridge, 1.48) * broad_ridge_support # Allows extreme primary relief only where the ridge has kilometre-scale width.
    var secondary_width_support: float = lerpf(0.25, 1.0, broad_ridge_support) * ridge_width_weight # Prevents secondary shoulders from rebuilding narrow protrusions beside a suppressed primary ridge.
    var secondary_ridge_shape: float = pow(rounded_secondary_ridge, 2.05) * secondary_width_support # Restricts secondary relief to supported mountain shoulders and side ridges.
    var summit_detail_weight: float = 1.0 - smoothstep(SUMMIT_DETAIL_FADE_START, SUMMIT_DETAIL_FADE_END, rounded_primary_ridge) # Removes secondary detail near primary summits.
    var elevation_mountain_scale: float = lerpf(0.86, 1.24, macro_elevation) # Makes mountain provinces even larger on upper world tiers.
    var mountain_base: float = mountain_province_mask * mountain_mass_mask * MOUNTAIN_BASE_HEIGHT # Raises the complete broad mountain province.
    var mountain_ridge: float = mountain_province_mask * mountain_mass_mask * primary_ridge_shape * MOUNTAIN_RIDGE_HEIGHT # Adds primary relief only where broad width support exists.
    var mountain_shoulders: float = mountain_province_mask * mountain_mass_mask * secondary_ridge_shape * MOUNTAIN_SHOULDER_HEIGHT * summit_detail_weight # Adds supported side ridges without thin protrusions or summit spikes.
    var mountain_height: float = (mountain_base + mountain_ridge + mountain_shoulders) * elevation_mountain_scale # Combines every mountain layer at the regional scale.
    var mountain_terrace_value: float = _sample_normalized(_mountain_terrace_noise, sample_x, sample_z) # Reads the alpine shelf-control field.
    var mountain_terrace_step: float = MOUNTAIN_TERRACE_MINIMUM_STEP + mountain_terrace_value * MOUNTAIN_TERRACE_STEP_RANGE # Varies giant shelf spacing across ranges.
    var terraced_mountain_height: float = snappedf(mountain_height, mountain_terrace_step) # Produces broad alpine height bands before blending.
    var mountain_terrace_strength: float = mountain_province_mask * mountain_mass_mask * lerpf(0.08, 0.20, mountain_terrace_value) # Keeps shelves visible without forming vertical walls.
    mountain_height = lerpf(mountain_height, terraced_mountain_height, mountain_terrace_strength) # Blends giant shelves into the continuous mountain mass.
    var uncarved_height: float = base_height + mountain_height # Resolves the complete tiered and mountainous world before valley erosion.
    var valley_width_value: float = _sample_normalized(_valley_width_noise, sample_x, sample_z) # Reads slowly changing valley-width control.
    var primary_valley_width: float = lerpf(0.14, 0.30, valley_width_value) # Makes major valleys vary from broad corridors to immense basins.
    var secondary_valley_width: float = lerpf(0.07, 0.16, 1.0 - valley_width_value) # Gives tributaries a complementary changing width.
    var primary_valley_line: float = _get_valley_line(_primary_valley_noise.get_noise_2d(sample_x, sample_z), primary_valley_width) # Finds positions near the major winding valley network.
    var secondary_valley_line: float = _get_valley_line(_secondary_valley_noise.get_noise_2d(sample_x, sample_z), secondary_valley_width) # Finds positions near branching tributary valleys.
    var primary_valley_shape: float = pow(primary_valley_line, 1.35) # Keeps major valley floors and walls broad over long distances.
    var secondary_valley_shape: float = pow(secondary_valley_line, 1.75) # Keeps tributaries narrower while still traversable.
    var primary_valley_depth: float = PRIMARY_VALLEY_BASE_DEPTH + macro_elevation * PRIMARY_VALLEY_TIER_DEPTH + mountain_province_mask * PRIMARY_VALLEY_MOUNTAIN_DEPTH # Deepens major valleys on high shelves and through ranges.
    var primary_valley_floor: float = maxf(LOWEST_VALLEY_FLOOR, tier_height * 0.10 - 240.0 + plateau_relief * 0.10) # Gives each major valley a broad floor tied loosely to its regional tier.
    var primary_carved_height: float = maxf(primary_valley_floor, uncarved_height - primary_valley_depth) # Calculates the deepest permitted major-valley surface.
    var height_after_primary_valley: float = lerpf(uncarved_height, primary_carved_height, primary_valley_shape) # Blends smoothly from plateau or mountain wall into the major valley floor.
    var secondary_valley_weight: float = secondary_valley_shape * (1.0 - primary_valley_shape * 0.65) # Prevents tributaries from stacking extreme cuts at major valley centres.
    var secondary_valley_depth: float = SECONDARY_VALLEY_BASE_DEPTH + macro_elevation * SECONDARY_VALLEY_TIER_DEPTH + mountain_province_mask * SECONDARY_VALLEY_MOUNTAIN_DEPTH # Deepens tributaries according to surrounding terrain scale.
    var secondary_valley_floor: float = maxf(LOWEST_VALLEY_FLOOR - 80.0, tier_height * 0.16 - 190.0 + plateau_relief * 0.08) # Keeps tributary floors below their shelf without uncontrolled pits.
    var secondary_carved_height: float = maxf(secondary_valley_floor, height_after_primary_valley - secondary_valley_depth) # Calculates the tributary target surface.
    var valley_height: float = lerpf(height_after_primary_valley, secondary_carved_height, secondary_valley_weight) # Blends tributaries into plateaus, mountains, and major valleys.
    var valley_suppression: float = clampf(maxf(primary_valley_shape, secondary_valley_shape) * 0.82, 0.0, 1.0) # Suppresses noisy detail on broad valley floors.
    var surface_detail: float = _surface_detail_noise.get_noise_2d(sample_x, sample_z) * SURFACE_DETAIL_HEIGHT * (1.0 - valley_suppression) # Adds restrained local terrain relief away from smooth valley floors.
    var full_height: float = valley_height + surface_detail # Resolves the complete monumental terrain hierarchy before shoreline grading.
    var shoreline_profile: float = _sample_normalized(_shoreline_profile_noise, sample_x, sample_z) # Reads slow regional variation in beach and underwater-shelf breadth.
    full_height = _shape_height_around_water(full_height, local_water_level, shoreline_profile) # Compresses near-water relief into broad shallow approaches while preserving distant terrain.
    var spawn_distance: float = Vector2(world_x, world_z).length() # Measures distance from the world-origin spawn centre.
    var spawn_blend: float = smoothstep(SPAWN_INNER_RADIUS, SPAWN_OUTER_RADIUS, spawn_distance) # Introduces monumental terrain gradually outside the safe start.
    var spawn_height: float = plateau_relief * 0.10 + surface_detail * 0.18 # Keeps the initial region gently varied without macro cliffs or mountains.
    var procedural_height: float = lerpf(spawn_height, full_height, spawn_blend) # Blends the readable start into the complete tiered world.
    var flat_blend: float = smoothstep(SPAWN_FLAT_RADIUS, SPAWN_FLAT_BLEND_RADIUS, spawn_distance) # Keeps the inner spawn circle exactly level.
    return lerpf(SPAWN_FLAT_HEIGHT, procedural_height, flat_blend) # Returns the final deterministic world height.

func _sample_broad_ridge_support(sample_x: float, sample_z: float, centre_ridge: float) -> float: # Measures ridge elevation around the current point so narrow protrusions cannot receive full height.
    var east_ridge: float = _sample_normalized(_mountain_ridge_noise, sample_x + MOUNTAIN_WIDTH_SAMPLE_DISTANCE, sample_z) # Samples ridge support to the east.
    var west_ridge: float = _sample_normalized(_mountain_ridge_noise, sample_x - MOUNTAIN_WIDTH_SAMPLE_DISTANCE, sample_z) # Samples ridge support to the west.
    var north_ridge: float = _sample_normalized(_mountain_ridge_noise, sample_x, sample_z - MOUNTAIN_WIDTH_SAMPLE_DISTANCE) # Samples ridge support to the north.
    var south_ridge: float = _sample_normalized(_mountain_ridge_noise, sample_x, sample_z + MOUNTAIN_WIDTH_SAMPLE_DISTANCE) # Samples ridge support to the south.
    var surrounding_average: float = (east_ridge + west_ridge + north_ridge + south_ridge) * 0.25 # Measures the broad ridge body independently of one centre-line maximum.
    return centre_ridge * 0.20 + surrounding_average * 0.80 # Lets surrounding width dominate while retaining a restrained contribution from the centre.

func _get_local_water_level(regional_height: float) -> float: # Selects the same flat tiered water elevation used by the water mesh generator.
    var water_coordinate: float = (regional_height - TerrainConfiguration.WATER_LEVEL_CLEARANCE - TerrainConfiguration.WATER_LEVEL_OFFSET) / TIER_HEIGHT # Finds the highest water band safely below the surrounding regional terrain.
    var water_tier_index: int = clampi(floori(water_coordinate), 0, TIER_LEVEL_COUNT - 1) # Restricts the selected band to the six established world tiers.
    return float(water_tier_index) * TIER_HEIGHT + TerrainConfiguration.WATER_LEVEL_OFFSET # Returns the exact shared local water elevation.

func _shape_height_around_water(terrain_height: float, water_level: float, shoreline_profile: float) -> float: # Converts steep near-water contours into shallow dry approaches and underwater shelves.
    var height_delta: float = terrain_height - water_level # Measures signed terrain elevation relative to the local flat water surface.
    if height_delta >= 0.0: # Selects the dry shoreline profile above the waterline.
        var land_band: float = SHORELINE_LAND_BAND_MINIMUM + shoreline_profile * SHORELINE_LAND_BAND_RANGE # Varies the vertical terrain range drawn into the shallow dry approach.
        if height_delta >= land_band: # Detects terrain beyond shoreline influence.
            return terrain_height # Preserves hills, cliffs, plateaus, and mountains outside the beach approach.
        var normalized_land_height: float = clampf(height_delta / land_band, 0.0, 1.0) # Maps the affected dry elevation into a zero-to-one shoreline coordinate.
        var land_profile_power: float = SHORELINE_LAND_PROFILE_MINIMUM + shoreline_profile * SHORELINE_LAND_PROFILE_RANGE # Selects how strongly the immediate shoreline flattens.
        var shaped_land_height: float = _get_shallow_profile(normalized_land_height, land_profile_power) * land_band # Expands low dry contours while matching the original height and slope at the outer edge.
        return water_level + shaped_land_height # Returns the broad shallow dry shoreline elevation.
    var water_depth: float = -height_delta # Converts submerged signed elevation into a positive depth below the surface.
    var underwater_band: float = SHORELINE_UNDERWATER_BAND_MINIMUM + shoreline_profile * SHORELINE_UNDERWATER_BAND_RANGE # Varies how far vertical relief is drawn into the shallow shelf.
    if water_depth >= underwater_band: # Detects terrain below the shelf influence range.
        return terrain_height # Preserves deep lake floors, valley bottoms, and underwater cliffs beyond the near-shore shelf.
    var normalized_water_depth: float = clampf(water_depth / underwater_band, 0.0, 1.0) # Maps the affected depth into a zero-to-one offshore coordinate.
    var underwater_profile_power: float = SHORELINE_UNDERWATER_PROFILE_MINIMUM + shoreline_profile * SHORELINE_UNDERWATER_PROFILE_RANGE # Selects how gradually the underwater shelf descends.
    var shaped_water_depth: float = _get_shallow_profile(normalized_water_depth, underwater_profile_power) * underwater_band # Expands shallow submerged contours while preserving continuity into deep terrain.
    return water_level - shaped_water_depth # Returns the broad shallow underwater shelf elevation.

func _get_shallow_profile(normalized_height: float, profile_power: float) -> float: # Creates a flattened inner profile that rejoins untouched terrain with matching outer slope.
    var powered_height: float = pow(normalized_height, profile_power) # Suppresses vertical change strongly near the waterline.
    return powered_height * (profile_power - (profile_power - 1.0) * normalized_height) # Preserves value and first derivative at the outer edge to avoid a visible grading seam.

func _get_tier_height(macro_elevation: float) -> float: # Converts a normalized macro value into continuous broad elevation shelves.
    var highest_tier_index: float = float(TIER_LEVEL_COUNT - 1) # Converts the number of shelf levels into the highest valid zero-based index.
    var tier_coordinate: float = clampf(macro_elevation, 0.0, 1.0) * highest_tier_index # Maps the macro value across every available shelf.
    var lower_tier_index: float = floor(tier_coordinate) # Selects the broad shelf beneath the current macro coordinate.
    var tier_fraction: float = tier_coordinate - lower_tier_index # Measures progress toward the next shelf.
    var tier_transition: float = smoothstep(TIER_TRANSITION_START, 1.0, tier_fraction) # Keeps most of each region level before a broad continuous climb.
    return (lower_tier_index + tier_transition) * TIER_HEIGHT # Returns a continuous shelf height with no discontinuous steps.

func _get_valley_line(noise_value: float, width: float) -> float: # Converts a signed noise contour into one broad winding valley centre line.
    var distance_from_line: float = absf(noise_value) # Treats the zero contour as the valley centre.
    var inner_width: float = width * 0.24 # Keeps a broad central floor before the valley walls begin.
    return 1.0 - smoothstep(inner_width, width, distance_from_line) # Returns one at the floor centre and zero outside the valley walls.

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
