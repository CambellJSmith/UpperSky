extends Node # Owns authoritative player health, stamina, and mana values independently from their interface presentation.
class_name PlayerVitals # Makes the player resource model available to HUD, inventory, combat, developer controls, and future gameplay systems.

const MINIMUM_MAXIMUM_VALUE: float = 0.001 # Prevents invalid zero-range resources when a maximum is changed dynamically.
const DEFAULT_MAXIMUM_HEALTH: float = HealthState.DEFAULT_MAXIMUM # Defines the initial maximum health displayed by the existing red status bar.
const DEFAULT_MAXIMUM_STAMINA: float = 100.0 # Defines the initial maximum stamina and therefore the initial inventory weight capacity.
const DEFAULT_MAXIMUM_MANA: float = 100.0 # Defines the initial maximum mana displayed by the existing blue status bar.

var _stamina: float = DEFAULT_MAXIMUM_STAMINA # Stores the player's current stamina.
var _maximum_stamina: float = DEFAULT_MAXIMUM_STAMINA # Stores the authoritative current maximum stamina copied by inventory capacity.
var _mana: float = DEFAULT_MAXIMUM_MANA # Stores the player's current mana.
var _maximum_mana: float = DEFAULT_MAXIMUM_MANA # Stores the authoritative current maximum mana.
var _infinite_stamina_enabled: bool = false # Tracks whether developer controls currently prevent stamina from being consumed.
var _infinite_mana_enabled: bool = false # Tracks whether developer controls currently prevent mana from dropping below maximum.
var _revision: int = 0 # Increments whenever any displayed resource changes so polling interfaces can refresh without signals.
var _health_regen_delay: float = 0.0
var _last_health: float = HealthState.DEFAULT_MAXIMUM
const HEALTH_REGEN_DELAY := 3.0
const HEALTH_REGEN_RATE := 2.0

var _health_state: HealthState = HealthState.new()
func _init(): _health_state.changed.connect(func(): _revision += 1)
func _process(delta: float) -> void:
    var current_health := get_health()
    if current_health < _last_health:
        _health_regen_delay = HEALTH_REGEN_DELAY
    _last_health = current_health
    if _health_regen_delay > 0.0:
        _health_regen_delay -= delta
    elif not is_dead() and get_health() < get_maximum_health():
        heal(HEALTH_REGEN_RATE * delta)
func get_health_state() -> HealthState: return _health_state
func heal(amount: float) -> float: return _health_state.heal(amount)
func is_dead() -> bool: return _health_state.is_dead()
func get_health_ratio() -> float: return _health_state.get_health_ratio()

func get_health() -> float: # Returns the current health value.
    return _health_state.get_health()

func get_maximum_health() -> float: # Returns the current maximum health value.
    return _health_state.get_maximum_health()

func get_stamina() -> float: # Returns the current stamina value.
    return _stamina # Exposes the authoritative current stamina.

func get_maximum_stamina() -> float: # Returns the current maximum stamina value used as inventory capacity.
    return _maximum_stamina # Supplies one shared stamina maximum to both status and inventory interfaces.

func has_stamina() -> bool: # Reports whether exertion systems may still spend stamina.
    return _infinite_stamina_enabled or _stamina > 0.0 # Treats infinite stamina as permanently available while preserving ordinary empty-pool behavior otherwise.

func get_mana() -> float: # Returns the current mana value.
    return _mana # Exposes the authoritative current mana.

func get_maximum_mana() -> float: # Returns the current maximum mana value.
    return _maximum_mana # Exposes the authoritative mana range.

func get_revision() -> int: # Reports whether any resource has changed since a caller last refreshed.
    return _revision # Returns the monotonically increasing resource revision.

func is_infinite_health_enabled() -> bool: # Reports whether the developer infinite-health mode is active.
    return _health_state.is_infinite_health_enabled()

func is_infinite_stamina_enabled() -> bool: # Reports whether the developer infinite-stamina mode is active.
    return _infinite_stamina_enabled # Exposes the current stamina-cheat state without allowing direct mutation.

func is_infinite_mana_enabled() -> bool: # Reports whether the developer infinite-mana mode is active.
    return _infinite_mana_enabled # Exposes the current mana-cheat state without allowing direct mutation.

func set_infinite_health_enabled(enabled: bool) -> void: # Enables or disables authoritative prevention of player health loss.
    _health_state.set_infinite_health_enabled(enabled)

func set_infinite_stamina_enabled(enabled: bool) -> void: # Enables or disables authoritative prevention of player stamina consumption.
    if enabled == _infinite_stamina_enabled: # Detects a developer request that would not change cheat state.
        return # Avoids redundant resource work for an unchanged mode.
    _infinite_stamina_enabled = enabled # Stores the requested stamina-cheat state before normalizing the current value.
    if _infinite_stamina_enabled: # Detects activation that must immediately restore the protected resource.
        _set_stamina_internal(_maximum_stamina) # Restores stamina to maximum through the shared revision-tracked mutation path.

func set_infinite_mana_enabled(enabled: bool) -> void: # Enables or disables authoritative prevention of player mana loss.
    if enabled == _infinite_mana_enabled: # Detects a developer request that would not change cheat state.
        return # Avoids redundant resource work for an unchanged mode.
    _infinite_mana_enabled = enabled # Stores the requested mana-cheat state before normalizing the current value.
    if _infinite_mana_enabled: # Detects activation that must immediately restore the protected resource.
        _set_mana_internal(_maximum_mana) # Restores mana to maximum through the shared revision-tracked mutation path.

func apply_damage(amount: float) -> float: # Removes positive health through the existing clamped revision-tracked player resource model and reports actual damage applied.
    var applied := _health_state.apply_damage(amount)
    if applied > 0.0: _health_regen_delay = HEALTH_REGEN_DELAY
    return applied

func set_health(value: float) -> void: # Changes current health while respecting its current maximum and developer protection state.
    _health_state.set_health(value)

func set_maximum_health(value: float) -> void: # Changes maximum health and clamps current health into the new range.
    _health_state.set_maximum_health(value)

func set_stamina(value: float) -> void: # Changes current stamina while respecting its current maximum and developer protection state.
    var requested_value: float = _maximum_stamina if _infinite_stamina_enabled else value # Forces maximum stamina while developer infinite-stamina protection is active.
    _set_stamina_internal(requested_value) # Applies the normalized request through the shared clamped revision-tracked mutation path.

func consume_stamina(amount: float) -> float: # Spends up to the requested stamina and reports the amount gameplay may treat as successfully consumed.
    var requested_amount: float = maxf(amount, 0.0) # Rejects negative consumption without turning it into recovery.
    if is_zero_approx(requested_amount): # Detects a no-op resource request before ordinary or protected handling.
        return 0.0 # Reports that no stamina operation was required.
    if _infinite_stamina_enabled: # Detects developer stamina protection before exertion can alter the resource pool.
        return requested_amount # Reports the spend as satisfied so sprint, climb, swim, and jump logic continues while stored stamina remains full.
    if is_zero_approx(_stamina): # Detects an ordinary stamina pool that is already empty.
        return 0.0 # Reports that no stamina could be consumed.
    var previous_stamina: float = _stamina # Retains the prior value so partial final-frame spending can be reported accurately.
    set_stamina(_stamina - requested_amount) # Uses the ordinary clamped setter so HUD revision tracking remains authoritative.
    return previous_stamina - _stamina # Returns the exact amount removed, including a partial final spend at exhaustion.

func restore_stamina(amount: float) -> float: # Restores up to the requested stamina and reports the amount actually recovered.
    var requested_amount: float = maxf(amount, 0.0) # Rejects negative recovery without turning it into consumption.
    if is_zero_approx(requested_amount) or is_equal_approx(_stamina, _maximum_stamina): # Detects a no-op request or a full stamina pool.
        return 0.0 # Reports that no stamina needed to be restored.
    var previous_stamina: float = _stamina # Retains the prior value so capped recovery can be reported accurately.
    set_stamina(_stamina + requested_amount) # Uses the ordinary clamped setter so HUD revision tracking remains authoritative.
    return _stamina - previous_stamina # Returns the exact amount restored before the maximum cap.

func set_maximum_stamina(value: float) -> void: # Changes maximum stamina and therefore the inventory's live weight limit.
    var next_maximum: float = maxf(value, MINIMUM_MAXIMUM_VALUE) # Guarantees a valid positive maximum.
    if is_equal_approx(next_maximum, _maximum_stamina): # Detects a no-op maximum assignment.
        return # Leaves the revision unchanged when nothing changed.
    _maximum_stamina = next_maximum # Stores the authoritative capacity-defining stamina maximum.
    _stamina = _maximum_stamina if _infinite_stamina_enabled else minf(_stamina, _maximum_stamina) # Keeps protected stamina full while ordinary stamina only clamps to the new capacity.
    _revision += 1 # Marks both the HUD and inventory capacity as changed.

func set_mana(value: float) -> void: # Changes current mana while respecting its current maximum and developer protection state.
    var requested_value: float = _maximum_mana if _infinite_mana_enabled else value # Forces maximum mana while developer infinite-mana protection is active.
    _set_mana_internal(requested_value) # Applies the normalized request through the shared clamped revision-tracked mutation path.

func set_maximum_mana(value: float) -> void: # Changes maximum mana and clamps current mana into the new range.
    var next_maximum: float = maxf(value, MINIMUM_MAXIMUM_VALUE) # Guarantees a valid positive maximum.
    if is_equal_approx(next_maximum, _maximum_mana): # Detects a no-op maximum assignment.
        return # Leaves the revision unchanged when nothing changed.
    _maximum_mana = next_maximum # Stores the validated maximum mana.
    _mana = _maximum_mana if _infinite_mana_enabled else minf(_mana, _maximum_mana) # Keeps protected mana full while ordinary mana only clamps to the new maximum.
    _revision += 1 # Marks both the range and potentially current mana as changed.

func _set_health_internal(value: float) -> void: # Applies one health mutation without re-evaluating developer cheat policy.
    _health_state.set_health(value)

func _set_stamina_internal(value: float) -> void: # Applies one stamina mutation without re-evaluating developer cheat policy.
    var next_value: float = clampf(value, 0.0, _maximum_stamina) # Restricts stamina to its valid range.
    if is_equal_approx(next_value, _stamina): # Detects a no-op assignment.
        return # Avoids unnecessary interface refreshes.
    _stamina = next_value # Stores the validated stamina value.
    _revision += 1 # Marks the resource model as changed.

func _set_mana_internal(value: float) -> void: # Applies one mana mutation without re-evaluating developer cheat policy.
    var next_value: float = clampf(value, 0.0, _maximum_mana) # Restricts mana to its valid range.
    if is_equal_approx(next_value, _mana): # Detects a no-op assignment.
        return # Avoids unnecessary interface refreshes.
    _mana = next_value # Stores the validated mana value.
    _revision += 1 # Marks the resource model as changed.
