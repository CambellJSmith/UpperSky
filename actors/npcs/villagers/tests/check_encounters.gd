extends SceneTree

class FlatTerrain extends InfiniteTerrain:
    func _ready(): pass
    func get_height_at(_point: Vector2) -> float: return 0.0
    func has_water_at(_point: Vector2) -> bool: return false

func _initialize(): run.call_deferred()

func run():
    var terrain := FlatTerrain.new()
    root.add_child(terrain)
    terrain.set_process(false)
    var sampler := VillagerPopulationSampler.new(terrain)
    var town := sampler._settlements.find_nearby(Vector2.ZERO,"town")
    var road_centre := Vector2i((town.position/VillagerPopulationSampler.TRAVEL_CELL).floor())
    var kinds := {}
    var groups := {}
    var total := 0
    var all_definitions: Array[Dictionary] = []
    for z in range(-2,3):
        for x in range(-2,3):
            var cell := road_centre+Vector2i(x,z)
            var definitions := sampler.travellers(cell)
            assert(definitions == sampler.travellers(cell))
            for definition in definitions:
                var duplicate := false
                for existing in all_definitions:
                    if existing.seed==definition.seed: duplicate = true; break
                if duplicate: continue
                all_definitions.append(definition)
                assert(sampler.route_safe(definition.route,false))
                assert(not definition.journey.is_empty())
                assert(definition.role == "traveller" and definition.model in [0,1,2,7,9])
                kinds[definition.encounter] = true
                groups[definition.leader_seed] = groups.get(definition.leader_seed,0)+1
                total += 1
    assert(total > 5 and not kinds.has("explorers"))
    var parties := 0
    for size in groups.values():
        assert(size>=1 and size<=5)
        if size>1: parties += 1
    assert(parties>=2)
    var common := 0
    for definition in all_definitions:
        if definition.model in [0,1,2]: common += 1
        if definition.seed==definition.leader_seed: assert(definition.model in [0,1,2])
    assert(common>total*.75,"Road traffic should predominantly be peasants and orcs")
    var wave_sampler := VillagerPopulationSampler.new(terrain)
    var before := wave_sampler.travellers(road_centre)
    wave_sampler.set_traffic_wave(1)
    var after := wave_sampler.travellers(road_centre)
    assert(not before.is_empty() and not after.is_empty())
    for definition in after:
        for old in before: assert(definition.seed!=old.seed,"Traffic must replenish after previous travellers have passed")
        var same_road := false
        for old in before:
            if definition.journey.key==old.journey.key and definition.route==old.route: same_road=true
        assert(same_road,"New waves must keep real settlement journeys")

    var scheduler := GenerationScheduler.new()
    root.add_child(scheduler)
    var fresh := VillagerPopulationSampler.new(terrain)
    assert(await fresh.travellers_incremental(road_centre,scheduler) == sampler.travellers(road_centre))
    # Existing groups can gain missing members without duplicating their leader.
    var party: Array[Dictionary] = []
    var chosen := 0
    for key in groups:
        if groups[key]>=3: chosen = key; break
    for definition in all_definitions:
        if definition.leader_seed == chosen: party.append(definition)
    assert(party.size()>=3)
    var game := Node3D.new()
    var world := Node3D.new(); world.name = "World"
    terrain.reparent(world)
    terrain.name = "Terrain"
    var dynamic := Node3D.new(); dynamic.name = "DynamicEntities"
    var player: FirstPersonPlayer = load("res://actors/player/first_person_player.tscn").instantiate()
    player.name = "Player"
    dynamic.add_child(player)
    game.add_child(dynamic)
    game.add_child(world)
    var settlements := SettlementStreamer.new()
    settlements.name = "Settlements"
    world.add_child(settlements)
    var streamer := VillagerPopulationStreamer.new()
    streamer.name = "Villagers"
    world.add_child(streamer)
    root.add_child(game)
    player.set_physics_process(false)
    settlements.set_process(false)
    streamer.set_process(false)
    var origin: Vector2 = party[0].route[party[0].start]
    var partial: Array[Dictionary] = []
    partial.assign(party.slice(0,2))
    streamer._spawn("test-party",partial,origin)
    assert(streamer.get_child_count()==2)
    streamer._spawn("test-party",party,origin)
    assert(streamer.get_child_count()==party.size())
    streamer._spawn("test-party",party,origin)
    assert(streamer.get_child_count()==party.size())
    streamer._spawn("neighbouring-cell",party,origin)
    assert(streamer.get_child_count()==party.size(),"Journey duplicated across streaming cells")
    var group_leader: Villager = streamer.get_child(0)
    for member in streamer.get_children():
        member.set_physics_process(false)
        member.set_process(false)
        if member != group_leader: assert(member.follow_leader.get_ref()==group_leader)
    var companion: Villager = streamer.get_child(1)
    var before_leader := group_leader.world_position
    var before_companion := companion.world_position
    for member in streamer.get_children():
        member.set_physics_process(true)
        member._wait = 0
        member._waypoint = (party[0].start+1)%member.route.size()
        member._state = "walk"
    for frame in range(240): await physics_frame
    assert(group_leader.world_position.distance_to(before_leader)>1)
    assert(companion.world_position.distance_to(before_companion)>.5)
    assert(companion.world_position.distance_to(group_leader.world_position)<20)
    group_leader.set_physics_process(false)
    game.queue_free()
    var leader := Villager.new()
    leader.world_position = Vector3(10,0,10)
    leader._travel_trail.assign([Vector2(0,0),Vector2(5,0),Vector2(10,0),Vector2(10,5),Vector2(10,10)])
    assert(leader.trail_target(3).is_equal_approx(Vector2(10,7)))
    assert(leader.trail_target(3,Vector2.ZERO).is_equal_approx(Vector2(10,0)))
    leader.free()
    scheduler.queue_free()
    await process_frame
    print("PASS ",total," travellers, ",parties," parties, settlement destinations and solo/group journeys, dry safe routes, deterministic scheduling and following around bends")
    quit()
