extends RefCounted
class_name SaveCodec

static func encode(value):
    if value is Vector3: return {"type":"v3", "value":[value.x,value.y,value.z]}
    if value is Vector2i: return {"type":"v2i", "value":[value.x,value.y]}
    if value is HealthState: return {"type":"health", "value":[value.get_health(),value.get_maximum_health()]}
    if value is AffectionState: return {"type":"affection", "value":value.get_score()}
    if value is InventoryStack:
        return {"type":"stack", "value":[String(value.get_item_id()),value.get_display_name(),value.get_unit_weight(),value.get_quantity(),value.get_category()]}
    if value is LootStorage: return {"type":"storage", "value":encode(value.stacks)}
    if value is DungeonPairDefinition:
        return {"type":"pair", "value":encode([str(value.pair_id),value.region_coordinate,str(value.dungeon_seed),value.endpoint_a_world_position,value.endpoint_b_world_position,value.endpoint_a_yaw,value.endpoint_b_yaw])}
    if value is Dictionary:
        var entries = []
        for key in value: entries.append([encode(key),encode(value[key])])
        return {"type":"dictionary", "value":entries}
    if value is Array:
        var result = []
        for item in value: result.append(encode(item))
        return result
    return value

static func valid(value, depth: int = 0) -> bool:
    if depth > 24: return false
    if value is float: return is_finite(value)
    if value is String: return value.length() <= 4096
    if value == null or value is bool or value is int: return true
    if value is Array:
        if value.size() > 100000: return false
        for item in value:
            if not valid(item,depth+1): return false
        return true
    if not value is Dictionary or value.size() != 2 or not value.has("type") or not value.has("value"): return false
    var v = value.value
    if not valid(v,depth+1): return false
    match value.type:
        "v3", "v2i", "health":
            var count = 3 if value.type == "v3" else 2
            if not v is Array or v.size() != count: return false
            for n in v:
                if not (n is float or n is int) or absf(n) > 1e12: return false
            return value.type != "health" or (v[1] > 0 and v[0] >= 0 and v[0] <= v[1])
        "affection": return (v is float or v is int) and v >= 0 and v <= 200
        "stack":
            return v is Array and v.size() == 5 and v[0] is String and not v[0].is_empty() and v[1] is String and (v[2] is float or v[2] is int) and v[2] >= 0 and v[2] <= 1e6 and (v[3] is float or v[3] is int) and v[3] == int(v[3]) and v[3] > 0 and v[3] <= 1000000 and (v[4] is float or v[4] is int) and InventoryCategory.is_valid(int(v[4]))
        "storage":
            if not v is Array: return false
            for item in v:
                if not item is Dictionary or item.type != "stack": return false
            return true
        "dictionary":
            if not v is Array: return false
            for entry in v:
                if not entry is Array or entry.size() != 2: return false
                var key = entry[0]
                if not (key is String or key is int or key is float or (key is Dictionary and key.type == "v2i")): return false
            return true
        "pair":
            return v is Array and v.size() == 7 and v[0] is String and v[0].is_valid_int() and v[1] is Dictionary and v[1].type == "v2i" and v[2] is String and v[2].is_valid_int() and v[3] is Dictionary and v[3].type == "v3" and v[4] is Dictionary and v[4].type == "v3" and (v[5] is float or v[5] is int) and (v[6] is float or v[6] is int)
    return false

static func decode(value):
    if value is Array:
        var result = []
        for item in value: result.append(decode(item))
        return result
    if not value is Dictionary: return value
    var v = value.value
    match value.type:
        "v3": return Vector3(v[0],v[1],v[2])
        "v2i": return Vector2i(int(v[0]),int(v[1]))
        "health":
            var state = HealthState.new()
            state.set_maximum_health(v[1])
            state.set_health(v[0])
            return state
        "affection": return AffectionState.new(float(v))
        "stack": return InventoryStack.new(StringName(v[0]),v[1],v[2],int(v[3]),int(v[4]))
        "storage":
            var storage = LootStorage.new()
            for item in v: storage.stacks.append(decode(item))
            return storage
        "dictionary":
            var result = {}
            for entry in v: result[decode(entry[0])] = decode(entry[1])
            return result
        "pair":
            var values = decode(v)
            var pair = DungeonPairDefinition.new()
            pair.pair_id = int(values[0])
            pair.region_coordinate = values[1]
            pair.dungeon_seed = int(values[2])
            pair.endpoint_a_world_position = values[3]
            pair.endpoint_b_world_position = values[4]
            pair.endpoint_a_yaw = values[5]
            pair.endpoint_b_yaw = values[6]
            return pair
    return null
