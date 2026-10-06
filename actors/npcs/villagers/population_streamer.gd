extends Node3D
class_name VillagerPopulationStreamer

const LOAD_DISTANCE: float = 420.0
const UNLOAD_DISTANCE: float = 600.0
const MAX_NPCS: int = 24
@onready var _terrain: InfiniteTerrain = $"../Terrain"
@onready var _player: FirstPersonPlayer = $"../../DynamicEntities/Player"
@onready var _settlements: SettlementStreamer = $"../Settlements"
var _sampler: VillagerPopulationSampler
var _groups: Dictionary = {}
var _refreshing = false
var _elapsed: float = 1.0

func _ready(): _sampler = VillagerPopulationSampler.new(_terrain)
func _process(delta: float):
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__process(delta)
        return
    var _profile_token = RuntimeProfiler.begin("npcs.population_stream")
    _profile__process(delta)
    RuntimeProfiler.end(_profile_token)

func _profile__process(delta: float):
    if _terrain.get_loaded_chunk_count() == 0 or not _player.is_physics_processing(): return
    var position_world = _terrain.local_to_world_position(_player.global_position)
    var point = Vector2(position_world.x,position_world.z)
    for group in _groups.values():
        for npc: Villager in group:
            npc.position = _terrain.world_to_local_position(npc.world_position)
            npc.set_active(point.distance_to(Vector2(npc.world_position.x,npc.world_position.z)) < LOAD_DISTANCE)
    _elapsed += delta
    if _elapsed > 1.0:
        _elapsed = 0
        if GenerationScheduler.instance == null: _refresh(point)
        elif not _refreshing:
            _refreshing = true
            _run_refresh(point,GenerationScheduler.instance)

func _refresh(point: Vector2):
    for key in _groups.keys():
        var group: Array = _groups[key]
        if group.is_empty(): _groups.erase(key); continue
        var nearby = false
        for npc in group:
            if point.distance_to(Vector2(npc.world_position.x,npc.world_position.z)) < UNLOAD_DISTANCE: nearby = true
        if not nearby:
            for npc in group: remove_child(npc); npc.queue_free()
            _groups.erase(key)
    for cell in _settlements._towns:
        var definition: Dictionary = _settlements._towns[cell].get_meta("definition")
        if point.distance_to(definition.position) < LOAD_DISTANCE:
            _spawn("town:%s"%cell,_sampler.town(definition),point)
    for cell in _settlements._homes:
        var definition = _sampler._settlements.sample_homestead(cell)
        if point.distance_to(definition.position) < LOAD_DISTANCE:
            _spawn("home:%s"%cell,_sampler.home(definition),point)
    var centre = Vector2i(floori(point.x/VillagerPopulationSampler.TRAVEL_CELL),floori(point.y/VillagerPopulationSampler.TRAVEL_CELL))
    for z in range(-1,2):
        for x in range(-1,2):
            var cell = centre+Vector2i(x,z)
            var definitions = _sampler.travellers(cell)
            if not definitions.is_empty(): _spawn("trail:%s"%cell,definitions,point)

func _spawn(key: String, definitions: Array[Dictionary], point: Vector2):
    if _groups.has(key) or definitions.is_empty(): return
    var group: Array[Villager] = []
    for definition in definitions:
        if get_child_count() >= MAX_NPCS: break
        var start: Vector2 = definition.route[definition.start%definition.route.size()]
        if point.distance_to(start) > LOAD_DISTANCE: continue
        var npc = Villager.new()
        npc.name = ["Pilgrim","Weaver","Orc"][definition.model]+"_%d"%definition.seed
        npc.configure(_terrain,definition)
        add_child(npc)
        group.append(npc)
    if not group.is_empty(): _groups[key] = group

func perform_nearby(action: String) -> bool:
    var closest: Villager
    var distance: float = 20.0
    for child in get_children():
        var candidate: float = child.global_position.distance_to(_player.global_position)
        if candidate < distance: closest = child; distance = candidate
    return closest != null and closest.perform_action(action)

func _spawn_incremental(key: String, definitions: Array[Dictionary], point: Vector2, scheduler: GenerationScheduler):
    if _groups.has(key) or definitions.is_empty(): return
    var group: Array[Villager] = []
    for definition in definitions:
        if not await scheduler.checkpoint(): return
        if get_child_count() >= MAX_NPCS: break
        var start: Vector2 = definition.route[definition.start%definition.route.size()]
        if point.distance_to(start) > LOAD_DISTANCE: continue
        var npc = Villager.new()
        npc.name = ["Pilgrim","Weaver","Orc"][definition.model]+"_%d"%definition.seed
        npc.configure(_terrain,definition)
        add_child(npc)
        group.append(npc)
    if not group.is_empty(): _groups[key] = group

func _refresh_incremental(point: Vector2, scheduler: GenerationScheduler):
    for key in _groups.keys():
        if not await scheduler.checkpoint(): return
        var group: Array = _groups[key]
        if group.is_empty(): _groups.erase(key); continue
        var nearby = false
        for npc in group:
            if not await scheduler.checkpoint(): return
            if point.distance_to(Vector2(npc.world_position.x,npc.world_position.z)) < UNLOAD_DISTANCE: nearby = true
        if not nearby:
            for npc in group: remove_child(npc); npc.queue_free()
            _groups.erase(key)
    for cell in _settlements._towns:
        if not await scheduler.checkpoint(): return
        var definition: Dictionary = _settlements._towns[cell].get_meta("definition")
        if point.distance_to(definition.position) < LOAD_DISTANCE:
            await _spawn_incremental("town:%s"%cell,await _sampler.town_incremental(definition,scheduler),point,scheduler)
    for cell in _settlements._homes:
        if not await scheduler.checkpoint(): return
        var definition = _sampler._settlements.sample_homestead(cell)
        if point.distance_to(definition.position) < LOAD_DISTANCE:
            await _spawn_incremental("home:%s"%cell,await _sampler.home_incremental(definition,scheduler),point,scheduler)
    var centre = Vector2i(floori(point.x/VillagerPopulationSampler.TRAVEL_CELL),floori(point.y/VillagerPopulationSampler.TRAVEL_CELL))
    for z in range(-1,2):
        if not await scheduler.checkpoint(): return
        for x in range(-1,2):
            if not await scheduler.checkpoint(): return
            var cell = centre+Vector2i(x,z)
            var definitions = await _sampler.travellers_incremental(cell,scheduler)
            if not definitions.is_empty(): await _spawn_incremental("trail:%s"%cell,definitions,point,scheduler)

func _run_refresh(point: Vector2, scheduler: GenerationScheduler):
    scheduler.active_owner = self
    scheduler.active_priority = 2
    await _refresh_incremental(point,scheduler)
    _refreshing = false
