extends Node3D
class_name SettlementStreamer

const LOAD_DISTANCE: float = 2400.0
const UNLOAD_DISTANCE: float = 2800.0
const COLLISION_DISTANCE: float = TerrainConfiguration.CHUNK_SIZE*(TerrainConfiguration.COLLISION_RADIUS+1)+100.0
@onready var _terrain: InfiniteTerrain = $"../Terrain"
@onready var _player: FirstPersonPlayer = $"../../DynamicEntities/Player"
var _sampler: SettlementSampler
var _homes: Dictionary = {}
var _towns: Dictionary = {}
var _pending: Array[Dictionary] = []
var _refreshing = false
var _building = false
var _elapsed: float = .5

func _ready():
    _sampler = SettlementSampler.for_terrain(_terrain)

func _process(delta: float):
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__process(delta)
        return
    var _profile_token = RuntimeProfiler.begin("settlements.stream")
    _profile__process(delta)
    RuntimeProfiler.end(_profile_token)

func _profile__process(delta: float):
    if _terrain.get_loaded_chunk_count() == 0 or not _player.is_physics_processing():
        return
    var player_world: Vector3 = _terrain.local_to_world_position(_player.global_position)
    var point = Vector2(player_world.x,player_world.z)
    for collection in [_homes,_towns]:
        for root: Node3D in collection.values():
            root.position = _terrain.world_to_local_position(root.get_meta("world_position"))
    _elapsed += delta
    if _elapsed >= .5:
        _elapsed = 0.0
        if GenerationScheduler.instance == null: _refresh(point)
        elif not _refreshing:
            _refreshing = true
            _run_refresh(point,GenerationScheduler.instance)
    if _building: return
    # A town builds at most one house per frame, rather than a sixteen-house spike.
    for town: Node3D in _towns.values():
        var definition: Dictionary = town.get_meta("definition")
        var next: int = town.get_meta("next_house")
        if next < definition["houses"].size():
            if GenerationScheduler.instance == null: _append_house(town,definition,next)
            else:
                _building = true
                _run_house(town,definition,next,GenerationScheduler.instance)
            return
    if not _pending.is_empty():
        var job = _pending.pop_front()
        if GenerationScheduler.instance == null: _build(job)
        else:
            _building = true
            _run_build(job,GenerationScheduler.instance)
        return

func _nearby_cells(point: Vector2, centre: Vector2i, size: float) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    var radius := ceili(LOAD_DISTANCE/size)
    for z in range(-radius,radius+1):
        for x in range(-radius,radius+1):
            var cell := centre+Vector2i(x,z)
            var bounds := Rect2(Vector2(cell)*size,Vector2.ONE*size)
            if point.distance_to(point.clamp(bounds.position,bounds.end)) <= LOAD_DISTANCE:
                result.append(cell)
    result.sort_custom(func(a: Vector2i,b: Vector2i):
        return point.distance_squared_to((Vector2(a)+Vector2.ONE*.5)*size) < point.distance_squared_to((Vector2(b)+Vector2.ONE*.5)*size))
    return result

func _nearby_sites(point: Vector2) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for kind in ["home","town"]:
        var size: float = SettlementSampler.HOMESTEAD_CELL_SIZE if kind=="home" else SettlementSampler.TOWN_CELL_SIZE
        var centre := Vector2i((point/size).floor())
        for cell in _nearby_cells(point,centre,size):
            result.append({"kind":kind,"cell":cell,"distance":point.distance_squared_to((Vector2(cell)+Vector2.ONE*.5)*size)})
    result.sort_custom(func(a: Dictionary,b: Dictionary): return a.distance < b.distance)
    return result

func _refresh(point: Vector2):
    _pending.clear()
    for collection in [_homes,_towns]:
        for cell in collection.keys():
            var root: Node3D = collection[cell]
            var world: Vector3 = root.get_meta("world_position")
            var distance: float = point.distance_to(Vector2(world.x,world.z))
            if distance > UNLOAD_DISTANCE:
                remove_child(root)
                root.queue_free()
                collection.erase(cell)
            else:
                _collision_state(root,distance < COLLISION_DISTANCE)
    for site in _nearby_sites(point):
        var kind: String = site.kind
        var cell: Vector2i = site.cell
        var collection: Dictionary = _homes if kind=="home" else _towns
        if collection.has(cell): continue
        var definition: Dictionary = _sampler.sample_homestead(cell) if kind=="home" else _sampler.sample_town(cell)
        if definition.is_empty() or point.distance_to(definition["position"]) > LOAD_DISTANCE:
            continue
        _pending.append({"kind":kind,"cell":cell,"definition":definition,"distance":point.distance_squared_to(definition["position"])})
    _pending.sort_custom(func(a: Dictionary,b: Dictionary): return a["distance"] < b["distance"])

func _build(job: Dictionary):
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__build(job)
        return
    var _profile_token = RuntimeProfiler.begin("settlements.build")
    _profile__build(job)
    RuntimeProfiler.end(_profile_token)

func _profile__build(job: Dictionary):
    var definition: Dictionary = job["definition"]
    var point: Vector2 = definition["position"]
    var root: Node3D
    if job["kind"] == "home":
        root = HouseGeometry.new().build(definition["recipe"])
        root.rotation.y = definition["yaw"]
        root.name = "Homestead_%d_%d"%[job["cell"].x,job["cell"].y]
        _homes[job["cell"]] = root
    else:
        root = Node3D.new()
        root.name = "Town_%d_%d"%[job["cell"].x,job["cell"].y]
        root.rotation.y = definition["yaw"]
        root.set_meta("definition",definition)
        root.set_meta("next_house",0)
        if CityGeometry.is_city(definition):
            root.add_child(CityGeometry.exterior(definition))
            CityStaticBatch.build_sync(root)
            root.set_meta("next_house",definition.houses.size())
        else:
            root.add_child(SettlementGeometry.new().build_furniture(_sampler,definition))
        _towns[job["cell"]] = root
    var world = Vector3(point.x,definition["height"],point.y)
    root.set_meta("world_position",world)
    root.position = _terrain.world_to_local_position(world)
    add_child(root)
    WorldPathNetwork.for_terrain(_terrain).local_routes(definition)
    var chest = LootChest.new()
    chest.loot_key = "settlement:%s:%s"%[job.kind,job.cell]
    chest.seed_value = definition.seed
    var local = Vector2(5,5) if job.kind == "town" else Vector2(definition.bounds.end.x+1.7,definition.bounds.position.y-1.5)
    var ground = point+SettlementSampler.rotate(local,definition.yaw)
    if _sampler._safe_ground(ground):
        chest.position = Vector3(local.x,_sampler.ground_height(ground)-definition.height+.04,local.y)
        root.add_child(chest)
    else: chest.free()
    var player_world = _terrain.local_to_world_position(_player.global_position)
    _collision_state(root,Vector2(player_world.x,player_world.z).distance_to(point)<COLLISION_DISTANCE)

func _append_house(town: Node3D, definition: Dictionary, index: int):
    var item: Dictionary = definition["houses"][index]
    var house = HouseGeometry.new().build(item["recipe"])
    house.name = "House%02d"%index
    var offset: Vector2 = SettlementSampler.rotate(item["position"]-definition["position"],-definition["yaw"])
    house.position = Vector3(offset.x,item["height"]-definition["height"],offset.y)
    house.rotation.y = item["yaw"]-definition["yaw"]
    town.add_child(house)
    _set_collision_recursive(house,town.get_meta("collision_active",true))
    town.set_meta("next_house",index+1)

func _collision_state(root: Node3D, enabled: bool):
    if root.has_meta("collision_active") and root.get_meta("collision_active") == enabled:
        return
    root.set_meta("collision_active",enabled)
    _set_collision_recursive(root,enabled)

func _set_collision_recursive(node: Node, enabled: bool):
    if node is StaticBody3D:
        node.collision_layer = 1 if enabled else 0
        node.collision_mask = 1 if enabled else 0
    for child in node.get_children():
        _set_collision_recursive(child,enabled)

func _refresh_incremental(point: Vector2, scheduler: GenerationScheduler):
    _pending.clear()
    for collection in [_homes,_towns]:
        if not await scheduler.checkpoint(): return
        for cell in collection.keys():
            if not await scheduler.checkpoint(): return
            var root: Node3D = collection[cell]
            var world: Vector3 = root.get_meta("world_position")
            var distance: float = point.distance_to(Vector2(world.x,world.z))
            if distance > UNLOAD_DISTANCE:
                remove_child(root)
                root.queue_free()
                collection.erase(cell)
            else:
                _collision_state(root,distance < COLLISION_DISTANCE)
    for site in _nearby_sites(point):
        if not await scheduler.checkpoint(): return
        var kind: String = site.kind
        var cell: Vector2i = site.cell
        var collection: Dictionary = _homes if kind=="home" else _towns
        if collection.has(cell): continue
        var definition: Dictionary = await _sampler.sample_homestead_incremental(cell,scheduler) if kind=="home" else await _sampler.sample_town_incremental(cell,scheduler)
        if definition.is_empty() or point.distance_to(definition["position"]) > LOAD_DISTANCE:
            continue
        _pending.append({"kind":kind,"cell":cell,"definition":definition,"distance":point.distance_squared_to(definition["position"])})
    _pending.sort_custom(func(a: Dictionary,b: Dictionary): return a["distance"] < b["distance"])

func _run_refresh(point: Vector2, scheduler: GenerationScheduler):
    scheduler.active_owner = self
    scheduler.active_priority = 2
    await _refresh_incremental(point,scheduler)
    _refreshing = false

func _build_incremental(job: Dictionary, scheduler: GenerationScheduler):
    var definition: Dictionary = job["definition"]
    var point: Vector2 = definition["position"]
    var root: Node3D
    if job["kind"] == "home":
        root = await HouseGeometry.new().build_incremental(definition["recipe"],true,scheduler)
        if root == null: return
        root.rotation.y = definition["yaw"]
        root.name = "Homestead_%d_%d"%[job["cell"].x,job["cell"].y]
        _homes[job["cell"]] = root
    else:
        root = Node3D.new()
        root.name = "Town_%d_%d"%[job["cell"].x,job["cell"].y]
        root.rotation.y = definition["yaw"]
        root.set_meta("definition",definition)
        root.set_meta("next_house",0)
        if CityGeometry.is_city(definition):
            root.add_child(CityGeometry.exterior(definition))
            if not await CityStaticBatch.build(root,get_tree(),scheduler,self):
                root.free()
                return
            root.set_meta("next_house",definition.houses.size())
        else:
            root.add_child(SettlementGeometry.new().build_furniture(_sampler,definition))
        _towns[job["cell"]] = root
    var world = Vector3(point.x,definition["height"],point.y)
    root.set_meta("world_position",world)
    root.position = _terrain.world_to_local_position(world)
    add_child(root)
    WorldPathNetwork.for_terrain(_terrain).local_routes(definition)
    var chest = LootChest.new()
    chest.loot_key = "settlement:%s:%s"%[job.kind,job.cell]
    chest.seed_value = definition.seed
    var local = Vector2(5,5) if job.kind == "town" else Vector2(definition.bounds.end.x+1.7,definition.bounds.position.y-1.5)
    var ground = point+SettlementSampler.rotate(local,definition.yaw)
    if _sampler._safe_ground(ground):
        chest.position = Vector3(local.x,_sampler.ground_height(ground)-definition.height+.04,local.y)
        root.add_child(chest)
    else: chest.free()
    var player_world = _terrain.local_to_world_position(_player.global_position)
    _collision_state(root,Vector2(player_world.x,player_world.z).distance_to(point)<COLLISION_DISTANCE)

func _append_house_incremental(town: Node3D, definition: Dictionary, index: int, scheduler: GenerationScheduler):
    var item: Dictionary = definition["houses"][index]
    var house = await HouseGeometry.new().build_incremental(item["recipe"],true,scheduler)
    if house == null: return
    if not is_instance_valid(town) or not town.is_inside_tree():
        house.free()
        return
    house.name = "House%02d"%index
    var offset: Vector2 = SettlementSampler.rotate(item["position"]-definition["position"],-definition["yaw"])
    house.position = Vector3(offset.x,item["height"]-definition["height"],offset.y)
    house.rotation.y = item["yaw"]-definition["yaw"]
    town.add_child(house)
    _set_collision_recursive(house,town.get_meta("collision_active",true))
    town.set_meta("next_house",index+1)

func _run_build(job: Dictionary, scheduler: GenerationScheduler):
    var collection = _homes if job.kind == "home" else _towns
    if collection.has(job.cell):
        _building = false
        return
    scheduler.active_owner = self
    scheduler.active_priority = 2
    await _build_incremental(job,scheduler)
    _building = false

func _run_house(town: Node3D, definition: Dictionary, index: int, scheduler: GenerationScheduler):
    scheduler.active_owner = self
    scheduler.active_priority = 2
    await _append_house_incremental(town,definition,index,scheduler)
    _building = false
