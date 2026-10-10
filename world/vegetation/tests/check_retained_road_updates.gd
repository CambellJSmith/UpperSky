extends SceneTree # Verify road filtering preserves sampled transforms, render resources and unaffected collision.

class FloraFixture extends GroundFloraStreamer: # Supply deterministic roads without procedural world generation.
    var suppression: float = 1.0 # Control the road mask for the fixture.
    var queries: int = 0 # Count candidate road queries.
    func _road_suppression(_position: Vector2) -> float: # Replace the fixture's world query only.
        queries += 1 # Record filtering work.
        return suppression # Return the fixture's current road state.

func _initialize() -> void: run.call_deferred() # Wait for an active scene tree.

func run() -> void: # Exercise production retained-candidate components and coalescing.
    var arrays: Array = [] # Create a tiny shared visual mesh.
    arrays.resize(Mesh.ARRAY_MAX) # Match the production surface layout.
    arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD]) # Supply deterministic geometry.
    var mesh: ArrayMesh = ArrayMesh.new() # Allocate shared rendering geometry.
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays) # Upload the fixture surface.
    var library: WorldDecorationMeshLibrary = WorldDecorationMeshLibrary.new(true) # Avoid unrelated procedural mesh construction.
    for _index: int in range(TreeGeometry.VARIANT_COUNT * WorldDecorationMeshLibrary.LOD_COUNT): library._tree_meshes.append(mesh) # Supply each authored tree tier.
    for _index: int in range(WorldDecorationMeshLibrary.BOULDER_VARIANT_COUNT * WorldDecorationMeshLibrary.LOD_COUNT): library._boulder_meshes.append(mesh) # Supply each authored rock tier.
    var shape: SphereShape3D = SphereShape3D.new() # Supply one reusable physical part.
    for _index: int in range(TreeGeometry.VARIANT_COUNT): library._tree_collision_parts.append([{"shape": shape, "transform": Transform3D.IDENTITY}]) # Match authored tree collision metadata.
    var placements: Array[WorldDecorationPlacement] = [] # Retain deterministic tree candidates.
    for x: float in [8.0, 100.0]: placements.append(WorldDecorationPlacement.new(WorldDecorationPlacement.Kind.TREE, 0, Transform3D(Basis.IDENTITY, Vector3(x, 0, 8)))) # Separate affected and unaffected ownership.
    var decoration: WorldDecorationChunk = WorldDecorationChunk.new() # Use the actual retained decoration body.
    root.add_child(decoration) # Install rendering and physics in the fixture world.
    decoration.configure(placements, library, WorldDecorationMeshLibrary.LOD_NEAR) # Build initial visible membership.
    decoration.set_collision_active(true) # Install physical owners for both candidates.
    var unaffected_owner: int = decoration._collision_shape_owners[1] # Track the collider outside the changed road region.
    var area: Rect2 = Rect2(Vector2.ZERO, Vector2(20, 20)) # Limit the update to the first candidate.
    var road: Dictionary = {"mask": 1.0, "queries": 0} # Control the fixture's changing road state.
    var query: Callable = func(_point: Vector2) -> float: # Count production candidate filtering calls.
        road.queries += 1 # Record only actual road queries.
        return road.mask # Return the current completed-road mask.
    for index: int in range(decoration.candidate_count()): decoration.refresh_path_candidate(index, area, query) # Apply a narrow road neighborhood.
    decoration.commit_path_visibility() # Install changed visual and physical membership.
    assert(road.queries == 1 and decoration._placements.size() == 1) # Avoid queries and removals outside the dirty neighborhood.
    assert(decoration._collision_shape_owners == [unaffected_owner]) # Preserve the unaffected physical owner identity.
    road.mask = 0.0 # Simulate removal or replacement of a completed route.
    for index: int in range(decoration.candidate_count()): decoration.refresh_path_candidate(index, area, query) # Reconsider the retained hidden candidate.
    decoration.commit_path_visibility() # Restore road-safe visual and physical membership.
    assert(decoration._placements.size() == 2 and decoration._collision_shape_owners.has(unaffected_owner)) # Restore candidates without replacing surviving colliders.
    var flora: FloraFixture = FloraFixture.new() # Use the production road-notification consumer.
    root.add_child(flora) # Enable cooperative filtering validity checks.
    flora.set_process(false) # Keep procedural startup out of the fixture.
    flora._meshes = [mesh] # Supply shared geometry for the fixture species.
    var chunk: Node3D = Node3D.new() # Own one retained flora batch.
    flora.add_child(chunk) # Keep the batch in the active world.
    var transforms: Array[Transform3D] = [Transform3D(Basis(Vector3.UP, 0.3).scaled(Vector3(2, 3, 4)), Vector3(8, 4, 8)), Transform3D(Basis.IDENTITY, Vector3(100, 8, 8))] # Exercise rotation, scale and stable instance order.
    var colours: Array[Color] = [Color.RED, Color.BLUE] # Keep appearance tied to each candidate.
    var limits: Array[float] = [0.4, 0.4] # Represent retained probability thresholds.
    var batch: RoadFilteredFloraBatch = flora._add_batch(chunk, 0, transforms, colours, limits, Vector2.ZERO, false) # Create the production component without synchronous queries.
    assert(not batch.visible) # Hide default instance transforms until the initial batch upload completes.
    batch.apply_visibility() # Install initial visible membership.
    var expected_buffer: PackedFloat32Array = PackedFloat32Array([transforms[0].basis.x.x, transforms[0].basis.y.x, transforms[0].basis.z.x, 8, transforms[0].basis.x.y, transforms[0].basis.y.y, transforms[0].basis.z.y, 4, transforms[0].basis.x.z, transforms[0].basis.y.z, transforms[0].basis.z.z, 8, 1, 0, 0, 1, 1, 0, 0, 100, 0, 1, 0, 8, 0, 0, 1, 8, 0, 0, 1, 1]) # Match the documented row-major transform and colour layout.
    assert(batch.multimesh.buffer == expected_buffer) # Verify complete engine buffer storage without relying on the dummy renderer's individual-instance getter.
    var identity: int = batch.multimesh.get_instance_id() # Track the retained rendering resource.
    await flora._refresh_flora_batch(batch, area, null) # Apply the narrow road region without procedural resampling.
    assert(flora.queries == 1 and batch.multimesh.instance_count == 1) # Filter only the affected candidate.
    assert(batch.multimesh.buffer == expected_buffer.slice(16)) # Preserve the surviving candidate transform.
    assert(batch.multimesh.get_instance_id() == identity) # Retain the MultiMesh resource through road updates.
    flora.suppression = 0.0 # Reopen the fixture's road-cleared region.
    await flora._refresh_flora_batch(batch, area, null) # Restore the retained candidate.
    assert(batch.multimesh.instance_count == 2 and batch.multimesh.get_instance_id() == identity) # Restore flora without resource replacement.
    flora._chunks[Vector2i.ZERO] = chunk # Register the retained chunk for notifications.
    flora._on_paths_ready(Vector2i.ZERO) # Queue one road publication.
    flora._on_paths_ready(Vector2i.ZERO) # Repeat the same publication while work is pending.
    assert(flora._path_dirty.size() == 1 and not chunk.is_queued_for_deletion()) # Coalesce duplicate notifications without destroying scenery.
    flora.free() # Release retained flora fixtures.
    decoration.free() # Release visual and physical decoration fixtures.
    print("PASS retained road filtering, restoration, unaffected collision, bulk transforms, colours and coalescing") # Report production behavior coverage.
    quit() # Complete the regression process.
