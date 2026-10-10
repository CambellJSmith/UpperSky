# Saved games

The game automatically resumes `current.json` on startup, autosaves every 60 seconds, and saves when its window closes. F5 writes the separate quick-save slot; F9 reloads that slot. A small message confirms saves and loads.

The developer console also accepts `save`, `load`, `save quick`, `load quick`, and `save folder`. Loading rebuilds the game scene so streamed actors bind to the restored world records. The current slot resumes automatically; the quick slot is explicitly loaded with F9.

Saves include absolute overworld position (independent of floating-origin shifts), cave identity and interior position, heading and camera pitch, all inventory stacks and their quantities/categories/weights, equipped item, current and maximum health/stamina/mana, world time and clock speed, NPC wounds/deaths/affection/corpse locations/belongings, changed container contents, activated wayshrines, and the special starting cave pair. Deterministic terrain, settlements and other generated structures reconstruct from the world seed. Living NPC patrol animation, velocity, open menus, debug cheats, flying and performance captures are transient.

Files live in Godot's `user://saves` folder, normally `~/.local/share/godot/app_userdata/UpperSky/saves` on Linux. `save folder` opens the actual configured location. Each slot is versioned JSON with a world seed and generation revision. Older generation saves retain progress; overworld player positions below the new ground or water are raised safely during restoration. Cave seeds and pair IDs are decimal strings to preserve all 64 integer bits. The save contains plain data; loading does not deserialize scripts or arbitrary resources.

Writes are flushed and verified in a temporary file before replacing the current file. The previous verified save becomes `.json.bak`. If the main file is invalid, loading tries the backup. Invalid/incompatible files without a usable backup are preserved and autosaving pauses; an explicit save can replace them. Failed writes retain the previous file or backup. If saving on window close fails, the first close shows a warning and a second close exits without saving. Force-killing the process cannot run the close save; the last autosave/quick save remains available.

The loader validates file size, format, fields, finite numbers, item definitions and state types before replacing runtime records. Saves wait while initial collision or a travel transition is unresolved. Restoration grants no duplicate starter equipment and retains owned items even if carrying capacity has fallen below their combined weight. A matching cave is rebuilt before player physics resumes, including its original exterior exit pair.

Run `godot --headless --path . --script application/save/tests/check_save.gd` for restart, backup recovery, cave routing, state restoration and 64-bit seed checks. Test files use an isolated temporary save folder.
