extends Node3D
class_name VillagerPopulationStreamer

const LOAD_DISTANCE: float = 420.0
const UNLOAD_DISTANCE: float = 600.0
const MAX_NPCS: int = 72
const RESIDENT_LIMIT: int = 48
const TRAVELLER_LIMIT: int = 48
const TRAFFIC_INTERVAL: int = 180
@onready var _terrain: InfiniteTerrain = $"../Terrain"
@onready var _player: FirstPersonPlayer = $"../../DynamicEntities/Player"
@onready var _settlements: SettlementStreamer = $"../Settlements"
var _sampler: VillagerPopulationSampler
var _groups: Dictionary = {}
var _refreshing = false
var _local_refreshing = false
var _elapsed: float = 1.0

func _ready():
	_sampler = VillagerPopulationSampler.new(_terrain)
	_sampler.set_traffic_wave(int(Time.get_unix_time_from_system())/TRAFFIC_INTERVAL)
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
	_sampler.set_traffic_wave(int(Time.get_unix_time_from_system())/TRAFFIC_INTERVAL)
	var position_world = _terrain.local_to_world_position(_player.global_position)
	var point = Vector2(position_world.x,position_world.z)
	for group in _groups.values():
		for npc: Villager in group:
			npc.set_active(point.distance_to(Vector2(npc.world_position.x,npc.world_position.z)) < LOAD_DISTANCE)
	_elapsed += delta
	if _elapsed > 1.0:
		_elapsed = 0
		if GenerationScheduler.instance == null: _refresh(point)
		else:
			if not _local_refreshing:
				_local_refreshing = true
				_run_local_refresh(point,GenerationScheduler.instance)
			if not _refreshing:
				_refreshing = true
				_run_refresh(point,GenerationScheduler.instance)

func _refresh(point: Vector2):
	for key in _groups.keys():
		var group: Array = _groups.get(key,[])
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
	for z in range(-2,3):
		for x in range(-2,3):
			var cell = centre+Vector2i(x,z)
			var definitions = _sampler.travellers(cell)
			if not definitions.is_empty(): _spawn("trail:%s"%cell,definitions,point)

func _spawn(key: String, definitions: Array[Dictionary], point: Vector2):
	if definitions.is_empty(): return
	var group: Array[Villager] = []
	group.assign(_groups.get(key,[]))
	for definition in definitions:
		var exists := false
		for existing in get_children():
			if existing.get_meta("spawn_seed",0) == definition.seed: exists = true; break
		if exists: continue
		if get_child_count() >= MAX_NPCS: break
		var role_count := 0
		for existing in get_children():
			if (existing.role=="traveller") == (definition.role=="traveller"): role_count+=1
		if role_count >= (TRAVELLER_LIMIT if definition.role=="traveller" else RESIDENT_LIMIT): continue
		var start: Vector2 = definition.route[definition.start%definition.route.size()]
		var record: Dictionary = LootSession.records.get("npc:%s:%d:%d"%[definition.role,definition.model,definition.seed],{})
		var saved: Dictionary = record.get("journey",{})
		if saved.get("key","") == definition.get("journey",{}).get("key","missing") and saved.get("position") is Vector3:
			start = Vector2(saved.position.x,saved.position.z)
		if point.distance_to(start) > LOAD_DISTANCE: continue
		if _player.is_physics_processing():
			var current := _terrain.local_to_world_position(_player.global_position)
			if Vector2(current.x,current.z).distance_to(start)>LOAD_DISTANCE: continue
		var npc = Villager.new()
		npc.name = "Knight_%d"%definition.seed if definition.model == 9 else "Wizard_%d"%definition.seed if definition.model == 7 else ["Pilgrim","Weaver","Orc"][definition.model]+"_%d"%definition.seed
		npc.set_meta("spawn_seed",definition.seed)
		npc.set_meta("leader_seed",definition.get("leader_seed",definition.seed))
		npc.configure(_terrain,definition)
		add_child(npc)
		group.append(npc)
	group.assign(group.filter(func(npc): return is_instance_valid(npc) and npc.is_inside_tree()))
	if not group.is_empty():
		_groups[key] = group
		_link_party(group)

func perform_nearby(action: String) -> bool:
	var closest: Villager
	var distance: float = 20.0
	for child in get_children():
		var candidate: float = child.global_position.distance_to(_player.global_position)
		if candidate < distance: closest = child; distance = candidate
	return closest != null and closest.perform_action(action)

func _spawn_incremental(key: String, definitions: Array[Dictionary], point: Vector2, scheduler: GenerationScheduler):
	if definitions.is_empty(): return
	var group: Array[Villager] = []
	group.assign(_groups.get(key,[]))
	for definition in definitions:
		if not await scheduler.checkpoint(): return
		var exists := false
		for existing in get_children():
			if existing.get_meta("spawn_seed",0) == definition.seed: exists = true; break
		if exists: continue
		if get_child_count() >= MAX_NPCS: break
		var role_count := 0
		for existing in get_children():
			if (existing.role=="traveller") == (definition.role=="traveller"): role_count+=1
		if role_count >= (TRAVELLER_LIMIT if definition.role=="traveller" else RESIDENT_LIMIT): continue
		var start: Vector2 = definition.route[definition.start%definition.route.size()]
		var record: Dictionary = LootSession.records.get("npc:%s:%d:%d"%[definition.role,definition.model,definition.seed],{})
		var saved: Dictionary = record.get("journey",{})
		if saved.get("key","") == definition.get("journey",{}).get("key","missing") and saved.get("position") is Vector3:
			start = Vector2(saved.position.x,saved.position.z)
		if point.distance_to(start) > LOAD_DISTANCE: continue
		if _player.is_physics_processing():
			var current := _terrain.local_to_world_position(_player.global_position)
			if Vector2(current.x,current.z).distance_to(start)>LOAD_DISTANCE: continue
		var npc = Villager.new()
		npc.name = "Knight_%d"%definition.seed if definition.model == 9 else "Wizard_%d"%definition.seed if definition.model == 7 else ["Pilgrim","Weaver","Orc"][definition.model]+"_%d"%definition.seed
		npc.set_meta("spawn_seed",definition.seed)
		npc.set_meta("leader_seed",definition.get("leader_seed",definition.seed))
		npc.configure(_terrain,definition)
		add_child(npc)
		group.append(npc)
	group.assign(group.filter(func(npc): return is_instance_valid(npc) and npc.is_inside_tree()))
	if not group.is_empty():
		_groups[key] = group
		_link_party(group)

func _refresh_local_incremental(point: Vector2, scheduler: GenerationScheduler):
	for key in _groups.keys():
		if not await scheduler.checkpoint(): return
		var group: Array = _groups.get(key,[])
		if group.is_empty(): _groups.erase(key); continue
		var nearby = false
		for npc in group:
			if point.distance_to(Vector2(npc.world_position.x,npc.world_position.z)) < UNLOAD_DISTANCE: nearby = true
		if not nearby:
			for npc in group: remove_child(npc); npc.queue_free()
			_groups.erase(key)
	for cell in _settlements._towns.keys():
		if not await scheduler.checkpoint(): return
		var town = _settlements._towns.get(cell)
		if not is_instance_valid(town): continue
		var definition: Dictionary = town.get_meta("definition")
		if point.distance_to(definition.position) < LOAD_DISTANCE:
			await _spawn_incremental("town:%s"%cell,await _sampler.town_incremental(definition,scheduler),point,scheduler)
	for cell in _settlements._homes.keys():
		if not await scheduler.checkpoint(): return
		if not is_instance_valid(_settlements._homes.get(cell)): continue
		var definition = _sampler._settlements.sample_homestead(cell)
		if definition.is_empty(): continue
		if point.distance_to(definition.position) < LOAD_DISTANCE:
			await _spawn_incremental("home:%s"%cell,await _sampler.home_incremental(definition,scheduler),point,scheduler)

func _refresh_incremental(point: Vector2, scheduler: GenerationScheduler):
	var centre = Vector2i(floori(point.x/VillagerPopulationSampler.TRAVEL_CELL),floori(point.y/VillagerPopulationSampler.TRAVEL_CELL))
	for z in range(-2,3):
		if not await scheduler.checkpoint(): return
		for x in range(-2,3):
			if not await scheduler.checkpoint(): return
			var cell = centre+Vector2i(x,z)
			var definitions = await _sampler.travellers_incremental(cell,scheduler)
			if not definitions.is_empty(): await _spawn_incremental("trail:%s"%cell,definitions,point,scheduler)

func _run_local_refresh(point: Vector2, scheduler: GenerationScheduler):
	scheduler.active_owner = self
	scheduler.active_priority = 1
	await _refresh_local_incremental(point,scheduler)
	_local_refreshing = false

func _run_refresh(point: Vector2, scheduler: GenerationScheduler):
	scheduler.active_owner = self
	scheduler.active_priority = 3
	await _refresh_incremental(point,scheduler)
	_refreshing = false

func _link_party(group: Array[Villager]) -> void:
	var leaders: Dictionary = {}
	for npc in group: leaders[npc.get_meta("spawn_seed")] = npc
	for npc in group:
		var leader = leaders.get(npc.get_meta("leader_seed"))
		if is_instance_valid(leader) and leader != npc: npc.follow_leader = weakref(leader)
