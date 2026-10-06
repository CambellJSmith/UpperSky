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
    _notice_seconds = maxf(0,_notice_seconds-delta)
    if _notice_label != null: _notice_label.visible = _notice_seconds > 0
    if not ready_to_save: return
    elapsed += delta
    if elapsed >= 60.0:
        elapsed = 0.0
        if not protect_invalid_save: save_slot("current")

func _unhandled_input(event):
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_F5:
            save_slot("quick")
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
    var game = get_parent()
    var player = game.get_node("DynamicEntities/Player")
    var terrain = game.get_node("World/Terrain")
    var dungeon = game.get_node("DungeonSystem")
    var vitals = player.get_node("PlayerVitals")
    var inventory = player.get_node("PlayerInventory")
    var stacks = []
    for i in range(inventory.get_stack_count()): stacks.append(inventory.get_stack_at(i))
    var clock = get_tree().get_first_node_in_group(DayNightCycle.GROUP_NAME)
    return {"position":player.global_position if dungeon._active_dungeon != null else terrain.local_to_world_position(player.global_position),"yaw":player.rotation.y,"pitch":player._pitch,"inventory":stacks,"equipment":String(player.get_node("PlayerEquipment").get_equipped_item_id()),"vitals":[vitals.get_health(),vitals.get_maximum_health(),vitals.get_stamina(),vitals.get_maximum_stamina(),vitals.get_mana(),vitals.get_maximum_mana(),vitals.get_experience()],"time":clock.get_time_of_day_hours(),"time_speed":clock.get_speed_multiplier(),"loot":LootSession.records,"shrines":WayshrineRegistry.activated,"starting_pair":dungeon._starting_pair,"active_pair":dungeon._active_pair}

func save_slot(slot: String = "current") -> bool:
    if slot not in ["current","quick"]: return _fail("Use current or quick as the save slot.")
    if not ready_to_save: return _fail("Wait for the world to finish loading.")
    var player = get_parent().get_node("DynamicEntities/Player")
    if not player.is_physics_processing():
        status = "Wait until travel finishes before saving."
        return false
    var data = {"version":VERSION,"world_seed":TerrainHeightSampler.WORLD_SEED,"saved_at":Time.get_datetime_string_from_system(true),"state":SaveCodec.encode(snapshot())}
    var path = folder.path_join(slot+".json")
    if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK: return _fail("Cannot create save folder.")
    var file = FileAccess.open(path+".tmp",FileAccess.WRITE)
    if file == null: return _fail("Cannot write save file.")
    file.store_string(JSON.stringify(data))
    file.flush()
    var error = file.get_error()
    file.close()
    if error != OK: return _fail("Save write failed; previous save retained.")
    if not _read_file(path+".tmp").is_empty():
        # Only rotate a verified previous save, retaining recovery when the main file is damaged.
        if not _read_file(path).is_empty():
            if FileAccess.file_exists(path+".bak"): DirAccess.remove_absolute(path+".bak")
            if DirAccess.rename_absolute(path,path+".bak") != OK: return _fail("Cannot back up previous save.")
        if DirAccess.rename_absolute(path+".tmp",path) != OK: return _fail("Cannot install save; backup retained.")
        protect_invalid_save = false
        status = "Saved: "+ProjectSettings.globalize_path(path)
        print(status)
        _show_notice("Game saved" if slot == "current" else "Quick save complete")
        return true
    return _fail("Save verification failed; previous save retained.")

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

func _read_file(path: String) -> Dictionary:
    var file = FileAccess.open(path,FileAccess.READ)
    if file == null or file.get_length() > MAX_FILE_BYTES: return {}
    var parser = JSON.new()
    if parser.parse(file.get_as_text()) != OK: return {}
    var parsed = parser.data
    if not parsed is Dictionary or parsed.get("version") != VERSION or parsed.get("world_seed") != TerrainHeightSampler.WORLD_SEED or not SaveCodec.valid(parsed.get("state")): return {}
    var state = SaveCodec.decode(parsed.state)
    if not _valid_state(state): return {}
    return state

func _valid_state(s) -> bool:
    if not s is Dictionary: return false
    for key in ["position","yaw","pitch","inventory","equipment","vitals","time","time_speed","loot","shrines","starting_pair","active_pair"]:
        if not s.has(key): return false
    if not s.position is Vector3 or not s.inventory is Array or not s.equipment is String or not s.vitals is Array or (s.vitals.size() != 6 and s.vitals.size() != 7) or not s.loot is Dictionary or not s.shrines is Dictionary: return false
    for n in [s.yaw,s.pitch,s.time,s.time_speed]+s.vitals:
        if not (n is int or n is float) or not is_finite(n): return false
    if s.time < 0 or s.time >= 24 or s.time_speed < 0 or s.time_speed > DayNightCycle.MAXIMUM_SPEED_MULTIPLIER: return false
    for i in [0,2,4]:
        if s.vitals[i+1] <= 0 or s.vitals[i] < 0 or s.vitals[i] > s.vitals[i+1]: return false
    for stack in s.inventory:
        if not stack is InventoryStack: return false
    for record in s.loot.values():
        if not record is Dictionary or not record.get("inventory") is LootStorage or not record.get("health") is HealthState: return false
        if record.has("affection") and not record.affection is AffectionState: return false
        if record.has("position") and not record.position is Vector3: return false
    for key in s.shrines:
        var shrine = s.shrines[key]
        if not key is Vector2i or not shrine is Dictionary or shrine.get("id") != key or not shrine.get("position") is Vector3 or not shrine.get("landing") is Vector3 or not shrine.get("title") is String or not (shrine.get("yaw") is float or shrine.get("yaw") is int): return false
    return (s.starting_pair == null or s.starting_pair is DungeonPairDefinition) and (s.active_pair == null or s.active_pair is DungeonPairDefinition)

func load_slot(slot: String = "current") -> bool:
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
