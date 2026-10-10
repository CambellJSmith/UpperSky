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
    var startup_deadline: int = Time.get_ticks_msec() + 15000 # Bound initial collision-backed loading.
    while not game.get_node("SaveSystem").ready_to_save and Time.get_ticks_msec() < startup_deadline: # Wait for ready gameplay rather than a hardware-dependent frame count.
        await process_frame # Let incremental startup complete.
    assert(game.get_node("SaveSystem").ready_to_save and player.is_physics_processing(), "Startup did not finish") # Reject an incomplete streaming fixture.
    var sampler: SettlementSampler = SettlementSampler.for_terrain(terrain) # Select a town that has exterior residents.
    var absolute: Vector3 = terrain.local_to_world_position(player.global_position) # Locate the current search region.
    var centre: Vector2i = Vector2i((Vector2(absolute.x, absolute.z) / SettlementSampler.TOWN_CELL_SIZE).floor()) # Search near the real spawn.
    var town: Dictionary = {} # Retain a valid ordinary town fixture.
    for z: int in range(-3, 4): # Examine nearby settlement regions.
        for x: int in range(-3, 4): # Find a town whose residents live in the overworld.
            var candidate: Dictionary = sampler.sample_town(centre + Vector2i(x, z)) # Inspect deterministic placement.
            if not candidate.is_empty() and not CityGeometry.is_city(candidate) and not population._sampler.town(candidate).is_empty(): # Require validated resident routes in the exterior space.
                town = candidate # Retain an ordinary town.
                break # Stop the current row after finding the fixture.
        if not town.is_empty(): break # Stop once a town is available.
    assert(not town.is_empty(), "No ordinary town fixture found") # Require an exterior population to exercise.
    player.set_fly_mode_enabled(true) # Keep the fixture clear of unloaded collision.
    player.global_position = terrain.world_to_local_position(Vector3(town.position.x, town.height + 30.0, town.position.y)) # Visit the selected town directly.
    var town_deadline: int = Time.get_ticks_msec() + 20000 # Bound incremental town and resident loading.
    while (population.get_child_count() < 8 or paths._chunks.is_empty()) and Time.get_ticks_msec() < town_deadline: # Wait for useful streaming output.
        await process_frame # Allow real-time streamer intervals and scheduler slices to progress.
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
    terrain.origin_shifted.emit() # Notify retained actors and static scenery after the simulated rebase.
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
    var home_deadline: int = Time.get_ticks_msec() + 20000 # Bound homesteader streaming after travel.
    var has_homesteader: bool = false # Observe the actual resident outcome.
    while not has_homesteader and Time.get_ticks_msec() < home_deadline: # Wait for a real streamed resident rather than a fixed frame count.
        await process_frame # Let placement and population slices progress.
        for child: Node in population.get_children(): # Inspect the currently loaded actors.
            if child.role == "homesteader": has_homesteader = true # Stop waiting after the expected resident appears.
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
