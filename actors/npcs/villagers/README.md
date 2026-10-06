# Villagers and travellers

The supplied Humble Pilgrim and Village Weaver GLBs retain their original mesh, textures, rig and imported Running clip. Both models appear as non-hostile civilians: six mixed residents per nearby town, one resident beside a suitable isolated home, and sparse travellers on the existing meandering wilderness paths.

## Animation sources

Idle, walking, jogging, sprinting and two punches use the CC0 Quaternius Universal Animation Library. The local pack's skeleton and seven source clips are preserved in `animations/source/quaternius_source.tscn`, without unrelated meshes, scripts or textures. Creator: https://quaternius.com/packs/universalanimationlibrary.html . License: `animations/QUATERNIUS-LICENSE.txt`.

The free Standard libraries do not include a kick. `Kick` is an authored complementary front kick generated from the retargeted idle pose, with a knee lift, extension and recovery. It is explicitly not represented as a downloaded Quaternius clip.

`authoring/bake_animations.gd` maps anatomical bones, calibrates lowered arms and legs against the pack's T-pose, preserves limb lengths, transfers normalized quaternion rotations, scales vertical pelvis motion and removes horizontal root motion. Each rig has one shared compressed ten-clip library; retargeting runs offline, not once per NPC. The pilgrim maps 41 supported bones and the weaver maps 65. Missing optional finger bones remain attached to their parents.

Rebuild: `godot --headless --path . --script actors/npcs/villagers/authoring/bake_animations.gd` after importing the GLBs.

## Behaviour and placement

Residents stroll and pause on checked routes drawn from `WorldPathNetwork` streets that avoid houses and the central well. Homesteaders stroll along their home’s shared entrance path and road connection. Travellers follow checked stretches of the terrain's existing path network, walking with occasional jogging. Routes reject water, lava, unsuitable biome cores, camp clearings, buildings and abrupt height changes. Character-body collision handles trees, rocks, houses, other villagers and the player; blocked NPCs pause and reverse along their route.

The population loads within 420 metres, unloads beyond 600 metres and caps at 24 characters. Distant characters pause animation and movement. Absolute positions survive floating-origin shifts, and the World subtree automatically suspends them in dungeons. Unloaded NPCs regenerate deterministically when revisited; health, affection and belongings persist in records included in saved games.

`Villager.perform_action("punch")` and `perform_action("kick")` play one-shot actions before returning to the route. In the developer console, `npc punch` or `npc kick` previews the nearest available villager within 20 metres. NPCs initiate combat at affection 10 or below. These unarmed actions are available only without an inventory weapon; armed NPCs use weapon_slash, weapon_chop or weapon_stab instead.

## Checks

`tests/check_population.gd` checks village/home/traveller placement, repeatability, valid normalized bone tracks, distinct action poses, movement and action gating. `tests/check_streaming.gd` checks the actual game composition, both models, bounds on population size, actions, origin shifts, dungeon suspension and unloading.

Villagers now have 100 health and accept melee equipment hits. Defeated villagers lie down and expose their inventory through the shared loot interface. Death locations and changed belongings survive streaming through saved games. See `items/loot/README.md`.

NPC health uses the same `HealthState` as `PlayerVitals`, exposed through a `DamageableHealth` child named Health. Damage, healing, maximum changes, invulnerability, health ratios and death transitions follow shared rules. Wounds survive streaming. Healing a corpse above zero restores its standing pose and movement and closes corpse-loot access.

## Additional supplied characters

The shared roster now contains the pilgrim, weaver, friendly orc (`Meshy_AI_Orc_Warlord_Running.glb`), demon (`Meshy_AI_Character_output.glb`), ghost (`Meshy_AI_Frostbound_Wraith_Running.glb`) and zombie (`Meshy_AI_Low_Poly_ZOmbie_Running.glb`). Source GLBs are copied unchanged. Orcs share normal resident, homesteader and traveller routes with the humans. The source filenames are mapped to the user's requested roles.

Each rig has a baked ten-clip library. The demon has no imported clips and uses numbered bones; its anatomy is mapped explicitly in `authoring/rig_map.gd`. Monster rigs without optional named finger landmarks skip only that calibration segment. All seven models retain their proportions and share the health, death, revival and loot systems.

`VolcanoPopulation` streams up to eight demons on checked dry routes near volcanic island centres, avoiding water and lava. `CavePopulation` adds up to four alternating ghosts and zombies to connected cave floor cells away from entrance doors. Cave actors use local dungeon coordinates and floor heights rather than overworld sampling. Their identities, deaths and inventories survive rebuilding the same cave through saved games.

Demons, zombies and fish-men start hostile at affection 0. Humans, orcs and ghosts start above the combat threshold; any species becomes hostile at affection 10 or below. `populations/check_placement.gd` verifies volcanic restrictions, cave floor routes, bounded spawning and cave corpse persistence. The population check now exercises all seven rigs and animation sets.

The blue Tidefin Sentinel is a separate fish-man (`fish_man.glb`, roster index 6), not an orc. `WaterPopulation` samples deterministic 512-metre cells for dry eight-metre patrol routes within 24 metres of water. Routes avoid lava, camps, settlement clearings and abrupt slopes; nearby fish-men stream within 420 metres, unload beyond 650 metres and cap at eight. Candidate caches are bounded to 128 cells. The new Orc Warlord occupies the friendly orc slot (index 2). Both retain shared animations, health and corpse loot.

## Inventory weapons

NpcEquipment chooses the highest-damage WEAPON in the NPC's inventory, retaining the first inventory entry on ties. Tools and unknown items do not count as weapons. It reuses the native low-poly weapon model and follows the right hand in normalized world units on all seven rigs. Inventory changes refresh equipment immediately for combat and each active frame for rendering. Equipped items stay in inventory; looting the item removes the corpse's visible weapon, and streaming preserves the loadout.

Swords use WeaponSlash, axes WeaponChop, knives and the rapier WeaponStab. These three complementary quaternion motions are authored in the offline baker alongside the authored kick; Quaternius supplies the existing locomotion and punch clips. Every rig now has ten clips. Armed NPCs use the selected weapon's catalogue damage, reach and cooldown and cannot punch or kick. Removing or replacing a weapon during a queued strike cancels that hit. Without a weapon they return to unarmed combat. Existing starting inventory contents are unchanged.

See `actors/combat/tests/check_npc_equipment.gd` for grip, selection, armed damage, disarming, streaming and corpse-loot checks.
