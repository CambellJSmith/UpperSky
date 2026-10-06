extends SceneTree
class TestPlayer extends FirstPersonPlayer:
    func _ready(): pass
    func _physics_process(_delta: float): pass
class TestTerrain extends InfiniteTerrain:
    func _ready(): pass
    func get_height_at(_point: Vector2) -> float: return 0.0
    func has_water_at(_point: Vector2) -> bool: return false
    func get_water_level_at(_point: Vector2) -> float: return -100.0
func _initialize(): run.call_deferred()
func run():
    LootSession.records.clear()
    var game := Node3D.new()
    root.add_child(game)
    var world = load("res://world/environments/basic_world.tscn").instantiate()
    world.name="World"
    game.add_child(world)
    world.set_process(false)
    world.get_node("Terrain").free()
    var terrain := TestTerrain.new()
    terrain.name="Terrain"
    world.add_child(terrain)
    var entities := Node3D.new()
    entities.name="DynamicEntities"
    game.add_child(entities)
    var player := TestPlayer.new()
    player.name="Player"
    var vitals := PlayerVitals.new()
    vitals.name="PlayerVitals"
    player.add_child(vitals)
    var collision := CollisionShape3D.new()
    collision.name="CollisionShape3D"
    player.add_child(collision)
    var head := Node3D.new()
    head.name="Head"
    player.add_child(head)
    var camera := Camera3D.new()
    camera.name="Camera3D"
    head.add_child(camera)
    entities.add_child(player)
    player.set_process(false)
    player.set_physics_process(false)
    var ghosts := NightGhostPopulation.new()
    world.add_child(ghosts)
    ghosts.set_process(false)
    assert(not NightGhostPopulation.is_night(6) and not NightGhostPopulation.is_night(17.99))
    assert(NightGhostPopulation.is_night(18) and NightGhostPopulation.is_night(5.99))
    var rng := RandomNumberGenerator.new()
    rng.seed=1945
    var route := ghosts.wandering_route(Vector2(700,700),rng)
    assert(route.size()==2 and route[0]!=route[1])
    var npc := Villager.new()
    npc.configure(terrain,{"route":route,"model":4,"role":"night_ghost","seed":1945,"start":0})
    world.add_child(npc)
    npc.set_active(false)
    var materials: Array[BaseMaterial3D] = []
    ghosts._materials(npc._visual,materials)
    assert(not materials.is_empty() and npc.affection.score==25)
    ghosts._actors[1945]={"npc":npc,"materials":materials,"fade":1.0,"wander":20.0,"rng":rng}
    # Prevent Player physics from actually executing while the population runs.
    player.set_physics_process(true)
    world.set_time_of_day_hours(6)
    ghosts._process(4)
    assert(is_equal_approx(materials[0].albedo_color.a,.5))
    assert(not npc.is_in_group("npc") and not npc.is_physics_processing())
    ghosts._process(4)
    assert(ghosts._actors.is_empty())
    world.set_time_of_day_hours(18)
    player.global_position=Vector3(700,0,700)
    for i in range(20): ghosts._process(.3)
    assert(ghosts._actors.size()>0 and ghosts._actors.size()<=NightGhostPopulation.MAX_GHOSTS)
    for entry in ghosts._actors.values():
        assert(entry.npc.model_index==4 and entry.npc.affection.score==25)
    world.set_time_of_day_hours(6)
    ghosts._process(8)
    assert(ghosts._actors.is_empty())
    player.set_physics_process(false)
    game.queue_free()
    await process_frame
    print("PASS shared night schedule, random safe roaming, affection 25, independent transparent materials and gradual sunrise removal")
    quit()
