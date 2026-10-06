# Shared world paths

`WorldPathNetwork` supplies wilderness roads, town crossroads and squares, front-door footpaths, and homestead entrances. Settlement exits connect to a nearby regional road with a checked direct route or a bounded eight-direction terrain search. Connections reject water, lava, steep ground, camps and buildings. If the search cannot find a safe connection, the local streets remain; no road is forced across a dangerous area.

`PathMeshBuilder` renders every road type with the same compacted-earth colours and softened shoulders. Faces are clipped to both world chunks and the exact terrain triangles. Terrain collision remains the walking surface. `PathStreamer` builds one nearby chunk per frame, retaining at most 81 chunks, and stores absolute coordinates for floating-origin alignment. Its World parent handles dungeon suspension.

`TerrainPathSampler` combines regional and settlement wear/grass masks when given the owning terrain. Terrain colouring, grass, flowers, trees and rocks query this shared mask. Residents and travellers obtain their routes from the same network; they still validate routes against obstacles and water.

Base height generation and initial camp/building placement use the original regional mask only. This keeps terrain elevation and settlement placement independent of road planning order and prevents circular sampling. Connections then avoid those established footprints. Both road-plan and chunk caches are bounded to 128 entries.

Run `godot --headless --path . --script world/paths/tests/check_network.gd` after importing the project. It checks dry town/home connections, deterministic plans, vegetation masks, NPC waypoints, chunk clipping and terrain-conforming meshes. Villager streaming checks exercise the composed game, origin shifts and dungeon suspension.
