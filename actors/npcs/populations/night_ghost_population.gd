extends Node3D
class_name NightGhostPopulation

const CELL_SIZE := 256.0
const MAX_GHOSTS := 8
const FADE_SECONDS := 8.0
@onready var _terrain: InfiniteTerrain = $"../Terrain"
@onready var _player: FirstPersonPlayer = $"../../DynamicEntities/Player"
var _actors: Dictionary = {}
var _pending: Array[Vector2i] = []
var _centre := Vector2i(2147483647,2147483647)
var _elapsed := 0.0
var _night := false
var _spawning := false
var _routes: VillagerPopulationSampler

static func is_night(hour: float) -> bool:
    return DayNightCycle.is_night_hour(hour)

func _ready():
    _routes = VillagerPopulationSampler.new(_terrain)

func wandering_route(point: Vector2, rng: RandomNumberGenerator) -> Array[Vector2]:
    for attempt in range(8):
        var route: Array[Vector2] = [point,point+Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(12,32)]
        if _routes.route_safe(route,false): return route
    return []

func _materials(node: Node, result: Array[BaseMaterial3D]):
    if node is MeshInstance3D and node.mesh != null:
        for surface in range(node.mesh.get_surface_count()):
            var source = node.get_active_material(surface)
            if source is BaseMaterial3D:
                var material: BaseMaterial3D = source.duplicate()
                material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
                node.set_surface_override_material(surface,material)
                result.append(material)
    for child in node.get_children(): _materials(child,result)

func _process(delta: float):
    var clock := get_tree().get_first_node_in_group(DayNightCycle.GROUP_NAME) as DayNightCycle
    if clock == null or not _player.is_physics_processing(): return
    var night := is_night(clock.get_time_of_day_hours())
    var absolute := _terrain.local_to_world_position(_player.global_position)
    var point := Vector2(absolute.x,absolute.z)
    for key in _actors.keys():
        var entry: Dictionary = _actors[key]
        var npc: Villager = entry.npc
        npc.position = _terrain.world_to_local_position(npc.world_position)
        if not night:
            npc.set_active(false)
            npc.remove_from_group("npc")
            entry.fade = maxf(0.0,entry.fade-delta/FADE_SECONDS)
        else:
            if not npc.health.is_dead():
                npc.add_to_group("npc")
                npc.set_active(point.distance_to(Vector2(npc.world_position.x,npc.world_position.z)) < 420)
            entry.fade = minf(1.0,entry.fade+delta/2.0)
            entry.wander -= delta
            if entry.wander <= 0 and not npc.health.is_dead() and not npc._was_in_combat:
                var route := wandering_route(Vector2(npc.world_position.x,npc.world_position.z),entry.rng)
                if not route.is_empty():
                    npc.route = route
                    npc._waypoint = 1
                entry.wander = entry.rng.randf_range(10,25)
        for material: BaseMaterial3D in entry.materials:
            material.albedo_color.a = entry.fade
        if entry.fade <= 0 or point.distance_to(Vector2(npc.world_position.x,npc.world_position.z)) > 650:
            npc.queue_free()
            _actors.erase(key)
    if not night:
        _pending.clear()
        _night = false
        return
    var centre := Vector2i((point/CELL_SIZE).floor())
    if not _night or centre != _centre:
        _pending.clear()
        for z in range(-2,3):
            for x in range(-2,3): _pending.append(centre+Vector2i(x,z))
        _pending.sort_custom(func(a,b): return point.distance_squared_to((Vector2(a)+Vector2.ONE*.5)*CELL_SIZE)<point.distance_squared_to((Vector2(b)+Vector2.ONE*.5)*CELL_SIZE))
        _centre = centre
    _night = true
    _elapsed += delta
    if _elapsed < .25 or _pending.is_empty() or _actors.size() >= MAX_GHOSTS or _spawning: return
    _elapsed = 0
    var cell: Vector2i = _pending.pop_front()
    var seed_value := hash("night-ghost:%s"%cell)
    if _actors.has(seed_value): return
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    if rng.randf() > .65: return
    var start := Vector2(cell)*CELL_SIZE+Vector2(rng.randf_range(32,224),rng.randf_range(32,224))
    if point.distance_to(start)>420 or point.distance_to(start)<30: return
    var route: Array[Vector2] = []
    var scheduler := GenerationScheduler.instance
    if scheduler != null:
        _spawning = true
        scheduler.active_owner = self
        scheduler.active_priority = 3
        for attempt in range(8):
            var candidate: Array[Vector2] = [start,start+Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(12,32)]
            if await _routes.route_safe_incremental(candidate,scheduler,false):
                route = candidate
                break
        _spawning = false
        # A route search may span sunrise or a world-space transition.
        if not is_inside_tree() or not is_night(clock.get_time_of_day_hours()) or not _player.is_physics_processing(): return
    else:
        route = wandering_route(start,rng)
    if route.is_empty(): return
    var npc := Villager.new()
    npc.name = "NightGhost_%d"%seed_value
    npc.configure(_terrain,{"route":route,"model":4,"role":"night_ghost","seed":seed_value,"start":0})
    if npc._loot_record.health.is_dead():
        npc.free()
        return
    add_child(npc)
    var materials: Array[BaseMaterial3D] = []
    _materials(npc,materials)
    for material in materials: material.albedo_color.a = 0.0
    _actors[seed_value] = {"npc":npc,"materials":materials,"fade":.001,"wander":rng.randf_range(10,25),"rng":rng}
