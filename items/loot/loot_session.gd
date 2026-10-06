extends RefCounted
class_name LootSession
# Retain changed contents and deaths across streaming; SaveSystem persists these records.
static var records: Dictionary = {}
static func get_record(key: String, seed_value: int, person: bool = false) -> Dictionary:
    if records.has(key):
        if person: records[key]["npc_id"] = key
        return records[key]
    var inventory = LootStorage.new()
    var rng = RandomNumberGenerator.new()
    rng.seed = seed_value
    inventory.try_add_item(&"coins","Coins",.01,rng.randi_range(2,12))
    inventory.try_add_item(&"bread","Bread",.25,rng.randi_range(1,3),InventoryCategory.Type.INGREDIENTS)
    if person:
        inventory.try_add_item(&"linen","Linen cloth",.15,1+rng.randi_range(0,2))
    else:
        var equipment: EquipmentDefinition = EquipmentCatalog.DEFINITIONS[rng.randi_range(0,EquipmentCatalog.DEFINITIONS.size()-1)]
        inventory.try_add_item(equipment.item_id,equipment.display_name,equipment.unit_weight,1,InventoryCategory.Type.WEAPONS_TOOLS)
    var record = {"inventory":inventory,"health":HealthState.new()}
    if person: record["npc_id"] = key
    records[key] = record
    return record

static func get_affection(record: Dictionary, species: String) -> AffectionState:
    if not record.has("affection"):
        record["affection"] = AffectionState.new(AffectionState.starting_score(species))
    return record["affection"]
