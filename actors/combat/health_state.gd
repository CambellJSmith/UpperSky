extends RefCounted
class_name HealthState
signal changed
signal died
const DEFAULT_MAXIMUM: float = 100.0
const MINIMUM_MAXIMUM: float = .001
var _maximum: float = DEFAULT_MAXIMUM
var _current: float = DEFAULT_MAXIMUM
var _invulnerable: bool = false
var _revision: int = 0
func get_health() -> float: return _current
func get_maximum_health() -> float: return _maximum
func get_revision() -> int: return _revision
func get_health_ratio() -> float: return _current/_maximum
func is_dead() -> bool: return _current <= 0
func is_infinite_health_enabled() -> bool: return _invulnerable
func _notify(was_alive: bool):
    _revision += 1
    changed.emit()
    if was_alive and is_dead(): died.emit()
func set_health(value: float):
    if not is_finite(value): return
    var next = _maximum if _invulnerable else clampf(value,0,_maximum)
    if next == _current: return
    var was_alive = not is_dead()
    _current = next
    _notify(was_alive)
func set_maximum_health(value: float):
    if not is_finite(value): return
    var next = maxf(value,MINIMUM_MAXIMUM)
    if is_equal_approx(next,_maximum): return
    _maximum = next
    _current = _maximum if _invulnerable else minf(_current,_maximum)
    _notify(not is_dead())
func apply_damage(amount: float) -> float:
    if not is_finite(amount) or amount <= 0 or _invulnerable or is_dead(): return 0
    var previous = _current
    set_health(_current-amount)
    return previous-_current
func heal(amount: float) -> float:
    if not is_finite(amount) or amount <= 0: return 0
    var previous = _current
    set_health(_current+amount)
    return _current-previous
func restore_full_health(): set_health(_maximum)
func set_infinite_health_enabled(enabled: bool):
    if enabled == _invulnerable: return
    _invulnerable = enabled
    if enabled: restore_full_health()
