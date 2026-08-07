extends RefCounted
class_name EquipmentCatalog

const IRON_SWORD: EquipmentDefinition = preload("res://items/equipment/definitions/iron_sword.tres")
const IRON_PICKAXE: EquipmentDefinition = preload("res://items/equipment/definitions/iron_pickaxe.tres")
const DEFINITIONS: Array[EquipmentDefinition] = [IRON_SWORD, IRON_PICKAXE]

static func get_definition(item_id: StringName) -> EquipmentDefinition:
    for definition: EquipmentDefinition in DEFINITIONS:
        if definition != null and definition.item_id == item_id:
            return definition
    return null

static func is_equippable(item_id: StringName) -> bool:
    return get_definition(item_id) != null

static func get_all_definitions() -> Array[EquipmentDefinition]:
    return DEFINITIONS.duplicate()
