extends Node3D
class_name WaterPopulation
@onready var _terrain: InfiniteTerrain = $"../Terrain"
@onready var _player: FirstPersonPlayer = $"../../DynamicEntities/Player"
var _elapsed: float = 1
var _ground: CampSampler
var _actors: Dictionary = {}
func _ready(): _ground = CampSampler.new(_terrain)
var _definitions: Dictionary = {}
func _remember(cell: Vector2i, result: Array[Dictionary]):
    if _definitions.size() >= 128: _definitions.erase(_definitions.keys()[0])
    _definitions[cell] = result
const CELL_SIZE: float = 512.0
func near_water(point: Vector2) -> bool:
    if _terrain.has_water_at(point): return false
    for offset in [Vector2(24,0),Vector2(-24,0),Vector2(0,24),Vector2(0,-24)]:
        if _terrain.has_water_at(point+offset): return true
    return false
func definitions(cell: Vector2i) -> Array[Dictionary]:
    if _definitions.has(cell): return _definitions[cell]
    var result: Array[Dictionary] = []
    var rng = RandomNumberGenerator.new()
    rng.seed = hash("fish-man:%s"%cell)
    for attempt in range(72):
        var centre = (Vector2(cell)+Vector2(rng.randf(),rng.randf()))*CELL_SIZE
        if not near_water(centre) or BiomeProfile.is_lava(centre) or _ground.is_clearing(centre): continue
        for direction in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]:
            var end = centre+direction*8
            var safe = true
            for step in range(9):
                var point = centre.lerp(end,float(step)/8)
                if not near_water(point) or BiomeProfile.is_lava(point) or _ground.is_clearing(point): safe = false; break
                if SettlementSampler.for_terrain(_terrain).is_clearing(point): safe = false; break
                if absf(_ground.ground_height(point+direction)-_ground.ground_height(point)) > .35: safe = false; break
            if safe:
                var route: Array[Vector2] = [centre,end]
                var fish_seed = hash("fish:%s:%d"%[cell, result.size()])
                result.append({"route":route,"model":6,"role":"fish_man","seed":fish_seed,"start":0})
                if result.size() >= 3:
                    _remember(cell,result)
                    return result
                break
    _remember(cell,result)
    return result
func _process(delta: float):
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__process(delta)
        return
    var _profile_token = RuntimeProfiler.begin("npcs.water_stream")
    _profile__process(delta)
    RuntimeProfiler.end(_profile_token)

func _profile__process(delta: float):
    if not _player.is_physics_processing() or _terrain.get_loaded_chunk_count() == 0: return
    var absolute = _terrain.local_to_world_position(_player.global_position)
    var point = Vector2(absolute.x,absolute.z)
    for key in _actors.keys():
        var npc: Villager = _actors[key]
        var distance = point.distance_to(Vector2(npc.world_position.x,npc.world_position.z))
        if distance > 650:
            remove_child(npc)
            npc.queue_free()
            _actors.erase(key)
        else: npc.set_active(distance < 420)
    _elapsed += delta
    if _elapsed < 1: return
    _elapsed = 0
    var cell = Vector2i(floori(point.x/CELL_SIZE),floori(point.y/CELL_SIZE))
    for z in range(-1,2):
        for x in range(-1,2):
            var region_cell = cell+Vector2i(x,z)
            if point.distance_to((Vector2(region_cell)+Vector2(.5,.5))*CELL_SIZE) > 800: continue
            for definition in definitions(region_cell):
                if _actors.size() >= 16 or _actors.has(definition.seed): continue
                if point.distance_to(definition.route[0]) > 420: continue
                var npc = Villager.new()
                npc.name = "FishMan_%d"%definition.seed
                npc.configure(_terrain,definition)
                add_child(npc)
                _actors[definition.seed] = npc
