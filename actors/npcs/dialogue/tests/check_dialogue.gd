extends SceneTree # Exercise conversation content, actor lifecycle, targeting and composed menu controls.

class HeadlessInteraction extends DialogueInteraction: # Adapt only display-server mouse capture for headless lifecycle testing.
    func _gameplay_active() -> bool: # Preserve participant validity while the dummy display lacks mouse capture.
        return is_instance_valid(_player) and _player.is_physics_processing() and not _player.get_health_state().is_dead() # Exercise production eligibility independently of display capabilities.

func _initialize() -> void: # Defer tests until autoloads are available.
    run.call_deferred() # Prepare the scene tree before instantiating actors.

func run() -> void: # Verify factual phrases and actual dialogue interaction.
    var game_scene: PackedScene = load("res://application/game/game.tscn") # Preload ordinary equipment and actor composition dependencies.
    assert(game_scene != null) # Require the integrated game scene to compile.
    var game: Node3D = Node3D.new() # Build a controlled game composition without procedural streaming.
    root.add_child(game) # Provide a shared world for targeting and UI.
    var world: Node3D = Node3D.new() # Provide the production terrain path.
    world.name = "World" # Match composition paths used by the controller.
    game.add_child(world) # Attach the world container.
    var terrain: InfiniteTerrain = InfiniteTerrain.new() # Provide real coordinate conversion and geography access.
    terrain.name = "Terrain" # Match the controller's terrain path.
    world.add_child(terrain) # Initialize the terrain node.
    terrain.set_process(false) # Keep terrain generation outside this controlled test.
    terrain.set_physics_process(false) # Keep origin shifts under test control.
    var dynamic: Node3D = Node3D.new() # Provide the production player path.
    dynamic.name = "DynamicEntities" # Match the controller's player composition.
    game.add_child(dynamic) # Attach the player container.
    var player_scene: PackedScene = load("res://actors/player/first_person_player.tscn") # Load the real input and health implementation.
    var player: FirstPersonPlayer = player_scene.instantiate() as FirstPersonPlayer # Instantiate the real player composition.
    player.name = "Player" # Match the production player path.
    dynamic.add_child(player) # Initialize the player controls and camera.
    var point: Vector2 = Vector2(100, 100) # Anchor the controlled actor near the player.
    var route: Array[Vector2] = [point, point + Vector2.RIGHT * 4.0] # Provide a short ordinary actor route.
    var npc: Villager = Villager.new() # Instantiate a real human camper.
    npc.configure(terrain, {"route": route, "seed": 930001, "model": 0, "role": "camper", "start": 0}) # Initialize persistent social state and animation.
    game.add_child(npc) # Load the actual model and collider.
    npc.set_process(false) # Avoid animation ticks outside explicit actor checks.
    npc.set_physics_process(false) # Avoid unsolicited route movement during setup.
    player.global_position = npc.global_position + Vector3(0, 0, 2) # Keep both participants within talking distance.
    var interaction_scene: PackedScene = load("res://application/ui/dialogue/dialogue_interaction.tscn") # Load the editor-authored UI composition.
    var interaction: DialogueInteraction = interaction_scene.instantiate() as DialogueInteraction # Instantiate the production conversation controller.
    interaction.set_script(HeadlessInteraction) # Replace only the headless display readiness predicate.
    game.add_child(interaction) # Connect authored topics and lifecycle state.
    interaction.set_process(false) # Run lifecycle checks explicitly.
    var sampler: SettlementSampler = SettlementSampler.for_terrain(terrain) # Access the shared generated geography cache.
    sampler._towns.clear() # Start with explicitly missing local city knowledge.
    var context: Dictionary = DialogueContext.build(npc, terrain, null) # Resolve an actor snapshot without geography or clock.
    assert(not context.has("city_name")) # Require an honest missing-city context.
    assert(not DialoguePhrases.response("city", context, 0).contains("{")) # Require a complete fallback without unresolved variables.
    sampler._towns[Vector2i.ZERO] = {"seed": 3, "position": point + Vector2(2000, 0)} # Seed a real named city definition for controlled geography checks.
    sampler._towns[Vector2i.ONE] = {"seed": 6, "position": point + Vector2(4000, 0)} # Provide a farther valid city to test nearest selection.
    context = DialogueContext.build(npc, terrain, null) # Resolve actual city substitutions from the shared cache.
    assert(context.city_name == CityGeometry.city_name(3)) # Require the exact game-generated city name.
    assert(context.city_direction == "east" and context.city_distance == "2.0 km") # Require factual position-based directions and distance.
    var city_space: CitySpace = CitySpace.new() # Verify city-local dialogue uses the actual containing city.
    city_space.definition = {"seed": 6, "position": point + Vector2(4000, 0)} # Provide the enclosing city's authoritative definition.
    game.add_child(city_space) # Compose the city without generating its full geometry.
    npc.reparent(city_space) # Place the speaker inside the actual city space.
    var city_context: Dictionary = DialogueContext.build(npc, terrain, null) # Resolve city-local world facts.
    assert(city_context.in_city and city_context.city_name == CityGeometry.city_name(6)) # Prefer the containing city over an exterior cached city.
    assert(DialoguePhrases.response("city", city_context, 0).contains(city_context.city_name)) # Require complete current-city phrasing without direction placeholders.
    npc.reparent(game) # Restore the exterior actor composition.
    city_space.free() # Release the controlled city container.
    terrain._world_origin_offset = Vector2(256, -256) # Simulate a floating-origin shift.
    assert(DialogueContext.build(npc, terrain, null) == context) # Require geography to remain stable in absolute world coordinates.
    terrain._world_origin_offset = Vector2.ZERO # Restore actor placement before interaction checks.
    var cycle_scene: PackedScene = load("res://world/environments/basic_world.tscn") # Load the editor-authored lighting composition.
    var cycle: DayNightCycle = cycle_scene.instantiate() as DayNightCycle # Provide a clock with its required environment and lights.
    game.add_child(cycle) # Initialize the lighting clock.
    cycle.set_process(false) # Keep the time deterministic.
    cycle.set_time_of_day_hours(22) # Exercise a nighttime greeting.
    context = DialogueContext.build(npc, terrain, cycle) # Resolve the actual clock state.
    assert(context.clock_time == "22:00" and context.time_of_day == "night") # Require the shared world clock values.
    for topic: String in DialoguePhrases.TOPICS: # Exercise all authored topic paths.
        for variant: int in range(12): # Exercise every alternative and repeated-question wraparound.
            var line: String = DialoguePhrases.response(topic, context, variant) # Expand the authored template.
            assert(not line.is_empty() and not line.contains("{") and not line.contains("}")) # Require fully resolved nonempty responses.
    for offset: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]: # Verify cardinal world directions.
        assert(DialogueContext.direction(offset) in ["north", "south", "west", "east"]) # Require cardinal alignment.
    var camera: Camera3D = player.get_view_camera() # Use the production interaction ray origin.
    camera.look_at(npc.global_position + Vector3.UP * 0.9) # Aim at the actual NPC collider.
    player.set_physics_process(false) # Prevent gravity from moving the controlled participant during collision registration.
    await physics_frame # Let the physics server register the actor collider.
    await physics_frame # Wait for registered collision transforms to finish synchronization.
    player.set_physics_process(true) # Restore the controller's gameplay-ready state.
    assert(interaction._ray_target() == npc) # Require a real visible NPC to be targetable.
    var wall: StaticBody3D = StaticBody3D.new() # Exercise ordinary scenery occlusion.
    var wall_collision: CollisionShape3D = CollisionShape3D.new() # Provide a real blocking collision volume.
    var wall_shape: BoxShape3D = BoxShape3D.new() # Model a solid wall between the participants.
    wall_shape.size = Vector3(2, 3, 0.2) # Cover the camera-to-speaker ray.
    wall_collision.shape = wall_shape # Assign the wall's collision geometry.
    wall.add_child(wall_collision) # Compose the blocking body.
    wall.position = npc.global_position + Vector3(0, 1, 1) # Place the wall between camera and NPC.
    game.add_child(wall) # Register the blocking scenery.
    player.set_physics_process(false) # Hold the participant in place during physics synchronization.
    await physics_frame # Register the wall collider.
    await physics_frame # Finish collision transform synchronization.
    assert(interaction._ray_target() == null) # Reject conversation targeting through walls.
    wall.free() # Remove the blocking scenery.
    player.set_physics_process(true) # Restore active gameplay eligibility.
    assert(interaction.open_dialogue(npc)) # Open through the production conversation controller.
    assert(not player._gameplay_input_enabled) # Require exclusive menu input and a visible pointer.
    assert(not npc.begin_dialogue(game)) # Reject a second conversation owner.
    var menu: DialogueMenu = interaction.get_node("Menu") as DialogueMenu # Access the actual composed menu.
    var topics: VBoxContainer = menu.get_node("Shade/Margins/Center/Panel/Scroll/Content/Topics") as VBoxContainer # Resolve the authored topic controls.
    (topics.get_child(1) as Button).pressed.emit() # Select the actual city topic button.
    var response: Label = menu.get_node("Shade/Margins/Center/Panel/Scroll/Content/Response") as Label # Inspect the displayed NPC line.
    assert(response.text.contains(CityGeometry.city_name(3))) # Detect incorrectly captured topic-button closures.
    npc.set_physics_process(true) # Exercise the actor's conversation movement hold.
    var before: Vector3 = npc.world_position # Record the speaker's grounded position.
    npc._profile__physics_process(0.1) # Run an actual actor update during conversation.
    assert(npc.world_position.is_equal_approx(before)) # Require route movement to stop while talking.
    npc.set_physics_process(false) # Restore explicit update control.
    interaction.close_dialogue() # Release the first conversation.
    assert(player._gameplay_input_enabled) # Require gameplay restoration on goodbye.
    npc.model_index = 2 # Exercise the existing orc relationship species.
    assert(interaction.open_dialogue(npc)) # Require orcs to support the same conversation flow.
    npc.combat.active = true # Simulate combat beginning while the menu is open.
    interaction._process(0.2) # Check the live speaker's changed eligibility.
    assert(player._gameplay_input_enabled) # Require combat to close the menu safely.
    npc.combat.active = false # Restore peaceful actor state.
    npc.model_index = 3 # Exercise a non-human and non-orc actor.
    assert(not interaction.open_dialogue(npc)) # Reject unsupported species without changing input.
    npc.model_index = 0 # Restore the original human model.
    var inventory: PlayerInventory = player.get_node("PlayerInventory") as PlayerInventory # Exercise the real player's purchase and gift flow.
    assert(interaction.open_encounter(npc, "boot_money")) # Open a stock-backed sale in the authored menu.
    assert(menu._accept.text.contains("5 Coins") and menu._accept.text.contains("Bread")) # Show exact goods and price before consent.
    menu._accept.pressed.emit() # Attempt the purchase without sufficient currency.
    assert(menu._encounter.visible and not player._gameplay_input_enabled) # Keep failed purchases pending in the menu.
    assert(response.text.contains("Need") and inventory.get_total_item_count() == 0) # Explain missing funds without delivering goods.
    assert(inventory.try_add_item(&"coins", "Coins", 0.01, 5, InventoryCategory.Type.MISC)) # Supply the actual quoted currency.
    menu._accept.pressed.emit() # Accept through the native button signal.
    assert(menu._goodbye.visible and not menu._encounter.visible) # Hold a readable completion screen after settlement.
    assert(RadiantOfferService.find_item(inventory, &"bread").get_quantity() == 3) # Deliver the real purchased bread.
    var purchase_revision: int = inventory.get_revision() # Snapshot the completed purchase.
    menu._accept.pressed.emit() # Reproduce a stale repeated acceptance signal.
    assert(inventory.get_revision() == purchase_revision) # Prevent a duplicate payout or charge.
    menu._goodbye.pressed.emit() # Acknowledge the completed exchange.
    assert(player._gameplay_input_enabled and npc.get_affection() > NpcCombat.HOSTILE_THRESHOLD) # Restore gameplay with the merchant still peaceful.
    assert(interaction.open_dialogue(npc)) # Restore ordinary conversations after an event.
    assert(menu._topics.visible and menu._goodbye.text == "Goodbye") # Reset the authored normal topic and exit controls.
    interaction.close_dialogue() # Release the merchant before testing a gift giver.
    var giver: Villager = Villager.new() # Provide a separate one-time gift identity.
    giver.configure(terrain, {"route": route, "seed": 930003, "model": 2, "role": "radiant_challenger", "start": 0}) # Exercise orc gifts through the normal actor composition.
    game.add_child(giver) # Initialize the actual gift giver.
    giver.set_physics_process(false) # Hold its position during consent checks.
    assert(interaction.open_encounter(giver, "shared_lunch")) # Present the free-food invitation.
    menu._decline.pressed.emit() # Refuse the pending gift.
    assert(inventory.get_revision() == purchase_revision and player._gameplay_input_enabled) # Transfer nothing on refusal and restore controls.
    assert(interaction.open_encounter(giver, "shared_lunch")) # Retry the same stable uncompleted gift quote.
    menu._accept.pressed.emit() # Explicitly accept the free goods.
    assert(RadiantOfferService.find_item(inventory, &"bread").get_quantity() == 5) # Add only the promised two free bread.
    menu._goodbye.pressed.emit() # Release the completed friendly encounter.
    giver.free() # Release the controlled gift actor.
    assert(interaction.open_dialogue(npc)) # Start another live conversation.
    npc.health.apply_damage(100000) # Exercise an actual death during the exchange.
    interaction._process(0.2) # Validate the dead conversation target.
    assert(player._gameplay_input_enabled and not npc.can_talk()) # Require dead actors to revert to corpse interactions.
    var replacement: Villager = Villager.new() # Exercise streaming removal with a live conversation owner.
    replacement.configure(terrain, {"route": route, "seed": 930002, "model": 1, "role": "resident", "start": 0}) # Initialize another supported human speaker.
    game.add_child(replacement) # Load the replacement actor lifecycle.
    replacement.set_physics_process(false) # Hold the actor in place for the controlled exchange.
    assert(interaction.open_dialogue(replacement)) # Start a conversation before unloading its speaker.
    replacement.free() # Reproduce streaming removal of the owning NPC subtree.
    interaction._process(0.2) # Check a previously freed speaker reference safely.
    assert(player._gameplay_input_enabled) # Require actor unload to release conversation input.
    player.set_physics_process(false) # Stop the player during teardown.
    game.queue_free() # Release the controlled composition and conversation resources.
    await process_frame # Finish deferred scene cleanup before reporting success.
    print("PASS contextual dialogue, city facts, clock, topic controls, actor idle, species, combat, death and input restoration") # Report verified conversation behavior.
    quit() # Complete the regression check.
