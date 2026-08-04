# UpperSky

A Godot 4.6 first-person open-world RPG project.

## Current foundation

- Reusable basic exterior world scene with sky, sun, fog, ground collision, and a movement test platform.
- Reusable first-person `CharacterBody3D` player with mouse and controller look.
- Walking, sprinting, jumping, gravity, floor handling, and limited air control.
- Composition-root game scene that owns the world and player instances.
- No autoloads, signals, external assets, or editor-exposed tuning variables.

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
