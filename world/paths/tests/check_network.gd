extends SceneTree
func _initialize(): run.call_deferred()

func run():
    var terrain := SeamlessInfiniteTerrain.new()
    root.add_child(terrain)
    terrain.set_process(false)
    var network := WorldPathNetwork.for_terrain(terrain)
    var town := network._settlements.find_nearby(Vector2.ZERO,"town")
    var district := Vector2i((town.position/SettlementSampler.TOWN_CELL_SIZE).floor())
    var links = network._district_links.call(district)
    var chosen: Dictionary = {}
    for link in links:
        if link.kind != "arterial" or link.has("requires_failed"): continue
        var other: Vector2 = link.b.position if link.a.position == town.position else link.a.position
        if other.x < -4000 and other.y > 3000: chosen = link; break
    assert(not chosen.is_empty(),"Production fixture centre has no western neighbour")
    network._disk_cache.directory = "/tmp/upper-sky-production-road-test/"
    var path: String = network._disk_cache.directory+String(chosen.key).sha256_text()+".road"
    DirAccess.remove_absolute(path)
    var scheduler := GenerationScheduler.new()
    root.add_child(scheduler)
    var started := Time.get_ticks_msec()
    var road := await network._road(chosen,scheduler)
    var cold_ms := Time.get_ticks_msec()-started
    await process_frame
    assert(not road.is_empty(),"Production population centres did not connect")
    assert(scheduler.completed_jobs == 1,"Production road was not calculated by a background worker")
    var planner := TerrainRoadPlanner.new(network)
    for i in range(road.points.size()-1):
        assert(planner.inspect_edge(road.points[i],road.points[i+1]).valid,"Worker route violates actual terrain geometry")
    # Isolated worker samplers must exactly match the production controller.
    var worker := TerrainRoadJob.new(chosen,true)
    var isolated := worker.create_sampler()
    for p in [chosen.start,chosen.end,Vector2.ZERO,Vector2(-2048,2048),Vector2(2048,2048),Vector2(2048,-2048)]:
        assert(is_equal_approx(isolated.get_height_at(p),terrain.get_height_at(p)))
        assert(isolated.has_water_at(p) == terrain.has_water_at(p))
        assert(isolated.get_water_level_at(p) == terrain.get_water_level_at(p)) # Includes identical absent-water sentinels as well as deterministic wet elevations.
    isolated.free()
    var second := WorldPathNetwork.new(terrain)
    second._disk_cache.directory = network._disk_cache.directory
    started = Time.get_ticks_msec()
    assert(await second._road(chosen,scheduler) == road)
    assert(scheduler.completed_jobs == 1,"Cached road restarted its worker")
    var warm_ms := Time.get_ticks_msec()-started
    # Isolate mesh checks from planning other districts, keeping this regression
    # focused on the generated route and its exact terrain/chunk clipping.
    var centre: Vector2 = road.points[road.points.size()/2]
    var cell := Vector2i((centre/WorldPathNetwork.CHUNK_SIZE).floor())
    for z in range(-1,2):
        for x in range(-1,2):
            var key := cell+Vector2i(x,z)
            var sections: Array[Dictionary] = []
            network._append_chunk(sections,road,Rect2(Vector2(key)*256,Vector2.ONE*256))
            network._chunks[key] = sections
    var mesh := PathMeshBuilder.new(terrain).build(cell)
    assert(mesh != null)
    var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    for vertex in vertices:
        assert(vertex.is_finite())
        assert(vertex.x >= -.01 and vertex.x <= 256.01 and vertex.z >= -.01 and vertex.z <= 256.01)
        var point := Vector2(vertex.x,vertex.z)+Vector2(cell)*256
        assert(absf(vertex.y-network._settlements.ground_height(point)-.035)<.015)
    var export_file := FileAccess.open("/tmp/upper-sky-road-preview.dat",FileAccess.WRITE)
    export_file.store_var(road,false)
    export_file.close()
    scheduler.queue_free()
    await process_frame
    terrain.free()
    print("PASS production centre connection, exact worker terrain/water parity, fine geometry validation, cached reload (",cold_ms,"ms cold / ",warm_ms,"ms warm), ",road.bridges.size()," bridges and ",vertices.size()," terrain-conforming clipped vertices")
    quit()
