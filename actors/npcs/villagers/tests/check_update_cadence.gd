extends SceneTree # Verify distant work reductions and elapsed-time preservation.

class FlatSpace extends Node3D: # Supply a clear route for real villager travel.
    func is_walkable(_point: Vector2) -> bool: return true # Accept the test's unobstructed route.

func _initialize() -> void: # Defer actor setup until the tree is ready.
    run.call_deferred() # Begin the regression outside initialization.

func run() -> void: # Check cadence independently and then exercise a real animated actor.
    var cadence: NpcUpdateCadence = NpcUpdateCadence.new() # Own an isolated timing policy.
    cadence.configure(7) # Exercise a staggered first deadline.
    cadence.distance_squared = 1000000.0 # Select distant timing.
    var physics_updates: int = 0 # Count expensive distant simulation steps.
    var animation_updates: int = 0 # Count distant skeleton evaluations.
    var physics_time: float = 0.0 # Accumulate time delivered to patrol movement.
    var animation_time: float = 0.0 # Accumulate time delivered to animation playback.
    for step: int in range(600): # Simulate a fixed observation duration.
        var movement: float = cadence.physics_step(1.0 / 60.0, false) # Query distant movement timing.
        var pose: float = cadence.animation_step(1.0 / 60.0, false) # Query distant pose timing.
        if movement > 0.0: physics_updates += 1 # Count only completed simulation updates.
        if pose > 0.0: animation_updates += 1 # Count only completed pose evaluations.
        physics_time += movement # Track elapsed patrol time.
        animation_time += pose # Track elapsed animation time.
    assert(physics_updates < 50 and animation_updates < 60, "Distant actor retained full update frequency") # Verify substantial work reduction.
    assert(absf(physics_time - 10.0) < 0.3 and absf(animation_time - 10.0) < 0.25, "Cadence lost elapsed time") # Preserve speed and playback progress.
    cadence.reset() # Remove deferred time at a streaming transition.
    assert(is_equal_approx(cadence.physics_step(1.0 / 60.0, true), 1.0 / 60.0), "Combat failed to receive an immediate update") # Preserve full-speed urgent updates.
    cadence.distance_squared = 0.0 # Bring the actor into the near-player region.
    for step: int in range(60): # Observe close movement and poses.
        assert(cadence.physics_step(1.0 / 60.0, false) > 0.0 and cadence.animation_step(1.0 / 60.0, false) > 0.0, "Nearby actor skipped an update") # Preserve smooth nearby behaviour.
    LootSession.records.clear() # Isolate generated actor persistence.
    var space: FlatSpace = FlatSpace.new() # Own a flat interior route.
    root.add_child(space) # Attach the route space.
    var player: Node3D = Node3D.new() # Supply player proximity without player movement.
    space.add_child(player) # Attach the player stand-in.
    player.add_to_group("player") # Let the real villager resolve it.
    player.position = Vector3(1000.0, 0.0, 0.0) # Keep travel on the distant simulation path.
    var route: Array[Vector2] = [Vector2.ZERO, Vector2(0.0, 100.0)] # Supply an unobstructed long patrol segment.
    var npc: Villager = Villager.new() # Instantiate production movement and animation.
    npc.configure_space(space, {"model":0,"role":"resident","seed":198317,"route":route}) # Bind a deterministic resident.
    space.add_child(npc) # Build the real visual rig and combat components.
    npc.set_process(false) # Keep animation advancement under test control.
    npc.set_physics_process(false) # Keep movement advancement under test control.
    npc.world_position = Vector3(0.0, 0.04, 0.0) # Begin at the route origin.
    npc._synchronize_world_position() # Apply the explicit test placement.
    npc._waypoint = 1 # Head toward the distant endpoint.
    npc._wait = 0.0 # Begin movement without an initial pause.
    npc._state = "walk" # Select ordinary walking speed.
    for step: int in range(600): npc._profile__physics_process(1.0 / 60.0) # Advance production distant travel.
    assert(absf(npc.world_position.z - 16.5) < 0.6, "Distant patrol speed changed") # Preserve elapsed-time travel speed.
    assert(npc.global_position.is_equal_approx(space.to_global(npc.world_position)), "Distant transform lost authoritative position") # Keep actor state aligned.
    space.queue_free() # Release the production actor and fixture.
    await process_frame # Complete scene teardown.
    print("PASS distant work reduction, elapsed time, full nearby and combat cadence, and real patrol speed") # Report regression coverage.
    quit() # Finish the regression process.
