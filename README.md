# UpperSky

UpperSky is a first-person procedural open-world RPG in active development with Godot 4.7.

The current game is built around exploring a deterministic, continuously streamed world on foot: crossing wilderness and distinct biome regions, finding camps, homesteads and towns, entering procedural cave dungeons, fighting and looting NPCs, collecting and equipping weapons, discovering wayshrines, and returning to the same persistent world through the save system.

This README describes the game as it currently exists on `main`. It is intended as a current-state overview rather than a development changelog.

## Current Game

UpperSky currently combines these playable systems:

- Infinite deterministic terrain with streamed collision, water and floating-origin rebasing.
- First-person walking, sprinting, jumping, climbing and swimming.
- Concentric health, stamina, mana and experience rings, with delayed health regeneration.
- A categorized, weight-limited inventory and first-person equipment system.
- Seventeen melee weapons/tools with distinct damage, reach, cooldowns and attack motions.
- First-person arms that grip and animate equipped weapons.
- Shared player/NPC health and melee combat.
- Armed and unarmed NPC combat driven by an affection/hostility system.
- Lootable chests and defeated NPC inventories.
- Procedural camps, medieval homes, towns, fortified city entrances, terrain-aware roads and bridges.
- Procedural cliff entrances and deterministic cave-dungeon interiors.
- Peasants, orcs, wizards, knights, kings, Shadow Sentinels, demons, ghosts, zombies and fish-men, plus night-transforming werewolves and vampires.
- Discoverable wayshrines with fast travel between activated shrines.
- A day/night cycle, night-only encounters, biome-specific scenery and automated shore ferries.
- Automatic saving, quick save/load and persistent world/NPC state.
- Enterable building rooms and separate city/cave spaces with loading screens.
- A heading compass for nearby points of interest, with provisional fallback markers.
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

Water surfaces are flat, horizontal planes. Seas, lakes and river reaches use fixed levels, with waterfalls between river elevations; rendering, swimming and ferry placement share these levels.

Water is part of traversal rather than just scenery. Entering sufficiently deep water switches the player into swimming movement and applies an underwater view effect. Volcanic lava is currently a visual world feature rather than a player damage system.

### Day And Night

The overworld has a continuous day/night cycle with sun, moon, sky, fog and environment lighting changes. World time and cycle speed are included in saved games and can also be inspected or changed through the developer console.

### Vegetation And Scenery

The world streams varied low-poly trees, closely fitted boulder collision, shrubs, flora and dense ground cover around the player. Placement shares reservations with roads, settlements, camps and other structures.

Grass combines nearby instanced blade meshes with distant shading in the existing terrain material. Density drops at 42 and 65 metres; blades shorten and disappear by 95 metres as ground shading takes over. Both representations use shared road, shoreline, biome and clearing masks and stable world coordinates. This reduces distant geometry without an extra terrain render pass; performance still depends on the scene and hardware.

### Camps

Small deterministic wilderness camps can appear on suitable dry, gently sloped terrain. Camps include generated props such as tents, campfires, stumps, axes, bedrolls and loot chests.

Looking at a camp bedroll and interacting with it allows the player to rest for eight hours of world time.

### Homesteads And Towns

Settlements are placed directly into the procedural terrain rather than existing as fixed authored maps.

Isolated homesteads use small single-storey cottages on suitable flat ground. Each 384-metre cell has a 55% chance to attempt a home; every 1536-metre region attempts a town or city, with unsuitable sites rejected. Larger towns contain 8–16 houses arranged around connected streets, a central square and a well. Procedural house styles include cottages, long halls, winged houses, jettied upper floors and towers, with combinations of stone, brick, wood, timber framing, slate and thatch.

Doors face the generated street network, short paths connect buildings to roads, and placement rejects unsuitable water, slope, camp and overlap conditions. Interact with a building entrance to enter its separate interior room. Rooms currently provide empty spaces sized to their exterior; furnished interiors and detailed indoor activities remain future work. Loading screens cover entry and exit.

### Roads And Paths

A shared terrain-aware network connects population centres, city gates and isolated homes, together with town streets and door paths. Routes sample ground heights, avoid cliffs, water, lava and structures, and can cross short rivers or ravines on low-poly wooden bridges. Visible paths conform to terrain; NPC routes and vegetation clearing use the same network.

Road planning runs in bounded background jobs and caches completed plans between sessions. Local streets appear independently of unfinished regional searches. Broad seas and impassable terrain can leave settlements disconnected.

### Fortified Cities

One third of valid settlement seeds become city entrances. Their exterior has tall stone walls, towers, gates, a moat and drawbridge. Crossing the drawbridge enters a separate city space with 52 varied medieval houses, 52 peasant residents, streets, a market square and castle.

Each castle has exactly **one Crimson King and one Shadow Sentinel**, with six knights patrolling the courtyard and streets. Their health, affection, belongings and positions persist across visits and saves. City scenery is batched by material and neighbourhood; construction happens across frames while the loading screen remains visible. The city gate returns to the overworld, and city houses have their own interior rooms.

### Docks And Boats

Wooden docks appear in suitable shallow-gradient shore locations with a checked crossing to another bank. Dock pairs are spaced apart and reject intersecting lanes, shoals, waterfalls, lava and unsafe approaches.

Each bank maintains three waiting boats. Interact at a dock to board immediately; the boat sails automatically and places the passenger on the opposite dock. Player and NPC boats can travel independently in both directions. Saving aboard records a safe departure dock.

Where both banks have validated settlement connections, travelling NPCs walk from their home settlement, cross by boat and continue to another town or city gate. Following them leads toward a settlement. City travellers currently stop at the exterior approach rather than entering the separate city space.

## Dungeons

UpperSky generates paired cliff and hillside entrances in the overworld. Interacting with an entrance builds the corresponding deterministic cave interior and moves the player into an isolated underground dungeon space.

Dungeon identity, topology and entrance pairing are deterministic. Interior doors route back to the correct overworld endpoint instead of acting as generic teleports. The overworld streaming presentation is suspended while a dungeon is active and restored when the player exits.

Cave interiors have collidable floors, walls and ceilings, their own environment, and cave-specific NPC population. Ghosts and zombies can populate connected floor cells away from entrance doors. The active cave identity and player position inside it are preserved by the save system.

A starting cave pair is generated as part of a new game's initial world setup. Loading screens cover initial loading, cave entry/exit and saved-space restoration until destination geometry and collision are ready.

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

Health uses the same underlying health model as NPCs. After three seconds without damage, a living player regenerates two health per second.

Health, stamina and mana appear as clockwise concentric rings in the top right. A white centre ring tracks experience, capped at 100; it stays full when filled and does not currently trigger an automatic level-up. NPC defeats and certain loot transfers award experience. Loot rewards currently use item-weight thresholds as a proxy rather than a full economic value system.

### Compass

A heading-relative compass shows cardinal directions and nearby undiscovered camps, homes, towns, cities and caves. Inside cities it marks the castle, gate, square and nearby houses. Only forward-facing bearings are drawn in the visible bar.

The current overworld fallback pads the list to at least five entries using provisional directional markers; these do not yet locate verified, unstreamed POIs. Treat fallback icons as unfinished exploration guidance.

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

The current roster has thirteen models: Humble Pilgrim, Village Weaver, Orc Warlord, demon, ghost, zombie, Tidefin Sentinel fish-man, travelling wizard, werewolf, knight, vampire, Crimson King and Shadow Sentinel.

Towns provide six civilian residents and two guards; isolated homes have a resident. City residents, king, shadow person and guards stay in their own city space. Road travellers include peasants, orcs, wizards and knights in groups of 3–5, travelling between real settlements and pausing on arrival before returning. Traffic adds new deterministic party identities every three minutes, targeting regular encounters near loaded roads rather than guaranteeing a sighting regardless of terrain or visibility. The wilderness villager population is capped at 72, with separate resident and traveller allowances so traffic cannot crowd out townspeople.

Demons patrol suitable volcanic ground, zombies and ghosts inhabit caves, and fish-men patrol near water. Up to eight additional ghosts roam the overworld at night and fade out at sunrise. Eligible travelling human peasants have a 1-in-50 chance of being a werewolf and a separate, mutually exclusive 1-in-50 chance of being a vampire. They transform during the shared 18:00–06:00 night window, become hostile at affection 0, and restore their daytime form and affection after sunrise.

Models retain their supplied rigs and textures. Shared offline-baked quaternion animation libraries provide idle, walk, run, punches, kick and weapon motions. Quaternius supplies locomotion and punches; the kick and weapon attacks are complementary authored animations.

### Affection And Hostility

Affection ranges from **0** (hate) through **100** (neutral) to **200** (adoration). Starting player scores are:

| NPC | Affection |
| --- | ---: |
| Humans, wizards, kings, Shadow Sentinels | 100 |
| Orcs | 50 |
| Ghosts | 25 |
| Knights | 11 |
| Demons, zombies, fish-men, werewolf/vampire forms | 0 |

When two living NPCs first come within 50 metres in the same world space, each receives its own directed score toward the other: its species' player starting score, plus 50 for matching species, capped at 200. These relationships are decided once and saved. Peasants, wizards, knights and kings count as human for the matching-species bonus.

Every point of actual damage removes one affection point from the victim toward the attacker, including NPC-on-NPC hits. Combat selects the lowest-affection eligible living target with line of sight in the same space. Scores of 10 or below enable hostility; an NPC that has caused damage can also become a retaliation target above 10 when its score falls below the victim's score toward the player. Target selection runs within 24 metres and pursuit ends beyond 36 metres.

NPC movement uses checked terrain routes and collision, avoiding water, lava and unsafe slopes. Saved records retain wounds, relationships, deaths, positions, journeys and belongings across streaming and sessions.

### Combat

NPCs use the same equipment catalogue as the player when armed. An armed NPC chooses the highest-damage weapon in its inventory and uses that weapon's damage, reach, cooldown and appropriate slash/chop/stab animation.

Unarmed NPCs use a sequence of punches and kicks. Combat hits are checked at impact time for range, line of sight and a living target.

Unarmed wizards cast visible travelling fireballs. Projectiles hit the first wall or character, including other NPCs, and attribute damage to their caster, allowing accidental hits to provoke retaliation. Armed wizards use their weapon instead.

Player melee attacks damage NPCs through the shared health system. At zero health, a character stops normal movement, enters a physical skeletal ragdoll state and becomes lootable. Wounds, deaths and changed corpse inventories survive streaming and saved games. Corpse physics includes a skeletal simulation, interaction dragging and water-current handling. This system remains experimental: the current grab releases when Interact is released, and stable full-body dragging and flotation need further validation.

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

Saved state includes the player's absolute overworld location or active cave/city/building space, view orientation, inventory, equipped item, health, stamina, mana, experience, world time, NPC wounds/deaths/relationships/belongings and journey state, changed loot containers, activated wayshrines and deterministic cave-pair information.

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
city
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

The `biome`, `town`, `city`, `homestead` and `houses` commands are development navigation/preview tools. To investigate performance, run `profile start`, play through slow areas, then run `profile export` and share the resulting JSON. Reports include frame-time percentiles, spikes, scoped CPU timings, streaming queues, counters and markers. Main-thread scopes and overlapping worker durations are reported separately; the scheduler uses a soft frame budget rather than a strict frame-time guarantee.

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
  settlements/     Homesteads, towns and isolated city spaces
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
godot --headless --path . --script actors/combat/tests/check_npc_grudges.gd
godot --headless --path . --script world/settlements/tests/check_city.gd
godot --headless --path . --script world/paths/tests/check_ferries.gd
godot --headless --path . --script application/debug/tests/check_profiler_threads.gd
godot --headless --path . --script items/loot/tests/check_loot.gd
godot --headless --path . --script world/wayshrines/tests/check_wayshrines.gd
```

See each subsystem README for the checks relevant to that system.

## License

UpperSky is licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE).

Some bundled third-party assets have their own attribution/license information alongside the relevant source files; for example, NPC animation sources include the Quaternius license under `actors/npcs/villagers/animations/`.
