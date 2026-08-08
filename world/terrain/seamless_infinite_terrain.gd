extends InfiniteTerrain # Retains the existing infinite streaming and floating-origin system while replacing only terrain-water generation and query services.
class_name SeamlessInfiniteTerrain # Provides the production terrain controller whose water surface cannot form vertical tier or chunk walls.

const SEAMLESS_WATER_PRESENCE_EPSILON: float = 0.02 # Matches the seamless mesh clip tolerance when deciding whether gameplay occupies rendered water.
const SEAMLESS_INVALID_WATER_CELL: Vector2i = Vector2i(2_147_483_647, 2_147_483_647) # Forces the first gameplay water query to populate the seamless shared-vertex cache.

var _seamless_water_query_cell_coordinate: Vector2i = SEAMLESS_INVALID_WATER_CELL # Stores the globally aligned water-grid cell used by the most recent gameplay query.
var _seamless_water_top_left_height: float = 0.0 # Caches the continuous water elevation at the active cell's back-left shared vertex.
var _seamless_water_top_right_height: float = 0.0 # Caches the continuous water elevation at the active cell's back-right shared vertex.
var _seamless_water_bottom_left_height: float = 0.0 # Caches the continuous water elevation at the active cell's forward-left shared vertex.
var _seamless_water_bottom_right_height: float = 0.0 # Caches the continuous water elevation at the active cell's forward-right shared vertex.
var _seamless_terrain_top_left_height: float = 0.0 # Caches terrain elevation at the active cell's back-left shared vertex.
var _seamless_terrain_top_right_height: float = 0.0 # Caches terrain elevation at the active cell's back-right shared vertex.
var _seamless_terrain_bottom_left_height: float = 0.0 # Caches terrain elevation at the active cell's forward-left shared vertex.
var _seamless_terrain_bottom_right_height: float = 0.0 # Caches terrain elevation at the active cell's forward-right shared vertex.

func _ready() -> void: # Initializes ordinary infinite-terrain resources and then replaces generation services before any player-driven chunk construction occurs.
    super() # Builds the established materials and baseline services while preserving all inherited streaming setup assumptions.
    _height_sampler = SeamlessTerrainHeightSampler.new() # Replaces terrain sampling so coastal and underwater shaping use the continuous water profile.
    _mesh_builder = TerrainMeshBuilder.new(_height_sampler, _terrain_material) # Rebinds visible terrain generation to the seamless terrain-height sampler.
    _water_level_sampler = SeamlessTerrainWaterLevelSampler.new() # Replaces discontinuous geological water bands with the shared continuous world-space water function.
    _water_mesh_builder = SeamlessTerrainWaterMeshBuilder.new(_height_sampler, _water_level_sampler, _water_material) # Replaces stepped water cells and vertical curtains with shared-vertex continuous top surfaces.

func get_water_level_at(world_position: Vector2) -> float: # Returns the exact triangle-interpolated water elevation rendered at one stable world-space horizontal position.
    _update_seamless_water_query_cache(world_position) # Populates shared water and terrain vertex samples only when the query crosses a globally aligned water cell boundary.
    return _sample_cached_water_height(world_position) # Interpolates the same water triangle and diagonal used by the seamless water mesh builder.

func has_water_at(world_position: Vector2) -> bool: # Reports whether the seamless rendered water surface occupies one stable world-space horizontal position.
    _update_seamless_water_query_cache(world_position) # Ensures the exact four terrain and water vertex samples for the active rendered cell are cached.
    var rendered_water_height: float = _sample_cached_water_height(world_position) # Reconstructs the exact continuous water triangle height at the requested horizontal coordinate.
    var rendered_terrain_height: float = _sample_cached_terrain_height(world_position) # Reconstructs the exact terrain triangle height using the same grid and diagonal.
    return rendered_terrain_height < rendered_water_height - SEAMLESS_WATER_PRESENCE_EPSILON # Matches mesh clipping so gameplay water exists only where the rendered top surface lies meaningfully above terrain.

func _update_seamless_water_query_cache(world_position: Vector2) -> void: # Caches one globally aligned shared-vertex cell for efficient exact water and terrain interpolation.
    var water_cell_count: int = TerrainConfiguration.WATER_RESOLUTION - 1 # Calculates the number of rendered water cells spanning one terrain chunk axis.
    var water_cell_size: float = TerrainConfiguration.CHUNK_SIZE / float(water_cell_count) # Calculates the stable-world spacing between shared water-grid vertices.
    var cell_coordinate: Vector2i = Vector2i(floori(world_position.x / water_cell_size), floori(world_position.y / water_cell_size)) # Finds the globally stable water cell independently from loaded chunk boundaries and floating-origin state.
    if cell_coordinate == _seamless_water_query_cell_coordinate: # Detects repeated player or camera queries inside the already cached water cell.
        return # Reuses cached shared-vertex values without rerunning terrain and regional noise sampling.
    _seamless_water_query_cell_coordinate = cell_coordinate # Stores the new globally aligned cell before calculating its exact shared vertices.
    var cell_origin_x: float = float(cell_coordinate.x) * water_cell_size # Calculates the absolute x coordinate of the cell's back-left shared vertex.
    var cell_origin_z: float = float(cell_coordinate.y) * water_cell_size # Calculates the absolute z coordinate of the cell's back-left shared vertex.
    var cell_right_x: float = cell_origin_x + water_cell_size # Calculates the absolute x coordinate shared by both right-side cell vertices.
    var cell_forward_z: float = cell_origin_z + water_cell_size # Calculates the absolute z coordinate shared by both forward-side cell vertices.
    _seamless_water_top_left_height = _water_level_sampler.sample_water_level(cell_origin_x, cell_origin_z) # Samples the exact continuous water function at the back-left shared vertex.
    _seamless_water_top_right_height = _water_level_sampler.sample_water_level(cell_right_x, cell_origin_z) # Samples the exact continuous water function at the back-right shared vertex.
    _seamless_water_bottom_left_height = _water_level_sampler.sample_water_level(cell_origin_x, cell_forward_z) # Samples the exact continuous water function at the forward-left shared vertex.
    _seamless_water_bottom_right_height = _water_level_sampler.sample_water_level(cell_right_x, cell_forward_z) # Samples the exact continuous water function at the forward-right shared vertex.
    _seamless_terrain_top_left_height = _height_sampler.sample_height(cell_origin_x, cell_origin_z) # Samples the exact terrain function at the back-left shared vertex used by mesh clipping.
    _seamless_terrain_top_right_height = _height_sampler.sample_height(cell_right_x, cell_origin_z) # Samples the exact terrain function at the back-right shared vertex used by mesh clipping.
    _seamless_terrain_bottom_left_height = _height_sampler.sample_height(cell_origin_x, cell_forward_z) # Samples the exact terrain function at the forward-left shared vertex used by mesh clipping.
    _seamless_terrain_bottom_right_height = _height_sampler.sample_height(cell_right_x, cell_forward_z) # Samples the exact terrain function at the forward-right shared vertex used by mesh clipping.

func _sample_cached_water_height(world_position: Vector2) -> float: # Interpolates continuous water height across the active triangle exactly as the water mesh builder does.
    return _sample_cached_cell_height(world_position, _seamless_water_top_left_height, _seamless_water_top_right_height, _seamless_water_bottom_left_height, _seamless_water_bottom_right_height) # Reuses one diagonal-aware interpolation function for the cached water surface.

func _sample_cached_terrain_height(world_position: Vector2) -> float: # Interpolates terrain height across the active water-grid triangle for exact shoreline agreement.
    return _sample_cached_cell_height(world_position, _seamless_terrain_top_left_height, _seamless_terrain_top_right_height, _seamless_terrain_bottom_left_height, _seamless_terrain_bottom_right_height) # Reuses the same diagonal-aware interpolation used for water so both surfaces compare consistently.

func _sample_cached_cell_height(world_position: Vector2, top_left_height: float, top_right_height: float, bottom_left_height: float, bottom_right_height: float) -> float: # Interpolates one four-corner field using the exact two-triangle split shared by terrain and seamless water rendering.
    var water_cell_count: int = TerrainConfiguration.WATER_RESOLUTION - 1 # Calculates the globally shared water-grid cell count per terrain chunk.
    var water_cell_size: float = TerrainConfiguration.CHUNK_SIZE / float(water_cell_count) # Calculates the stable-world size of the active interpolation cell.
    var cell_origin_x: float = float(_seamless_water_query_cell_coordinate.x) * water_cell_size # Reconstructs the active cell's absolute back-left x coordinate.
    var cell_origin_z: float = float(_seamless_water_query_cell_coordinate.y) * water_cell_size # Reconstructs the active cell's absolute back-left z coordinate.
    var local_x: float = clampf((world_position.x - cell_origin_x) / water_cell_size, 0.0, 1.0) # Converts the requested x coordinate into normalized cell-local interpolation space.
    var local_z: float = clampf((world_position.y - cell_origin_z) / water_cell_size, 0.0, 1.0) # Converts the requested z coordinate into normalized cell-local interpolation space.
    if local_x + local_z <= 1.0: # Selects the back-left triangle matching the mesh builder's first triangle and terrain diagonal.
        return top_left_height + local_x * (top_right_height - top_left_height) + local_z * (bottom_left_height - top_left_height) # Interpolates the back-left triangle linearly from its three shared vertex heights.
    return bottom_right_height + (1.0 - local_z) * (top_right_height - bottom_right_height) + (1.0 - local_x) * (bottom_left_height - bottom_right_height) # Interpolates the forward-right triangle using the exact complementary barycentric form.
