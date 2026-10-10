extends SceneTree # Verify overlap reuse and slope-boundary invalidation independently of world generation.
func _initialize() -> void: # Begin the deterministic grid regression.
    var streamer: DenseGroundCoverStreamer = DenseGroundCoverStreamer.new() # Use production reuse rules.
    var samples: PackedFloat32Array = PackedFloat32Array() # Build a committed terrain grid.
    samples.resize(DenseGroundCoverStreamer.TERRAIN_MAP_RESOLUTION * DenseGroundCoverStreamer.TERRAIN_MAP_RESOLUTION) # Match the production grid dimensions.
    streamer._commit_map_samples(Vector2.ZERO, samples, samples) # Install a complete reusable map.
    for shift: Vector2 in [Vector2(32, 0), Vector2(-32, 0), Vector2(0, 32), Vector2(0, -32)]: # Exercise recentering on either side of the world origin.
        var reused: int = 0 # Count world samples retained during this move.
        for z: int in range(DenseGroundCoverStreamer.TERRAIN_MAP_RESOLUTION): # Visit every destination row.
            for x: int in range(DenseGroundCoverStreamer.TERRAIN_MAP_RESOLUTION): # Visit every destination column.
                var point: Vector2 = shift + Vector2(x, z) * DenseGroundCoverStreamer.TERRAIN_VERTEX_SPACING # Resolve the destination world coordinate.
                if streamer._cached_sample_index(point) >= 0: reused += 1 # Count exact overlapping samples.
        assert(reused == 1677, "A one-axis step did not preserve the expected overlap") # Confirm strip-only terrain sampling.
    assert(not streamer._can_reuse_coverage(Vector2i(0, 10), Vector2(32, 80), 10 * 43 + 4)) # Refresh the new clamped slope boundary.
    assert(not streamer._can_reuse_coverage(Vector2i(38, 10), Vector2(336, 80), 10 * 43 + 42)) # Refresh the old boundary that becomes an interior sample.
    assert(streamer._can_reuse_coverage(Vector2i(10, 10), Vector2(112, 80), 10 * 43 + 14)) # Preserve interior slopes with identical neighbors.
    streamer._dirty_mask_areas.append(Rect2(Vector2(100, 70), Vector2(24, 24))) # Simulate a local road notification.
    assert(not streamer._can_reuse_coverage(Vector2i(10, 10), Vector2(112, 80), 10 * 43 + 14)) # Refresh coverage inside the road area.
    assert(streamer._can_reuse_coverage(Vector2i(20, 10), Vector2(192, 80), 10 * 43 + 24)) # Preserve unaffected coverage elsewhere.
    assert(streamer._cached_sample_index(Vector2(1, 1)) == -1) # Reject unaligned sample reuse.
    streamer.free() # Release the fixture without starting gameplay.
    print("PASS grass overlap reuse, signed movement, slope borders and local road invalidation") # Report verified reuse rules.
    quit() # Complete the regression process.
