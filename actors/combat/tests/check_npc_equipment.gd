extends SceneTree
func _initialize(): run.call_deferred()
func add_item(storage: LootStorage, definition: EquipmentDefinition):
    assert(storage.try_add_item(definition.item_id,definition.display_name,definition.unit_weight,1,InventoryCategory.Type.WEAPONS_TOOLS))
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
    var definition: Dictionary = sampler.town(town)[0].duplicate()
    var player = load("res://actors/player/first_person_player.tscn").instantiate()
    game.add_child(player)
    player.set_physics_process(false)
    for model in range(7):
        # Each grip fixture needs a clear arena; previous death checks leave corpses.
        for child in world.get_children():
            if child.has_meta("loot_target"): child.queue_free()
        await physics_frame
        await physics_frame
        definition.model = model
        definition.seed = 8000+model
        var npc = Villager.new()
        npc.configure(terrain,definition)
        world.add_child(npc)
        npc.set_physics_process(false)
        npc.set_process(false)
        npc.set_affection(10)
        var inventory = npc.get_inventory()
        assert(npc.get_equipped_weapon() == null)
        add_item(inventory,EquipmentCatalog.IRON_PICKAXE)
        assert(npc.get_equipped_weapon() == null,"Tool was mistaken for a weapon")
        for weapon in [EquipmentCatalog.IRON_SWORD,EquipmentCatalog.WOODSMAN_AXE,EquipmentCatalog.HUNTERS_KNIFE]:
            add_item(inventory,weapon)
            assert(npc.get_equipped_weapon() == weapon)
            assert(not npc.perform_action("punch") and not npc.perform_action("kick"))
            player.get_health_state().restore_full_health()
            player.global_position = npc.global_position+Vector3(1.3,0,0)
            await physics_frame
            npc.combat.cancel()
            npc._action_remaining = 0
            npc.combat._cooldown = 0
            var fighting = npc.combat.tick(.01)
            assert(fighting and npc.combat.attacking,"Model %d weapon %s active %s target %s"%[model,weapon.item_id,fighting,npc.combat.target])
            var action = npc.get_weapon_attack_action()
            assert(action in ["weapon_slash","weapon_chop","weapon_stab"])
            assert(npc._animation.current_animation == "Quaternius/"+Villager.CLIPS[action])
            assert(is_equal_approx(npc.combat.get_attack_reach(),weapon.reach))
            npc.combat.tick(.5)
            assert(is_equal_approx(player.get_health_state().get_health(),100-weapon.damage),"Weapon damage differs from player equipment")
            for frame in range(30): npc._process(1.0/60)
            npc._ground_feet()
            npc.equipment.update_pose()
            var hand = npc._rig.global_transform*npc._rig.get_bone_global_pose(npc.equipment._hand)
            assert(npc.equipment._model.global_position.distance_to(hand.origin) < .081)
            assert(is_equal_approx(npc.equipment._model.global_basis.y.length(),1.0),"Imported rig scale leaked into held model")
            assert(inventory.remove_item(weapon.item_id) == 1)
            assert(npc.get_equipped_weapon() == null)
        # Entire existing catalogue can be equipped, with deterministic best-damage selection.
        var best: EquipmentDefinition
        for weapon in EquipmentCatalog.DEFINITIONS:
            if weapon.category != EquipmentDefinition.Category.WEAPON: continue
            add_item(inventory,weapon)
            if best == null or weapon.damage > best.damage: best = weapon
        assert(npc.get_equipped_weapon() == best)
        npc.health.set_health(0)
        assert(npc.get_loot_inventory() == inventory)
        npc._process(0)
        assert(npc.equipment._model != null)
        for weapon in EquipmentCatalog.DEFINITIONS:
            if weapon.category == EquipmentDefinition.Category.WEAPON: inventory.remove_item(weapon.item_id,99)
        npc._process(0)
        assert(npc.equipment.weapon == null and npc.equipment._model == null,"Looted corpse still held a removed weapon")
        npc.health.restore_full_health()
        add_item(inventory,EquipmentCatalog.IRON_SWORD)
        npc._action_remaining = 0
        npc.combat._cooldown = 0
        player.get_health_state().restore_full_health()
        npc.combat.tick(.01)
        assert(npc.combat.attacking)
        inventory.remove_item(EquipmentCatalog.IRON_SWORD.item_id)
        npc.combat.tick(.5)
        assert(player.get_health_state().get_health() == 100,"Removed weapon still hit during windup")
        npc._action_remaining = 0
        assert(npc.perform_action("punch"),"Disarmed NPC could not use fists")
        add_item(inventory,EquipmentCatalog.HUNTERS_KNIFE)
        var saved_inventory = inventory
        npc.free()
        npc = Villager.new()
        npc.configure(terrain,definition)
        world.add_child(npc)
        npc.set_physics_process(false)
        npc.set_process(false)
        assert(npc.get_inventory() == saved_inventory and npc.get_equipped_weapon() == EquipmentCatalog.HUNTERS_KNIFE)
        npc.free()
    game.queue_free()
    await process_frame
    print("PASS all seven weapon grips, swords/axes/knives and catalogue selection, tools excluded, armed animations/damage/reach, disarming, corpse loot and streaming")
    quit()
