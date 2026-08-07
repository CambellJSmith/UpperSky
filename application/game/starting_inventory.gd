extends Node
class_name StartingInventory

const MYSTERIOUS_LOCKET_ID: StringName = &"mysterious_locket"
const MYSTERIOUS_LOCKET_NAME: String = "Mysterious Locket"
const MYSTERIOUS_LOCKET_WEIGHT: float = 0.10
const MYSTERIOUS_LOCKET_QUANTITY: int = 1

@onready var _inventory: PlayerInventory = $"../DynamicEntities/Player/PlayerInventory"

func _ready() -> void:
    _grant_starting_items.call_deferred()

func _grant_starting_items() -> void:
    if _inventory == null:
        push_error("Unable to grant starting inventory: PlayerInventory was not found.")
        return

    if not _inventory.try_add_item(MYSTERIOUS_LOCKET_ID, MYSTERIOUS_LOCKET_NAME, MYSTERIOUS_LOCKET_WEIGHT, MYSTERIOUS_LOCKET_QUANTITY):
        push_error("Unable to grant starting item: Mysterious Locket.")

    _grant_equipment(EquipmentCatalog.IRON_SWORD)
    _grant_equipment(EquipmentCatalog.IRON_PICKAXE)

func _grant_equipment(definition: EquipmentDefinition) -> void:
    if definition == null or not definition.is_valid():
        push_error("Unable to grant invalid starting equipment definition.")
        return
    if not _inventory.try_add_item(definition.item_id, definition.display_name, definition.unit_weight, 1):
        push_error("Unable to grant starting equipment: %s." % definition.display_name)
