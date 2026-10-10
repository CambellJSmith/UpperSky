extends Node3D
class_name PathStreamer

@onready var _terrain: InfiniteTerrain = $"../Terrain"
@onready var _player: FirstPersonPlayer = $"../../DynamicEntities/Player"
var _building: Dictionary = {}
var _builder: PathMeshBuilder
var _chunks: Dictionary = {}
var _pending: Array[Vector2i] = []
var _centre: Vector2i = Vector2i(2147483647,2147483647)
var _dirty := {}
var _warm_pending: Array[Vector2i] = []
var _warming := false
func _ready():
    _builder = PathMeshBuilder.new(_terrain)
    _builder._network.chunk_routes_ready.connect(_routes_ready)

    _terrain.origin_shifted.connect(_update_origin_positions) # Subscribe static scenery to completed origin shifts.

func _routes_ready(cell: Vector2i):
    if maxi(absi(cell.x-_centre.x),absi(cell.y-_centre.y))>4: return
    _dirty[cell] = true
    if _building.has(cell):
        return
    if cell not in _pending: _pending.push_front(cell)

func _warm(cell: Vector2i, scheduler: GenerationScheduler):
    _warming = true
    scheduler.active_owner = self
    scheduler.active_priority = 2
    await _builder._network.routes_in_chunk_incremental(cell,scheduler)
    _warming = false

func _process(_delta: float):
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__process(_delta)
        return
    var _profile_token = RuntimeProfiler.begin("paths.stream")
    _profile__process(_delta)
    RuntimeProfiler.end(_profile_token)

func _profile__process(_delta: float):
    if _terrain.get_loaded_chunk_count() == 0 or not _player.is_physics_processing(): return
    var world = _terrain.local_to_world_position(_player.global_position)
    var centre = Vector2i(floori(world.x/WorldPathNetwork.CHUNK_SIZE),floori(world.z/WorldPathNetwork.CHUNK_SIZE))
    if centre != _centre: _refresh(centre)
    if not _pending.is_empty() and _building.is_empty():
        var cell = _pending.pop_front()
        _dirty.erase(cell)
        if GenerationScheduler.instance == null: _build(cell)
        else:
            _building[cell] = true
            _build_incremental(cell,GenerationScheduler.instance)
    if not _warming and not _warm_pending.is_empty() and GenerationScheduler.instance!=null:
        _warm(_warm_pending.pop_front(),GenerationScheduler.instance)

func _refresh(centre: Vector2i):
    _centre = centre
    _pending.clear()
    _warm_pending.clear()
    for cell in _chunks.keys():
        if maxi(absi(cell.x-centre.x),absi(cell.y-centre.y)) > 4:
            var node = _chunks[cell]
            remove_child(node)
            node.queue_free()
            _chunks.erase(cell)
            _dirty.erase(cell)
    for z in range(-3,4):
        for x in range(-3,4):
            var cell = centre+Vector2i(x,z)
            if not _chunks.has(cell) or _dirty.has(cell): _pending.append(cell)
            if not _builder._network._chunks.has(cell): _warm_pending.append(cell)
    _pending.sort_custom(func(a,b): return Vector2(a-centre).length_squared() < Vector2(b-centre).length_squared())
    _warm_pending.sort_custom(func(a,b): return Vector2(a-centre).length_squared() < Vector2(b-centre).length_squared())

func _build(cell: Vector2i):
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__build(cell)
        return
    var _profile_token = RuntimeProfiler.begin("paths.build_chunk")
    _profile__build(cell)
    RuntimeProfiler.end(_profile_token)

func _profile__build(cell: Vector2i):
    var mesh = _builder.build(cell)
    var node = MeshInstance3D.new()
    node.name = "Paths_%d_%d"%[cell.x,cell.y]
    node.mesh = mesh
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    node.position = _terrain.world_to_local_position(Vector3(cell.x*WorldPathNetwork.CHUNK_SIZE,0,cell.y*WorldPathNetwork.CHUNK_SIZE))
    add_child(node)
    _add_bridges(node,cell)
    if _chunks.has(cell): _chunks[cell].queue_free()
    _chunks[cell] = node

func _build_incremental(cell: Vector2i, scheduler: GenerationScheduler):
    scheduler.active_owner = self
    scheduler.active_priority = 1 if maxi(absi(cell.x-_centre.x),absi(cell.y-_centre.y)) <= 1 else 2
    var mesh = await _builder.build_incremental(cell,scheduler,true)
    _building.erase(cell)
    if _dirty.has(cell):
        if not scheduler._closing and cell not in _pending: _pending.push_front(cell)
    if scheduler._closing or is_queued_for_deletion() or not is_inside_tree() or maxi(absi(cell.x-_centre.x),absi(cell.y-_centre.y)) > 4: return
    var node = MeshInstance3D.new()
    node.name = "Paths_%d_%d"%[cell.x,cell.y]
    node.mesh = mesh
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    node.position = _terrain.world_to_local_position(Vector3(cell.x*WorldPathNetwork.CHUNK_SIZE,0,cell.y*WorldPathNetwork.CHUNK_SIZE))
    add_child(node)
    _add_bridges(node,cell)
    if _chunks.has(cell): _chunks[cell].queue_free()
    _chunks[cell] = node

func _add_bridges(node: MeshInstance3D, cell: Vector2i):
    var seen := {}
    for road in WorldPathNetwork.for_terrain(_terrain).cached_routes_in_chunk(cell):
        for bridge in road.bridges:
            var middle: Vector2 = (bridge.a+bridge.b)*.5
            if Vector2i((middle/WorldPathNetwork.CHUNK_SIZE).floor()) != cell or seen.has(bridge.key): continue
            seen[bridge.key] = true
            node.add_child(RoadBridge.build(bridge,_terrain,cell))

func _update_origin_positions() -> void: # Reposition retained static roots only after an origin shift.
    for cell in _chunks:
        var node: MeshInstance3D = _chunks[cell]
        node.position = _terrain.world_to_local_position(Vector3(cell.x*WorldPathNetwork.CHUNK_SIZE,0,cell.y*WorldPathNetwork.CHUNK_SIZE))
