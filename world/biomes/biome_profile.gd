extends RefCounted
class_name BiomeProfile

# Broad regions blend back into the existing temperate geology at their edges.
enum Kind { TEMPERATE, ICE_FLATS, RIVER_VALLEY, VOLCANIC_ISLANDS }
const REGION_SIZE: float = 4096.0
const CORE_RADIUS: float = 1200.0
const EDGE_RADIUS: float = 1800.0
const WATERFALL_DROP: float = 32.0
static var _regions_mutex = Mutex.new()
static var _regions: Dictionary[Vector2i, Dictionary] = {}

static func region_at(point: Vector2) -> Dictionary:
    return region(Vector2i(floori(point.x / REGION_SIZE), floori(point.y / REGION_SIZE)))

static func region(cell: Vector2i) -> Dictionary:
    _regions_mutex.lock()
    if _regions.has(cell):
        var cached = _regions[cell]
        _regions_mutex.unlock()
        return cached
    if _regions.size() >= 256:
        _regions.clear()
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = hash("biome:742913:%d:%d" % [cell.x, cell.y])
    var kind: int = rng.randi_range(Kind.ICE_FLATS, Kind.VOLCANIC_ISLANDS)
    # Make the first three distinctive regions discoverable around the starting province.
    if cell == Vector2i.ZERO:
        kind = Kind.ICE_FLATS
    elif cell == Vector2i(-1, 0):
        kind = Kind.RIVER_VALLEY
    elif cell == Vector2i(0, -1):
        kind = Kind.VOLCANIC_ISLANDS
    var centre: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5)) * REGION_SIZE
    centre += Vector2(rng.randf_range(-120.0, 120.0), rng.randf_range(-120.0, 120.0))
    # Align river lips with the shared 16-metre water grid for reliable seam joining.
    centre = centre.snapped(Vector2(16.0, 16.0))
    var result: Dictionary = {"kind": kind, "centre": centre, "sea": rng.randf_range(180.0, 360.0), "phase": rng.randf_range(0.0, TAU)}
    _regions[cell] = result
    _regions_mutex.unlock()
    return result

static func weight(point: Vector2, definition: Dictionary) -> float:
    var distance: float = point.distance_to(definition["centre"])
    return (1.0 - smoothstep(CORE_RADIUS, EDGE_RADIUS, distance)) * smoothstep(1400.0, 2000.0, point.length())

static func vegetation_weight(point: Vector2) -> float:
    var definition: Dictionary = region_at(point)
    if definition["kind"] == Kind.RIVER_VALLEY:
        return 1.0
    return 1.0 - weight(point, definition)

static func river_x(z: float, phase: float) -> float:
    return sin(z * 0.0022 + phase) * 150.0 + sin(z * 0.0051 + phase * 1.7) * 35.0

static func river_level(z: float, sea: float) -> float:
    # Two cascades connect three genuinely different river elevations.
    var first: float = 1.0 - smoothstep(-320.0, -304.0, z)
    var second: float = 1.0 - smoothstep(320.0, 336.0, z)
    return sea + WATERFALL_DROP * (first + second)

static func height(point: Vector2, original: float) -> float:
    var definition: Dictionary = region_at(point)
    var blend: float = weight(point, definition)
    if blend <= 0.0:
        return original
    var local: Vector2 = point - definition["centre"]
    var sea: float = definition["sea"]
    var phase: float = definition["phase"]
    var target: float = original
    match int(definition["kind"]):
        Kind.ICE_FLATS:
            var pool: float = smoothstep(0.05, 0.65, sin(local.x * 0.003 + phase) * 0.55 + cos(local.y * 0.004 - phase) * 0.45)
            target = sea + 3.5 - pool * 10.0 + sin(local.x * 0.006) * cos(local.y * 0.005) * 0.35
        Kind.RIVER_VALLEY:
            var channel_distance: float = absf(local.x - river_x(local.y, phase))
            var level: float = river_level(local.y, sea)
            # The bed drops before the lip; falling water has open space below it.
            var bed_level: float = river_level(local.y + 24.0, sea)
            var bank: float = smoothstep(44.0, 155.0, channel_distance)
            target = lerpf(bed_level - 7.0, level + 12.0 + 16.0 * sin(local.x * 0.0015) * sin(local.y * 0.002), bank)
            target += smoothstep(180.0, 700.0, channel_distance) * 65.0
        Kind.VOLCANIC_ISLANDS:
            target = sea - 38.0
            var radius: float = local.length()
            var angular_radius: float = polygon_radius(local.rotated(phase * 0.15), 9)
            var main_island: float = sea - 38.0 + 310.0 * clampf(1.0 - angular_radius / 650.0, 0.0, 1.0)
            # A broad raised rim surrounds a level crater floor and lava lake.
            main_island = lerpf(sea + 164.0, main_island, smoothstep(64.0, 100.0, radius))
            target = maxf(target, main_island)
            for offset: Vector2 in [Vector2(790.0, 270.0), Vector2(-660.0, -470.0), Vector2(120.0, -900.0)]:
                var island_distance: float = polygon_radius(local - offset.rotated(phase), 6)
                target = maxf(target, sea - 38.0 + 110.0 * clampf(1.0 - maxf(island_distance - 35.0, 0.0) / 320.0, 0.0, 1.0))
    return lerpf(original, target, blend)

static func water_height(point: Vector2, original: float) -> float:
    var definition: Dictionary = region_at(point)
    # Blend the land, never the water: each region/reach has a level surface.
    if weight(point, definition) < 0.5:
        return original
    var target: float = definition["sea"]
    if definition["kind"] == Kind.RIVER_VALLEY:
        var local_z: float = point.y - definition["centre"].y
        # Grid-aligned waterfall gaps belong to the lower plunge pool.
        if local_z < -320.0:
            target += WATERFALL_DROP * 2.0
        elif local_z < 320.0:
            target += WATERFALL_DROP
    return target

static func polygon_radius(point: Vector2, sides: int) -> float:
    var sector: float = TAU / float(sides)
    var angle: float = fposmod(atan2(point.y, point.x) + sector * 0.5, sector) - sector * 0.5
    return point.length() * cos(angle)

static func terrain_colour(point: Vector2, original: Color, normal: Vector3) -> Color:
    var definition: Dictionary = region_at(point)
    var blend: float = weight(point, definition)
    var local: Vector2 = point - definition["centre"]
    var target: Color = original
    match int(definition["kind"]):
        Kind.ICE_FLATS:
            target = Color(0.26, 0.49, 0.61, 0.0).lerp(Color(0.56, 0.69, 0.76, 0.0), smoothstep(0.82, 0.995, normal.y))
        Kind.RIVER_VALLEY:
            var distance: float = absf(local.x - river_x(local.y, definition["phase"]))
            var grass: Color = Color(0.22, 0.35, 0.27, 0.0)
            var bank: Color = Color(0.45, 0.42, 0.32, 0.0)
            target = bank.lerp(grass, smoothstep(120.0, 240.0, distance))
            target = target.lerp(Color(0.30, 0.36, 0.38, 0.0), 1.0 - smoothstep(0.5, 0.88, normal.y))
        Kind.VOLCANIC_ISLANDS:
            var coast: float = smoothstep(360.0, 650.0, local.length())
            target = Color(0.20, 0.23, 0.28, 0.0).lerp(Color(0.37, 0.32, 0.28, 0.0), coast)
            var sector: float = floor((atan2(local.y, local.x) + definition["phase"] * 0.15 + PI / 9.0) / (TAU / 9.0))
            target *= 0.97 + sin(sector * 1.73) * 0.075
            target.a = 0.0
    return original.lerp(target, blend)

static func is_lava(point: Vector2) -> bool:
    var definition: Dictionary = region_at(point)
    return definition["kind"] == Kind.VOLCANIC_ISLANDS and weight(point, definition) > 0.99 and point.distance_to(definition["centre"]) < 64.0

static func is_waterfall_gap(point: Vector2) -> bool:
    var definition: Dictionary = region_at(point)
    if definition["kind"] != Kind.RIVER_VALLEY or weight(point, definition) < 0.99:
        return false
    var z: float = point.y - definition["centre"].y
    return (z >= -320.0 and z < -304.0) or (z >= 320.0 and z < 336.0)

static func waterfall_pool_level(point: Vector2) -> float:
    var definition: Dictionary = region_at(point)
    return float(definition["sea"]) + (WATERFALL_DROP if point.y < definition["centre"].y else 0.0)
