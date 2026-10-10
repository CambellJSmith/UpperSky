extends TerrainWaterLevelSampler # Defines shared water planning data.
class_name SeamlessTerrainWaterLevelSampler # Defines shared water planning data.

func sample_water_level(world_x: float, world_z: float) -> float: # Keeps water planning deterministic in absolute coordinates.
    var point: Vector2 = Vector2(world_x, world_z) # Defines shared water planning data.
    var origin: Vector2 = (point / WaterBodyPlan.GRID_SPACING).floor() * WaterBodyPlan.GRID_SPACING # Defines shared water planning data.
    var plan: Dictionary = WaterBodyPlan.definition_at(origin + Vector2.ONE * WaterBodyPlan.GRID_SPACING * 0.5) # Defines shared water planning data.
    return float(plan.surface_height) if float(plan.boundary) > 0.0 else -INF # Keeps water planning deterministic in absolute coordinates.
