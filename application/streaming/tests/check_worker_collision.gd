extends SceneTree # Compare worker collision against Godot's original mesh collision path.

func _initialize() -> void: run.call_deferred() # Start after global classes and scene dependencies are loaded.

func run() -> void: # Cover worker handoff without forcing cold regional road searches.
    var scheduler: GenerationScheduler = GenerationScheduler.new() # Use the production worker handoff.
    root.add_child(scheduler) # Start task polling and budget admission.
    for cell: Vector2i in [Vector2i(3, -4), Vector2i(-2, 1)]: # Cover both signs of absolute world coordinates.
        var origin: Vector2 = Vector2(cell) * TerrainConfiguration.CHUNK_SIZE # Define a deterministic completed road mask.
        var routes: Dictionary = {cell: [{"bounds":Rect2(origin, Vector2.ONE * TerrainConfiguration.CHUNK_SIZE), "points":PackedVector2Array([origin, origin + Vector2.ONE * TerrainConfiguration.CHUNK_SIZE]), "core":2.0, "edge":5.0}]} # Supply private road data without synchronous region planning.
        var job: TerrainGenerationJob = TerrainGenerationJob.new(cell, routes) # Capture isolated job inputs.
        var results: Array = [] # Retain only a joined worker result.
        assert(scheduler.submit(scheduler, job.generate, func(data: Array): results.append(data))) # Exercise the real worker pool.
        var deadline: int = Time.get_ticks_msec() + 20000 # Bound task completion without frame-count assumptions.
        while results.is_empty() and Time.get_ticks_msec() < deadline: await process_frame # Let the scheduler join and apply the private buffers.
        assert(not results.is_empty(), "Terrain worker did not complete") # Detect task handoff failures.
        var result: Array = results[0] # Inspect the completed ground, water and collision payload.
        var builder: TerrainMeshBuilder = TerrainMeshBuilder.new(SeamlessTerrainHeightSampler.new(), null, null, false) # Generate an independent synchronous reference.
        builder.path_routes = routes # Use the same immutable completed road mask.
        var reference: Array = builder.build_chunk_arrays(cell) # Preserve original deterministic vertex and triangle rules.
        assert(result[0] == reference, "Worker changed ground buffers") # Preserve vertices, normals, colours, UVs and topology.
        var water: SeamlessTerrainWaterMeshBuilder = SeamlessTerrainWaterMeshBuilder.new(SeamlessTerrainHeightSampler.new(), SeamlessTerrainWaterLevelSampler.new(), null) # Generate independent water buffers.
        assert(result[1] == water.build_chunk_arrays(cell), "Worker changed water buffers") # Preserve clipped water geometry.
        var original_shape: ConcavePolygonShape3D = builder.mesh_from_arrays(reference).create_trimesh_shape() # Ask Godot to build collision through the previous path.
        assert(result[2] == original_shape.get_faces(), "CPU collision changed triangle winding or geometry") # Compare exact collision faces against the engine reference.
    scheduler.free() # Release all completed tasks and the singleton owner.
    print("PASS worker ground/water parity, completed road masks and exact mesh-derived collision triangles") # Report deterministic worker coverage.
    quit() # Complete the regression process.
