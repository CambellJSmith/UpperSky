extends RefCounted
class_name VillagerPopulationSampler

const TRAVEL_CELL: float = 256.0
var _terrain: InfiniteTerrain
var _settlements: SettlementSampler
var _cache: Dictionary = {}
var _validated_roads := {}
var traffic_wave: int = 0

func set_traffic_wave(value: int) -> void:
    if traffic_wave == value: return
    traffic_wave = value
    _cache.clear()
var _paths: WorldPathNetwork
func _init(terrain: InfiniteTerrain):
    _terrain = terrain
    _settlements = SettlementSampler.for_terrain(terrain)
    _paths = WorldPathNetwork.for_terrain(terrain)

func town(definition: Dictionary) -> Array[Dictionary]:
    if CityGeometry.is_city(definition): return []
    var points = _paths.town_walk_route(definition)
    if not route_safe(points): return []
    var result: Array[Dictionary] = []
    var starts = [0,1,4,7,8,12]
    for i in range(6): result.append(_definition(points,"resident",definition.seed+i*113,i%3,starts[i]))
    for i in range(2): result.append(_definition(points,"knight_patrol",definition.seed+7919+i*113,9,starts[2+i*3]))
    return result

func home(definition: Dictionary) -> Array[Dictionary]:
    var points = _paths.home_walk_route(definition)
    if not route_safe(points): return []
    return [_definition(points,"homesteader",definition.seed,definition.seed%3,0)]

func travellers(cell: Vector2i) -> Array[Dictionary]:
    if _cache.has(cell) and not _cache[cell].is_empty(): return _cache[cell]
    var result: Array[Dictionary] = []
    var accepted := 0
    for candidate in _encounter_candidates(cell):
        if not _validated_roads.has(candidate.journey.key):
            _validated_roads[candidate.journey.key] = route_safe(candidate.route, false)
        if not _validated_roads[candidate.journey.key]: continue
        result.append_array(_encounter_members(candidate))
        accepted += 1
        if accepted >= 6: break
    _remember_encounters(cell,result)
    return result

func _encounter_candidates(cell: Vector2i) -> Array[Dictionary]:
    # Whole checked roads have real settlement endpoints, unlike short trail loops.
    var centre := (Vector2(cell)+Vector2(.5,.5))*TRAVEL_CELL
    var candidates: Array[Dictionary] = []
    var seen := {}
    var available := _paths.cached_routes_in_chunk(cell) if GenerationScheduler.instance != null else _paths.routes_in_chunk(cell)
    for section in available:
        if section.kind not in ["arterial","connection"] or seen.has(section.get("key","")): continue
        var whole: Dictionary = _paths._roads.get(section.get("key",""),{})
        if whole.is_empty() or not whole.has_all(["from","to"]): continue
        seen[whole.key] = true
        var points: Array[Vector2] = []
        points.assign(whole.points)
        var start := 0
        var distance := INF
        for i in range(points.size()):
            if points[i].distance_squared_to(centre)<distance:
                distance = points[i].distance_squared_to(centre)
                start = i
        if distance > pow(TRAVEL_CELL*1.25,2): continue
        for party in range(2):
            var rng := RandomNumberGenerator.new()
            rng.seed = hash("road-traffic:%s:%d:%d"%[whole.key,traffic_wave,party])
            var count := rng.randi_range(3,5)
            var party_start := clampi(start+(3 if party==0 else -3),0,points.size()-1)
            candidates.append({"route":points,"start":party_start,"seed":rng.randi(),"count":count,"direction":1 if party==0 else -1,"kind":"road_party","journey":{"key":whole.key,"origin":whole.from,"destination":whole.to}})
    return candidates

func _encounter_members(candidate: Dictionary) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var rng := RandomNumberGenerator.new()
    rng.seed = candidate.seed
    var points: Array[Vector2] = []
    points.assign(candidate.route)
    var start: int = candidate.start
    for member in range(candidate.count):
        var seed_value: int = candidate.seed+member*113
        var model := posmod(candidate.seed,3) if member==0 else _traveller_model(rng.randi())
        var definition := _definition(points,"traveller",seed_value,model,start)
        definition["travel_direction"] = candidate.get("direction",1)
        definition["encounter"] = candidate.kind
        definition["journey"] = candidate.journey
        definition["leader_seed"] = candidate.seed
        definition["follow_gap"] = 2.5+member*2.0
        # Companions start a few metres apart on the same checked segment.
        definition["start_fraction"] = .8-member*.12
        result.append(definition)
    return result

func _remember_encounters(cell: Vector2i, result: Array[Dictionary]) -> void:
    if _cache.size() >= 128: _cache.erase(_cache.keys()[0])
    if _validated_roads.size()>256: _validated_roads.erase(_validated_roads.keys()[0])
    _cache[cell] = result

func route_safe(points: Array[Vector2], closed: bool = true) -> bool:
    if points.size() < 2: return false
    for i in range(points.size() if closed else points.size()-1):
        var start = points[i]
        var end = points[(i+1)%points.size()]
        var steps = maxi(1,ceili(start.distance_to(end)/2.0))
        var previous: float = _paths.walking_height(start)
        for step in range(steps+1):
            var p = start.lerp(end,float(step)/steps)
            var forbidden := not _settlements._safe_ground(p) if closed else (_terrain.has_water_at(p) or BiomeProfile.is_lava(p))
            if (forbidden and _paths.bridge_height(p) == null) or is_obstructed(p): return false
            var h = _paths.walking_height(p)
            if absf(h-previous) > .7: return false
            previous = h
    return true

func _definition(points: Array[Vector2],role: String,seed_value: int,model: int,start: int) -> Dictionary:
    return {"route":points,"role":role,"seed":seed_value,"model":model,"start":start}

func _traveller_model(random_value: int) -> int:
    var choice := posmod(random_value,12)
    if choice < 4: return 0
    if choice < 8: return 1
    if choice < 11: return 2
    return 7 if posmod(random_value/12,2)==0 else 9

func is_obstructed(point: Vector2) -> bool:
    var home_cell = Vector2i(floori(point.x/SettlementSampler.HOMESTEAD_CELL_SIZE),floori(point.y/SettlementSampler.HOMESTEAD_CELL_SIZE))
    var home = _settlements.sample_homestead(home_cell)
    if not home.is_empty() and home.bounds.grow(.5).has_point(SettlementSampler.rotate(point-home.position,-home.yaw)): return true
    var town_cell = Vector2i(floori(point.x/SettlementSampler.TOWN_CELL_SIZE),floori(point.y/SettlementSampler.TOWN_CELL_SIZE))
    var village = _settlements.sample_town(town_cell)
    if not village.is_empty():
        if CityGeometry.is_city(village):
            var local := SettlementSampler.rotate(point-village.position,-village.yaw)
            return CityGeometry.exterior_reserved(local,.6) and not (absf(local.x)<8.0 and local.y>=92.0 and local.y<=100.0)
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
        if CityGeometry.is_city(village):
            var local := SettlementSampler.rotate(point-village.position,-village.yaw)
            return CityGeometry.exterior_reserved(local,.6) and not (absf(local.x)<8.0 and local.y>=92.0 and local.y<=100.0)
        if point.distance_to(village.position+SettlementSampler.rotate(Vector2(-5,5),village.yaw)) < 2.1: return true
        for house in village.houses:
            if not await scheduler.checkpoint(): return false
            if house.bounds.grow(.5).has_point(SettlementSampler.rotate(point-house.position,-house.yaw)): return true
    return _settlements._ground.is_clearing(point)

func route_safe_incremental(points: Array[Vector2], scheduler: GenerationScheduler, closed: bool = true) -> bool:
    if points.size() < 2: return false
    for i in range(points.size() if closed else points.size()-1):
        if not await scheduler.checkpoint(): return false
        var start = points[i]
        var end = points[(i+1)%points.size()]
        var steps = maxi(1,ceili(start.distance_to(end)/2.0))
        var previous: float = _paths.walking_height(start)
        for step in range(steps+1):
            if not await scheduler.checkpoint(): return false
            var p = start.lerp(end,float(step)/steps)
            var forbidden := not _settlements._safe_ground(p) if closed else (_terrain.has_water_at(p) or BiomeProfile.is_lava(p))
            if (forbidden and _paths.bridge_height(p) == null) or await is_obstructed_incremental(p, scheduler): return false
            var h = _paths.walking_height(p)
            if absf(h-previous) > .7: return false
            previous = h
    return true

func travellers_incremental(cell: Vector2i, scheduler: GenerationScheduler) -> Array[Dictionary]:
    if _cache.has(cell) and not _cache[cell].is_empty(): return _cache[cell]
    await _paths.routes_in_chunk_incremental(cell,scheduler)
    if scheduler._closing: return []
    var result: Array[Dictionary] = []
    var accepted := 0
    for candidate in _encounter_candidates(cell):
        if not await scheduler.checkpoint(): return []
        if not _validated_roads.has(candidate.journey.key):
            _validated_roads[candidate.journey.key] = await route_safe_incremental(candidate.route,scheduler,false)
        if not _validated_roads[candidate.journey.key]: continue
        result.append_array(_encounter_members(candidate))
        accepted += 1
        if accepted >= 6: break
    _remember_encounters(cell,result)
    return result

func town_incremental(definition: Dictionary, scheduler: GenerationScheduler) -> Array[Dictionary]:
    _paths.local_routes(definition)
    if CityGeometry.is_city(definition): return []
    var points = _paths.town_walk_route(definition)
    if not await route_safe_incremental(points, scheduler): return []
    var result: Array[Dictionary] = []
    var starts = [0,1,4,7,8,12]
    for i in range(6): result.append(_definition(points,"resident",definition.seed+i*113,i%3,starts[i]))
    for i in range(2): result.append(_definition(points,"knight_patrol",definition.seed+7919+i*113,9,starts[2+i*3]))
    return result

func home_incremental(definition: Dictionary, scheduler: GenerationScheduler) -> Array[Dictionary]:
    _paths.local_routes(definition)
    var points = _paths.home_walk_route(definition)
    if not await route_safe_incremental(points, scheduler): return []
    return [_definition(points,"homesteader",definition.seed,definition.seed%3,0)]
