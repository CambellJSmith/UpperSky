# Equipment framework

Equipment is split into inventory ownership, data definitions, held runtime behaviour, and world hit receivers.

## Add a new melee weapon or tool

1. Create a held scene under `items/equipment/scenes/` whose root inherits `MeleeEquipment`.
2. Create an `EquipmentDefinition` resource under `items/equipment/definitions/` with the inventory ID, weight, scene, reach, cooldown, damage, tool power, and tool tags.
3. Add that definition to `EquipmentCatalog.DEFINITIONS`.
4. Add the same item ID/name/weight to pickups, loot, crafting, or starting inventory through `PlayerInventory.try_add_item()`.

The player can only equip definitions for item IDs they currently own.

## Controls

- `1`–`9`: equip owned equippable items in inventory order.
- Left mouse / right trigger: primary use.
- Right mouse / left trigger: secondary use.
- Controller D-pad left/right: previous/next equipment.
- Inventory: double-click or activate an equippable row to equip or unequip it.

## Make a world object react to equipment

Add this method to the collider itself or one of its first four parents:

```gdscript
func receive_equipment_hit(hit: EquipmentHit) -> void:
    # Weapons can use hit.damage.
    # Tools can check hit.tool_power and hit.tool_tags.
    # hit.position and hit.normal identify the exact contact point.
    pass
```

## Add a different equipment type

For firearms, bows, build tools, scanners, consumables, or other custom behaviour, inherit `EquippedItem` directly and override `_perform_primary_use()` and/or `_perform_secondary_use(pressed)`. The player equipment manager does not need to change.
