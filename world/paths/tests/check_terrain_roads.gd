extends SceneTree

class TestTerrain extends InfiniteTerrain:
    var river := false
    var ocean := false
    var mountain := false
    var ravine := false
    func _ready(): pass
    func get_height_at(p: Vector2) -> float:
        if ravine and absf(p.x-1024)<20: return -30.0
        if river and absf(p.x-1024)<36: return -4.0
        if ocean and p.x>900 and p.x<1200: return -30.0
        if mountain and Rect2(900,300,200,800).has_point(p): return 120.0
        return 0.0
    func has_water_at(p: Vector2) -> bool: return (river and absf(p.x-1024)<36) or (ocean and p.x>900 and p.x<1200)
    func get_water_level_at(_p: Vector2) -> float: return 0.0

class TestNetwork extends WorldPathNetwork:
    var wall := Rect2(900,300,200,800)
    var block := false
    func obstructed(p: Vector2) -> bool: return block and wall.has_point(p)

class TestSettlements extends SettlementSampler:
    var towns := {}
    var homes := {}
    func sample_town(cell: Vector2i) -> Dictionary: return towns.get(cell,{})
    func sample_homestead(cell: Vector2i) -> Dictionary: return homes.get(cell,{})
    func sample_town_incremental(cell: Vector2i, _scheduler: GenerationScheduler) -> Dictionary: return sample_town(cell)
    func sample_homestead_incremental(cell: Vector2i, _scheduler: GenerationScheduler) -> Dictionary: return sample_homestead(cell)

class FailedLinkNetwork extends TestNetwork:
    var forbidden_key := ""
    func _road(link: Dictionary, scheduler: GenerationScheduler = null, use_worker: bool = true) -> Dictionary:
        if link.key == forbidden_key: return {}
        return await super._road(link,scheduler,use_worker)

func _initialize(): run.call_deferred()
func solve(network: WorldPathNetwork, a: Vector2, b: Vector2) -> TerrainRoadPlanner:
    var planner := TerrainRoadPlanner.new(network)
    planner.begin(a,b)
    while not planner.done: planner.advance()
    assert(planner.result.size()>1,"No route through the test landscape")
    assert(planner.result[0] == a and planner.result[-1] == b)
    for i in range(planner.result.size()-1): assert(planner.inspect_edge(planner.result[i],planner.result[i+1]).valid)
    return planner

func town(p: Vector2, seed_value: int) -> Dictionary:
    return {"position":p,"yaw":0.0,"seed":seed_value,"houses":[],"radius":86.0}

func run():
    var terrain := TestTerrain.new()
    root.add_child(terrain)
    terrain.set_process(false)
    var network := TestNetwork.new(terrain)
    var settlements := TestSettlements.new(terrain)
    network._settlements = settlements
    var a := Vector2(700,700)
    var b := Vector2(1400,700)
    network.block = true
    var around := solve(network,a,b)
    assert(around.result.size()>4,"Road cut through an impassable footprint")
    network.block = false
    terrain.mountain = true
    var mountain := solve(network,a,b)
    for p in mountain.result: assert(terrain.get_height_at(p) == 0,"Road climbed a cliff")
    terrain.mountain = false
    terrain.ravine = true
    var ravine := solve(network,a,b)
    var viaduct := false
    for i in range(ravine.result.size()-1):
        if ravine.inspect_edge(ravine.result[i],ravine.result[i+1]).bridge: viaduct = true
    assert(viaduct,"Road did not span a narrow dry ravine")
    terrain.ravine = false
    terrain.river = true
    var river := solve(network,a,b)
    var crossings := 0
    for i in range(river.result.size()-1):
        var edge := river.inspect_edge(river.result[i],river.result[i+1])
        if edge.bridge:
            crossings += 1
            var definition := {"a":river.result[i],"b":river.result[i+1],"height":edge.height,"width":4.4,"key":"test"}
            network._index_bridge(definition)
            var middle: Vector2 = (definition.a+definition.b)*.5
            assert(network.bridge_height(middle) != null)
            var body := RoadBridge.build(definition,terrain,Vector2i.ZERO)
            root.add_child(body)
            await physics_frame
            var query := PhysicsRayQueryParameters3D.create(Vector3(middle.x,10,middle.y),Vector3(middle.x,-10,middle.y),1)
            var hit := terrain.get_world_3d().direct_space_state.intersect_ray(query)
            assert(not hit.is_empty() and hit.collider == body,"Bridge has no walking collision")
            body.free()
    assert(crossings==1,"River road failed to use one bridge")
    terrain.river = false
    terrain.ocean = true
    var sea := TerrainRoadPlanner.new(network)
    assert(not sea.inspect_edge(Vector2(880,700),Vector2(1210,700)).valid,"Road bridged an ocean")
    terrain.ocean = false
    # Every district centre and isolated home must attach to the same graph.
    var first := town(Vector2(700,700),1)
    var second := town(Vector2(SettlementSampler.TOWN_CELL_SIZE+700,700),4)
    var third := town(Vector2(SettlementSampler.TOWN_CELL_SIZE*2+700,700),7)
    settlements.towns = {Vector2i(0,0):first,Vector2i(1,0):second,Vector2i(2,0):third}
    var recipe := HouseRecipe.new()
    recipe.seed_value = 314
    var home := {"position":Vector2(1000,1000),"yaw":0.0,"seed":314,"recipe":recipe,"bounds":SettlementSampler.house_bounds(recipe)}
    settlements.homes[Vector2i((home.position/SettlementSampler.HOMESTEAD_CELL_SIZE).floor())] = home
    var links = network._district_links.call(Vector2i.ZERO)
    var primary_count := 0
    for link in links:
        if not link.has("requires_failed"): primary_count += 1
    assert(primary_count==2,"Centre/home graph did not choose the spanning links")
    var roads := network.town_routes(first)
    assert(roads.size()>network.local_routes(first).size())
    var cache := RoadPlanCache.new(false)
    cache.directory = "/tmp/upper-sky-road-cache-test/"
    var link: Dictionary = links[0]
    var cached_road: Dictionary = network._road.call(link)
    cache.write(link,cached_road)
    assert(cache.read(link) == cached_road,"Road cache did not preserve geometry")
    var changed := link.duplicate()
    changed.end += Vector2.ONE
    assert(cache.read(changed) == null,"Cache accepted changed settlement endpoints")
    var cancelled_job := TerrainRoadJob.new(link,true)
    cancelled_job.cancel()
    assert(cancelled_job.generate().is_empty(),"Cancelled road worker kept searching")
    var found_home := false
    for road in network.home_routes(home):
        if road.kind == "connection": found_home = true; assert(road.to == first.position or road.from == first.position)
    assert(found_home)
    var bypass_network := FailedLinkNetwork.new(terrain)
    bypass_network._settlements = settlements
    bypass_network.forbidden_key = network._link(first,second).key
    var bypass_found := false
    for road in bypass_network.town_routes(first):
        if road.kind == "arterial" and (road.from == third.position or road.to == third.position): bypass_found = true
    assert(bypass_found,"An inaccessible neighbour prevented a usable bypass")
    # Geometry generation order and asynchronous generation produce identical roads.
    var fresh := TestNetwork.new(terrain)
    fresh._settlements = settlements
    var scheduler := GenerationScheduler.new()
    root.add_child(scheduler)
    assert(await fresh.town_routes_incremental(first,scheduler) == roads)
    var cell := Vector2i(5,2)
    var chunk := network.routes_in_chunk(cell)
    assert(chunk == await fresh.routes_in_chunk_incremental(cell,scheduler))
    assert(not chunk.is_empty())
    var prepared_count := network._chunks.size()
    assert(network.cached_routes_in_chunk(Vector2i(3500,3500)).is_empty())
    assert(network.regional_route(Vector2(900000,900000),false).is_empty())
    assert(network.get_local_mask(Vector2(900000,900000)) == 0.0)
    assert(network._chunks.size() == prepared_count,"Runtime mask lookup started synchronous road generation")
    assert(network.get_local_mask(Vector2(1536,704))>.99,"Cached neighbour road lost its mask at a chunk boundary")
    for section in chunk:
        var midpoint: Vector2 = (section.points[0]+section.points[1])*.5
        if Vector2i((midpoint/256).floor()) == cell:
            assert(network.get_local_mask(midpoint)>.99)
            assert(network.get_local_mask(midpoint,true)>.99)
    var arc := network.regional_route(Vector2(1400,700),true,160)
    assert(arc.size()>2)
    for p in arc: assert(network.get_local_mask(p)>.99,"Traveller left the actual road")
    scheduler.queue_free()
    await process_frame
    terrain.free()
    print("PASS terrain/cliff/footprint detours, river bridge collision, ocean rejection, connected centre/home graph, deterministic sync/async routes, chunk masks and road travellers")
    quit()
