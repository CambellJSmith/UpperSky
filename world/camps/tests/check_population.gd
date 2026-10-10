extends SceneTree # Verify the camp population contract without running the game loop.

func _initialize() -> void: # Defer setup until the tree is available.
    run.call_deferred() # Allow autoload initialization to complete.

func run() -> void: # Exercise deterministic population and actual camp geometry.
    var scene: PackedScene = load("res://application/game/game.tscn") # Load actor composition before equipment dependencies.
    assert(scene != null) # Require the ordinary game composition to compile.
    var terrain: InfiniteTerrain = InfiniteTerrain.new() # Provide terrain conversion for generated camp scenery.
    root.add_child(terrain) # Give terrain a valid scene context.
    terrain.set_process(false) # Keep the test independent of terrain streaming.
    var sampler: CampSampler = CampSampler.new(terrain) # Reuse real geometry grounding.
    var counts: Dictionary = {} # Confirm all requested population sizes occur.
    var models: Dictionary = {} # Confirm both human models and orcs occur.
    for seed_value: int in range(100): # Cover deterministic variation across many camps.
        var definition: Dictionary = {"seed": seed_value, "position": Vector2(100, 100), "yaw": 0.7} # Supply a stable camp anchor.
        var residents: Array[Dictionary] = CampPopulation.definitions(definition) # Generate the camp membership.
        assert(residents == CampPopulation.definitions(definition)) # Require reload-stable identities and routes.
        assert(residents.size() >= 1 and residents.size() <= 4) # Enforce the requested population range.
        counts[residents.size()] = true # Record population coverage.
        var camp: Node3D = CampGeometry.new().build(sampler, definition.position, definition.yaw, seed_value) # Build the corresponding scenery.
        var tents: int = 0 # Count actual tent roots rather than predicted geometry.
        for child: Node in camp.get_children(): # Inspect the generated camp hierarchy.
            if child.name.begins_with("Tent"): # Identify tent roots.
                tents += 1 # Count one bedded tent per resident.
                assert(child.has_node("Bedroll")) # Require a usable bed in every tent.
        assert(tents == residents.size()) # Require exact tent and NPC parity.
        for resident: Dictionary in residents: # Validate appearance and every walking segment.
            models[resident.model] = true # Record supported appearance coverage.
            assert(resident.model in [0, 1, 2]) # Restrict campers to humans and orcs.
            for index: int in range(resident.route.size()): # Check entire routes including the closing edge.
                var point: Vector2 = resident.route[index] # Resolve the absolute waypoint.
                assert(point.distance_to(definition.position) < CampSampler.CAMP_RADIUS) # Keep wandering close to the camp.
                var next: Vector2 = resident.route[(index + 1) % resident.route.size()] # Inspect each closing segment.
                assert(point.lerp(next, 0.5).distance_to(definition.position) > 9.5) # Keep movement outside tents and fire furniture.
        camp.free() # Release procedural geometry between samples.
    assert(counts.size() == 4 and models.size() == 3) # Require complete count and appearance coverage.
    var actor_camp: Node3D = Node3D.new() # Exercise actors beneath an offset scenery root.
    actor_camp.position = Vector3(100, 0, 100) # Reproduce the camp streamer's transformed parent.
    root.add_child(actor_camp) # Activate actor lifecycle callbacks.
    var actor_definitions: Array[Dictionary] = CampPopulation.definitions({"seed": 7, "position": Vector2(100, 100), "yaw": 0.7}) # Provide ordinary camper routes.
    for model: int in range(3): # Instantiate each supported animated model.
        var actor_definition: Dictionary = actor_definitions[0].duplicate() # Keep the route shared while testing appearances.
        actor_definition.model = model # Exercise male human, female human and orc assets.
        actor_definition.seed = 900000 + model # Keep test loot identities distinct.
        var npc: Villager = Villager.new() # Exercise the actual camper actor implementation.
        npc.top_level = true # Match production independent actor transforms.
        npc.configure(terrain, actor_definition) # Initialize grounding and persistent state.
        var expected: Vector3 = npc.position # Preserve the configured local-world position.
        actor_camp.add_child(npc) # Exercise transformed-parent attachment.
        assert(npc.global_position.is_equal_approx(expected)) # Detect an erroneous doubled camp offset.
        assert(npc._animation.has_animation_library("Quaternius")) # Require working imported animations.
        npc.set_active(false) # Exercise dormant camper rebasing.
        terrain._world_origin_offset = Vector2(256, -256) # Simulate a completed floating-origin change.
        terrain.origin_shifted.emit() # Notify dormant actors using the production signal.
        assert(npc.global_position.is_equal_approx(terrain.world_to_local_position(npc.world_position))) # Require stable absolute placement after rebasing.
        assert(not npc.is_physics_processing()) # Keep distant residents dormant after rebasing.
        npc.set_active(true) # Exercise reactivation after returning to the camp.
        assert(npc.is_physics_processing()) # Require nearby campers to resume wandering.
        npc.free() # Release actor resources before testing the next model.
        terrain._world_origin_offset = Vector2.ZERO # Restore the starting origin between models.
    actor_camp.free() # Verify camp ownership can release all resident children.
    terrain.queue_free() # Release the test terrain.
    print("Camp population: deterministic counts, matching tents, human/orc models and bounded routes passed") # Report verified behavior.
    quit() # Complete the headless regression check.
