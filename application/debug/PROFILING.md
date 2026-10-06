# Capture a gameplay performance report

Open the developer console with the grave/tilde key, enter `profile start`, then close the console and play through the slow areas for about 30–90 seconds. Include walking into new terrain, towns, combat or shrine travel when those trigger the problem. Reopen the console and enter `profile export`. It stops recording and writes a JSON file; the console prints the complete path. Send that file for analysis. `profile folder` opens its containing folder.

Commands:

- `profile start`: begin a fresh recording; replaces the previous in-memory capture.
- `profile stop`: stop and retain the capture without exporting.
- `profile export`: stop if necessary and save a new JSON report.
- `profile status`: show capture state, duration and frame/marker counts.
- `profile mark entering a town`: label a moment and its position/counters.
- `profile folder`: open the report folder after export.

`profiler` is an alias for `profile`. The folder is `user://performance_reports` in Godot's UpperSky user data directory; use the displayed path rather than assuming a platform-specific location.

The report includes wall frame times, averages, p50/p95/p99, spike counts, the 40 longest frames with system breakdowns and context, hardware/renderer/settings, rendering/physics/memory counters, NPC counts, streaming counts and queue sizes, markers, and half-second timeline samples. Timeline samples contain cumulative system timings; differences between samples show work in each interval. Backend render CPU/GPU measurements are included when available, otherwise null.

Thirty-nine explicit CPU scopes cover world generation and streaming, terrain/water meshes, path connections, settlements, vegetation and grass updates, camps, biomes, wayshrines, NPC spawn/animation/physics/cave pursuit, player physics/arms and loot/shrine UI. Inclusive time contains nested calls; self time excludes other instrumented children, avoiding double-counting. Scope wrappers preserve synchronous early returns and return values. This does not capture every function, allocation or a call stack; add targeted scopes after analysing the first recording.

Off by default: no recorder callback, scope allocations, timers or GPU measurement while idle. Wrapped calls only take an inactive flag branch and forward to their original implementation. During recording there is measurement overhead. Recorder callback cost is included separately, but timing-hook overhead and backend measurement overhead are not fully isolated. Wall frame time includes vsync and other waits, so it is not identical to CPU work. Engine/backend counters can lag a frame and GPU metrics may be unavailable on Compatibility or headless rendering.

Memory limits: 60,000 frames, 1,800 half-second samples (roughly 15 minutes), 256 markers and 40 detailed frames. Reaching a frame/sample limit automatically stops while retaining data for export. Report generation occurs after capture stops. Export checks folder creation, file opening and write errors. Capture state is cleared by a new start or scene teardown; exported files persist.

Checks: `application/debug/tests/check_profiler.gd` and `application/debug/tests/check_profiler_console.gd` with `godot --headless --path . --script <path>`.

World generation now runs through background terrain jobs and shared main-thread slices. Look for `generation.main_thread_slices`, `terrain.install_chunk` and the context `generation` counters. Worker task elapsed times overlap frames and should be analysed separately. The scheduler budget is a soft target; indivisible engine calls can exceed it.

CPU scope stacks belong exclusively to the main thread. Shared procedural samplers also run on workers; their callback scopes return inactive tokens there, and worker durations remain in the scheduler generation counters. This prevents overlapping worker/main-thread calls from corrupting nesting or inflating main-thread CPU totals. Scope tokens are unique across recordings, so a callback finishing after stop/start cannot close a scope in the new recording. Strict nesting checks remain enabled within a capture.
