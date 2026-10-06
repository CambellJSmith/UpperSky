# UpperSky

A Godot 4.6 first-person open-world RPG project.

## Current foundation

- Deterministic infinite procedural height-field streamed in reusable terrain chunks around the player.
- Long rolling hills, broad mountain provinces, layered ridges, blended mountain tiers, deep valleys, and narrow regional crevasses.
- Seam-consistent mesh geometry and normals generated from continuous world-space coordinates.
- Near-to-far chunk generation spread across frames, with exact collision retained only around the player.
- Floating-origin rebasing keeps active entities and terrain transforms near local origin during effectively unbounded travel.
- Height and slope-driven vertex colouring for lowlands, grassland, highlands, rock faces, and snowy summits.
- Reusable first-person `CharacterBody3D` player with mouse and controller look.
- Walking, sprinting, jumping, gravity, floor handling, and limited air control.
- Composition-root game scene that owns the world and player instances.
- No autoloads, signals, external assets, or editor-exposed tuning variables.

## Terrain behaviour

The terrain is generated from a fixed world seed, so the landscape is stable rather than changing between playthroughs. Terrain chunks are created and removed as the player travels, while all chunks sample the same absolute world-space height function so their borders remain continuous. A floating origin periodically shifts loaded terrain and active entities toward local scene origin without changing their absolute procedural coordinates.

The starting area is intentionally gentler than the wider world. Extreme mountains, valleys, and crevasses blend in as the player moves away from the initial spawn.

## Controls

| Action | Keyboard and mouse | Controller |
| --- | --- | --- |
| Move | W, A, S, D | Left stick |
| Look | Mouse | Right stick |
| Sprint | Left Shift | Left-stick click |
| Jump | Space | A |
| Toggle mouse capture | Escape | Start |

## Run

Open the repository in Godot 4.6 and run the project. The configured main scene is `res://application/game/game.tscn`.

## Unoccupied camps

Camps are scattered deterministically through the streamed world, with two to four open-front canvas tents facing a central lit campfire and two chopping stumps with embedded axes. They contain no enemies. Sites are accepted only on dry, gently sloping ground: the 24-metre camp footprint must vary by no more than 1.5 metres, with sampled local grades below 14 percent. Unsuitable cells remain empty rather than forcing camps onto steep ground. Trees, boulders, and vegetation leave camp clearings; tents and stumps have collision. Camps unload with distance, keep their placement when revisited, follow floating-origin rebasing, and suspend during dungeon visits.

Each tent contains a usable bedroll. Look at it within three metres and press E (controller X) to rest for eight in-game hours. Rest wraps across midnight and refreshes the sky and lighting immediately while retaining the configured clock speed. Bedrolls cannot be used through tent walls or while inventory or the console is open.

## Biomes

The seeded world now blends broad distinct regions into the original temperate terrain:

- **Ice flats:** low snow-covered shelves and open-water pools, with irregular floating ice floes that gently bob and support the player nearby.
- **River valleys:** meandering submerged channels, dry banks, and two 32-metre cascades with animated falling water and foam.
- **Volcanic islands:** basalt archipelagos in a local sea, a raised volcano crater rim, and an animated glowing lava lake. Lava is currently visual scenery, not a damage system.

Biome features stream with the player, remain aligned after floating-origin shifts, and suspend during dungeon visits. Frozen and volcanic cores suppress normal woodland and grass. Camps still require dry, flat ground and cannot spawn in crater lava. The starting platform stays intact.

For quick previews, open the developer console with the tilde key and use `biome ice`, `biome river`, or `biome volcanic`. These commands enable fly mode and move above a nearby biome while its terrain loads. Use `fly off` after reaching safe ground to resume normal movement.

The biome art uses flat face lighting, a restrained palette, bevelled faceted ice, polygonal volcanic slopes, cracked lava plates, and soft low-poly smoke. Water surfaces are horizontal planes with subtle animated colour ripples. Geological lakes use fixed elevation bands; biome seas and river reaches use fixed regional levels without blending water uphill. Waterfalls connect the separate river elevations using vertical flowing ribbons, polygon rock clusters, and a spreading foam pool. Rendering, swimming and boats share the same water levels and shoreline clipping. Road and ferry caches are versioned when this water layout changes.

## Low-poly equipment

The Weapons/Tools inventory now contains 17 usable 3D items: the original iron sword and pickaxe, plus five swords, five axes and five knives. Designs include a swept-guard rapier, curved sabre, broad falchion, double battleaxe, bearded axe, obsidian hatchet, kukri and tanto. Equip them from the inventory; the first nine also have number-key shortcuts. Swords slash, axes chop and knives thrust, with individual weights, damage, reach and cooldowns.

## Procedural medieval houses

A seeded low-poly house generator supports cottages, long halls, L-shaped and cross-shaped wings, jettied upper storeys and towers. Wall styles include stone, brick, wood and timber framing; slate and bundled-thatch roofs include gabled or hipped shapes. Houses also have shutters, wooden doors, optional porches and brick chimneys. Sizes, floor counts and materials can be overridden in a saved recipe.

Use the developer console's `houses [seed]` command to inspect six examples in a courtyard, or instance `world/houses/procedural_house.tscn` in a level. `houses clear` removes the preview. Houses currently generate solid exteriors with collision. See `world/houses/README.md` for editor controls and the generation API.

## Natural settlements

Rare single-storey wood or stone cottages with thatched roofs now appear on dry, gently sloping ground. Lone homes are uncommon: only one in ten 768-metre cells attempts placement, with further terrain and biome checks.

Larger regions can contain towns with 8–16 varied medieval houses facing connected streets and a central square with a well. Streets follow the terrain, buildings have grounded stone footings, and vegetation clears their plots and access paths. Settlements stream during exploration and pause with the overworld in dungeons.

The developer console commands `town` and `homestead` visit naturally generated examples. See `world/settlements/README.md` for placement rules and verification.

## Varied low-poly woodland

Trees now include oaks, birches, beeches, Scots pines, spruces, willows, wind-bent oaks and occasional dead snags, with two forms per family. Tapered trunks, visible forks, roots, layered conifer branches and hanging willow foliage give each family a distinct structure. Species gather into groves, with conifers favoured at altitude and willows near water. All remain flat-shaded, low-poly models with shared meshes and three distance-detail levels. See `world/trees/README.md` for construction and verification.

## First-person arms

The supplied textured low-poly arm is now used for both player arms, mirrored for the left side and attached to the camera. The arms reach into view from below, curl their fingers around weapon handles, and follow sword slashes, axe/tool chops and knife thrusts. Heavy equipment uses both hands. See `actors/player/arms/README.md` for the rig and grip setup.

## Villagers and wilderness travellers

The Humble Pilgrim and Village Weaver now populate towns and suitable isolated homes, with occasional travellers following wilderness paths. They stroll, pause to idle and sometimes jog. Both use retargeted Quaternius movement and punch animations, plus a complementary authored front kick. They start neutral towards the player.

Use `town` or `homestead` to visit settlements, then `npc punch` or `npc kick` to preview a nearby character's action. NPCs avoid unsafe routes, stream with exploration and pause during dungeon visits. See `actors/npcs/villagers/README.md` for animation sources, behaviour and checks.

World roads now connect towns, city gates and isolated homes using terrain-aware routes rather than repeated wilderness curves. They avoid cliffs and obstacles, cross rivers and narrow ravines on walkable low-poly bridges, and share their geometry with village streets, vegetation clearing and road travellers. Road searches run in background workers and completed plans are cached between sessions. See `world/paths/README.md` for generation, streaming and checks.

Wilderness ground cover includes wind-swaying tall grass clumps among the short grass, denser clusters of faceted woody shrubs, ferns, reeds and wildflowers. Patch density, size and colour vary deterministically; plants follow the rendered terrain and keep roads, camps, houses, water and unsuitable biome cores clear. Grass clumps fade beyond 310 metres, while shrubs remain visible to 720 metres and use shared batched meshes.

Dense grass combines nearby blade meshes with distant grass shading in the terrain's existing material. Shared 56/28/7-blade meshes use 100/50/25 clumps per tile, with density transitions at 42 and 65 metres and hidden tiles beyond 95 metres. Blades gradually shorten from 60 to 95 metres while ground shading blends in from 42 to 80 metres, preserving the low-poly terrain faces. Both use the same local road, shore, biome and clearing masks; farther ground shading follows terrain colours. World-space patches remain stable across floating-origin shifts, and fine detail fades before it can shimmer. Five-metre density hysteresis prevents repeated switching. This reduces distant blade geometry without adding another terrain render pass; actual frame-rate gains depend on the scene and hardware.

Press E / X while looking at a chest or defeated villager to open loot. Take or store one item or an entire stack using the shared two-column inventory window. Camps, towns and isolated homes now contain wooden chests. Changed contents and corpse state survive world streaming during the current game session; restarting the game resets them. See `items/loot/README.md`.

Player and NPC health now share one generic `HealthState` model. NPCs start at 100/100 like the player and use the same damage, healing, maximum-health and invulnerability rules. Their `Health` component drives death, revival and corpse loot, while wounds persist through streaming for the current session. See `actors/combat/README.md`.

The supplied demon, ghost, zombie and orc models are now animated NPCs. Demons appear on dry volcanic ground, ghosts and zombies inside caves, and friendly orcs share settlements and wilderness trails with the human villagers. All use the shared health and corpse-loot systems. Their affection scores determine whether they patrol peacefully or initiate combat.

The friendly orc now uses the supplied Orc Warlord model. The blue Tidefin Sentinel is a separate fish-man population patrolling dry shoreline routes near water, with the shared animation, health and loot systems.

NPCs initiate combat when affection is 10 or below, pursuing nearby visible players and using timed melee attacks. Raising affection above 10 stops combat. NPCs with a weapon in their inventory equip its low-poly model and use sword slashes, axe chops or knife thrusts with the weapon's existing stats; only unarmed NPCs punch and kick. Equipped weapons remain available as corpse loot. Affection defaults are humans 100, orcs 50, ghosts 25, and demons/zombies/fish-men 0. See `actors/combat/README.md` for behaviour and checks.

Wayshrines now appear on dry, gently sloped wilderness ground, with stone arches, floating crystals and glowing runes. Press E / X to activate a discovered shrine and open its travel menu. Only other activated shrines can be selected; arrival loads destination collision and places the player safely beside it. Discoveries persist through area streaming for the current session. See `world/wayshrines/README.md`.

To capture slow gameplay, use `profile start` in the console, close it and play for 30–90 seconds, then use `profile export`. Send the resulting JSON file for diagnosis. `profile mark <description>` labels a moment, `profile status` shows progress, and `profile folder` opens the export directory. The recorder is off by default. See `application/debug/PROFILING.md`.

## Saving

Games resume automatically, autosave every 60 seconds and save when the window closes. **F5** quick-saves and **F9** loads the quick save. Console: `save`, `load`, `save quick`, `load quick`, `save folder`. Player inventory, equipment, location (including caves), stats, world time, NPC state, loot and activated wayshrines persist. See `application/save/README.md`.

## World streaming

Terrain and water buffers build on two background workers. Paths, vegetation and other placement work share a 3 ms main-thread generation budget, with nearby ground prioritized. Visual density and terrain resolution are retained; distant scenery fills in gradually. See `application/streaming/README.md`. Profiler reports include worker and scheduler counters.
