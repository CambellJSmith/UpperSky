extends RefCounted # Defines shared water planning data.
class_name WaterQueryService # Defines shared water planning data.

const PRESENCE_EPSILON: float = 0.02 # Defines shared water planning data.
var _height_sampler: TerrainHeightSampler # Defines shared water planning data.
var _cell: Vector2i = Vector2i(2147483647, 2147483647) # Defines shared water planning data.
var _ground: PackedFloat32Array = PackedFloat32Array() # Defines shared water planning data.
var _boundaries: PackedFloat32Array = PackedFloat32Array() # Defines shared water planning data.
var _definition: Dictionary = {} # Defines shared water planning data.

func _init(height_sampler: TerrainHeightSampler) -> void: # Keeps water planning deterministic in absolute coordinates.
    _height_sampler = height_sampler # Keeps water planning deterministic in absolute coordinates.

func sample(point: Vector2) -> Dictionary: # Keeps water planning deterministic in absolute coordinates.
    var spacing: float = WaterBodyPlan.GRID_SPACING # Defines shared water planning data.
    var cell: Vector2i = Vector2i((point / spacing).floor()) # Defines shared water planning data.
    var origin: Vector2 = Vector2(cell) * spacing # Defines shared water planning data.
    if cell != _cell: # Keeps water planning deterministic in absolute coordinates.
        _cell = cell # Keeps water planning deterministic in absolute coordinates.
        _definition = WaterBodyPlan.definition_at(origin + Vector2.ONE * spacing * 0.5) # Keeps water planning deterministic in absolute coordinates.
        _ground.clear() # Keeps water planning deterministic in absolute coordinates.
        _boundaries.clear() # Keeps water planning deterministic in absolute coordinates.
        for offset: Vector2 in [Vector2.ZERO, Vector2(spacing, 0.0), Vector2(0.0, spacing), Vector2.ONE * spacing]: # Keeps water planning deterministic in absolute coordinates.
            var corner: Vector2 = origin + offset # Defines shared water planning data.
            _ground.append(_height_sampler.sample_height(corner.x, corner.y)) # Keeps water planning deterministic in absolute coordinates.
            _boundaries.append(float(WaterBodyPlan.definition_at(corner).boundary)) # Keeps water planning deterministic in absolute coordinates.
    var fraction: Vector2 = (point - origin) / spacing # Defines shared water planning data.
    var ground: float = WaterBodyPlan.interpolate(_ground, fraction) # Defines shared water planning data.
    var boundary: float = WaterBodyPlan.interpolate(_boundaries, fraction) # Defines shared water planning data.
    var level: float = float(_definition.surface_height) # Defines shared water planning data.
    var present: bool = boundary > 0.0 and level - ground > PRESENCE_EPSILON # Defines shared water planning data.
    return {"present": present, "surface_height": level if present else -INF, "ground_height": ground, "depth": maxf(0.0, level - ground) if present else 0.0, "body_id": _definition.body_id if present else "", "flow": _definition.flow if present else Vector2.ZERO, "downstream_id": _definition.downstream_id if present else ""} # Keeps water planning deterministic in absolute coordinates.
