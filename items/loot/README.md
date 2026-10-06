# Loot and storage

Look at a chest or dead villager within three metres and press Interact (E / X). The two-column window shows its contents and the player's inventory. Select an item and take/store one or its entire stack; double-click moves one. Escape, Interact or Inventory closes the window. Carrying capacity is enforced for withdrawals. Transfers reject conflicting item definitions and insufficient quantities without changing either inventory.

`LootStorage` is the shared stack model and atomic transfer service. `LootSession` holds seeded initial contents and changed inventories for the current game session. Camps, villages and rare homes have low-poly wooden chests. `LootChest` exposes the inventory and an open-lid visual. The same interface searches corpse belongings.

Villagers now receive the existing `EquipmentHit` melee contract, with 100 health. At zero health they stop walking and animating, lie down and expose their belongings. Their death location, health and inventory survive streaming unload/reload, together with changed chest contents. The save system also retains this state between sessions.

Interaction rays hit walls and terrain first. Opening the interface releases the cursor and suspends player gameplay input; closing restores it. An invalid, hidden or distant target closes the window automatically. Equipment ownership validation automatically unequips the final copy of a stored weapon.

Run `godot --headless --path . --script items/loot/tests/check_loot.gd`. It checks two-way transfers, capacity, quantities, conflicting definitions, UI actions, container reloads, melee death, corpse reloads, interaction rays and wall occlusion. Villager streaming checks cover the composed scene, both NPC models, origin shifts and dungeon suspension.

NPC health uses the same `HealthState` as `PlayerVitals`, exposed through a `DamageableHealth` child named Health. Damage, healing, maximum changes, invulnerability, health ratios and death transitions follow shared rules. Wounds survive streaming. Healing a corpse above zero restores its standing pose and movement and closes corpse-loot access.
