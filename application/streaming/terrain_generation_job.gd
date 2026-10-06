extends RefCounted
class_name TerrainGenerationJob
var cell: Vector2i
var routes: Dictionary
func _init(coordinate: Vector2i, route_snapshot: Dictionary):
    cell = coordinate
    routes = route_snapshot
func generate() -> Array:
    # Each job owns its samplers and buffers. No scene nodes or graphics API calls.
    var sampler = SeamlessTerrainHeightSampler.new()
    var terrain = TerrainMeshBuilder.new(sampler,null,null,false)
    terrain.path_routes = routes
    var water = SeamlessTerrainWaterMeshBuilder.new(sampler,SeamlessTerrainWaterLevelSampler.new(),null)
    return [terrain.build_chunk_arrays(cell),water.build_chunk_arrays(cell)]
