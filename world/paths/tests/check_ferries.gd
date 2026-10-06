extends SceneTree

class ShoreTerrain extends InfiniteTerrain:
    var steep := false
    var island := false
    var falls := false
    func _ready(): pass
    func get_height_at(p: Vector2) -> float:
        return maxf(-5,minf(absf(p.x-1080)-80,40)*(.7 if steep else .12))
    func has_water_at(p: Vector2) -> bool: return p.x>1000 and p.x<1160 and not (island and p.x>1070 and p.x<1090)
    func get_water_level_at(p: Vector2) -> float: return (p.x-1000)*.4 if falls else 0.0

class ClearNetwork extends WorldPathNetwork:
    var blocked := false
    func obstructed(_point: Vector2) -> bool: return blocked

func _initialize(): run.call_deferred()

func shifted_crossing(data: Dictionary, offset: Vector2, key: String) -> Dictionary:
    var result := data.duplicate(true)
    result.key = key
    for dock in result.docks:
        for field in ["shore","land","tip","berth"]: dock[field] += offset
    result.lane = [data.lane[0]+offset,data.lane[1]+offset]
    return result

func run():
    var eligible := 0
    for z in range(-20,20):
        for x in range(-20,20):
            var cell := Vector2i(x,z)
            var selected := FerrySampler.eligible_cell(cell)
            assert(selected == FerrySampler.eligible_cell(cell),"Ferry density changes between reloads")
            if selected: eligible += 1
    assert(eligible>400 and eligible<700,"Unexpected ferry density")
    var terrain := ShoreTerrain.new()
    root.add_child(terrain)
    var sampler := FerrySampler.new(terrain)
    var clear := ClearNetwork.new(terrain,false)
    sampler.network = clear
    var data := sampler.crossing(Vector2(1000,700),Vector2.RIGHT)
    assert(not data.is_empty(),"Gentle river shore did not create paired docks")
    assert(data.docks.size()==2 and data.lane[0].distance_to(data.lane[1])>100)
    terrain.steep = true
    assert(sampler.crossing(Vector2(1000,700),Vector2.RIGHT).is_empty(),"Dock accepted a steep bank")
    terrain.steep = false
    terrain.island = true
    assert(sampler.crossing(Vector2(1000,700),Vector2.RIGHT).is_empty(),"Boat route crossed a dry island")
    terrain.island = false
    terrain.falls = true
    assert(sampler.crossing(Vector2(1000,700),Vector2.RIGHT).is_empty(),"Boat crossed a waterfall slope")
    terrain.falls = false
    clear.blocked = true
    assert(sampler.crossing(Vector2(1000,700),Vector2.RIGHT).is_empty(),"Dock overlapped a structure")
    clear.blocked = false
    assert(sampler.crossing(Vector2(1000,700),Vector2.RIGHT)==data,"Ferry geometry is not deterministic")
    var ferry := FerryCrossing.new()
    ferry.configure(terrain,data)
    root.add_child(ferry)
    ferry.set_physics_process(false)
    await physics_frame
    await physics_frame
    var point: Vector2 = data.docks[0].tip
    var hit := root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(point.x,5,point.y),Vector3(point.x,-5,point.y),1))
    assert(not hit.is_empty(),"Dock has no physical deck")
    var player: FirstPersonPlayer = load("res://actors/player/first_person_player.tscn").instantiate()
    root.add_child(player)
    player.initialize_environment(terrain)
    player.set_physics_process(false)
    player.global_position = Vector3(point.x,data.docks[0].height,point.y)
    var original_mask := player.collision_mask
    var interaction := FerryInteraction.new()
    interaction.initialize(player)
    root.add_child(interaction)
    var berth: Vector2 = data.docks[0].berth
    player.get_view_camera().look_at(Vector3(berth.x,.5,berth.y))
    await physics_frame
    await physics_frame
    assert(not interaction._target().is_empty(),"Boat interaction ray did not find the ferry from its dock")
    var use := InputEventAction.new()
    use.action = "Interact"
    use.pressed = true
    player.set_physics_process(true)
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    if DisplayServer.get_name()=="headless":
        assert(ferry.request(player,0)) # Headless drivers cannot capture a mouse.
    else: interaction._unhandled_input(use)
    player.set_physics_process(false)
    assert(player.water_transport==ferry,"Interact must board immediately")
    ferry._physics_process(.1)
    assert(player.water_transport==ferry and player.collision_mask==0)
    assert(ferry.save_position(player)==ferry.landing(0),"Mid-crossing save would restore the player in water")
    ferry._physics_process(2)
    ferry._physics_process(3)
    assert(ferry.moving and player.global_position.x>data.docks[0].tip.x)
    for i in range(30): ferry._physics_process(1)
    assert(player.water_transport==null and ferry.side==1 and player.collision_mask==original_mask)
    assert(player.global_position.distance_to(ferry.landing(1))<.01,"Player did not disembark on the opposite dock")
    # Both docks keep three idle boats even while other vessels sail.
    for end in range(2):
        var idle := 0
        for vessel in ferry.vessels:
            if not vessel.moving and vessel.side==end: idle+=1
        assert(idle==FerryCrossing.WAITING_BOATS_PER_SIDE)
    player.global_position = Vector3(point.x,data.docks[0].height,point.y)
    assert(ferry.request(player,0))
    assert(player.water_transport==ferry,"Opposite-side arrivals must not make a player wait")
    ferry.release(player,0)
    ferry.moving = false
    ferry.side = 0
    ferry.dwell = 0
    LootSession.records.clear()
    var npc := Villager.new()
    npc.ferry_route = ferry
    npc.configure(terrain,{"role":"traveller","model":0,"seed":345618,"start":0,"route":[data.docks[0].land,data.docks[0].tip,data.docks[1].land,data.docks[1].tip]})
    ferry.add_child(npc)
    npc._waypoint = 1
    npc._wait = 0
    npc.world_position = Vector3(point.x,data.docks[0].height+.04,point.y)
    npc.global_position = npc.world_position
    npc._profile__physics_process(.1)
    ferry._physics_process(.1)
    assert(npc.ferry_riding==ferry,"NPC did not board using its normal route logic")
    npc.set_active(true)
    assert(npc.collision_mask==0,"Population activation restored collisions during a boat trip")
    for i in range(22): ferry._physics_process(1)
    assert(npc.ferry_riding==null and npc._waypoint==2 and npc.world_position.distance_to(ferry.landing(1))<.01)
    # Rebase mid-trip without changing world-space passenger placement.
    npc.world_position = Vector3(data.docks[1].tip.x,data.docks[1].height,data.docks[1].tip.y)
    npc.global_position = npc.world_position
    assert(ferry.request(npc,1))
    ferry._physics_process(.1)
    player.global_position = Vector3(data.docks[0].tip.x,data.docks[0].height,data.docks[0].tip.y)
    assert(ferry.request(player,0))
    assert(player.water_transport==ferry and npc.ferry_riding==ferry and ferry.riders.size()==2,"Both banks must board simultaneously without waiting")
    assert(ferry.save_position(player)==ferry.landing(0) and ferry.save_position(npc)==ferry.landing(1))
    terrain._world_origin_offset = Vector2(32768,32768)
    ferry._physics_process(2)
    assert(terrain.local_to_world_position(npc.global_position).distance_to(npc.world_position)<.01)
    ferry.release(npc,1)
    ferry.release(player,0)
    terrain._world_origin_offset = Vector2.ZERO
    ferry.waiting.clear()
    ferry.moving = false
    ferry.side = 0
    ferry.dwell = 0
    ferry.progress = 0
    ferry.sail_speed = 80
    npc.world_position = ferry.landing(0)
    npc.global_position = npc.world_position
    npc._waypoint = 1
    npc._wait = 0
    npc._state = "walk"
    ferry.set_physics_process(true)
    var boarded := false
    var arrived := false
    for frame in range(1800):
        await physics_frame
        if npc.ferry_riding==ferry: boarded = true
        if boarded and npc.ferry_riding==null and npc.world_position.distance_to(ferry.landing(1))<2:
            arrived = true
            break
    assert(boarded and arrived,"NPC could not walk up its physical dock and complete an automatic crossing")
    ferry.set_physics_process(false)
    var network := WorldPathNetwork.for_terrain(terrain)
    var empty_roads: Array[Dictionary] = []
    network._chunks[Vector2i(3,2)] = empty_roads
    network.extra_routes["test"] = [network.route([Vector2(780,700),Vector2(900,700)],1.1,1.8,"dock_approach")]
    for i in range(20): assert(network.get_local_mask(Vector2(850,700))>.99)
    assert(network._chunks[Vector2i(3,2)].is_empty(),"Dock approach sampling mutated the base road cache")
    assert(network.routes_in_chunk(Vector2i(3,2)).size()==1)
    var system := FerrySystem.new()
    system.initialize(terrain,player)
    root.add_child(system)
    system._spawn(data)
    assert(system.crossings.size()==1)
    assert(system.crossings[data.key].passengers.is_empty(),"Passengers spawned without settlement destinations")
    var first: Vector2 = data.docks[0].land
    var second: Vector2 = data.docks[1].land
    var origin: Vector2 = first-Vector2(24,0)
    var destination: Vector2 = second+Vector2(24,0)
    var road_a := network.route([first,origin],1.2,2.0,"connection")
    var road_b := network.route([second,destination],1.2,2.0,"connection")
    var plan := {"roads":[road_a,road_b],"settlements":[{"position":origin,"kind":"town"},{"position":destination,"kind":"city"}]}
    system._install_journey(system.crossings[data.key],plan)
    assert(system.crossings[data.key].passengers.size()==2 and network.extra_routes.has(data.key+":deck"))
    var traveller: Villager = system.crossings[data.key].passengers[0]
    assert(traveller.route[0]==origin and traveller.route.back()==destination)
    assert(traveller.journey.destination_kind=="city")
    npc.set_active(false)
    player.global_position += Vector3(0,0,12)
    traveller._wait = 0
    traveller._state = "walk"
    var boarded_journey := false
    var completed_journey := false
    Engine.time_scale = 5.0
    for frame in range(1200):
        await physics_frame
        if traveller.ferry_riding!=null: boarded_journey = true
        if boarded_journey and traveller._visit_remaining>0 and Vector2(traveller.world_position.x,traveller.world_position.z).distance_to(destination)<1:
            completed_journey = true
            break
    Engine.time_scale = 1.0
    if not completed_journey:
        print("Incomplete journey: position=",traveller.world_position," waypoint=",traveller._waypoint," direction=",traveller._travel_direction," riding=",traveller.ferry_riding!=null," visit=",traveller._visit_remaining," boat=",system.crossings[data.key].side," destination=",destination)
    assert(completed_journey,"Traveller failed to walk to the dock, sail and continue to its settlement")
    traveller.set_active(false)
    traveller._visit_remaining = 0
    traveller.ferry_arrived(1)
    assert(traveller._waypoint==traveller.journey.land_indexes[1])
    traveller._advance_route()
    assert(traveller.route[traveller._waypoint]==destination,"Disembarking did not continue to the settlement")
    traveller._advance_route()
    assert(traveller._waypoint==traveller.route.size()-1,"Open journey wrapped across water")
    traveller.world_position = Vector3(destination.x,terrain.get_height_at(destination)+.04,destination.y)
    traveller._wait = 0
    traveller._profile__physics_process(.1)
    assert(traveller._visit_remaining>=25 and traveller._travel_direction==-1,"Settlement arrival did not start a visit")
    traveller.persist_journey()
    var encoded = SaveCodec.encode(traveller._loot_record)
    assert(SaveCodec.valid(encoded),"Journey state cannot be saved")
    assert(SaveCodec.decode(encoded).journey.key==data.key)
    var resumed := Villager.new()
    resumed.ferry_route = system.crossings[data.key]
    resumed.configure(terrain,{"role":"traveller","model":0,"seed":absi(data.seed),"start":0,"route":traveller.route,"journey":traveller.journey})
    assert(resumed.world_position==traveller.world_position and resumed._travel_direction==-1 and resumed._visit_remaining==traveller._visit_remaining,"Streaming reset the settlement journey")
    resumed.free()
    var nearby := shifted_crossing(data,Vector2(0,50),"nearby")
    assert(FerrySampler.conflicts(data,nearby),"Parallel nearby docks accepted")
    system._spawn(nearby)
    assert(system.crossings.size()==1,"Overlapping docks spawned")
    # One shared bank alone must reject the crossing, even with reversed order.
    var shared := shifted_crossing(data,Vector2(0,1000),"shared")
    shared.docks[0] = data.docks[0].duplicate(true)
    shared.docks.reverse()
    assert(FerrySampler.conflicts(data,shared),"Shared landing with reversed banks accepted")
    system._spawn(shared)
    assert(system.crossings.size()==1)
    var distant := shifted_crossing(data,Vector2(0,500),"distant")
    assert(not FerrySampler.conflicts(data,distant),"Well separated crossing rejected")
    var intersecting := shifted_crossing(data,Vector2(0,1000),"intersecting")
    var midpoint: Vector2 = (data.lane[0]+data.lane[1])*.5
    intersecting.lane = [midpoint+Vector2(0,-1000),midpoint+Vector2(0,1000)]
    assert(FerrySampler.conflicts(data,intersecting),"Intersecting boat lanes accepted")
    system.queue_free()
    FileAccess.open("/tmp/upper-sky-ferry-preview.dat",FileAccess.WRITE).store_var(data)
    player.queue_free()
    interaction.queue_free()
    ferry.queue_free()
    await process_frame
    terrain.free()
    print("PASS ferry density, dock spacing/shared-bank rejection, sailing-lane separation, shore validation, player/NPC crossings and masks")
    quit()
