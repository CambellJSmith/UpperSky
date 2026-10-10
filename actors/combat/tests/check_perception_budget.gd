extends SceneTree # Exercise real combat selection without loading the procedural world.

class Actor extends CharacterBody3D: # Supply the combat contracts for isolated perception checks.
    var vitality: HealthState = HealthState.new() # Own persistent health for eligibility checks.
    var record: Dictionary = {} # Own identity and directed social state.
    func get_health_state() -> HealthState: return vitality # Expose health through the shared combat contract.
    func get_social_record() -> Dictionary: return record # Expose the actor identity for provocation.
    func get_social_space() -> Node: return get_parent() # Keep actors within one test space.
    func perform_action(_action: String) -> bool: return true # Accept a strike without animation assets.

class CountingCombat extends NpcCombat: # Measure actual searches rather than timer implementation details.
    var searches: int = 0 # Count perception queries performed by tick.
    func select_target() -> void: # Observe target selection while retaining its real behaviour.
        searches += 1 # Count each spatial search.
        super.select_target() # Run production candidate selection.

func _initialize() -> void: # Start once the tree is ready for spatial queries.
    run.call_deferred() # Defer fixture construction until initialization completes.

func run() -> void: # Verify bounded idle work and immediate hostility reactions.
    var scene: Node3D = Node3D.new() # Own the isolated actors.
    root.add_child(scene) # Attach the spatial test space.
    var actor: Actor = Actor.new() # Create a peaceful observer.
    actor.record = {"npc_id":"observer"} # Assign a stable social identity.
    scene.add_child(actor) # Make the observer queryable.
    actor.add_to_group("npc") # Include the observer in NPC perception.
    var player: Actor = Actor.new() # Create a nearby player stand-in.
    player.record = {"npc_id":"player"} # Supply identity for provocation checks.
    scene.add_child(player) # Make player position queryable.
    player.add_to_group("player") # Include player targeting.
    player.position = Vector3(0.0, 0.0, 1.0) # Keep the player within melee reach.
    var distant: Actor = Actor.new() # Create a remote NPC candidate.
    scene.add_child(distant) # Attach the remote candidate.
    distant.add_to_group("npc") # Include it in the global actor collection.
    distant.position = Vector3(1000.0, 0.0, 0.0) # Place the candidate outside perception range.
    var affection: AffectionState = AffectionState.new(100.0) # Begin with peaceful player affection.
    var combat: CountingCombat = CountingCombat.new() # Observe real combat searches.
    actor.add_child(combat) # Attach combat to the observer.
    combat.configure(actor, affection, actor.vitality) # Bind actor state and signals.
    combat._selection_timer = 0.0 # Begin a deterministic cadence observation window.
    for step: int in range(100): # Simulate idle ticks without real-time waiting.
        assert(not combat.tick(0.01), "Peaceful actor entered combat") # Preserve peaceful behaviour.
    assert(combat.searches >= 4 and combat.searches <= 5, "Targetless perception ignored its interval") # Reject per-tick search regressions.
    NearbyActorIndex.invalidate() # Refresh the fixture's current spatial membership.
    var nearby: Array[Node3D] = NearbyActorIndex.nearby(self, actor.global_position, NpcCombat.NOTICE_DISTANCE) # Inspect filtered candidates.
    assert(nearby.has(player) and not nearby.has(distant), "Spatial search returned distant actors") # Reject whole-population candidate regressions.
    affection.set_score(0.0) # Turn the nearby player hostile through the production signal.
    assert(combat.tick(0.01) and combat.target == player, "Hostility change waited for the perception timer") # Preserve immediate reactions.
    affection.set_score(100.0) # Pacify the observer during its strike windup.
    assert(not combat.tick(0.01) and not combat.attacking, "Pacification retained an attack") # Cancel pending damage immediately.
    var previous_searches: int = combat.searches # Record work before death.
    actor.vitality.set_health(0.0) # Make the observer unavailable for combat.
    for step: int in range(100): combat.tick(0.01) # Exercise repeated corpse updates.
    assert(combat.searches == previous_searches, "Dead actor performed perception work") # Skip useless corpse searches.
    scene.queue_free() # Release test actors.
    await process_frame # Complete queued teardown.
    NearbyActorIndex.invalidate() # Release cached fixture references.
    print("PASS bounded targetless searches, local candidates, immediate hostility, pacification and no corpse perception") # Report the validated behaviour.
    quit() # Finish the regression process.
