extends Node
class_name SaveSystem

const VERSION = 1
const MAX_FILE_BYTES = 32 * 1024 * 1024
var folder: String = "user://saves"
var ready_to_save = false
var elapsed = 0.0
var startup: Dictionary = {}
var protect_invalid_save = false
var status = "No save yet."
var _notice_label: Label
var _notice_seconds = 0.0
var _quit_save_failed = false
var _save_task: int = -1 # Bound the save system to one in-flight transaction.
var _save_job: SaveFileJob # Retain the worker and its private data until joined.
var _save_slot: String = "" # Preserve notification identity across frames.
var last_worker_us: int = 0 # Report save serialization and disk work separately.
static var requested_load = ""
static var requested_folder = ""

func _ready():
    get_tree().auto_accept_quit = false
    var layer = CanvasLayer.new()
    layer.layer = 100
    add_child(layer)
    _notice_label = Label.new()
    _notice_label.position = Vector2(24,24)
    _notice_label.add_theme_color_override("font_shadow_color",Color.BLACK)
    _notice_label.add_theme_constant_override("shadow_offset_x",2)
    _notice_label.add_theme_constant_override("shadow_offset_y",2)
    _notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(_notice_label)

func prepare() -> Dictionary:
    if not requested_folder.is_empty():
        folder = requested_folder
        requested_folder = ""
    var slot = requested_load if not requested_load.is_empty() else "current"
    requested_load = ""
    startup = read_slot(slot)
    if not startup.is_empty():
        LootSession.records = startup.loot
        WayshrineRegistry.activated = startup.shrines
    return startup

func _process(delta):
    if _save_task >= 0 and WorkerThreadPool.is_task_completed(_save_task): finish_pending_save() # Poll without blocking the gameplay thread.
    _notice_seconds = maxf(0,_notice_seconds-delta)
    if _notice_label != null: _notice_label.visible = _notice_seconds > 0
    if not ready_to_save: return
    elapsed += delta
    if elapsed >= 60.0:
        elapsed = 0.0
        if not protect_invalid_save: request_save("current") # Coalesce autosaves while a transaction is in flight.

func _unhandled_input(event):
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_F5:
            request_save("quick") # Keep quick-save disk work out of input handling.
            get_viewport().set_input_as_handled()
        elif event.keycode == KEY_F9:
            load_slot("quick")
            get_viewport().set_input_as_handled()

func _notification(what):
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        if ready_to_save and not protect_invalid_save and not _quit_save_failed:
            if not save_slot("current"):
                _quit_save_failed = true
                _show_notice("Could not save. Close again to exit without saving.",8.0)
                return
        get_tree().quit()

func snapshot() -> Dictionary:
    for npc in get_tree().get_nodes_in_group("npc"):
        if npc is Villager and npc._space == null: npc.persist_journey()
    var game = get_parent()
    var player = game.get_node("DynamicEntities/Player")
    var terrain = game.get_node("World/Terrain")
    var dungeon = game.get_node("DungeonSystem")
    var vitals = player.get_node("PlayerVitals")
    var inventory = player.get_node("PlayerInventory")
    var stacks = []
    for i in range(inventory.get_stack_count()): stacks.append(inventory.get_stack_at(i))
    var clock = get_tree().get_first_node_in_group(DayNightCycle.GROUP_NAME)
    var cities: CityTravel = game.get_node_or_null("CityTravel")
    var city_state: Dictionary = cities.snapshot() if cities != null else {}
    return {"city":city_state,"position":city_state.return_position if not city_state.is_empty() else player.global_position if dungeon._active_dungeon != null else player.water_transport.save_position(player) if is_instance_valid(player.water_transport) else terrain.local_to_world_position(player.global_position),"yaw":player.rotation.y,"pitch":player._pitch,"inventory":stacks,"equipment":String(player.get_node("PlayerEquipment").get_equipped_item_id()),"vitals":[vitals.get_health(),vitals.get_maximum_health(),vitals.get_stamina(),vitals.get_maximum_stamina(),vitals.get_mana(),vitals.get_maximum_mana(),vitals.get_experience()],"time":clock.get_time_of_day_hours(),"time_speed":clock.get_speed_multiplier(),"loot":LootSession.records,"shrines":WayshrineRegistry.activated,"starting_pair":dungeon._starting_pair,"active_pair":dungeon._active_pair}

func _can_save(slot: String) -> bool: # Share readiness checks between synchronous and background saves.
    if slot not in ["current", "quick"]: return _fail("Use current or quick as the save slot.") # Reject unsupported destinations.
    if not ready_to_save: return _fail("Wait for the world to finish loading.") # Avoid partial startup snapshots.
    var player: Node = get_parent().get_node("DynamicEntities/Player") # Read scene state only on the gameplay thread.
    if not player.is_physics_processing(): # Preserve the travel transition guard.
        status = "Wait until travel finishes before saving." # Explain why no snapshot was started.
        return false # Keep the previous slot intact.
    return true # Allow a consistent scene snapshot.

func _capture_job(slot: String) -> SaveFileJob: # Freeze mutable gameplay objects before handing off file work.
    var data: Dictionary = {"version":VERSION,"world_seed":TerrainHeightSampler.WORLD_SEED,"saved_at":Time.get_datetime_string_from_system(true),"state":SaveCodec.encode(snapshot())} # Encoding creates fresh primitive containers without shared resources.
    return SaveFileJob.new(ProjectSettings.globalize_path(folder), slot, data) # Keep worker code independent of project nodes.

func request_save(slot: String = "current") -> bool: # Start a nonblocking gameplay save without queuing duplicate snapshots.
    if _save_task >= 0: # Bound memory and prevent overlapping file rotations.
        if slot == "quick": _show_notice("Save in progress; quick save again when it finishes.") # Explain an unaccepted explicit request.
        return false # Coalesce periodic saves without capturing redundant snapshots.
    if not _can_save(slot): return false # Respect loading and travel readiness.
    _save_job = _capture_job(slot) # Capture a consistent point in time on the scene thread.
    _save_slot = slot # Remember the notification identity until completion.
    _save_task = WorkerThreadPool.add_task(_save_job.run, false, "Save game") # Move JSON, disk I/O and full validation off gameplay callbacks.
    if _save_task < 0: # Handle worker submission failure explicitly.
        _save_job = null # Release the rejected snapshot.
        return _fail("Cannot start save worker.") # Preserve the previous save.
    status = "Saving game..." # Report progress without claiming durability early.
    return true # Report acceptance rather than file completion.

func finish_pending_save() -> bool: # Join a pending transaction before explicit loading, saving or teardown.
    if _save_task < 0: return true # Avoid a pool query without a live task.
    WorkerThreadPool.wait_for_task_completion(_save_task) # Join before observing worker-owned result fields.
    _save_task = -1 # Release the consumed pool identity.
    var job: SaveFileJob = _save_job # Retain the result until the scene notification completes.
    _save_job = null # Release the detached snapshot after this call.
    return _complete_save(_save_slot, job) # Apply status and notices exclusively on the main thread.

func _complete_save(slot: String, job: SaveFileJob) -> bool: # Apply a joined transaction result to scene-owned UI.
    last_worker_us = job.duration_us # Expose worker duration separately from main-thread snapshot cost.
    if not job.error.is_empty(): return _fail(job.error) # Keep failure handling consistent across both APIs.
    protect_invalid_save = false # Resume autosaving after a verified explicit repair.
    status = "Saved: " + ProjectSettings.globalize_path(folder.path_join(slot+".json")) # Report the installed slot.
    print(status) # Preserve existing save logging.
    _show_notice("Game saved" if slot == "current" else "Quick save complete") # Notify only after installation succeeds.
    return true # Report durable success.

func save_slot(slot: String = "current") -> bool: # Retain immediate completion for explicit setup, tests and exit saves.
    finish_pending_save() # Serialize this write behind any in-flight autosave.
    if not _can_save(slot): return false # Respect scene readiness.
    var job: SaveFileJob = _capture_job(slot) # Freeze the state through the same production snapshot path.
    job.run() # Complete explicitly synchronous callers before returning.
    return _complete_save(slot, job) # Preserve the boolean durability contract.

func _exit_tree() -> void: # Prevent a save worker from outliving its owning scene.
    if _save_task >= 0: # Avoid accessing scene-owned notices during teardown.
        WorkerThreadPool.wait_for_task_completion(_save_task) # Complete the detached file transaction before releasing the owner.
        _save_task = -1 # Consume the pool identity exactly once.
        _save_job = null # Release worker-owned snapshot data after joining.

func read_slot(slot: String) -> Dictionary:
    var path = folder.path_join(slot+".json")
    var result = _read_file(path)
    if result.is_empty():
        result = _read_file(path+".bak")
        if not result.is_empty(): status = "Recovered save from backup."
        elif FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak"):
            protect_invalid_save = true
            status = "Save is damaged or incompatible; automatic saving paused to preserve it."
    return result

func _read_file(path: String) -> Dictionary: # Reuse the scene-independent verified reader.
    return SaveFileJob.read_file(path) # Keep load and write validation identical.

func _valid_state(state: Variant) -> bool: # Retain the existing validation entry point for callers.
    return SaveFileJob.valid_state(state) # Delegate pure validation to the file component.

func load_slot(slot: String = "current") -> bool:
    finish_pending_save() # Finish pending writes before reading or reloading their owner.
    if slot not in ["current","quick"]: return _fail("Use current or quick as the save slot.")
    if not ready_to_save: return _fail("Wait for the world to finish loading.")
    if read_slot(slot).is_empty(): return _fail("No usable save in that slot.")
    requested_load = slot
    requested_folder = folder
    ready_to_save = false
    get_tree().reload_current_scene.call_deferred()
    return true

func restore_player():
    var player = get_parent().get_node("DynamicEntities/Player")
    var vitals = player.get_node("PlayerVitals")
    vitals.set_maximum_health(startup.vitals[1])
    vitals.set_health(startup.vitals[0])
    vitals.set_maximum_stamina(startup.vitals[3])
    vitals.set_stamina(startup.vitals[2])
    vitals.set_maximum_mana(startup.vitals[5])
    vitals.set_mana(startup.vitals[4])
    if startup.vitals.size() >= 7: vitals.add_experience(startup.vitals[6])
    player.get_node("PlayerInventory").restore_stacks(startup.inventory)
    player.get_node("PlayerEquipment").unequip()
    if not startup.equipment.is_empty(): player.get_node("PlayerEquipment").equip_item(StringName(startup.equipment))
    player.rotation.y = startup.yaw
    player._pitch = clampf(startup.pitch,FirstPersonPlayer.MINIMUM_PITCH,FirstPersonPlayer.MAXIMUM_PITCH)
    player.get_node("Head").rotation.x = player._pitch
    get_tree().get_first_node_in_group(DayNightCycle.GROUP_NAME).set_time_of_day_hours(startup.time)
    get_tree().get_first_node_in_group(DayNightCycle.GROUP_NAME).set_speed_multiplier(startup.time_speed)

func _fail(message: String) -> bool:
    status = message
    push_warning(message)
    _show_notice(message,8.0)
    return false

func _show_notice(message: String, seconds: float = 3.0):
    if _notice_label == null: return
    _notice_label.text = message
    _notice_label.visible = true
    _notice_seconds = seconds

func finish_loading():
    ready_to_save = true
    if protect_invalid_save: _show_notice(status,12.0)
    elif not startup.is_empty(): _show_notice("Game loaded" if status != "Recovered save from backup." else status,5.0)
