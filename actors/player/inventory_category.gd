extends RefCounted # Defines the stable inventory categories shared by stored item stacks and inventory interfaces.
class_name InventoryCategory # Exposes category identifiers without coupling the inventory UI to concrete item implementations.

enum Type { WEAPONS_TOOLS, ARMOUR, POTIONS, BOOKS, INGREDIENTS, MISC } # Keeps category indices stable so tabs and stored stacks use the same ordering.

const DISPLAY_NAMES: PackedStringArray = ["Weapons/Tools", "Armour", "Potions", "Books", "Ingredients", "Misc"] # Stores the exact user-facing label for every category in enum order.

static func get_count() -> int: # Reports the number of supported inventory categories.
    return DISPLAY_NAMES.size() # Uses the display-name table as the single source of category count.

static func is_valid(category: int) -> bool: # Reports whether an integer is a supported inventory category.
    return category >= 0 and category < get_count() # Restricts category values to the stable enum-backed display table.

static func get_display_name(category: int) -> String: # Returns the user-facing label for one category.
    if not is_valid(category): # Detects malformed or future category values not understood by this build.
        return DISPLAY_NAMES[Type.MISC] # Falls back to Misc so interfaces always have a safe readable label.
    return DISPLAY_NAMES[category] # Returns the exact label matching the stable category index.
