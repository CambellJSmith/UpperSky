# Planned Water

Water is a world-generation blueprint, rather than a second height-noise field. `WaterBodyPlan` defines body footprints, elevations, stable IDs and river connections before final terrain is resolved. `SeamlessTerrainHeightSampler` applies containing shores and river beds after geological, biome and mountain shaping.

The infinite-world boundary contract is deliberately closed regional watersheds. Lakes and lagoons are permanent closed sinks; spring-fed river reaches descend through explicit cascades into a terminal pool. Regional borders remain dry, so loading an arbitrary subset of chunks cannot invent a new outlet or change an upstream lake. The separate starting lake keeps the original dry origin and a temperate shoreline start. Water supply is an authored steady-state generation rule. There is no per-frame volume simulation, global ocean-connectivity search, or Priority-Flood reconstruction of arbitrary terrain depressions.

Each sampler or worker retains its own immutable provincial blueprint reference. Shared biome-cache locking happens when changing provinces, rather than for every planned terrain vertex. Body strings are allocated for metadata queries, while terrain shaping and mesh generation use lightweight elevation and footprint methods.

Water meshes use the final ground grid and diagonal. Workers pass their completed ground buffers into the water builder, avoiding duplicate terrain sampling. Each surface triangle is clipped against both the planned footprint and final ground clearance. Waterfall curtains are separate geometry and only span endpoints inside their connected upstream and downstream reaches.

`SeamlessInfiniteTerrain.get_water_sample_at(absolute_xz)` returns:

| Field | Wet result | Dry result |
| --- | --- | --- |
| `present` | `true` | `false` |
| `surface_height` | Actual calm reach elevation | Negative infinity |
| `ground_height` | Interpolated rendered triangle | Interpolated rendered triangle |
| `depth` | Positive ground clearance | Zero |
| `body_id` | Stable watershed/reach ID | Empty string |
| `downstream_id` | Next reach, or empty for a sink | Empty string |
| `flow` | Downstream direction, or zero for a sink | Zero |

Swimming, underwater effects and corpse water behaviour read the complete production sample. Corpses above a lake are not treated as immersed, and currents follow the planned channel.

`has_water_at` delegates to this contract, with a cheap rejection for points far outside footprints. The compatibility `get_water_level_at` supplies the **planned** body elevation, including dry banks inside a footprint, for conservative vegetation and placement clearance. It returns negative infinity outside planned footprints. Use `present` or `has_water_at` to establish actual water occupancy; an elevation alone does not imply water.

All query coordinates are absolute world coordinates. Origin rebasing only changes scene transforms. Generation revision is recorded in saves; older overworld player positions are raised above new terrain or water if necessary, while inventory, vitals and interior coordinates are retained. Road and ferry caches use new versions because containing shores change terrain.

Regression checks cover explicit dry space below hypothetical water altitude, downhill body connections, flat water, exact mesh/query occupancy, wet chunk seams, worker buffer parity, load order, reloads, origin rebasing, and the reported overhead spawn-water bug.
