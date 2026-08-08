# Equipment framework

Equipment is split into inventory ownership, data definitions, held runtime behaviour, and world hit receivers.

## Held-item visual rule

Every item that can be visibly held or equipped by the player must use PNG artwork for its player-facing visual. This includes weapons, tools, armour, consumables, quest items, and future equipment categories.

Held scenes may use `Node3D` for positioning and animation, but the visible authored item must be a `Sprite3D` backed by a `.png` texture. Do not build held items from `MeshInstance3D`, primitive meshes, imported 3D models, GLB/GLTF assets, or other model geometry.

The current iron sword and iron pickaxe follow this rule. Their PNG files live under `items/equipment/images/`, while their `Node3D` scene roots remain responsible only for first-person placement and swing animation.

## Add a new melee weapon or tool

1. Add the held-item PNG under `items/equipment/images/`.
2. Create a held scene under `items/equipment/scenes/` whose root inherits `MeleeEquipment`.
3. Add a `Sprite3D` child to that scene and assign the PNG texture. Keep the scene free of held-item model geometry.
4. Create an `EquipmentDefinition` resource under `items/equipment/definitions/` with the inventory ID, weight, scene, reach, cooldown, damage, tool power, and tool tags.
5. Add that definition to `EquipmentCatalog.DEFINITIONS`.
6. Add the same item ID/name/weight to pickups, loot, crafting, or starting inventory through `PlayerInventory.try_add_item()`.

The player can only equip definitions for item IDs they currently own.

## Controls

- `1`–`9`: equip owned equippable items in inventory order.
- Left mouse / right trigger: primary use.
- Right mouse / left trigger: secondary use.
- Controller D-pad left/right: previous/next equipment.
- Inventory: double-click or activate an equippable row to equip or unequip it.

## Melee motion

Melee equipment uses staged first-person motion rather than an instant transform kick. Weapons use a faster diagonal slash, while tools use a heavier overhead swing.

Gameplay contact is resolved at the strike phase of the animation rather than at initial button press, so the hit timing matches the visible motion more closely.

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

Regardless of runtime behaviour, any visible player-held representation must still use PNG artwork rather than a 3D model.
