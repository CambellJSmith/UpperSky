# Shared actor health

`HealthState` is the authoritative health model used by both `PlayerVitals` and NPC `DamageableHealth` components. The default is 100/100, with a positive configurable maximum. Damage and healing clamp to the valid range and return the actual amount changed. Invalid or non-finite amounts are ignored. Increasing the maximum does not automatically heal; lowering it clamps current health. Invulnerability restores full health and prevents damage.

The model exposes health, maximum, ratio, revision, `changed` and `died`. Death fires once per transition from positive health to zero. Healing or setting positive health revives the model. Player vitals delegates all health operations to this model while retaining separate stamina and mana and preserving the existing HUD and developer APIs.

All active villager types have a `Health` child and `get_health_component()`. Melee equipment hits route through this component. The legacy billboard NPC base also attaches the generic component. Villager death and revival handle the visual pose and corpse-loot availability; the health model itself has no rendering or inventory dependency.

Villager health states live in `LootSession` alongside inventory state, preserving wounds and deaths through streaming. The save system serializes these records for persistence between sessions.

Checks: `godot --headless --path . --script actors/combat/tests/check_health.gd`, followed by the loot and villager population checks.

## NPC combat

Every active NPC uses NpcCombat. Affection at or below 10 enables hostility, including species starting at 0. Nearby living players are acquired within 24 metres with line of sight; pursuit ends beyond 36 metres. Raising affection above 10 immediately cancels combat and pending strikes. Death and inactive streaming also cancel combat. Patrols resume after disengagement.

Armed NPCs select an inventory weapon and use its existing damage, reach and cooldown with dedicated slash, chop or stab motions. They cannot punch or kick while armed. See `actors/npcs/villagers/README.md` for weapon selection and grip details.

NPCs run towards the player at 3 metres/second on safe ground. Cave pursuit follows connected floor cells using bounded breadth-first routes, refreshed twice per second; overworld pursuit uses short dry-ground detours and physics collisions. NPCs avoid water, lava and unsafe slopes.

Only NPCs without a weapon use unarmed combat. Unarmed attacks alternate two punches and a kick, using the existing quaternion animations. Punches deal 8 damage after a 0.30-second windup; kicks deal 12 after 0.45 seconds. Attacks have at least 1.4 seconds between starts and wait for the animation to finish. Hits recheck the living target, 1.8-metre reach and unobstructed line of sight at impact. Damage uses the player's shared HealthState and therefore honours invulnerability and updates the existing health display. Player weapons still damage NPCs through the existing melee system; affection changes are controlled independently.

Checks: `godot --headless --path . --script actors/combat/tests/check_npc_combat.gd`.
