extends SceneTree
func _initialize(): run.call_deferred()
func run():
    var game = load("res://application/game/game.tscn").instantiate()
    root.add_child(game)
    var streamer = game.get_node("World/Settlements")
    var console = game.get_node("DeveloperConsole")
    var terrain = game.get_node("World/Terrain")
    var player = game.get_node("DynamicEntities/Player")
    for i in range(120): await process_frame
    console._execute_command("town")
    assert(player.is_fly_mode_enabled())
    for i in range(110): await process_frame
    assert(streamer._towns.size() > 0 and streamer._towns.size() <= 9)
    assert(streamer._homes.size() <= 49)
    var checked = 0
    for town in streamer._towns.values():
        var definition: Dictionary = town.get_meta("definition")
        assert(town.get_meta("next_house") == definition["houses"].size())
        for i in range(definition["houses"].size()):
            var house = town.get_node("House%02d"%i)
            var item: Dictionary = definition["houses"][i]
            var expected = terrain.world_to_local_position(Vector3(item["position"].x,item["height"],item["position"].y))
            assert(house.global_position.is_equal_approx(expected))
            checked += 1
    assert(checked >= 8)
    terrain._world_origin_offset += Vector2(512,-512)
    player.global_position -= Vector3(512,0,-512)
    streamer._process(0)
    for town in streamer._towns.values():
        assert(town.position.is_equal_approx(terrain.world_to_local_position(town.get_meta("world_position"))))
    var elapsed: float = streamer._elapsed
    game.get_node("DungeonSystem")._set_overworld_active(false)
    for i in range(4): await process_frame
    assert(not streamer.is_visible_in_tree())
    assert(streamer._elapsed == elapsed)
    game.get_node("DungeonSystem")._set_overworld_active(true)
    assert(streamer.is_visible_in_tree())
    console._execute_command("homestead")
    for i in range(100): await process_frame
    assert(streamer._homes.size() > 0)
    streamer._refresh(Vector2(150000,150000))
    assert(streamer._towns.is_empty() and streamer._homes.is_empty())
    print("PASS: natural town travel, staged construction of ",checked," houses, transforms, bounded streaming, origin shifts, dungeon suspension and unloading.")
    quit()
