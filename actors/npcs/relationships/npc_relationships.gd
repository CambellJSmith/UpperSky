extends Node
class_name NpcRelationships

const MEETING_DISTANCE := 50.0
const SAME_SPECIES_BONUS := 50.0
const CHECK_INTERVAL := .25
var _elapsed := CHECK_INTERVAL

func _process(delta: float) -> void:
    _elapsed += delta
    if _elapsed < CHECK_INTERVAL: return
    _elapsed = 0
    scan(get_tree().get_nodes_in_group("npc"))

func scan(actors: Array) -> void:
    var cells := {}
    for actor in actors:
        if not is_instance_valid(actor) or not actor.is_inside_tree() or not actor.can_process(): continue
        if not actor.has_method("get_social_record") or actor.get_social_record().is_empty(): continue
        var health: DamageableHealth = actor.get_health_component()
        if health == null or health.is_dead(): continue
        var space: Object = actor.get_social_space()
        if not is_instance_valid(space): continue
        var point: Vector3 = actor.global_position
        var cell := Vector3i(floori(point.x/MEETING_DISTANCE),floori(point.y/MEETING_DISTANCE),floori(point.z/MEETING_DISTANCE))
        if not cells.has(space.get_instance_id()): cells[space.get_instance_id()] = {}
        var grid: Dictionary = cells[space.get_instance_id()]
        for z in range(-1,2):
            for y in range(-1,2):
                for x in range(-1,2):
                    for other in grid.get(cell+Vector3i(x,y,z),[]): meet(actor,other)
        if not grid.has(cell): grid[cell] = []
        grid[cell].append(actor)

static func meet(a: Node3D, b: Node3D) -> bool:
    if a == b or not is_instance_valid(a) or not is_instance_valid(b): return false
    if a.get_social_space() != b.get_social_space(): return false
    if a.global_position.distance_squared_to(b.global_position) > MEETING_DISTANCE*MEETING_DISTANCE: return false
    var first: Dictionary = a.get_social_record()
    var second: Dictionary = b.get_social_record()
    if first.is_empty() or second.is_empty(): return false
    var id_a: String = first.get("npc_id","")
    var id_b: String = second.get("npc_id","")
    if id_a.is_empty() or id_b.is_empty() or id_a==id_b: return false
    var bonus := SAME_SPECIES_BONUS if a.get_relationship_species()==b.get_relationship_species() else 0.0
    _initialize_direction(first,id_b,a.get_default_affection(),bonus)
    _initialize_direction(second,id_a,b.get_default_affection(),bonus)
    return true

static func _initialize_direction(record: Dictionary, target: String, base_score: float, bonus: float) -> void:
    if not record.has("npc_affection"): record["npc_affection"] = {}
    if record.npc_affection.has(target): return
    record.npc_affection[target] = AffectionState.new(base_score+bonus)

static func get_state(actor: Node, other: Node) -> AffectionState:
    if not is_instance_valid(other) or not other.has_method("get_social_record"): return null
    var record: Dictionary = actor.get_social_record()
    var target: Dictionary = other.get_social_record()
    return record.get("npc_affection",{}).get(target.get("npc_id",""))

static func get_score(actor: Node, other: Node):
    var state := get_state(actor,other)
    return state.score if state != null else null

static func set_score(actor: Node, other: Node, value: float) -> bool:
    var state := get_state(actor,other)
    if state == null: return false
    state.set_score(value)
    return true

static func change_score(actor: Node, other: Node, amount: float) -> bool:
    var state := get_state(actor,other)
    if state == null: return false
    state.change_score(amount)
    return true

static func damage_received(actor: Node3D, source: Node3D, amount: float) -> void:
    if amount <= 0 or not is_instance_valid(source) or source == actor: return
    if source.is_in_group("player"):
        actor.change_affection(-amount)
    elif source.has_method("get_social_record"):
        meet(actor,source)
        if change_score(actor,source,-amount) and actor.combat != null:
            actor.combat.provoke(source)
