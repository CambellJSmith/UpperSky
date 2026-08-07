extends Node
class_name PlayerEquipment

const PRIMARY_ACTION: StringName = &"EquipmentPrimary"
const SECONDARY_ACTION: StringName = &"EquipmentSecondary"
const NEXT_ACTION: StringName = &"EquipmentNext"
const PREVIOUS_ACTION: StringName = &"EquipmentPrevious"

@onready var _player: FirstPersonPlayer = get_parent() as FirstPersonPlayer
@onready var _inventory: PlayerInventory = $"../PlayerInventory"
@onready var _mount: Node3D = $"../Head/Camera3D/EquipmentMount"

var _equipped_definition: EquipmentDefinition
var _equipped_item: EquippedItem
var _observed_inventory_revision: int = -1
var _revision: int = 0

func _ready() -> void:
    _validate_equipped_item()

func get_revision() -> int:
    return _revision

func get_equipped_item_id() -> StringName:
    if _equipped_definition == null:
        return &""
    return _equipped_definition.item_id

func get_equipped_definition() -> EquipmentDefinition:
    return _equipped_definition

func equip_item(item_id: StringName) -> bool:
    if _inventory == null or not _owns_item(item_id):
        return false
    var definition: EquipmentDefinition = EquipmentCatalog.get_definition(item_id)
    if definition == null or not definition.is_valid():
        return false
    if _equipped_definition != null and _equipped_definition.item_id == item_id and _equipped_item != null:
        return true

    var instance: Node = definition.held_scene.instantiate()
    if not (instance is EquippedItem):
        push_error("Equipment scene for %s must inherit EquippedItem." % definition.display_name)
        instance.queue_free()
        return false

    unequip()
    _equipped_definition = definition
    _equipped_item = instance as EquippedItem
    _mount.add_child(_equipped_item)
    _equipped_item.initialize(definition, _player, _player.get_view_camera())
    _revision += 1
    return true

func unequip() -> void:
    if _equipped_item != null:
        _equipped_item.on_unequipped()
        _equipped_item.queue_free()
    if _equipped_item != null or _equipped_definition != null:
        _revision += 1
    _equipped_item = null
    _equipped_definition = null

func _process(_delta: float) -> void:
    if _inventory == null:
        return
    if _inventory.get_revision() != _observed_inventory_revision:
        _observed_inventory_revision = _inventory.get_revision()
        _validate_equipped_item()

func _unhandled_input(event: InputEvent) -> void:
    if not _can_use_equipment():
        return

    if event.is_action_pressed(PRIMARY_ACTION):
        if _equipped_item != null:
            _equipped_item.primary_use()
            get_viewport().set_input_as_handled()
        return

    if event.is_action_pressed(SECONDARY_ACTION):
        if _equipped_item != null:
            _equipped_item.secondary_use(true)
            get_viewport().set_input_as_handled()
        return

    if event.is_action_released(SECONDARY_ACTION):
        if _equipped_item != null:
            _equipped_item.secondary_use(false)
            get_viewport().set_input_as_handled()
        return

    if event.is_action_pressed(NEXT_ACTION):
        _cycle_equipment(1)
        get_viewport().set_input_as_handled()
        return

    if event.is_action_pressed(PREVIOUS_ACTION):
        _cycle_equipment(-1)
        get_viewport().set_input_as_handled()
        return

    if event is InputEventKey:
        var key_event := event as InputEventKey
        if key_event.pressed and not key_event.echo:
            var slot_index: int = _slot_index_from_key(key_event.physical_keycode)
            if slot_index >= 0:
                _equip_owned_slot(slot_index)
                get_viewport().set_input_as_handled()

func _can_use_equipment() -> bool:
    return _player != null and _inventory != null and _mount != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func _validate_equipped_item() -> void:
    if _equipped_definition == null:
        return
    if not _owns_item(_equipped_definition.item_id):
        unequip()

func _owns_item(item_id: StringName) -> bool:
    for stack_index: int in range(_inventory.get_stack_count()):
        var stack: InventoryStack = _inventory.get_stack_at(stack_index)
        if stack != null and stack.get_item_id() == item_id and stack.get_quantity() > 0:
            return true
    return false

func _get_owned_equippable_ids() -> Array[StringName]:
    var result: Array[StringName] = []
    for stack_index: int in range(_inventory.get_stack_count()):
        var stack: InventoryStack = _inventory.get_stack_at(stack_index)
        if stack == null or stack.get_quantity() <= 0:
            continue
        var item_id: StringName = stack.get_item_id()
        if EquipmentCatalog.is_equippable(item_id):
            result.append(item_id)
    return result

func _equip_owned_slot(slot_index: int) -> void:
    var owned_items: Array[StringName] = _get_owned_equippable_ids()
    if slot_index < 0 or slot_index >= owned_items.size():
        return
    equip_item(owned_items[slot_index])

func _cycle_equipment(direction: int) -> void:
    var owned_items: Array[StringName] = _get_owned_equippable_ids()
    if owned_items.is_empty():
        unequip()
        return
    if _equipped_definition == null:
        var initial_index: int = 0 if direction >= 0 else owned_items.size() - 1
        equip_item(owned_items[initial_index])
        return
    var current_index: int = owned_items.find(_equipped_definition.item_id)
    if current_index < 0:
        equip_item(owned_items[0])
        return
    var next_index: int = posmod(current_index + direction, owned_items.size())
    equip_item(owned_items[next_index])

func _slot_index_from_key(keycode: Key) -> int:
    match keycode:
        KEY_1:
            return 0
        KEY_2:
            return 1
        KEY_3:
            return 2
        KEY_4:
            return 3
        KEY_5:
            return 4
        KEY_6:
            return 5
        KEY_7:
            return 6
        KEY_8:
            return 7
        KEY_9:
            return 8
        _:
            return -1
