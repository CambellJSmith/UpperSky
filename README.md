# UpperSky

UpperSky is a first-person procedural open-world RPG in active development with Godot 4.7.

The current game is built around exploring a deterministic, continuously streamed world on foot: crossing wilderness and distinct biome regions, finding camps, homesteads and towns, entering procedural cave dungeons, fighting and looting NPCs, collecting and equipping weapons, discovering wayshrines, and returning to the same persistent world through the save system.

This README describes the game as it currently exists on `main`. It is intended as a current-state overview rather than a development changelog.

## Current Game

UpperSky currently combines these playable systems:

- Infinite deterministic terrain with streamed collision, water and floating-origin rebasing.
- First-person walking, sprinting, jumping, climbing and swimming.
- Health, stamina and mana resources with an in-game status HUD.
- A categorized, weight-limited inventory and first-person equipment system.
- Seventeen melee weapons/tools with distinct damage, reach, cooldowns and attack motions.
- First-person arms that grip and animate equipped weapons.
- Shared player/NPC health and melee combat.
- Armed and unarmed NPC combat driven by an affection/hostility system.
- Lootable chests and defeated NPC inventories.
- Procedural camps, medieval houses, homesteads, towns, roads and wilderness paths.
- Procedural cliff entrances and deterministic cave-dungeon interiors.
- Human, orc, demon, ghost, zombie and fish-man NPC populations.
- Discoverable wayshrines with fast travel between activated shrines.
- A day/night cycle and biome-specific world features.
- Automatic saving, quick save/load and persistent world/NPC state.
- A developer console, runtime profiler and generation diagnostics.

UpperSky is still a development project rather than a finished, content-complete RPG. The current focus is the systemic world, exploration, combat, persistence and streaming foundation.

## World

### Infinite Terrain

The overworld is generated deterministically from the world seed and streamed around the player in reusable terrain chunks. Terrain geometry, water, paths and placement systems all use the same world-space sampling rules, so the world can be unloaded and reconstructed without losing its identity.

The terrain supports large hills, mountains, ridges, valleys and crevasses. Nearby collision is kept active for the player while more distant terrain is primarily visual. Floating-origin rebasing keeps the player and active physics close to the engine origin while preserving absolute world positions for saves and deterministic generation.

Terrain and water buffers are generated through two bounded worker jobs. Main-thread generation work across terrain, paths, settlements, vegetation, camps, NPC routes and wayshrines is coordinated through a soft per-frame generation budget, with nearby terrain work taking priority.

### Biomes

The procedural world contains several large-scale biome types with their own terrain and streamed features:

- **Ice Flats** — frozen terrain, water and floating collidable ice floes.
- **River Valleys** — broad river channels with waterfall and foam features.
- **Volcanic Islands** — volcanic terrain with crater lava, glow and smoke effects.

Water is part of traversal rather than just scenery. Entering sufficiently deep water switches the player into swimming movement and applies an underwater view effect. Volcanic lava is currently a visual world feature rather than a player damage system.

### Day And Night

The overworld has a continuous day/night cycle with sun, moon, sky, fog and environment lighting changes. World time and cycle speed are included in saved games and can also be inspected or changed through the developer console.

### Vegetation And Scenery

The world streams low-poly trees, rocks, shrubs, flora and dense ground cover around the player. Placement systems share reservations with roads, settlements, camps and other generated structures so vegetation does not simply ignore occupied world space.

### Camps

Small deterministic wilderness camps can appear on suitable dry, gently sloped terrain. Camps include generated props such as tents, campfires, stumps, axes, bedrolls and loot chests.

Looking at a camp bedroll and interacting with it allows the player to rest for eight hours of world time.

### Homesteads And Towns

Settlements are placed directly into the procedural terrain rather than existing as fixed authored maps.

Rare homesteads use small single-storey cottages. Larger towns contain 8–16 houses arranged around connected streets, a central square and a well. Procedural house styles include cottages, long halls, winged houses, jettied upper floors and towers, with combinations of stone, brick, wood, timber framing, slate and thatch.

Doors face the generated street network, short paths connect buildings to roads, and placement rejects unsuitable water, slope, camp and overlap conditions. Houses are currently solid exterior structures; the procedural settlement system does not provide enterable house interiors.

### Roads And Paths

A shared path network provides wilderness roads, settlement streets, door paths and dry connections between generated settlements. The same network is used by terrain/path rendering and by NPC route systems, allowing residents and travellers to move through the world using the generated geography.

## Dungeons

UpperSky generates paired cliff and hillside entrances in the overworld. Interacting with an entrance builds the corresponding deterministic cave interior and moves the player into an isolated underground dungeon space.

Dungeon identity, topology and entrance pairing are deterministic. Interior doors route back to the correct overworld endpoint instead of acting as generic teleports. The overworld streaming presentation is suspended while a dungeon is active and restored when the player exits.

Cave interiors have collidable floors, walls and ceilings, their own environment, and cave-specific NPC population. Ghosts and zombies can populate connected floor cells away from entrance doors. The active cave identity and player position inside it are preserved by the save system.

A starting cave pair is generated as part of a new game's initial world setup.

## Player

### Movement

The first-person controller currently supports:

- Walking and air control.
- Sprinting with stamina drain.
- Jumping with a stamina cost.
- Wall climbing while holding the jump/climb control and moving into a climbable collision surface.
- Swimming, including ascent, descent and faster swimming.
- Delayed stamina regeneration after exertion.
- Mouse and controller camera look.

The developer console also provides a collision-free fly mode for testing and world inspection.

### Vitals

The player owns three persistent resource pools:

- **Health** — receives combat damage and determines player death state.
- **Stamina** — consumed by sprinting, jumping, climbing and swimming. Maximum stamina also defines inventory carrying capacity.
- **Mana** — represented by the current player-resource and HUD/save systems for future gameplay use.

Health uses the same underlying health model as NPCs.

## Inventory And Equipment

### Inventory

The inventory is divided into six stable categories:

- Weapons/Tools
- Armour
- Potions
- Books
- Ingredients
- Misc

Every stack tracks quantity, unit weight and total stack weight. The player's maximum stamina is also the live carrying-weight limit, and loot transfers respect that capacity.

A new game currently starts with a **Mysterious Locket** and the complete equipment collection.

### Equipment

The current equipment catalogue contains seventeen usable melee weapons/tools:

- **Core:** Iron Sword, Iron Pickaxe.
- **Swords:** Bronze-Hilt Longsword, Duelist Rapier, Desert Sabre, Cleaver Falchion, Highland Greatsword.
- **Axes:** Woodsman Axe, Double Battleaxe, Crescent Axe, Bearded Raider Axe, Obsidian Hatchet.
- **Knives:** Crossguard Dagger, Curved Kukri, Black Tanto, Bone-Handle Seax, Hunter's Knife.

Each item has its own weight, reach, damage, cooldown and held scene. Swords primarily use slashing motion, axes and the pickaxe use chopping motion, and knives use thrusting motion. The rapier uses the stabbing profile. Gameplay contact is resolved during the strike portion of the visible first-person animation rather than immediately on button press.

Axes and tools can also expose tool power/tags to world objects that implement the equipment-hit contract.

Equipment can be selected from the inventory, with number keys `1`–`9`, or by cycling equipment on controller. The first-person arm rig follows the currently equipped item and its attack motion.

## NPCs

### Population

The current character roster includes:

- Humble Pilgrim
- Village Weaver
- Orc Warlord
- Demon
- Ghost
- Zombie
- Tidefin Sentinel fish-man

Humans and orcs can appear as residents, homesteaders and wilderness travellers. Demons are streamed around suitable volcanic areas. Ghosts and zombies populate cave dungeons. Fish-men patrol dry routes close to water.

NPC population is streamed around the player and rebuilt deterministically when areas are revisited. Persistent records retain important state such as health, affection, death state, corpse location and belongings.

### Affection And Hostility

NPC combat is controlled by affection. NPCs at affection `10` or below become hostile; raising affection above that threshold cancels active combat. Species can begin with different affection levels, so some populations are naturally friendly while others are hostile on encounter.

Hostile NPCs acquire nearby living players with line of sight, pursue on safe terrain and disengage when the target escapes their pursuit range. Cave pursuit uses connected dungeon floor cells, while overworld pursuit uses dry-ground routing and physics collision. NPC movement avoids water, lava and unsafe slopes.

### Combat

NPCs use the same equipment catalogue as the player when armed. An armed NPC chooses the highest-damage weapon in its inventory and uses that weapon's damage, reach, cooldown and appropriate slash/chop/stab animation.

Unarmed NPCs use a sequence of punches and kicks. Combat hits are checked at impact time for range, line of sight and a living target.

Player melee attacks damage NPCs through the shared health system. At zero health, a character stops normal movement, enters a corpse state and becomes lootable. Wounds, deaths and changed corpse inventories survive streaming and saved games.

## Loot

Look at a chest or defeated NPC within interaction range and use **Interact** to open the loot interface.

The loot window shows the container and player inventory side by side. Items can move in either direction, either individually or as a complete stack. Carrying capacity is enforced when taking items, and storing the final owned copy of an equipped weapon automatically unequips it.

Loot chests can appear in camps, towns and rare homes. Changed chest contents and corpse belongings are persistent save data rather than being regenerated each time the area streams back in.

## Wayshrines And Fast Travel

Wayshrines are deterministic low-poly stone monuments with bronze details, floating crystals and animated rune lights. They are placed on suitable dry ground away from incompatible generated features.

Look at a shrine within interaction range and use **Interact** to awaken it. Activated shrines are remembered permanently in the current save. Once at least two have been activated, the shrine interface can travel to another discovered shrine.

Fast travel rebuilds destination terrain collision, rebases the floating origin when required and resolves a collision-safe arrival point before returning control to the player.

## Saving And Persistence

UpperSky automatically resumes the `current` save slot on startup when one exists.

The game:

- Autosaves every 60 seconds.
- Saves when the game window closes normally.
- Uses `F5` for the separate quick-save slot.
- Uses `F9` to load the quick-save slot.
- Keeps a verified backup of the previous save when replacing a slot.
- Validates save structure and values before restoring runtime state.

Saved state includes the player's absolute overworld/cave location, view orientation, inventory, equipped item, health, stamina, mana, world time, NPC wounds/deaths/affection/belongings, changed loot containers, activated wayshrines and deterministic cave-pair information.

Terrain, settlements and other deterministic generated structures are reconstructed from the stored world seed instead of being serialized as scene geometry.

On Linux, saves normally live under:

```text
~/.local/share/godot/app_userdata/UpperSky/saves
```

The developer console command `save folder` opens the configured save directory directly.

## Controls

UpperSky supports keyboard/mouse and controller input.

| Action | Keyboard / Mouse | Controller |
| --- | --- | --- |
| Move | `W` `A` `S` `D` | Left Stick |
| Look | Mouse | Right Stick |
| Sprint / Fast Swim | `Shift` | Left Stick Click |
| Jump / Climb / Swim Up | `Space` | A |
| Swim Down | `Ctrl` | B |
| Interact | `E` | X |
| Inventory | `I` | Y |
| Primary Equipment Use | Left Mouse | Right Trigger |
| Secondary Equipment Use | Right Mouse | Left Trigger |
| Previous Equipment | — | D-Pad Left |
| Next Equipment | — | D-Pad Right |
| Equipment Slots | `1`–`9` | — |
| Toggle Mouse Capture | `Escape` | Start |
| Quick Save | `F5` | — |
| Quick Load | `F9` | — |
| Developer Console | Grave / Tilde | — |

Inventory and loot interfaces also use `Escape` to close. The inventory can equip or unequip a selected weapon/tool by activating its row.

## Developer Console

Press the grave/tilde key to open the in-game developer console. Type `help` for the current command list.

Useful commands include:

```text
save [current|quick]
load [current|quick]
save folder

fly [on|off]
infinite_health [on|off]
infinite_stamina [on|off]
infinite_mana [on|off]

biome <ice|river|volcanic>
town
homestead
houses [seed|clear]
npc <punch|kick>

time
time set <hour>
time speed <multiplier>

profile start
profile stop
profile status
profile mark <description>
profile export
profile folder
```

The `biome`, `town`, `homestead` and `houses` commands are development navigation/preview tools; they are not ordinary player fast-travel systems.

## Running The Project

### Requirements

- Godot **4.7**.
- The project currently uses Godot's **Compatibility** renderer.

### From The Editor

1. Clone the repository.
2. Import `project.godot` into Godot 4.7.
3. Allow Godot to import the included assets.
4. Run the project.

The configured main scene is:

```text
res://application/game/game.tscn
```

### From The Command Line

From the repository root:

```sh
godot --path .
```

## Project Structure

```text
actors/
  combat/          Shared health and NPC combat systems
  npcs/            Character rigs, population, relationships and behaviour
  player/          First-person controller, vitals, inventory, equipment and arms

application/
  debug/           Developer console and runtime profiler
  effects/         Player-facing effects such as underwater rendering
  game/            Main scene composition and gameplay interactions
  save/            Save/load, validation and persistence
  streaming/       Cross-system generation scheduling
  ui/              HUD, inventory and loot interfaces

items/
  equipment/       Equipment catalogue, definitions, held scenes and hit framework
  loot/            Loot storage, chests and persistent loot records

world/
  biomes/          Biome definitions and streamed biome features
  camps/           Procedural camp placement and geometry
  decorations/     World decoration streaming
  dungeons/        Procedural paired entrances and cave interiors
  environments/    World environment and day/night cycle
  houses/          Procedural medieval house generation
  paths/           Shared road and path network
  settlements/     Homestead and town generation
  terrain/         Infinite terrain, water and mesh generation
  trees/           Procedural low-poly tree generation
  vegetation/      Flora and dense ground-cover streaming
  wayshrines/      Wayshrine placement, activation and registry
```

## Detailed System Documentation

Several systems have their own implementation and testing notes:

- [Combat and shared actor health](actors/combat/README.md)
- [NPC relationships](actors/npcs/relationships/README.md)
- [Villagers, travellers and NPC populations](actors/npcs/villagers/README.md)
- [First-person arms](actors/player/arms/README.md)
- [Runtime profiling](application/debug/PROFILING.md)
- [Save system](application/save/README.md)
- [World-generation scheduling](application/streaming/README.md)
- [Equipment framework](items/equipment/README.md)
- [Loot and storage](items/loot/README.md)
- [Procedural houses](world/houses/README.md)
- [Roads and paths](world/paths/README.md)
- [Settlements](world/settlements/README.md)
- [Procedural trees](world/trees/README.md)
- [Wayshrines](world/wayshrines/README.md)

## Testing

Subsystems include headless checks under their respective `tests/` directories. Examples:

```sh
godot --headless --path . --script application/save/tests/check_save.gd
godot --headless --path . --script application/streaming/tests/check_generation.gd
godot --headless --path . --script actors/combat/tests/check_health.gd
godot --headless --path . --script actors/combat/tests/check_npc_combat.gd
godot --headless --path . --script items/loot/tests/check_loot.gd
godot --headless --path . --script world/wayshrines/tests/check_wayshrines.gd
```

See each subsystem README for the checks relevant to that system.

## License

UpperSky is licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE).

Some bundled third-party assets have their own attribution/license information alongside the relevant source files; for example, NPC animation sources include the Quaternius license under `actors/npcs/villagers/animations/`.
## Current world streaming details

The biome art uses flat face lighting, a restrained palette, bevelled faceted ice, polygonal volcanic slopes, cracked lava plates, and soft low-poly smoke. Water surfaces are horizontal planes with subtle animated colour ripples. Geological lakes use fixed elevation bands; biome seas and river reaches use fixed regional levels without blending water uphill. Waterfalls connect the separate river elevations using vertical flowing ribbons, polygon rock clusters, and a spreading foam pool. Rendering, swimming and boats share the same water levels and shoreline clipping. Road and ferry caches are versioned when this water layout changes.

World roads now connect towns, city gates and isolated homes using terrain-aware routes rather than repeated wilderness curves. They avoid cliffs and obstacles, cross rivers and narrow ravines on walkable low-poly bridges, and share their geometry with village streets, vegetation clearing and road travellers. Road searches run in background workers and completed plans are cached between sessions. See `world/paths/README.md` for generation, streaming and checks.

Dense grass combines nearby blade meshes with distant grass shading in the terrain's existing material. Shared 56/28/7-blade meshes use 100/50/25 clumps per tile, with density transitions at 42 and 65 metres and hidden tiles beyond 95 metres. Blades gradually shorten from 60 to 95 metres while ground shading blends in from 42 to 80 metres, preserving the low-poly terrain faces. Both use the same local road, shore, biome and clearing masks; farther ground shading follows terrain colours. World-space patches remain stable across floating-origin shifts, and fine detail fades before it can shimmer. Five-metre density hysteresis prevents repeated switching. This reduces distant blade geometry without adding another terrain render pass; actual frame-rate gains depend on the scene and hardware.

Each city castle has exactly one Crimson King and one Shadow Sentinel. Both use the shared NPC health, inventory, affection, animation and save systems; the Shadow Sentinel starts at neutral affection 100.
