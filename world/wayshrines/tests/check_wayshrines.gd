extends SceneTree
func _initialize(): run.call_deferred()
func run():
    var game = load("res://application/game/game.tscn").instantiate()
    root.add_child(game)
    for child in game.get_children():
        if child.name not in ["World","DynamicEntities","WayshrineInteraction"]: child.set_process(false)
    for child in game.get_node("World").get_children(): child.set_process(false)
    for frame in range(8): await physics_frame
    var player = game.get_node("DynamicEntities/Player")
    while not player.is_physics_processing(): await physics_frame
    player.set_physics_process(false)
    var terrain = game.get_node("World/Terrain")
    var sampler = WayshrineSampler.for_terrain(terrain)
    var definitions: Array[Dictionary] = []
    for z in range(-2,3):
        for x in range(-2,3):
            var cell = Vector2i(x,z)
            var definition = sampler.sample_cell(cell)
            assert(definition == sampler.sample_cell(cell))
            if definition.is_empty(): continue
            definitions.append(definition)
            var p = Vector2(definition.position.x,definition.position.z)
            assert(sampler.suitable(p) and sampler.is_clearing(p))
            assert(not terrain.has_water_at(Vector2(definition.landing.x,definition.landing.z)))
    assert(definitions.size() >= 2,"Too few usable shrine locations")
    var streamer = game.get_node("World/Wayshrines")
    var ui = game.get_node("WayshrineInteraction")
    var first: Wayshrine = streamer.ensure_cell(definitions[0].id)
    player.global_position = terrain.world_to_local_position(definitions[0].landing)
    terrain._rebase_world_if_needed()
    terrain.initialize(player,game.get_node("DynamicEntities"))
    streamer._process(0)
    await physics_frame
    player.set_physics_process(true)
    assert(ui.open_shrine(first))
    assert(WayshrineRegistry.is_activated(definitions[0].id))
    assert(ui._list.item_count == 0 and ui._travel_button.disabled)
    assert(not await ui.travel_to(definitions[1].id),"Travelled to locked shrine")
    assert(not await ui.travel_to(definitions[0].id),"Travelled to current shrine")
    assert(WayshrineRegistry.activate(definitions[1]))
    assert(not WayshrineRegistry.activate(definitions[1]),"Duplicate discovery")
    ui.close_menu()
    assert(ui.open_shrine(first) and ui._list.item_count == 1)
    var arrival: bool = await ui.travel_to(definitions[1].id)
    assert(arrival,"Collision-safe teleport failed")
    var position: Vector3 = terrain.local_to_world_position(player.global_position)
    assert(Vector2(position.x,position.z).distance_to(Vector2(definitions[1].landing.x,definitions[1].landing.z)) < .01)
    assert(absf(position.y-definitions[1].landing.y) < .5)
    assert(player.velocity == Vector3.ZERO and player.is_physics_processing())
    assert(player.global_position.length() < 3000,"Travel did not rebase origin")
    ui.close_menu()
    var second: Wayshrine = streamer.ensure_cell(definitions[1].id)
    streamer._process(0)
    assert(ui.open_shrine(second))
    assert(WayshrineRegistry.destinations(definitions[1].id).size() == 1)
    assert(await ui.travel_to(definitions[0].id),"Return teleport failed")
    ui.close_menu()
    # Rebuilding a streamed shrine restores its awakened appearance.
    var rebuilt = Wayshrine.new()
    rebuilt.definition = definitions[1]
    game.get_node("World").add_child(rebuilt)
    assert(rebuilt._active and rebuilt._glow.emission_energy_multiplier > 2)
    # Camera-ray interaction and solid cover, using the actual shrine collider.
    player.set_physics_process(false)
    rebuilt.global_position = player.global_position+Vector3(0,0,-2)
    rebuilt.rotation.y = 0
    player.rotation = Vector3.ZERO
    player.get_node("Head").rotation = Vector3.ZERO
    await physics_frame
    player.set_physics_process(true)
    assert(ui._ray_target() == rebuilt)
    var wall = StaticBody3D.new()
    var shape = CollisionShape3D.new()
    var box = BoxShape3D.new()
    box.size = Vector3(4,5,.1)
    shape.shape = box
    wall.add_child(shape)
    game.add_child(wall)
    wall.global_position = player.global_position+Vector3(0,1,-.6)
    await physics_frame
    assert(ui._ray_target() == null,"Activated shrine through a wall")
    # Populate empty cache entries to check the bound without generating 200 remote road regions.
    for cell in range(128): sampler._cache[Vector2i(cell,20)] = {}
    sampler.sample_cell(Vector2i(201,20))
    assert(sampler._cache.size() <= 128)
    game.queue_free()
    await process_frame
    print("PASS deterministic flat/dry placement, first activation, locked/current destination rejection, menu destinations, safe long-distance return travel, rebasing, streaming discovery, ray targeting and cover, bounded cache")
    quit()
