extends SceneTree
func _initialize(): run.call_deferred()
func run():
    var world = load("res://world/environments/basic_world.tscn").instantiate()
    root.add_child(world)
    world.set_process(false)
    var terrain = world.get_node("Terrain")
    terrain.set_process(false)
    var sampler = VillagerPopulationSampler.new(terrain)
    assert(sampler._traveller_model(3) == 7)
    var route: Array[Vector2] = [Vector2.ZERO, Vector2(8,0)]
    var npc = Villager.new()
    npc.configure(terrain, {"role":"traveller", "model":7, "seed":123456, "start":0, "route":route})
    world.add_child(npc)
    npc.set_physics_process(false)
    npc.set_process(false)
    assert(npc.affection.get_score() == 100.0)
    assert(npc.get_loot_title() == "Wizard's belongings")
    var library = npc._animation.get_animation_library("Quaternius")
    for clip in Villager.CLIPS.values():
        assert(library.has_animation(clip))
        npc._animation.play("Quaternius/"+clip)
        npc._animation.advance(0.1)
        for bone in range(npc._rig.get_bone_count()):
            assert(npc._rig.get_bone_global_pose(bone).origin.is_finite())
    world.free()
    print("PASS wizard spawning, neutral affection and shared animation clips")
    quit()
