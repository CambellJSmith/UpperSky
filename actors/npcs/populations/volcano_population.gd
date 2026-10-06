extends Node3D
class_name VolcanoPopulation
@onready var _terrain: InfiniteTerrain = $"../Terrain"
@onready var _player: FirstPersonPlayer = $"../../DynamicEntities/Player"
var _elapsed: float = 1
var _ground: CampSampler
var _actors: Dictionary = {}
func _ready(): _ground = CampSampler.new(_terrain)
func definitions(cell: Vector2i) -> Array[Dictionary]:
    var biome = BiomeProfile.region(cell)
    var result: Array[Dictionary] = []
    if biome.kind != BiomeProfile.Kind.VOLCANIC_ISLANDS: return result
    for i in range(4):
        var seed_value = hash("demon:%s:%d"%[cell,i])
        var rng = RandomNumberGenerator.new()
        rng.seed = seed_value
        var centre: Vector2 = biome.centre+Vector2.from_angle(float(i)*TAU/4+biome.phase)*rng.randf_range(180,340)
        var route: Array[Vector2] = [centre,centre+Vector2.from_angle(rng.randf()*TAU)*8]
        var dry = true
        for step in range(9):
            var point = route[0].lerp(route[1],float(step)/8)
            if _terrain.has_water_at(point) or BiomeProfile.is_lava(point): dry = false; break
            if absf(_ground.ground_height(point+Vector2(1,0))-_ground.ground_height(point)) > .7: dry = false; break
        if dry: result.append({"route":route,"model":3,"role":"demon","seed":seed_value,"start":0})
    return result
func _process(delta: float):
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__process(delta)
        return
    var _profile_token = RuntimeProfiler.begin("npcs.volcano_stream")
    _profile__process(delta)
    RuntimeProfiler.end(_profile_token)

func _profile__process(delta: float):
    if not _player.is_physics_processing() or _terrain.get_loaded_chunk_count() == 0: return
    var absolute = _terrain.local_to_world_position(_player.global_position)
    var point = Vector2(absolute.x,absolute.z)
    for key in _actors.keys():
        var npc: Villager = _actors[key]
        npc.position = _terrain.world_to_local_position(npc.world_position)
        var distance = point.distance_to(Vector2(npc.world_position.x,npc.world_position.z))
        if distance > 650:
            remove_child(npc)
            npc.queue_free()
            _actors.erase(key)
        else: npc.set_active(distance < 420)
    _elapsed += delta
    if _elapsed < 1: return
    _elapsed = 0
    var cell = Vector2i(floori(point.x/BiomeProfile.REGION_SIZE),floori(point.y/BiomeProfile.REGION_SIZE))
    for z in range(-1,2):
        for x in range(-1,2):
            var region_cell = cell+Vector2i(x,z)
            if point.distance_to(BiomeProfile.region(region_cell).centre) > 850: continue
            for definition in definitions(region_cell):
                if _actors.size() >= 8 or _actors.has(definition.seed): continue
                if point.distance_to(definition.route[0]) > 420: continue
                var npc = Villager.new()
                npc.name = "Demon_%d"%definition.seed
                npc.configure(_terrain,definition)
                add_child(npc)
                _actors[definition.seed] = npc
