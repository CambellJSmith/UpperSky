extends SceneTree
func _initialize(): run.call_deferred()
func run():
    var terrain = InfiniteTerrain.new()
    root.add_child(terrain)
    var sampler = SeamlessTerrainHeightSampler.new()
    var builder = TerrainMeshBuilder.new(sampler,null,terrain)
    var water = SeamlessTerrainWaterMeshBuilder.new(sampler,SeamlessTerrainWaterLevelSampler.new(),null)
    var cell = Vector2i(3,-4)
    var routes = {}
    var network = WorldPathNetwork.for_terrain(terrain)
    for offset in [Vector2i.ZERO,Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)]: routes[cell+offset] = network.routes_in_chunk(cell+offset).duplicate(true)
    var job = TerrainGenerationJob.new(cell,routes)
    var arrays = job.generate()
    var reference = builder.build_chunk_arrays(cell)
    assert(arrays[0][Mesh.ARRAY_VERTEX] == reference[Mesh.ARRAY_VERTEX])
    assert(arrays[0][Mesh.ARRAY_COLOR] == reference[Mesh.ARRAY_COLOR])
    assert(arrays[0][Mesh.ARRAY_INDEX] == reference[Mesh.ARRAY_INDEX])
    assert(arrays[1] == water.build_chunk_arrays(cell))
    var reference_shape: ConcavePolygonShape3D = builder.mesh_from_arrays(reference).create_trimesh_shape() # Compare worker triangles against Godot's original mesh collision path.
    assert(arrays[2] == reference_shape.get_faces(), "Worker collision differs from mesh collision") # Preserve physics geometry and winding exactly.
    var scheduler = GenerationScheduler.new()
    root.add_child(scheduler)
    var result = []
    assert(scheduler.submit(terrain,job.generate,func(data): result.append(data)))
    while result.is_empty(): await process_frame
    assert(result[0][0][Mesh.ARRAY_VERTEX] == reference[Mesh.ARRAY_VERTEX])
    var paths = PathMeshBuilder.new(terrain)
    var sync_mesh = paths.build(cell)
    var async_mesh = await paths.build_incremental(cell,scheduler)
    assert((sync_mesh == null) == (async_mesh == null))
    if sync_mesh != null:
        assert(sync_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == async_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
        assert(sync_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] == async_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR])
    # A fresh planner must match existing town and connection rules after yielding.
    var town = network._settlements.find_nearby(Vector2.ZERO,"town")
    var town_cell = Vector2i(floori(town.position.x/SettlementSampler.TOWN_CELL_SIZE),floori(town.position.y/SettlementSampler.TOWN_CELL_SIZE))
    var fresh = SettlementSampler.new(terrain)
    var async_town = await fresh.sample_town_incremental(town_cell,scheduler)
    assert(async_town.seed == town.seed and async_town.position == town.position)
    assert(async_town.houses.size() == town.houses.size())
    for i in range(town.houses.size()):
        assert(async_town.houses[i].position == town.houses[i].position)
        assert(async_town.houses[i].recipe.resolve() == town.houses[i].recipe.resolve())
    var fresh_network = WorldPathNetwork.new(terrain)
    assert(await fresh_network.town_routes_incremental(town,scheduler) == network.town_routes(town))
    var decoration = WorldDecorationSampler.new(terrain)
    var placements = decoration.sample_chunk(cell,3)
    var async_placements = await decoration.sample_chunk_incremental(cell,3,scheduler)
    assert(placements.size() == async_placements.size())
    for i in range(placements.size()):
        assert(placements[i].transform == async_placements[i].transform)
        assert(placements[i].variant == async_placements[i].variant)
    for layout in [HouseRecipe.Layout.COTTAGE,HouseRecipe.Layout.CROSS]:
        var recipe = HouseRecipe.new()
        recipe.layout = layout
        recipe.seed_value = 12345
        var original_house = HouseGeometry.new().build(recipe)
        var async_house = await HouseGeometry.new().build_incremental(recipe,true,scheduler)
        assert(original_house.get_meta("bounds") == async_house.get_meta("bounds"))
        assert(original_house.get_child_count() == async_house.get_child_count())
        for i in range(original_house.get_child_count()):
            var a = original_house.get_child(i)
            var b = async_house.get_child(i)
            if a is MeshInstance3D:
                assert(a.mesh.surface_get_arrays(0) == b.mesh.surface_get_arrays(0))
            else: assert(a.get_child_count() == b.get_child_count())
        original_house.free()
        async_house.free()
    var paused_owner = Node.new()
    root.add_child(paused_owner)
    paused_owner.process_mode = Node.PROCESS_MODE_DISABLED
    var paused_results: Array = []
    assert(scheduler.submit(paused_owner,func(): return 42,func(data): paused_results.append(data)))
    while not scheduler._workers[0].get("joined",false): await process_frame
    for frame in range(6): await process_frame
    assert(paused_results.is_empty() and scheduler._workers.size()==1)
    var resumed = []
    _wait_for_owner(scheduler,paused_owner,resumed)
    for i in range(3): await process_frame
    assert(resumed.is_empty())
    paused_owner.process_mode = Node.PROCESS_MODE_INHERIT
    while resumed.is_empty(): await process_frame
    assert(resumed[0])
    while paused_results.is_empty(): await process_frame
    assert(paused_results == [42] and scheduler._workers.is_empty())
    paused_owner.queue_free()
    print("PASS worker terrain/water buffers, path geometry, town/road rules, decoration transforms, house meshes/collisions and paused-owner resumption")
    scheduler.queue_free()
    await process_frame
    # Standalone synchronous streaming must skip the nine already-built spawn chunks.
    var player = Node3D.new()
    root.add_child(player)
    terrain.set_process(false)
    terrain.initialize(player,player)
    for i in range(4): terrain._build_pending_chunks()
    assert(terrain.get_child_count() == terrain.get_loaded_chunk_count())
    player.queue_free()
    terrain.queue_free()
    await process_frame
    quit()

func _wait_for_owner(scheduler: GenerationScheduler, owner: Node, result: Array):
    result.append(await scheduler.checkpoint(owner))
