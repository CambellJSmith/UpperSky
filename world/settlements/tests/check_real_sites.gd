extends SceneTree
func _initialize(): run.call_deferred()
func run():
    var terrain = SeamlessInfiniteTerrain.new()
    root.add_child(terrain)
    var sampler = SettlementSampler.new(terrain)
    var towns = 0
    var homes = 0
    for z in range(-2,3):
        for x in range(-2,3):
            var town = sampler.sample_town(Vector2i(x,z))
            if town.is_empty(): continue
            towns += 1
            assert(town["houses"].size() >= 8)
            for house in town["houses"]:
                assert(not sampler._house_patch(house["position"],house["yaw"],house["recipe"],1.35,.18).is_empty())
            # Road geometry is checked by world/paths/tests/check_network.gd.
            var furniture = SettlementGeometry.new().build_furniture(sampler,town)
            assert(furniture.get_child_count() == 1)
            assert(furniture.get_child(0).name == "VillageWell")
            furniture.free()
    for z in range(-8,9):
        for x in range(-8,9):
            var home = sampler.sample_homestead(Vector2i(x,z))
            if home.is_empty(): continue
            homes += 1
            assert(not sampler._house_patch(home["position"],home["yaw"],home["recipe"],.90,.13).is_empty())
    assert(towns > 0 and homes > 0)
    print("PASS: real terrain ",towns," towns and ",homes," rare homesteads; village furniture and every building footprint revalidated.")
    quit()
