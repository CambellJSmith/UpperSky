# Natural homesteads and towns

Settlements use the same low-poly medieval house generator as the inspection courtyard, but are now placed directly on the procedural terrain and streamed with exploration.

## Lone homesteads

Each 768-metre cell has only a 10% chance to even attempt a homestead. The twelve bounded placement attempts can still all fail. Accepted homes are small, single-storey wood or stone cottages with thatched roofs, chimneys and occasional porches. They are kept outside towns and existing camps.

The initial real-terrain survey found about one homestead per 13 square kilometres. This is a sampled density, not a guaranteed count in every district. Different terrain and biome conditions can leave large areas empty.

Footprints must be dry, avoid existing paths, vary by at most 0.90 metres, and keep sampled grades below 13%. Frozen and volcanic cores, lava and the immediate origin area are excluded.

## Towns

Each 3072-metre region has a 78% chance to attempt a town. Up to 24 candidate sites are checked; rejected sites remain empty. An accepted town contains 8–16 houses around a connected main street, crossing street and central square with a well.

Houses mix cottage, longhall, winged, jettied and tower layouts with stone, brick, wood and timber walls, and slate or thatched roofs. Plot dimensions, setbacks and style choices vary by seed. Doors face the streets, short paths connect each front door to the road, and expanded lots cannot intersect streets or neighbouring buildings.

The road corridor must be dry with sampled grades below 20% and no more than 10 metres of variation across the town. Every house footprint independently requires at most 1.35 metres of height variation and 18% sampled grade. Buildings reject existing camps and paths. Roads and door paths conform to the rendered terrain triangles. Stone foundations extend below uneven ground rather than leaving cottages floating.

## Streaming and clearing

`SettlementStreamer` is a child of `World` in the main game scene. Houses start loading within 2400 metres and unload beyond 2800 metres. Town houses are constructed one per frame. Collision is active only near the player. Saved absolute positions keep settlements aligned after floating-origin shifts, and the World subtree handles suspension during dungeon visits.

The shared deterministic `SettlementSampler` also reserves building plots, roads and footpaths for the decoration, ground-flora and grass systems. Trees and rocks use additional clearance around buildings. This works even before the corresponding settlement models have streamed in.

`HouseRecipe.foundation_extension` controls the below-ground stone footing depth used by the placement system. `house_bounds()` conservatively includes roof overhangs, porches and wings during placement tests.

## Visit examples

Open the developer console with the grave/tilde key:

- `town`: fly to a nearby naturally generated town.
- `homestead`: fly to a nearby rare cottage.
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
