extends SceneTree # Check collision reuse, memory bounds and physical activation.

func _initialize() -> void: run.call_deferred() # Wait for the active tree before adding fixtures.

func run() -> void: # Exercise real terrain chunks without procedural noise or scenery.
    var terrain: InfiniteTerrain = InfiniteTerrain.new() # Use the production cache owner.
    root.add_child(terrain) # Initialize shared terrain resources.
    terrain.set_process(false) # Keep generation under test control.
    terrain.set_physics_process(false) # Avoid requiring a tracked player.
    var arrays: Array = [] # Build a deterministic upward-facing triangle.
    arrays.resize(Mesh.ARRAY_MAX) # Match Godot's surface layout.
    var faces: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0), Vector3(0, 0, 10)]) # Supply exact CPU collision triangles.
    arrays[Mesh.ARRAY_VERTEX] = faces # Use identical visual and physical geometry.
    var ground: ArrayMesh = ArrayMesh.new() # Allocate one reusable fixture mesh.
    ground.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays) # Upload the deterministic triangle once.
    var water: ArrayMesh = ArrayMesh.new() # Provide an empty optional water mesh.
    var chunks: Array[TerrainChunk] = [] # Track collider fixtures for eviction checks.
    for index: int in range(InfiniteTerrain.INACTIVE_COLLISION_LIMIT + 2): # Exceed the retained inactive capacity.
        var chunk: TerrainChunk = TerrainChunk.new() # Allocate a production physics body.
        terrain.add_child(chunk) # Attach physics to the real world.
        chunk.configure(ground, water, faces) # Provide geometry without GPU readback.
        terrain._set_chunk_collision(chunk, true) # Activate exact collision through the cache owner.
        var identity: int = chunk._cached_collision.get_instance_id() # Preserve the shape identity across radius transitions.
        terrain._set_chunk_collision(chunk, false) # Simulate leaving the physical radius.
        assert(chunk._collision_shape.shape == null, "Inactive terrain still collides") # Exclude distant bodies from physics queries.
        terrain._set_chunk_collision(chunk, true) # Simulate returning to the same loaded chunk.
        assert(chunk._cached_collision.get_instance_id() == identity, "Returning rebuilt cached terrain collision") # Verify actual resource reuse.
        assert(chunk._cached_collision.get_faces() == faces, "Collision faces changed") # Preserve triangle winding and exact geometry.
        terrain._set_chunk_collision(chunk, false) # Return the shape to the inactive cache.
        chunks.append(chunk) # Retain the fixture for capacity checks.
    assert(terrain._inactive_collisions.size() == InfiniteTerrain.INACTIVE_COLLISION_LIMIT) # Bound retained collision during travel.
    assert(chunks[0]._cached_collision == null and chunks[1]._cached_collision == null) # Evict oldest inactive shapes.
    terrain._set_chunk_collision(chunks[0], true) # Rebuild a collider only after real eviction.
    assert(chunks[0]._cached_collision != null and chunks[0]._collision_shape.shape != null) # Restore usable physics after an evicted return.
    await physics_frame # Let the physics server register the reactivated body.
    await physics_frame # Allow the next physics tick to finish registration.
    var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(2, 5, 2), Vector3(2, -5, 2)) # Check physical ground rather than shape fields alone.
    assert(not root.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "Reactivated terrain had no ground") # Verify returned chunks remain walkable.
    terrain.free() # Release cache and physics fixtures together.
    print("PASS exact terrain collider reuse, inactive physics removal, bounded eviction and reactivated ground") # Report behavioral coverage.
    quit() # Complete the regression process.
