extends RefCounted
class_name WayshrineSampler
const CELL_SIZE: float = 1536.0
const CLEARING_RADIUS: float = 9.0
static var _shared: Dictionary = {}
var terrain: InfiniteTerrain
var ground: CampSampler
var settlements: SettlementSampler
var _cache: Dictionary = {}
static func for_terrain(value: InfiniteTerrain) -> WayshrineSampler:
    var id = value.get_instance_id()
    for old in _shared.keys():
        if _shared[old].terrain.get_ref() == null: _shared.erase(old)
    if not _shared.has(id): _shared[id] = {"terrain":weakref(value),"sampler":WayshrineSampler.new(value)}
    return _shared[id].sampler
func _init(value: InfiniteTerrain):
    terrain = value
    ground = CampSampler.new(value)
    settlements = SettlementSampler.for_terrain(value)
func sample_cell(cell: Vector2i) -> Dictionary:
    if _cache.has(cell): return _cache[cell]
    if _cache.size() >= 128: _cache.clear()
    var rng = RandomNumberGenerator.new()
    rng.seed = hash("wayshrine:%s:%s"%[TerrainHeightSampler.WORLD_SEED,cell])
    var result: Dictionary = {}
    if rng.randf() < .85:
        for attempt in range(32):
            var point = Vector2(cell)*CELL_SIZE+Vector2(rng.randf_range(64,CELL_SIZE-64),rng.randf_range(64,CELL_SIZE-64))
            if not suitable(point): continue
            var yaw = rng.randf()*TAU
            var landing = point+Vector2(0,4.8).rotated(-yaw)
            var titles = ["Dawn","Moon","Ember","Star","Winter","Moss","Storm","Sun"]
            var endings = ["reach","fall","watch","haven","veil","gate","rest","ward"]
            result = {"id":cell,"position":Vector3(point.x,ground.ground_height(point),point.y),"landing":Vector3(landing.x,ground.ground_height(landing)+.12,landing.y),"yaw":yaw,"style":rng.randi_range(0,2),"title":"%s%s Wayshrine"%[titles[rng.randi_range(0,7)],endings[rng.randi_range(0,7)]]}
            break
    _cache[cell] = result
    return result
func suitable(point: Vector2) -> bool:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        return _profile_suitable(point)
    var _profile_token = RuntimeProfiler.begin("wayshrines.check_ground")
    var _profile_result = _profile_suitable(point)
    RuntimeProfiler.end(_profile_token)
    return _profile_result

func _profile_suitable(point: Vector2) -> bool:
    var low = INF
    var high = -INF
    for z in range(-2,3):
        for x in range(-2,3):
            var sample = point+Vector2(x,z)*3
            if terrain.has_water_at(sample) or BiomeProfile.is_lava(sample) or ground.is_clearing(sample) or _settlement_obstruction(sample) or TerrainPathSampler.get_wilderness_grass_suppression(sample) > .1: return false
            var height = ground.ground_height(sample)
            low = minf(low,height)
            high = maxf(high,height)
            if high-low > 1.8: return false
    return true
func is_clearing(point: Vector2, padding: float = 0) -> bool:
    var cell = Vector2i(floori(point.x/CELL_SIZE),floori(point.y/CELL_SIZE))
    var definition = sample_cell(cell)
    return not definition.is_empty() and point.distance_to(Vector2(definition.position.x,definition.position.z)) < CLEARING_RADIUS+padding

func _settlement_obstruction(point: Vector2) -> bool:
    # Exclude whole town plots without generating the inter-town path plans.
    if settlements._within_town(point,16): return true
    var cell = Vector2i(floori(point.x/SettlementSampler.HOMESTEAD_CELL_SIZE),floori(point.y/SettlementSampler.HOMESTEAD_CELL_SIZE))
    var home = settlements.sample_homestead(cell)
    if home.is_empty(): return false
    return home.bounds.grow(8).has_point(SettlementSampler.rotate(point-home.position,-home.yaw))

func _settlement_obstruction_incremental(point: Vector2, scheduler: GenerationScheduler) -> bool:
    # Exclude whole town plots without generating the inter-town path plans.
    if await settlements._within_town_incremental(point,16,scheduler): return true
    var cell = Vector2i(floori(point.x/SettlementSampler.HOMESTEAD_CELL_SIZE),floori(point.y/SettlementSampler.HOMESTEAD_CELL_SIZE))
    var home = await settlements.sample_homestead_incremental(cell,scheduler)
    if home.is_empty(): return false
    return home.bounds.grow(8).has_point(SettlementSampler.rotate(point-home.position,-home.yaw))

func suitable_incremental(point: Vector2, scheduler: GenerationScheduler) -> bool:
    var low = INF
    var high = -INF
    for z in range(-2,3):
        if not await scheduler.checkpoint(): return false
        for x in range(-2,3):
            if not await scheduler.checkpoint(): return false
            var sample = point+Vector2(x,z)*3
            if terrain.has_water_at(sample) or BiomeProfile.is_lava(sample) or ground.is_clearing(sample) or await _settlement_obstruction_incremental(sample, scheduler) or TerrainPathSampler.get_wilderness_grass_suppression(sample) > .1: return false
            var height = ground.ground_height(sample)
            low = minf(low,height)
            high = maxf(high,height)
            if high-low > 1.8: return false
    return true

func sample_cell_incremental(cell: Vector2i, scheduler: GenerationScheduler) -> Dictionary:
    if _cache.has(cell): return _cache[cell]
    if _cache.size() >= 128: _cache.clear()
    var rng = RandomNumberGenerator.new()
    rng.seed = hash("wayshrine:%s:%s"%[TerrainHeightSampler.WORLD_SEED,cell])
    var result: Dictionary = {}
    if rng.randf() < .85:
        for attempt in range(32):
            if not await scheduler.checkpoint(): return {}
            var point = Vector2(cell)*CELL_SIZE+Vector2(rng.randf_range(64,CELL_SIZE-64),rng.randf_range(64,CELL_SIZE-64))
            if not await suitable_incremental(point, scheduler): continue
            var yaw = rng.randf()*TAU
            var landing = point+Vector2(0,4.8).rotated(-yaw)
            var titles = ["Dawn","Moon","Ember","Star","Winter","Moss","Storm","Sun"]
            var endings = ["reach","fall","watch","haven","veil","gate","rest","ward"]
            result = {"id":cell,"position":Vector3(point.x,ground.ground_height(point),point.y),"landing":Vector3(landing.x,ground.ground_height(landing)+.12,landing.y),"yaw":yaw,"style":rng.randi_range(0,2),"title":"%s%s Wayshrine"%[titles[rng.randi_range(0,7)],endings[rng.randi_range(0,7)]]}
            break
    _cache[cell] = result
    return result
