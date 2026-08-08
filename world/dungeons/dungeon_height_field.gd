extends RefCounted # Stores the two deterministic vertex height maps that define the complete dungeon floor and ceiling surfaces.
class_name DungeonHeightField # Exposes shared floor/ceiling samples so rendering, collision, doors, and spawn grounding all use the same geometry source.

const FLOOR_BASE_HEIGHT: float = 0.0 # Keeps the generated floor centred around the established dungeon-local threshold elevation.
const FLOOR_VARIATION: float = 0.48 # Adds restrained vertical floor relief while remaining comfortably below the player's maximum walkable slope.
const CEILING_BASE_HEIGHT: float = 4.15 # Raises the average ceiling slightly above the previous flat interior height for clearer irregular cavern-like volume.
const CEILING_VARIATION: float = 0.62 # Gives the independent ceiling map enough variation to produce visibly different overhead profiles.
const MINIMUM_HEADROOM: float = 3.25 # Guarantees sufficient vertical clearance between every paired floor and ceiling vertex for the player capsule.
const ENDPOINT_FLATTEN_RADIUS: float = 1.65 # Flattens both height maps around paired endpoint cells so doors always meet predictable local surfaces.
const FLOOR_NOISE_FREQUENCY: float = 0.21 # Controls broad floor undulation across the relatively small dungeon vertex grid.
const CEILING_NOISE_FREQUENCY: float = 0.17 # Uses a different overhead frequency so ceiling relief does not simply mirror the floor.
const NOISE_OCTAVES: int = 3 # Adds a small number of deterministic fractal layers without creating noisy high-frequency walk surfaces.

var vertex_width: int = 0 # Stores the number of shared height samples along dungeon-local x, which is one greater than logical cell width.
var vertex_depth: int = 0 # Stores the number of shared height samples along dungeon-local z, which is one greater than logical cell depth.
var _floor_heights: PackedFloat32Array = PackedFloat32Array() # Stores row-major floor heights for every shared grid vertex.
var _ceiling_heights: PackedFloat32Array = PackedFloat32Array() # Stores row-major ceiling heights paired one-to-one with the floor samples.
var _layout_width: int = 0 # Retains logical cell width for converting centred local coordinates back into height-map coordinates.
var _layout_depth: int = 0 # Retains logical cell depth for converting centred local coordinates back into height-map coordinates.

func generate(layout: DungeonLayout, dungeon_seed: int) -> void: # Builds both deterministic height maps from the same logical topology and immutable dungeon seed.
    if layout == null: # Rejects missing topology before allocating height-map storage.
        _clear() # Returns the data object to a valid empty state.
        return # Stops generation because no dimensions or endpoints can be resolved safely.
    _layout_width = layout.width # Retains logical width for centred coordinate conversion and later bilinear sampling.
    _layout_depth = layout.height # Retains logical depth for centred coordinate conversion and later bilinear sampling.
    vertex_width = _layout_width + 1 # Creates one shared vertex on both sides of every logical x cell boundary.
    vertex_depth = _layout_depth + 1 # Creates one shared vertex on both sides of every logical z cell boundary.
    _floor_heights.resize(vertex_width * vertex_depth) # Allocates exactly one floor sample per shared vertex.
    _ceiling_heights.resize(vertex_width * vertex_depth) # Allocates the matching ceiling map with identical dimensions.
    var floor_noise: FastNoiseLite = _create_noise(dungeon_seed + 18_431, FLOOR_NOISE_FREQUENCY) # Creates an isolated deterministic fractal source for floor relief.
    var ceiling_noise: FastNoiseLite = _create_noise(dungeon_seed + 71_903, CEILING_NOISE_FREQUENCY) # Creates an independently seeded overhead source so the two maps are not parallel copies.
    for vertex_z: int in range(vertex_depth): # Visits every row of the shared height-map grid exactly once.
        for vertex_x: int in range(vertex_width): # Visits every sample in the current row exactly once.
            var floor_unit: float = floor_noise.get_noise_2d(float(vertex_x), float(vertex_z)) # Samples smooth deterministic floor relief at this shared grid vertex.
            var ceiling_unit: float = ceiling_noise.get_noise_2d(float(vertex_x), float(vertex_z)) # Samples independent smooth deterministic ceiling relief at the same horizontal coordinate.
            var floor_height: float = FLOOR_BASE_HEIGHT + floor_unit * FLOOR_VARIATION # Converts normalized floor noise into a conservative physical elevation range.
            var ceiling_height: float = CEILING_BASE_HEIGHT + ceiling_unit * CEILING_VARIATION # Converts overhead noise into an independent physical ceiling elevation.
            var endpoint_weight: float = _get_endpoint_flatten_weight(layout, vertex_x, vertex_z) # Measures whether this vertex belongs near either paired entrance landing zone.
            floor_height = lerpf(floor_height, FLOOR_BASE_HEIGHT, endpoint_weight) # Blends endpoint-adjacent floor samples toward the stable threshold plane.
            ceiling_height = lerpf(ceiling_height, CEILING_BASE_HEIGHT, endpoint_weight) # Blends endpoint-adjacent ceiling samples toward predictable doorway headroom.
            ceiling_height = maxf(ceiling_height, floor_height + MINIMUM_HEADROOM) # Enforces minimum headroom even when independent maps would otherwise approach too closely.
            var data_index: int = _get_index(vertex_x, vertex_z) # Converts the validated two-dimensional sample coordinate into row-major storage.
            _floor_heights[data_index] = floor_height # Stores the final floor value used by rendering, collision, and player grounding.
            _ceiling_heights[data_index] = ceiling_height # Stores the paired ceiling value used by rendering and overhead collision.

func get_floor_height(vertex_x: int, vertex_z: int) -> float: # Returns one exact floor-map vertex height with defensive coordinate clamping.
    if vertex_width <= 0 or vertex_depth <= 0: # Detects access before successful generation.
        return FLOOR_BASE_HEIGHT # Returns the stable floor baseline instead of indexing empty storage.
    var safe_x: int = clampi(vertex_x, 0, vertex_width - 1) # Keeps horizontal sample access within the allocated map width.
    var safe_z: int = clampi(vertex_z, 0, vertex_depth - 1) # Keeps depth sample access within the allocated map depth.
    return _floor_heights[_get_index(safe_x, safe_z)] # Returns the exact shared floor vertex consumed by procedural mesh construction.

func get_ceiling_height(vertex_x: int, vertex_z: int) -> float: # Returns one exact ceiling-map vertex height with defensive coordinate clamping.
    if vertex_width <= 0 or vertex_depth <= 0: # Detects access before successful generation.
        return CEILING_BASE_HEIGHT # Returns stable default headroom rather than indexing empty storage.
    var safe_x: int = clampi(vertex_x, 0, vertex_width - 1) # Restricts horizontal access to valid shared vertices.
    var safe_z: int = clampi(vertex_z, 0, vertex_depth - 1) # Restricts depth access to valid shared vertices.
    return _ceiling_heights[_get_index(safe_x, safe_z)] # Returns the exact paired overhead sample used by mesh construction.

func sample_floor(local_x: float, local_z: float, cell_size: float) -> float: # Bilinearly samples the floor map at an arbitrary centred dungeon-local horizontal position.
    return _sample_map(_floor_heights, local_x, local_z, cell_size, FLOOR_BASE_HEIGHT) # Reuses one interpolation path so spawn grounding exactly follows the visible floor surface.

func sample_ceiling(local_x: float, local_z: float, cell_size: float) -> float: # Bilinearly samples the ceiling map at an arbitrary centred dungeon-local horizontal position.
    return _sample_map(_ceiling_heights, local_x, local_z, cell_size, CEILING_BASE_HEIGHT) # Reuses the same coordinate convention for overhead placement and diagnostics.

func get_scaled_floor_map_data(vertical_scale: float) -> PackedFloat32Array: # Returns a copy of floor heights pre-divided for a uniformly scaled HeightMapShape3D collision node.
    var result: PackedFloat32Array = PackedFloat32Array() # Allocates an isolated physics-data copy so collision setup cannot mutate authoritative geometry values.
    result.resize(_floor_heights.size()) # Matches the exact shared vertex count required by HeightMapShape3D map_data.
    var safe_scale: float = maxf(absf(vertical_scale), 0.0001) # Prevents division by zero if malformed collision scaling is supplied.
    for data_index: int in range(_floor_heights.size()): # Visits every authoritative floor sample once while producing collision-space values.
        result[data_index] = _floor_heights[data_index] / safe_scale # Pre-scales vertical data so uniform node scaling restores the intended world-space height.
    return result # Returns the complete row-major floor map ready for HeightMapShape3D assignment.

func _sample_map(map_data: PackedFloat32Array, local_x: float, local_z: float, cell_size: float, fallback: float) -> float: # Performs centred bilinear sampling against either authoritative dungeon height map.
    if vertex_width <= 1 or vertex_depth <= 1 or map_data.is_empty(): # Detects an ungenerated or degenerate map that cannot support bilinear interpolation.
        return fallback # Uses the requested stable baseline when valid height data is unavailable.
    var safe_cell_size: float = maxf(absf(cell_size), 0.0001) # Prevents malformed cell dimensions from causing undefined coordinate conversion.
    var origin_x: float = -float(_layout_width) * safe_cell_size * 0.5 # Reconstructs the centred physical x coordinate of height-map vertex zero.
    var origin_z: float = -float(_layout_depth) * safe_cell_size * 0.5 # Reconstructs the centred physical z coordinate of height-map vertex zero.
    var grid_x: float = clampf((local_x - origin_x) / safe_cell_size, 0.0, float(vertex_width - 1)) # Converts local x into continuous height-map sample coordinates.
    var grid_z: float = clampf((local_z - origin_z) / safe_cell_size, 0.0, float(vertex_depth - 1)) # Converts local z into continuous height-map sample coordinates.
    var x0: int = mini(int(floor(grid_x)), vertex_width - 2) # Resolves the left sample column while guaranteeing a valid right neighbour.
    var z0: int = mini(int(floor(grid_z)), vertex_depth - 2) # Resolves the near sample row while guaranteeing a valid far neighbour.
    var x1: int = x0 + 1 # Selects the adjacent horizontal sample required by bilinear interpolation.
    var z1: int = z0 + 1 # Selects the adjacent depth sample required by bilinear interpolation.
    var tx: float = clampf(grid_x - float(x0), 0.0, 1.0) # Calculates normalized horizontal interpolation within the selected grid square.
    var tz: float = clampf(grid_z - float(z0), 0.0, 1.0) # Calculates normalized depth interpolation within the selected grid square.
    var h00: float = map_data[_get_index(x0, z0)] # Reads the near-left height shared by the current grid square.
    var h10: float = map_data[_get_index(x1, z0)] # Reads the near-right height shared by the current grid square.
    var h01: float = map_data[_get_index(x0, z1)] # Reads the far-left height shared by the current grid square.
    var h11: float = map_data[_get_index(x1, z1)] # Reads the far-right height shared by the current grid square.
    var near_height: float = lerpf(h00, h10, tx) # Interpolates the near edge at the requested horizontal fraction.
    var far_height: float = lerpf(h01, h11, tx) # Interpolates the far edge at the same horizontal fraction.
    return lerpf(near_height, far_height, tz) # Interpolates between both edges to recover the continuous surface height.

func _get_endpoint_flatten_weight(layout: DungeonLayout, vertex_x: int, vertex_z: int) -> float: # Produces a smooth zero-to-one flattening weight around both exact paired endpoint cells.
    var sample_point: Vector2 = Vector2(float(vertex_x), float(vertex_z)) # Represents this shared height-map vertex in logical grid coordinates.
    var endpoint_a: Vector2 = Vector2(float(layout.door_a_cell.x) + 0.5, float(layout.door_a_cell.y) + 0.5) # Resolves endpoint A to the centre of its guaranteed walkable logical cell.
    var endpoint_b: Vector2 = Vector2(float(layout.door_b_cell.x) + 0.5, float(layout.door_b_cell.y) + 0.5) # Resolves endpoint B to the centre of its guaranteed walkable logical cell.
    var distance_a: float = sample_point.distance_to(endpoint_a) # Measures grid-space distance from this vertex to the A landing cell.
    var distance_b: float = sample_point.distance_to(endpoint_b) # Measures grid-space distance from this vertex to the B landing cell.
    var nearest_distance: float = minf(distance_a, distance_b) # Uses whichever paired endpoint is closest to the current shared vertex.
    return 1.0 - smoothstep(0.45, ENDPOINT_FLATTEN_RADIUS, nearest_distance) # Produces full flattening near a door and a smooth transition back to procedural relief.

func _create_noise(noise_seed: int, frequency: float) -> FastNoiseLite: # Creates one isolated smooth deterministic fractal source for a dungeon height-map channel.
    var noise: FastNoiseLite = FastNoiseLite.new() # Allocates a fresh generator so dungeon sampling never consumes mutable global random state.
    noise.seed = noise_seed # Separates this field deterministically from layout, lighting, and the other height-map channel.
    noise.frequency = frequency # Sets the broad grid-space feature size used by floor or ceiling relief.
    noise.fractal_type = FastNoiseLite.FRACTAL_FBM # Combines a few smooth octaves instead of producing sharp ridged walk surfaces.
    noise.fractal_octaves = NOISE_OCTAVES # Limits high-frequency detail for stable traversal and inexpensive deterministic generation.
    noise.fractal_gain = 0.48 # Reduces each successive octave so broad height changes remain dominant.
    noise.fractal_lacunarity = 2.0 # Doubles frequency per octave using the conventional fractal progression.
    return noise # Returns the complete local noise source used only during height-map generation.

func _get_index(vertex_x: int, vertex_z: int) -> int: # Converts one validated shared grid coordinate into packed row-major storage.
    return vertex_z * vertex_width + vertex_x # Stores complete x rows consecutively for cache-friendly generation and mesh traversal.

func _clear() -> void: # Resets all generated map state after an invalid generation request.
    vertex_width = 0 # Removes the previous shared sample width.
    vertex_depth = 0 # Removes the previous shared sample depth.
    _layout_width = 0 # Clears logical width retained for coordinate conversion.
    _layout_depth = 0 # Clears logical depth retained for coordinate conversion.
    _floor_heights = PackedFloat32Array() # Releases authoritative floor samples.
    _ceiling_heights = PackedFloat32Array() # Releases authoritative ceiling samples.
