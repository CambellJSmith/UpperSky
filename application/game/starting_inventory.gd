extends Node # Grants the active player the authored items they should hold at the beginning of a new game.
class_name StartingInventory # Makes the starter-inventory composition node available for typed scene references and diagnostics.

const MYSTERIOUS_LOCKET_ID: StringName = &"mysterious_locket" # Defines the stable identifier used for stacking, removal, and future item-specific behaviour.
const MYSTERIOUS_LOCKET_NAME: String = "Mysterious Locket" # Defines the exact player-facing item name shown in the inventory list.
const MYSTERIOUS_LOCKET_WEIGHT: float = 0.10 # Gives the small metal locket a restrained carried weight in kilograms.
const MYSTERIOUS_LOCKET_QUANTITY: int = 1 # Grants exactly one locket at the beginning of a new game.

@onready var _inventory: PlayerInventory = $"../DynamicEntities/Player/PlayerInventory" # Resolves the authoritative player-owned inventory from the game composition root.

func _ready() -> void: # Defers starter-item assignment until every player-owned inventory dependency has completed initialization.
    _grant_starting_items.call_deferred() # Ensures maximum stamina is available before the capacity-aware inventory addition runs.

func _grant_starting_items() -> void: # Adds every authored starting item through the ordinary capacity-enforcing inventory API.
    if _inventory == null: # Detects a malformed game composition without the expected player inventory node.
        push_error("Unable to grant starting inventory: PlayerInventory was not found.") # Reports the missing scene dependency without silently discarding the starter item.
        return # Stops before attempting an invalid inventory call.
    var locket_added: bool = _inventory.try_add_item(MYSTERIOUS_LOCKET_ID, MYSTERIOUS_LOCKET_NAME, MYSTERIOUS_LOCKET_WEIGHT, MYSTERIOUS_LOCKET_QUANTITY) # Adds the locket exactly as any future pickup or reward would.
    if not locket_added: # Detects invalid capacity or an unexpected conflicting item definition.
        push_error("Unable to grant starting item: Mysterious Locket.") # Makes failed starter-state initialization visible during development.
