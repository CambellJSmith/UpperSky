extends TerrainWaterLevelSampler
class_name SeamlessTerrainWaterLevelSampler

# Keep geological lakes level. Terrain can blend between provinces, water cannot.
# Globally aligned cell centres give mesh generation and gameplay identical levels.
func sample_water_level(world_x: float, world_z: float) -> float:
    var spacing := TerrainConfiguration.CHUNK_SIZE / float(TerrainConfiguration.WATER_RESOLUTION - 1)
    var point := (Vector2(world_x, world_z) / spacing).floor() * spacing + Vector2.ONE * spacing * 0.5
    var geological_level := super.sample_water_level(point.x, point.y)
    return BiomeProfile.water_height(point, geological_level)
