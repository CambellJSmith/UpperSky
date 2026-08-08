extends RefCounted # Stores one immutable item definition with a mutable held quantity for the player inventory.
class_name InventoryStack # Makes typed inventory entries available to the inventory model and interface.

var _item_id: StringName # Stores the stable identifier used to combine matching item stacks.
var _display_name: String # Stores the human-readable item name shown in the inventory list.
var _unit_weight: float # Stores the weight contributed by one item in this stack.
var _quantity: int # Stores the number of currently held items in this stack.
var _category: int # Stores the stable inventory category used by tab filtering.

func _init(item_id: StringName, display_name: String, unit_weight: float, quantity: int, category: int) -> void: # Creates one validated stack from an item definition, quantity, and inventory category.
    _item_id = item_id # Retains the stable item identifier.
    _display_name = display_name # Retains the user-facing item name.
    _unit_weight = maxf(unit_weight, 0.0) # Prevents negative item weights from reducing carried mass.
    _quantity = maxi(quantity, 0) # Prevents a newly created stack from starting with a negative quantity.
    _category = category if InventoryCategory.is_valid(category) else InventoryCategory.Type.MISC # Normalizes malformed category values into the safe Misc fallback.

func get_item_id() -> StringName: # Returns the stable identifier for stack matching.
    return _item_id # Exposes the item identifier without allowing mutation.

func get_display_name() -> String: # Returns the item name shown by inventory interfaces.
    return _display_name # Exposes the user-facing name without allowing mutation.

func get_unit_weight() -> float: # Returns the weight of one item in this stack.
    return _unit_weight # Exposes the validated per-item weight.

func get_quantity() -> int: # Returns the number of held items in this stack.
    return _quantity # Exposes the current stack count.

func get_category() -> int: # Returns the stable inventory category assigned when this stack was created.
    return _category # Exposes category data read-only so interfaces can filter without mutating item identity.

func get_stack_weight() -> float: # Calculates the complete weight contributed by this stack.
    return _unit_weight * float(_quantity) # Multiplies unit weight by held quantity.

func increase_quantity(amount: int) -> void: # Adds a positive quantity after the inventory has approved capacity.
    _quantity += maxi(amount, 0) # Prevents accidental negative additions from reducing the stack.

func remove_quantity(amount: int) -> int: # Removes up to the requested number of items and reports the actual amount removed.
    var removed_quantity: int = mini(maxi(amount, 0), _quantity) # Restricts removal to a valid positive amount no larger than the stack.
    _quantity -= removed_quantity # Applies the validated removal.
    return removed_quantity # Reports the quantity actually removed to the inventory model.
