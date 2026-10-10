extends SceneTree # Verify staged operations and stale terrain cancellation.

func _initialize() -> void: run.call_deferred() # Begin after the tree is available.

func run() -> void: # Check shared operation admission through actual chunk installation.
    var scheduler: GenerationScheduler = GenerationScheduler.new() # Use production frame scheduling.
    root.add_child(scheduler) # Start shared budget ticks.
    var terrain: InfiniteTerrain = InfiniteTerrain.new() # Use production staged mesh installation.
    root.add_child(terrain) # Initialize the terrain builders.
    terrain._water_mesh_builder = SeamlessTerrainWaterMeshBuilder.new(SeamlessTerrainHeightSampler.new(), SeamlessTerrainWaterLevelSampler.new(), null) # Match the production worker backend.
    terrain.set_process(false) # Avoid unrelated procedural generation.
    terrain._current_chunk_coordinate = Vector2i.ZERO # Match the initialized physical neighbourhood.
    var cell: Vector2i = Vector2i.ZERO # Keep the fixture inside the collision radius.
    var arrays: Array = [] # Supply a small deterministic indexed surface.
    arrays.resize(Mesh.ARRAY_MAX) # Match the surface buffer layout.
    var vertices: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0), Vector3(0, 0, 10)]) # Define one upward-facing triangle.
    arrays[Mesh.ARRAY_VERTEX] = vertices # Provide CPU positions.
    arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2]) # Preserve exact winding.
    terrain._desired_chunks[cell] = true # Require the fixture chunk.
    terrain._building[cell] = true # Simulate a worker result waiting for application.
    var data: Array = [arrays, [], vertices] # Match the worker handoff contract.
    terrain._install_background_chunk(cell, data) # Start asynchronous staged installation.
    assert(not terrain._chunks.has(cell), "All stages ran in one frame") # Reject an indivisible combined installation.
    terrain._desired_chunks.clear() # Simulate travel while uploads are waiting.
    var deadline: int = Time.get_ticks_msec() + 5000 # Bound stale-result cancellation.
    while terrain._building.has(cell) and Time.get_ticks_msec() < deadline: await process_frame # Let the next stage recheck demand.
    assert(not terrain._building.has(cell) and not terrain._chunks.has(cell)) # Discard stale work and release its guard.
    terrain._desired_chunks[cell] = true # Request a current result.
    terrain._building[cell] = true # Restore the in-flight guard.
    terrain._install_background_chunk(cell, data) # Start a valid staged installation.
    var first_frame: int = Engine.get_process_frames() # Record the installation start.
    deadline = Time.get_ticks_msec() + 5000 # Bound completion without assuming an exact frame count.
    while terrain._building.has(cell) and Time.get_ticks_msec() < deadline: await process_frame # Resume stages through real frame budgets.
    assert(terrain._chunks.has(cell) and not terrain._building.has(cell)) # Complete exactly one required chunk.
    assert(Engine.get_process_frames() - first_frame >= 2, "Engine operations were combined") # Separate ground, water and physics installation.
    assert(terrain._chunks[cell]._collision_shape.shape != null) # Install safe near-player ground with the final stage.
    assert(scheduler.operation_max_us > 0 and scheduler.stale_jobs > 0) # Expose operation cost and discarded work.
    terrain.free() # Release installed geometry before scheduler shutdown.
    scheduler.free() # Complete task and coroutine cleanup.
    print("PASS staged terrain uploads, exact near collision, stale travel cancellation and operation diagnostics") # Report integration coverage.
    quit() # Complete the regression process.
