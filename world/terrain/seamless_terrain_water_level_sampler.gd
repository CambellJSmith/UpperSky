extends TerrainWaterLevelSampler # Implements planned elevations through the existing water sampler interface.
class_name SeamlessTerrainWaterLevelSampler # Keeps existing terrain and vegetation consumers on the shared body plan.

var _body_plan: WaterBodyPlan = WaterBodyPlan.new() # Reuses the immutable provincial blueprint without per-sample locking.

func boundary_at(point: Vector2) -> float: # Supports cheap rejection of points far outside planned bodies.
    return _body_plan.boundary(point) # Returns the shared signed footprint.

func sample_water_level(world_x: float, world_z: float) -> float: # Samples the owning calm body or explicitly reports an absent footprint.
    var point: Vector2 = Vector2(world_x, world_z) # Packs the absolute horizontal sample coordinate.
    var origin: Vector2 = (point / WaterBodyPlan.GRID_SPACING).floor() * WaterBodyPlan.GRID_SPACING # Aligns reach ownership with final ground cells.
    var centre: Vector2 = origin + Vector2.ONE * WaterBodyPlan.GRID_SPACING * 0.5 # Selects the same flat reach as the rendered ground cell.
    return _body_plan.surface_height(centre) if _body_plan.boundary(centre) > 0.0 else -INF # Reports no planned water outside explicit bodies.
