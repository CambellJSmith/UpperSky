extends RefCounted
class_name EquipmentCatalog

const IRON_SWORD: EquipmentDefinition = preload("res://items/equipment/definitions/iron_sword.tres")
const IRON_PICKAXE: EquipmentDefinition = preload("res://items/equipment/definitions/iron_pickaxe.tres")
const BRONZE_LONGSWORD: EquipmentDefinition = preload("res://items/equipment/definitions/bronze_longsword.tres")
const DUELIST_RAPIER: EquipmentDefinition = preload("res://items/equipment/definitions/duelist_rapier.tres")
const DESERT_SABRE: EquipmentDefinition = preload("res://items/equipment/definitions/desert_sabre.tres")
const CLEAVER_FALCHION: EquipmentDefinition = preload("res://items/equipment/definitions/cleaver_falchion.tres")
const HIGHLAND_GREATSWORD: EquipmentDefinition = preload("res://items/equipment/definitions/highland_greatsword.tres")
const WOODSMAN_AXE: EquipmentDefinition = preload("res://items/equipment/definitions/woodsman_axe.tres")
const DOUBLE_BATTLEAXE: EquipmentDefinition = preload("res://items/equipment/definitions/double_battleaxe.tres")
const CRESCENT_AXE: EquipmentDefinition = preload("res://items/equipment/definitions/crescent_axe.tres")
const BEARDED_RAIDER_AXE: EquipmentDefinition = preload("res://items/equipment/definitions/bearded_raider_axe.tres")
const OBSIDIAN_HATCHET: EquipmentDefinition = preload("res://items/equipment/definitions/obsidian_hatchet.tres")
const CROSSGUARD_DAGGER: EquipmentDefinition = preload("res://items/equipment/definitions/crossguard_dagger.tres")
const CURVED_KUKRI: EquipmentDefinition = preload("res://items/equipment/definitions/curved_kukri.tres")
const BLACK_TANTO: EquipmentDefinition = preload("res://items/equipment/definitions/black_tanto.tres")
const BONE_SEAX: EquipmentDefinition = preload("res://items/equipment/definitions/bone_seax.tres")
const HUNTERS_KNIFE: EquipmentDefinition = preload("res://items/equipment/definitions/hunters_knife.tres")

const DEFINITIONS: Array[EquipmentDefinition] = [
    IRON_SWORD, IRON_PICKAXE,
    BRONZE_LONGSWORD,
    DUELIST_RAPIER,
    DESERT_SABRE,
    CLEAVER_FALCHION,
    HIGHLAND_GREATSWORD,
    WOODSMAN_AXE,
    DOUBLE_BATTLEAXE,
    CRESCENT_AXE,
    BEARDED_RAIDER_AXE,
    OBSIDIAN_HATCHET,
    CROSSGUARD_DAGGER,
    CURVED_KUKRI,
    BLACK_TANTO,
    BONE_SEAX,
    HUNTERS_KNIFE,
]

static func get_definition(item_id: StringName) -> EquipmentDefinition:
    for definition: EquipmentDefinition in DEFINITIONS:
        if definition != null and definition.item_id == item_id:
            return definition
    return null

static func is_equippable(item_id: StringName) -> bool:
    return get_definition(item_id) != null

static func get_all_definitions() -> Array[EquipmentDefinition]:
    return DEFINITIONS.duplicate()
