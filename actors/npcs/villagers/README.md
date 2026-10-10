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

## Residents and settlement journeys

Residents and homesteaders stay on their town or home routes; city residents, guards and the king stay in their separate city space. Wilderness travellers now follow complete checked roads between actual homes, towns and city entrances. Random short exploration loops and fragments of road are no longer used as destinations. Travellers include peasants, orcs, wizards and knights, alone or in parties of two to five. They pause for 25–60 seconds on arrival before taking the validated return route. City destinations currently end at the exterior approach; the separate city population continues to live inside.

Party members follow their leader's recorded footsteps around bends. Whole-road seeds identify the same party across neighbouring streaming cells; spawning checks the entire population to avoid duplicating a party when it changes cells. Journey position, waypoint, direction and visit time are retained in the existing loot/save record. Blocked travellers wait rather than changing direction to patrol a short stretch of road. Human travellers retain their rare werewolf/vampire eligibility and existing health, affection, equipment, combat and loot systems.

Nearby cells stream cooperatively through the generation scheduler, with at most 72 villagers in the wilderness population. Complete routes are validated once and cached, and empty encounter cells retry when road generation finishes. `tests/check_encounters.gd` checks settlement destinations, dry route safety, deterministic scheduling, shared identities, party spawning and following.

## Affection between NPCs

`NpcRelationships` checks nearby NPCs every quarter second using fifty-metre spatial cells, separately for the wilderness, each cave and each city. When two living NPCs first come within fifty metres, each starts with its own default affection toward the player, plus 50 if their species match, capped at 200. Defaults are 100 for humans, wizards and kings, 50 for orcs, 25 for ghosts, 11 for knights, and 0 for zombies, demons, fish men, werewolves and vampires. Peasants, wizards, knights and kings are all human for the matching-species bonus; current werewolf/vampire forms count as their transformed species. For example, a human starts at 150 toward a knight, while the knight starts at 61 toward the human. Scores are decided once and do not reroll after moving away, changing form, streaming or loading a save. Existing saved relationships retain their scores.

The directed scores live in the existing persistent NPC loot records. `get_npc_affection(other)` returns `null` until they have met; `set_npc_affection` and `change_npc_affection` return false for an unmet NPC. Their player affection and player combat rules continue to use the existing separate score. This stores relationships for future social behaviours; it does not make NPCs attack one another automatically. `relationships/tests/check_npc_relationships.gd` checks proximity, species bonuses, asymmetric scores and persistence.

`NightGhostPopulation` adds up to eight free-roaming overworld ghosts near the player. They choose random dry, walkable wilderness routes and regularly choose a new direction, independently of roads and settlements. They share the vampire/werewolf night window (18:00–06:00), fade in over two seconds, and fade out over eight seconds at sunrise. Their default affection remains 25. Cave ghosts retain their existing behavior. The population pauses with the overworld during cave/interior/city visits and maintains absolute positions across origin shifts.

Road traffic creates two parties of 3–5 travellers per checked settlement road, travelling in opposite directions. Peasants and orcs make up most travellers; every party has a peasant or orc leader, with occasional wizards and knights. Fresh traffic identities are introduced every 180 seconds so a road does not stay empty after its first party leaves. Existing travellers continue their journeys; this does not teleport them back. The 72-NPC local limit remains. Residents and travellers each have their own 48-NPC ceiling, leaving room for both rather than letting either population fill all slots. The three-minute cadence targets a sighting at least every five minutes near a loaded, walkable road, subject to visibility and local combat.

Town and homestead populations refresh independently of road travellers, at higher scheduler priority. A pending regional journey validation cannot hold up a newly entered village. The resident allowance counts residents rather than all NPCs; towns provide six residents and two patrolling guards even when the road-traveller allowance is full. `tests/check_town_priority.gd` covers both starvation cases together.

## Runtime Update Cadence

Villagers retain collision-backed movement every physics tick within 80 metres of the player. Outside that range, peaceful patrols advance along checked routes at approximately ten updates per second out to 180 metres and four updates per second beyond it. Elapsed time is accumulated so reduced update frequency preserves travel speed. Active combat, explicit actions and ferry-route actors retain ordinary physics updates.

Manual skeleton evaluation remains continuous within 40 metres, drops to approximately fifteen evaluations per second out to 120 metres, and five farther away. Combat and action poses stay continuous. Inventory revisions and night-form changes remain independent of pose timing. Streaming activation resets deferred time so suspended actors do not jump forward on reactivation.

NPCs own their position updates. Population streamers manage activation and membership; floating-origin events reposition overworld actors, including suspended actors, without recurring streamer transform writes.

Run the cadence and streaming regressions through the shared scene-first runner:

- `godot --headless --path . --script application/streaming/tests/run_regression.gd -- actors/npcs/villagers/tests/check_update_cadence.gd`
- `godot --headless --path . --script application/streaming/tests/run_regression.gd -- actors/npcs/villagers/tests/check_streaming.gd`
