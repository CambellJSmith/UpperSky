extends SceneTree # Exercise detached save snapshots and safe file transactions.

func _initialize() -> void: run.call_deferred() # Start after the scene tree is ready.

func run() -> void: # Verify live changes cannot leak into an accepted background snapshot.
    var game: Node = load("res://application/game/game.tscn").instantiate() # Use the production save hierarchy.
    var saves: SaveSystem = game.get_node("SaveSystem") # Select the real save component.
    saves.folder = "user://background-save-test" # Isolate test files from ordinary saves.
    root.add_child(game) # Finish production initialization.
    while not saves.ready_to_save: await physics_frame # Wait for a valid point-in-time snapshot.
    var record: Dictionary = LootSession.get_record("worker-snapshot", 42, true) # Persist a mutable NPC record.
    record.health.set_health(17.0) # Mark the accepted snapshot state.
    record.inventory.stacks.clear() # Make the mutable inventory fixture deterministic.
    record.inventory.try_add_item(&"coins", "Coins", 0.01, 17) # Populate worker snapshot inventory.
    assert(saves.request_save(), "Background save was not accepted") # Start the production nonblocking API.
    assert(not saves.request_save(), "Duplicate autosave was queued") # Bound in-flight transactions.
    record.health.set_health(3.0) # Mutate the live resource after snapshot capture.
    record.inventory.stacks[0].remove_quantity(15) # Mutate a live stack after snapshot capture.
    LootSession.records["worker-snapshot"].position = Vector3.ONE # Mutate the live dictionary after capture.
    var deadline: int = Time.get_ticks_msec() + 20000 # Fail rather than hang if worker completion stops.
    while saves._save_task >= 0 and Time.get_ticks_msec() < deadline: await process_frame # Let ordinary frame polling apply completion.
    assert(saves._save_task < 0, "Save worker did not finish") # Verify nonblocking completion.
    var recovered: Dictionary = saves.read_slot("current") # Read the actual installed file.
    assert(recovered.loot["worker-snapshot"].health.get_health() == 17.0, "Worker read live health") # Preserve accepted snapshot health.
    assert(recovered.loot["worker-snapshot"].inventory.stacks[0].get_quantity() == 17, "Worker read live inventory") # Preserve accepted snapshot inventory.
    assert(not recovered.loot["worker-snapshot"].has("position"), "Worker read live dictionary") # Preserve accepted snapshot dictionary contents.
    assert(saves.last_worker_us > 0, "Worker duration was not recorded") # Confirm file work completed through the worker.
    assert(saves.request_save("quick"), "Quick save was not accepted") # Start an explicit background transaction.
    assert(saves.save_slot(), "Synchronous save could not follow a worker") # Join pending work before another file transaction.
    assert(saves.read_slot("quick").loot["worker-snapshot"].health.get_health() == 3.0) # Confirm the joined quick save captured the later state.
    assert(saves.request_save(), "Teardown save was not accepted") # Leave a live task for scene cleanup.
    var folder: String = saves.folder # Preserve the file identity after the scene is freed.
    game.free() # Exercise worker joining without touching freed notices.
    assert(not SaveFileJob.read_file(folder.path_join("current.json")).is_empty()) # Verify teardown retained a completed save.
    DirAccess.make_dir_recursive_absolute(folder.path_join("blocked/current.json.tmp")) # Block the temporary file with an isolated directory.
    var bad: SaveFileJob = SaveFileJob.new(folder.path_join("blocked"), "current", {}) # Supply a deliberately unwritable file destination.
    var task: int = WorkerThreadPool.add_task(bad.run) # Exercise failure reporting from private worker code.
    WorkerThreadPool.wait_for_task_completion(task) # Join before reading the result.
    assert(not bad.error.is_empty(), "Worker failure was reported as success") # Preserve failed-save reporting.
    for name: String in ["current.json", "current.json.bak", "current.json.tmp", "quick.json", "quick.json.bak"]: # Remove isolated save artifacts.
        DirAccess.remove_absolute(folder.path_join(name)) # Clean only this regression's files.
    DirAccess.remove_absolute(folder.path_join("blocked/current.json.tmp")) # Release the blocked destination fixture.
    DirAccess.remove_absolute(folder.path_join("blocked")) # Release its isolated parent.
    DirAccess.remove_absolute(folder) # Release the empty fixture directory.
    print("PASS detached background snapshot, coalescing, synchronous ordering, scene teardown and worker write failure") # Report the covered save contracts.
    quit() # Complete the regression process.
