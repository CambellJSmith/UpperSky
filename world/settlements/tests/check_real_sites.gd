extends SceneTree
func _initialize(): run.call_deferred()
func run():
    var terrain = SeamlessInfiniteTerrain.new()
    root.add_child(terrain)
    var sampler = SettlementSampler.new(terrain)
    var towns = 0
    var homes = 0
    var cities = 0
    var nearest = INF
    for z in range(-4,6):
        for x in range(-4,6):
            var town = sampler.sample_town(Vector2i(x,z))
            if town.is_empty(): continue
            towns += 1
            if CityGeometry.is_city(town): cities += 1
            nearest = minf(nearest,town.position.length())
            assert(town["houses"].size() >= 8)
            for house in town["houses"]:
                assert(not sampler._house_patch(house["position"],house["yaw"],house["recipe"],1.35,.18).is_empty())
            # Road geometry is checked by world/paths/tests/check_network.gd.
            var furniture = SettlementGeometry.new().build_furniture(sampler,town)
            assert(furniture.get_child_count() == 1)
            assert(furniture.get_child(0).name == "VillageWell")
            furniture.free()
    for z in range(-16,18):
        for x in range(-16,18):
            var home = sampler.sample_homestead(Vector2i(x,z))
            if home.is_empty(): continue
            homes += 1
            assert(not sampler._house_patch(home["position"],home["yaw"],home["recipe"],.90,.13).is_empty())
    assert(towns >= 50 and homes >= 150 and cities >= 10)
    print("SURVEY ",towns," towns ",homes," homes ",cities," cities; nearest ",nearest)
    print("PASS: real terrain ",towns," towns and ",homes," homesteads, ",cities," cities; nearest settlement ",nearest," metres; village furniture and every building footprint revalidated.")
    quit()
