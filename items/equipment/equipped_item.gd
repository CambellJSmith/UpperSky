extends Node3D
class_name EquippedItem

var _definition: EquipmentDefinition
var _player: FirstPersonPlayer
var _camera: Camera3D
var _primary_cooldown_remaining: float = 0.0

func initialize(definition: EquipmentDefinition, player: FirstPersonPlayer, camera: Camera3D) -> void:
    _definition = definition
    _player = player
    _camera = camera
    on_equipped()

func get_definition() -> EquipmentDefinition:
    return _definition

func on_equipped() -> void:
    pass

func on_unequipped() -> void:
    pass

func primary_use() -> bool:
    if _definition == null or _primary_cooldown_remaining > 0.0:
        return false
    if not _perform_primary_use():
        return false
    _primary_cooldown_remaining = maxf(_definition.primary_cooldown, 0.0)
    return true

func secondary_use(pressed: bool) -> bool:
    return _perform_secondary_use(pressed)

func _perform_primary_use() -> bool:
    return false

func _perform_secondary_use(_pressed: bool) -> bool:
    return false

func _process(delta: float) -> void:
    if _primary_cooldown_remaining > 0.0:
        _primary_cooldown_remaining = maxf(_primary_cooldown_remaining - delta, 0.0)
