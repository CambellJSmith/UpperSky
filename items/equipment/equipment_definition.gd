extends Resource
class_name EquipmentDefinition

enum Category {
    WEAPON,
    TOOL,
}

@export var item_id: StringName = &""
@export var display_name: String = ""
@export var category: Category = Category.TOOL
@export_range(0.0, 100.0, 0.01) var unit_weight: float = 0.0
@export var held_scene: PackedScene
@export_range(0.1, 20.0, 0.05) var reach: float = 2.5
@export_range(0.01, 10.0, 0.01) var primary_cooldown: float = 0.5
@export_range(0.0, 10000.0, 0.1) var damage: float = 0.0
@export_range(0.0, 1000.0, 0.1) var tool_power: float = 0.0
@export var tool_tags: PackedStringArray = PackedStringArray()

func is_valid() -> bool:
    return not String(item_id).is_empty() and held_scene != null
