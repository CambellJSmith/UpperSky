extends Node # Owns authoritative player health, stamina, and mana values independently from their interface presentation.
class_name PlayerVitals # Makes the player resource model available to HUD, inventory, and future gameplay systems.

const MINIMUM_MAXIMUM_VALUE: float = 0.001 # Prevents invalid zero-range resources when a maximum is changed dynamically.
const DEFAULT_MAXIMUM_HEALTH: float = 100.0 # Defines the initial maximum health displayed by the existing red status bar.
const DEFAULT_MAXIMUM_STAMINA: float = 100.0 # Defines the initial maximum stamina and therefore the initial inventory weight capacity.
const DEFAULT_MAXIMUM_MANA: float = 100.0 # Defines the initial maximum mana displayed by the existing blue status bar.

var _health: float = DEFAULT_MAXIMUM_HEALTH # Stores the player's current health.
var _maximum_health: float = DEFAULT_MAXIMUM_HEALTH # Stores the authoritative current maximum health.
var _stamina: float = DEFAULT_MAXIMUM_STAMINA # Stores the player's current stamina.
var _maximum_stamina: float = DEFAULT_MAXIMUM_STAMINA # Stores the authoritative current maximum stamina copied by inventory capacity.
var _mana: float = DEFAULT_MAXIMUM_MANA # Stores the player's current mana.
var _maximum_mana: float = DEFAULT_MAXIMUM_MANA # Stores the authoritative current maximum mana.
var _revision: int = 0 # Increments whenever any displayed resource changes so polling interfaces can refresh without signals.

func get_health() -> float: # Returns the current health value.
    return _health # Exposes the authoritative current health without mutable node access.

func get_maximum_health() -> float: # Returns the current maximum health value.
    return _maximum_health # Exposes the authoritative health range.

func get_stamina() -> float: # Returns the current stamina value.
    return _stamina # Exposes the authoritative current stamina.

func get_maximum_stamina() -> float: # Returns the current maximum stamina value used as inventory capacity.
    return _maximum_stamina # Supplies one shared stamina maximum to both status and inventory interfaces.

func get_mana() -> float: # Returns the current mana value.
    return _mana # Exposes the authoritative current mana.

func get_maximum_mana() -> float: # Returns the current maximum mana value.
    return _maximum_mana # Exposes the authoritative mana range.

func get_revision() -> int: # Reports whether any resource has changed since a caller last refreshed.
    return _revision # Returns the monotonically increasing resource revision.

func set_health(value: float) -> void: # Changes current health while respecting its current maximum.
    var next_value: float = clampf(value, 0.0, _maximum_health) # Restricts health to its valid range.
    if is_equal_approx(next_value, _health): # Detects a no-op assignment.
        return # Avoids unnecessary interface refreshes.
    _health = next_value # Stores the validated health value.
    _revision += 1 # Marks the resource model as changed.

func set_maximum_health(value: float) -> void: # Changes maximum health and clamps current health into the new range.
    var next_maximum: float = maxf(value, MINIMUM_MAXIMUM_VALUE) # Guarantees a valid positive maximum.
    if is_equal_approx(next_maximum, _maximum_health): # Detects a no-op maximum assignment.
        return # Leaves the revision unchanged when nothing changed.
    _maximum_health = next_maximum # Stores the validated maximum health.
    _health = minf(_health, _maximum_health) # Prevents current health from exceeding the new maximum.
    _revision += 1 # Marks both the range and potentially current health as changed.

func set_stamina(value: float) -> void: # Changes current stamina while respecting its current maximum.
    var next_value: float = clampf(value, 0.0, _maximum_stamina) # Restricts stamina to its valid range.
    if is_equal_approx(next_value, _stamina): # Detects a no-op assignment.
        return # Avoids unnecessary interface refreshes.
    _stamina = next_value # Stores the validated stamina value.
    _revision += 1 # Marks the resource model as changed.

func set_maximum_stamina(value: float) -> void: # Changes maximum stamina and therefore the inventory's live weight limit.
    var next_maximum: float = maxf(value, MINIMUM_MAXIMUM_VALUE) # Guarantees a valid positive maximum.
    if is_equal_approx(next_maximum, _maximum_stamina): # Detects a no-op maximum assignment.
        return # Leaves the revision unchanged when nothing changed.
    _maximum_stamina = next_maximum # Stores the authoritative capacity-defining stamina maximum.
    _stamina = minf(_stamina, _maximum_stamina) # Prevents current stamina from exceeding the new maximum.
    _revision += 1 # Marks both the HUD and inventory capacity as changed.

func set_mana(value: float) -> void: # Changes current mana while respecting its current maximum.
    var next_value: float = clampf(value, 0.0, _maximum_mana) # Restricts mana to its valid range.
    if is_equal_approx(next_value, _mana): # Detects a no-op assignment.
        return # Avoids unnecessary interface refreshes.
    _mana = next_value # Stores the validated mana value.
    _revision += 1 # Marks the resource model as changed.

func set_maximum_mana(value: float) -> void: # Changes maximum mana and clamps current mana into the new range.
    var next_maximum: float = maxf(value, MINIMUM_MAXIMUM_VALUE) # Guarantees a valid positive maximum.
    if is_equal_approx(next_maximum, _maximum_mana): # Detects a no-op maximum assignment.
        return # Leaves the revision unchanged when nothing changed.
    _maximum_mana = next_maximum # Stores the validated maximum mana.
    _mana = minf(_mana, _maximum_mana) # Prevents current mana from exceeding the new maximum.
    _revision += 1 # Marks both the range and potentially current mana as changed.
