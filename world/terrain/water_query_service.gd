extends RefCounted # Owns a detached water query cache without scene ownership.
class_name WaterQueryService # Exposes the authoritative water occupancy result.

const PRESENCE_EPSILON: float = 0.02 # Matches the shoreline clipping tolerance.
var _planner: WaterBodyPlan = WaterBodyPlan.new() # Avoids shared provincial locks during repeated gameplay queries.
var _height_provider: Callable # Reuses terrain corner caching when owned by a live world.
var _height_sampler: TerrainHeightSampler # Supplies final terrain when no world cache is available.
var _cell: Vector2i = Vector2i(2147483647, 2147483647) # Marks the corner cache as initially invalid.
var _ground: PackedFloat32Array = PackedFloat32Array() # Stores the final ground triangle corners.
var _boundaries: PackedFloat32Array = PackedFloat32Array() # Stores the planned footprint at the same corners.
var _definition: Dictionary = {} # Stores the owning body and reach for the active cell.

func _init(height_sampler: TerrainHeightSampler, height_provider: Callable = Callable()) -> void: # Captures terrain sampling without creating scene resources.
    _height_sampler = height_sampler # Retains the final terrain sampler.
    _height_provider = height_provider # Captures optional world cache access for gameplay queries.

func sample(point: Vector2) -> Dictionary: # Returns explicit occupancy, elevation, depth, identity and flow.
    var spacing: float = WaterBodyPlan.GRID_SPACING # Uses the rendered ground lattice.
    var cell: Vector2i = Vector2i((point / spacing).floor()) # Finds the globally aligned query cell.
    var origin: Vector2 = Vector2(cell) * spacing # Reconstructs its absolute origin.
    if cell != _cell: # Refreshes only when crossing a ground cell.
        _cell = cell # Records the cell owning the cached corners.
        _definition = _planner.definition(origin + Vector2.ONE * spacing * 0.5) # Resolves its body and calm reach elevation.
        _ground.clear() # Replaces the previous terrain corners.
        _boundaries.clear() # Replaces the previous footprint corners.
        for offset: Vector2 in [Vector2.ZERO, Vector2(spacing, 0.0), Vector2(0.0, spacing), Vector2.ONE * spacing]: # Visits corners in the final ground triangle order.
            var corner: Vector2 = origin + offset # Reconstructs each absolute ground vertex.
            _ground.append(float(_height_provider.call(corner)) if _height_provider.is_valid() else _height_sampler.sample_height(corner.x, corner.y)) # Reuses world heights or samples detached terrain.
            _boundaries.append(_planner.boundary(corner)) # Samples explicit body occupancy at that vertex.
    var fraction: Vector2 = (point - origin) / spacing # Locates the point inside its ground cell.
    var ground: float = WaterBodyPlan.interpolate(_ground, fraction) # Evaluates the actual rendered ground triangle.
    var boundary: float = WaterBodyPlan.interpolate(_boundaries, fraction) # Evaluates the linearly clipped body footprint.
    var level: float = float(_definition.surface_height) # Reads the cell surface shared with water generation.
    var present: bool = boundary > 0.0 and level - ground > PRESENCE_EPSILON # Requires both body membership and meaningful terrain clearance.
    return {"present": present, "surface_height": level if present else -INF, "ground_height": ground, "depth": maxf(0.0, level - ground) if present else 0.0, "body_id": _definition.body_id if present else "", "flow": _definition.flow if present else Vector2.ZERO, "downstream_id": _definition.downstream_id if present else ""} # Clears water identity and depth for dry results.
