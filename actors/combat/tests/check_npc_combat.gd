extends SceneTree
func _initialize(): run.call_deferred()
func run():
    LootSession.records.clear()
    var game = Node3D.new()
    root.add_child(game)
    var world = load("res://world/environments/basic_world.tscn").instantiate()
    game.add_child(world)
    world.set_process(false)
    var terrain = world.get_node("Terrain")
    terrain.set_process(false)
    var sampler = VillagerPopulationSampler.new(terrain)
    var town = sampler._settlements.find_nearby(Vector2.ZERO,"town")
    var definition = sampler.town(town)[0]
    var npc = Villager.new()
    npc.configure(terrain,definition)
    world.add_child(npc)
    npc.set_physics_process(false)
    npc.set_process(false)
    var player = load("res://actors/player/first_person_player.tscn").instantiate()
    game.add_child(player)
    player.set_physics_process(false)
    player.global_position = npc.global_position+Vector3(1.3,0,0)
    await physics_frame
    var combat = npc.combat
    npc.set_affection(11)
    assert(not combat.tick(.01))
    npc.set_affection(10)
    assert(combat.tick(.01) and npc.is_in_combat() and combat.attacking)
    assert(player.get_health_state().get_health() == 100,"Windup dealt immediate damage")
    combat.tick(.15)
    assert(player.get_health_state().get_health() == 100)
    combat.tick(.16)
    assert(player.get_health_state().get_health() == 92)
    combat.tick(.7)
    assert(player.get_health_state().get_health() == 92,"Cooldown allowed a duplicate strike")
    npc.set_affection(11)
    assert(not npc.is_in_combat() and not combat.attacking)
    npc.set_affection(0)
    npc._action_remaining = 0
    combat._cooldown = 0
    assert(combat.tick(.01) and combat.attacking)
    player.global_position += Vector3(4,0,0)
    combat.tick(.31)
    assert(player.get_health_state().get_health() == 92,"Missed attack damaged player")
    player.global_position = npc.global_position+Vector3(1.3,0,0)
    npc._action_remaining = 0
    combat._cooldown = 0
    combat.tick(.01)
    npc.set_affection(100)
    combat.tick(1)
    assert(player.get_health_state().get_health() == 92,"Pacified attack dealt damage")
    var wall = StaticBody3D.new()
    var collider = CollisionShape3D.new()
    var box = BoxShape3D.new()
    box.size = Vector3(.1,3,3)
    collider.shape = box
    wall.add_child(collider)
    game.add_child(wall)
    wall.global_position = npc.global_position+Vector3(.65,1,0)
    await physics_frame
    npc.set_affection(10)
    assert(not combat.tick(.01),"Acquired player through wall")
    wall.queue_free()
    await physics_frame
    await physics_frame
    npc._action_remaining = 0
    combat._cooldown = 0
    assert(combat.tick(NpcCombat.PERCEPTION_INTERVAL)) # Wait for the next bounded perception update after removing cover.
    var health = player.get_health_state()
    health.set_infinite_health_enabled(true)
    combat.tick(.5)
    assert(health.get_health() == 100)
    health.set_infinite_health_enabled(false)
    health.set_health(0)
    assert(not combat.tick(.01),"Attacked dead player")
    health.restore_full_health()
    player.global_position = npc.global_position+Vector3(50,0,0)
    assert(not combat.tick(.01),"Initiated combat beyond notice distance")
    # Actual chase motion uses the same terrain routes and physics as patrols.
    var origin = Vector2(npc.world_position.x,npc.world_position.z)
    var endpoint: Vector2 = origin+(Vector2(definition.route[1])-origin).normalized()*5.0
    player.global_position = terrain.world_to_local_position(Vector3(endpoint.x,sampler._settlements.ground_height(endpoint)+.04,endpoint.y))
    npc.set_affection(10)
    npc._action_remaining = 0
    combat._cooldown = 0
    var before = npc.world_position
    var distance = npc.global_position.distance_to(player.global_position)
    for step in range(60): npc._physics_process(1.0/60)
    assert(npc.world_position.distance_to(before) > .5,"Hostile NPC did not pursue")
    assert(npc.global_position.distance_to(player.global_position) < distance)
    player.global_position = npc.global_position+Vector3(1.3,0,0)
    npc._action_remaining = 0
    combat._cooldown = 0
    combat.tick(.01)
    health.restore_full_health()
    combat.cancel()
    npc._action_remaining = 0
    combat._cooldown = 0
    for step in range(30): npc._physics_process(1.0/60)
    assert(health.get_health() < 100,"Integrated attack did not damage player")
    assert(npc._animation.current_animation in ["Quaternius/Punch_Jab","Quaternius/Kick"])
    health.restore_full_health()
    npc.health.set_health(0)
    assert(not combat.active and not combat.attacking)
    combat.tick(1)
    assert(health.get_health() == 100,"Dead NPC attacked")
    # Cave pursuit paths must follow connected floor cells around walls.
    var dungeon = ProceduralDungeonWorld.new()
    dungeon._layout = DungeonLayoutGenerator.new().generate(742913)
    npc._dungeon = dungeon
    var first = DungeonGeometryBuilder.get_cell_center(dungeon._layout,dungeon._layout.door_a_cell)
    var last = DungeonGeometryBuilder.get_cell_center(dungeon._layout,dungeon._layout.door_b_cell)
    var path = npc._cave_chase_path(Vector2(first.x,first.z),Vector2(last.x,last.z))
    assert(not path.is_empty())
    for point in path:
        var cell = Vector2i((point/4+Vector2(dungeon._layout.width,dungeon._layout.height)*.5).floor())
        assert(dungeon._layout.is_walkable(cell))
    dungeon.free()
    game.queue_free()
    await process_frame
    print("PASS threshold, timed hits, cooldown, dodging, pacification, cover, invulnerability, deaths, detection range, actual pursuit and cave paths")
    quit()
