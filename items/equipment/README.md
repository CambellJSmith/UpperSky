# Equipment framework

Equipment is split into inventory ownership, data definitions, held runtime behaviour, and world hit receivers.

## Low-poly 3D visuals

Held equipment uses reusable native 3D model scenes under `items/equipment/models/`. The iron sword has a diamond-section blade, crossguard, wrapped leather grip and pommel; the pickaxe has a curved iron head, socket and bound wooden handle. Materials use solid colours without image textures.

Model dimensions are in metres, with the grip at the origin and the blade or handle pointing up (+Y). The camera equipment mount scales models to 55% for first-person framing. The held scene controls the ready angle and the existing runtime controls the swing. Meshes use ordinary depth testing and world lighting; held models do not cast shadows onto the player's surroundings.

## Add a new melee weapon or tool

1. Make a low-poly model scene under `items/equipment/models/`, with named editable mesh parts and solid-colour materials.
2. Create a held scene under `items/equipment/scenes/` whose root inherits `MeleeEquipment`, and instance the model as a child.
3. Set the held scene's ready angle and check its framing throughout the swing.
4. Create an `EquipmentDefinition` resource under `items/equipment/definitions/` with the inventory ID, weight, scene, reach, cooldown, damage, tool power, and tool tags.
5. Add that definition to `EquipmentCatalog.DEFINITIONS`.
6. Grant inventory ownership through `PlayerInventory.try_add_item()`.

The player can only equip definitions for item IDs they currently own.

## Controls

- `1`–`9`: equip owned equippable items in inventory order.
- Left mouse / right trigger: primary use.
- Right mouse / left trigger: secondary use.
- Controller D-pad left/right: previous/next equipment.
- Inventory: double-click or activate an equippable row to equip or unequip it.

## Melee motion

Melee equipment uses staged first-person motion. Swords use a diagonal slash, axes and the pickaxe use an overhead chop, and knives use a short forward thrust. Held scenes select SLASH, CHOP or STAB through `motion_profile`.

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

Reuse the same 3D model convention for other held equipment. Unequipping a melee item cancels its pending swing and contact.

## Weapon collection

The starting inventory includes the original sword and pickaxe plus fifteen new weapons, all in Weapons/Tools. Items after the first nine can be equipped from the inventory or reached with the controller equipment cycle.

- Swords: Bronze-Hilt Longsword, Duelist Rapier, Desert Sabre, Cleaver Falchion, Highland Greatsword.
- Axes: Woodsman Axe, Double Battleaxe, Crescent Axe, Bearded Raider Axe, Obsidian Hatchet.
- Knives: Crossguard Dagger, Curved Kukri, Black Tanto, Bone-Handle Seax, Hunter's Knife.

Each has a separate model scene, held scene and definition with its own weight, damage, reach and cooldown. Axes also supply `chopping` tags and tool power to compatible world hit receivers. The greatsword and battleaxe hit harder with longer recovery; knives trade reach and damage for speed. No enemies are added.

`authoring/build_weapon_collection.gd` can regenerate the fifteen model scenes and optionally export GLB files. Runtime equipment instances the saved native scenes directly and does not run the authoring script. Models use bevelled, flat-shaded geometry and editable named components.
