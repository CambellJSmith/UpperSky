extends SceneTree
class FlatTerrain extends InfiniteTerrain:
    func _ready(): pass
    func get_height_at(_point: Vector2) -> float: return 0.0
    func has_water_at(_point: Vector2) -> bool: return false
    func get_loaded_chunk_count() -> int: return 9
class BusySampler extends VillagerPopulationSampler:
    var blocked := true
    func travellers_incremental(_cell: Vector2i,scheduler: GenerationScheduler) -> Array[Dictionary]:
        while blocked:
            if not await scheduler.checkpoint(): return []
        return []
class ExistingTraveller extends Villager:
    func _ready():
        set_process(false)
        set_physics_process(false)
func _initialize(): run.call_deferred()
func run():
    LootSession.records.clear()
    var game := Node3D.new()
    var world := Node3D.new()
    world.name="World"
    game.add_child(world)
    var terrain := FlatTerrain.new()
    terrain.name="Terrain"
    world.add_child(terrain)
    var entities := Node3D.new()
    entities.name="DynamicEntities"
    game.add_child(entities)
    var player: FirstPersonPlayer = load("res://actors/player/first_person_player.tscn").instantiate()
    player.name="Player"
    entities.add_child(player)
    var settlements := SettlementStreamer.new()
    settlements.name="Settlements"
    world.add_child(settlements)
    var population := VillagerPopulationStreamer.new()
    population.name="Villagers"
    world.add_child(population)
    root.add_child(game)
    settlements.set_process(false)
    population.set_process(false)
    player.set_physics_process(false)
    var sampler := BusySampler.new(terrain)
    population._sampler=sampler
    var town: Dictionary = {}
    for z in range(-2,3):
        for x in range(-2,3):
            var candidate := sampler._settlements.sample_town(Vector2i(x,z))
            if not candidate.is_empty() and not CityGeometry.is_city(candidate): town=candidate; break
        if not town.is_empty(): break
    assert(not town.is_empty())
    var cell := Vector2i((town.position/SettlementSampler.TOWN_CELL_SIZE).floor())
    var town_root := Node3D.new()
    town_root.set_meta("definition",town)
    settlements.add_child(town_root)
    settlements._towns[cell]=town_root
    for i in range(VillagerPopulationStreamer.TRAVELLER_LIMIT):
        var traveller := ExistingTraveller.new()
        traveller.role="traveller"
        traveller.set_meta("spawn_seed",-100-i)
        population.add_child(traveller)
    var route: Array[Vector2] = [town.position,town.position+Vector2(5,0)]
    var extra: Array[Dictionary] = [{"role":"traveller","model":0,"seed":99888899,"route":route,"start":0}]
    population._spawn("extra-road-traffic",extra,town.position)
    assert(population.get_child_count()==VillagerPopulationStreamer.TRAVELLER_LIMIT,"Travellers must leave slots for local residents")
    var scheduler := GenerationScheduler.new()
    root.add_child(scheduler)
    player.global_position=Vector3(town.position.x,5,town.position.y)
    player.set_fly_mode_enabled(true)
    player.set_physics_process(true)
    population._profile__process(1.1)
    var deadline := Time.get_ticks_msec()+20000
    while Time.get_ticks_msec()<deadline and population.get_child_count()<VillagerPopulationStreamer.TRAVELLER_LIMIT+8:
        await process_frame
    var residents := 0
    var guards := 0
    for npc in population.get_children():
        if npc.role=="resident": residents+=1
        if npc.role=="knight_patrol": guards+=1
    var road_still_pending: bool = population._refreshing
    sampler.blocked=false
    for i in range(8): await process_frame
    game.queue_free()
    scheduler.queue_free()
    await process_frame
    assert(road_still_pending and residents==6 and guards==2,"Town locals must spawn despite a full traveller allowance and blocked road update")
    print("PASS six town residents and two guards spawn with 48 travellers already present while road validation remains pending")
    quit()
