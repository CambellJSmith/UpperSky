extends SceneTree # Verify stable decoration batches and shared operation admission during LOD transitions.

class TrackedChunk extends WorldDecorationChunk: # Observe production transitions without changing their rendering behavior.
    var transition_frames: Array[int] = [] # Record actual changed detail frames.
    func set_lod_level(lod: int) -> void: # Track changed tiers before invoking production reuse.
        if get_lod_level() != lod: transition_frames.append(Engine.get_process_frames()) # Record only real transitions.
        super.set_lod_level(lod) # Preserve all production rendering behavior.

func _initialize() -> void: run.call_deferred() # Begin once scene ownership is available.

func run() -> void: # Exercise first visits, repeated visits and scheduled retained-chunk changes.
    var library: WorldDecorationMeshLibrary = WorldDecorationMeshLibrary.new() # Use real authored geometry and conservative bounds.
    var placements: Array[WorldDecorationPlacement] = [] # Supply deterministic tree and rock membership.
    for index: int in range(2): placements.append(WorldDecorationPlacement.new(WorldDecorationPlacement.Kind.TREE, index, Transform3D(Basis.IDENTITY, Vector3(index * 25, 0, 0)))) # Cover multiple tree draw groups.
    for index: int in range(12): placements.append(WorldDecorationPlacement.new(WorldDecorationPlacement.Kind.BOULDER, index % 3, Transform3D(Basis.IDENTITY, Vector3(index * 8, 0, 40)))) # Cover authored near, middle and far rock grouping.
    var chunk: WorldDecorationChunk = WorldDecorationChunk.new() # Use production retained rendering.
    root.add_child(chunk) # Attach every cached batch to real chunk ownership.
    chunk.configure(placements, library, WorldDecorationMeshLibrary.LOD_NEAR) # Install initial near scenery.
    var trees: Dictionary[int, MultiMeshInstance3D] = chunk._visual_batches._trees # Inspect retained identities in the regression fixture.
    var first_tree: MultiMeshInstance3D = trees[0] # Preserve the first tree group's node identity.
    var tree_buffer: PackedFloat32Array = first_tree.multimesh.buffer # Preserve its complete transform buffer.
    var tree_resource: int = first_tree.multimesh.get_instance_id() # Preserve its rendering resource identity.
    for lod: int in range(WorldDecorationMeshLibrary.LOD_COUNT): # Visit each authored detail alternative once.
        chunk.set_lod_level(lod) # Use production mesh swaps and lazy rock allocation.
        assert(trees[0] == first_tree and first_tree.multimesh.get_instance_id() == tree_resource and first_tree.multimesh.buffer == tree_buffer) # Keep tree transforms and resources unchanged.
        assert(first_tree.multimesh.mesh == library.get_tree_mesh(lod, 0)) # Swap only the shared tree geometry.
        var rocks: int = 0 # Count submitted rock membership at the active tier.
        for child: Node in chunk.get_children(): # Examine retained alternatives through real scene ownership.
            var node: MultiMeshInstance3D = child as MultiMeshInstance3D # Read each batched draw node.
            if not node.visible: continue # Exclude cached inactive alternatives from submitted membership.
            if str(node.name).begins_with("SmoothBoulders"): rocks += node.multimesh.instance_count # Count visible authored rock instances.
            assert(node.cast_shadow == (GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if lod == WorldDecorationMeshLibrary.LOD_FAR else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)) # Preserve distant shadow policy.
        assert(rocks == (6 if lod == WorldDecorationMeshLibrary.LOD_FAR else 12)) # Preserve deterministic far thinning and full near membership.
        var expected: AABB = placements[0].transform * library.get_tree_mesh(lod, 0).get_aabb() # Resolve this tier's real transformed silhouette.
        assert(first_tree.multimesh.custom_aabb.grow(0.001).encloses(expected)) # Prevent mesh swaps from escaping retained bounds.
    var identities: Array[int] = [] # Capture the bounded complete retained alternative set.
    for child: Node in chunk.get_children(): identities.append(child.get_instance_id()) # Track stable cached draw nodes.
    for lod: int in [0, 2, 1, 0, 2]: chunk.set_lod_level(lod) # Revisit every tier after caches are populated.
    var revisited: Array[int] = [] # Capture identities after repeated movement across boundaries.
    for child: Node in chunk.get_children(): revisited.append(child.get_instance_id()) # Inspect retained nodes again.
    assert(identities == revisited and chunk._visual_batches._rocks.size() == 3) # Bound cache growth and eliminate repeated node allocation.
    chunk.free() # Release every cached alternative with the chunk.
    var scheduler: GenerationScheduler = GenerationScheduler.new() # Use production shared engine-operation admission.
    root.add_child(scheduler) # Start actual frame budget ticks.
    var streamer: WorldDecorationStreamer = WorldDecorationStreamer.new() # Use production changed-tier queueing.
    root.add_child(streamer) # Enable scheduler owner validity.
    streamer.set_process(false) # Keep procedural startup outside the fixture.
    streamer._current_chunk_coordinate = Vector2i.ZERO # Establish current desired distance rings.
    var first: TrackedChunk = TrackedChunk.new() # Observe one middle-ring transition.
    var second: TrackedChunk = TrackedChunk.new() # Observe one far-ring transition.
    streamer.add_child(first) # Own the first retained chunk.
    streamer.add_child(second) # Own the second retained chunk.
    first.configure(placements, library, 0) # Begin with detail requiring a real change.
    second.configure(placements, library, 0) # Begin with another detail requiring a change.
    streamer._chunks[Vector2i(2, 0)] = first # Request authored middle detail.
    streamer._chunks[Vector2i(4, 0)] = second # Request authored far detail.
    streamer._queue_lod_updates() # Queue only actual changed tiers.
    assert(streamer._pending_lod_updates.size() == 2) # Avoid no-op queue slots.
    await scheduler.operation_checkpoint(streamer) # Consume this frame's admission as another generation owner would.
    streamer._profile__apply_pending_lod_updates() # Start the real asynchronous LOD consumer.
    assert(first.transition_frames.is_empty() and second.transition_frames.is_empty()) # Reject LOD operations in a frame whose admission was already consumed.
    var deadline: int = Time.get_ticks_msec() + 5000 # Bound cooperative transition completion.
    while streamer._lod_updating and Time.get_ticks_msec() < deadline: await process_frame # Resume through actual scheduler frames.
    assert(first.get_lod_level() == 1 and second.get_lod_level() == 2) # Install the desired real tiers.
    assert(first.transition_frames.size() == 1 and second.transition_frames.size() == 1 and first.transition_frames[0] != second.transition_frames[0]) # Separate costly changed chunks across frames.
    streamer._queue_lod_updates() # Revisit the same center without changing demand.
    assert(streamer._pending_lod_updates.is_empty()) # Skip all retained chunks already at the correct tier.
    streamer.free() # Release retained renderer alternatives and queue state.
    scheduler.free() # Unwind scheduler ownership.
    print("PASS persistent tree buffers, bounded rock alternatives, authored thinning/shadows/bounds and shared LOD operation admission") # Report behavioral coverage.
    quit() # Complete the regression process.
