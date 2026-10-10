extends RefCounted
class_name CampSampler

const CELL_SIZE: float = 384.0
const CAMP_RADIUS: float = 12.0
const CLEARING_RADIUS: float = 18.0
const MAXIMUM_HEIGHT_VARIATION: float = 1.5
const MAXIMUM_GRADE: float = 0.14
const ATTEMPTS: int = 12
const CAMP_CHANCE: float = 0.80

var _terrain: InfiniteTerrain
var _cache: Dictionary[Vector2i, Dictionary] = {}

func _init(terrain: InfiniteTerrain) -> void:
    _terrain = terrain

func sample_cell(cell: Vector2i) -> Dictionary:
    if _cache.has(cell):
        return _cache[cell]
    CacheEviction.make_room(_cache, 256) # Evict old samples progressively during unbounded travel.
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = hash("camp:%d:%d:%d" % [TerrainHeightSampler.WORLD_SEED, cell.x, cell.y])
    var result: Dictionary = {}
    if rng.randf() < CAMP_CHANCE:
        for attempt: int in range(ATTEMPTS):
            var point: Vector2 = Vector2(cell) * CELL_SIZE + Vector2(rng.randf_range(48.0, CELL_SIZE - 48.0), rng.randf_range(48.0, CELL_SIZE - 48.0))
            if _is_suitable(point):
                result = {"position": point, "yaw": rng.randf_range(0.0, TAU), "seed": rng.randi()}
                break
    _cache[cell] = result
    return result

func is_clearing(point: Vector2) -> bool:
    var cell: Vector2i = Vector2i(floori(point.x / CELL_SIZE), floori(point.y / CELL_SIZE))
    # Candidate margins keep every clearing inside its owning cell.
    var camp: Dictionary = sample_cell(cell)
    return not camp.is_empty() and point.distance_to(camp["position"]) < CLEARING_RADIUS

func _is_suitable(point: Vector2) -> bool:
    var lowest: float = INF
    var highest: float = -INF
    for z: int in range(-3, 4):
        for x: int in range(-3, 4):
            var sample: Vector2 = point + Vector2(x, z) * 4.0
            if BiomeProfile.is_lava(sample):
                return false
            if _terrain.has_water_at(sample) or TerrainPathSampler.get_wilderness_grass_suppression(sample) > 0.1:
                return false
            var height: float = ground_height(sample)
            lowest = minf(lowest, height)
            highest = maxf(highest, height)
            if highest - lowest > MAXIMUM_HEIGHT_VARIATION:
                return false
            if absf(ground_height(sample + Vector2(2.0, 0.0)) - height) > 2.0 * MAXIMUM_GRADE:
                return false
            if absf(ground_height(sample + Vector2(0.0, 2.0)) - height) > 2.0 * MAXIMUM_GRADE:
                return false
    return true # Never force a camp onto rejected terrain.

func ground_height(point: Vector2) -> float:
    # Match the rendered terrain triangles instead of grounding on finer noise.
    var spacing: float = TerrainConfiguration.CHUNK_SIZE / float(TerrainConfiguration.CHUNK_RESOLUTION - 1)
    var corner: Vector2 = Vector2(floor(point.x / spacing), floor(point.y / spacing)) * spacing
    var fraction: Vector2 = (point - corner) / spacing
    var a: float = _terrain.get_height_at(corner)
    var b: float = _terrain.get_height_at(corner + Vector2(spacing, 0.0))
    var c: float = _terrain.get_height_at(corner + Vector2(0.0, spacing))
    if fraction.x + fraction.y <= 1.0:
        return a + (b - a) * fraction.x + (c - a) * fraction.y
    var d: float = _terrain.get_height_at(corner + Vector2(spacing, spacing))
    return d + (c - d) * (1.0 - fraction.x) + (b - d) * (1.0 - fraction.y)

func _is_suitable_incremental(point: Vector2, scheduler: GenerationScheduler) -> bool:
    var lowest: float = INF
    var highest: float = -INF
    for z: int in range(-3, 4):
        if not await scheduler.checkpoint(): return false
        for x: int in range(-3, 4):
            if not await scheduler.checkpoint(): return false
            var sample: Vector2 = point + Vector2(x, z) * 4.0
            if BiomeProfile.is_lava(sample):
                return false
            if _terrain.has_water_at(sample) or TerrainPathSampler.get_wilderness_grass_suppression(sample) > 0.1:
                return false
            var height: float = ground_height(sample)
            lowest = minf(lowest, height)
            highest = maxf(highest, height)
            if highest - lowest > MAXIMUM_HEIGHT_VARIATION:
                return false
            if absf(ground_height(sample + Vector2(2.0, 0.0)) - height) > 2.0 * MAXIMUM_GRADE:
                return false
            if absf(ground_height(sample + Vector2(0.0, 2.0)) - height) > 2.0 * MAXIMUM_GRADE:
                return false
    return true # Never force a camp onto rejected terrain.

func sample_cell_incremental(cell: Vector2i, scheduler: GenerationScheduler) -> Dictionary:
    if _cache.has(cell):
        return _cache[cell]
    CacheEviction.make_room(_cache, 256) # Evict old samples progressively during unbounded travel.
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = hash("camp:%d:%d:%d" % [TerrainHeightSampler.WORLD_SEED, cell.x, cell.y])
    var result: Dictionary = {}
    if rng.randf() < CAMP_CHANCE:
        for attempt: int in range(ATTEMPTS):
            if not await scheduler.checkpoint(): return {}
            var point: Vector2 = Vector2(cell) * CELL_SIZE + Vector2(rng.randf_range(48.0, CELL_SIZE - 48.0), rng.randf_range(48.0, CELL_SIZE - 48.0))
            if await _is_suitable_incremental(point, scheduler):
                result = {"position": point, "yaw": rng.randf_range(0.0, TAU), "seed": rng.randi()}
                break
    _cache[cell] = result
    return result
