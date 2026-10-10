extends SceneTree # Checks the shared water contract independently of scene streaming.

class LowGround extends TerrainHeightSampler: # Creates deliberately low dry land to test explicit occupancy.
    func sample_height(_x: float, _z: float) -> float: return -10000.0 # Separates basin membership from altitude.

func _initialize() -> void: run.call_deferred() # Starts after the tree is initialized.

func covered(point: Vector2, vertices: PackedVector3Array) -> bool: # Tests actual emitted water polygons rather than reusing the query implementation.
    for index: int in range(0, vertices.size(), 3): # Examines each nonindexed rendered triangle.
        var a: Vector2 = Vector2(vertices[index].x, vertices[index].z) # Projects the first vertex onto the horizontal plane.
        var b: Vector2 = Vector2(vertices[index + 1].x, vertices[index + 1].z) # Projects the second vertex.
        var c: Vector2 = Vector2(vertices[index + 2].x, vertices[index + 2].z) # Projects the final vertex.
        var first: float = (b - a).cross(point - a) # Measures which side of the first edge contains the sample.
        var second: float = (c - b).cross(point - b) # Measures the second edge.
        var third: float = (a - c).cross(point - c) # Measures the final edge.
        if (first >= 0.0 and second >= 0.0 and third >= 0.0) or (first <= 0.0 and second <= 0.0 and third <= 0.0): # Accepts consistent triangle winding.
            return true # Reports coverage by actual emitted geometry.
    return false # Reports dry space when no emitted triangle covers the point.

func seam(vertices: PackedVector3Array, edge: float) -> Array[Vector2]: # Extracts unique edge heights for cross-chunk comparison.
    var result: Array[Vector2] = [] # Collects stable horizontal-edge samples.
    for vertex: Vector3 in vertices: # Inspects every rendered vertex.
        var value: Vector2 = Vector2(vertex.z, vertex.y) # Stores the seam position and level.
        if absf(vertex.x - edge) < 0.00001 and not result.has(value): result.append(value) # Deduplicates matching seam vertices.
    result.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y)) # Orders samples independently of triangle emission.
    return result # Returns a canonical seam representation.

func run() -> void: # Exercises explicit boundaries, drainage, meshes, worker order and rebasing.
    var low_query: WaterQueryService = WaterQueryService.new(LowGround.new()) # Uses a height field that would flood everywhere under the old rule.
    assert(not low_query.sample(Vector2.ZERO).present) # Keeps the origin dry regardless of ground altitude.
    for cell: Vector2i in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(20, -17)]: # Checks signed and distant provincial ownership.
        var edge: Vector2 = Vector2(cell) * BiomeProfile.REGION_SIZE + Vector2(0.1, 2048.0) # Samples an unloaded provincial boundary.
        var dry: Dictionary = low_query.sample(edge) # Queries explicit body occupancy above deeply low terrain.
        assert(not dry.present and dry.body_id == "" and dry.depth == 0.0 and dry.surface_height == -INF) # Requires a complete and unambiguous dry result.
    var river: Dictionary = BiomeProfile.region(Vector2i(-1, 0)) # Loads the deterministic cascade watershed.
    var previous: Dictionary = {} # Tracks the preceding reach in the drainage graph.
    for z: float in [-600.0, 0.0, 600.0]: # Traverses reaches in downstream order.
        var point: Vector2 = Vector2(river.centre) + Vector2(BiomeProfile.river_x(z, float(river.phase)), z) # Samples the planned channel centre.
        var plan: Dictionary = WaterBodyPlan.definition_at(point) # Reads the body identity and drainage contract.
        if not previous.is_empty(): # Checks each adjacent connection.
            assert(previous.downstream_id == plan.body_id and previous.surface_height > plan.surface_height) # Requires explicit gravity-compatible connectivity.
        previous = plan # Advances downstream.
    assert(previous.downstream_id == "") # Terminates the river in a closed sink rather than an unloaded neighbour.
    var terrain: SeamlessInfiniteTerrain = SeamlessInfiniteTerrain.new() # Exercises production gameplay queries.
    terrain._height_sampler = SeamlessTerrainHeightSampler.new() # Supplies final planned terrain.
    terrain._water_level_sampler = SeamlessTerrainWaterLevelSampler.new() # Supplies compatibility sampling for other consumers.
    var builder: SeamlessTerrainWaterMeshBuilder = SeamlessTerrainWaterMeshBuilder.new(terrain._height_sampler, terrain._water_level_sampler, null) # Builds the production clipped surface.
    var point: Vector2 = Vector2(BiomeProfile.region(Vector2i(0, -1)).centre) + Vector2(800.0, 0.0) # Selects a lagoon away from the raised central island.
    var cell: Vector2i = Vector2i((point / TerrainConfiguration.CHUNK_SIZE).floor()) # Selects a wet chunk and its neighbour.
    var first: Array = builder.build_chunk_arrays(cell) # Generates the first chunk before its neighbour.
    var second: Array = builder.build_chunk_arrays(cell + Vector2i.RIGHT) # Generates the adjacent chunk.
    assert(not first.is_empty() and not second.is_empty()) # Ensures seam checks exercise actual water.
    var vertices: PackedVector3Array = first[Mesh.ARRAY_VERTEX] # Reads final clipped geometry.
    assert(seam(vertices, TerrainConfiguration.CHUNK_SIZE) == seam(second[Mesh.ARRAY_VERTEX], 0.0)) # Requires identical wet-edge intersections and elevations.
    var rng: RandomNumberGenerator = RandomNumberGenerator.new() # Provides reproducible independent coverage samples.
    rng.seed = 92817 # Fixes the test sample order.
    for index: int in range(128): # Samples interiors and shores across the selected chunk.
        var local: Vector2 = Vector2(rng.randf_range(0.01, 255.99), rng.randf_range(0.01, 255.99)) # Avoids ambiguous ownership on exact chunk edges.
        var absolute: Vector2 = Vector2(cell) * TerrainConfiguration.CHUNK_SIZE + local # Restores the stable world coordinate.
        var sample: Dictionary = terrain.get_water_sample_at(absolute) # Reads the authoritative gameplay result.
        assert(bool(sample.present) == covered(local, vertices)) # Checks both wet and dry query results against emitted triangles.
        if sample.present: assert(sample.depth > WaterQueryService.PRESENCE_EPSILON and not String(sample.body_id).is_empty()) # Requires meaningful depth and stable identity.
    var start_sample: Dictionary = terrain.get_water_sample_at(WaterBodyPlan.STARTING_LAKE_CENTRE) # Checks the explicitly planned temperate starting basin.
    assert(start_sample.present and start_sample.body_id == "starting_lake" and is_equal_approx(start_sample.depth, 8.0)) # Requires a contained shallow lake with stable identity.
    var before: Dictionary = terrain.get_water_sample_at(point) # Captures the absolute result before origin rebasing.
    terrain._world_origin_offset = Vector2(32768.0, -65536.0) # Simulates a distant floating origin.
    var local_position: Vector3 = terrain.world_to_local_position(Vector3(point.x, 0.0, point.y)) # Converts through the rebased scene coordinate space.
    var recovered: Vector3 = terrain.local_to_world_position(local_position) # Restores the absolute query coordinate.
    assert(terrain.get_water_sample_at(Vector2(recovered.x, recovered.z)) == before) # Requires identical water identity, elevation and occupancy after rebasing.
    var other_job: TerrainGenerationJob = TerrainGenerationJob.new(cell + Vector2i.RIGHT, {}) # Generates the neighbour first on a worker.
    var same_job: TerrainGenerationJob = TerrainGenerationJob.new(cell, {}) # Regenerates the original after a different load order.
    var task: int = WorkerThreadPool.add_task(other_job.generate) # Exercises worker-safe regional definition access.
    var generated: Array = same_job.generate() # Builds the original through the complete worker buffer path.
    WorkerThreadPool.wait_for_task_completion(task) # Joins before ending the scene tree.
    assert(generated[1] == first) # Requires reload and job-order independence for all water buffers.
    terrain.free() # Releases the test terrain node.
    print("PASS explicit dry occupancy, downhill connections, wet chunk seams, inverse mesh coverage, worker reloads and rebasing") # Reports the verified contract.
    quit() # Ends the regression process.
