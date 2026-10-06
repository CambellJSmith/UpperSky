extends Node3D
class_name WayshrineStreamer
@onready var terrain: InfiniteTerrain = $"../Terrain"
@onready var player: FirstPersonPlayer = $"../../DynamicEntities/Player"
var sampler: WayshrineSampler
var _cells: Dictionary = {}
var _building = false
var _pending: Array[Vector2i] = []
var _centre: Vector2i = Vector2i(2147483647,2147483647)
func _ready(): sampler = WayshrineSampler.for_terrain(terrain)
func _process(_delta):
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__process(_delta)
        return
    var _profile_token = RuntimeProfiler.begin("wayshrines.stream")
    _profile__process(_delta)
    RuntimeProfiler.end(_profile_token)

func _profile__process(_delta):
    for shrine in _cells.values():
        if shrine != null: shrine.position = terrain.world_to_local_position(shrine.definition.position)
    if not player.is_physics_processing() or terrain.get_loaded_chunk_count() == 0: return
    var world = terrain.local_to_world_position(player.global_position)
    var centre = Vector2i(floori(world.x/sampler.CELL_SIZE),floori(world.z/sampler.CELL_SIZE))
    if centre != _centre:
        _centre = centre
        _pending.clear()
        for cell in _cells.keys():
            if maxi(absi(cell.x-centre.x),absi(cell.y-centre.y)) > 1:
                if _cells[cell] != null: _cells[cell].queue_free()
                _cells.erase(cell)
        for ring in range(2):
            for z in range(-ring,ring+1):
                for x in range(-ring,ring+1):
                    var cell = centre+Vector2i(x,z)
                    if maxi(absi(x),absi(z)) == ring and not _cells.has(cell): _pending.append(cell)
    if not _pending.is_empty() and not _building:
        var cell = _pending.pop_front()
        if GenerationScheduler.instance == null: ensure_cell(cell)
        else:
            _building = true
            _build_incremental(cell,GenerationScheduler.instance)
func ensure_cell(cell: Vector2i) -> Wayshrine:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        return _profile_ensure_cell(cell)
    var _profile_token = RuntimeProfiler.begin("wayshrines.build")
    var _profile_result = _profile_ensure_cell(cell)
    RuntimeProfiler.end(_profile_token)
    return _profile_result

func _profile_ensure_cell(cell: Vector2i) -> Wayshrine:
    if _cells.has(cell): return _cells[cell]
    var definition = sampler.sample_cell(cell)
    _cells[cell] = null
    if definition.is_empty(): return null
    var shrine = Wayshrine.new()
    shrine.definition = definition
    shrine.position = terrain.world_to_local_position(definition.position)
    add_child(shrine)
    _cells[cell] = shrine
    return shrine

func _build_incremental(cell: Vector2i, scheduler: GenerationScheduler):
    scheduler.active_owner = self
    scheduler.active_priority = 2
    var definition = await sampler.sample_cell_incremental(cell,scheduler)
    _building = false
    if not is_inside_tree() or _cells.has(cell) or maxi(absi(cell.x-_centre.x),absi(cell.y-_centre.y)) > 1: return
    if not await scheduler.checkpoint(self): return
    _cells[cell] = null
    if definition.is_empty(): return
    var shrine = Wayshrine.new()
    shrine.definition = definition
    shrine.position = terrain.world_to_local_position(definition.position)
    add_child(shrine)
    _cells[cell] = shrine
