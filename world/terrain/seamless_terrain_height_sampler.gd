extends TerrainHeightSampler # Reuses the complete deterministic geological terrain generator while replacing only its discontinuous local-water profile.
class_name SeamlessTerrainHeightSampler # Supplies terrain heights shaped against the same continuous water elevation used by rendering and gameplay.

func _get_local_water_level(regional_height: float) -> float: # Replaces hard water-tier selection with the shared continuous geological water profile.
    return TerrainWaterProfile.get_continuous_level(regional_height) # Keeps coast grading and underwater shaping synchronized with the seamless rendered water surface.

func sample_height(world_x: float, world_z: float) -> float:
    var point := Vector2(world_x, world_z)
    var height := BiomeProfile.height(point, super.sample_height(world_x, world_z))
    return height + rocky_mountain_uplift(point)

static func rocky_mountain_uplift(point: Vector2) -> float:
    # Compact ranges fill the temperate margins between broad biome centres.
    # Absolute coordinates keep workers, physics and adjacent chunks identical.
    var biome := BiomeProfile.region_at(point)
    var local: Vector2 = (point - biome.centre).rotated(biome.phase)
    var uplift := 0.0
    for index in range(3):
        var summit := Vector2(1720.0, (float(index) - 1.0) * 540.0)
        var offset := local - summit
        var radius := Vector2(offset.x / 620.0, offset.y / 780.0).length()
        var shoulder := maxf(0.0, 1.0 - radius)
        if shoulder <= 0.0: continue
        var angle := atan2(offset.y, offset.x)
        var ridge := 0.82 + 0.18 * cos(angle * 5.0 + biome.phase + float(index))
        var height := (1900.0 + float(index) * 240.0) * pow(shoulder, 1.25) * ridge
        uplift = maxf(uplift, height)
    # Leave the initial province gentle and the ice/river/volcano cores intact.
    var cell_local: Vector2 = point - Vector2(Vector2i(floori(point.x / BiomeProfile.REGION_SIZE), floori(point.y / BiomeProfile.REGION_SIZE))) * BiomeProfile.REGION_SIZE
    var edge_distance := minf(minf(cell_local.x, cell_local.y), minf(BiomeProfile.REGION_SIZE - cell_local.x, BiomeProfile.REGION_SIZE - cell_local.y))
    return uplift * smoothstep(0.0, 280.0, edge_distance) * smoothstep(1000.0, 1500.0, point.length()) * (1.0 - BiomeProfile.weight(point, biome))
