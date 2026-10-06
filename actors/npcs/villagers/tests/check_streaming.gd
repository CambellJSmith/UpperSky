extends SceneTree
func _initialize(): run.call_deferred()
func run():
    var game = load("res://application/game/game.tscn").instantiate()
    root.add_child(game)
    var console = game.get_node("DeveloperConsole")
    var population = game.get_node("World/Villagers")
    var terrain = game.get_node("World/Terrain")
    var paths = game.get_node("World/Paths")
    var player = game.get_node("DynamicEntities/Player")
    for i in range(100): await process_frame
    console._execute_command("town")
    for i in range(160): await process_frame
    assert(paths._chunks.size() > 0 and paths._chunks.size() <= 81)
    assert(population.get_child_count() >= 6)
    assert(population.get_child_count() <= VillagerPopulationStreamer.MAX_NPCS)
    var models: Dictionary = {}
    for npc in population.get_children():
        models[npc.model_index] = true
        assert(npc.route.size() >= 2)
    assert(models.has(0) and models.has(1) and models.has(2) and models.has(9))
    var npc = population.get_child(0)
    player.global_position = npc.global_position+Vector3(0,2,3)
    assert(population.perform_nearby("punch"))
    var world_position: Vector3 = npc.world_position
    terrain._world_origin_offset += Vector2(512,-512)
    population._process(0)
    paths._process(0)
    for cell in paths._chunks:
        var expected = terrain.world_to_local_position(Vector3(cell.x*256,0,cell.y*256))
        assert(paths._chunks[cell].global_position.is_equal_approx(expected))
    assert(npc.global_position.is_equal_approx(terrain.world_to_local_position(world_position)))
    game.get_node("DungeonSystem")._set_overworld_active(false)
    var elapsed: float = population._elapsed
    for i in range(5): await process_frame
    assert(not population.is_visible_in_tree())
    assert(not paths.is_visible_in_tree())
    assert(population._elapsed == elapsed)
    game.get_node("DungeonSystem")._set_overworld_active(true)
    console._execute_command("homestead")
    for i in range(150): await process_frame
    var found = false
    for child in population.get_children():
        if child.role == "homesteader": found = true
    assert(found)
    assert(paths._chunks.size() <= 81)
    population._refresh(Vector2(500000,500000))
    assert(population.get_child_count() == 0)
    assert(population._groups.is_empty())
    print("PASS: village and cottage populations, all three friendly models, nearby punch action, bounded counts, floating origin, dungeon suspension and unloading.")
    quit()
