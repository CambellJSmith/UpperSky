extends SceneTree
func _initialize(): run.call_deferred()
func run():
    # Placement helpers alone cannot catch populations missing from the playable scene.
    var playable = load("res://application/game/game.tscn").instantiate()
    assert(playable.get_node("World/VolcanoPopulation") is VolcanoPopulation)
    assert(playable.get_node("World/WaterPopulation") is WaterPopulation)
    playable.free()
    LootSession.records.clear()
    var game = Node3D.new()
    root.add_child(game)
    var world = load("res://world/environments/basic_world.tscn").instantiate()
    world.name = "World"
    game.add_child(world)
    world.set_process(false)
    var terrain = world.get_node("Terrain")
    terrain.set_process(false)
    var entities = Node3D.new()
    entities.name = "DynamicEntities"
    game.add_child(entities)
    var player = load("res://actors/player/first_person_player.tscn").instantiate()
    player.name = "Player"
    entities.add_child(player)
    player.set_physics_process(false)
    var volcano = VolcanoPopulation.new()
    world.add_child(volcano)
    volcano.set_process(false)
    var definitions = volcano.definitions(Vector2i(0,-1))
    assert(definitions.size() > 0)
    assert(volcano.definitions(Vector2i.ZERO).is_empty())
    assert(definitions == volcano.definitions(Vector2i(0,-1)))
    for definition in definitions:
        for point in definition.route:
            assert(not terrain.has_water_at(point) and not BiomeProfile.is_lava(point))
    var point: Vector2 = definitions[0].route[0]
    terrain._build_chunk_immediately(Vector2i(floori(point.x/256),floori(point.y/256)))
    player.global_position = terrain.world_to_local_position(Vector3(point.x,terrain.get_height_at(point)+2,point.y))
    player.set_physics_process(true)
    volcano._process(1)
    player.set_physics_process(false)
    assert(volcano.get_child_count() > 0 and volcano.get_child_count() <= 8)
    for npc in volcano.get_children():
        assert(npc.model_index == 3 and npc.health.get_health() == 100)
        npc.set_active(false)
    var fish = WaterPopulation.new()
    world.add_child(fish)
    fish.set_process(false)
    var river: Vector2 = BiomeProfile.region(Vector2i(-1,0)).centre
    var centre_cell = Vector2i(floori(river.x/512),floori(river.y/512))
    var fish_routes = 0
    var first_fish: Dictionary = {}
    for z in range(-2,3):
        for x in range(-2,3):
            var cell = centre_cell+Vector2i(x,z)
            var routes = fish.definitions(cell)
            assert(routes == fish.definitions(cell))
            for definition in routes:
                if first_fish.is_empty(): first_fish = definition
                assert(definition.model == 6 and definition.role == "fish_man")
                for step in range(9):
                    var sample: Vector2 = definition.route[0].lerp(definition.route[1],float(step)/8)
                    assert(fish.near_water(sample) and not BiomeProfile.is_lava(sample))
                fish_routes += 1
    assert(fish_routes > 0,"No fish-man shoreline routes found")
    point = first_fish.route[0]
    player.global_position = terrain.world_to_local_position(Vector3(point.x,terrain.get_height_at(point)+2,point.y))
    player.set_physics_process(true)
    fish._process(1)
    player.set_physics_process(false)
    assert(fish.get_child_count() > 0 and fish.get_child_count() <= 8)
    for npc in fish.get_children():
        assert(npc.model_index == 6 and npc.health.get_health() == 100)
        npc.set_active(false)
    var dungeon = StableWallProceduralDungeonWorld.new()
    game.add_child(dungeon)
    dungeon.build(19,742913,Vector2i(2,-3))
    await physics_frame
    var models: Dictionary = {}
    var identities: Array[Dictionary] = []
    for child in dungeon.get_children():
        if not child is Villager: continue
        child.set_active(false)
        models[child.model_index] = true
        assert(child.role == "cave" and child.health.get_health() == 100)
        assert(child._walkable(child.route[0]) and child._walkable(child.route[1]))
        child._wait = 0
        child._waypoint = 1
        child._state = "walk"
        var before: Vector3 = child.world_position
        for step in range(60): child._physics_process(1.0/60)
        assert(child.world_position.distance_to(before) > .5,"Cave NPC did not patrol its floor route")
        var hit = EquipmentHit.new()
        hit.damage = 120
        child.receive_equipment_hit(hit)
        identities.append({"model":child.model_index,"inventory":child.get_loot_inventory(),"position":child.world_position})
    assert(identities.size() == 4 and models.has(4) and models.has(5))
    dungeon.free()
    dungeon = StableWallProceduralDungeonWorld.new()
    game.add_child(dungeon)
    dungeon.build(19,742913,Vector2i(2,-3))
    var index = 0
    for child in dungeon.get_children():
        if not child is Villager: continue
        assert(child.health.is_dead())
        assert(child.get_loot_inventory() == identities[index].inventory)
        assert(child.world_position == identities[index].position)
        index += 1
    await process_frame
    game.free()
    LootSession.records.clear()
    print("PASS: dry shoreline fish-man routes and bounded spawning, deterministic dry volcano demons, bounded spawning, cave ghosts/zombies on connected floor routes, shared health and corpse inventories preserved across cave revisits.")
    quit()
