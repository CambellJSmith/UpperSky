extends InfiniteTerrain # Defines shared water planning data.
class_name SeamlessInfiniteTerrain # Defines shared water planning data.

var _water_query_service: WaterQueryService # Defines shared water planning data.

func _ready() -> void: # Keeps water planning deterministic in absolute coordinates.
    super() # Keeps water planning deterministic in absolute coordinates.
    _height_sampler = SeamlessTerrainHeightSampler.new() # Keeps water planning deterministic in absolute coordinates.
    _mesh_builder = TerrainMeshBuilder.new(_height_sampler, _terrain_material, self) # Keeps water planning deterministic in absolute coordinates.
    _water_level_sampler = SeamlessTerrainWaterLevelSampler.new() # Keeps water planning deterministic in absolute coordinates.
    _water_mesh_builder = SeamlessTerrainWaterMeshBuilder.new(_height_sampler, _water_level_sampler, _water_material) # Keeps water planning deterministic in absolute coordinates.
    _water_query_service = WaterQueryService.new(_height_sampler) # Keeps water planning deterministic in absolute coordinates.

func get_water_sample_at(world_position: Vector2) -> Dictionary: # Keeps water planning deterministic in absolute coordinates.
    if _water_query_service == null: # Keeps water planning deterministic in absolute coordinates.
        _water_query_service = WaterQueryService.new(_height_sampler) # Keeps water planning deterministic in absolute coordinates.
    return _water_query_service.sample(world_position) # Keeps water planning deterministic in absolute coordinates.

func get_water_level_at(world_position: Vector2) -> float: # Keeps water planning deterministic in absolute coordinates.
    return float(get_water_sample_at(world_position).surface_height) # Keeps water planning deterministic in absolute coordinates.

func has_water_at(world_position: Vector2) -> bool: # Keeps water planning deterministic in absolute coordinates.
    return bool(get_water_sample_at(world_position).present) # Keeps water planning deterministic in absolute coordinates.
