# World generation scheduling

The production seamless terrain streamer computes ground and water buffers on two bounded `WorkerThreadPool` jobs. Jobs own their noise samplers and copied path definitions. They produce plain mesh arrays; mesh uploads, materials, nodes and physics shapes stay on the main thread. Biome cache access is protected by a mutex. The scheduler retains each generator until its task has finished and joins outstanding tasks during scene teardown.

Runtime terrain preparation, paths, settlement placement/house geometry, trees/boulders, shrubs, grass maps, NPC route checks, camp placement and shrine placement cooperate through `GenerationScheduler.checkpoint`. The scheduler targets **3 ms of generation work per rendered frame**, including worker result installation. A checkpoint cannot interrupt an individual engine call or candidate check, so this is a soft budget rather than a hard maximum frame time. Nearby terrain preparation has highest priority; nearby paths/vegetation follow; distant work shares FIFO turns. Jobs inherit their priority and owning node through nested async helpers. Disabled world owners wait until resumed.

Terrain remains queued in rings from the player outward. Initial spawn and explicit teleport collision neighbourhoods are built synchronously before movement resumes. The starting cave and its physical return doors are ready before play begins; later entrance searches are incremental. Finished worker results are discarded when a chunk has left the desired stream set or was already created synchronously. Ordinary base-terrain use without the production seamless worker backend retains the synchronous API and duplicate/stale queue checks.

Paths reject segments outside the chunk before subdivision, cache repeated vertex queries and yield during clipping/assembly. The terrain query service also keeps a bounded 32,768-entry cache of exact height samples shared by placement and ground interpolation. No terrain resolution, road width, density or visual quality was reduced.

Grass builds its next map into a private image. Repeated recenter requests coalesce, and outdated results are discarded. The image, world-space map origin and tile positions update together after the map is complete, keeping the old valid carpet visible while generation runs.

Synchronous generation APIs remain available for editor previews, placement tests and explicit collision-safe setup. Incremental APIs use the same deterministic seeds and geometry rules. Changes to those rules should update both paths; `tests/check_generation.gd` checks equivalent terrain/water arrays, path vertices/colours, town placement/road definitions, decoration transforms and house meshes/collisions. It also checks worker handoff and paused-owner resumption.

Profiler reports now include `generation.main_thread_slices`, `terrain.install_chunk`, active workers, queued slices, completed/stale jobs, budget and largest observed slice, plus worker task elapsed times. Worker times overlap frames and other tasks and must not be summed into main-thread frame timings. These counters reset with the game scene, so compare their changes over a recording.

Checks:

- `godot --headless --path . --script application/streaming/tests/check_generation.gd`
- `godot --headless --path . --script application/save/tests/check_save.gd`

Validation included a 30-second headless full-world capture with no frames above 100 ms, plus a Compatibility renderer smoke test. Headless FPS is not comparable to a rendered gameplay capture. Use `profile start`, follow the same route as the original report, then `profile export` to measure the remaining bottlenecks on the player's graphics hardware.
