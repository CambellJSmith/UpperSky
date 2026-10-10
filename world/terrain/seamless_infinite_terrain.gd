extends InfiniteTerrain # Extends streaming terrain with planned basin queries.
class_name SeamlessInfiniteTerrain # Retains the production terrain scene interface.

var _water_query_service: WaterQueryService # Owns the authoritative gameplay corner cache.

func _ready() -> void: # Installs production terrain and water services after base initialization.
    super() # Initializes the inherited streaming controller.
    _height_sampler = SeamlessTerrainHeightSampler.new() # Selects final biome and basin terrain.
    _mesh_builder = TerrainMeshBuilder.new(_height_sampler, _terrain_material, self) # Builds visible ground from that final terrain.
    _water_level_sampler = SeamlessTerrainWaterLevelSampler.new() # Selects the shared planned water elevation provider.
    _water_mesh_builder = SeamlessTerrainWaterMeshBuilder.new(_height_sampler, _water_level_sampler, _water_material) # Clips visible water against final ground and body boundaries.
    _water_query_service = WaterQueryService.new(_height_sampler, get_height_at) # Reuses world corner heights for gameplay queries.

func get_water_sample_at(world_position: Vector2) -> Dictionary: # Returns authoritative absolute-world water metadata.
    if _water_query_service == null: # Supports detached terrain fixtures before scene initialization.
        _water_query_service = WaterQueryService.new(_height_sampler, get_height_at) # Creates the same corner cache used by a live world.
    return _water_query_service.sample(world_position) # Delegates presence and depth to the shared triangle query.

func get_water_level_at(world_position: Vector2) -> float: # Provides planned elevation for conservative shore placement.
    return _water_level_sampler.sample_water_level(world_position.x, world_position.y) # Reads the shared plan without recomputing ground corners.

func has_water_at(world_position: Vector2) -> bool: # Reports actual clipped water occupancy.
    if (_water_level_sampler as SeamlessTerrainWaterLevelSampler).boundary_at(world_position) < -WaterBodyPlan.GRID_SPACING * 2.0: # Rejects distant dry points before sampling ground corners.
        return false # Keeps deep terrain outside explicit bodies dry.
    return bool(get_water_sample_at(world_position).present) # Delegates occupancy to the authoritative result.
