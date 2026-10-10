extends SceneTree # Verify full-footprint city support and actual entrance terrain connections.

const GAME: PackedScene = preload("res://application/game/game.tscn") # Resolve normal game and equipment dependencies before isolated terrain tests.

class SlopedTerrain extends InfiniteTerrain: # Model deterministic terrain in absolute world coordinates.
    func _ready() -> void: # Avoid procedural streaming during geometric assertions.
        pass # Keep this controlled sampler independent of chunk generation.
    func get_height_at(point: Vector2) -> float: # Provide sloped ground with an interior triangle-lattice depression.
        return 120.0 + point.x * 0.12 + point.y * 0.06 - (12.0 if point == Vector2(1000, 1000) else 0.0) # Exercise support below the centre and an extremum between arbitrary sampling points.
    func has_water_at(_point: Vector2) -> bool: # Keep the controlled entrance on dry ground.
        return false # Exclude water from this alignment regression.

func _initialize() -> void: # Run after normal autoload initialization.
    run.call_deferred() # Prepare the real scene tree and physics server.

func run() -> void: # Check placement, foundation support, ramp continuity and batching.
    assert(GAME != null) # Require the integrated game composition to compile.
    var terrain: SlopedTerrain = SlopedTerrain.new() # Supply authoritative triangle elevations.
    root.add_child(terrain) # Register terrain coordinate conversion.
    terrain.set_process(false) # Prevent uncontrolled terrain generation.
    terrain.set_physics_process(false) # Keep floating-origin changes explicit.
    var ground: CampSampler = CampSampler.new(terrain) # Use the production rendered-triangle query as the reference.
    var scheduler: GenerationScheduler = GenerationScheduler.new() # Exercise scheduled fitting alongside immediate construction.
    root.add_child(scheduler) # Initialize cooperative frame admission.
    for yaw: float in [0.0, 0.7, 2.4, 0.7854]: # Exercise axis alignment, rotated footprints and nearly parallel triangle edges.
        var centre: Vector2 = Vector2(100011.3, -99993.3) if yaw == 0.7854 else Vector2(1011.3, 1006.7) # Include distant negative coordinates while keeping roots off the vertex lattice.
        var definition: Dictionary = {"position": centre, "height": ground.ground_height(centre), "yaw": yaw, "seed": 300, "houses": [{"height": 999.0}]} # Include unrelated high house plots that must not raise the exterior.
        var fit: Dictionary = CityGroundAlignment.new(terrain, definition).fit() # Compute exact full-footprint extrema.
        var scheduled: Dictionary = await CityGroundAlignment.new(terrain, definition).fit_incremental(scheduler) # Compute the same fit through frame checkpoints.
        assert(fit == scheduled) # Require identical immediate and scheduled placement.
        for z: int in range(-61, 62): # Check the whole footprint against dense independent terrain queries.
            for x: int in range(-61, 62): # Include boundary and interior ground across both slopes.
                var local: Vector2 = Vector2(x, z) # Resolve this independent local surface sample.
                var height: float = ground.ground_height(centre + SettlementSampler.rotate(local, yaw)) - float(definition.height) # Read the actual rendered terrain under the city.
                assert(float(fit.bottom) < height and float(fit.base) > height) # Require solid support without clipping the retained upper surface.
        assert(float(fit.base) < 30.0) # Prevent distant house elevations from lifting the exterior into the sky.
        var profile: Array = fit.approach # Inspect the continuous prepared entrance profile.
        assert(is_equal_approx(float(profile.front().top), float(fit.base) + 1.6)) # Match the drawbridge surface at its actual end.
        assert(is_equal_approx(float(profile.back().top), float(profile.back().ground) + 0.05)) # Meet real ground at the road end.
        for index: int in range(profile.size() - 1): # Verify the complete ramp surface against independent terrain samples.
            for step: int in range(9): # Include each section's endpoints and interior walking positions.
                var fraction: float = float(step) / 8.0 # Resolve the local interpolation along this prism.
                var z: float = lerpf(float(profile[index].z), float(profile[index + 1].z), fraction) # Locate the sampled cross-section.
                var top: float = lerpf(float(profile[index].top), float(profile[index + 1].top), fraction) # Resolve the actual planar walking surface.
                for x: float in [-5.0, -2.5, 0.0, 2.5, 5.0]: # Check the full walking width.
                    var height: float = ground.ground_height(centre + SettlementSampler.rotate(Vector2(x, z), yaw)) - float(definition.height) # Query the independently interpolated terrain.
                    assert(top >= height + 0.049) # Reject terrain clipping through the visible approach.
        var exterior: Node3D = CityGeometry.exterior(definition, fit) # Build visible and collidable production city scenery.
        exterior.rotation.y = yaw # Apply the same rotation used by ground fitting.
        exterior.position = Vector3(centre.x, definition.height, centre.y) # Place the city at its original absolute root elevation.
        root.add_child(exterior) # Register all static collision shapes.
        await physics_frame # Synchronize authored city collision.
        await physics_frame # Finish physics transform registration.
        var probe: Vector3 = exterior.to_global(Vector3(0, lerpf(float(profile[-2].top), float(profile[-1].top), 0.5), 91.0)) # Aim at the terrain-connected end of the approach.
        var hit: Dictionary = exterior.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 10.0, probe - Vector3.UP * 20.0)) # Exercise real entrance walking collision.
        assert(not hit.is_empty() and absf(float(hit.position.y) - probe.y) < 0.01) # Require collision at the exact visible walking elevation.
        CityStaticBatch.build_sync(exterior) # Apply the actual streamed exterior batching path.
        assert(exterior.has_meta("city_gate") and exterior.get_meta("ground_alignment") == fit) # Retain gate and ground placement metadata through batching.
        await physics_frame # Synchronize collision reparenting after batching.
        await physics_frame # Finish collision synchronization.
        hit = exterior.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 10.0, probe - Vector3.UP * 20.0)) # Verify batched ramp collision remains at its fitted elevation.
        assert(not hit.is_empty() and absf(float(hit.position.y) - probe.y) < 0.01) # Preserve exact visible walking collision after scenery batching.
        exterior.position -= Vector3(256.0, 0.0, -256.0) # Simulate the production floating-origin translation.
        probe -= Vector3(256.0, 0.0, -256.0) # Rebase the matching walking probe.
        await physics_frame # Synchronize the rebased city collision.
        await physics_frame # Finish the transform update.
        hit = exterior.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 10.0, probe - Vector3.UP * 20.0)) # Recheck the entrance after origin rebasing.
        assert(not hit.is_empty() and absf(float(hit.position.y) - probe.y) < 0.01) # Keep terrain-fitted collision stable through origin shifts.
        exterior.free() # Release the tested exterior before the next orientation.
    scheduler.free() # Release generation admission resources.
    terrain.free() # Release controlled terrain state.
    print("PASS city full-footprint support, rotated triangle extrema, scheduled parity, ground-connected approach and batched collision") # Report all alignment assertions passing.
    quit() # Finish the bounded regression.
