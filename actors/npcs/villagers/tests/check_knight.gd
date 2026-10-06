extends SceneTree
func _initialize(): run.call_deferred()
func run():
    LootSession.records.clear()
    var world = load("res://world/environments/basic_world.tscn").instantiate()
    root.add_child(world)
    world.set_process(false)
    var terrain = world.get_node("Terrain")
    terrain.set_process(false)
    var sampler = VillagerPopulationSampler.new(terrain)
    assert(sampler._traveller_model(4) == 9)
    var town = sampler._settlements.find_nearby(Vector2.ZERO,"town")
    var residents = sampler.town(town)
    var patrols := 0
    for definition in residents:
        if definition.model == 9:
            assert(definition.role == "knight_patrol")
            patrols += 1
    assert(patrols == 2)
    var npc = Villager.new()
    npc.configure(terrain,residents.back())
    world.add_child(npc)
    npc.set_process(false)
    npc.set_physics_process(false)
    assert(npc.affection.get_score() == 11)
    assert(not npc._werewolf_carrier)
    var library = npc._animation.get_animation_library("Quaternius")
    for clip in Villager.CLIPS.values():
        assert(library.has_animation(clip))
        npc._animation.play("Quaternius/"+clip)
        npc._animation.advance(.1)
        for bone in range(npc._rig.get_bone_count()): assert(npc._rig.get_bone_global_pose(bone).origin.is_finite())
    world.free()
    print("PASS village knight patrols, wilderness selection, 11 affection and shared animations")
    quit()
