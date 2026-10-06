extends RefCounted
class_name VillagerPopulationSampler

const TRAVEL_CELL: float = 512.0
var _terrain: InfiniteTerrain
var _settlements: SettlementSampler
var _cache: Dictionary = {}
var _paths: WorldPathNetwork
func _init(terrain: InfiniteTerrain):
    _terrain = terrain
    _settlements = SettlementSampler.for_terrain(terrain)
    _paths = WorldPathNetwork.for_terrain(terrain)

func town(definition: Dictionary) -> Array[Dictionary]:
    var points = _paths.town_walk_route(definition)
    if not route_safe(points): return []
    var result: Array[Dictionary] = []
    var starts = [0,1,4,7,8,12]
    for i in range(6): result.append(_definition(points,"resident",definition.seed+i*113,i%3,starts[i]))
    return result

func home(definition: Dictionary) -> Array[Dictionary]:
    var points = _paths.home_walk_route(definition)
    if not route_safe(points): return []
    return [_definition(points,"homesteader",definition.seed,definition.seed%3,0)]

func travellers(cell: Vector2i) -> Array[Dictionary]:
    if _cache.has(cell): return _cache[cell]
    var rng = RandomNumberGenerator.new()
    rng.seed = hash("villager-travellers:%s"%cell)
    var result: Array[Dictionary] = []
    if rng.randf() < .42:
        for attempt in range(12):
            var centre = (Vector2(cell)+Vector2(.5,.5))*TRAVEL_CELL
            var vertical: bool = rng.randf() < .5
            var points: Array[Vector2] = _paths.regional_route(centre,vertical)
            if Vector2(cell*int(TRAVEL_CELL)).distance_to(points[4]) > TRAVEL_CELL*1.5: continue
            if route_safe(points):
                # Return along the same checked trail, with pauses at either end.
                for i in range(points.size()-2,0,-1): points.append(points[i])
                result.append(_definition(points,"traveller",rng.randi(),rng.randi()%3,4))
                break
    if _cache.size() >= 128: _cache.erase(_cache.keys()[0])
    _cache[cell] = result
    return result

func route_safe(points: Array[Vector2]) -> bool:
    if points.size() < 2: return false
    for i in range(points.size()):
        var start = points[i]
        var end = points[(i+1)%points.size()]
        var steps = maxi(1,ceili(start.distance_to(end)/2.0))
        var previous: float = _settlements.ground_height(start)
        for step in range(steps+1):
            var p = start.lerp(end,float(step)/steps)
            if not _settlements._safe_ground(p) or is_obstructed(p): return false
            var h = _settlements.ground_height(p)
            if absf(h-previous) > .7: return false
            previous = h
    return true

func _definition(points: Array[Vector2],role: String,seed_value: int,model: int,start: int) -> Dictionary:
    return {"route":points,"role":role,"seed":seed_value,"model":model,"start":start}

func is_obstructed(point: Vector2) -> bool:
    var home_cell = Vector2i(floori(point.x/SettlementSampler.HOMESTEAD_CELL_SIZE),floori(point.y/SettlementSampler.HOMESTEAD_CELL_SIZE))
    var home = _settlements.sample_homestead(home_cell)
    if not home.is_empty() and home.bounds.grow(.5).has_point(SettlementSampler.rotate(point-home.position,-home.yaw)): return true
    var town_cell = Vector2i(floori(point.x/SettlementSampler.TOWN_CELL_SIZE),floori(point.y/SettlementSampler.TOWN_CELL_SIZE))
    var village = _settlements.sample_town(town_cell)
    if not village.is_empty():
        if point.distance_to(village.position+SettlementSampler.rotate(Vector2(-5,5),village.yaw)) < 2.1: return true
        for house in village.houses:
            if house.bounds.grow(.5).has_point(SettlementSampler.rotate(point-house.position,-house.yaw)): return true
    return _settlements._ground.is_clearing(point)

func is_obstructed_incremental(point: Vector2, scheduler: GenerationScheduler) -> bool:
    var home_cell = Vector2i(floori(point.x/SettlementSampler.HOMESTEAD_CELL_SIZE),floori(point.y/SettlementSampler.HOMESTEAD_CELL_SIZE))
    var home = await _settlements.sample_homestead_incremental(home_cell,scheduler)
    if not home.is_empty() and home.bounds.grow(.5).has_point(SettlementSampler.rotate(point-home.position,-home.yaw)): return true
    var town_cell = Vector2i(floori(point.x/SettlementSampler.TOWN_CELL_SIZE),floori(point.y/SettlementSampler.TOWN_CELL_SIZE))
    var village = await _settlements.sample_town_incremental(town_cell,scheduler)
    if not village.is_empty():
        if point.distance_to(village.position+SettlementSampler.rotate(Vector2(-5,5),village.yaw)) < 2.1: return true
        for house in village.houses:
            if not await scheduler.checkpoint(): return false
            if house.bounds.grow(.5).has_point(SettlementSampler.rotate(point-house.position,-house.yaw)): return true
    return _settlements._ground.is_clearing(point)

func route_safe_incremental(points: Array[Vector2], scheduler: GenerationScheduler) -> bool:
    if points.size() < 2: return false
    for i in range(points.size()):
        if not await scheduler.checkpoint(): return false
        var start = points[i]
        var end = points[(i+1)%points.size()]
        var steps = maxi(1,ceili(start.distance_to(end)/2.0))
        var previous: float = _settlements.ground_height(start)
        for step in range(steps+1):
            if not await scheduler.checkpoint(): return false
            var p = start.lerp(end,float(step)/steps)
            if not _settlements._safe_ground(p) or await is_obstructed_incremental(p, scheduler): return false
            var h = _settlements.ground_height(p)
            if absf(h-previous) > .7: return false
            previous = h
    return true

func travellers_incremental(cell: Vector2i, scheduler: GenerationScheduler) -> Array[Dictionary]:
    if _cache.has(cell): return _cache[cell]
    var rng = RandomNumberGenerator.new()
    rng.seed = hash("villager-travellers:%s"%cell)
    var result: Array[Dictionary] = []
    if rng.randf() < .42:
        for attempt in range(12):
            if not await scheduler.checkpoint(): return []
            var centre = (Vector2(cell)+Vector2(.5,.5))*TRAVEL_CELL
            var vertical: bool = rng.randf() < .5
            var points: Array[Vector2] = _paths.regional_route(centre,vertical)
            if Vector2(cell*int(TRAVEL_CELL)).distance_to(points[4]) > TRAVEL_CELL*1.5: continue
            if await route_safe_incremental(points, scheduler):
                # Return along the same checked trail, with pauses at either end.
                for i in range(points.size()-2,0,-1): points.append(points[i])
                result.append(_definition(points,"traveller",rng.randi(),rng.randi()%3,4))
                break
    if _cache.size() >= 128: _cache.erase(_cache.keys()[0])
    _cache[cell] = result
    return result

func town_incremental(definition: Dictionary, scheduler: GenerationScheduler) -> Array[Dictionary]:
    await _paths.town_routes_incremental(definition,scheduler)
    var points = _paths.town_walk_route(definition)
    if not await route_safe_incremental(points, scheduler): return []
    var result: Array[Dictionary] = []
    var starts = [0,1,4,7,8,12]
    for i in range(6): result.append(_definition(points,"resident",definition.seed+i*113,i%3,starts[i]))
    return result

func home_incremental(definition: Dictionary, scheduler: GenerationScheduler) -> Array[Dictionary]:
    await _paths.home_routes_incremental(definition,scheduler)
    var points = _paths.home_walk_route(definition)
    if not await route_safe_incremental(points, scheduler): return []
    return [_definition(points,"homesteader",definition.seed,definition.seed%3,0)]
