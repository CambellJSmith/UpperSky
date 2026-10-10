extends Node3D
class_name CampStreamer

const STREAM_RADIUS: int = 3
var _terrain: InfiniteTerrain
var _player: FirstPersonPlayer
var _sampler: CampSampler
var _cells: Dictionary[Vector2i, Node3D] = {}
var _pending: Array[Vector2i] = []
var _centre: Vector2i = Vector2i(2147483647, 2147483647)
var _building = false
var _elapsed: float = 0.0

func _ready() -> void:
    _terrain = get_node("../World/Terrain") as InfiniteTerrain
    _player = get_node("../DynamicEntities/Player") as FirstPersonPlayer
    _sampler = CampSampler.new(_terrain)

    _terrain.origin_shifted.connect(_update_origin_positions) # Subscribe static scenery to completed origin shifts.

func _process(delta: float) -> void:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__process(delta)
        return
    var _profile_token = RuntimeProfiler.begin("camps.stream")
    _profile__process(delta)
    RuntimeProfiler.end(_profile_token)

func _profile__process(delta: float) -> void:
    if _terrain.get_loaded_chunk_count() == 0 or not _player.is_physics_processing():
        return
    _elapsed += delta
    if _elapsed >= 0.2:
        _elapsed = 0.0
        var world: Vector3 = _terrain.local_to_world_position(_player.global_position)
        var centre: Vector2i = Vector2i(floori(world.x / CampSampler.CELL_SIZE), floori(world.z / CampSampler.CELL_SIZE))
        if centre != _centre:
            _centre = centre
            _refresh()
    if not _pending.is_empty() and not _building:
        var cell = _pending.pop_front()
        if GenerationScheduler.instance == null: _build_cell(cell)
        else:
            _building = true
            _run_build(cell,GenerationScheduler.instance)

func _refresh() -> void:
    _pending.clear()
    for cell: Vector2i in _cells.keys():
        if maxi(absi(cell.x - _centre.x), absi(cell.y - _centre.y)) > STREAM_RADIUS:
            if _cells[cell] != null:
                _cells[cell].queue_free()
            _cells.erase(cell)
    for ring: int in range(STREAM_RADIUS + 1):
        for z: int in range(-ring, ring + 1):
            for x: int in range(-ring, ring + 1):
                if maxi(absi(x), absi(z)) != ring:
                    continue
                var cell: Vector2i = _centre + Vector2i(x, z)
                if not _cells.has(cell):
                    _pending.append(cell)

func _build_cell(cell: Vector2i) -> void:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__build_cell(cell)
        return
    var _profile_token = RuntimeProfiler.begin("camps.build")
    _profile__build_cell(cell)
    RuntimeProfiler.end(_profile_token)

func _profile__build_cell(cell: Vector2i) -> void:
    var definition: Dictionary = _sampler.sample_cell(cell)
    _cells[cell] = null # Remember empty cells without allocating scene nodes.
    if definition.is_empty():
        return
    var point: Vector2 = definition["position"]
    var world: Vector3 = Vector3(point.x, _sampler.ground_height(point), point.y)
    var camp: Node3D = CampGeometry.new().build(_sampler, point, definition["yaw"], definition["seed"])
    camp.name = "Camp_%d_%d" % [cell.x, cell.y]
    camp.set_meta("world_position", world)
    camp.position = _terrain.world_to_local_position(world)
    var chest = LootChest.new()
    chest.loot_key = "camp:%s"%cell
    chest.seed_value = definition.seed
    var offset = Vector2(0,-3.5).rotated(definition.yaw)
    chest.position = Vector3(offset.x,_sampler.ground_height(point+offset)-world.y+.04,offset.y)
    camp.add_child(chest)
    add_child(camp)
    _cells[cell] = camp

func _build_cell_incremental(cell: Vector2i, scheduler: GenerationScheduler) -> void:
    var definition: Dictionary = await _sampler.sample_cell_incremental(cell,scheduler)
    if maxi(absi(cell.x-_centre.x),absi(cell.y-_centre.y)) > STREAM_RADIUS: return
    if not await scheduler.checkpoint(self): return
    _cells[cell] = null # Remember empty cells without allocating scene nodes.
    if definition.is_empty():
        return
    var point: Vector2 = definition["position"]
    var world: Vector3 = Vector3(point.x, _sampler.ground_height(point), point.y)
    var camp: Node3D = CampGeometry.new().build(_sampler, point, definition["yaw"], definition["seed"])
    camp.name = "Camp_%d_%d" % [cell.x, cell.y]
    camp.set_meta("world_position", world)
    camp.position = _terrain.world_to_local_position(world)
    var chest = LootChest.new()
    chest.loot_key = "camp:%s"%cell
    chest.seed_value = definition.seed
    var offset = Vector2(0,-3.5).rotated(definition.yaw)
    chest.position = Vector3(offset.x,_sampler.ground_height(point+offset)-world.y+.04,offset.y)
    camp.add_child(chest)
    add_child(camp)
    _cells[cell] = camp

func _run_build(cell: Vector2i, scheduler: GenerationScheduler):
    scheduler.active_owner = self
    scheduler.active_priority = 2
    await _build_cell_incremental(cell,scheduler)
    _building = false

func _update_origin_positions() -> void: # Reposition retained static roots only after an origin shift.
    for root: Node3D in _cells.values():
        if root != null:
            root.position = _terrain.world_to_local_position(root.get_meta("world_position"))
