extends SceneTree # Verify real radiant actor placement, approach, consent and combat transitions.

class FlatTerrain extends InfiniteTerrain: # Provide deterministic dry terrain with real separately registered collision.
    var wet: bool = false # Allow the test to exercise water rejection.
    func get_height_at(_point: Vector2) -> float: # Keep all checked terrain triangles at the controlled floor.
        return 0.0 # Match the physical test floor.
    func has_water_at(_point: Vector2) -> bool: # Expose controlled water presence to placement and movement.
        return wet # Let the test switch the route between dry and submerged ground.
    func get_loaded_chunk_count() -> int: # Mark the controlled collision world as ready for scheduling.
        return 1 # Keep production scheduling gates active without procedural chunk generation.

class HeadlessDialogue extends DialogueInteraction: # Adapt only dummy-display mouse capture for the real conversation controller.
    func _gameplay_active() -> bool: # Preserve gameplay ownership and actor availability in the headless display.
        return is_instance_valid(_player) and _player.is_physics_processing() and _player._gameplay_input_enabled and not _player.get_health_state().is_dead() # Match live input ownership without requiring physical mouse capture.

func _initialize() -> void: # Defer setup until game autoloads are initialized.
    run.call_deferred() # Build the controlled composition in a live SceneTree.

func run() -> void: # Exercise production actor movement and authored consent controls.
    var composition: PackedScene = load("res://application/game/game.tscn") # Load normal equipment and actor composition dependencies.
    assert(composition != null) # Require the integrated radiant game scene to compile.
    var game: Node3D = Node3D.new() # Build a bounded outdoor collision test world.
    root.add_child(game) # Register the controlled game composition.
    var world: Node3D = Node3D.new() # Provide the production world path.
    world.name = "World" # Match the director's terrain lookup.
    game.add_child(world) # Attach the terrain container.
    var terrain: FlatTerrain = FlatTerrain.new() # Provide stable terrain queries for placement validation.
    terrain.name = "Terrain" # Match ordinary game composition paths.
    world.add_child(terrain) # Initialize the controlled terrain.
    terrain.set_process(false) # Keep procedural terrain streaming outside this test.
    terrain.set_physics_process(false) # Keep rebasing under explicit test control.
    var floor_body: StaticBody3D = StaticBody3D.new() # Register genuine loaded ground collision.
    var floor_collision: CollisionShape3D = CollisionShape3D.new() # Compose the ground collision shape.
    var floor_shape: BoxShape3D = BoxShape3D.new() # Provide an extended physical walking surface.
    floor_shape.size = Vector3(512, 1, 512) # Cover every bounded spawn and approach proposal.
    floor_collision.shape = floor_shape # Assign the controlled floor geometry.
    floor_body.add_child(floor_collision) # Attach the floor's physical shape.
    floor_body.position = Vector3(128, -0.5, 128) # Match sampled terrain elevation with the collider top.
    game.add_child(floor_body) # Register streamed ground with the physics server.
    var dynamic: Node3D = Node3D.new() # Provide the production player path.
    dynamic.name = "DynamicEntities" # Match player composition lookups.
    game.add_child(dynamic) # Attach the participant container.
    var player_scene: PackedScene = load("res://actors/player/first_person_player.tscn") # Use the real player movement and capability implementation.
    var player: FirstPersonPlayer = player_scene.instantiate() as FirstPersonPlayer # Instantiate a real player and camera.
    player.name = "Player" # Match ordinary game composition.
    dynamic.add_child(player) # Initialize player health and input components.
    player.global_position = Vector3(100, 0.1, 100) # Place the participant above the controlled floor.
    player.initialize_environment(terrain) # Mark the participant as being in the actual overworld.
    var dialogue_scene: PackedScene = load("res://application/ui/dialogue/dialogue_interaction.tscn") # Use authored conversation and consent controls.
    var dialogue: DialogueInteraction = dialogue_scene.instantiate() as DialogueInteraction # Instantiate the production dialogue composition.
    dialogue.set_script(HeadlessDialogue) # Adapt only dummy-display capture readiness.
    game.add_child(dialogue) # Initialize the live conversation controller.
    dialogue.set_process(false) # Keep menu lifecycle updates under explicit test control.
    LootSession.records["npc:radiant_challenger:0:expired"] = {} # Simulate a saved transient actor that is not reconstructed.
    var director: RadiantEventDirector = RadiantEventDirector.new() # Use the production scheduler and event state machine.
    game.add_child(director) # Resolve the participant and dialogue through normal composition.
    director.set_process(false) # Drive bounded scheduling updates explicitly.
    director._rng.seed = 1234 # Keep placement proposals reproducible in the regression.
    director._event_bag.assign([RadiantEventPhrases.BATTLE_CHALLENGE]) # Keep the movement regression focused on battle consent.
    for frame: int in range(20): # Allow player-floor collision and grounding to settle.
        await physics_frame # Register actual grounded player state.
    assert(not LootSession.records.has("npc:radiant_challenger:0:expired")) # Require expired saved event records to be cleaned after startup.
    assert(player.can_receive_radiant_encounter(terrain)) # Require the production outdoor readiness capability to pass.
    var rear: Vector2 = Vector2(100, 132) # Provide a wholly hidden rear candidate.
    assert(director._sampler.valid(rear, player)) # Require safe streamed rear ground to be accepted.
    assert(not director._sampler.valid(Vector2(100, 68), player)) # Reject an otherwise safe on-screen spawn.
    terrain.wet = true # Mark the proposed approach as water.
    assert(not director._sampler.valid(rear, player)) # Reject submerged spawn and approach ground.
    terrain.wet = false # Restore safe dry ground.
    var wall: StaticBody3D = StaticBody3D.new() # Exercise blocked route rejection before actor allocation.
    var wall_collision: CollisionShape3D = CollisionShape3D.new() # Compose a solid route obstacle.
    var wall_shape: BoxShape3D = BoxShape3D.new() # Model a wall across the initial approach.
    wall_shape.size = Vector3(4, 3, 0.5) # Cover the planned straight walking corridor.
    wall_collision.shape = wall_shape # Assign the blocker shape.
    wall.add_child(wall_collision) # Attach the physical obstacle.
    wall.position = Vector3(100, 1.5, 116) # Place the obstacle between rear spawn and player.
    game.add_child(wall) # Register the route blocker with physics.
    await physics_frame # Synchronize the wall's collision registration.
    await physics_frame # Finish its transform synchronization.
    assert(not director._sampler.valid(rear, player)) # Reject a wall-blocked approach.
    wall.free() # Restore an unobstructed route.
    floor_body.collision_layer = 0 # Simulate terrain whose render data lacks registered collision.
    await physics_frame # Synchronize removal of the streamed ground collision.
    await physics_frame # Finish physics query updates.
    assert(not director._sampler.valid(rear, player)) # Reject unloaded ground even when sampled height is available.
    floor_body.collision_layer = 1 # Restore loaded ground collision.
    await physics_frame # Register the floor again before spawning.
    await physics_frame # Finish ground collision synchronization.
    player.initialize_environment(null) # Simulate entering an isolated interior.
    assert(not director._try_spawn()) # Prevent radiant outdoor spawns while the player is indoors.
    player.initialize_environment(terrain) # Restore eligible outdoor gameplay.
    player.set_gameplay_input_enabled(false) # Simulate another menu owning player controls.
    assert(not director._try_spawn()) # Prevent an unsolicited event from stealing another menu's input.
    player.set_gameplay_input_enabled(true) # Restore ordinary input ownership.
    var spawned: bool = false # Track a bounded set of deterministic candidate attempts.
    for attempt: int in range(6): # Allow conservative placement to skip an unsuitable proposal.
        if director._try_spawn(): # Use production validation and actor construction.
            spawned = true # Record the first successfully hidden encounter actor.
            break # Keep the single-actor event invariant intact.
    assert(spawned) # Require an actual radiant actor on safe controlled ground.
    var npc: Villager = director._actor # Retain the production event actor for behavior assertions.
    assert(npc.role == "radiant_challenger" and npc.model_index in [0, 1, 2]) # Require supported humanoid encounter models.
    assert(RadiantSpawnSampler.is_offscreen(player.get_view_camera(), npc.global_position)) # Verify the full actor bounds were hidden at creation.
    assert(npc.get_affection() == AffectionState.NEUTRAL) # Require a peaceful invitation before any consent.
    assert(not director._try_spawn()) # Prevent duplicate event actors while one approaches.
    var first_distance: float = npc.global_position.distance_to(player.global_position) # Record the initial approach distance.
    for frame: int in range(1000): # Give ordinary collision-backed running time to reach the participant.
        await physics_frame # Let production Villager movement update without teleporting it.
        director._process(1.0 / 60.0) # Advance the real bounded director state machine.
        if director._state == RadiantEventDirector.State.TALKING: # Detect an automatically started conversation at arrival.
            break # Stop advancing once the menu owns gameplay input.
    assert(director._state == RadiantEventDirector.State.TALKING) # Require actual approach and automatic dialogue initiation.
    assert(npc.global_position.distance_to(player.global_position) < first_distance and npc.global_position.distance_to(player.global_position) <= 2.8) # Require visible running toward the player rather than distant dialogue.
    assert(npc.get_affection() == AffectionState.NEUTRAL and not player._gameplay_input_enabled) # Keep hostility pending while the consent menu owns input.
    var menu: DialogueMenu = dialogue.get_node("Menu") as DialogueMenu # Inspect the real editor-authored event choices.
    var decline: Button = menu.get_node("Shade/Margins/Center/Panel/Scroll/Content/Encounter/Decline") as Button # Resolve the peaceful refusal control.
    decline.pressed.emit() # Exercise explicit player refusal through production signal wiring.
    assert(npc.get_affection() == AffectionState.NEUTRAL and director._state == RadiantEventDirector.State.LEAVING) # Require refusal to preserve affection and trigger retreat.
    assert(player._gameplay_input_enabled) # Restore player controls after declining.
    director._process(0.25) # Apply the peaceful retreat through the production director.
    assert(npc.route[0] == director._departure) # Require refusal to steer back toward the validated rear spawn.
    npc.set_physics_process(false) # Keep the retreating actor stable during the next consent check.
    assert(dialogue.open_encounter(npc, RadiantEventPhrases.BATTLE_CHALLENGE)) # Reopen the invitation to exercise mapped cancellation independently.
    var cancel: InputEventAction = InputEventAction.new() # Model a project-mapped controller cancel press.
    cancel.action = "Button_B" # Use the actual game controller action.
    cancel.pressed = true # Represent a new cancellation press.
    dialogue._input(cancel) # Route cancellation through the production conversation input handler.
    assert(npc.get_affection() == AffectionState.NEUTRAL and player._gameplay_input_enabled) # Require closing the menu to remain a peaceful refusal.
    assert(dialogue.open_encounter(npc, RadiantEventPhrases.BATTLE_CHALLENGE)) # Reopen to test explicit battle acceptance.
    var accept: Button = menu.get_node("Shade/Margins/Center/Panel/Scroll/Content/Encounter/Accept") as Button # Resolve the authored consent control.
    accept.pressed.emit() # Agree to the battle through the actual UI signal.
    assert(npc.get_affection() == AffectionState.HATE) # Require affection to become hostile synchronously during the selection.
    assert(npc.get_social_record().affection.get_score() == AffectionState.HATE) # Require the actor's existing persistent social state to reflect acceptance.
    assert(player._gameplay_input_enabled and director._state == RadiantEventDirector.State.FIGHTING) # Release menu ownership before normal combat takes over.
    npc.combat.tick(0.01) # Exercise the existing hostility perception immediately after acceptance.
    assert(npc.combat.target == player and npc.combat.active) # Require existing combat to select and engage the player.
    accept.pressed.emit() # Simulate a stale event button signal after the menu has closed.
    assert(npc.get_affection() == AffectionState.HATE and director._state == RadiantEventDirector.State.FIGHTING) # Require consent effects to resolve only once.
    npc.health.apply_damage(100000) # End the accepted battle through ordinary NPC death.
    director._process(0.25) # Update the completed battle while its corpse is still nearby.
    assert(director._actor == npc) # Retain nearby corpse loot instead of immediately removing the actor.
    var event_record_id: String = str(npc.get_social_record().npc_id) # Retain the completed transient identity for cleanup verification.
    player.global_position += Vector3(0, 0, -120) # Move beyond the encounter retirement radius with the corpse behind the view.
    director._process(0.25) # Exercise conservative offscreen retirement.
    assert(director._state == RadiantEventDirector.State.IDLE and director._actor == null) # Release the event slot after safe actor retirement.
    assert(not LootSession.records.has(event_record_id)) # Avoid leaking records for permanently retired event actors.
    assert(director._remaining >= 180.0) # Require a cooldown before another unsolicited encounter.
    player.set_physics_process(false) # Stop the participant during scene teardown.
    game.queue_free() # Release controlled world, UI and event resources.
    await process_frame # Finish queued actor and scene cleanup.
    print("PASS radiant offscreen placement, water/wall/unloaded rejection, gameplay gates, running approach, automatic dialogue, refusal, cancellation, immediate hostility, combat, corpse retention and cooldown") # Report verified behavior.
    quit() # Complete the headless encounter regression.
