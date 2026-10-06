extends Node3D
class_name FerrySystem
const MAX_ACTIVE_CROSSINGS := 4

var terrain: InfiniteTerrain
var player: FirstPersonPlayer
var crossings := {}
var sampled := {}
var pending: Array[Vector2i] = []
var jobs := {}
var journey_job: FerryJourneyJob
var journey_pending: Array[FerryCrossing] = []
var centre := Vector2i(2147483647,2147483647)
var elapsed := 0.0
var cache_directory := "user://ferries/v5_%d/"%TerrainHeightSampler.WORLD_SEED

func initialize(source: InfiniteTerrain, character: FirstPersonPlayer):
    terrain = source
    player = character
    cache_directory = "user://ferries/v5_%d_%s/"%[TerrainHeightSampler.WORLD_SEED,"seamless" if source is SeamlessInfiniteTerrain else "tiered"]

func _process(delta: float):
    if terrain == null or player == null or terrain.get_loaded_chunk_count()==0 or not terrain.is_visible_in_tree(): return
    elapsed += delta
    if elapsed<.5: return
    elapsed = 0
    var world := terrain.local_to_world_position(player.global_position)
    var point := Vector2(world.x,world.z)
    var next := Vector2i((point/FerrySampler.CELL_SIZE).floor())
    if next!=centre:
        centre = next
        pending.clear()
        for z in range(-2,3):
            for x in range(-2,3):
                var cell := centre+Vector2i(x,z)
                if not sampled.has(cell) and not jobs.has(cell): pending.append(cell)
        pending.sort_custom(func(a,b): return Vector2(a-centre).length_squared()<Vector2(b-centre).length_squared())
    for key in crossings.keys():
        var ferry: FerryCrossing = crossings[key]
        var near := false
        for dock in ferry.definition.docks:
            if point.distance_to(dock.land)<1200: near = true
        for npc in ferry.passengers:
            if is_instance_valid(npc) and point.distance_to(Vector2(npc.world_position.x,npc.world_position.z))<700: near = true
        if not near and ferry.riders.is_empty():
            crossings.erase(key)
            ferry.queue_free()
            WorldPathNetwork.for_terrain(terrain).extra_routes.erase(key)
            WorldPathNetwork.for_terrain(terrain).extra_routes.erase(key+":deck")
            WorldPathNetwork.for_terrain(terrain).extra_routes.erase(key+":journey")
            WorldPathNetwork.for_terrain(terrain).invalidate_extra_routes()
    for cell in sampled:
        for definition in sampled[cell]:
            if crossings.size()>=MAX_ACTIVE_CROSSINGS: break
            if _near(definition,point,850): _spawn(definition)
    for ferry: FerryCrossing in crossings.values():
        for npc in ferry.passengers:
            if is_instance_valid(npc): npc.set_active(npc.ferry_riding!=null or point.distance_to(Vector2(npc.world_position.x,npc.world_position.z))<700)
        _connect_roads(ferry)
    var scheduler := GenerationScheduler.instance
    if scheduler!=null and not journey_pending.is_empty() and journey_job==null and scheduler.has_worker_room(true):
        _prepare_journey(journey_pending.pop_front(),scheduler)
    if pending.is_empty() or not jobs.is_empty() or scheduler==null or not scheduler.has_worker_room(true): return
    var cell: Vector2i = pending.pop_front()
    var path := cache_directory.path_join("%d_%d.ferry"%[cell.x,cell.y])
    if FileAccess.file_exists(path):
        var file := FileAccess.open(path,FileAccess.READ)
        var data = file.get_var(false) if file!=null else null
        if _valid_cache(data): sampled[cell] = data; return
    var job := FerryJob.new(cell,terrain is SeamlessInfiniteTerrain)
    jobs[cell] = job
    if not scheduler.submit(self,job.generate,func(data):
        jobs.erase(cell)
        sampled[cell] = data
        if sampled.size()>96: sampled.erase(sampled.keys()[0])
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_directory))
        var file := FileAccess.open(path,FileAccess.WRITE)
        if file!=null: file.store_var(data,false)
    ,true):
        jobs.erase(cell)
        pending.push_front(cell)

func _valid_cache(data) -> bool:
    if not data is Array or data.size()>1: return false
    for definition in data:
        if not definition is Dictionary or not definition.has_all(["key","seed","docks","lane"]): return false
        if not definition.docks is Array or definition.docks.size()!=2 or not definition.lane is Array or definition.lane.size()!=2: return false
        for dock in definition.docks:
            if not dock is Dictionary or not dock.has_all(["land","tip","shore","berth","height","land_height"]): return false
            for field in ["land","tip","shore","berth"]:
                if not dock[field] is Vector2 or not dock[field].is_finite(): return false
            if not is_finite(float(dock.height)) or not is_finite(float(dock.land_height)): return false
        for p in definition.lane:
            if not p is Vector2 or not p.is_finite(): return false
    return true

func _near(data: Dictionary, point: Vector2, distance: float) -> bool:
    for dock in data.docks:
        if dock.land.distance_to(point)<distance: return true
    return false

func _spawn(data: Dictionary):
    if crossings.has(data.key) or crossings.size()>=MAX_ACTIVE_CROSSINGS: return
    for ferry: FerryCrossing in crossings.values():
        if FerrySampler.conflicts(ferry.definition,data): return
    var ferry := FerryCrossing.new()
    ferry.name = "Ferry_%d"%data.seed
    ferry.configure(terrain,data)
    crossings[data.key] = ferry
    add_child(ferry)
    var network := WorldPathNetwork.for_terrain(terrain)
    var reservations: Array[Dictionary] = []
    for dock in data.docks: reservations.append(network.route([dock.land,dock.tip],1.8,2.5,"dock_deck"))
    network.extra_routes[data.key+":deck"] = reservations
    network.invalidate_extra_routes()
    journey_pending.append(ferry)

func _prepare_journey(ferry: FerryCrossing, scheduler: GenerationScheduler):
    if not is_instance_valid(ferry) or ferry.is_queued_for_deletion(): return
    var path := cache_directory.path_join("journey_"+String(ferry.definition.key).sha256_text()+".ferry")
    if FileAccess.file_exists(path):
        var file := FileAccess.open(path,FileAccess.READ)
        var data = file.get_var(false) if file != null else null
        if data is Dictionary:
            _install_journey(ferry,data)
            return
    journey_job = FerryJourneyJob.new(ferry.definition,terrain is SeamlessInfiniteTerrain)
    var job := journey_job
    ferry.tree_exiting.connect(job.cancel,CONNECT_ONE_SHOT)
    if not scheduler.submit(self,job.generate,func(data):
        journey_job = null
        if not is_instance_valid(ferry) or ferry.is_queued_for_deletion(): return
        if ferry.tree_exiting.is_connected(job.cancel): ferry.tree_exiting.disconnect(job.cancel)
        _install_journey(ferry,data)
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_directory))
        var file := FileAccess.open(path,FileAccess.WRITE)
        if file!=null: file.store_var(data,false)
    ,true):
        journey_job = null
        journey_pending.push_front(ferry)

func _install_journey(ferry: FerryCrossing, plan: Dictionary):
    # No safe onward land route means no artificial dock-loop passengers.
    if plan.is_empty() or not plan.has_all(["roads","settlements"]) or plan.roads.size()!=2 or plan.settlements.size()!=2: return
    if not ferry.passengers.is_empty(): return
    var network := WorldPathNetwork.for_terrain(terrain)
    network.extra_routes[ferry.definition.key+":journey"] = plan.roads
    network.invalidate_extra_routes()
    _refresh_paths(plan.roads)
    for road in plan.roads:
        for bridge in road.bridges: network._index_bridge(bridge)
    var points: Array[Vector2] = []
    points.assign(plan.roads[0].points)
    points.reverse()
    var land_a := points.size()-1
    points.append(ferry.definition.docks[0].tip)
    var tip_a := points.size()-1
    points.append(ferry.definition.docks[1].tip)
    var tip_b := points.size()-1
    var land_b := points.size()
    points.append_array(plan.roads[1].points)
    var itinerary := {"key":ferry.definition.key,"origin":plan.settlements[0].position,"destination":plan.settlements[1].position,"origin_kind":plan.settlements[0].kind,"destination_kind":plan.settlements[1].kind,"ferry_stops":{tip_a:0,tip_b:1},"land_indexes":[land_a,land_b]}
    for end in range(2):
        var npc := Villager.new()
        npc.ferry_route = ferry
        npc.configure(terrain,{"role":"traveller","model":end,"seed":absi(ferry.definition.seed)+end*173,"start":land_a if end==0 else land_b,"route":points,"journey":itinerary})
        if not npc._loot_record.has("journey"): npc._travel_direction = 1 if end==0 else -1
        ferry.add_child(npc)
        npc.global_position = terrain.world_to_local_position(npc.world_position)
        ferry.passengers.append(npc)

func _connect_roads(ferry: FerryCrossing):
    var network := WorldPathNetwork.for_terrain(terrain)
    if network.extra_routes.has(ferry.definition.key): return
    var routes: Array[Dictionary] = []
    for dock in ferry.definition.docks:
        var nearest: Vector2 = dock.land
        var distance := 160.0
        var dock_cell := Vector2i((dock.land/WorldPathNetwork.CHUNK_SIZE).floor())
        for z in range(-1,2):
            for x in range(-1,2):
                for road in network._chunks.get(dock_cell+Vector2i(x,z),[]):
                    if not road.bridges.is_empty(): continue
                    var p := Geometry2D.get_closest_point_to_segment(dock.land,road.points[0],road.points[1])
                    if p.distance_to(dock.land)<distance: nearest = p; distance = p.distance_to(dock.land)
        if distance>=160 or distance<2: continue
        var edge := TerrainRoadPlanner.new(network).inspect_edge(dock.land,nearest)
        if not edge.valid or edge.get("bridge",false): continue
        routes.append(network.route([dock.land,nearest],1.1,1.8,"dock_approach"))
    if routes.is_empty(): return
    network.extra_routes[ferry.definition.key] = routes
    network.invalidate_extra_routes()
    _refresh_paths(routes)

func _refresh_paths(routes: Array):
    var network := WorldPathNetwork.for_terrain(terrain)
    for cell in network._chunks.keys():
        var bounds := Rect2(Vector2(cell)*WorldPathNetwork.CHUNK_SIZE,Vector2.ONE*WorldPathNetwork.CHUNK_SIZE)
        for road in routes:
            if road.bounds.intersects(bounds):
                network.chunk_routes_ready.emit(cell)
                break
    var paths := get_parent().get_node_or_null("Paths")
    if paths!=null:
        for cell in paths._chunks.keys():
            var bounds := Rect2(Vector2(cell)*WorldPathNetwork.CHUNK_SIZE,Vector2.ONE*WorldPathNetwork.CHUNK_SIZE)
            for road in routes:
                if road.bounds.intersects(bounds):
                    paths._routes_ready(cell)
                    break

func _exit_tree():
    for job in jobs.values(): job.cancel()
    if journey_job!=null: journey_job.cancel()
