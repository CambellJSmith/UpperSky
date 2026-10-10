extends RefCounted # Resolve encounter goods through the game's existing item metadata.
class_name RadiantItemCatalogue # Keep item weights and categories consistent with inventory and equipment.

static func item(id: StringName) -> InventoryStack: # Resolve known existing goods without inventing unusable equipment.
    match id: # Reuse existing ordinary inventory item definitions.
        &"bread": # Describe the food already stocked by NPCs.
            return InventoryStack.new(id, "Bread", 0.25, 1, InventoryCategory.Type.INGREDIENTS) # Preserve the existing food weight and category.
        &"linen": # Describe the cloth already stocked by NPCs.
            return InventoryStack.new(id, "Linen Cloth", 0.15, 1, InventoryCategory.Type.MISC) # Preserve existing cloth metadata.
        &"coins": # Describe the existing inventory currency.
            return InventoryStack.new(id, "Coins", 0.01, 1, InventoryCategory.Type.MISC) # Preserve the existing coin weight and classification.
    var equipment: EquipmentDefinition = EquipmentCatalog.get_definition(id) # Resolve tools and weapons from their authoritative definitions.
    if equipment == null: # Reject unknown or unimplemented equipment.
        return null # Keep unsupported goods out of offers.
    return InventoryStack.new(id, equipment.display_name, equipment.unit_weight, 1, InventoryCategory.Type.WEAPONS_TOOLS) # Match how existing loot stores usable equipment.

static func quantity_label(item_stack: InventoryStack, quantity: int) -> String: # Show exact transaction quantities in both invitations and buttons.
    return "%d Coins" % quantity if item_stack.get_item_id() == &"coins" else "%d × %s" % [quantity, item_stack.get_display_name()] # Distinguish prices from item bundles clearly.
