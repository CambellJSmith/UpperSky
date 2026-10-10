extends RefCounted # Retains decoration draw batches across distance and road membership changes.
class_name DecorationVisualBatches # Separates rendering resource reuse from chunk physics and streaming.

var _owner: Node3D # Owns the retained render nodes for the lifetime of one streamed chunk.
var _library: WorldDecorationMeshLibrary # Supplies shared meshes across all authored distance tiers.
var _tree_groups: Dictionary[int, Array] = {} # Keeps stable per-variant tree transforms independent of LOD.
var _rock_groups: Dictionary[int, Dictionary] = {} # Keeps pregrouped rock transforms for every authored tier.
var _trees: Dictionary[int, MultiMeshInstance3D] = {} # Reuses tree nodes and transform buffers while swapping shared meshes.
var _rocks: Dictionary[int, Dictionary] = {} # Lazily retains each visited tier's small rock batch set.
var _lod: int = -1 # Tracks the currently visible distance tier.

func _init(owner: Node3D, library: WorldDecorationMeshLibrary) -> void: # Binds retained rendering to one chunk and its shared mesh library.
    _owner = owner # Keep render nodes under the streamed chunk's ownership.
    _library = library # Reuse shared mesh resources rather than duplicating geometry.

func set_placements(placements: Array[WorldDecorationPlacement], lod: int) -> void: # Updates only groups whose retained membership changed.
    var tree_groups: Dictionary[int, Array] = {} # Stage tree membership without changing existing buffers.
    var rock_groups: Dictionary[int, Dictionary] = {} # Stage each tier's authored rock grouping.
    for tier: int in range(WorldDecorationMeshLibrary.LOD_COUNT): rock_groups[tier] = {} # Prepare the bounded authored tier set.
    var rock_sequence: int = 0 # Preserve deterministic far-distance thinning among visible rocks.
    for placement: WorldDecorationPlacement in placements: # Group retained transforms without procedural world sampling.
        if placement.kind == WorldDecorationPlacement.Kind.TREE: # Keep tree membership identical across all distance tiers.
            _append_transform(tree_groups, placement.variant, placement.transform) # Collect the shared tree variant once.
            continue # Skip rock grouping for tree candidates.
        for tier: int in range(WorldDecorationMeshLibrary.LOD_COUNT): # Prepare the small authored rock alternatives once per membership revision.
            if tier == WorldDecorationMeshLibrary.LOD_FAR and rock_sequence % 2 != 0: continue # Preserve authored far-distance rock thinning.
            var variant: int = placement.variant if tier == WorldDecorationMeshLibrary.LOD_NEAR else (posmod(placement.variant, 2) if tier == WorldDecorationMeshLibrary.LOD_MEDIUM else 0) # Preserve each tier's silhouette grouping.
            _append_transform(rock_groups[tier], variant, placement.transform) # Collect transforms without allocating rendering resources.
        rock_sequence += 1 # Advance the stable visible-rock thinning order.
    for variant: int in _trees.keys(): # Hide groups emptied by a road update while retaining their node identity.
        if not tree_groups.has(variant): # Detect a formerly visible variant with no current members.
            if not _tree_groups.get(variant, []).is_empty(): _write_batch(_trees[variant], [], _tree_bounds_meshes(variant)) # Clear only groups whose membership changed.
            _trees[variant].visible = false # Remove empty batches from rendering.
    for variant: int in tree_groups.keys(): # Update the bounded tree variant set.
        var transforms: Array = tree_groups[variant] # Retrieve stable current membership.
        if not _trees.has(variant): _trees[variant] = _new_batch("Trees_%d" % variant, _library.get_tree_mesh(lod, variant)) # Create each tree draw node only once.
        if transforms != _tree_groups.get(variant, []): _write_batch(_trees[variant], transforms, _tree_bounds_meshes(variant)) # Upload transforms only when roads changed group membership.
    for tier: int in _rocks.keys(): # Update only rock tiers that have actually been visited.
        var nodes: Dictionary = _rocks[tier] # Retrieve existing retained rock nodes.
        var groups: Dictionary = rock_groups[tier] # Retrieve this tier's current membership.
        var previous: Dictionary = _rock_groups.get(tier, {}) # Retrieve the previously uploaded grouping.
        for variant: int in nodes.keys(): # Clear cached variants emptied by roads.
            if not groups.has(variant) and not previous.get(variant, []).is_empty(): _write_batch(nodes[variant], [], [_library.get_boulder_mesh(variant, tier)]) # Release submitted membership without replacing the batch.
        for variant: int in groups.keys(): # Update changed cached variant groups.
            if not nodes.has(variant): nodes[variant] = _new_batch("SmoothBoulders_%d_LOD%d" % [variant, tier], _library.get_boulder_mesh(variant, tier)) # Allocate only newly populated retained groups.
            if groups[variant] != previous.get(variant, []): _write_batch(nodes[variant], groups[variant], [_library.get_boulder_mesh(variant, tier)]) # Upload only changed instance membership.
    _tree_groups = tree_groups # Retain current immutable tree membership for later comparisons.
    _rock_groups = rock_groups # Retain pregrouped rock alternatives for allocation-free revisits.
    _lod = -1 # Force visibility and mesh refresh after changed group membership.
    set_lod(lod) # Restore the active authored distance tier using retained batches.

func set_lod(lod: int) -> void: # Changes distance detail without regrouping placements or replacing existing tree buffers.
    if lod == _lod: return # Skip unchanged detail requests entirely.
    for variant: int in _trees.keys(): # Update the shared geometry and shadow policy for retained tree batches.
        var node: MultiMeshInstance3D = _trees[variant] # Retrieve the stable variant draw node.
        node.multimesh.mesh = _library.get_tree_mesh(lod, variant) # Swap only shared geometry while preserving instance data and conservative bounds.
        node.visible = not _tree_groups.get(variant, []).is_empty() # Submit only variants with visible road-safe members.
        node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if lod == WorldDecorationMeshLibrary.LOD_FAR else GeometryInstance3D.SHADOW_CASTING_SETTING_ON # Preserve the authored distant-shadow policy.
    if not _rocks.has(lod): # Allocate an authored rock alternative only on its first visit.
        var nodes: Dictionary[int, MultiMeshInstance3D] = {} # Retain this tier's small draw-group set.
        var groups: Dictionary = _rock_groups.get(lod, {}) # Reuse pregrouped transforms without another placement traversal.
        for variant: int in groups.keys(): # Build only the newly visited tier's rock groups.
            var mesh: ArrayMesh = _library.get_boulder_mesh(variant, lod) # Retrieve shared authored geometry.
            var node: MultiMeshInstance3D = _new_batch("SmoothBoulders_%d_LOD%d" % [variant, lod], mesh) # Create one retained draw node for this tier and silhouette.
            _write_batch(node, groups[variant], [mesh]) # Upload this alternative's transforms only once.
            nodes[variant] = node # Retain the batch for future visits to this tier.
        _rocks[lod] = nodes # Bound cached alternatives to the authored tier set and chunk lifetime.
    for tier: int in _rocks.keys(): # Toggle cached rock alternatives without deleting resources.
        var nodes: Dictionary = _rocks[tier] # Retrieve the tier's retained nodes.
        for variant: int in nodes.keys(): # Update only the small draw-group visibility state.
            var node: MultiMeshInstance3D = nodes[variant] # Retrieve the retained silhouette batch.
            node.visible = tier == lod and node.multimesh.instance_count > 0 # Draw exactly one authored rock alternative.
            node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if tier == WorldDecorationMeshLibrary.LOD_FAR else GeometryInstance3D.SHADOW_CASTING_SETTING_ON # Preserve near and middle grounding.
    _lod = lod # Record the installed visible tier.

func _append_transform(groups: Dictionary, variant: int, transform: Transform3D) -> void: # Adds one stable transform to a shared silhouette group.
    if not groups.has(variant): groups[variant] = [] # Allocate a CPU collection only for populated groups.
    groups[variant].append(transform) # Preserve deterministic placement order.

func _new_batch(node_name: String, mesh: Mesh) -> MultiMeshInstance3D: # Allocates one retained render node and instance resource.
    var data: MultiMesh = MultiMesh.new() # Allocate instance storage once for this group.
    data.transform_format = MultiMesh.TRANSFORM_3D # Configure full transforms before assigning instance capacity.
    data.mesh = mesh # Reuse the authored shared geometry.
    var node: MultiMeshInstance3D = MultiMeshInstance3D.new() # Create the group's stable draw node.
    node.name = node_name # Preserve readable diagnostic group names.
    node.multimesh = data # Bind the retained resource to the node.
    _owner.add_child(node) # Let chunk unloading free all cached alternatives together.
    return node # Return the stable rendering group.

func _tree_bounds_meshes(variant: int) -> Array[Mesh]: # Supplies every authored tree silhouette for conservative bounds across mesh swaps.
    var meshes: Array[Mesh] = [] # Collect the bounded authored detail alternatives.
    for tier: int in range(WorldDecorationMeshLibrary.LOD_COUNT): meshes.append(_library.get_tree_mesh(tier, variant)) # Include all tiers before transform buffers are installed.
    return meshes # Prevent a later richer silhouette from escaping cached visibility bounds.

func _write_batch(node: MultiMeshInstance3D, transforms: Array, meshes: Array) -> void: # Uploads one complete changed group with conservative CPU visibility bounds.
    node.multimesh.instance_count = transforms.size() # Allocate exactly current submitted membership.
    if transforms.is_empty(): return # Avoid uploading or calculating invalid bounds for empty groups.
    var mesh_bounds: AABB = (meshes[0] as Mesh).get_aabb() # Read shared mesh bounds once per changed group.
    for index: int in range(1, meshes.size()): mesh_bounds = mesh_bounds.merge((meshes[index] as Mesh).get_aabb()) # Cover every authored silhouette used by this buffer.
    var bounds: AABB = (transforms[0] as Transform3D) * mesh_bounds # Start bounds from a real retained transform.
    for index: int in range(1, transforms.size()): bounds = bounds.merge((transforms[index] as Transform3D) * mesh_bounds) # Accumulate conservative bounds without repeated engine mesh queries.
    node.multimesh.custom_aabb = bounds # Avoid automatic runtime bounds reconstruction.
    node.multimesh.buffer = InstanceTransformBuffer.pack(transforms) # Upload the complete changed transform buffer in one rendering-server operation.
