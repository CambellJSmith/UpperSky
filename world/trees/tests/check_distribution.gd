extends SceneTree
func _initialize(): run.call_deferred()
func run():
    var world = load("res://world/environments/basic_world.tscn").instantiate()
    root.add_child(world)
    var terrain = world.get_node("Terrain")
    terrain.set_process(false)
    var sampler = WorldDecorationSampler.new(terrain)
    var home = sampler._settlement_sampler.find_nearby(Vector2.ZERO,"home")
    var centre = Vector2i(floori(home.position.x/TerrainConfiguration.CHUNK_SIZE),floori(home.position.y/TerrainConfiguration.CHUNK_SIZE))
    var forms: Dictionary = {}
    var trees = 0
    for z in range(-2,3):
        for x in range(-2,3):
            var cell = centre+Vector2i(x,z)
            var first = sampler.sample_chunk(cell,3)
            var second = sampler.sample_chunk(cell,3)
            assert(first.size() == second.size())
            for i in range(first.size()):
                assert(first[i].transform == second[i].transform and first[i].variant == second[i].variant)
                if first[i].kind != WorldDecorationPlacement.Kind.TREE: continue
                var origin: Vector3 = first[i].transform.origin
                var point = Vector2(origin.x,origin.z)+Vector2(cell)*TerrainConfiguration.CHUNK_SIZE
                assert(absf(origin.y-sampler._camp_sampler.ground_height(point)) < .001)
                assert(not sampler._settlement_sampler.is_clearing(point,8.0))
                var species = TreeGeometry.species_of(first[i].variant)
                if species == TreeGeometry.Species.WILLOW:
                    assert(origin.y-terrain.get_water_level_at(point) < 32.0)
                forms[first[i].variant] = true
                trees += 1
    assert(trees > 20 and forms.size() >= 4)
    world.free()
    print("PASS: ",trees," trees across 25 terrain chunks; ",forms.size()," forms, repeatable placement, grounded roots, settlement clearance and shoreline willows.")
    quit()
