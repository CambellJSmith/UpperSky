extends SceneTree
func _initialize(): run.call_deferred()
func run():
    var game = load("res://application/game/game.tscn").instantiate()
    root.add_child(game)
    for i in range(100): await process_frame
    var console = game.get_node("DeveloperConsole")
    var terrain = game.get_node("World/Terrain")
    var player = game.get_node("DynamicEntities/Player")
    console._execute_command("houses 42")
    var showcase = game.get_node("World/HouseShowcase")
    assert(showcase._contents.get_child_count() == 8)
    assert(player.is_fly_mode_enabled())
    var anchor = showcase._world_anchor
    terrain._world_origin_offset += Vector2(1024,-1024)
    showcase._process(0)
    assert(terrain.local_to_world_position(showcase.global_position).is_equal_approx(anchor))
    var previous = showcase
    console._execute_command("houses 43")
    showcase = game.get_node("World/HouseShowcase")
    assert(showcase != previous and showcase._contents.get_child_count() == 8)
    assert(showcase._contents.get_node("House0").recipe.seed_value == 43)
    console._execute_command("houses nonsense")
    assert(game.get_node("World/HouseShowcase") == showcase)
    game.get_node("World").visible = false
    console._execute_command("houses 55")
    assert(game.get_node("World/HouseShowcase") == showcase)
    game.get_node("World").visible = true
    console._execute_command("houses clear")
    assert(game.get_node_or_null("World/HouseShowcase") == null)
    print("PASS: in-game gallery creation, six houses, safe fly view, rebasing, replacement, invalid/dungeon commands and clearing.")
    quit()
