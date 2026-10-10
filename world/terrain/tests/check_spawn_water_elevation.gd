extends SceneTree # Prevent full-height geological water from hovering above the lowered starting terrain.

func _initialize() -> void: run.call_deferred() # Begin after the scene tree is available.

func run() -> void: # Exercise the reported starting-region mismatch through production meshes and gameplay queries.
    var terrain: SeamlessInfiniteTerrain = SeamlessInfiniteTerrain.new() # Use the production flat-water query path.
    terrain._height_sampler = SeamlessTerrainHeightSampler.new() # Preserve the existing terrain height field.
    terrain._water_level_sampler = SeamlessTerrainWaterLevelSampler.new() # Use corrected cell-aligned water selection.
    var builder: SeamlessTerrainWaterMeshBuilder = SeamlessTerrainWaterMeshBuilder.new(terrain._height_sampler, terrain._water_level_sampler, null) # Exercise real water clipping without a rendering material.
    for point: Vector2 in [Vector2.ZERO, Vector2(264, 184), Vector2(512, 0), Vector2(-256, 128), Vector2(128, -256)]: # Cover the reproduced failure and signed starting-region coordinates.
        var ground: float = terrain.get_height_at(point) # Read the unchanged low terrain surface.
        var water: float = terrain.get_water_level_at(point) # Read the corrected cell's horizontal water level.
        assert(water < ground and not terrain.has_water_at(point), "Geological water still floats above starting land") # Keep the formerly overflooded starting terrain dry.
    assert(is_equal_approx(terrain.get_height_at(Vector2(264, 184)), -2.95394826217793)) # Preserve the reproduced terrain height instead of raising the land to mask the bug.
    for cell: Vector2i in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]: # Cover meshes surrounding the world origin.
        assert(builder.build_chunk_arrays(cell).is_empty(), "Starting chunk emitted overhead water geometry") # Exclude the old high water sheet from actual generated mesh buffers.
    var sampler: TerrainWaterLevelSampler = TerrainWaterLevelSampler.new() # Inspect ordinary geological band selection independently of biome overrides.
    var unchanged: Dictionary[Vector2, float] = {Vector2(1408, 0): 340.0, Vector2(2048, 2048): 340.0, Vector2(-2048, 2048): 340.0, Vector2(2048, -2048): 340.0, Vector2(32768, -32768): 570.0, Vector2(-65536, 65536): 340.0} # Retain known pre-fix water levels beyond the starting transition.
    for point: Vector2 in unchanged.keys(): # Check distant positive and negative world coordinates.
        assert(is_equal_approx(sampler.sample_water_level(point.x, point.y), unchanged[point]), "Distant geological water changed") # Restrict the correction to terrain's starting-region transition.
    var river: Dictionary = BiomeProfile.region(Vector2i(-1, 0)) # Preserve authored biome river reaches.
    for offset: float in [-600.0, 0.0, 600.0]: # Visit each flat river reach away from the spawn blend.
        var point: Vector2 = river.centre + Vector2(0, offset) # Resolve the authored river centerline.
        var expected: float = river.sea + (64.0 if offset < -320.0 else (32.0 if offset < 320.0 else 0.0)) # Preserve the established cascade levels.
        assert(is_equal_approx(terrain.get_water_level_at(point), expected)) # Keep biome-specific water elevations intact.
    terrain.free() # Release cached terrain and water queries.
    print("PASS no overhead spawn water, dry gameplay queries, unchanged terrain, distant levels and authored river reaches") # Report regression coverage.
    quit() # Complete the regression process.
