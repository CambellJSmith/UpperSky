extends RefCounted # Deterministically scatters smooth trees and boulders across streamed terrain chunks.
class_name WorldDecorationSampler # Makes repeatable decoration placement available to the infinite terrain controller.

const TREE_CELL_SIZE: float = 46.0 # Provides bounded tree spacing while still allowing recognisable forest patches.
const BOULDER_CELL_SIZE: float = 62.0 # Keeps large rocks less common and farther apart than trees.
const TREE_JITTER_FRACTION: float = 0.72 # Moves tree candidates within their global cells without allowing neighbouring candidates to collapse together.
const BOULDER_JITTER_FRACTION: float = 0.70 # Moves boulders away from an obvious grid while preserving minimum broad spacing.
const TREE_MAXIMUM_SLOPE_VARIATION: float = 5.0 # Rejects tree positions with excessive height change across the local footprint.
const BOULDER_MAXIMUM_SLOPE_VARIATION: float = 11.0 # Allows boulders on rougher ground than trees.
const SLOPE_SAMPLE_DISTANCE: float = 7.0 # Measures local terrain variation around each candidate.
const TREE_MINIMUM_WATER_CLEARANCE: float = 5.0 # Keeps trunks visibly above shorelines and outside clipped water edges.
const BOULDER_MINIMUM_WATER_CLEARANCE: float = 1.2 # Allows shoreline rocks while preventing visibly submerged placements.
const TREE_MINIMUM_SPACING: float = 13.0 # Prevents neighbouring accepted trees from visually intersecting.
const BOULDER_OBJECT_SPACING: float = 7.5 # Prevents large rocks from intersecting nearby trees or other boulders.
const TREE_ALTITUDE_FADE_START: float = 1450.0 # Begins reducing forest density on high exposed terrain.
const TREE_ALTITUDE_FADE_END: float = 2450.0 # Removes ordinary trees from extreme mountain elevations.
const HASH_MAXIMUM: float = 2147483647.0 # Converts the positive hash range into a zero-to-one value.

var _terrain: InfiniteTerrain # Supplies exact terrain height, rendered water occupancy, and local water levels.
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
    var occupied_positions: Array[Vector2] = [] # Tracks accepted objects so unlike decoration types do not visibly overlap.
    var chunk_origin: Vector2 = Vector2(float(chunk_coordinate.x), float(chunk_coordinate.y)) * TerrainConfiguration.CHUNK_SIZE # Calculates the absolute back-left chunk corner.
    _append_tree_placements(chunk_origin, placements, occupied_positions) # Generates forest candidates first so trunks retain their required spacing.
    _append_boulder_placements(chunk_origin, maxi(boulder_variant_count, 1), placements, occupied_positions) # Adds rounded rocks around the accepted trees.
    return placements # Returns deterministic chunk-local transforms for rendering and collision.

func _append_tree_placements(chunk_origin: Vector2, placements: Array[WorldDecorationPlacement], occupied_positions: Array[Vector2]) -> void: # Generates tree candidates from a globally stable jittered grid.
    var minimum_cell_x: int = floori(chunk_origin.x / TREE_CELL_SIZE) # Finds the first global tree cell touching the chunk.
    var maximum_cell_x: int = floori((chunk_origin.x + TerrainConfiguration.CHUNK_SIZE - 0.001) / TREE_CELL_SIZE) # Finds the final global tree cell touching the chunk.
    var minimum_cell_z: int = floori(chunk_origin.y / TREE_CELL_SIZE) # Finds the first global tree row touching the chunk.
    var maximum_cell_z: int = floori((chunk_origin.y + TerrainConfiguration.CHUNK_SIZE - 0.001) / TREE_CELL_SIZE) # Finds the final global tree row touching the chunk.
    for cell_z: int in range(minimum_cell_z, maximum_cell_z + 1): # Visits every relevant global row.
        for cell_x: int in range(minimum_cell_x, maximum_cell_x + 1): # Visits every relevant global column.
            var candidate: Vector2 = _get_jittered_candidate(cell_x, cell_z, TREE_CELL_SIZE, TREE_JITTER_FRACTION, 11) # Generates one stable position inside the cell.
            if not _is_inside_chunk(candidate, chunk_origin): # Handles jittered candidates belonging to a neighbouring chunk.
                continue # Lets the owning chunk generate the candidate instead.
            if _is_excluded(candidate): # Protects the player spawn and any future authored clear area.
                continue # Leaves the protected area empty.
            var terrain_height: float = _terrain.get_height_at(candidate) # Reads the exact visible ground height.
            var water_level: float = _terrain.get_water_level_at(candidate) # Reads the local deterministic water band.
            if _terrain.has_water_at(candidate) or terrain_height <= water_level + TREE_MINIMUM_WATER_CLEARANCE: # Rejects water, shoreline clipping, and barely dry ground.
                continue # Keeps every trunk visibly rooted on dry land.
            if _sample_slope_variation(candidate, terrain_height) > TREE_MAXIMUM_SLOPE_VARIATION: # Rejects steep local terrain.
                continue # Prevents tilted-looking or floating tree bases.
            var broad_density: float = _sample_normalized(_forest_density_noise, candidate) # Reads the kilometre-scale forest mask.
            var breakup_density: float = _sample_normalized(_forest_breakup_noise, candidate) # Reads local clearing variation.
            var forest_weight: float = smoothstep(0.38, 0.72, broad_density) * lerpf(0.42, 1.0, breakup_density) # Combines broad stands with irregular local density.
            var altitude_weight: float = 1.0 - smoothstep(TREE_ALTITUDE_FADE_START, TREE_ALTITUDE_FADE_END, terrain_height) # Fades ordinary trees from exposed high mountains.
            var acceptance_probability: float = forest_weight * altitude_weight * 0.72 # Limits average per-chunk density while retaining genuine forests.
            if _hash01(cell_x, cell_z, 31) > acceptance_probability: # Applies a stable per-cell probability against the continuous density fields.
                continue # Leaves this candidate as open ground.
            if _is_too_close(candidate, occupied_positions, TREE_MINIMUM_SPACING): # Defensively enforces spacing after terrain and density rejection.
                continue # Prevents intersecting canopies and trunks.
            var width_scale: float = lerpf(0.78, 1.24, _hash01(cell_x, cell_z, 47)) # Varies trunk width and canopy spread.
            var height_scale: float = lerpf(0.82, 1.38, _hash01(cell_x, cell_z, 53)) # Varies complete tree height independently.
            var yaw: float = _hash01(cell_x, cell_z, 59) * TAU # Rotates branch and canopy asymmetry around the trunk.
            var local_position: Vector3 = Vector3(candidate.x - chunk_origin.x, terrain_height, candidate.y - chunk_origin.y) # Converts the absolute candidate into chunk-local scene space.
            var basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3(width_scale, height_scale, width_scale)) # Applies stable rotation and nonuniform size variation.
            placements.append(WorldDecorationPlacement.new(WorldDecorationPlacement.Kind.TREE, 0, Transform3D(basis, local_position))) # Adds one smooth shared-tree instance.
            occupied_positions.append(candidate) # Reserves local spacing for subsequent trees and boulders.

func _append_boulder_placements(chunk_origin: Vector2, variant_count: int, placements: Array[WorldDecorationPlacement], occupied_positions: Array[Vector2]) -> void: # Generates rounded boulder candidates from a second globally stable grid.
    var minimum_cell_x: int = floori(chunk_origin.x / BOULDER_CELL_SIZE) # Finds the first global boulder cell touching the chunk.
    var maximum_cell_x: int = floori((chunk_origin.x + TerrainConfiguration.CHUNK_SIZE - 0.001) / BOULDER_CELL_SIZE) # Finds the final global boulder cell touching the chunk.
    var minimum_cell_z: int = floori(chunk_origin.y / BOULDER_CELL_SIZE) # Finds the first global boulder row touching the chunk.
    var maximum_cell_z: int = floori((chunk_origin.y + TerrainConfiguration.CHUNK_SIZE - 0.001) / BOULDER_CELL_SIZE) # Finds the final global boulder row touching the chunk.
    for cell_z: int in range(minimum_cell_z, maximum_cell_z + 1): # Visits every relevant global row.
        for cell_x: int in range(minimum_cell_x, maximum_cell_x + 1): # Visits every relevant global column.
            var candidate: Vector2 = _get_jittered_candidate(cell_x, cell_z, BOULDER_CELL_SIZE, BOULDER_JITTER_FRACTION, 101) # Generates one stable rock position inside the cell.
            if not _is_inside_chunk(candidate, chunk_origin): # Handles jittered candidates owned by neighbouring chunks.
                continue # Avoids duplicate placements across chunk boundaries.
            if _is_excluded(candidate): # Keeps the protected spawn area unobstructed.
                continue # Leaves the candidate empty.
            var terrain_height: float = _terrain.get_height_at(candidate) # Reads the exact visible ground elevation.
            var water_level: float = _terrain.get_water_level_at(candidate) # Reads the local water band.
            if _terrain.has_water_at(candidate) or terrain_height <= water_level + BOULDER_MINIMUM_WATER_CLEARANCE: # Rejects submerged or barely visible rocks.
                continue # Keeps generated boulders on usable land.
            if _sample_slope_variation(candidate, terrain_height) > BOULDER_MAXIMUM_SLOPE_VARIATION: # Rejects only the roughest local footprints.
                continue # Prevents severely floating rocks on abrupt terrain discontinuities.
            var rocky_density: float = _sample_normalized(_boulder_density_noise, candidate) # Reads the broad rocky-region mask.
            var acceptance_probability: float = smoothstep(0.47, 0.78, rocky_density) * 0.58 + 0.035 # Creates coherent boulder fields with a very sparse background population.
            if _hash01(cell_x, cell_z, 113) > acceptance_probability: # Applies stable per-cell acceptance.
                continue # Leaves most ordinary terrain free of large rocks.
            if _is_too_close(candidate, occupied_positions, BOULDER_OBJECT_SPACING): # Prevents rocks from intersecting trunks or neighbouring boulders.
                continue # Leaves sufficient visible separation.
            var scale_x: float = lerpf(1.25, 3.25, _hash01(cell_x, cell_z, 127)) # Varies the horizontal boulder extent.
            var scale_y: float = lerpf(0.85, 2.25, _hash01(cell_x, cell_z, 131)) # Varies vertical mass independently.
            var scale_z: float = lerpf(1.20, 3.10, _hash01(cell_x, cell_z, 137)) # Creates nonuniform broad silhouettes.
            var yaw: float = _hash01(cell_x, cell_z, 139) * TAU # Rotates the irregular shared mesh around the vertical axis.
            var pitch: float = lerpf(-0.16, 0.16, _hash01(cell_x, cell_z, 149)) # Adds restrained natural settling tilt.
            var roll: float = lerpf(-0.16, 0.16, _hash01(cell_x, cell_z, 151)) # Adds independent tilt along the other horizontal axis.
            var basis: Basis = Basis(Vector3.UP, yaw) # Starts with the primary random world rotation.
            basis = basis.rotated(Vector3.RIGHT, pitch) # Applies restrained forward or backward settling.
            basis = basis.rotated(Vector3.FORWARD, roll) # Applies restrained side settling.
            basis = basis.scaled(Vector3(scale_x, scale_y, scale_z)) # Applies the complete irregular instance size.
            var embedded_height: float = terrain_height + scale_y * 0.48 # Places part of the rounded volume below ground so it appears naturally embedded.
            var local_position: Vector3 = Vector3(candidate.x - chunk_origin.x, embedded_height, candidate.y - chunk_origin.y) # Converts the absolute candidate into chunk-local scene space.
            var variant: int = floori(_hash01(cell_x, cell_z, 157) * float(variant_count)) # Selects one shared smooth boulder silhouette.
            placements.append(WorldDecorationPlacement.new(WorldDecorationPlacement.Kind.BOULDER, mini(variant, variant_count - 1), Transform3D(basis, local_position))) # Adds the rounded boulder placement.
            occupied_positions.append(candidate) # Reserves space around the accepted rock.

func _get_jittered_candidate(cell_x: int, cell_z: int, cell_size: float, jitter_fraction: float, salt: int) -> Vector2: # Produces one stable candidate inside a global scatter cell.
    var centre: Vector2 = Vector2((float(cell_x) + 0.5) * cell_size, (float(cell_z) + 0.5) * cell_size) # Calculates the exact global cell centre.
    var half_jitter: float = cell_size * jitter_fraction * 0.5 # Calculates the maximum offset along either axis.
    var offset_x: float = lerpf(-half_jitter, half_jitter, _hash01(cell_x, cell_z, salt)) # Generates stable x-axis jitter.
    var offset_z: float = lerpf(-half_jitter, half_jitter, _hash01(cell_x, cell_z, salt + 1)) # Generates independent z-axis jitter.
    return centre + Vector2(offset_x, offset_z) # Returns the final absolute world-space candidate.

func _sample_slope_variation(position: Vector2, centre_height: float) -> float: # Measures the maximum local terrain-height difference around one footprint.
    var variation: float = absf(_terrain.get_height_at(position + Vector2(SLOPE_SAMPLE_DISTANCE, 0.0)) - centre_height) # Samples east of the candidate.
    variation = maxf(variation, absf(_terrain.get_height_at(position - Vector2(SLOPE_SAMPLE_DISTANCE, 0.0)) - centre_height)) # Includes the western sample.
    variation = maxf(variation, absf(_terrain.get_height_at(position + Vector2(0.0, SLOPE_SAMPLE_DISTANCE)) - centre_height)) # Includes the southern sample.
    variation = maxf(variation, absf(_terrain.get_height_at(position - Vector2(0.0, SLOPE_SAMPLE_DISTANCE)) - centre_height)) # Includes the northern sample.
    return variation # Returns the steepest measured local height change.

func _is_inside_chunk(position: Vector2, chunk_origin: Vector2) -> bool: # Reports whether one absolute candidate belongs to the active chunk.
    return position.x >= chunk_origin.x and position.x < chunk_origin.x + TerrainConfiguration.CHUNK_SIZE and position.y >= chunk_origin.y and position.y < chunk_origin.y + TerrainConfiguration.CHUNK_SIZE # Uses half-open bounds to prevent duplicates at chunk edges.

func _is_excluded(position: Vector2) -> bool: # Reports whether one candidate falls inside the protected gameplay area.
    if _exclusion_radius <= 0.0: # Detects whether any exclusion has been configured.
        return false # Allows all candidates when no protected area exists.
    return position.distance_squared_to(_exclusion_centre) < _exclusion_radius * _exclusion_radius # Uses squared distance for a stable circular protected area.

func _is_too_close(position: Vector2, occupied_positions: Array[Vector2], minimum_spacing: float) -> bool: # Tests candidate separation against previously accepted objects in this chunk.
    var minimum_spacing_squared: float = minimum_spacing * minimum_spacing # Avoids square roots during repeated spacing checks.
    for occupied_position: Vector2 in occupied_positions: # Visits every previously accepted local decoration.
        if position.distance_squared_to(occupied_position) < minimum_spacing_squared: # Detects an intersecting or overcrowded candidate.
            return true # Rejects the candidate immediately.
    return false # Reports sufficient spacing from every accepted object.

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
