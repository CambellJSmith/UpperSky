extends Node
class_name NpcCombat
signal combat_started
signal combat_ended
const HOSTILE_THRESHOLD: float = 10.0
const NOTICE_DISTANCE: float = 24.0
const DISENGAGE_DISTANCE: float = 36.0
const REACH: float = 1.8
const ATTACK_INTERVAL: float = 1.4
var actor: CharacterBody3D
var affection: AffectionState
var health: HealthState
var target: Node3D
var _selection_timer := 0.0
var active: bool = false
var attacking: bool = false
var _cooldown: float = 0.0
var _windup: float = 0.0
var _damage: float = 0.0
var _attack_count: int = 0
var _pending_weapon: EquipmentDefinition
var _strike_reach: float = REACH

func configure(body: CharacterBody3D, relationship: AffectionState, vitality: HealthState):
    actor = body
    affection = relationship
    health = vitality
    affection.changed.connect(_affection_changed)
    health.died.connect(cancel)

func _affection_changed(_previous: float, current: float):
    if current > HOSTILE_THRESHOLD and is_instance_valid(target) and target.is_in_group("player"): cancel()

func provoke(source: Node3D):
    var record: Dictionary = actor.get_social_record()
    if not record.has("npc_aggressors"): record["npc_aggressors"] = {}
    record.npc_aggressors[source.get_social_record().npc_id] = true
    _selection_timer = 0

func target_health(body: Node3D) -> HealthState:
    if body.has_method("get_health_state"): return body.get_health_state()
    if body.has_method("get_health_component"):
        var component = body.get_health_component()
        if component != null: return component.state
    return null

func score_for(body: Node3D):
    return affection.score if body.is_in_group("player") else NpcRelationships.get_score(actor,body)

func eligible(body: Node3D) -> bool:
    if not is_instance_valid(body) or body == actor or not body.is_inside_tree() or not body.is_visible_in_tree(): return false
    var vitality = target_health(body)
    if vitality == null or vitality.is_dead(): return false
    if not body.is_in_group("player"):
        if not body.can_process() or actor.get_social_space() != body.get_social_space(): return false
    var score = score_for(body)
    if score == null: return false
    var provoked := false
    if body.has_method("get_social_record"):
        provoked = actor.get_social_record().get("npc_aggressors",{}).has(body.get_social_record().get("npc_id",""))
    return score <= HOSTILE_THRESHOLD or (provoked and score < affection.score)

func select_target():
    var best: Node3D = target if eligible(target) and actor.global_position.distance_to(target.global_position) <= DISENGAGE_DISTANCE else null
    var best_score: float = float(score_for(best)) if best != null else INF
    var candidates: Array[Node3D] = NearbyActorIndex.nearby(get_tree(), actor.global_position, NOTICE_DISTANCE) # Share nearby candidates across this physics frame.
    for body in candidates:
        if body == actor or not eligible(body): continue # Reject self and apply social checks only to nearby candidates.
        var score: float = float(score_for(body))
        if score < best_score and line_of_sight_to(body):
            best = body
            best_score = score
    if best != target:
        cancel()
        target = best

func cancel():
    attacking = false
    _windup = 0
    _pending_weapon = null
    if active:
        active = false
        combat_ended.emit()

func has_line_of_sight() -> bool:
    if not is_instance_valid(target): return false
    return line_of_sight_to(target)

func line_of_sight_to(body: Node3D) -> bool:
    var query = PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP, body.global_position+Vector3.UP, 1|4)
    query.exclude = [actor.get_rid()]
    var hit = actor.get_world_3d().direct_space_state.intersect_ray(query)
    return hit.is_empty() or hit.collider == body

func tick(delta: float) -> bool:
    _selection_timer -= delta
    if _selection_timer <= 0: # Respect perception cadence even when no hostile target exists.
        select_target()
        _selection_timer = .25
    if health.is_dead() or not eligible(target) or not actor.is_visible_in_tree():
        cancel()
        return false
    var distance = actor.global_position.distance_to(target.global_position)
    if distance > (DISENGAGE_DISTANCE if active else NOTICE_DISTANCE):
        cancel()
        return false
    if not active:
        if not has_line_of_sight(): return false
        active = true
        combat_started.emit()
    _cooldown = maxf(0,_cooldown-delta)
    var weapon = get_weapon()
    if attacking and weapon != _pending_weapon:
        # Removing or replacing a weapon cancels the already queued armed hit.
        attacking = false
        _windup = 0
    if attacking:
        _windup -= delta
        if _windup <= 0:
            attacking = false
            # Recheck contact at the strike, so dodging and cover prevent damage.
            if distance <= _strike_reach and has_line_of_sight():
                if is_wizard():
                    var projectile = preload("res://actors/combat/npc_fireball.gd").new()
                    actor.get_parent().add_child(projectile)
                    projectile.launch(actor,target.global_position+Vector3.UP,_damage)
                else:
                    deal_hit(target,_damage)
    elif _cooldown <= 0 and distance <= get_attack_reach() and has_line_of_sight():
        var kick = _attack_count%3 == 2
        var action = "punch" if is_wizard() else (actor.get_weapon_attack_action() if weapon != null else ("kick" if kick else "punch"))
        if not actor.has_method("perform_action") or actor.perform_action(action):
            _attack_count += 1
            _pending_weapon = weapon
            _strike_reach = get_attack_reach()
            _damage = 20.0 if is_wizard() else (weapon.damage if weapon != null else (12.0 if kick else 8.0))
            if is_wizard():
                _windup = .5
                _cooldown = 2.0
            elif weapon != null:
                _windup = {"weapon_slash":.42,"weapon_chop":.48,"weapon_stab":.38}[action]
                _cooldown = weapon.primary_cooldown
            else:
                _windup = .45 if kick else .30
                _cooldown = ATTACK_INTERVAL
            attacking = true
    return true

func get_weapon() -> EquipmentDefinition:
    return actor.get_equipped_weapon() if actor.has_method("get_equipped_weapon") else null
func get_attack_reach() -> float:
    if is_wizard(): return 18.0
    var weapon = get_weapon()
    return weapon.reach if weapon != null else REACH

func is_wizard() -> bool:
    return actor is Villager and actor.model_index == 7 and get_weapon() == null

func deal_hit(body: Node3D, damage: float):
    var hit := EquipmentHit.new()
    hit.source = actor
    hit.damage = damage
    if body.has_method("receive_equipment_hit"): body.receive_equipment_hit(hit)
    else: target_health(body).apply_damage(damage)
