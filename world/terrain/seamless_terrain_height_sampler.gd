extends TerrainHeightSampler # Reuses the complete deterministic geological terrain generator while replacing only its discontinuous local-water profile.
class_name SeamlessTerrainHeightSampler # Supplies terrain heights shaped against the same continuous water elevation used by rendering and gameplay.

func _get_local_water_level(regional_height: float) -> float: # Replaces hard water-tier selection with the shared continuous geological water profile.
    return TerrainWaterProfile.get_continuous_level(regional_height) # Keeps coast grading and underwater shaping synchronized with the seamless rendered water surface.
