extends Node # Stores reusable health state for damageable world actors without owning presentation or combat input.
class_name DamageableHealth # Exposes a strongly typed health component for enemies, targets, and future damageable actors.

var _maximum_health: float = 1.0 # Stores the validated maximum health used for clamping and normalized display values.
var _current_health: float = 1.0 # Stores the actor's current remaining health.
var _revision: int = 0 # Increments whenever health changes so presentation code can refresh without signals.

func initialize(maximum_health: float) -> void: # Initializes or fully resets this health component to a validated maximum value.
    _maximum_health = maxf(maximum_health, 1.0) # Prevents zero or negative maximum health from creating invalid ratios.
    _current_health = _maximum_health # Starts the actor at full health whenever the component is initialized.
    _revision += 1 # Marks the health state as changed for any polling presentation layer.

func apply_damage(amount: float) -> float: # Removes positive health and returns the exact damage actually applied after clamping.
    if amount <= 0.0 or is_dead(): # Rejects healing-through-damage and repeated damage after health has reached zero.
        return 0.0 # Reports that no health changed for the rejected request.
    var previous_health: float = _current_health # Captures the pre-hit value so applied damage can be measured exactly.
    _current_health = maxf(_current_health - amount, 0.0) # Applies damage while preventing health from becoming negative.
    var applied_damage: float = previous_health - _current_health # Calculates the amount that actually changed the health state.
    if applied_damage > 0.0: # Detects a real health mutation rather than a no-op request.
        _revision += 1 # Marks the state as changed for health bars and other presentation systems.
    return applied_damage # Returns the clamped damage amount consumed by this actor.

func restore_full_health() -> void: # Restores the actor to maximum health for respawns or reusable training targets.
    if is_equal_approx(_current_health, _maximum_health): # Detects an already-full actor that needs no state mutation.
        return # Avoids a false revision change when health is already complete.
    _current_health = _maximum_health # Restores the exact validated maximum health value.
    _revision += 1 # Marks the restored health state as changed for presentation refresh.

func get_current_health() -> float: # Returns the actor's current remaining health.
    return _current_health # Exposes current health without allowing external mutation.

func get_maximum_health() -> float: # Returns the actor's validated maximum health.
    return _maximum_health # Exposes maximum health without allowing external mutation.

func get_health_ratio() -> float: # Returns normalized health in the inclusive range from zero to one.
    return clampf(_current_health / _maximum_health, 0.0, 1.0) # Produces a safe value for health-bar scaling.

func is_dead() -> bool: # Reports whether the actor has no health remaining.
    return _current_health <= 0.0 # Treats exactly zero health as the dead state.

func get_revision() -> int: # Reports the monotonically increasing health revision for polling consumers.
    return _revision # Exposes state changes without introducing a signal dependency.
