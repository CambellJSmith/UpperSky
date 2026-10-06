extends SceneTree
func _initialize(): run.call_deferred()
func run():
    var world = load("res://world/environments/basic_world.tscn").instantiate()
    root.add_child(world)
    world.set_process(false)
    var terrain = world.get_node("Terrain")
    terrain.set_process(false)
    var network = WorldPathNetwork.for_terrain(terrain)
    var town = network._settlements.find_nearby(Vector2.ZERO,"town")
    var home = network._settlements.find_nearby(Vector2.ZERO,"home")
    var connections = 0
    for definition in [town,home]:
        var roads = network.town_routes(definition) if definition.has("houses") else network.home_routes(definition)
        for road in roads:
            if road.kind != "connection": continue
            connections += 1
            assert(TerrainPathSampler.get_wilderness_wear_mask(road.points[-1]) > .99)
            var heights: Dictionary = {}
            for i in range(road.points.size()-1):
                assert(network._edge_safe(road.points[i],road.points[i+1],definition,heights))
                var midpoint: Vector2 = road.points[i].lerp(road.points[i+1],.5)
                assert(TerrainPathSampler.get_wear_mask(midpoint,terrain) > .99)
                assert(TerrainPathSampler.get_grass_suppression(midpoint,terrain) > .99)
    assert(connections == 2,"Town or home did not connect to a regional path")
    var second = WorldPathNetwork.new(terrain)
    assert(second.town_routes(town) == network.town_routes(town))
    assert(second.home_routes(home) == network.home_routes(home))
    var population = VillagerPopulationSampler.new(terrain)
    for definition in population.town(town)+population.home(home):
        for p in definition.route: assert(TerrainPathSampler.get_wear_mask(p,terrain) > .99)
    var builder = PathMeshBuilder.new(terrain)
    var chunks: Dictionary = {}
    for road in network.town_routes(town):
        for p in road.points: chunks[Vector2i(floori(p.x/256),floori(p.y/256))] = true
    var vertices = 0
    for cell in chunks:
        var mesh = builder.build(cell)
        assert(mesh != null)
        for vertex in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
            assert(vertex.is_finite())
            assert(vertex.x >= -.01 and vertex.x <= 256.01 and vertex.z >= -.01 and vertex.z <= 256.01)
            var point = Vector2(vertex.x,vertex.z)+Vector2(cell)*256
            assert(absf(vertex.y-network._settlements.ground_height(point)-.035) < .015)
            vertices += 1
    world.free()
    print("PASS: town and home connections, dry graded routes, deterministic network, shared wear/vegetation/NPC routes, ",vertices," terrain-conforming clipped mesh vertices.")
    quit()
