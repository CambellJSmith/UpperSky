extends SceneTree # Compare rolling maps with full regeneration while measuring actual terrain queries.

class TerrainFixture extends InfiniteTerrain: # Supply a deterministic nonflat height field without streaming.
    var queries: int = 0 # Count actual terrain sampling work.
    func get_height_at(point: Vector2) -> float: # Exercise finite-difference slopes and floating point storage.
        queries += 1 # Record newly exposed terrain samples.
        return 400.0 + sin(point.x * 0.08) * 12.0 + cos(point.y * 0.045) * 8.0 # Produce reproducible varying terrain.
class WaterFixture extends TerrainWaterLevelSampler: # Keep water queries independent of procedural geological setup.
    func sample_water_level(_x: float, _z: float) -> float: return 100.0 # Supply a dry deterministic water plane.
class CampFixture extends CampSampler: # Remove unrelated world clearing generation from map parity.
    func is_clearing(_point: Vector2) -> bool: return false # Keep every fixture candidate outside camp clearings.
class SettlementFixture extends SettlementSampler: # Remove unrelated building generation from map parity.
    func is_clearing(_point: Vector2, _padding: float = 0.0) -> bool: return false # Keep fixture grass outside settlement clearings.
class ShrineFixture extends WayshrineSampler: # Keep shrine preparation deterministic during yielded map generation.
    func is_clearing(_point: Vector2, _padding: float = 0.0) -> bool: return false # Keep the fixture map outside shrine clearings.
    func sample_cell_incremental(_cell: Vector2i, _scheduler: GenerationScheduler) -> Dictionary: return {} # Avoid unrelated procedural shrine work.
class RoadFixture extends WorldPathNetwork: # Supply a changing localized road without regional searches.
    var area: Rect2 = Rect2(Vector2(24, 24), Vector2(72, 72)) # Define a deterministic road neighborhood.
    var mask: float = 0.0 # Control whether the fixture road has completed.
    func get_local_mask(point: Vector2, _grass: bool = false, _padding: float = 0.0) -> float: return mask if area.has_point(point) else 0.0 # Restrict suppression to the fixture corridor.

var _cancelled: Array[Dictionary] = [] # Capture asynchronous cancellation without storing a coroutine state.
func _initialize() -> void: run.call_deferred() # Start after scene ownership exists.

func make_streamer(terrain: TerrainFixture) -> DenseGroundCoverStreamer: # Compose production grass maps with deterministic fixture services.
    var streamer: DenseGroundCoverStreamer = DenseGroundCoverStreamer.new() # Use production map generation and overlap reuse.
    root.add_child(streamer) # Enable scheduler ownership checks.
    streamer.set_process(false) # Keep gameplay initialization outside this fixture.
    streamer._terrain = terrain # Use counted deterministic terrain samples.
    streamer._water_sampler = WaterFixture.new() # Supply deterministic water queries.
    streamer._camp_sampler = CampFixture.new(terrain) # Supply deterministic camp clearing rules.
    streamer._settlement_sampler = SettlementFixture.new(terrain) # Supply deterministic settlement clearing rules.
    streamer._coverage_noise = streamer._create_noise(1031, 0.0048, 2, 0.48) # Preserve production regional vegetation noise.
    streamer._terrain_image = Image.create_empty(43, 43, false, Image.FORMAT_RGF) # Stage production-format coverage pixels.
    streamer._terrain_texture = ImageTexture.create_from_image(streamer._terrain_image) # Exercise real texture storage.
    return streamer # Return the composed production fixture.

func capture_cancelled(streamer: DenseGroundCoverStreamer, origin: Vector2, scheduler: GenerationScheduler) -> void: # Collect a real stale yielded result.
    _cancelled.append(await streamer._generate_map_incremental(origin, scheduler)) # Preserve the production coroutine's cancellation outcome.

func run() -> void: # Exercise exact pixel parity across signed moves, road updates and teleports.
    var terrain: TerrainFixture = TerrainFixture.new() # Count production grass height sampling.
    root.add_child(terrain) # Initialize the underlying terrain service.
    terrain.set_process(false) # Keep unrelated chunk generation out of the fixture.
    terrain.set_physics_process(false) # Avoid requiring a tracked player.
    var shrine: ShrineFixture = ShrineFixture.new(terrain) # Supply shared fixture shrine queries.
    WayshrineSampler._shared[terrain.get_instance_id()] = {"terrain": weakref(terrain), "sampler": shrine} # Match production shared shrine lookup.
    var road: RoadFixture = RoadFixture.new(terrain) # Supply shared fixture path masks.
    WorldPathNetwork._networks[terrain.get_instance_id()] = weakref(road) # Match production road lookup.
    var rolling: DenseGroundCoverStreamer = make_streamer(terrain) # Retain committed overlap across consecutive moves.
    for origin: Vector2 in [Vector2.ZERO, Vector2(32, 0), Vector2.ZERO, Vector2(0, -32), Vector2(32, 0), Vector2(2048, -2048)]: # Cover signed one-axis moves, diagonal overlap and no-overlap travel.
        var expected_queries: int = 1849 # Default to a complete newly exposed grid.
        if rolling._cached_map_origin.is_finite(): # Count overlap before committing this destination.
            expected_queries = 0 # Count only samples absent from the committed grid.
            for z: int in range(43): # Visit destination rows.
                for x: int in range(43): # Visit destination columns.
                    if rolling._cached_sample_index(origin + Vector2(x, z) * 8) < 0: expected_queries += 1 # Count newly exposed world positions.
        terrain.queries = 0 # Isolate this move's actual sampling cost.
        rolling._terrain_map_world_origin = origin # Set the destination absolute map origin.
        rolling._profile__refresh_terrain_map() # Exercise the production synchronous fallback.
        assert(terrain.queries == expected_queries) # Verify overlap reuse through actual sampler calls.
        var reference: DenseGroundCoverStreamer = make_streamer(terrain) # Generate a fresh uncached map at the same destination.
        reference._terrain_map_world_origin = origin # Match the destination world grid.
        reference._profile__refresh_terrain_map() # Regenerate every reference sample normally.
        assert(rolling._terrain_image.get_data() == reference._terrain_image.get_data(), "Rolling grass differed from a full map") # Preserve exact terrain heights and coverage including edge slopes.
        reference.free() # Release the independent reference after comparison.
    rolling._terrain_map_world_origin = Vector2.ZERO # Return to the localized fixture road.
    rolling._profile__refresh_terrain_map() # Establish a committed road-free map.
    road.mask = 1.0 # Publish the fixture's completed road corridor.
    rolling._dirty_mask_areas.append(road.area) # Invalidate only affected coverage samples.
    terrain.queries = 0 # Measure road-only map changes.
    rolling._profile__refresh_terrain_map() # Recompute road coverage from retained terrain and water.
    assert(terrain.queries == 0) # Avoid all terrain sampling for a road-only change.
    var reference: DenseGroundCoverStreamer = make_streamer(terrain) # Build a complete fresh road-aware reference.
    reference._profile__refresh_terrain_map() # Sample the authoritative current road state.
    assert(rolling._terrain_image.get_data() == reference._terrain_image.get_data()) # Match full regeneration after local road publication.
    reference.free() # Release the road reference.
    var scheduler: GenerationScheduler = GenerationScheduler.new() # Use actual yielding generation ownership.
    root.add_child(scheduler) # Begin shared frame ticks.
    rolling._requested_centre = Vector2(168, 168) # Match the committed origin before asynchronous work.
    var generated: Dictionary = await rolling._generate_map_incremental(Vector2(32, 0), scheduler) # Exercise the same reuse path under cooperative yields.
    var fresh: DenseGroundCoverStreamer = make_streamer(terrain) # Build the full synchronous reference for the yielded result.
    fresh._terrain_map_world_origin = Vector2(32, 0) # Match the yielded destination grid.
    fresh._profile__refresh_terrain_map() # Generate an uncached reference at that destination.
    assert((generated.image as Image).get_data() == fresh._terrain_image.get_data()) # Preserve parity between synchronous and incremental reuse.
    fresh.free() # Release the final pixel reference.
    scheduler._deadline = 0 # Force an actual scheduler yield before stale work proceeds.
    capture_cancelled(rolling, Vector2(64, 0), scheduler) # Start work against the current request snapshot.
    rolling._requested_centre += Vector2(32, 0) # Move the requested center while generation is suspended.
    var deadline: int = Time.get_ticks_msec() + 5000 # Bound stale cancellation completion.
    while _cancelled.is_empty() and Time.get_ticks_msec() < deadline: await process_frame # Resume through production scheduler ticks.
    assert(_cancelled.size() == 1 and _cancelled[0].is_empty()) # Abandon stale map work rather than finishing obsolete sampling.
    rolling.free() # Release retained textures and sample caches.
    scheduler.free() # Unwind cooperative map ownership.
    terrain.free() # Release the shared fixture services.
    print("PASS exact grass pixels across signed/diagonal/teleport movement, terrain-query reuse, road-only updates and stale yielded cancellation") # Report end-to-end map coverage.
    quit() # Complete the regression process.
