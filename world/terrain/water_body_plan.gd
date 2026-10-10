extends RefCounted # Defines shared water planning data.
class_name WaterBodyPlan # Defines shared water planning data.

# Each province is a closed watershed: lakes are terminal sinks, not implicit oceans.
# River reaches have explicit downhill connections and spring-fed upstream caps.
# Dry provincial borders make the infinite-world drainage contract independent of chunk order.
const GENERATION_VERSION: int = 2 # Defines shared water planning data.
const GRID_SPACING: float = TerrainConfiguration.CHUNK_SIZE / float(TerrainConfiguration.CHUNK_RESOLUTION - 1) # Defines shared water planning data.
const SHORE_WIDTH: float = 48.0 # Defines shared water planning data.
const SPAWN_DRY_RADIUS: float = 1500.0 # Defines shared water planning data.

static func definition_at(point: Vector2) -> Dictionary: # Keeps water planning deterministic in absolute coordinates.
    var cell: Vector2i = Vector2i((point / BiomeProfile.REGION_SIZE).floor()) # Defines shared water planning data.
    var biome: Dictionary = BiomeProfile.region(cell) # Defines shared water planning data.
    var local: Vector2 = point - Vector2(biome.centre) # Defines shared water planning data.
    var kind: int = int(biome.kind) # Defines shared water planning data.
    var reach: int = 0 # Defines shared water planning data.
    var level: float = float(biome.sea) # Defines shared water planning data.
    var boundary: float = 1100.0 - local.length() # Defines shared water planning data.
    var flow: Vector2 = Vector2.ZERO # Defines shared water planning data.
    if kind == BiomeProfile.Kind.RIVER_VALLEY: # Keeps water planning deterministic in absolute coordinates.
        reach = 0 if local.y < -320.0 else (1 if local.y < 320.0 else 2) # Keeps water planning deterministic in absolute coordinates.
        level += BiomeProfile.WATERFALL_DROP * float(2 - reach) # Keeps water planning deterministic in absolute coordinates.
        boundary = minf(120.0 - absf(local.x - BiomeProfile.river_x(local.y, float(biome.phase))), 1050.0 - absf(local.y)) # Keeps water planning deterministic in absolute coordinates.
        flow = Vector2(0.0, 1.0) if local.y < 800.0 else Vector2.ZERO # Keeps water planning deterministic in absolute coordinates.
    boundary = minf(boundary, point.length() - SPAWN_DRY_RADIUS) # Keeps water planning deterministic in absolute coordinates.
    var body_id: String = "watershed:%d:%d:reach:%d" % [cell.x, cell.y, reach] # Defines shared water planning data.
    var downstream_id: String = "watershed:%d:%d:reach:%d" % [cell.x, cell.y, reach + 1] if kind == BiomeProfile.Kind.RIVER_VALLEY and reach < 2 else "" # Defines shared water planning data.
    return {"body_id": body_id, "downstream_id": downstream_id, "surface_height": level, "boundary": boundary, "flow": flow, "kind": kind, "reach": reach, "region": cell} # Keeps water planning deterministic in absolute coordinates.

static func shape_height(point: Vector2, original: float) -> float: # Keeps water planning deterministic in absolute coordinates.
    var plan: Dictionary = definition_at(point) # Defines shared water planning data.
    var boundary: float = float(plan.boundary) # Defines shared water planning data.
    if boundary < -SHORE_WIDTH: # Keeps water planning deterministic in absolute coordinates.
        return original # Keeps water planning deterministic in absolute coordinates.
    var level: float = float(plan.surface_height) # Defines shared water planning data.
    var target: float = original # Defines shared water planning data.
    if boundary < SHORE_WIDTH * 2.0: # Keeps water planning deterministic in absolute coordinates.
        # A raised, continuous shore contains water even where old biome blends lower the land.
        target = maxf(original, level + 4.0 - maxf(boundary, 0.0) * 0.25) # Keeps water planning deterministic in absolute coordinates.
        return lerpf(original, target, smoothstep(-SHORE_WIDTH, 0.0, boundary) * (1.0 - smoothstep(0.0, SHORE_WIDTH * 2.0, boundary))) # Keeps water planning deterministic in absolute coordinates.
    if int(plan.kind) == BiomeProfile.Kind.RIVER_VALLEY: # Keeps water planning deterministic in absolute coordinates.
        # The plunge-pool bed drops before each lip, leaving space beneath the explicit curtain.
        var biome: Dictionary = BiomeProfile.region(Vector2i(plan.region)) # Defines shared water planning data.
        var local_z: float = point.y - Vector2(biome.centre).y # Defines shared water planning data.
        var bed: float = BiomeProfile.river_level(local_z + 24.0, float(biome.sea)) - 7.0 # Defines shared water planning data.
        target = minf(original, bed) # Keeps water planning deterministic in absolute coordinates.
    return lerpf(original, target, smoothstep(SHORE_WIDTH, SHORE_WIDTH * 2.0, boundary)) # Keeps water planning deterministic in absolute coordinates.

static func interpolate(values: PackedFloat32Array, fraction: Vector2) -> float: # Keeps water planning deterministic in absolute coordinates.
    if fraction.x + fraction.y <= 1.0: # Keeps water planning deterministic in absolute coordinates.
        return values[0] + fraction.x * (values[1] - values[0]) + fraction.y * (values[2] - values[0]) # Keeps water planning deterministic in absolute coordinates.
    return values[3] + (1.0 - fraction.y) * (values[1] - values[3]) + (1.0 - fraction.x) * (values[2] - values[3]) # Keeps water planning deterministic in absolute coordinates.
