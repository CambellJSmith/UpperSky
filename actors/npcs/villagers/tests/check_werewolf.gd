extends SceneTree
func _initialize(): run.call_deferred()
func run():
    LootSession.records.clear()
    var world = load("res://world/environments/basic_world.tscn").instantiate()
    root.add_child(world)
    world.set_process(false)
    var terrain = world.get_node("Terrain")
    terrain.set_process(false)
    var carrier_seed := 0
    var count := 0
    for seed_value in range(10000):
        if Villager.werewolf_seed(seed_value):
            count += 1
            carrier_seed = seed_value
    assert(count > 130 and count < 270)
    var route: Array[Vector2] = [Vector2.ZERO, Vector2(8,0)]
    var definition := {"role":"traveller","model":0,"seed":carrier_seed,"route":route,"start":0}
    world.set_time_of_day_hours(12)
    var npc = Villager.new()
    npc.configure(terrain,definition)
    world.add_child(npc)
    npc.set_process(false)
    npc.set_physics_process(false)
    npc.affection.set_score(73.5)
    var before: Vector3 = npc.world_position
    world.set_time_of_day_hours(18)
    npc._update_werewolf_form()
    assert(npc.model_index == 8 and npc.affection.get_score() == 0)
    assert(npc.world_position == before)
    var library = npc._animation.get_animation_library("Quaternius")
    for clip in Villager.CLIPS.values(): assert(library.has_animation(clip))
    npc.free()
    npc = Villager.new()
    npc.configure(terrain,definition)
    world.add_child(npc)
    npc.set_process(false)
    npc.set_physics_process(false)
    assert(npc.model_index == 8 and npc.affection.get_score() == 0)
    world.set_time_of_day_hours(6)
    npc._update_werewolf_form()
    assert(npc.model_index == 0 and npc.affection.get_score() == 73.5)
    world.free()
    print("PASS rare carriers, sunset transformation, animation clips, streaming and sunrise affection restoration")
    quit()
