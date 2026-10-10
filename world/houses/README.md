# Procedural medieval houses

This generator creates low-poly exterior houses entirely from native geometry and solid-colour materials. A seed produces a repeatable house; the same recipe works in the Godot editor and during gameplay.

## Preview in the game

Open the developer console with the grave/tilde key and enter:

- `houses`: build a six-house inspection courtyard using seed 42.
- `houses 123`: build another collection using a different integer seed.
- `houses clear`: remove the courtyard.

The preview enables fly mode and moves the player to the courtyard. It sits above the terrain so the examples can be inspected without terrain or vegetation cutting through them. It follows floating-origin changes and is hidden with the overworld during dungeon visits. Normal world generation does not scatter these preview houses into the landscape.

## Use in a level

Instance `res://world/houses/procedural_house.tscn`. Expand its `recipe` resource in the Inspector and edit the seed or override the settings. Changes rebuild the house automatically. The `regenerate` checkbox also requests a rebuild; `generate_collision` controls physical collision.

A `HouseRecipe` resource can be saved as a `.tres` and shared with settlement or placement systems. Leave width, depth or floors at zero for seeded defaults, or override them. Width/depth overrides are bounded to 4–14 and 4–18 metres; floors are bounded to 1–3. The ground plane is local Y=0 and the main entrance faces local -Z. Position the house on suitable level ground and rotate its parent to change its facing.

```gdscript
var recipe = HouseRecipe.new()
recipe.seed_value = 123
recipe.layout = HouseRecipe.Layout.L_SHAPED
recipe.wall_style = HouseRecipe.WallStyle.BRICK
recipe.roof_style = HouseRecipe.RoofStyle.SLATE

var house = ProceduralHouse.new()
house.recipe = recipe
house.position = Vector3(0, 0, 0)
add_child(house)
```

`HouseGeometry.new().build(recipe, true)` returns a generated `Node3D` directly for systems that do not need editor regeneration. The generated root's `house_parameters` metadata contains the resolved dimensions and style choices; `bounds` and `footprint` metadata include the complete geometry, including annexes, overhangs and porches, for future placement systems.

## Variation

- Layouts: cottage, long hall, L-shaped annex, cross-shaped wings, jettied upper storeys, narrow tower.
- Walls: staggered stone blocks, reddish brick courses, vertical wooden boards, plaster and timber framing. Jettied upper floors switch to timber framing and include support brackets.
- Roofs: blue-grey slate with overlapping tiles, or golden thatch with raised reed bundles, uneven eaves and a rounded ridge. Towers and some cottages use hipped roofs; other houses use gables.
- Details: pitched gable framing, multi-pane windows, shutters, plank doors, iron fittings, stone thresholds, optional supported porches, and optional brick chimneys with caps and dark flue openings.

Masonry blocks, siding planks, slate tiles and thatch bundles use broader spacing for a slightly simpler appearance and less generated geometry. Shared spacing constants keep immediate and incremental generation consistent; the wall relief, overlapping roofs, raised thatch folds and structural framing remain.

The geometry batches detail into one mesh per material rather than one node per brick, board or roof tile. Foundation, floor footprint, roof and chimney collisions are separate shapes under one static body. Houses are solid exterior buildings: doors and windows are decorative, and interior rooms are not generated.

Generated children are temporary and not serialized with the house node; the saved recipe is the source of truth. Geometry/materials require no imported art assets.

## Verification

After the usual Godot editor import, run:

```sh
godot --headless --path . --script res://world/houses/tests/check_generation.gd
godot --headless --path . --script res://world/houses/tests/check_build_paths.gd
godot --headless --path . --script res://world/houses/tests/check_showcase.gd
```

These cover all 48 explicit layout/wall/roof combinations, seed repeatability, geometry winding and normals, dimension overrides, physical collision, recipe-driven regeneration, and in-game preview lifecycle and origin shifts.
