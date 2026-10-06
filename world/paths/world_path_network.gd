extends RefCounted
class_name WorldPathNetwork

const CHUNK_SIZE: float = 256.0
const MAX_CONNECTION: float = 950.0
const CORE_COLOUR: Color = Color(.25,.20,.12)
const EDGE_COLOUR: Color = Color(.34,.28,.17)
static var _networks: Dictionary = {}
var _terrain: InfiniteTerrain
var _settlements: SettlementSampler
var _plans: Dictionary = {}
var _chunks: Dictionary = {}

static func for_terrain(terrain: InfiniteTerrain) -> WorldPathNetwork:
    var id = terrain.get_instance_id()
    if _networks.has(id):
        var existing = (_networks[id] as WeakRef).get_ref()
        if existing != null: return existing
    for key in _networks.keys():
        if (_networks[key] as WeakRef).get_ref() == null: _networks.erase(key)
    var network = WorldPathNetwork.new(terrain)
    _networks[id] = weakref(network)
    return network

func _init(terrain: InfiniteTerrain):
    _terrain = terrain
    _settlements = SettlementSampler.for_terrain(terrain)

func route(points: Array[Vector2], core: float, edge: float, kind: String) -> Dictionary:
    var bounds = Rect2(points[0],Vector2.ZERO)
    for p in points: bounds = bounds.expand(p)
    return {"points":points,"core":core,"edge":edge,"kind":kind,"bounds":bounds.grow(edge)}

func town_routes(town: Dictionary) -> Array[Dictionary]:
    var key = "town:%s:%s"%[town.position,town.seed]
    if _plans.has(key): return _plans[key]
    var result: Array[Dictionary] = []
    for ends in [[Vector2(-76,0),Vector2(76,0)],[Vector2(0,-76),Vector2(0,76)]]:
        var points: Array[Vector2] = []
        for p in ends: points.append(town.position+SettlementSampler.rotate(p,town.yaw))
        result.append(route(points,3.2,4.3,"street"))
    for house in town.houses:
        var points: Array[Vector2] = [town.position+SettlementSampler.rotate(house.path_start,town.yaw),town.position+SettlementSampler.rotate(house.path_end,town.yaw)]
        result.append(route(points,.75,1.25,"door"))
    # A square is represented by adjacent lanes in the same road data.
    for offset in [-6.0,-2.0,2.0,6.0]:
        var points: Array[Vector2] = [town.position+SettlementSampler.rotate(Vector2(-8,offset),town.yaw),town.position+SettlementSampler.rotate(Vector2(8,offset),town.yaw)]
        result.append(route(points,2.0,2.2,"square"))
    var exits: Array[Vector2] = []
    for p in [Vector2(-76,0),Vector2(76,0),Vector2(0,-76),Vector2(0,76)]: exits.append(town.position+SettlementSampler.rotate(p,town.yaw))
    _connect(result,exits,town)
    _remember(key,result)
    return result

func home_routes(home: Dictionary) -> Array[Dictionary]:
    var key = "home:%s:%s"%[home.position,home.seed]
    if _plans.has(key): return _plans[key]
    var p = home.recipe.resolve()
    var door = home.position+SettlementSampler.rotate(Vector2(0,-p.depth*.5-.8),home.yaw)
    var outside = home.position+SettlementSampler.rotate(Vector2(0,home.bounds.position.y-1.8),home.yaw)
    var result: Array[Dictionary] = []
    var entry: Array[Vector2] = [door,outside]
    result.append(route(entry,.75,1.25,"door"))
    var exits: Array[Vector2] = [outside]
    _connect(result,exits,home)
    _remember(key,result)
    return result

func town_walk_route(town: Dictionary) -> Array[Vector2]:
    var streets = town_routes(town)
    var extent: float = streets[0].points[0].distance_to(streets[0].points[1])*.5-18
    var lane: float = streets[0].core*.56
    var local: Array[Vector2] = [Vector2(-extent,-lane),Vector2(-extent*.5,-lane),Vector2(lane,-lane),Vector2(lane,-extent*.5),Vector2(lane,-extent),Vector2(lane,-extent*.5),Vector2(lane,-lane),Vector2(extent*.5,-lane),Vector2(extent,-lane),Vector2(extent*.5,-lane),Vector2(lane,-lane),Vector2(lane,extent*.5),Vector2(lane,extent),Vector2(lane,extent*.5),Vector2(lane,-lane),Vector2(-extent*.5,-lane)]
    var points: Array[Vector2] = []
    for p in local: points.append(town.position+SettlementSampler.rotate(p,town.yaw))
    return points

func home_walk_route(home: Dictionary) -> Array[Vector2]:
    var roads = home_routes(home)
    var outside: Vector2 = roads[0].points[-1]
    for road in roads:
        if road.kind == "connection":
            return [outside,outside.move_toward(road.points[1],5)]
    return [outside,outside.move_toward(roads[0].points[0],.7)]

func _remember(key: String, routes: Array[Dictionary]):
    if _plans.size() >= 128: _plans.erase(_plans.keys()[0])
    _plans[key] = routes

func regional_point(point: Vector2, vertical: bool) -> Vector2:
    if vertical:
        var line = round((point.x-TerrainPathSampler._get_vertical_meander(point.y))/TerrainPathSampler.PATH_SPACING)
        return Vector2(line*TerrainPathSampler.PATH_SPACING+TerrainPathSampler._get_vertical_meander(point.y),point.y)
    var line = round((point.y-TerrainPathSampler._get_horizontal_meander(point.x))/TerrainPathSampler.PATH_SPACING)
    return Vector2(point.x,line*TerrainPathSampler.PATH_SPACING+TerrainPathSampler._get_horizontal_meander(point.x))

func regional_route(centre: Vector2, vertical: bool, length: float = 192.0) -> Array[Vector2]:
    var result: Array[Vector2] = []
    var steps = maxi(1,ceili(length/16.0))
    for i in range(steps+1):
        var offset: float = -length*.5+length*i/steps
        var point = centre+(Vector2(0,offset) if vertical else Vector2(offset,0))
        # Choose one repeated road at the centre, avoiding a family switch along a curve.
        var anchor = regional_point(centre,vertical)
        if vertical: point.x = anchor.x-TerrainPathSampler._get_vertical_meander(centre.y)+TerrainPathSampler._get_vertical_meander(point.y)
        else: point.y = anchor.y-TerrainPathSampler._get_horizontal_meander(centre.x)+TerrainPathSampler._get_horizontal_meander(point.x)
        result.append(point)
    return result

func routes_in_chunk(cell: Vector2i) -> Array[Dictionary]:
    if _chunks.has(cell): return _chunks[cell]
    var bounds = Rect2(Vector2(cell)*CHUNK_SIZE,Vector2.ONE*CHUNK_SIZE)
    var result: Array[Dictionary] = []
    # Regional roads and settlement lanes are rendered by the same chunk builder.
    for vertical in [true,false]:
        var centre = bounds.get_center()
        var anchor = regional_point(centre,vertical)
        for offset in [-TerrainPathSampler.PATH_SPACING,0.0,TerrainPathSampler.PATH_SPACING]:
            var road_centre = anchor+(Vector2(offset,0) if vertical else Vector2(0,offset))
            var points = regional_route(road_centre,vertical,CHUNK_SIZE+64)
            var road = route(points,TerrainPathSampler.PATH_CORE_RADIUS,TerrainPathSampler.PATH_EDGE_RADIUS,"regional")
            if road.bounds.grow(2).intersects(bounds): result.append(road)
    var area = bounds.grow(MAX_CONNECTION)
    for kind in ["town","home"]:
        var size: float = SettlementSampler.TOWN_CELL_SIZE if kind == "town" else SettlementSampler.HOMESTEAD_CELL_SIZE
        var start = Vector2i(floori(area.position.x/size),floori(area.position.y/size))
        var end = Vector2i(floori(area.end.x/size),floori(area.end.y/size))
        for z in range(start.y,end.y+1):
            for x in range(start.x,end.x+1):
                var definition = _settlements.sample_town(Vector2i(x,z)) if kind == "town" else _settlements.sample_homestead(Vector2i(x,z))
                if definition.is_empty(): continue
                var routes = town_routes(definition) if kind == "town" else home_routes(definition)
                for road in routes:
                    if road.bounds.grow(2).intersects(bounds): result.append(road)
    if _chunks.size() >= 128: _chunks.erase(_chunks.keys()[0])
    _chunks[cell] = result
    return result

func get_local_mask(point: Vector2, grass: bool = false, padding: float = 0.0) -> float:
    var cell = Vector2i(floori(point.x/CHUNK_SIZE),floori(point.y/CHUNK_SIZE))
    var mask: float = 0
    for road in routes_in_chunk(cell):
        if road.kind == "regional" or not road.bounds.grow((2 if grass else 0)+padding).has_point(point): continue
        var core: float = road.core+(1.0 if grass else 0.0)+padding
        var edge: float = road.edge+(2.0 if grass else 0.0)+padding
        for i in range(road.points.size()-1):
            var distance = SettlementSampler._segment_distance(point,road.points[i],road.points[i+1])
            mask = maxf(mask,1-smoothstep(core,edge,distance))
    return mask

func _connect(result: Array[Dictionary], exits: Array[Vector2], owner: Dictionary):
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__connect(result, exits, owner)
        return
    var _profile_token = RuntimeProfiler.begin("paths.connect")
    _profile__connect(result, exits, owner)
    RuntimeProfiler.end(_profile_token)

func _profile__connect(result: Array[Dictionary], exits: Array[Vector2], owner: Dictionary):
    var candidates: Array[Dictionary] = []
    for exit in exits:
        for vertical in [true,false]:
            for along in [0.0,-96.0,96.0,-192.0,192.0]:
                var target = regional_point(exit+(Vector2(0,along) if vertical else Vector2(along,0)),vertical)
                if exit.distance_to(target) <= MAX_CONNECTION and _safe(target,owner):
                    candidates.append({"start":exit,"end":target,"distance":exit.distance_squared_to(target)})
    candidates.sort_custom(func(a,b): return a.distance < b.distance)
    # One usable connection is enough to attach this settlement to the regional network.
    for i in range(mini(6,candidates.size())):
        var path = _find_connection(candidates[i].start,candidates[i].end,owner)
        if path.size() > 1:
            result.append(route(path,2.2,3.2,"connection"))
            return

func _safe(point: Vector2, owner: Dictionary) -> bool:
    if not _settlements._safe_ground(point) or _settlements._ground.is_clearing(point): return false
    if owner.has("houses"):
        for house in owner.houses:
            if house.bounds.grow(3.4).has_point(SettlementSampler.rotate(point-house.position,-house.yaw)): return false
    elif owner.bounds.grow(1.4).has_point(SettlementSampler.rotate(point-owner.position,-owner.yaw)): return false
    # Other nearby settlements reserve their footprints too. Placement samples
    # use the base terrain, so this query cannot recurse into the road network.
    var home_cell = Vector2i(floori(point.x/SettlementSampler.HOMESTEAD_CELL_SIZE),floori(point.y/SettlementSampler.HOMESTEAD_CELL_SIZE))
    var home = _settlements.sample_homestead(home_cell)
    if not home.is_empty() and home.position != owner.position and home.bounds.grow(3.4).has_point(SettlementSampler.rotate(point-home.position,-home.yaw)): return false
    var town_cell = Vector2i(floori(point.x/SettlementSampler.TOWN_CELL_SIZE),floori(point.y/SettlementSampler.TOWN_CELL_SIZE))
    var town = _settlements.sample_town(town_cell)
    if not town.is_empty():
        if point.distance_to(town.position+SettlementSampler.rotate(Vector2(-5,5),town.yaw)) < 4: return false
        for house in town.houses:
            if house.bounds.grow(3.4).has_point(SettlementSampler.rotate(point-house.position,-house.yaw)): return false
    return true

func _find_connection(start: Vector2, end: Vector2, owner: Dictionary) -> Array[Vector2]:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        return _profile__find_connection(start, end, owner)
    var _profile_token = RuntimeProfiler.begin("paths.find_connection")
    var _profile_result = _profile__find_connection(start, end, owner)
    RuntimeProfiler.end(_profile_token)
    return _profile_result

func _profile__find_connection(start: Vector2, end: Vector2, owner: Dictionary) -> Array[Vector2]:
    var direct_heights: Dictionary = {}
    if _edge_safe(start,end,owner,direct_heights): return [start,end]
    var step: float = 16.0
    var start_cell = Vector2i(roundi(start.x/step),roundi(start.y/step))
    var end_cell = Vector2i(roundi(end.x/step),roundi(end.y/step))
    var area = Rect2(start,Vector2.ZERO).expand(end).grow(128)
    var open: Array[Vector2i] = [start_cell]
    var cost: Dictionary = {start_cell:0.0}
    var parents: Dictionary = {}
    var heights: Dictionary = {}
    var closed: Dictionary = {}
    var found = false
    for iteration in range(1600):
        if open.is_empty(): break
        var best = 0
        var score: float = INF
        for i in range(open.size()):
            var value: float = cost[open[i]]+Vector2(open[i]-end_cell).length()*step
            if value < score: best = i; score = value
        var current = open[best]
        open.remove_at(best)
        if current == end_cell: found = true; break
        closed[current] = true
        var a = start if current == start_cell else Vector2(current)*step
        var ah: float = _height(a,heights)
        for direction in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]:
            var next: Vector2i = current+direction
            if closed.has(next): continue
            var b = end if next == end_cell else Vector2(next)*step
            if not area.has_point(b) or not _safe(b,owner): continue
            var bh: float = _height(b,heights)
            var length = a.distance_to(b)
            if absf(bh-ah) > length*.27 or not _edge_safe(a,b,owner,heights): continue
            var new_cost: float = cost[current]+length+absf(bh-ah)*4
            if cost.has(next) and cost[next] <= new_cost: continue
            cost[next] = new_cost
            parents[next] = current
            if next not in open: open.append(next)
    var result: Array[Vector2] = []
    if not found: return result
    var current = end_cell
    result.append(end)
    while current != start_cell:
        current = parents[current]
        result.append(start if current == start_cell else Vector2(current)*step)
    result.reverse()
    return result

func _height(point: Vector2, cache: Dictionary) -> float:
    if not cache.has(point): cache[point] = _settlements.ground_height(point)
    return cache[point]

func _edge_safe(a: Vector2, b: Vector2, owner: Dictionary, heights: Dictionary) -> bool:
    var steps = maxi(1,ceili(a.distance_to(b)/4))
    var previous: float = _height(a,heights)
    var across = Vector2(-(b-a).y,(b-a).x).normalized()*3.2
    for i in range(steps+1):
        var p = a.lerp(b,float(i)/steps)
        for sample in [p,p+across,p-across]:
            if not _safe(sample,owner): return false
        var h: float = _height(p,heights)
        if absf(h-previous) > 1.2: return false
        previous = h
    return true

func _edge_safe_incremental(a: Vector2, b: Vector2, owner: Dictionary, heights: Dictionary, scheduler: GenerationScheduler) -> bool:
    var steps = maxi(1,ceili(a.distance_to(b)/4))
    var previous: float = _height(a,heights)
    var across = Vector2(-(b-a).y,(b-a).x).normalized()*3.2
    for i in range(steps+1):
        if not await scheduler.checkpoint(): return false
        var p = a.lerp(b,float(i)/steps)
        for sample in [p,p+across,p-across]:
            if not await scheduler.checkpoint(): return false
            if not _safe(sample,owner): return false
        var h: float = _height(p,heights)
        if absf(h-previous) > 1.2: return false
        previous = h
    return true

func _find_connection_incremental(start: Vector2, end: Vector2, owner: Dictionary, scheduler: GenerationScheduler) -> Array[Vector2]:
    var direct_heights: Dictionary = {}
    if await _edge_safe_incremental(start,end,owner,direct_heights, scheduler): return [start,end]
    var step: float = 16.0
    var start_cell = Vector2i(roundi(start.x/step),roundi(start.y/step))
    var end_cell = Vector2i(roundi(end.x/step),roundi(end.y/step))
    var area = Rect2(start,Vector2.ZERO).expand(end).grow(128)
    var open: Array[Vector2i] = [start_cell]
    var cost: Dictionary = {start_cell:0.0}
    var parents: Dictionary = {}
    var heights: Dictionary = {}
    var closed: Dictionary = {}
    var found = false
    for iteration in range(1600):
        if not await scheduler.checkpoint(): return []
        if open.is_empty(): break
        var best = 0
        var score: float = INF
        for i in range(open.size()):
            if not await scheduler.checkpoint(): return []
            var value: float = cost[open[i]]+Vector2(open[i]-end_cell).length()*step
            if value < score: best = i; score = value
        var current = open[best]
        open.remove_at(best)
        if current == end_cell: found = true; break
        closed[current] = true
        var a = start if current == start_cell else Vector2(current)*step
        var ah: float = _height(a,heights)
        for direction in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]:
            if not await scheduler.checkpoint(): return []
            var next: Vector2i = current+direction
            if closed.has(next): continue
            var b = end if next == end_cell else Vector2(next)*step
            if not area.has_point(b) or not _safe(b,owner): continue
            var bh: float = _height(b,heights)
            var length = a.distance_to(b)
            if absf(bh-ah) > length*.27 or not await _edge_safe_incremental(a,b,owner,heights, scheduler): continue
            var new_cost: float = cost[current]+length+absf(bh-ah)*4
            if cost.has(next) and cost[next] <= new_cost: continue
            cost[next] = new_cost
            parents[next] = current
            if next not in open: open.append(next)
    var result: Array[Vector2] = []
    if not found: return result
    var current = end_cell
    result.append(end)
    while current != start_cell:
        if not await scheduler.checkpoint(): return []
        current = parents[current]
        result.append(start if current == start_cell else Vector2(current)*step)
    result.reverse()
    return result

func _connect_incremental(result: Array[Dictionary], exits: Array[Vector2], owner: Dictionary, scheduler: GenerationScheduler):
    var candidates: Array[Dictionary] = []
    for exit in exits:
        if not await scheduler.checkpoint(): return
        for vertical in [true,false]:
            if not await scheduler.checkpoint(): return
            for along in [0.0,-96.0,96.0,-192.0,192.0]:
                if not await scheduler.checkpoint(): return
                var target = regional_point(exit+(Vector2(0,along) if vertical else Vector2(along,0)),vertical)
                if exit.distance_to(target) <= MAX_CONNECTION and _safe(target,owner):
                    candidates.append({"start":exit,"end":target,"distance":exit.distance_squared_to(target)})
    candidates.sort_custom(func(a,b): return a.distance < b.distance)
    # One usable connection is enough to attach this settlement to the regional network.
    for i in range(mini(6,candidates.size())):
        if not await scheduler.checkpoint(): return
        var path = await _find_connection_incremental(candidates[i].start,candidates[i].end,owner, scheduler)
        if path.size() > 1:
            result.append(route(path,2.2,3.2,"connection"))
            return

func town_routes_incremental(town: Dictionary, scheduler: GenerationScheduler) -> Array[Dictionary]:
    var key = "town:%s:%s"%[town.position,town.seed]
    if _plans.has(key): return _plans[key]
    var result: Array[Dictionary] = []
    for ends in [[Vector2(-76,0),Vector2(76,0)],[Vector2(0,-76),Vector2(0,76)]]:
        if not await scheduler.checkpoint(): return []
        var points: Array[Vector2] = []
        for p in ends: points.append(town.position+SettlementSampler.rotate(p,town.yaw))
        result.append(route(points,3.2,4.3,"street"))
    for house in town.houses:
        if not await scheduler.checkpoint(): return []
        var points: Array[Vector2] = [town.position+SettlementSampler.rotate(house.path_start,town.yaw),town.position+SettlementSampler.rotate(house.path_end,town.yaw)]
        result.append(route(points,.75,1.25,"door"))
    # A square is represented by adjacent lanes in the same road data.
    for offset in [-6.0,-2.0,2.0,6.0]:
        if not await scheduler.checkpoint(): return []
        var points: Array[Vector2] = [town.position+SettlementSampler.rotate(Vector2(-8,offset),town.yaw),town.position+SettlementSampler.rotate(Vector2(8,offset),town.yaw)]
        result.append(route(points,2.0,2.2,"square"))
    var exits: Array[Vector2] = []
    for p in [Vector2(-76,0),Vector2(76,0),Vector2(0,-76),Vector2(0,76)]: exits.append(town.position+SettlementSampler.rotate(p,town.yaw))
    await _connect_incremental(result,exits,town, scheduler)
    _remember(key,result)
    return result

func home_routes_incremental(home: Dictionary, scheduler: GenerationScheduler) -> Array[Dictionary]:
    var key = "home:%s:%s"%[home.position,home.seed]
    if _plans.has(key): return _plans[key]
    var p = home.recipe.resolve()
    var door = home.position+SettlementSampler.rotate(Vector2(0,-p.depth*.5-.8),home.yaw)
    var outside = home.position+SettlementSampler.rotate(Vector2(0,home.bounds.position.y-1.8),home.yaw)
    var result: Array[Dictionary] = []
    var entry: Array[Vector2] = [door,outside]
    result.append(route(entry,.75,1.25,"door"))
    var exits: Array[Vector2] = [outside]
    await _connect_incremental(result,exits,home, scheduler)
    _remember(key,result)
    return result

func routes_in_chunk_incremental(cell: Vector2i, scheduler: GenerationScheduler) -> Array[Dictionary]:
    if _chunks.has(cell): return _chunks[cell]
    var bounds = Rect2(Vector2(cell)*CHUNK_SIZE,Vector2.ONE*CHUNK_SIZE)
    var result: Array[Dictionary] = []
    # Regional roads and settlement lanes are rendered by the same chunk builder.
    for vertical in [true,false]:
        if not await scheduler.checkpoint(): return []
        var centre = bounds.get_center()
        var anchor = regional_point(centre,vertical)
        for offset in [-TerrainPathSampler.PATH_SPACING,0.0,TerrainPathSampler.PATH_SPACING]:
            if not await scheduler.checkpoint(): return []
            var road_centre = anchor+(Vector2(offset,0) if vertical else Vector2(0,offset))
            var points = regional_route(road_centre,vertical,CHUNK_SIZE+64)
            var road = route(points,TerrainPathSampler.PATH_CORE_RADIUS,TerrainPathSampler.PATH_EDGE_RADIUS,"regional")
            if road.bounds.grow(2).intersects(bounds): result.append(road)
    var area = bounds.grow(MAX_CONNECTION)
    for kind in ["town","home"]:
        if not await scheduler.checkpoint(): return []
        var size: float = SettlementSampler.TOWN_CELL_SIZE if kind == "town" else SettlementSampler.HOMESTEAD_CELL_SIZE
        var start = Vector2i(floori(area.position.x/size),floori(area.position.y/size))
        var end = Vector2i(floori(area.end.x/size),floori(area.end.y/size))
        for z in range(start.y,end.y+1):
            if not await scheduler.checkpoint(): return []
            for x in range(start.x,end.x+1):
                if not await scheduler.checkpoint(): return []
                var definition = await _settlements.sample_town_incremental(Vector2i(x,z),scheduler) if kind == "town" else await _settlements.sample_homestead_incremental(Vector2i(x,z),scheduler)
                if definition.is_empty(): continue
                var routes = await town_routes_incremental(definition, scheduler) if kind == "town" else await home_routes_incremental(definition, scheduler)
                for road in routes:
                    if not await scheduler.checkpoint(): return []
                    if road.bounds.grow(2).intersects(bounds): result.append(road)
    if _chunks.size() >= 128: _chunks.erase(_chunks.keys()[0])
    _chunks[cell] = result
    return result
