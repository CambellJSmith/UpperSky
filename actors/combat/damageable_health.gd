extends Node
class_name DamageableHealth
signal health_changed
signal died
var state: HealthState = HealthState.new()
func _ready(): _connect_state()
func _connect_state():
    if not state.changed.is_connected(_changed): state.changed.connect(_changed)
    if not state.died.is_connected(_died): state.died.connect(_died)
func _changed(): health_changed.emit()
func _died(): died.emit()
func bind_state(value: HealthState):
    if state.changed.is_connected(_changed): state.changed.disconnect(_changed)
    if state.died.is_connected(_died): state.died.disconnect(_died)
    state = value
    _connect_state()
func initialize(maximum_health: float):
    state.set_maximum_health(maximum_health)
    state.restore_full_health()
func get_health() -> float: return state.get_health()
func get_current_health() -> float: return state.get_health()
func get_maximum_health() -> float: return state.get_maximum_health()
func get_health_ratio() -> float: return state.get_health_ratio()
func get_revision() -> int: return state.get_revision()
func is_dead() -> bool: return state.is_dead()
func apply_damage(amount: float) -> float: return state.apply_damage(amount)
func heal(amount: float) -> float: return state.heal(amount)
func set_health(value: float): state.set_health(value)
func set_maximum_health(value: float): state.set_maximum_health(value)
func restore_full_health(): state.restore_full_health()
func is_infinite_health_enabled() -> bool: return state.is_infinite_health_enabled()
func set_infinite_health_enabled(value: bool): state.set_infinite_health_enabled(value)
func receive_equipment_hit(hit: EquipmentHit):
    if hit != null: apply_damage(hit.damage)
