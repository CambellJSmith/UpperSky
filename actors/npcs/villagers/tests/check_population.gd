extends SceneTree
func _initialize(): run.call_deferred()
func run():
    var world = load("res://world/environments/basic_world.tscn").instantiate()
    root.add_child(world)
    world.set_process(false)
    var terrain = world.get_node("Terrain")
    terrain.set_process(false)
    var sampler = VillagerPopulationSampler.new(terrain)
    var settlements = sampler._settlements
    var town = settlements.find_nearby(Vector2.ZERO,"town")
    var home = settlements.find_nearby(Vector2.ZERO,"home")
    var residents = sampler.town(town)
    var homesteaders = sampler.home(home)
    assert(residents.size() == 6,"Town street route was rejected")
    assert(homesteaders.size() == 1,"Cottage yard route was rejected")
    var travellers = 0
    for z in range(-4,5):
        for x in range(-4,5):
            var first = sampler.travellers(Vector2i(x,z))
            var second = sampler.travellers(Vector2i(x,z))
            assert(first == second)
            for definition in first:
                assert(sampler.route_safe(definition.route))
                travellers += 1
    assert(travellers > 0)
    var moving = 0
    for model in range(7):
        var definition: Dictionary = residents[model%residents.size()].duplicate()
        definition.model = model
        var npc = Villager.new()
        npc.configure(terrain,definition)
        world.add_child(npc)
        npc.set_physics_process(false)
        npc.set_process(false)
        var library: AnimationLibrary = npc._animation.get_animation_library("Quaternius")
        assert(library.get_animation_list().size() == 10)
        var signatures: Dictionary = {}
        for action in Villager.CLIPS:
            var clip: Animation = library.get_animation(Villager.CLIPS[action])
            assert(clip != null)
            for track in range(clip.get_track_count()):
                var bone = npc._rig.find_bone(clip.track_get_path(track).get_subname(0))
                assert(bone >= 0)
                if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
                    for key in range(clip.track_get_key_count(track)):
                        var q: Quaternion = clip.track_get_key_value(track,key)
                        assert(absf(q.length()-1) < .0001)
            npc._animation.play("Quaternius/"+Villager.CLIPS[action],0)
            npc._animation.advance(0)
            npc._animation.seek(clip.length*.35,true)
            npc._ground_feet()
            for bone in range(npc._rig.get_bone_count()): assert(npc._rig.get_bone_global_pose(bone).origin.is_finite())
            var rotations: Array = []
            for bone in range(npc._rig.get_bone_count()): rotations.append(npc._rig.get_bone_pose_rotation(bone))
            var signature = hash(rotations)
            assert(not signatures.has(signature),"Two actions produced the same pose")
            signatures[signature] = true
            npc._animation.stop()
        assert(npc.perform_action("punch"))
        assert(not npc.perform_action("kick"))
        npc._action_remaining = 0
        assert(npc.perform_action("kick"))
        assert(not npc.perform_action("other"))
        npc._action_remaining = 0
        npc._wait = 0
        npc._waypoint = (definition.start+1)%definition.route.size()
        npc._state = "walk"
        var start: Vector3 = npc.world_position
        for i in range(90): npc._physics_process(1.0/60.0)
        assert(npc.world_position.distance_to(start) > .5)
        moving += 1
        npc.free()
    world.free()
    print("PASS: six village residents, isolated-home resident, ",travellers," dry wilderness routes, deterministic sampling, seven rigs with ten valid quaternion clips, actions and actual walking.")
    quit()
