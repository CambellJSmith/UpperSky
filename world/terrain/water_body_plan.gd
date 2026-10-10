extends RefCounted # Represents an immutable procedural watershed blueprint without scene ownership.
class_name WaterBodyPlan # Exposes the shared body planner to terrain, workers and gameplay.

# Each province is a closed watershed: lakes are terminal sinks, not implicit oceans.
# River reaches have explicit downhill connections and spring-fed upstream caps.
# Dry provincial borders make the infinite-world drainage contract independent of chunk order.
const GENERATION_VERSION: int = 2 # Identifies the basin terrain revision for save relocation.
const GRID_SPACING: float = TerrainConfiguration.CHUNK_SIZE / float(TerrainConfiguration.CHUNK_RESOLUTION - 1) # Matches the exact rendered ground vertex spacing.
const BANK_GUARD_WIDTH: float = GRID_SPACING * 2.0 # Keeps containing banks wider than one ground triangle.
const SHORE_WIDTH: float = 48.0 # Grades a containing bank around each body footprint.
const SPAWN_DRY_RADIUS: float = 1500.0 # Protects the lowered starting terrain from planned water.

const STARTING_LAKE_CENTRE: Vector2 = Vector2(2208.0, 3520.0) # Places a contained teaching lake in the temperate starting margin.
const STARTING_LAKE_RADIUS: float = 240.0 # Separates the starting basin from the regional ice watershed.
const STARTING_LAKE_LEVEL: float = 320.0 # Defines the calm starting basin before detailed terrain generation.

static func _is_starting_lake(point: Vector2) -> bool: # Identifies the starting basin and its containing shore influence.
    return point.distance_squared_to(STARTING_LAKE_CENTRE) < pow(STARTING_LAKE_RADIUS + SHORE_WIDTH * 2.0, 2.0) # Keeps the starting blueprint separate from neighbouring watersheds.

var _region_cell: Vector2i = Vector2i(2147483647, 2147483647) # Marks the private provincial cache as initially invalid.
var _biome_definition: Dictionary = {} # Retains one immutable provincial blueprint per sampler or worker.

func _biome_at(point: Vector2) -> Dictionary: # Avoids locking the shared provincial cache at every ground vertex.
    var cell: Vector2i = Vector2i((point / BiomeProfile.REGION_SIZE).floor()) # Selects deterministic provincial ownership.
    if cell != _region_cell: # Refreshes only when crossing provincial boundaries.
        _region_cell = cell # Records the privately cached province.
        _biome_definition = BiomeProfile.region(cell) # Acquires the seed-derived blueprint once per region transition.
    return _biome_definition # Reuses the immutable blueprint without shared synchronization.

func surface_height(point: Vector2) -> float: # Samples the shared planned elevation without allocating body metadata.
    return surface_height_at(point, _biome_at(point)) # Reuses the worker-owned provincial blueprint.

static func surface_height_at(point: Vector2, biome: Dictionary) -> float: # Resolves calm lake and reach elevations independently of ground detail.
    if _is_starting_lake(point): # Selects the authored starting watershed.
        return STARTING_LAKE_LEVEL # Shares its calm elevation with terrain and gameplay.
    var level: float = float(biome.sea) # Reads the lake or terminal-pool elevation.
    if int(biome.kind) == BiomeProfile.Kind.RIVER_VALLEY: # Selects the explicit cascade profile.
        var z: float = point.y - Vector2(biome.centre).y # Locates the sample along the planned river.
        level += BiomeProfile.WATERFALL_DROP * (2.0 if z < -320.0 else (1.0 if z < 320.0 else 0.0)) # Connects reaches with strictly descending drops.
    return level # Returns the authoritative planned surface.

func definition(point: Vector2) -> Dictionary: # Samples body metadata through the private provincial cache.
    return definition_at(point, _biome_at(point)) # Delegates to the deterministic stateless implementation.

func boundary(point: Vector2) -> float: # Samples occupancy without allocating metadata or locking per vertex.
    return boundary_at(point, _biome_at(point)) # Shares the same footprint as detached static queries.

func shape(point: Vector2, original: float) -> float: # Resolves final ground using the worker-owned blueprint cache.
    return shape_height(point, original, _biome_at(point)) # Keeps final terrain identical across main and worker paths.

static func boundary_at(point: Vector2, biome_definition: Dictionary = {}) -> float: # Samples occupancy without allocating body metadata for terrain vertices.
    if _is_starting_lake(point): # Resolves the separate contained starting basin.
        return STARTING_LAKE_RADIUS - point.distance_to(STARTING_LAKE_CENTRE) # Supplies its explicit footprint before applying regional spawn exclusion.
    var biome: Dictionary = BiomeProfile.region_at(point) if biome_definition.is_empty() else biome_definition # Reuses the bounded deterministic provincial cache.
    var local: Vector2 = point - Vector2(biome.centre) # Measures position relative to the planned basin.
    var boundary: float = 1100.0 - local.length() # Defines a contained regional lake footprint.
    if int(biome.kind) == BiomeProfile.Kind.RIVER_VALLEY: # Replaces the lake footprint with a capped river corridor.
        boundary = minf(120.0 - absf(local.x - BiomeProfile.river_x(local.y, float(biome.phase))), 1050.0 - absf(local.y)) # Bounds the source, banks and terminal sink.
    return minf(boundary, point.length() - SPAWN_DRY_RADIUS) # Leaves the starting province dry.

static func definition_at(point: Vector2, biome_definition: Dictionary = {}) -> Dictionary: # Resolves body metadata from the world seed and provincial coordinates.
    var cell: Vector2i = Vector2i((point / BiomeProfile.REGION_SIZE).floor()) # Assigns negative and positive coordinates to deterministic provinces.
    var biome: Dictionary = BiomeProfile.region(cell) if biome_definition.is_empty() else biome_definition # Reuses the seed-derived provincial blueprint.
    var local: Vector2 = point - Vector2(biome.centre) # Measures position relative to the planned basin centre.
    var starting_lake: bool = _is_starting_lake(point) # Selects the explicitly planned starting body.
    var kind: int = BiomeProfile.Kind.TEMPERATE if starting_lake else int(biome.kind) # Preserves a temperate shoreline start.
    var reach: int = 0 # Starts with a closed lake rather than an implicit drainage connection.
    var level: float = surface_height_at(point, biome) # Reads the shared lake or reach elevation.
    var boundary: float = boundary_at(point, biome) # Reads the shared contained footprint.
    var flow: Vector2 = Vector2.ZERO # Leaves closed lakes without downstream flow.
    if kind == BiomeProfile.Kind.RIVER_VALLEY: # Resolves the connected river reach identity.
        reach = 0 if local.y < -320.0 else (1 if local.y < 320.0 else 2) # Selects the planned cascade reach.
        var tangent_x: float = 0.33 * cos(local.y * 0.0022 + float(biome.phase)) + 0.1785 * cos(local.y * 0.0051 + float(biome.phase) * 1.7) # Differentiates the authored channel centreline.
        flow = Vector2(tangent_x, 1.0).normalized() if local.y < 800.0 else Vector2.ZERO # Follows the channel into the closed terminal pool.
    var body_id: String = "starting_lake" if starting_lake else "watershed:%d:%d:reach:%d" % [cell.x, cell.y, reach] # Names bodies by stable province and reach coordinates.
    var downstream_id: String = "watershed:%d:%d:reach:%d" % [cell.x, cell.y, reach + 1] if kind == BiomeProfile.Kind.RIVER_VALLEY and reach < 2 else "" # Connects upstream reaches and explicitly terminates closed sinks.
    return {"body_id": body_id, "downstream_id": downstream_id, "surface_height": level, "boundary": boundary, "flow": flow, "kind": kind, "reach": reach, "region": cell} # Returns one plan shared by final terrain and water consumers.

static func shape_height(point: Vector2, original: float, biome_definition: Dictionary = {}) -> float: # Resolves terrain around the planned basin after biome shaping.
    var boundary: float = boundary_at(point, biome_definition) # Rejects distant terrain before allocating full body metadata.
    if boundary < -SHORE_WIDTH: # Leaves terrain outside the shore influence unchanged.
        return original # Preserves geological terrain away from planned bodies.
    var biome: Dictionary = BiomeProfile.region_at(point) if biome_definition.is_empty() else biome_definition # Resolves the blueprint only within shore influence.
    var level: float = surface_height_at(point, biome) # Reads planned elevation without allocating identity metadata.
    if _is_starting_lake(point): # Carves the starting basin directly from its blueprint.
        var rim: float = level + 4.0 # Grades a gentle dry shore as part of the authored starting basin.
        var bed: float = level - 8.0 # Creates shallow permanent water supplied by the starting watershed.
        if boundary >= BANK_GUARD_WIDTH: # Grades the inner bank after the dry containing strip.
            return lerpf(rim, bed, smoothstep(BANK_GUARD_WIDTH, SHORE_WIDTH * 2.0, boundary)) # Avoids a discontinuity between shore and carved floor.
        return lerpf(original, rim, smoothstep(-SHORE_WIDTH, -BANK_GUARD_WIDTH, boundary)) # Keeps both sides of the footprint dry at ground-grid precision.
    var target: float = original # Reads the original terrain before applying containment.
    if boundary < SHORE_WIDTH * 2.0: # Grades the containing shore before entering the basin interior.
        var bank_level: float = surface_height_at(point - Vector2(0.0, BANK_GUARD_WIDTH), biome) if int(biome.kind) == BiomeProfile.Kind.RIVER_VALLEY else level # Keeps banks above the upstream reach beside waterfall lips.
        var rim: float = maxf(original, bank_level + 4.0) # Keeps the entire footprint boundary above planned water.
        if boundary >= BANK_GUARD_WIDTH: # Blends the protected inner bank into preserved terrain.
            return lerpf(rim, original, smoothstep(BANK_GUARD_WIDTH, SHORE_WIDTH * 2.0, boundary)) # Keeps interior islands and shoals without an open water edge.
        return lerpf(original, rim, smoothstep(-SHORE_WIDTH, -BANK_GUARD_WIDTH, boundary)) # Protects both sides of the boundary from triangle interpolation leaks.
    if int(biome.kind) == BiomeProfile.Kind.RIVER_VALLEY: # Carves only the planned river interior.
        # The plunge-pool bed drops before each lip, leaving space beneath the explicit curtain.
        var local_z: float = point.y - Vector2(biome.centre).y # Locates the river position relative to its planned cascades.
        var bed: float = BiomeProfile.river_level(local_z + 24.0, float(biome.sea)) - 7.0 # Places the plunge bed below the downstream reach.
        target = minf(original, bed) # Keeps the channel below its planned water surface.
    return lerpf(original, target, smoothstep(SHORE_WIDTH, SHORE_WIDTH * 2.0, boundary)) # Blends river carving into the containing banks.

static func interpolate(values: PackedFloat32Array, fraction: Vector2) -> float: # Interpolates the same diagonal used by final ground triangles.
    if fraction.x + fraction.y <= 1.0: # Selects the upper ground triangle.
        return values[0] + fraction.x * (values[1] - values[0]) + fraction.y * (values[2] - values[0]) # Evaluates its linear surface at the query point.
    return values[3] + (1.0 - fraction.y) * (values[1] - values[3]) + (1.0 - fraction.x) * (values[2] - values[3]) # Evaluates the lower ground triangle at the query point.
