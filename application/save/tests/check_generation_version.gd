extends SceneTree # Checks world-generation save metadata without instantiating gameplay scenes.

func _initialize() -> void: # Validates legacy and current save envelopes through the production file path.
    var state: Dictionary = {"position": Vector3(264.0, -100.0, 184.0), "yaw": 0.0, "pitch": 0.0, "inventory": [], "equipment": "", "vitals": [100.0, 100.0, 100.0, 100.0, 100.0, 100.0], "time": 12.0, "time_speed": 1.0, "loot": {}, "shrines": {}, "starting_pair": null, "active_pair": null} # Supplies a complete valid snapshot with an old low exterior position.
    var data: Dictionary = {"version": SaveSystem.VERSION, "world_seed": TerrainHeightSampler.WORLD_SEED, "state": SaveCodec.encode(state)} # Recreates the legacy envelope without generation metadata.
    var folder: String = "user://generation-version-test-" + str(Time.get_ticks_usec()) # Isolates test saves from real player progress.
    assert(SaveFileJob.write_file(folder, "legacy", data).is_empty()) # Requires successful legacy file verification and installation.
    var legacy: Dictionary = SaveFileJob.read_file(folder.path_join("legacy.json")) # Reads the legacy envelope through production validation.
    assert(legacy.generation_version == 1 and legacy.position == state.position and legacy.vitals == state.vitals) # Preserves gameplay progress while marking terrain migration.
    data.generation_version = WaterBodyPlan.GENERATION_VERSION # Identifies current-generation terrain.
    assert(SaveFileJob.write_file(folder, "current", data).is_empty()) # Requires current generation file verification.
    assert(SaveFileJob.read_file(folder.path_join("current.json")).generation_version == WaterBodyPlan.GENERATION_VERSION) # Round-trips the generation marker.
    for invalid: Variant in [-1, 1.5, "bad", WaterBodyPlan.GENERATION_VERSION + 1]: # Checks malformed and incompatible generation metadata.
        data.generation_version = invalid # Corrupts only the optional generation field.
        assert(not SaveFileJob.write_file(folder, "invalid", data).is_empty()) # Rejects incompatible snapshots before installation.
    print("PASS legacy save progress retained, current generation round-trip and incompatible generation rejection") # Reports compatibility coverage.
    quit() # Completes the regression process.
