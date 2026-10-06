extends Node3D
class_name NpcEquipment
# Equipped weapons remain in the inventory, so their corpse can be looted normally.
const RigMap = preload("res://actors/npcs/villagers/authoring/rig_map.gd")
var inventory: LootStorage
var weapon: EquipmentDefinition
var _rig: Skeleton3D
var _hand: int = -1
var _grip_basis: Basis = Basis.IDENTITY
var _model: Node3D
var _revision: int = -1

func configure(body: Node3D, rig: Skeleton3D, storage: LootStorage):
    inventory = storage
    _rig = rig
    _hand = RigMap.find_target_bone(rig,&"RightHand")
    assert(_hand >= 0,"NPC weapon grip requires the right hand")
    # Calibrate in the grounded idle pose, independently of each GLB's bone axes/scale.
    var hand_basis = (_rig.global_basis*_rig.get_bone_global_pose(_hand).basis).orthonormalized()
    _grip_basis = hand_basis.inverse()*body.global_basis.orthonormalized()
    sync_inventory()

func sync_inventory():
    if inventory == null or _revision == inventory.get_revision(): return
    _revision = inventory.get_revision()
    var best: EquipmentDefinition
    for stack in inventory.stacks:
        var definition = EquipmentCatalog.get_definition(stack.get_item_id())
        if definition == null or definition.category != EquipmentDefinition.Category.WEAPON or stack.get_quantity() <= 0: continue
        if best == null or definition.damage > best.damage: best = definition
    if best == weapon: return
    weapon = best
    if is_instance_valid(_model):
        remove_child(_model)
        _model.queue_free()
        _model = null
    if weapon == null: return
    # Reuse only the low-poly model, without player input or first-person mounting transforms.
    var held = weapon.held_scene.instantiate()
    _model = held.get_node("Model")
    held.remove_child(_model)
    held.free()
    add_child(_model)
    _model.name = "HeldWeapon"
    _model.top_level = true
    update_pose()

func update_pose():
    if not is_instance_valid(_model) or _hand < 0: return
    var hand = _rig.global_transform*_rig.get_bone_global_pose(_hand)
    var basis = hand.basis.orthonormalized()*_grip_basis
    _model.global_transform = Transform3D(basis,hand.origin+basis.y*.08)

func get_attack_action() -> String:
    if weapon == null: return ""
    if "axe" in weapon.tool_tags: return "weapon_chop"
    if "knife" in weapon.tool_tags or "dagger" in weapon.tool_tags or weapon.item_id == &"duelist_rapier": return "weapon_stab"
    return "weapon_slash"
