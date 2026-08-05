extends RefCounted # Deterministically scatters dense smooth trees and boulders across streamed terrain chunks.
class_name WorldDecorationSampler # Makes repeatable decoration placement available to the world-decoration streamer.

const TREE_CELL_SIZE: float = 24.0 # Allows roughly four times as many tree candidates per square kilometre as the original scatter grid.
const BOULDER_CELL_SIZE: float = 30.0 # Allows roughly four times as many boulder candidates per square kilometre as the original scatter grid.
const TREE_JITTER_FRACTION: float = 0.54 # Breaks the visible grid while preserving enough guaranteed separation for broad tree canopies.
const BOULDER_JITTER_FRACTION: float = 0.62 # Produces irregular rock fields while retaining useful minimum candidate spacing.
const TREE_MAXIMUM_SLOPE_VARIATION: float = 5.5 # Keeps trees on plausible ground while admitting more gently rolling terrain.
const BOULDER_MAXIMUM_SLOPE_VARIATION: float = 12.0 # Allows rocks on substantially rougher ground than trees.
const SLOPE_SAMPLE_DISTANCE: float = 7.0 # Measures local terrain variation around each candidate footprint.
const TREE_MINIMUM_WATER_CLEARANCE: float = 4.0 # Keeps trunks visibly dry without stripping vegetation from broad shore regions.
const BOULDER_MINIMUM_WATER_CLEARANCE: float = 0.8 # Allows dense shoreline rocks while keeping their centres above the local water plane.
const TREE_MINIMUM_SPACING: float = 8.5 # Prevents the densest accepted trees from visibly intersecting at their trunks.
const BOULDER_OBJECT_SPACING: float = 6.5 # Prevents the largest rocks from occupying the same local footprint as another object.
const TREE_ALTITUDE_FADE_START: float = 1650.0 # Retains dense woodland farther up high terrain than the original distribution.
const TREE_ALTITUDE_FADE_END: float = 2700.0 # Removes ordinary trees only from the highest exposed mountain terrain.
const TREE_BACKGROUND_PROBABILITY: float = 0.18 # Keeps open regions visibly populated instead of restricting trees to rare forest masks.
const TREE_FOREST_PROBABILITY: float = 0.80 # Adds dense stands on top of the background tree population.
const BOULDER_BACKGROUND_PROBABILITY: float = 0.14 # Creates a substantial sparse rock population outside dedicated boulder fields.
const BOULDER_FIELD_PROBABILITY: float = 0.72 # Makes coherent rocky regions dramatically denser.
const OCCUPANCY_CELL_SIZE: float = 8.0 # Spatially indexes accepted placements so overlap checks avoid scanning the complete chunk.
const HASH_MAXIMUM: float = 2147483647.0 # Converts the positive hash range into a zero-to-one value.

var _terrain: InfiniteTerrain # Supplies exact terrain height and local water levels.
var _forest_density_noise: FastNoiseLite # Creates kilometre-scale forest and open-land regions.
var _forest_breakup_noise: FastNoiseLite # Breaks broad forests into natural clearings and denser stands.
var _boulder_density_noise: FastNoiseLite # Creates coherent rocky areas instead of uniform scattering.
var _exclusion_centre: Vector2 = Vector2.ZERO # Stores the current protected spawn or gameplay position.
var _exclusion_radius: float = 0.0 # Stores the radius in which no generated decoration may appear.

func _init(terrain: InfiniteTerrain) -> void: # Connects the sampler to the authoritative streamed world and builds density fields.
    _terrain = terrain # Stores the public terrain and water query service used by gameplay and rendering.
    _forest_density_noise = _create_noise(401, 0.00072, 3, 0.54) # Creates broad forests spanning multiple chunks.
    _forest_breakup_noise = _create_noise(419, 0.0045, 2, 0.48) # Creates local clearings and irregular forest edges.
    _boulder_density_noise = _create_noise(443, 0.00135, 3, 0.52) # Creates broad rocky belts and boulder fields.

func set_exclusion_area(world_position: Vector2, radius: float) -> void: # Protects a deterministic area from generated objects before its chunks are built.
    _exclusion_centre = world_position # Stores the absolute world-space centre.
    _exclusion_radius = maxf(radius, 0.0) # Rejects negative exclusion radii defensively.

func sample_chunk(chunk_coordinate: Vector2i, boulder_variant_count: int) -> Array[WorldDecorationPlacement]: # Generates every accepted smooth decoration placement for one chunk.
    var placements: Array[WorldDecorationPlacement] = [] # Stores the complete deterministic result in stable generation order.
    var occupied_cells: Dictionary = {} # Spatially indexes accepted objects so dense overlap tests remain close to constant time.
    var chunk_origin: Vector2 = Vector2(float(chunk_coordinate.x), float(chunk_coordinate.y)) * TerrainConfiguration.CHUNK_SIZE # Calculates the absolute back-left chunk corner.
    _append_tree_placements(chunk_origin, placements, occupied_cells) # Generates forest candidates first so trunks retain their required spacing.
    _append_boulder_placements(chunk_origin, maxi(boulder_variant_count, 1), placements, occupied_cells) # Adds rounded rocks around the accepted trees.
    return placements # Returns deterministic chunk-local transforms for rendering and collision.

func _append_tree_placements(chunk_origin: Vector2, placements: Array[WorldDecorationPlacement], occupied_cells: Dictionary) -> void: # Generates dense tree candidates from a globally stable jittered grid.
    var minimum_cell_x: int = floori(chunk_origin.x / TREE_CELL_SIZE) # Finds the first global tree cell touching the chunk.
    var maximum_cell_x: int = floori((chunk_origin.x + TerrainConfiguration.CHUNK_SIZE - 0.001) / TREE_CELL_SIZE) # Finds the final global tree cell touching the chunk.
    var minimum_cell_z: int = floori(chunk_origin.y / TREE_CELL_SIZE) # Finds the first global tree row touching the chunk.
    var maximum_cell_z: int = floori((chunk_origin.y + TerrainConfiguration.CHUNK_SIZE - 0.001) / TREE_CELL_SIZE) # Finds the final global tree row touching the chunk.
    for cell_z: int in range(minimum_cell_z, maximum_cell_z + 1): # Visits every relevant global row.
        for cell_x: int in range(minimum_cell_x, maximum_cell_x + 1): # Visits every relevant global column.
            var candidate: Vector2 = _get_jittered_candidate(cell_x, cell_z, TREE_CELL_SIZE, TREE_JITTER_FRACTION, 11) # Generates one stable position inside the cell.
            if not _is_inside_chunk(candidate, chunk_origin) or _is_excluded(candidate): # Rejects neighbouring ownership and the protected spawn clearing before expensive world sampling.
                continue # Leaves this candidate to its owning chunk or the protected clear area.
            var broad_density: float = _sample_normalized(_forest_density_noise, candidate) # Reads the kilometre-scale forest mask.
            var breakup_density: float = _sample_normalized(_forest_breakup_noise, candidate) # Reads local clearing variation.
            var forest_weight: float = smoothstep(0.28, 0.70, broad_density) * lerpf(0.58, 1.0, breakup_density) # Produces broad dense stands while retaining irregular clearings.
            var acceptance_probability: float = TREE_BACKGROUND_PROBABILITY + forest_weight * TREE_FOREST_PROBABILITY # Keeps background woodland and strongly fills forest regions.
            var acceptance_roll: float = _hash01(cell_x, cell_z, 31) # Reuses one stable probability before and after altitude weighting.
            if acceptance_roll > acceptance_probability: # Rejects most candidates before terrain and water sampling.
                continue # Saves several procedural height samples for objects that will never be shown.
            var terrain_height: float = _terrain.get_height_at(candidate) # Reads the exact visible ground height only for density-approved candidates.
            var altitude_weight: float = 1.0 - smoothstep(TREE_ALTITUDE_FADE_START, TREE_ALTITUDE_FADE_END, terrain_height) # Fades ordinary trees from exposed high mountains.
            if acceptance_roll > acceptance_probability * altitude_weight: # Applies altitude reduction without introducing a second random decision.
                continue # Leaves extreme high terrain progressively clearer.
            var water_level: float = _terrain.get_water_level_at(candidate) # Reads the deterministic local water band.
            if terrain_height <= water_level + TREE_MINIMUM_WATER_CLEARANCE: # Uses a conservative height clearance instead of the more expensive rendered-water interpolation query.
                continue # Keeps every trunk visibly rooted on dry land.
            if _sample_slope_variation(candidate, terrain_height) > TREE_MAXIMUM_SLOPE_VARIATION: # Rejects steep local terrain using two diagonal samples rather than four cardinal samples.
                continue # Prevents tilted-looking or floating tree bases.
            if _is_too_close(candidate, occupied_cells, TREE_MINIMUM_SPACING): # Enforces local separation through the spatial occupancy index.
                continue # Prevents intersecting trunks and the most obvious canopy overlap.
            var width_scale: float = lerpf(0.72, 1.20, _hash01(cell_x, cell_z, 47)) # Varies trunk width and canopy spread while permitting more compact dense trees.
            var height_scale: float = lerpf(0.76, 1.34, _hash01(cell_x, cell_z, 53)) # Varies complete tree height independently.
            var yaw: float = _hash01(cell_x, cell_z, 59) * TAU # Rotates branch and canopy asymmetry around the trunk.
            var local_position: Vector3 = Vector3(candidate.x - chunk_origin.x, terrain_height, candidate.y - chunk_origin.y) # Converts the absolute candidate into chunk-local scene space.
            var basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3(width_scale, height_scale, width_scale)) # Applies stable rotation and nonuniform size variation.
            placements.append(WorldDecorationPlacement.new(WorldDecorationPlacement.Kind.TREE, 0, Transform3D(basis, local_position))) # Adds one smooth shared-tree instance.
            _reserve_position(candidate, occupied_cells) # Adds the accepted tree to the local spatial index.

func _append_boulder_placements(chunk_origin: Vector2, variant_count: int, placements: Array[WorldDecorationPlacement], occupied_cells: Dictionary) -> void: # Generates dense rounded boulder candidates from a second globally stable grid.
    var minimum_cell_x: int = floori(chunk_origin.x / BOULDER_CELL_SIZE) # Finds the first global boulder cell touching the chunk.
    var maximum_cell_x: int = floori((chunk_origin.x + TerrainConfiguration.CHUNK_SIZE - 0.001) / BOULDER_CELL_SIZE) # Finds the final global boulder cell touching the chunk.
    var minimum_cell_z: int = floori(chunk_origin.y / BOULDER_CELL_SIZE) # Finds the first global boulder row touching the chunk.
    var maximum_cell_z: int = floori((chunk_origin.y + TerrainConfiguration.CHUNK_SIZE - 0.001) / BOULDER_CELL_SIZE) # Finds the final global boulder row touching the chunk.
    for cell_z: int in range(minimum_cell_z, maximum_cell_z + 1): # Visits every relevant global row.
        for cell_x: int in range(minimum_cell_x, maximum_cell_x + 1): # Visits every relevant global column.
            var candidate: Vector2 = _get_jittered_candidate(cell_x, cell_z, BOULDER_CELL_SIZE, BOULDER_JITTER_FRACTION, 101) # Generates one stable rock position inside the cell.
            if not _is_inside_chunk(candidate, chunk_origin) or _is_excluded(candidate): # Rejects neighbouring ownership and the protected spawn clearing before expensive sampling.
                continue # Leaves the candidate empty or owned by its correct chunk.
            var rocky_density: float = _sample_normalized(_boulder_density_noise, candidate) # Reads the broad rocky-region mask.
            var field_weight: float = smoothstep(0.34, 0.74, rocky_density) # Expands coherent boulder fields substantially.
            var acceptance_probability: float = BOULDER_BACKGROUND_PROBABILITY + field_weight * BOULDER_FIELD_PROBABILITY # Combines dense rocky belts with a visible background population.
            if _hash01(cell_x, cell_z, 113) > acceptance_probability: # Rejects candidates before terrain and water work.
                continue # Saves procedural sampling for rocks that will not be rendered.
            var terrain_height: float = _terrain.get_height_at(candidate) # Reads the exact visible ground elevation.
            var water_level: float = _terrain.get_water_level_at(candidate) # Reads the local water band.
            if terrain_height <= water_level + BOULDER_MINIMUM_WATER_CLEARANCE: # Uses conservative clearance instead of the more expensive rendered-water interpolation query.
                continue # Keeps generated boulders on visible land.
            if _sample_slope_variation(candidate, terrain_height) > BOULDER_MAXIMUM_SLOPE_VARIATION: # Rejects only the roughest local footprints.
                continue # Prevents severely floating rocks on abrupt terrain discontinuities.
            if _is_too_close(candidate, occupied_cells, BOULDER_OBJECT_SPACING): # Prevents rocks from intersecting trunks or neighbouring boulders.
                continue # Leaves sufficient visible separation.
            var scale_x: float = lerpf(0.95, 2.85, _hash01(cell_x, cell_z, 127)) # Includes smaller common rocks as well as substantial boulders.
            var scale_y: float = lerpf(0.70, 2.05, _hash01(cell_x, cell_z, 131)) # Varies vertical mass independently.
            var scale_z: float = lerpf(0.90, 2.70, _hash01(cell_x, cell_z, 137)) # Creates nonuniform broad silhouettes.
            var yaw: float = _hash01(cell_x, cell_z, 139) * TAU # Rotates the irregular shared mesh around the vertical axis.
            var pitch: float = lerpf(-0.16, 0.16, _hash01(cell_x, cell_z, 149)) # Adds restrained natural settling tilt.
            var roll: float = lerpf(-0.16, 0.16, _hash01(cell_x, cell_z, 151)) # Adds independent tilt along the other horizontal axis.
            var basis: Basis = Basis(Vector3.UP, yaw) # Starts with the primary random world rotation.
            basis = basis.rotated(Vector3.RIGHT, pitch) # Applies restrained forward or backward settling.
            basis = basis.rotated(Vector3.FORWARD, roll) # Applies restrained side settling.
            basis = basis.scaled(Vector3(scale_x, scale_y, scale_z)) # Applies the complete irregular instance size.
            var embedded_height: float = terrain_height + scale_y * 0.44 # Places part of the rounded volume below ground so it appears naturally embedded.
            var local_position: Vector3 = Vector3(candidate.x - chunk_origin.x, embedded_height, candidate.y - chunk_origin.y) # Converts the absolute candidate into chunk-local scene space.
            var variant: int = floori(_hash01(cell_x, cell_z, 157) * float(variant_count)) # Selects one shared smooth boulder silhouette.
            placements.append(WorldDecorationPlacement.new(WorldDecorationPlacement.Kind.BOULDER, mini(variant, variant_count - 1), Transform3D(basis, local_position))) # Adds the rounded boulder placement.
            _reserve_position(candidate, occupied_cells) # Adds the accepted rock to the local spatial index.

func _get_jittered_candidate(cell_x: int, cell_z: int, cell_size: float, jitter_fraction: float, salt: int) -> Vector2: # Produces one stable candidate inside a global scatter cell.
    var centre: Vector2 = Vector2((float(cell_x) + 0.5) * cell_size, (float(cell_z) + 0.5) * cell_size) # Calculates the exact global cell centre.
    var half_jitter: float = cell_size * jitter_fraction * 0.5 # Calculates the maximum offset along either axis.
    var offset_x: float = lerpf(-half_jitter, half_jitter, _hash01(cell_x, cell_z, salt)) # Generates stable x-axis jitter.
    var offset_z: float = lerpf(-half_jitter, half_jitter, _hash01(cell_x, cell_z, salt + 1)) # Generates independent z-axis jitter.
    return centre + Vector2(offset_x, offset_z) # Returns the final absolute world-space candidate.

func _sample_slope_variation(position: Vector2, centre_height: float) -> float: # Measures local terrain variation with two diagonal samples to halve height-query cost.
    var diagonal_offset: Vector2 = Vector2(SLOPE_SAMPLE_DISTANCE, SLOPE_SAMPLE_DISTANCE) # Covers both horizontal axes with one sample direction.
    var variation: float = absf(_terrain.get_height_at(position + diagonal_offset) - centre_height) # Samples the north-east edge of the footprint.
    variation = maxf(variation, absf(_terrain.get_height_at(position - diagonal_offset) - centre_height)) # Includes the opposing south-west edge.
    return variation # Returns the steepest measured diagonal height change.

func _is_inside_chunk(position: Vector2, chunk_origin: Vector2) -> bool: # Reports whether one absolute candidate belongs to the active chunk.
    return position.x >= chunk_origin.x and position.x < chunk_origin.x + TerrainConfiguration.CHUNK_SIZE and position.y >= chunk_origin.y and position.y < chunk_origin.y + TerrainConfiguration.CHUNK_SIZE # Uses half-open bounds to prevent duplicates at chunk edges.

func _is_excluded(position: Vector2) -> bool: # Reports whether one candidate falls inside the protected gameplay area.
    if _exclusion_radius <= 0.0: # Detects whether any exclusion has been configured.
        return false # Allows all candidates when no protected area exists.
    return position.distance_squared_to(_exclusion_centre) < _exclusion_radius * _exclusion_radius # Uses squared distance for a stable circular protected area.

func _is_too_close(position: Vector2, occupied_cells: Dictionary, minimum_spacing: float) -> bool: # Tests nearby spatial buckets rather than scanning every accepted object in the chunk.
    var centre_cell: Vector2i = _get_occupancy_cell(position) # Finds the spatial bucket containing the candidate.
    var search_radius: int = ceili(minimum_spacing / OCCUPANCY_CELL_SIZE) # Calculates how many neighbouring buckets can contain an overlapping object.
    var minimum_spacing_squared: float = minimum_spacing * minimum_spacing # Avoids square roots during repeated distance checks.
    for offset_z: int in range(-search_radius, search_radius + 1): # Visits every potentially overlapping bucket row.
        for offset_x: int in range(-search_radius, search_radius + 1): # Visits every potentially overlapping bucket column.
            var cell: Vector2i = centre_cell + Vector2i(offset_x, offset_z) # Calculates one neighbouring bucket coordinate.
            if not occupied_cells.has(cell): # Detects an empty bucket.
                continue # Skips allocation and iteration for empty space.
            var positions: Array = occupied_cells[cell] # Retrieves the small list of accepted positions in this bucket.
            for stored_position_value: Variant in positions: # Visits every accepted object in the bucket.
                var stored_position: Vector2 = stored_position_value # Converts the variant back into the stored horizontal position.
                if position.distance_squared_to(stored_position) < minimum_spacing_squared: # Detects an intersecting or overcrowded candidate.
                    return true # Rejects the candidate immediately.
    return false # Reports sufficient spacing from every nearby accepted object.

func _reserve_position(position: Vector2, occupied_cells: Dictionary) -> void: # Adds one accepted object to the spatial occupancy index.
    var cell: Vector2i = _get_occupancy_cell(position) # Finds the bucket that owns the accepted position.
    if not occupied_cells.has(cell): # Detects the first accepted object in this bucket.
        occupied_cells[cell] = [] # Creates the bucket's compact position list.
    var positions: Array = occupied_cells[cell] # Retrieves the mutable list stored for this bucket.
    positions.append(position) # Adds the accepted position for future overlap tests.
    occupied_cells[cell] = positions # Stores the updated list explicitly for predictable dictionary mutation.

func _get_occupancy_cell(position: Vector2) -> Vector2i: # Converts an absolute position into the dense-placement spatial index.
    return Vector2i(floori(position.x / OCCUPANCY_CELL_SIZE), floori(position.y / OCCUPANCY_CELL_SIZE)) # Uses floor division so negative world coordinates remain stable.

func _sample_normalized(noise: FastNoiseLite, position: Vector2) -> float: # Converts a signed density sample into a defensive zero-to-one range.
    return clampf((noise.get_noise_2d(position.x, position.y) + 1.0) * 0.5, 0.0, 1.0) # Normalizes and clamps the coherent field.

func _hash01(x: int, z: int, salt: int) -> float: # Produces one stable zero-to-one value from integer world-cell coordinates.
    var value: int = x * 374761393 + z * 668265263 + salt * 982451653 + TerrainHeightSampler.WORLD_SEED * 31 # Mixes coordinates, purpose salt, and the established world seed.
    value = (value ^ (value >> 13)) & 0x7fffffff # Applies the first xor shift and constrains the intermediate range.
    value = (value * 1274126177) & 0x7fffffff # Applies avalanche multiplication without overflowing signed 64-bit range.
    value = value ^ (value >> 16) # Applies a final xor shift to distribute nearby coordinates.
    return float(value & 0x7fffffff) / HASH_MAXIMUM # Converts the positive 31-bit result into a stable probability.

func _create_noise(seed_offset: int, frequency: float, octaves: int, gain: float) -> FastNoiseLite: # Creates one deterministic decoration-density field.
    var noise: FastNoiseLite = FastNoiseLite.new() # Allocates an independent coherent noise source.
    noise.seed = TerrainHeightSampler.WORLD_SEED + seed_offset # Derives the field from the established world seed without changing terrain.
    noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH # Uses rounded coherent regions appropriate for forests and rock fields.
    noise.frequency = frequency # Sets the real-world scale of density variation.
    noise.fractal_type = FastNoiseLite.FRACTAL_FBM # Combines multiple smooth scales without ridged artefacts.
    noise.fractal_octaves = octaves # Sets the number of accumulated density layers.
    noise.fractal_gain = gain # Controls the contribution of finer layers.
    noise.fractal_lacunarity = 2.0 # Doubles frequency at each finer layer.
    return noise # Returns the configured repeatable field.
