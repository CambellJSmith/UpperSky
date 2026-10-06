extends RefCounted
class_name TerrainRoadPlanner

# Search state advances one expansion at a time, allowing the same deterministic
# planner to run synchronously in tools or within the streaming frame budget.
const MAX_GRADE := .28
const MAX_BRIDGE := 192.0
const DETOUR_MARGIN := 2048.0
const DIRECTIONS := [Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0),Vector2i(0,-1),Vector2i(1,1),Vector2i(-1,1),Vector2i(-1,-1),Vector2i(1,-1),Vector2i(2,0),Vector2i(-2,0),Vector2i(0,2),Vector2i(0,-2),Vector2i(3,0),Vector2i(-3,0),Vector2i(0,3),Vector2i(0,-3),Vector2i(2,2),Vector2i(-2,2),Vector2i(-2,-2),Vector2i(2,-2)]
var network: WorldPathNetwork
var samples := {}
var edges := {}
var start: Vector2
var finish: Vector2
var step := 64.0
var area: Rect2
var first: Vector2i
var last: Vector2i
var heap: Array = []
var costs := {}
var parents := {}
var closed := {}
var done := false
var result: Array[Vector2] = []
var expansions := 0
var maximum_expansions := 6000
var water_samples := {}
var edge_spacing := 8.0

func _init(paths: WorldPathNetwork): network = paths

func begin(a: Vector2, b: Vector2, spacing: float = 64.0):
    start = a
    finish = b
    step = spacing
    first = Vector2i(roundi(a.x/step),roundi(a.y/step))
    last = Vector2i(roundi(b.x/step),roundi(b.y/step))
    area = Rect2(a,Vector2.ZERO).expand(b).grow(DETOUR_MARGIN)
    costs = {first:0.0}
    parents.clear()
    closed.clear()
    heap.clear()
    result.clear()
    done = false
    expansions = 0
    if first == last:
        if inspect_edge(a,b).valid: result = [a,b]
        done = true
        return
    _push(first,a.distance_to(b),0.0)

func point(cell: Vector2i) -> Vector2:
    if cell == first: return start
    if cell == last: return finish
    return Vector2(cell)*step

func advance(): _advance.call(null)

func advance_incremental(scheduler: GenerationScheduler): await _advance(scheduler)

func _advance(scheduler: GenerationScheduler):
    if done: return
    if heap.is_empty() or expansions >= maximum_expansions:
        done = true
        return
    var item: Array = _pop()
    var cell: Vector2i = item[0]
    if closed.has(cell) or item[2] != costs.get(cell,INF): return
    if cell == last:
        result.append(finish)
        while cell != first:
            cell = parents[cell]
            result.append(point(cell))
        result.reverse()
        done = true
        return
    closed[cell] = true
    expansions += 1
    var a := point(cell)
    for direction in DIRECTIONS:
        if scheduler != null and not await scheduler.checkpoint(): done = true; return
        var next: Vector2i = cell+direction
        if closed.has(next): continue
        var b := point(next)
        if not area.has_point(b): continue
        var jump: bool = direction.length_squared() > 2
        if jump:
            var midpoint := water_sample(a.lerp(b,.5))
            if not midpoint.wet and midpoint.height > (water_sample(a).height+water_sample(b).height)*.5-6: continue
        var edge := inspect_edge(a,b) if scheduler == null else await inspect_edge_incremental(a,b,scheduler)
        if not edge.valid or (jump and not edge.bridge): continue
        var cost: float = costs[cell]+edge.cost
        if cost >= costs.get(next,INF): continue
        costs[next] = cost
        parents[next] = cell
        _push(next,cost+b.distance_to(finish)*2.0,cost)

func sample(p: Vector2) -> Dictionary:
    if samples.has(p): return samples[p]
    var terrain := network._terrain
    var wet := terrain.has_water_at(p)
    var value := {"height":network._settlements.ground_height(p),"wet":wet,"water":terrain.get_water_level_at(p) if wet else -INF,"safe":not BiomeProfile.is_lava(p) and not BiomeProfile.is_waterfall_gap(p) and not network.obstructed(p)}
    samples[p] = value
    return value

func sample_incremental(p: Vector2, scheduler: GenerationScheduler) -> Dictionary:
    if samples.has(p): return samples[p]
    # Warm procedural footprints cooperatively before the pure sample accesses
    # them. A newly entered district must not synchronously plan an entire town.
    await network._settlements.sample_town_incremental(Vector2i((p/SettlementSampler.TOWN_CELL_SIZE).floor()),scheduler)
    await network._settlements.sample_homestead_incremental(Vector2i((p/SettlementSampler.HOMESTEAD_CELL_SIZE).floor()),scheduler)
    await network._settlements._ground.sample_cell_incremental(Vector2i((p/CampSampler.CELL_SIZE).floor()),scheduler)
    return sample(p)

func inspect_edge(a: Vector2, b: Vector2) -> Dictionary:
    var key := edge_key(a,b)
    if edges.has(key): return edges[key]
    var value: Dictionary = _inspect.call(a,b,null)
    edges[key] = value
    return value

func inspect_edge_incremental(a: Vector2, b: Vector2, scheduler: GenerationScheduler) -> Dictionary:
    var key := edge_key(a,b)
    if edges.has(key): return edges[key]
    var value := await _inspect(a,b,scheduler)
    edges[key] = value
    return value

func edge_key(a: Vector2, b: Vector2) -> Array:
    return [a,b,edge_spacing] if a.x < b.x or (a.x == b.x and a.y <= b.y) else [b,a,edge_spacing]

func water_sample(p: Vector2) -> Dictionary:
    if water_samples.has(p): return water_samples[p]
    var wet := network._terrain.has_water_at(p)
    var height := network._settlements.ground_height(p)
    var value := {"wet":wet,"height":height,"depth":network._terrain.get_water_level_at(p)-height if wet else 0.0}
    water_samples[p] = value
    return value

func water_edge(a: Vector2, b: Vector2) -> bool:
    if water_sample(a).wet or water_sample(b).wet: return false
    var length := a.distance_to(b)
    var count := maxi(1,ceili(length/16))
    var wet_count := 0
    for i in range(1,count):
        var value := water_sample(a.lerp(b,float(i)/count))
        if value.wet:
            wet_count += 1
            if value.depth > 90: return false
    return wet_count*length/count <= 160 and (wet_count == 0 or length <= MAX_BRIDGE)

func water_connected(a: Vector2, b: Vector2) -> bool:
    # A cheap shore-only preflight avoids detailed searches across broad oceans.
    # Retry a finer grid to retain narrow land corridors and river crossings.
    for spacing in [128.0,64.0]:
        begin(a,b,spacing)
        if first == last and water_edge(a,b): return true
        while not heap.is_empty() and expansions < 12000:
            if network.cancel_check.is_valid() and network.cancel_check.call(): return false
            var item := _pop()
            var cell: Vector2i = item[0]
            if closed.has(cell): continue
            if cell == last: return true
            closed[cell] = true
            expansions += 1
            var current := point(cell)
            for direction in DIRECTIONS.slice(0,8):
                var next: Vector2i = cell+direction
                if closed.has(next): continue
                var p := point(next)
                if not area.has_point(p) or not water_edge(current,p): continue
                var cost: float = costs[cell]+current.distance_to(p)
                if cost >= costs.get(next,INF): continue
                costs[next] = cost
                _push(next,cost+p.distance_to(finish)*2,cost)
    return false

func _inspect(a: Vector2, b: Vector2, scheduler: GenerationScheduler) -> Dictionary:
    var invalid := {"valid":false,"cost":INF,"bridge":false}
    var length := a.distance_to(b)
    if length < .01: return invalid
    var across := Vector2(-(b-a).y,(b-a).x).normalized()*3.2
    var sa := sample(a) if scheduler == null else await sample_incremental(a,scheduler)
    var sb := sample(b) if scheduler == null else await sample_incremental(b,scheduler)
    if not sa.safe or not sb.safe or sa.wet or sb.wet: return invalid
    var count := maxi(1,ceili(length/edge_spacing))
    var previous: float = sa.height
    var rise := 0.0
    var water := -INF
    var wet_count := 0
    var last_wet := false
    var runs := 0
    var steep := false
    var heights: Array[float] = []
    for i in range(count+1):
        if scheduler != null and not await scheduler.checkpoint(): return invalid
        var p := a.lerp(b,float(i)/count)
        var centre := sample(p) if scheduler == null else await sample_incremental(p,scheduler)
        heights.append(centre.height)
        var wet := false
        for q in [p,p+across,p-across]:
            if scheduler != null and not await scheduler.checkpoint(): return invalid
            var s := sample(q) if scheduler == null else await sample_incremental(q,scheduler)
            if not s.safe: return invalid
            wet = wet or s.wet
            if s.wet:
                water = maxf(water,s.water)
                # Do not bridge deep ocean channels or waterfall drops.
                if s.water-s.height > 90.0: return invalid
            elif absf(s.height-centre.height) > 2.0: steep = true
        if wet:
            wet_count += 1
            if not last_wet: runs += 1
        last_wet = wet
        if i > 0:
            rise += absf(centre.height-previous)
            if absf(centre.height-previous) > length/count*MAX_GRADE: steep = true
        previous = centre.height
    if wet_count > 0 or steep:
        if length > MAX_BRIDGE or wet_count*length/count > 160.0 or runs > 1: return invalid
        var deck_a: float = maxf(water+.85,sa.height+.6)
        var deck_b: float = maxf(water+.85,sb.height+.6)
        if absf(deck_b-deck_a)/length > MAX_GRADE or deck_a-sa.height > 2.4 or deck_b-sb.height > 2.4: return invalid
        var gap := false
        for i in range(heights.size()):
            var deck := lerpf(deck_a,deck_b,float(i)/count)
            if heights[i] > deck-.1: return invalid
            if deck-heights[i] > 6.0: gap = true
        if wet_count == 0 and not gap: return invalid
        return {"valid":true,"cost":length*2.5+40.0,"bridge":true,"height":maxf(deck_a,deck_b),"height_a":deck_a,"height_b":deck_b}
    # Penalize accumulated climbing, including rises hidden between endpoints.
    return {"valid":true,"cost":length+rise*8.0,"bridge":false}

func _push(cell: Vector2i, score: float, cost: float):
    heap.append([cell,score,cost])
    var i := heap.size()-1
    while i > 0:
        var parent := (i-1)/2
        if heap[parent][1] <= score: break
        heap[i] = heap[parent]
        i = parent
    heap[i] = [cell,score,cost]

func _pop() -> Array:
    var value: Array = heap[0]
    var tail: Array = heap.pop_back()
    if heap.is_empty(): return value
    var i := 0
    while i*2+1 < heap.size():
        var child := i*2+1
        if child+1 < heap.size() and heap[child+1][1] < heap[child][1]: child += 1
        if tail[1] <= heap[child][1]: break
        heap[i] = heap[child]
        i = child
    heap[i] = tail
    return value
