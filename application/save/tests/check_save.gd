extends SceneTree
var folder = "user://save-test-"+str(Time.get_ticks_usec())
func _initialize(): run.call_deferred()
func spawn():
    var game = load("res://application/game/game.tscn").instantiate()
    game.get_node("SaveSystem").folder = folder
    root.add_child(game)
    while not game.get_node("SaveSystem").ready_to_save: await physics_frame
    return game
func run():
    var game = await spawn()
    var saves = game.get_node("SaveSystem")
    var player = game.get_node("DynamicEntities/Player")
    var terrain = game.get_node("World/Terrain")
    var vitals = player.get_node("PlayerVitals")
    var inventory = player.get_node("PlayerInventory")
    inventory.clear()
    assert(inventory.try_add_item(&"bread","Bread",.25,3,InventoryCategory.Type.INGREDIENTS))
    var weapon = EquipmentCatalog.DEFINITIONS[0]
    assert(inventory.try_add_item(weapon.item_id,weapon.display_name,weapon.unit_weight,1,InventoryCategory.Type.WEAPONS_TOOLS))
    assert(player.get_node("PlayerEquipment").equip_item(weapon.item_id))
    vitals.set_maximum_stamina(1)
    vitals.set_stamina(.5)
    vitals.set_maximum_health(150)
    vitals.set_health(72)
    vitals.set_maximum_mana(200)
    vitals.set_mana(39)
    player.rotation.y = .7
    player._pitch = -.3
    var clock = get_first_node_in_group(DayNightCycle.GROUP_NAME)
    clock.set_time_of_day_hours(16.75)
    clock.set_speed_multiplier(0)
    var position = terrain.local_to_world_position(player.global_position)
    var record = LootSession.get_record("test-npc",42,true)
    record.health.set_health(0)
    record.position = Vector3(100,20,30)
    LootSession.get_affection(record,"human").set_score(6.5)
    record.inventory.stacks.clear()
    record.inventory.try_add_item(&"coins","Coins",.01,17)
    WayshrineRegistry.activate({"id":Vector2i(1,2),"position":Vector3(1,2,3),"landing":Vector3(4,5,6),"yaw":.4,"style":1,"title":"Test Shrine"})
    assert(saves.save_slot())
    assert(saves.save_slot())
    var encoded = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("current.json")))
    assert(encoded.version == 1)
    # Corrupt the primary file and verify recovery from the previous good snapshot.
    var corrupt = FileAccess.open(folder.path_join("current.json"),FileAccess.WRITE)
    corrupt.store_string("{broken")
    corrupt.close()
    assert(not saves.read_slot("current").is_empty())
    game.free()
    game = await spawn()
    player = game.get_node("DynamicEntities/Player")
    inventory = player.get_node("PlayerInventory")
    vitals = player.get_node("PlayerVitals")
    assert(get_first_node_in_group(DayNightCycle.GROUP_NAME).get_time_of_day_hours() == 16.75)
    assert(get_first_node_in_group(DayNightCycle.GROUP_NAME).get_speed_multiplier() == 0)
    assert(inventory.get_stack_count() == 2)
    assert(inventory.get_total_weight() > inventory.get_maximum_weight())
    assert(vitals.get_health() == 72 and vitals.get_maximum_health() == 150)
    assert(vitals.get_mana() == 39 and vitals.get_maximum_mana() == 200)
    assert(player.get_node("PlayerEquipment").get_equipped_item_id() == weapon.item_id)
    assert(absf(player._pitch+.3) < .001 and absf(player.rotation.y-.7) < .001)
    assert(game.get_node("World/Terrain").local_to_world_position(player.global_position).distance_to(position) < 1)
    assert(LootSession.records["test-npc"].health.is_dead())
    assert(LootSession.records["test-npc"].affection.get_score() == 6.5)
    assert(LootSession.records["test-npc"].inventory.stacks[0].get_quantity() == 17)
    assert(WayshrineRegistry.is_activated(Vector2i(1,2)))
    # Enter a genuine streamed cave; preserve both its pair and interior position.
    var dungeon = game.get_node("DungeonSystem")
    for i in range(3): await physics_frame
    var pair = dungeon._starting_pair
    assert(pair != null)
    assert(dungeon._enter_dungeon(pair.pair_id,DungeonPairDefinition.Endpoint.A))
    var cave_position = player.global_position
    assert(game.get_node("SaveSystem").save_slot())
    game.free()
    game = await spawn()
    dungeon = game.get_node("DungeonSystem")
    player = game.get_node("DynamicEntities/Player")
    assert(dungeon._active_pair.pair_id == pair.pair_id)
    assert(dungeon._active_pair.dungeon_seed == pair.dungeon_seed)
    assert(player.global_position.distance_to(cave_position) < 1)
    assert(dungeon._find_matching_exterior_door(pair.pair_id,DungeonPairDefinition.Endpoint.B) != null)
    assert(dungeon._exit_dungeon(pair.pair_id,DungeonPairDefinition.Endpoint.B))
    for i in range(4): await process_frame
    assert(player.is_physics_processing())
    assert(not SaveCodec.valid({"type":"stack","value":["bad","bad",-1,1,0]}))
    assert(not SaveCodec.valid({"type":"v3","value":["bad",0,0]}))
    var huge_pair = DungeonPairDefinition.new()
    huge_pair.pair_id = 9223372036854775806
    huge_pair.dungeon_seed = -9223372036854775807
    var serialized = JSON.parse_string(JSON.stringify(SaveCodec.encode(huge_pair)))
    assert(SaveCodec.valid(serialized))
    var recovered_pair = SaveCodec.decode(serialized)
    assert(recovered_pair.pair_id == huge_pair.pair_id and recovered_pair.dungeon_seed == huge_pair.dungeon_seed)
    assert(game.get_node("SaveSystem").save_slot("quick"))
    var event = InputEventKey.new()
    event.keycode = KEY_F5
    event.pressed = true
    game.get_node("SaveSystem")._unhandled_input(event)
    game.get_node("SaveSystem").elapsed = 61
    game.get_node("SaveSystem")._process(.1)
    assert(not game.get_node("SaveSystem").read_slot("current").is_empty())
    # Exercise the actual reload path rather than only constructing fresh scenes.
    current_scene = game
    assert(game.get_node("SaveSystem").load_slot("quick"))
    await process_frame
    await process_frame
    game = current_scene
    while not game.get_node("SaveSystem").ready_to_save: await physics_frame
    assert(game.get_node("DynamicEntities/Player/PlayerInventory").get_stack_count() == 2)
    assert(LootSession.records["test-npc"].health.is_dead())
    # Reject an incompatible slot without mutating the restored session.
    var bad = FileAccess.open(folder.path_join("quick.json"),FileAccess.WRITE)
    bad.store_string(JSON.stringify({"version":999,"world_seed":TerrainHeightSampler.WORLD_SEED}))
    bad.close()
    assert(not game.get_node("SaveSystem").read_slot("quick").is_empty()) # backup
    DirAccess.remove_absolute(folder.path_join("quick.json.bak"))
    assert(game.get_node("SaveSystem").read_slot("quick").is_empty())
    assert(game.get_node("SaveSystem").protect_invalid_save)
    assert(LootSession.records["test-npc"].health.is_dead())
    game.free()
    for name in ["current.json","current.json.bak","current.json.tmp","quick.json","quick.json.bak"]: DirAccess.remove_absolute(folder.path_join(name))
    DirAccess.remove_absolute(folder)
    print("PASS save round trip, inventory capacity, equipment, vitals, facing, corpse loot, fractional affection, wayshrines, backup recovery, cave identity/location and paired exit")
    quit()
