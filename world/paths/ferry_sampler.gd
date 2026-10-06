extends RefCounted
class_name FerrySampler

const CELL_SIZE := 512.0
const MAX_CROSSING := 768.0
const MAX_SHORE_GRADE := .22
const CELL_CHANCE := 0.35
const MIN_DOCK_SPACING := 300.0
var terrain: InfiniteTerrain
var ground: CampSampler
var network: WorldPathNetwork
var cancelled: Callable

func _init(source: InfiniteTerrain):
    terrain = source
    ground = CampSampler.new(source)
    network = WorldPathNetwork.new(source,false)

func safe(point: Vector2) -> bool:
    var biome := BiomeProfile.region_at(point)
    if biome.kind==BiomeProfile.Kind.ICE_FLATS and BiomeProfile.weight(point,biome)>.75: return false
    return not BiomeProfile.is_lava(point) and not BiomeProfile.is_waterfall_gap(point)

func dock(shore: Vector2, outward: Vector2) -> Dictionary:
    var land := shore-outward*12
    if terrain.has_water_at(land) or not safe(land) or network.obstructed(land): return {}
    var across := Vector2(-outward.y,outward.x)
    # Check the approach, shoreline and submerged bank, across the entire pier.
    for side in [-3.0,0.0,3.0]:
        var previous := ground.ground_height(shore-outward*24+across*side)
        for step in range(-20,13,4):
            var p: Vector2 = shore+outward*step+across*side
            var h := ground.ground_height(p)
            if absf(h-previous)/4 > MAX_SHORE_GRADE or not safe(p): return {}
            previous = h
    var tip := shore+outward*12
    while tip.distance_to(shore) <= 40:
        if terrain.has_water_at(tip) and terrain.get_water_level_at(tip)-ground.ground_height(tip) >= 1.0: break
        tip += outward*4
    if tip.distance_to(shore)>40: return {}
    var berth := tip+outward*3
    var height := terrain.get_water_level_at(tip)+.65
    var land_height := ground.ground_height(land)+.06
    if absf(height-land_height)/land.distance_to(tip)>MAX_SHORE_GRADE: return {}
    for step in range(ceili(land.distance_to(tip)/4)+1):
        var t := minf(1.0,step*4.0/land.distance_to(tip))
        var p := land.lerp(tip,t)
        if not safe(p) or network.obstructed(p): return {}
        if ground.ground_height(p)>lerpf(land_height,height,t)-.03: return {}
    return {"shore":shore,"land":land,"tip":tip,"berth":berth,"height":height,"land_height":land_height}

func crossing(shore: Vector2, outward: Vector2) -> Dictionary:
    var a := dock(shore,outward)
    if a.is_empty(): return {}
    var last_wet: Vector2 = a.berth
    if not terrain.has_water_at(last_wet): return {}
    var far := last_wet
    for distance in range(8,int(MAX_CROSSING)+1,8):
        if cancelled.is_valid() and cancelled.call(): return {}
        far = a.berth+outward*distance
        if not safe(far): return {}
        if not terrain.has_water_at(far): break
        last_wet = far
    if terrain.has_water_at(far): return {}
    for iteration in range(6):
        var mid := last_wet.lerp(far,.5)
        if terrain.has_water_at(mid): last_wet = mid
        else: far = mid
    var b := dock(far,-outward)
    if b.is_empty() or a.berth.distance_to(b.berth)<24: return {}
    var across := Vector2(-outward.y,outward.x)*1.6
    var previous := terrain.get_water_level_at(a.berth)
    for step in range(ceili(a.berth.distance_to(b.berth)/4)+1):
        var p: Vector2 = a.berth.lerp(b.berth,minf(1,step*4.0/a.berth.distance_to(b.berth)))
        var water := terrain.get_water_level_at(p)
        if absf(water-previous)>.16: return {}
        previous = water
        for offset in [-across,Vector2.ZERO,across]:
            var test: Vector2 = p+offset
            if not safe(test) or not terrain.has_water_at(test) or terrain.get_water_level_at(test)-ground.ground_height(test)<.65: return {}
    if str(a.shore)>str(b.shore):
        var swap := a
        a = b
        b = swap
    var key := "%s>%s"%[a.shore.snapped(Vector2.ONE*16),b.shore.snapped(Vector2.ONE*16)]
    return {"key":key,"docks":[a,b],"seed":hash(key),"lane":[a.berth,b.berth]}

static func eligible_cell(cell: Vector2i) -> bool:
    var rng := RandomNumberGenerator.new()
    rng.seed = hash("ferry-density:%d:%d:%d" % [TerrainHeightSampler.WORLD_SEED, cell.x, cell.y])
    return rng.randf() < CELL_CHANCE

static func segment_distance(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
    if Geometry2D.segment_intersects_segment(a,b,c,d) != null: return 0.0
    return minf(minf(a.distance_to(Geometry2D.get_closest_point_to_segment(a,c,d)), b.distance_to(Geometry2D.get_closest_point_to_segment(b,c,d))), minf(c.distance_to(Geometry2D.get_closest_point_to_segment(c,a,b)), d.distance_to(Geometry2D.get_closest_point_to_segment(d,a,b))))

static func conflicts(a: Dictionary, b: Dictionary) -> bool:
    # Compare full pier footprints on either bank, independent of endpoint order.
    for first in a.docks:
        for second in b.docks:
            if segment_distance(first.land,first.tip,second.land,second.tip) < MIN_DOCK_SPACING:
                return true
    # Crossing boats must not share or intersect a sailing lane.
    return segment_distance(a.lane[0],a.lane[1],b.lane[0],b.lane[1]) < 8.0

func sample(cell: Vector2i) -> Array[Dictionary]:
    if not eligible_cell(cell): return []
    # Fixed probes make opposite-bank discovery and reloads reproducible.
    var origin := Vector2(cell)*CELL_SIZE
    for z in range(8):
        for x in range(8):
            if cancelled.is_valid() and cancelled.call(): return []
            var start := origin+Vector2(x+.5,z+.5)*64
            if terrain.has_water_at(start) or not safe(start): continue
            for direction in range(8):
                var outward := Vector2.from_angle(direction*TAU/8)
                var dry := start
                var wet := start
                for step in range(1,9):
                    wet = start+outward*step*8
                    if terrain.has_water_at(wet): break
                    dry = wet
                if not terrain.has_water_at(wet): continue
                for iteration in range(6):
                    var mid := dry.lerp(wet,.5)
                    if terrain.has_water_at(mid): wet = mid
                    else: dry = mid
                var pair := crossing(dry,outward)
                if not pair.is_empty(): return [pair]
    return []
