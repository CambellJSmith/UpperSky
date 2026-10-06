extends SceneTree
var changes: Array = []
func _initialize(): run.call_deferred()
func run():
    var state = AffectionState.new()
    state.changed.connect(func(previous, current): changes.append([previous,current]))
    assert(state.score == 100)
    state.change_score(-150)
    assert(state.score == 0 and changes == [[100.0,0.0]])
    state.set_score(-1)
    assert(changes.size() == 1)
    state.score = 300
    assert(state.get_score() == 200)
    state.set_score(NAN)
    state.change_score(INF)
    assert(state.score == 200 and changes.size() == 2)
    state.change_score(-.5)
    assert(state.score == 199.5)
    LootSession.records.clear()
    var world = load("res://world/environments/basic_world.tscn").instantiate()
    root.add_child(world)
    world.set_process(false)
    var terrain = world.get_node("Terrain")
    terrain.set_process(false)
    var dungeon = ProceduralDungeonWorld.new()
    dungeon._region_coordinate = Vector2i(9,3)
    dungeon._pair_id = 2
    var expected = [100.0,100.0,50.0,0.0,25.0,0.0,0.0]
    for model in range(7):
        var definition = {"model":model,"role":"affection_test","seed":900+model,"route":[Vector2.ZERO,Vector2(8,0)]}
        for cave in [false,true]:
            var npc = Villager.new()
            if cave: npc.configure_cave(dungeon,definition)
            else: npc.configure(terrain,definition)
            assert(npc.get_affection() == expected[model])
            npc.set_affection(137)
            var retained = npc.affection
            npc.free()
            var reloaded = Villager.new()
            if cave: reloaded.configure_cave(dungeon,definition)
            else: reloaded.configure(terrain,definition)
            assert(reloaded.get_affection() == 137 and reloaded.affection == retained)
            reloaded.change_affection(-7)
            assert(reloaded.get_affection() == 130)
            reloaded.free()
    var billboard = BillboardNpc3D.new()
    assert(billboard.get_affection() == 100)
    billboard.change_affection(30)
    assert(billboard.get_affection() == 130)
    billboard.free()
    dungeon.free()
    world.queue_free()
    await process_frame
    print("PASS affection bounds, notifications, all seven species, overworld/cave persistence and generic NPC API")
    quit()
