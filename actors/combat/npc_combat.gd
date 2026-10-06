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
var target: FirstPersonPlayer
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
    if current > HOSTILE_THRESHOLD: cancel()

func cancel():
    attacking = false
    _windup = 0
    _pending_weapon = null
    if active:
        active = false
        combat_ended.emit()

func has_line_of_sight() -> bool:
    if not is_instance_valid(target): return false
    var query = PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP, target.global_position+Vector3.UP, 1|4)
    query.exclude = [actor.get_rid()]
    var hit = actor.get_world_3d().direct_space_state.intersect_ray(query)
    return hit.is_empty() or hit.collider == target

func tick(delta: float) -> bool:
    if not is_instance_valid(target): target = get_tree().get_first_node_in_group("player") as FirstPersonPlayer
    if affection.score > HOSTILE_THRESHOLD or health.is_dead() or not is_instance_valid(target) or not actor.is_visible_in_tree() or not target.is_visible_in_tree() or target.get_health_state().is_dead():
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
            if distance <= _strike_reach and has_line_of_sight(): target.get_health_state().apply_damage(_damage)
    elif _cooldown <= 0 and distance <= get_attack_reach() and has_line_of_sight():
        var kick = _attack_count%3 == 2
        var action = actor.get_weapon_attack_action() if weapon != null else ("kick" if kick else "punch")
        if not actor.has_method("perform_action") or actor.perform_action(action):
            _attack_count += 1
            _pending_weapon = weapon
            _strike_reach = weapon.reach if weapon != null else REACH
            _damage = weapon.damage if weapon != null else (12.0 if kick else 8.0)
            if weapon != null:
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
    var weapon = get_weapon()
    return weapon.reach if weapon != null else REACH
