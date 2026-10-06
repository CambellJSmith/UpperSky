extends SceneTree

class TestTerrain extends InfiniteTerrain:
    func _ready(): pass
    func get_loaded_chunk_count() -> int: return 9
    func get_height_at(p: Vector2) -> float: return .02*p.x+.01*p.y
    func has_water_at(_p: Vector2) -> bool: return false
    func get_water_level_at(_p: Vector2) -> float: return -100.0

class BlockedNetwork extends WorldPathNetwork:
    var started := false
    func routes_in_chunk_incremental(_cell: Vector2i, scheduler: GenerationScheduler) -> Array[Dictionary]:
        started = true
        while not scheduler._closing:
            if not await scheduler.checkpoint(): return []
            await scheduler.frame_started
        return []

func _initialize(): run.call_deferred()
func run():
    var scheduler := GenerationScheduler.new(); root.add_child(scheduler)
    var game := Node3D.new(); root.add_child(game)
    var world := Node3D.new(); world.name="World"; game.add_child(world)
    var terrain := TestTerrain.new(); terrain.name="Terrain"; world.add_child(terrain)
    var network := BlockedNetwork.new(terrain)
    WorldPathNetwork._networks[terrain.get_instance_id()] = weakref(network)
    var dynamic := Node3D.new(); dynamic.name="DynamicEntities"; game.add_child(dynamic)
    var player: FirstPersonPlayer = load("res://actors/player/first_person_player.tscn").instantiate()
    player.name="Player"; dynamic.add_child(player)
    player.initialize_environment(terrain)
    player.global_position=Vector3(128,30,128)
    var streamer := PathStreamer.new(); streamer.name="Paths"; world.add_child(streamer)
    # A village street is ready, while the regional planner never finishes.
    var points: Array[Vector2] = [Vector2(32,128),Vector2(128,128),Vector2(224,160)]
    var road := network.route(points,2.2,3.2,"street")
    network._plans["village"] = [road]
    var deadline := Time.get_ticks_msec()+5000
    while Time.get_ticks_msec()<deadline:
        await process_frame
        if streamer._chunks.has(Vector2i.ZERO) and streamer._chunks[Vector2i.ZERO].mesh!=null: break
    assert(network.started,"Regional planner fixture was not exercised")
    assert(streamer._chunks.has(Vector2i.ZERO) and streamer._chunks[Vector2i.ZERO].mesh!=null,"Ready streets waited for regional planning")
    var mesh: ArrayMesh = streamer._chunks[Vector2i.ZERO].mesh
    var arrays := mesh.surface_get_arrays(0)
    var solid := 0
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
    for i in range(vertices.size()):
        assert(absf(vertices[i].y-network._settlements.ground_height(Vector2(vertices[i].x,vertices[i].z))-.035)<.001)
        if colours[i].a>.9: solid+=1
    assert(solid>100,"Ready path was transparent")
    streamer._routes_ready(Vector2i.ZERO)
    assert(streamer._chunks[Vector2i.ZERO].mesh==mesh,"Path disappeared while its replacement was queued")
    # Publishing another completed road must replace a previously empty chunk.
    var other_points: Array[Vector2] = [Vector2(270,128),Vector2(480,128)]
    var other := network.route(other_points,2.2,3.2,"connection")
    other.key="late"; other.from=other_points[0]; other.to=other_points[1]
    network._roads[other.key] = other
    network._publish_available(other)
    deadline=Time.get_ticks_msec()+5000
    while Time.get_ticks_msec()<deadline:
        await process_frame
        if streamer._chunks.has(Vector2i(1,0)) and streamer._chunks[Vector2i(1,0)].mesh!=null: break
    assert(streamer._chunks.has(Vector2i(1,0)) and streamer._chunks[Vector2i(1,0)].mesh!=null,"Late road did not refresh an empty path chunk")
    assert(network.get_local_mask(Vector2(400,128))>.99,"Partial-road grass mask is missing")
    # Mesh winding must face upwards; transparent edge geometry must not cull it.
    for i in range(0,vertices.size(),3):
        assert((vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).y<0)
    game.queue_free(); await process_frame
    scheduler.queue_free(); await process_frame
    print("PASS visible opaque ground-conforming paths while regional planning is blocked, late-road refresh, grass masks, winding and shutdown")
    quit()
