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
    var ground: Array = terrain.build_chunk_arrays(cell) # Preserve the worker-owned indexed ground buffers.
    var vertices: PackedVector3Array = ground[Mesh.ARRAY_VERTEX] # Read CPU positions before any rendering upload.
    var indices: PackedInt32Array = ground[Mesh.ARRAY_INDEX] # Preserve exact mesh triangle winding.
    var faces: PackedVector3Array = PackedVector3Array() # Prepare triangle soup for later main-thread physics creation.
    faces.resize(indices.size()) # Allocate the complete collision buffer once.
    for index: int in range(indices.size()): # Expand indexed triangles without accessing rendering resources.
        faces[index] = vertices[indices[index]] # Keep collision geometry identical to the visual mesh.
    return [ground, water.build_chunk_arrays(cell), faces] # Hand only plain buffers back to the scene thread.
