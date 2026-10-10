extends RefCounted # Keep file work independent of the active scene tree.
class_name SaveFileJob # Own one detached snapshot and its serialized file transaction.

var _folder: String # Capture the destination before the worker starts.
var _slot: String # Capture the slot before the worker starts.
var _data: Dictionary # Own encoded primitives with no live gameplay objects.
var error: String = "" # Publish the result only after the task is joined.
var duration_us: int = 0 # Measure worker time separately from frame time.

func _init(destination: String, slot: String, data: Dictionary) -> void: # Transfer exclusive snapshot ownership to this job.
    _folder = destination # Retain the resolved writable destination.
    _slot = slot # Retain the requested file identity.
    _data = data # Retain the already detached state.

func run() -> void: # Serialize and verify private data away from gameplay callbacks.
    var started: int = Time.get_ticks_usec() # Begin the worker timing scope.
    error = write_file(_folder, _slot, _data) # Perform the complete recoverable file transaction.
    duration_us = Time.get_ticks_usec() - started # Publish elapsed worker time after completion.

static func write_file(folder: String, slot: String, data: Dictionary) -> String: # Return an error or an empty successful result.
    var path: String = folder.path_join(slot+".json") # Select the target and temporary file names.
    if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK: return ("Cannot create save folder.") # Ensure the destination exists before opening a file.
    var file: FileAccess = FileAccess.open(path+".tmp",FileAccess.WRITE) # Create the temporary file without truncating the current slot.
    if file == null: return ("Cannot write save file.") # Preserve the installed slot when opening fails.
    file.store_string(JSON.stringify(data)) # Serialize only the worker-owned primitive snapshot.
    file.flush() # Flush buffered data before verifying the temporary file.
    var write_error: Error = file.get_error() # Capture the write result before closing the handle.
    file.close() # Close the writer before opening the verification reader.
    if write_error != OK: return ("Save write failed; previous save retained.") # Retain the previous save after a disk write failure.
    if not read_file(path+".tmp").is_empty(): # Verify the completed temporary file before installing it.
        # Only rotate a verified previous save, retaining recovery when the main file is damaged.
        if not read_file(path).is_empty(): # Rotate only a verified previous primary into recovery storage.
            if FileAccess.file_exists(path+".bak"): DirAccess.remove_absolute(path+".bak") # Remove the previous backup only when a valid replacement exists.
            if DirAccess.rename_absolute(path,path+".bak") != OK: return ("Cannot back up previous save.") # Retain the primary when recovery rotation fails.
        if DirAccess.rename_absolute(path+".tmp",path) != OK: return ("Cannot install save; backup retained.") # Install the verified snapshot through a same-directory rename.
        return "" # Report successful atomic installation to the scene owner.
    return "Save verification failed; previous save retained." # Preserve the last usable slot on verification failure.

static func read_file(path: String) -> Dictionary: # Read and validate save files independently of gameplay nodes.
    var file: FileAccess = FileAccess.open(path,FileAccess.READ) # Open a separate reader for each private validation pass.
    if file == null or file.get_length() > SaveSystem.MAX_FILE_BYTES: return {} # Reject unavailable or oversized files before parsing.
    var parser: JSON = JSON.new() # Keep the parser private to this validation call.
    if parser.parse(file.get_as_text()) != OK: return {} # Reject invalid JSON without altering the destination.
    var parsed: Variant = parser.data # Read the validated parser result.
    if not parsed is Dictionary or parsed.get("version") != SaveSystem.VERSION or parsed.get("world_seed") != TerrainHeightSampler.WORLD_SEED or not SaveCodec.valid(parsed.get("state")): return {} # Require the supported envelope and bounded codec payload.
    var state: Variant = SaveCodec.decode(parsed.state) # Create private decoded state for semantic validation.
    if not valid_state(state): return {} # Reject structurally valid payloads with invalid gameplay state.
    return state # Return only a fully verified decoded snapshot.


static func valid_state(s: Variant) -> bool: # Validate a private decoded snapshot without scene access.
    if not s is Dictionary: return false # Reject incompatible or malformed saved state.
    for key in ["position","yaw","pitch","inventory","equipment","vitals","time","time_speed","loot","shrines","starting_pair","active_pair"]: # Validate every persisted entry before accepting the snapshot.
        if not s.has(key): return false # Reject incompatible or malformed saved state.
    if not s.position is Vector3 or not s.inventory is Array or not s.equipment is String or not s.vitals is Array or (s.vitals.size() != 6 and s.vitals.size() != 7) or not s.loot is Dictionary or not s.shrines is Dictionary: return false # Reject incompatible or malformed saved state.
    for n in [s.yaw,s.pitch,s.time,s.time_speed]+s.vitals: # Validate every persisted entry before accepting the snapshot.
        if not (n is int or n is float) or not is_finite(n): return false # Reject incompatible or malformed saved state.
    if s.time < 0 or s.time >= 24 or s.time_speed < 0 or s.time_speed > DayNightCycle.MAXIMUM_SPEED_MULTIPLIER: return false # Reject incompatible or malformed saved state.
    for i in [0,2,4]: # Validate every persisted entry before accepting the snapshot.
        if s.vitals[i+1] <= 0 or s.vitals[i] < 0 or s.vitals[i] > s.vitals[i+1]: return false # Reject incompatible or malformed saved state.
    if s.has("city"): # Validate the optional persisted gameplay field.
        if not s.city is Dictionary: return false # Reject incompatible or malformed saved state.
        if not s.city.is_empty(): # Validate the optional persisted gameplay field.
            for key in ["cell","position","yaw","return_position","return_yaw"]: # Validate every persisted entry before accepting the snapshot.
                if not s.city.has(key): return false # Reject incompatible or malformed saved state.
            if not s.city.cell is Vector2i or not s.city.position is Vector3 or not s.city.return_position is Vector3: return false # Reject incompatible or malformed saved state.
            if not s.city.position.is_finite() or not s.city.return_position.is_finite(): return false # Reject incompatible or malformed saved state.
            if not (s.city.yaw is float or s.city.yaw is int) or not (s.city.return_yaw is float or s.city.return_yaw is int): return false # Reject incompatible or malformed saved state.
            if not is_finite(s.city.yaw) or not is_finite(s.city.return_yaw): return false # Reject incompatible or malformed saved state.
            var room = s.city.get("room",{}) # Read the persisted field for semantic validation.
            if not room is Dictionary: return false # Reject incompatible or malformed saved state.
            if not room.is_empty(): # Validate the optional persisted gameplay field.
                if not room.get("house") is String or not room.house.begins_with("CityHouse_") or "/" in room.house: return false # Reject incompatible or malformed saved state.
                if not room.get("position") is Vector3 or not room.position.is_finite(): return false # Reject incompatible or malformed saved state.
    for stack in s.inventory: # Validate every persisted entry before accepting the snapshot.
        if not stack is InventoryStack: return false # Reject incompatible or malformed saved state.
    for record in s.loot.values(): # Validate every persisted entry before accepting the snapshot.
        if not record is Dictionary or not record.get("inventory") is LootStorage or not record.get("health") is HealthState: return false # Reject incompatible or malformed saved state.
        if record.has("affection") and not record.affection is AffectionState: return false # Reject incompatible or malformed saved state.
        if record.has("npc_id") and not record.npc_id is String: return false # Reject incompatible or malformed saved state.
        if record.has("npc_aggressors"): # Validate the optional persisted gameplay field.
            if not record.npc_aggressors is Dictionary: return false # Reject incompatible or malformed saved state.
            for target in record.npc_aggressors: # Validate every persisted entry before accepting the snapshot.
                if not target is String or not record.npc_aggressors[target] is bool: return false # Reject incompatible or malformed saved state.
        if record.has("npc_affection"): # Validate the optional persisted gameplay field.
            if not record.npc_affection is Dictionary: return false # Reject incompatible or malformed saved state.
            for target in record.npc_affection: # Validate every persisted entry before accepting the snapshot.
                if not target is String or not record.npc_affection[target] is AffectionState: return false # Reject incompatible or malformed saved state.
        if record.has("position") and not record.position is Vector3: return false # Reject incompatible or malformed saved state.
    for key in s.shrines: # Validate every persisted entry before accepting the snapshot.
        var shrine = s.shrines[key] # Read the persisted field for semantic validation.
        if not key is Vector2i or not shrine is Dictionary or shrine.get("id") != key or not shrine.get("position") is Vector3 or not shrine.get("landing") is Vector3 or not shrine.get("title") is String or not (shrine.get("yaw") is float or shrine.get("yaw") is int): return false # Reject incompatible or malformed saved state.
    return (s.starting_pair == null or s.starting_pair is DungeonPairDefinition) and (s.active_pair == null or s.active_pair is DungeonPairDefinition) # Require valid optional dungeon identities.

