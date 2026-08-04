extends Node # Owns the player's held item stacks and enforces a stamina-derived carrying capacity.
class_name PlayerInventory # Makes the inventory available to gameplay systems and the inventory interface through strong typing.

const WEIGHT_EPSILON: float = 0.0001 # Avoids rejecting additions because of insignificant floating-point rounding differences.

var _vitals: PlayerVitals # Supplies the current maximum stamina copied directly as the live maximum carried weight.
var _stacks: Array[InventoryStack] = [] # Stores held item stacks in stable insertion order for display and future save data.
var _revision: int = 0 # Increments whenever held contents change so the open interface can refresh without signals.

func _ready() -> void: # Resolves the player-owned vitals sibling authored beside this inventory node.
    var vitals_node: Node = get_node_or_null("../PlayerVitals") # Finds the authoritative resource model inside the same player scene.
    if vitals_node is PlayerVitals: # Verifies the scene dependency has the expected strong type.
        initialize(vitals_node as PlayerVitals) # Connects carrying capacity to current maximum stamina immediately.

func initialize(vitals: PlayerVitals) -> void: # Connects the inventory to the authoritative player resource model.
    _vitals = vitals # Stores the source whose current maximum stamina defines carrying capacity.

func get_maximum_weight() -> float: # Returns the live carrying limit copied from current maximum stamina.
    if _vitals == null: # Handles inventory access before game composition has connected player vitals.
        return 0.0 # Rejects weighted additions until a valid capacity source exists.
    return maxf(_vitals.get_maximum_stamina(), 0.0) # Copies the authoritative current stamina maximum without a duplicated inventory constant.

func get_total_weight() -> float: # Calculates the complete weight of all currently held items.
    var total_weight: float = 0.0 # Starts the accumulation with an empty inventory.
    for stack: InventoryStack in _stacks: # Visits every held item stack.
        total_weight += stack.get_stack_weight() # Adds quantity multiplied by unit weight for the current stack.
    return total_weight # Returns the complete carried weight.

func get_total_item_count() -> int: # Counts every individual held item across all stacks.
    var total_count: int = 0 # Starts the accumulation with no items.
    for stack: InventoryStack in _stacks: # Visits every held stack.
        total_count += stack.get_quantity() # Adds the quantity represented by the current stack.
    return total_count # Returns the complete number of held item units.

func get_stack_count() -> int: # Reports how many distinct item stacks are currently held.
    return _stacks.size() # Returns the number of visible inventory rows.

func get_stack_at(index: int) -> InventoryStack: # Returns one held stack for read-only interface presentation.
    if index < 0 or index >= _stacks.size(): # Rejects invalid row indices defensively.
        return null # Reports that no stack exists at the requested index.
    return _stacks[index] # Returns the stable stack object at the requested position.

func get_revision() -> int: # Reports whether held contents changed since a caller last refreshed.
    return _revision # Returns the monotonically increasing inventory revision.

func can_add_item(unit_weight: float, quantity: int = 1) -> bool: # Reports whether a weighted quantity fits inside the live stamina-derived limit.
    if unit_weight < 0.0 or quantity <= 0: # Rejects invalid item definitions or quantities.
        return false # Prevents malformed additions from entering capacity calculations.
    var added_weight: float = unit_weight * float(quantity) # Calculates the mass contributed by the requested addition.
    return get_total_weight() + added_weight <= get_maximum_weight() + WEIGHT_EPSILON # Allows the addition only when total carried weight remains within capacity.

func try_add_item(item_id: StringName, display_name: String, unit_weight: float, quantity: int = 1) -> bool: # Adds an item stack only when its full weight fits inside current capacity.
    var item_id_text: String = String(item_id) # Converts the stable identifier for validation and fallback display text.
    if item_id_text.is_empty() or unit_weight < 0.0 or quantity <= 0: # Rejects missing identifiers, negative weight, or non-positive quantities.
        return false # Leaves inventory contents unchanged for invalid additions.
    if not can_add_item(unit_weight, quantity): # Checks the live maximum stamina before changing any stack.
        return false # Enforces the current carrying limit atomically.
    var resolved_display_name: String = display_name.strip_edges() # Removes accidental whitespace from the user-facing item name.
    if resolved_display_name.is_empty(): # Handles definitions without an explicit display name.
        resolved_display_name = item_id_text # Falls back to the stable identifier so every held item remains visible.
    var existing_stack: InventoryStack = _find_stack(item_id) # Searches for an existing stack with the same stable item identifier.
    if existing_stack != null: # Detects an item that should combine with an existing row.
        if not is_equal_approx(existing_stack.get_unit_weight(), unit_weight): # Detects conflicting weight definitions for one identifier.
            return false # Prevents an existing stack from silently changing its physical weight.
        existing_stack.increase_quantity(quantity) # Adds the approved quantity to the matching stack.
    else: # Handles the first held instance of this item definition.
        _stacks.append(InventoryStack.new(item_id, resolved_display_name, unit_weight, quantity)) # Creates a new visible stack in insertion order.
    _revision += 1 # Marks inventory contents as changed for the open interface.
    return true # Reports that the complete requested quantity was accepted.

func remove_item(item_id: StringName, quantity: int = 1) -> int: # Removes up to the requested quantity and returns the actual amount removed.
    if quantity <= 0: # Rejects non-positive removal requests.
        return 0 # Leaves inventory contents unchanged.
    var stack_index: int = _find_stack_index(item_id) # Locates the matching held stack.
    if stack_index < 0: # Detects an item the player does not currently hold.
        return 0 # Reports that nothing could be removed.
    var stack: InventoryStack = _stacks[stack_index] # Retrieves the matching stack for mutation.
    var removed_quantity: int = stack.remove_quantity(quantity) # Removes only the amount currently available.
    if removed_quantity <= 0: # Handles a defensive empty-stack result.
        return 0 # Leaves the revision unchanged when no content changed.
    if stack.get_quantity() == 0: # Detects a stack emptied by the removal.
        _stacks.remove_at(stack_index) # Removes empty rows from storage and the visible list.
    _revision += 1 # Marks inventory contents as changed for interface refresh.
    return removed_quantity # Reports the quantity actually removed.

func clear() -> void: # Removes every currently held item stack.
    if _stacks.is_empty(): # Detects an already empty inventory.
        return # Avoids a false revision change.
    _stacks.clear() # Discards every held stack.
    _revision += 1 # Marks inventory contents as changed.

func _find_stack(item_id: StringName) -> InventoryStack: # Finds one held stack by stable item identifier.
    var stack_index: int = _find_stack_index(item_id) # Reuses the indexed lookup implementation.
    if stack_index < 0: # Detects that no matching stack exists.
        return null # Reports an unavailable stack.
    return _stacks[stack_index] # Returns the matching stack.

func _find_stack_index(item_id: StringName) -> int: # Finds the array position of one held stack.
    for stack_index: int in range(_stacks.size()): # Visits every stored stack index in stable order.
        if _stacks[stack_index].get_item_id() == item_id: # Compares the stable identifier for the current row.
            return stack_index # Returns immediately when the requested item is found.
    return -1 # Reports that no matching held stack exists.
