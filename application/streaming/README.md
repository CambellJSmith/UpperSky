# World generation scheduling

The production seamless terrain streamer computes ground and water buffers through two bounded `WorkerThreadPool` slots. Road and ferry searches may occupy at most one slot, reserving capacity for terrain. Jobs own their noise samplers and copied path definitions. They produce plain mesh arrays; mesh uploads, materials, nodes and physics shapes stay on the main thread. Biome cache access is protected by a mutex. The scheduler retains each generator until its task has finished, cancels cancellable samplers before joining them during scene teardown, and then releases the tasks.

Runtime terrain preparation, paths, settlement placement/house geometry, trees/boulders, shrubs, grass maps, NPC route checks, camp placement and shrine placement cooperate through `GenerationScheduler.checkpoint`. The scheduler targets **3 ms of generation work per rendered frame**, including worker result installation. A checkpoint cannot interrupt an individual engine call or candidate check, so this is a soft budget rather than a hard maximum frame time. Nearby terrain preparation starts with highest priority; waiting tickets gain urgency every 120 ms so continually renewed high-priority jobs cannot starve distant terrain or decorations. Disabled world owners wait until resumed.

Terrain, trees, rocks, shrubs and grass never wait for regional road planning. Terrain workers snapshot only completed road masks, and vegetation starts with whatever masks are already available. Finishing a road chunk notifies nearby decoration/flora chunks to regenerate their clear corridors and refreshes the grass map. An update received during placement invalidates that unfinished result and queues a replacement. Thus a cold road cache cannot leave the initial terrain island surrounded by an empty, unchanging world.

Terrain remains queued in rings from the player outward. Initial spawn and explicit teleport collision neighbourhoods are built synchronously before movement resumes. The starting cave and its physical return doors are ready before play begins; later entrance searches are incremental. Finished worker results are discarded when a chunk has left the desired stream set or was already created synchronously. Ordinary base-terrain use without the production seamless worker backend retains the synchronous API and duplicate/stale queue checks.

Paths reject segments outside the chunk before subdivision, cache repeated vertex queries and yield during clipping/assembly. The terrain query service also keeps a bounded 32,768-entry cache of exact height samples shared by placement and ground interpolation. No terrain resolution, road width, density or visual quality was reduced.

Grass builds its next map into a private image. Repeated recenter requests coalesce, and outdated results are discarded. The image, world-space map origin and tile positions update together after the map is complete, keeping the old valid carpet visible while generation runs.

Synchronous generation APIs remain available for editor previews, placement tests and explicit collision-safe setup. Incremental APIs use the same deterministic seeds and geometry rules. Changes to those rules should update both paths; `tests/check_generation.gd` checks equivalent terrain/water arrays, path vertices/colours, town placement/road definitions, decoration transforms and house meshes/collisions. It also checks worker handoff and paused-owner resumption.

Profiler reports now include `generation.main_thread_slices`, `terrain.install_chunk`, active workers, queued slices, completed/stale jobs, budget and largest observed slice, plus worker task elapsed times. Worker times overlap frames and other tasks and must not be summed into main-thread frame timings. These counters reset with the game scene, so compare their changes over a recording.

Checks:

- `godot --headless --path . --script application/streaming/tests/check_generation.gd`
- `godot --headless --path . --script application/streaming/tests/check_scheduler_progress.gd`
- `godot --headless --path . --script application/streaming/tests/check_world_streaming.gd` (use an isolated `XDG_DATA_HOME` for a cold-cache test)
- `godot --headless --path . --script application/save/tests/check_save.gd`

Validation included a 30-second headless full-world capture with no frames above 100 ms, plus a Compatibility renderer smoke test. Headless FPS is not comparable to a rendered gameplay capture. Use `profile start`, follow the same route as the original report, then `profile export` to measure the remaining bottlenecks on the player's graphics hardware.

The continuity regression deliberately blocks the background search slot while checking fresh terrain, actual tree/boulder placements, shrubs/grass, and new chunks after a kilometre of movement. The scheduler regression checks that essential jobs still complete with a blocked search and that low-priority work progresses under a continuously renewed high-priority task.

Static camps, paths and settlement roots update their local positions on `InfiniteTerrain.origin_shifted`, rather than on every rendered frame. The event fires after the dynamic roots, terrain chunks and absolute origin offset have been updated. Suspended NPCs subscribe independently so their local coordinates remain correct when reactivated.

Origin regression: `godot --headless --path . --script application/streaming/tests/run_regression.gd -- application/streaming/tests/check_origin_updates.gd`. The runner loads production scene dependencies first, avoiding the existing equipment preload cycle seen when some standalone test scripts are loaded first. Use an isolated `XDG_DATA_HOME` for integration tests that create saves or road caches.

## Save and collision work

Periodic autosaves and keyboard quick saves capture an encoded point-in-time snapshot on the main thread, then use a separate save worker for JSON serialization, file writes/flushes, parsing and full verification of the temporary and previous saves. No live inventory, health, NPC dictionary or scene node is handed to that worker. Only one transaction may be in flight; periodic requests coalesce and an overlapping keyboard quick-save request reports that it was not accepted. Status changes and notices occur after the task is joined. Explicit `save_slot`, load/reload and shutdown preserve their synchronous completion contracts. Snapshot capture/encoding still costs main-thread time proportional to persisted state; it is not covered by the generation budget.

Inactive terrain bodies detach their physical shape, while retaining the most recently used exact concave shapes. The streamer limits this cache to sixteen inactive chunks in addition to the active physical neighbourhood. Visual chunk unloading releases cache ownership. Returning to a retained chunk reuses the same shape; returning after eviction rebuilds it. Seamless workers additionally expand indexed ground triangles into CPU collision faces, avoiding render-mesh readback at installation and subsequent rebuilds. These face buffers live with the bounded visual chunk set and do not lower collision resolution.

Streamed ground upload, water upload and final node/near-collision installation now pass through shared engine-operation admission. At most one admitted costly operation runs per rendered frame across terrain, incremental house surface commits and scheduled city batch uploads. The in-flight chunk guard remains set until all stages finish. Every resumed terrain stage checks that its coordinate is still desired and was not synchronously replaced. Loading-screen and explicit teleport collision setup retain their immediate safety contract.

Admission prevents several expensive operations from being combined in the same generation frame, but cannot preempt one engine call or guarantee a hard frame maximum. Profiler generation context includes `operation_max_ms` and `operation_overruns` to reveal that remaining limitation. This can increase generation latency while reducing combined per-frame spikes; compare rendered captures on the same route before claiming an FPS improvement.

Additional regressions, invoked through `tests/run_regression.gd -- <script>`:

- `application/save/tests/check_background_save.gd`: detached mutable state, request coalescing, ordering, teardown and failed writes.
- `world/terrain/tests/check_collision_cache.gd`: exact shape identity reuse, inactive physics removal, bounded eviction and actual ground after reactivation.
- `application/streaming/tests/check_staged_install.gd`: multi-frame handoff, collision installation, stale travel cancellation and operation measurements.
