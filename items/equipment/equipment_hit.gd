extends RefCounted
class_name EquipmentHit

var source: FirstPersonPlayer
var item_id: StringName = &""
var category: EquipmentDefinition.Category = EquipmentDefinition.Category.TOOL
var damage: float = 0.0
var tool_power: float = 0.0
var tool_tags: PackedStringArray = PackedStringArray()
var position: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.UP

static func create(
    source_player: FirstPersonPlayer,
    definition: EquipmentDefinition,
    hit_position: Vector3,
    hit_normal: Vector3
) -> EquipmentHit:
    var hit := EquipmentHit.new()
    hit.source = source_player
    hit.item_id = definition.item_id
    hit.category = definition.category
    hit.damage = definition.damage
    hit.tool_power = definition.tool_power
    hit.tool_tags = definition.tool_tags.duplicate()
    hit.position = hit_position
    hit.normal = hit_normal
    return hit
