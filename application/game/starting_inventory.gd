extends Node # Grants the player a deterministic initial set of inventory items after game composition is ready.
class_name StartingInventory # Exposes starting-inventory composition as a dedicated game service.

const MYSTERIOUS_LOCKET_ID: StringName = &"mysterious_locket" # Stores the stable identifier for the starting miscellaneous item.
const MYSTERIOUS_LOCKET_NAME: String = "Mysterious Locket" # Stores the user-facing locket name shown in the inventory.
const MYSTERIOUS_LOCKET_WEIGHT: float = 0.10 # Stores the physical carrying weight of one locket.
const MYSTERIOUS_LOCKET_QUANTITY: int = 1 # Grants exactly one locket at game start.

@onready var _inventory: PlayerInventory = $"../DynamicEntities/Player/PlayerInventory" # Resolves the authoritative player inventory owned by the active game scene.

func _ready() -> void: # Defers starting-item grants until the composed player scene has completed its own initialization.
    _grant_starting_items.call_deferred() # Schedules deterministic inventory grants after the current ready pass.

func _grant_starting_items() -> void: # Adds every authored starting item to its correct inventory category.
    if _inventory == null: # Detects a broken game composition without the required player inventory.
        push_error("Unable to grant starting inventory: PlayerInventory was not found.") # Reports the missing dependency for development diagnostics.
        return # Stops before attempting item grants against a missing model.

    if not _inventory.try_add_item(MYSTERIOUS_LOCKET_ID, MYSTERIOUS_LOCKET_NAME, MYSTERIOUS_LOCKET_WEIGHT, MYSTERIOUS_LOCKET_QUANTITY, InventoryCategory.Type.MISC): # Adds the locket to the Misc tab using the shared category model.
        push_error("Unable to grant starting item: Mysterious Locket.") # Reports any capacity or definition failure during the locket grant.

    _grant_equipment(EquipmentCatalog.IRON_SWORD) # Adds the authored iron sword under Weapons/Tools.
    _grant_equipment(EquipmentCatalog.IRON_PICKAXE) # Adds the authored iron pickaxe under Weapons/Tools.

func _grant_equipment(definition: EquipmentDefinition) -> void: # Adds one valid equipment definition to the shared Weapons/Tools inventory category.
    if definition == null or not definition.is_valid(): # Rejects missing or malformed equipment definitions before touching inventory state.
        push_error("Unable to grant invalid starting equipment definition.") # Reports the invalid definition for development diagnostics.
        return # Stops without creating a malformed inventory stack.
    if not _inventory.try_add_item(definition.item_id, definition.display_name, definition.unit_weight, 1, InventoryCategory.Type.WEAPONS_TOOLS): # Adds all currently supported weapon and tool definitions to the combined equipment tab.
        push_error("Unable to grant starting equipment: %s." % definition.display_name) # Reports capacity or stacking failures for the authored equipment item.
