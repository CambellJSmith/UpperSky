extends MultiMeshInstance3D # Retains sampled flora candidates while roads change their visible membership.
class_name RoadFilteredFloraBatch # Keeps road filtering separate from procedural flora generation.

var _transforms: Array[Transform3D] = [] # Retain accepted terrain and noise results in deterministic order.
var _colours: Array[Color] = [] # Keep per-instance colour attached to its candidate.
var _limits: Array[float] = [] # Store each candidate's maximum admissible road suppression.
var _visible_candidates: PackedByteArray = PackedByteArray() # Track membership without moving immutable candidates.
var _world_origin: Vector2 = Vector2.ZERO # Anchor candidate positions independently of floating-origin movement.
var _dirty: bool = true # Track whether visible membership needs a buffer update.

func configure_candidates(transforms: Array[Transform3D], colours: Array[Color], limits: Array[float], origin: Vector2) -> void: # Retain the data needed for inexpensive road updates.
    visible = false # Hide default instance transforms until initial road filtering and upload finish.
    _transforms = transforms # Keep deterministic local transforms for restoration and filtering.
    _colours = colours # Preserve candidate colours across compaction.
    _limits = limits # Keep the probability-derived acceptance thresholds.
    _world_origin = origin # Bind the candidates to absolute world coordinates.
    _visible_candidates.resize(transforms.size()) # Allocate compact membership state.
    _visible_candidates.fill(1) # Begin with every terrain-valid candidate eligible.

func refresh_candidate(index: int, area: Rect2, query: Callable) -> void: # Recheck a candidate only inside the notified road neighborhood.
    var local_position: Vector3 = _transforms[index].origin # Read the retained grounding position.
    var position: Vector2 = _world_origin + Vector2(local_position.x, local_position.z) # Resolve the absolute road query position.
    if not area.has_point(position): return # Avoid querying roads outside the affected region.
    var suppression: float = float(query.call(position)) # Sample the current completed road geometry.
    var enabled: int = int(suppression < 0.995 and suppression <= _limits[index]) # Preserve the original probability and fully cleared corridor rules.
    if enabled == _visible_candidates[index]: return # Skip unchanged membership.
    _visible_candidates[index] = enabled # Retain the current candidate state.
    _dirty = true # Request one compacted batch upload.

func candidate_count() -> int: # Expose bounded filtering work without returning mutable candidate arrays.
    return _transforms.size() # Report the retained candidate count.

func needs_upload() -> bool: # Let the streamer skip engine operations when road visibility did not change.
    return _dirty # Report pending membership changes.

func apply_visibility() -> void: # Compact visible candidates while retaining the existing render node and resource.
    if not _dirty: return # Avoid redundant buffer construction and upload.
    var transforms: Array[Transform3D] = [] # Collect visible transforms in their original order.
    var colours: Array[Color] = [] # Collect the matching visible colours.
    for index: int in range(_transforms.size()): # Traverse retained candidates without world or noise sampling.
        if _visible_candidates[index] == 0: continue # Exclude road-cleared flora from submitted geometry.
        transforms.append(_transforms[index]) # Keep the candidate's unchanged transform.
        colours.append(_colours[index]) # Keep its matching appearance.
    multimesh.instance_count = transforms.size() # Resize only when a membership update is committed.
    if not transforms.is_empty(): multimesh.buffer = InstanceTransformBuffer.pack(transforms, colours) # Upload the complete compacted batch in one operation.
    visible = not transforms.is_empty() # Submit only complete nonempty visible membership.
    _dirty = false # Mark this visible membership as installed.
