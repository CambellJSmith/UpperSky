extends SceneTree

class FlatTerrain extends InfiniteTerrain:
    func _ready(): pass
    func _process(_delta): pass
    func get_height_at(_point: Vector2) -> float: return 0.0
    func has_water_at(_point: Vector2) -> bool: return false
    func get_loaded_chunk_count() -> int: return 1

class DungeonStub extends Node:
    var _active_dungeon = null
    var _starting_pair = null
    var _active_pair = null

func _initialize(): run.call_deferred()

func run():
    LootSession.records.clear()
    var game := Node3D.new()
    game.name = "Game"
    var world: Node3D = load("res://world/environments/basic_world.tscn").instantiate()
    world.name = "World"
    var old_terrain := world.get_node("Terrain")
    world.remove_child(old_terrain)
    old_terrain.free()
    var terrain := FlatTerrain.new()
    terrain.name = "Terrain"
    world.add_child(terrain)
    game.add_child(world)
    var dynamic := Node3D.new()
    dynamic.name = "DynamicEntities"
    var player: FirstPersonPlayer = load("res://actors/player/first_person_player.tscn").instantiate()
    player.name = "Player"
    dynamic.add_child(player)
    game.add_child(dynamic)
    var loading := LoadingScreen.new()
    loading.name = "LoadingScreen"
    var panel := ColorRect.new()
    panel.name = "Panel"
    var label := Label.new()
    label.name = "Label"
    panel.add_child(label)
    loading.add_child(panel)
    game.add_child(loading)
    var interiors := BuildingInteriors.new()
    interiors.name = "BuildingInteriors"
    game.add_child(interiors)
    var dungeon := DungeonStub.new()
    dungeon.name = "DungeonSystem"
    game.add_child(dungeon)
    var settlements := SettlementStreamer.new()
    settlements.name = "Settlements"
    world.add_child(settlements)
    var save := SaveSystem.new()
    save.name = "SaveSystem"
    game.add_child(save)
    var travel := CityTravel.new()
    travel.name = "CityTravel"
    game.add_child(travel)
    root.add_child(game)
    settlements.set_process(false)
    player.set_physics_process(false)
    travel.initialize(player,terrain)
    interiors.initialize(player,terrain)
    var definition := {"seed":300,"position":Vector2.ZERO,"height":0.0,"yaw":.7,"houses":[]}
    var exterior := CityGeometry.exterior(definition)
    assert(exterior.has_meta("city_gate"))
    CityStaticBatch.build_sync(exterior)
    assert(exterior.has_meta("city_gate"))
    var city_exterior := Node3D.new()
    city_exterior.set_meta("definition",definition)
    city_exterior.add_child(exterior)
    settlements.add_child(city_exterior)
    settlements._towns[Vector2i.ZERO] = city_exterior
    settlements._sampler._towns[Vector2i.ZERO] = definition
    var gate: Vector3 = exterior.get_meta("city_gate")
    player.global_position = exterior.to_global(gate)
    player.set_physics_process(true)
    travel._process(.1)
    while travel.busy: await process_frame
    var city := travel.active
    assert(city.house_count == 52 and city.resident_count == 52)
    assert(city.king_count == 1 and city.knight_count == 6)
    var scenery_batches := 0
    for child in city.get_children():
        if child is MeshInstance3D and child.mesh != null and str(child.name).begins_with("SceneryBatch"):
            scenery_batches += 1
            assert(not child.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR].is_empty())
    assert(scenery_batches > 0 and scenery_batches < 160)
    assert(terrain.process_mode == Node.PROCESS_MODE_DISABLED and not terrain.visible)
    assert(not loading._panel.visible)
    var king: Villager
    var peasants := 0
    for child in city.get_children():
        if not child is Villager: continue
        if child.model_index == 11: king = child
        if child.model_index in [0,1]: peasants += 1
        if child.model_index == 9: assert(child.affection.score == 11)
        for i in child.route.size():
            var a: Vector2 = child.route[i]
            var b: Vector2 = child.route[(i+1)%child.route.size()]
            for sample in range(21): assert(city.is_walkable(a.lerp(b,sample/20.0)))
    assert(peasants == 52 and king != null and king.affection.score == 100)
    for clip in Villager.CLIPS.values():
        assert(king._animation.has_animation("Quaternius/"+clip))
        king._animation.play("Quaternius/"+clip)
        king._animation.advance(.1)
        for bone in king._rig.get_bone_count(): assert(king._rig.get_bone_global_pose(bone).origin.is_finite())
    var snapshot := save.snapshot()
    assert(snapshot.city.cell == Vector2i.ZERO and snapshot.position == travel.return_position)
    var encoded = SaveCodec.encode(snapshot)
    assert(SaveCodec.valid(encoded) and save._valid_state(SaveCodec.decode(encoded)))
    king.affection.score = 73
    save.ready_to_save = true
    save.folder = "/tmp/upper-sky-city-save-%d"%Time.get_ticks_usec()
    assert(save.save_slot("quick"))
    var disk := save.read_slot("quick")
    assert(disk.city.cell == snapshot.city.cell and disk.city.position == snapshot.city.position)
    assert(disk.position == travel.return_position)
    var before := king.world_position
    king._wait = 0
    king._waypoint = 1
    king._state = "walk"
    for frame in range(20): await physics_frame
    assert(king.world_position.distance_to(before) > .05)
    var query := PhysicsRayQueryParameters3D.create(CityTravel.ORIGIN+Vector3(0,10,100),CityTravel.ORIGIN+Vector3(0,-5,100),1)
    assert(not city.get_world_3d().direct_space_state.intersect_ray(query).is_empty())
    var expected_return := travel.return_position
    await travel.leave()
    assert(travel.active == null and terrain.visible and terrain.process_mode == Node.PROCESS_MODE_INHERIT)
    assert(player.global_position.distance_to(expected_return) < .1)
    assert(not loading._panel.visible and player.is_physics_processing())
    player.set_physics_process(false)
    LootSession.records = disk.loot
    await travel.restore(disk.city)
    assert(travel.active != null and travel.active.king_count == 1)
    assert(travel.active.to_local(player.global_position).distance_to(snapshot.city.position) < .1)
    for child in travel.active.get_children():
        if child is Villager and child.model_index == 11: assert(child.affection.score == 73)
    var house: Node3D = travel.active.get_node("CityHouse_0")
    await interiors._enter_room(house)
    assert(interiors._active_room != null and player._terrain == null)
    var room_state := travel.snapshot()
    assert(room_state.room.house == "CityHouse_0")
    assert(save._valid_state(SaveCodec.decode(SaveCodec.encode(save.snapshot()))))
    await interiors._leave_room()
    assert(player._terrain == null)
    assert(player.global_position.distance_to(travel.active.to_global(room_state.position)) < .1)
    await travel.leave()
    player.set_physics_process(false)
    await travel.restore(room_state)
    assert(interiors._active_room != null)
    assert(player.global_position.distance_to(room_state.room.position) < .1)
    await interiors._leave_room()
    await travel.leave()
    game.free()
    print("PASS city layout, ",scenery_batches," scenery batches, safe patrol routes, king animations, single king/six guards, drawbridge entry, isolated world, collision, movement, disk saves, restoration, interiors and return travel")
    quit()
