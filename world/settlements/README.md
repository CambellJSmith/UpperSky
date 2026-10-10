# Natural homesteads and towns

Settlements use the same low-poly medieval house generator as the inspection courtyard, but are now placed directly on the procedural terrain and streamed with exploration.

## Lone homesteads

Each 384-metre cell has a 55% chance to attempt a homestead, with up to 24 candidate sites. Accepted homes are small, single-storey wood or stone cottages with thatched roofs, chimneys and occasional porches. They remain outside towns and existing camps, on dry, gently sloping ground.

Footprints must be dry, avoid existing paths, vary by at most 0.90 metres, and keep sampled grades below 13%. Frozen and volcanic cores, lava and the immediate origin area are excluded.

## Towns

Every 1536-metre region attempts a town or city. Up to 48 candidate sites are checked; rejected sites remain empty. An accepted town contains 8–16 houses around a connected main street, crossing street and central square with a well.

Houses mix cottage, longhall, winged, jettied and tower layouts with stone, brick, wood and timber walls, and slate or thatched roofs. Plot dimensions, setbacks and style choices vary by seed. Doors face the streets, short paths connect each front door to the road, and expanded lots cannot intersect streets or neighbouring buildings.

The road corridor must be dry with sampled grades below 20% and no more than 10 metres of variation across the town. Every house footprint independently requires at most 1.35 metres of height variation and 18% sampled grade. Buildings reject existing camps and paths. Roads and door paths conform to the rendered terrain triangles. Stone foundations extend below uneven ground rather than leaving cottages floating.

A real-terrain survey over the same area produced 71 settlements (including 29 cities) and 295 isolated homes, compared with 21 settlements and 26 homes before this density change. Counts vary with terrain and biome conditions.

## Streaming and clearing

`SettlementStreamer` is a child of `World` in the main game scene. Houses start loading within 2400 metres and unload beyond 2800 metres. Nearby regions are scanned first, with search coverage derived from the load distance. Existing town houses are completed before starting another settlement. Collision is active only near the player. Saved absolute positions keep settlements aligned after floating-origin shifts, and the World subtree handles suspension during dungeon visits.

The shared deterministic `SettlementSampler` also reserves building plots, roads and footpaths for the decoration, ground-flora and grass systems. Trees and rocks use additional clearance around buildings. This works even before the corresponding settlement models have streamed in.

`HouseRecipe.foundation_extension` controls the below-ground stone footing depth used by the placement system. `house_bounds()` conservatively includes roof overhangs, porches and wings during placement tests.

## Visit examples

Open the developer console with the grave/tilde key:

- `town`: fly to a nearby naturally generated town.
- `homestead`: fly to a nearby cottage.
- `houses [seed]`: the separate six-house inspection courtyard remains available.

Travel searches a bounded nearby area and reports when no valid site is found. Allow terrain and settlement models to stream at the destination. Houses remain solid exterior models. The villager population system supplies residents.

## Checks

After importing the Godot project, run these from the repository root:

```sh
godot --headless --path . --script res://world/settlements/tests/check_sampling.gd
godot --headless --path . --script res://world/settlements/tests/check_real_sites.gd
godot --headless --path . --script res://world/settlements/tests/check_streaming.gd
```

The checks cover repeatability, rarity, primitive styles, rejected wet/steep sites, non-overlapping street-facing lots, vegetation reservations, village furniture, dry building footprints on real terrain, streaming, origin shifts and dungeon suspension.

Village streets, squares and door paths now belong to `WorldPathNetwork` and `PathStreamer`, together with the wilderness roads and dry connections between settlements and the regional network. `SettlementGeometry` only builds the well. Road surfaces use the terrain collision rather than separate raised collision floors. See `world/paths/README.md`.

## Fortified cities

One third of valid settlement seeds create a city entrance instead of a wilderness village. The exterior has stone curtain walls, crenellated towers, a retained moat, a wooden drawbridge and a stone approach. Simplified roofs and a keep provide a skyline. The regional path network connects to the gate rather than generating invisible exterior house paths.

Walking across the drawbridge loads a separate city space. Each city has 52 varied medieval houses and peasants, a street grid and market square, and a castle with one Crimson King, one Shadow Sentinel and six knights. Two guards patrol the courtyard; four patrol the city streets. Walk through the city gate to leave. The loading screen stays up until all houses, NPCs, scenery batches and physics have been prepared.

Wilderness streaming pauses during city visits; the day/night clock continues. Static scenery is batched by material in 48-metre neighbourhoods, retaining individual building metadata and collisions. City identity, player position, NPC health, affection, inventory and patrol positions persist through saves and visits. Saves inside city houses restore the corresponding room. Construction happens across frames.

Use `city` in the developer console to fly to a nearby natural city exterior. Descend to the approach and cross the drawbridge. `town` and `homestead` remain available. Run `world/settlements/tests/check_city.gd` for city geometry, safe routes, king animations, entry, exit, save files and building interior checks.

The Shadow Sentinel uses the supplied rigged GLB and the shared Quaternius animation pack, baked offline for idle, walk, run, punch, kick and weapon attacks. Each city creates exactly one with a stable identity and a courtyard patrol. It starts neutral at 100 affection; inventory, health, relationships and position use the same persistent city NPC system as the king.

### City batching performance

City scenery now copies source vertices, inverse-transpose normals, flat colours and rebased triangle indices directly into neighbourhood buffers. Only the final ArrayMesh for each group is uploaded; generation no longer creates and uploads a temporary coloured mesh for every source surface. Existing building nodes, metadata, physics children, dynamic actors and special transparent/textured rendering remain intact. Frame checkpoints and 48-metre culling groups are retained.

An isolated headless Godot 4.7.2 comparison using 52 houses from the current HouseGeometry generator measured the batching stage at 3.87 seconds before and 2.67 seconds after (about 31% less time). This measures batching, not total city loading or gameplay FPS; timings depend on hardware and recipes. A separate 4,000-box comparison retained the same triangle geometry, colours, vertex count and 36 neighbourhood batches.

Run the focused buffer and hierarchy regression alongside the full city integration check:

```sh
godot --headless --path . --script res://world/settlements/tests/check_city_batch.gd
godot --headless --path . --script res://world/settlements/tests/check_city.gd
```
