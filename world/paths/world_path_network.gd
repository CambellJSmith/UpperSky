extends RefCounted
class_name WorldPathNetwork
signal chunk_routes_ready(cell: Vector2i)

const CHUNK_SIZE := 256.0
const MAX_CONNECTION := 6144.0
const CORE_COLOUR := Color(.25,.20,.12)
const EDGE_COLOUR := Color(.34,.28,.17)
static var _networks: Dictionary = {}
var _terrain: InfiniteTerrain
var _settlements: SettlementSampler
var _chunks := {}
var _snapshot_chunks := {}
var _links := {}
var _roads := {}
var _pending := {}
var _plans := {}
var _bridges := {}
var routing_status := {}
var cancel_check: Callable
var _disk_cache: RoadPlanCache
var extra_routes := {}
var _extra_chunk_cache := {}
var _extra_group_count := -1

func invalidate_extra_routes() -> void:
    _extra_chunk_cache.clear()
    _extra_group_count = extra_routes.size()

static func for_terrain(terrain: InfiniteTerrain) -> WorldPathNetwork:
    var id := terrain.get_instance_id()
    if _networks.has(id):
        var existing = _networks[id].get_ref()
        if existing != null: return existing
    for key in _networks.keys():
        if _networks[key].get_ref() == null: _networks.erase(key)
    var network := WorldPathNetwork.new(terrain)
    _networks[id] = weakref(network)
    return network

func _init(terrain: InfiniteTerrain, shared: bool = true):
    _terrain = terrain
    _settlements = SettlementSampler.for_terrain(terrain) if shared else SettlementSampler.new(terrain)
    if shared and terrain.get_script() in [preload("res://world/terrain/infinite_terrain.gd"),preload("res://world/terrain/seamless_infinite_terrain.gd")]:
        _disk_cache = RoadPlanCache.new(terrain is SeamlessInfiniteTerrain)

func route(points: Array[Vector2], core: float, edge: float, kind: String) -> Dictionary:
    var bounds := Rect2(points[0],Vector2.ZERO)
    for p in points: bounds = bounds.expand(p)
    return {"points":points,"core":core,"edge":edge,"kind":kind,"bounds":bounds.grow(edge),"bridges":[]}

func exits(definition: Dictionary) -> Array[Vector2]:
    if definition.has("houses"):
        if CityGeometry.is_city(definition): return [definition.position+SettlementSampler.rotate(Vector2(0,94),definition.yaw)]
        var result: Array[Vector2] = []
        for p in [Vector2(-76,0),Vector2(0,-76),Vector2(76,0),Vector2(0,76)]: result.append(definition.position+SettlementSampler.rotate(p,definition.yaw))
        return result
    return [definition.position+SettlementSampler.rotate(Vector2(0,definition.bounds.position.y-3.5),definition.yaw)]

func local_routes(definition: Dictionary) -> Array[Dictionary]:
    var key := str(definition.position)
    if _plans.has(key): return _plans[key]
    var result: Array[Dictionary] = []
    if not definition.has("houses"):
        var p: Dictionary = definition.recipe.resolve()
        var door: Vector2 = definition.position+SettlementSampler.rotate(Vector2(0,-p.depth*.5-.8),definition.yaw)
        result.append(route([door,exits(definition)[0]],.75,1.25,"door"))
    elif CityGeometry.is_city(definition):
        result.append(route([definition.position+SettlementSampler.rotate(Vector2(0,62),definition.yaw),exits(definition)[0]],4.0,5.0,"city_gate"))
    else:
        for ends in [[Vector2(-76,0),Vector2(76,0)],[Vector2(0,-76),Vector2(0,76)]]:
            var points: Array[Vector2] = []
            for p in ends: points.append(definition.position+SettlementSampler.rotate(p,definition.yaw))
            result.append(route(points,3.2,4.3,"street"))
        for house in definition.houses:
            result.append(route([definition.position+SettlementSampler.rotate(house.path_start,definition.yaw),definition.position+SettlementSampler.rotate(house.path_end,definition.yaw)],.75,1.25,"door"))
        for offset in [-6.0,-2.0,2.0,6.0]:
            result.append(route([definition.position+SettlementSampler.rotate(Vector2(-8,offset),definition.yaw),definition.position+SettlementSampler.rotate(Vector2(8,offset),definition.yaw)],2.0,2.2,"square"))
    _remember(_plans,key,result,256)
    for road in result: _publish_available(road)
    return result

func _link(a: Dictionary, b: Dictionary) -> Dictionary:
    # Canonical ownership makes routes independent of streaming order.
    if str(a.position) > str(b.position):
        var swap := a
        a = b
        b = swap
    var pair: Array[Vector2] = []
    var distance := INF
    for start in exits(a):
        for end in exits(b):
            if start.distance_squared_to(end) < distance:
                distance = start.distance_squared_to(end)
                pair = [start,end]
    return {"key":"%s>%s"%[a.position,b.position],"a":a,"b":b,"start":pair[0],"end":pair[1],"bounds":Rect2(pair[0],Vector2.ZERO).expand(pair[1]).grow(TerrainRoadPlanner.DETOUR_MARGIN+6),"kind":"arterial" if a.has("houses") and b.has("houses") else "connection"}

func _district_links(cell: Vector2i, scheduler: GenerationScheduler = null) -> Array[Dictionary]:
    if _links.has(cell): return _links[cell]
    var towns: Array[Dictionary] = []
    for z in range(-2,3):
        for x in range(-2,3):
            if scheduler != null and not await scheduler.checkpoint(): return []
            var town := _settlements.sample_town(cell+Vector2i(x,z)) if scheduler == null else await _settlements.sample_town_incremental(cell+Vector2i(x,z),scheduler)
            if not town.is_empty(): towns.append(town)
    var owner := _settlements.sample_town(cell)
    var result: Array[Dictionary] = []
    var primary: Array[Dictionary] = []
    var alternatives: Array[Dictionary] = []
    if not owner.is_empty():
        # Relative-neighbourhood edges keep spanning links without an all-pairs
        # web. Only a closer town on both sides can remove a redundant edge.
        for other in towns:
            if other.position == owner.position: continue
            var distance: float = owner.position.distance_squared_to(other.position)
            if distance > MAX_CONNECTION*MAX_CONNECTION: continue
            var redundant := false
            for third in towns:
                if third.position == owner.position or third.position == other.position: continue
                if owner.position.distance_squared_to(third.position) < distance and other.position.distance_squared_to(third.position) < distance:
                    redundant = true
                    break
            var link := _link(owner,other)
            if not redundant:
                result.append(link)
                primary.append(link)
            else: alternatives.append(link)
        # Geometry can invalidate the shortest graph edge. Retain nearby bypass
        # candidates so an inaccessible neighbour does not strand a settlement.
        alternatives.sort_custom(func(a,b): return a.start.distance_squared_to(a.end) < b.start.distance_squared_to(b.end))
        for i in range(mini(2,alternatives.size())):
            alternatives[i]["requires_failed"] = primary.duplicate()
            result.append(alternatives[i])
    var ratio := roundi(SettlementSampler.TOWN_CELL_SIZE/SettlementSampler.HOMESTEAD_CELL_SIZE)
    for z in range(ratio):
        for x in range(ratio):
            if scheduler != null and not await scheduler.checkpoint(): return []
            var home_cell := cell*ratio+Vector2i(x,z)
            var home := _settlements.sample_homestead(home_cell) if scheduler == null else await _settlements.sample_homestead_incremental(home_cell,scheduler)
            if home.is_empty(): continue
            var destination := owner
            if destination.is_empty():
                var distance := MAX_CONNECTION*MAX_CONNECTION
                for town in towns:
                    var candidate: float = home.position.distance_squared_to(town.position)
                    if candidate < distance: destination = town; distance = candidate
            if not destination.is_empty():
                var link := _link(home,destination)
                result.append(link)
                var alternate: Dictionary = {}
                var distance := MAX_CONNECTION*MAX_CONNECTION
                for town in towns:
                    if town.position == destination.position: continue
                    var candidate: float = home.position.distance_squared_to(town.position)
                    if candidate < distance: alternate = town; distance = candidate
                if not alternate.is_empty():
                    var bypass := _link(home,alternate)
                    bypass["requires_failed"] = [link]
                    result.append(bypass)
    _remember(_links,cell,result,96)
    return result

func _road(link: Dictionary, scheduler: GenerationScheduler = null, use_worker: bool = true) -> Dictionary:
    if _roads.has(link.key): return _roads[link.key]
    if link.has("requires_failed"):
        var failed := false
        for primary in link.requires_failed:
            if (await _road(primary,scheduler,use_worker)).is_empty(): failed = true
        if not failed: return {}
    if _disk_cache != null:
        var cached = _disk_cache.read(link)
        if cached != null:
            _remember(_roads,link.key,cached,256)
            if not cached.is_empty():
                for bridge in cached.bridges: _index_bridge(bridge)
                _publish_available(cached)
            return cached
    if scheduler != null:
        while _pending.has(link.key):
            await scheduler.frame_started
            if scheduler._closing: return {}
            if _roads.has(link.key): return _roads[link.key]
        _pending[link.key] = true
    if use_worker and scheduler != null and _terrain.get_script() in [preload("res://world/terrain/infinite_terrain.gd"),preload("res://world/terrain/seamless_infinite_terrain.gd")]:
        var owner := scheduler.active_owner if is_instance_valid(scheduler.active_owner) else scheduler
        var job := TerrainRoadJob.new(link,_terrain is SeamlessInfiniteTerrain)
        scheduler.tree_exiting.connect(job.cancel,CONNECT_ONE_SHOT)
        if owner != scheduler: owner.tree_exiting.connect(job.cancel,CONNECT_ONE_SHOT)
        while not scheduler.has_worker_room(true):
            await scheduler.frame_started
            if scheduler._closing or not is_instance_valid(owner): _pending.erase(link.key); return {}
        routing_status[link.key] = {"worker":true}
        if scheduler.submit(owner,job.generate,job.accept,true):
            await job.completed
            var road: Dictionary = job.result
            if scheduler.tree_exiting.is_connected(job.cancel): scheduler.tree_exiting.disconnect(job.cancel)
            if is_instance_valid(owner) and owner != scheduler and owner.tree_exiting.is_connected(job.cancel): owner.tree_exiting.disconnect(job.cancel)
            _remember(_roads,link.key,road,256)
            if _disk_cache != null: _disk_cache.write(link,road)
            if not road.is_empty():
                for bridge in road.bridges: _index_bridge(bridge)
                _publish_available(road)
            routing_status.erase(link.key)
            _pending.erase(link.key)
            return road
    var planner := TerrainRoadPlanner.new(self)
    if scheduler == null and _terrain.get_script() in [preload("res://world/terrain/infinite_terrain.gd"),preload("res://world/terrain/seamless_infinite_terrain.gd")] and not planner.water_connected(link.start,link.end):
        _remember(_roads,link.key,{},256)
        return {}
    planner.maximum_expansions = mini(6000,maxi(1600,int(link.start.distance_to(link.end)*.75)))
    for spacing in [64.0,32.0]:
        for refinement in range(4):
            planner.edge_spacing = 16.0
            planner.begin(link.start,link.end,spacing)
            routing_status[link.key] = {"spacing":spacing,"expansions":0}
            while not planner.done:
                if cancel_check.is_valid() and cancel_check.call(): return {}
                if scheduler != null and not await scheduler.checkpoint():
                    _pending.erase(link.key)
                    return {}
                if scheduler == null: planner.advance()
                else: await planner.advance_incremental(scheduler)
                routing_status[link.key].expansions = planner.expansions
            if planner.result.size()<2: break
            var safe := true
            planner.edge_spacing = 8.0
            for i in range(planner.result.size()-1):
                var a := planner.result[i]
                var b := planner.result[i+1]
                var edge := planner.inspect_edge(a,b) if scheduler == null else await planner.inspect_edge_incremental(a,b,scheduler)
                if not edge.valid:
                    # Re-plan around failures found by the final fine check.
                    planner.edge_spacing = 16.0
                    planner.edges[planner.edge_key(a,b)] = edge
                    planner.edge_spacing = 8.0
                    safe = false
            if safe: break
            planner.result.clear()
        if planner.result.size() >= 2: break
    var road: Dictionary = {}
    if planner.result.size() >= 2:
        var points: Array[Vector2] = await _round_corners(planner,scheduler)
        road = route(points,2.2 if link.kind == "arterial" else 1.2,3.2 if link.kind == "arterial" else 2.0,link.kind)
        road["key"] = link.key
        road["from"] = link.a.position
        road["to"] = link.b.position
        for i in range(points.size()-1):
            var edge := planner.inspect_edge(points[i],points[i+1])
            if edge.bridge: road.bridges.append({"a":points[i],"b":points[i+1],"height":edge.height,"height_a":edge.height_a,"height_b":edge.height_b,"width":road.core*2,"key":"%s:%d"%[link.key,i]})
    # Remember impossible sea/cliff links too; never paint disconnected fragments.
    _remember(_roads,link.key,road,256)
    if _disk_cache != null: _disk_cache.write(link,road)
    if not road.is_empty():
        for bridge in road.bridges: _index_bridge(bridge)
        _publish_available(road)
    _pending.erase(link.key)
    routing_status.erase(link.key)
    return road

# With no scheduler, these shared implementations never suspend. Callable.call
# preserves a synchronous public API while async streamers use the same logic.
func town_routes(town: Dictionary) -> Array[Dictionary]: return _settlement_routes.call(town)
func home_routes(home: Dictionary) -> Array[Dictionary]: return _settlement_routes.call(home)
func town_routes_incremental(town: Dictionary, scheduler: GenerationScheduler) -> Array[Dictionary]: return await _settlement_routes(town,scheduler)
func home_routes_incremental(home: Dictionary, scheduler: GenerationScheduler) -> Array[Dictionary]: return await _settlement_routes(home,scheduler)

func _settlement_routes(definition: Dictionary, scheduler: GenerationScheduler = null) -> Array[Dictionary]:
    var result: Array[Dictionary] = local_routes(definition).duplicate()
    var cell := Vector2i((definition.position/SettlementSampler.TOWN_CELL_SIZE).floor())
    for link in await _district_links(cell,scheduler):
        if link.a.position != definition.position and link.b.position != definition.position: continue
        var road := await _road(link,scheduler)
        if not road.is_empty(): result.append(road)
    return result

func routes_in_chunk(cell: Vector2i) -> Array[Dictionary]: return _with_extra_routes(_chunk_routes.call(cell),cell)
func routes_in_chunk_incremental(cell: Vector2i, scheduler: GenerationScheduler) -> Array[Dictionary]: return _with_extra_routes(await _chunk_routes(cell,scheduler),cell)

func _publish_available(road: Dictionary) -> void:
    # Announce each completed road, not just the end of a regional search.
    var interested := _snapshot_chunks.keys()
    for cell in _chunks.keys():
        if cell not in interested: interested.append(cell)
    for cell in interested:
        var bounds := Rect2(Vector2(cell)*CHUNK_SIZE,Vector2.ONE*CHUNK_SIZE)
        if not road.bounds.intersects(bounds.grow(32)): continue
        for i in range(road.points.size()-1):
            if Rect2(road.points[i],Vector2.ZERO).expand(road.points[i+1]).grow(road.edge+32).intersects(bounds):
                _snapshot_chunks.erase(cell)
                chunk_routes_ready.emit(cell)
                break

func cached_routes_in_chunk(cell: Vector2i) -> Array[Dictionary]:
    # Snapshot only completed geometry. This never starts or awaits a search.
    if not _snapshot_chunks.has(cell):
        var bounds := Rect2(Vector2(cell)*CHUNK_SIZE,Vector2.ONE*CHUNK_SIZE)
        var sections: Array[Dictionary] = []
        sections.assign(_chunks.get(cell,[]))
        for road in _roads.values():
            if not road.is_empty(): _append_chunk(sections,road,bounds)
        for roads in _plans.values():
            for road in roads: _append_chunk(sections,road,bounds)
        var unique: Array[Dictionary] = []
        var seen := {}
        for section in sections:
            var key := "%s:%s:%s"%[section.kind,section.points[0],section.points[1]]
            if seen.has(key): continue
            seen[key] = true
            unique.append(section)
        _remember(_snapshot_chunks,cell,unique,512)
    return _with_extra_routes(_snapshot_chunks[cell],cell)

func _with_extra_routes(base: Array[Dictionary], cell: Vector2i) -> Array[Dictionary]:
    var result: Array[Dictionary] = base.duplicate()
    if _extra_group_count!=extra_routes.size(): invalidate_extra_routes()
    if _extra_chunk_cache.has(cell):
        result.append_array(_extra_chunk_cache[cell])
        return result
    var additions: Array[Dictionary] = []
    var bounds := Rect2(Vector2(cell)*CHUNK_SIZE,Vector2.ONE*CHUNK_SIZE)
    for routes in extra_routes.values():
        for road in routes: _append_chunk(additions,road,bounds)
    _remember(_extra_chunk_cache,cell,additions,512)
    result.append_array(additions)
    return result

func _chunk_routes(cell: Vector2i, scheduler: GenerationScheduler = null) -> Array[Dictionary]:
    if _chunks.has(cell): return _chunks[cell]
    var bounds := Rect2(Vector2(cell)*CHUNK_SIZE,Vector2.ONE*CHUNK_SIZE)
    var district := Vector2i((bounds.get_center()/SettlementSampler.TOWN_CELL_SIZE).floor())
    var result: Array[Dictionary] = []
    var seen := {}
    var sources: Array[Vector2i] = []
    for z in range(-3,4):
        for x in range(-3,4): sources.append(district+Vector2i(x,z))
    sources.sort_custom(func(a,b): return Vector2(a-district).length_squared()<Vector2(b-district).length_squared())
    for source in sources:
        if scheduler != null and not await scheduler.checkpoint(): return []
        var source_bounds := Rect2(Vector2(source)*SettlementSampler.TOWN_CELL_SIZE,Vector2.ONE*SettlementSampler.TOWN_CELL_SIZE)
        if not source_bounds.grow(MAX_CONNECTION+TerrainRoadPlanner.DETOUR_MARGIN).intersects(bounds): continue
        for link in await _district_links(source,scheduler):
            if seen.has(link.key) or not link.bounds.intersects(bounds): continue
            var road := await _road(link,scheduler)
            if not road.is_empty():
                seen[link.key] = true
                _append_chunk(result,road,bounds)
            elif _roads.has(link.key): seen[link.key] = true
    var local_area := bounds.grow(110)
    for kind in ["town","home"]:
        var size: float = SettlementSampler.TOWN_CELL_SIZE if kind == "town" else SettlementSampler.HOMESTEAD_CELL_SIZE
        var first := Vector2i((local_area.position/size).floor())
        var last := Vector2i((local_area.end/size).floor())
        for z in range(first.y,last.y+1):
            for x in range(first.x,last.x+1):
                if scheduler != null and not await scheduler.checkpoint(): return []
                var definition: Dictionary
                if scheduler == null: definition = _settlements.sample_town(Vector2i(x,z)) if kind == "town" else _settlements.sample_homestead(Vector2i(x,z))
                else: definition = await _settlements.sample_town_incremental(Vector2i(x,z),scheduler) if kind == "town" else await _settlements.sample_homestead_incremental(Vector2i(x,z),scheduler)
                if not definition.is_empty():
                    for road in local_routes(definition): _append_chunk(result,road,bounds)
    _remember(_chunks,cell,result,256)
    _snapshot_chunks.erase(cell)
    chunk_routes_ready.emit(cell)
    return result

func _append_chunk(result: Array[Dictionary], road: Dictionary, bounds: Rect2):
    if not road.bounds.intersects(bounds.grow(32)): return
    # Bucket segments, not entire kilometre-long roads, for grass and terrain.
    for i in range(road.points.size()-1):
        var a: Vector2 = road.points[i]
        var b: Vector2 = road.points[i+1]
        if not Rect2(a,Vector2.ZERO).expand(b).grow(road.edge+32).intersects(bounds): continue
        var section := route([a,b],road.core,road.edge,road.kind)
        section["key"] = road.get("key","")
        for bridge in road.bridges:
            if bridge.a == a and bridge.b == b:
                section.bridges.append(bridge)
                _index_bridge(bridge)
        result.append(section)

func get_local_mask(point: Vector2, grass: bool = false, padding: float = 0.0) -> float:
    var mask := 0.0
    var cell := Vector2i((point/CHUNK_SIZE).floor())
    var roads: Array = []
    # Available road snapshots include partial regional results and local streets.
    for z in range(-1,2):
        for x in range(-1,2): roads.append_array(cached_routes_in_chunk(cell+Vector2i(x,z)))
    for road in roads:
        if not road.bounds.grow((2 if grass else 0)+padding).has_point(point): continue
        var distance := SettlementSampler._segment_distance(point,road.points[0],road.points[1])
        mask = maxf(mask,1-smoothstep(road.core+(1 if grass else 0)+padding,road.edge+(2 if grass else 0)+padding,distance))
    return mask

func obstructed(point: Vector2) -> bool:
    if _settlements._ground.is_clearing(point): return true
    var home := _settlements.sample_homestead(Vector2i((point/SettlementSampler.HOMESTEAD_CELL_SIZE).floor()))
    if not home.is_empty() and home.bounds.grow(2.0).has_point(SettlementSampler.rotate(point-home.position,-home.yaw)): return true
    var town := _settlements.sample_town(Vector2i((point/SettlementSampler.TOWN_CELL_SIZE).floor()))
    if town.is_empty(): return false
    if CityGeometry.is_city(town):
        var local := SettlementSampler.rotate(point-town.position,-town.yaw)
        return absf(local.x) < 66 and absf(local.y) < 66
    if point.distance_to(town.position+SettlementSampler.rotate(Vector2(-5,5),town.yaw)) < 4: return true
    for house in town.houses:
        if house.bounds.grow(2.0).has_point(SettlementSampler.rotate(point-house.position,-house.yaw)): return true
    return false

func _safe(point: Vector2, _owner: Dictionary = {}) -> bool:
    return not _terrain.has_water_at(point) and not BiomeProfile.is_lava(point) and not obstructed(point)

func _edge_safe(a: Vector2, b: Vector2, _owner: Dictionary, _heights: Dictionary) -> bool:
    return TerrainRoadPlanner.new(self).inspect_edge(a,b).valid

func town_walk_route(town: Dictionary) -> Array[Vector2]:
    var lane := 1.8
    var local: Array[Vector2] = [Vector2(-58,-lane),Vector2(-29,-lane),Vector2(lane,-lane),Vector2(lane,-29),Vector2(lane,-58),Vector2(lane,-29),Vector2(lane,-lane),Vector2(29,-lane),Vector2(58,-lane),Vector2(29,-lane),Vector2(lane,-lane),Vector2(lane,29),Vector2(lane,58),Vector2(lane,29),Vector2(lane,-lane),Vector2(-29,-lane)]
    var result: Array[Vector2] = []
    for p in local: result.append(town.position+SettlementSampler.rotate(p,town.yaw))
    return result

func home_walk_route(home: Dictionary) -> Array[Vector2]:
    var road := local_routes(home)[0]
    var outside: Vector2 = road.points[1]
    return [outside,outside.move_toward(road.points[0],.7)]

func regional_route(centre: Vector2, _vertical: bool, length: float = 192.0) -> Array[Vector2]:
    var best: Dictionary = {}
    var distance := CHUNK_SIZE*1.25
    var cell := Vector2i((centre/CHUNK_SIZE).floor())
    var available := cached_routes_in_chunk(cell) if GenerationScheduler.instance!=null else routes_in_chunk(cell)
    for road in available:
        if road.kind not in ["arterial","connection"]: continue
        var candidate := SettlementSampler._segment_distance(centre,road.points[0],road.points[1])
        if candidate < distance: best = road; distance = candidate
    if best.is_empty(): return []
    var whole: Dictionary = _roads.get(best.key,best)
    var points: Array[Vector2] = whole.points
    var closest := 0.0
    var along := 0.0
    distance = INF
    for i in range(points.size()-1):
        var a := points[i]
        var b := points[i+1]
        var t := clampf((centre-a).dot(b-a)/maxf(a.distance_squared_to(b),.001),0,1)
        var d := centre.distance_to(a.lerp(b,t))
        if d < distance: closest = along+a.distance_to(b)*t; distance = d
        along += a.distance_to(b)
    var start := maxf(0,closest-length*.5)
    var end := minf(along,closest+length*.5)
    var result: Array[Vector2] = []
    along = 0
    for i in range(points.size()-1):
        var a := points[i]
        var b := points[i+1]
        var span := a.distance_to(b)
        if along+span >= start and along <= end:
            var first := clampf((start-along)/span,0,1)
            var last := clampf((end-along)/span,0,1)
            var steps := maxi(1,ceili(span*(last-first)/12))
            for j in range(steps+1):
                var p := a.lerp(b,lerpf(first,last,float(j)/steps))
                if result.is_empty() or result[-1].distance_to(p) > .01: result.append(p)
        along += span
    return result

func _remember(cache: Dictionary, key: Variant, value: Variant, limit: int):
    if cache.size() >= limit: cache.erase(cache.keys()[0])
    cache[key] = value

func _index_bridge(bridge: Dictionary):
    var bounds := Rect2(bridge.a,Vector2.ZERO).expand(bridge.b).grow(bridge.width*.5+1)
    var first := Vector2i((bounds.position/CHUNK_SIZE).floor())
    var last := Vector2i((bounds.end/CHUNK_SIZE).floor())
    for z in range(first.y,last.y+1):
        for x in range(first.x,last.x+1):
            var cell := Vector2i(x,z)
            if not _bridges.has(cell): _remember(_bridges,cell,{},512)
            _bridges[cell][bridge.key] = bridge

func bridge_height(point: Vector2):
    var cell := Vector2i((point/CHUNK_SIZE).floor())
    for bridge in _bridges.get(cell,{}).values():
        var a: Vector2 = bridge.a
        var b: Vector2 = bridge.b
        var span := a.distance_to(b)
        var along := (point-a).dot((b-a)/span)
        if along < 0 or along > span or SettlementSampler._segment_distance(point,a,b) > bridge.width*.5: continue
        var ramp := minf(10.0,span*.3)
        var deck_a: float = bridge.get("height_a",bridge.height)
        var deck_b: float = bridge.get("height_b",bridge.height)
        var top_a := lerpf(deck_a,deck_b,ramp/span)
        var top_b := lerpf(deck_a,deck_b,1-ramp/span)
        if along < ramp: return lerpf(_settlements.ground_height(a)+.06,top_a,along/ramp)
        if along > span-ramp: return lerpf(top_b,_settlements.ground_height(b)+.06,(along-(span-ramp))/ramp)
        return lerpf(deck_a,deck_b,along/span)
    return null

func walking_height(point: Vector2) -> float:
    var bridge = bridge_height(point)
    return float(bridge) if bridge != null else _settlements.ground_height(point)

func _round_corners(planner: TerrainRoadPlanner, scheduler: GenerationScheduler) -> Array[Vector2]:
    var points := planner.result
    var result: Array[Vector2] = [points[0]]
    for i in range(1,points.size()-1):
        if scheduler != null and not await scheduler.checkpoint(): return points
        var before := planner.inspect_edge(points[i-1],points[i])
        var after := planner.inspect_edge(points[i],points[i+1])
        var incoming := (points[i]-points[i-1]).normalized()
        var outgoing := (points[i+1]-points[i]).normalized()
        if before.bridge or after.bridge or incoming.dot(outgoing) > .98:
            result.append(points[i])
            continue
        var radius := minf(12,minf(points[i].distance_to(points[i-1]),points[i].distance_to(points[i+1]))*.25)
        var head := points[i].move_toward(points[i-1],radius)
        var tail := points[i].move_toward(points[i+1],radius)
        var curve: Array[Vector2] = [head]
        for j in range(1,4):
            var t := j/3.0
            curve.append(head.lerp(points[i],t).lerp(points[i].lerp(tail,t),t))
        var safe := true
        for j in range(curve.size()-1):
            var edge := planner.inspect_edge(curve[j],curve[j+1]) if scheduler == null else await planner.inspect_edge_incremental(curve[j],curve[j+1],scheduler)
            if not edge.valid or edge.bridge: safe = false; break
        if safe: result.append_array(curve)
        else: result.append(points[i])
    result.append(points[-1])
    return result
