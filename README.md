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
