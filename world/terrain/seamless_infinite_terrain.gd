extends InfiniteTerrain
class_name SeamlessInfiniteTerrain

# Water queries use the same flat cell level and clipped shoreline as the mesh.

const SEAMLESS_WATER_PRESENCE_EPSILON: float = 0.02
const SEAMLESS_INVALID_WATER_CELL: Vector2i = Vector2i(2_147_483_647, 2_147_483_647)

var _seamless_water_query_cell_coordinate: Vector2i = SEAMLESS_INVALID_WATER_CELL
var _seamless_water_cell_level: float = 0.0
var _seamless_terrain_top_left_height: float = 0.0
var _seamless_terrain_top_right_height: float = 0.0
var _seamless_terrain_bottom_left_height: float = 0.0
var _seamless_terrain_bottom_right_height: float = 0.0

func _ready() -> void:
    super()
    _height_sampler = SeamlessTerrainHeightSampler.new()
    _mesh_builder = TerrainMeshBuilder.new(_height_sampler, _terrain_material,self)
    _water_level_sampler = SeamlessTerrainWaterLevelSampler.new()
    _water_mesh_builder = SeamlessTerrainWaterMeshBuilder.new(_height_sampler, _water_level_sampler, _water_material)

func get_water_level_at(world_position: Vector2) -> float:
    _update_seamless_water_query_cache(world_position)
    return _seamless_water_cell_level

func has_water_at(world_position: Vector2) -> bool:
    _update_seamless_water_query_cache(world_position)
    var rendered_water_height: float = _seamless_water_cell_level
    var rendered_terrain_height: float = _sample_cached_terrain_height(world_position)
    return rendered_terrain_height < rendered_water_height - SEAMLESS_WATER_PRESENCE_EPSILON

func _update_seamless_water_query_cache(world_position: Vector2) -> void:
    var water_cell_count: int = TerrainConfiguration.WATER_RESOLUTION - 1
    var water_cell_size: float = TerrainConfiguration.CHUNK_SIZE / float(water_cell_count)
    var cell_coordinate: Vector2i = Vector2i(floori(world_position.x / water_cell_size), floori(world_position.y / water_cell_size))
    if cell_coordinate == _seamless_water_query_cell_coordinate:
        return
    _seamless_water_query_cell_coordinate = cell_coordinate
    var cell_origin_x: float = float(cell_coordinate.x) * water_cell_size
    var cell_origin_z: float = float(cell_coordinate.y) * water_cell_size
    var cell_right_x: float = cell_origin_x + water_cell_size
    var cell_forward_z: float = cell_origin_z + water_cell_size
    _seamless_water_cell_level = _water_level_sampler.sample_water_level(cell_origin_x + water_cell_size * 0.5, cell_origin_z + water_cell_size * 0.5)
    _seamless_terrain_top_left_height = get_height_at(Vector2(cell_origin_x, cell_origin_z))
    _seamless_terrain_top_right_height = get_height_at(Vector2(cell_right_x, cell_origin_z))
    _seamless_terrain_bottom_left_height = get_height_at(Vector2(cell_origin_x, cell_forward_z))
    _seamless_terrain_bottom_right_height = get_height_at(Vector2(cell_right_x, cell_forward_z))

func _sample_cached_terrain_height(world_position: Vector2) -> float:
    return _sample_cached_cell_height(world_position, _seamless_terrain_top_left_height, _seamless_terrain_top_right_height, _seamless_terrain_bottom_left_height, _seamless_terrain_bottom_right_height)

func _sample_cached_cell_height(world_position: Vector2, top_left_height: float, top_right_height: float, bottom_left_height: float, bottom_right_height: float) -> float:
    var water_cell_count: int = TerrainConfiguration.WATER_RESOLUTION - 1
    var water_cell_size: float = TerrainConfiguration.CHUNK_SIZE / float(water_cell_count)
    var cell_origin_x: float = float(_seamless_water_query_cell_coordinate.x) * water_cell_size
    var cell_origin_z: float = float(_seamless_water_query_cell_coordinate.y) * water_cell_size
    var local_x: float = clampf((world_position.x - cell_origin_x) / water_cell_size, 0.0, 1.0)
    var local_z: float = clampf((world_position.y - cell_origin_z) / water_cell_size, 0.0, 1.0)
    if local_x + local_z <= 1.0:
        return top_left_height + local_x * (top_right_height - top_left_height) + local_z * (bottom_left_height - top_left_height)
    return bottom_right_height + (1.0 - local_z) * (top_right_height - bottom_right_height) + (1.0 - local_x) * (bottom_left_height - bottom_right_height)
