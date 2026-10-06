extends Node3D
class_name FirstPersonArms

const ARM_SCENE: PackedScene = preload("res://actors/player/arms/rigged_arm.glb")
const ARM_SCALE: float = .55
const FINGER_ROOTS = ["Bone.002","Bone.006","Bone.010","Bone.014","Bone.018"]
var _arms: Array[Dictionary] = []
var _item: EquippedItem
var _two_handed: bool = false
var _clock: float = 0.0

func _ready() -> void:
    # Run after the equipment tweens so the hands use this frame's handle pose.
    process_priority = 50
    for side in [1.0,-1.0]:
        var arm = ARM_SCENE.instantiate() as Node3D
        arm.name = "RightArm" if side > 0 else "LeftArm"
        add_child(arm)
        arm.scale = Vector3(side*ARM_SCALE,ARM_SCALE,ARM_SCALE)
        arm.position = Vector3(side*.40,-.62,-.02)
        var armature = arm.get_node("Armature") as Node3D
        armature.position = Vector3.ZERO
        var skeleton = armature.get_node("Skeleton3D") as Skeleton3D
        _prepare_meshes(arm)
        var rests: Array[Transform3D] = []
        for i in range(skeleton.get_bone_count()): rests.append(skeleton.get_bone_global_rest(i))
        _arms.append({"root":arm,"skeleton":skeleton,"rests":rests,"side":side,"grip":Vector3.ZERO})
    _update_pose(0.0)

func bind_item(item: EquippedItem) -> void:
    _item = item
    _two_handed = false
    if is_instance_valid(item):
        var definition = item.get_definition()
        _two_handed = definition != null and (definition.category == EquipmentDefinition.Category.TOOL or item.get("motion_profile") == MeleeEquipment.MotionProfile.CHOP or definition.item_id == &"highland_greatsword")
    var mount = get_parent().get_node("EquipmentMount") as Node3D
    mount.position = Vector3(.12,-.28,-.55) if _two_handed else Vector3(.28,-.25,-.65)
    _update_pose(0.0)

func _process(delta: float) -> void:
    _clock += delta
    _update_pose(delta)

func _update_pose(_delta: float) -> void:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__update_pose(_delta)
        return
    var _profile_token = RuntimeProfiler.begin("player.arms")
    _profile__update_pose(_delta)
    RuntimeProfiler.end(_profile_token)

func _profile__update_pose(_delta: float) -> void:
    var held: bool = is_instance_valid(_item) and not _item.is_queued_for_deletion()
    for arm in _arms:
        var side: float = arm.side
        var closed: bool = held and (side > 0 or _two_handed)
        var grip: Vector3
        var shaft: Vector3 = Vector3.UP
        var forward: Vector3 = Vector3.FORWARD
        if closed:
            var handle_offset = Vector3(0,-.045 if side > 0 else .22,0)
            if _item.get_definition().item_id == &"highland_greatsword" and side < 0:
                handle_offset.y = -.17
            grip = to_local(_item.to_global(handle_offset))
            shaft = global_basis.inverse()*_item.global_basis.y.normalized()
            forward = global_basis.inverse()*(-_item.global_basis.z.normalized())
        else:
            grip = Vector3(side*.28,-.43,-.58)+Vector3(0,sin(_clock*1.7)*.004,0)
            forward = Vector3(side*-.16,.15,-1).normalized()
        arm.grip = grip
        _pose_arm(arm,grip,shaft,forward,closed)

func _pose_arm(arm: Dictionary, grip: Vector3, shaft: Vector3, forward: Vector3, closed: bool) -> void:
    var skeleton: Skeleton3D = arm.skeleton
    var rests: Array[Transform3D] = arm.rests
    arm.root.position = Vector3(arm.side*.40,-.62,-.02)
    var rig_to_view = global_transform.affine_inverse()*skeleton.global_transform
    var view_to_rig = rig_to_view.affine_inverse()
    var finger_forward = (view_to_rig.basis*forward).normalized()
    var across = -(view_to_rig.basis*shaft).normalized()
    var back = across.cross(finger_forward).normalized()
    across = finger_forward.cross(back).normalized()
    var hand_basis = Basis(across,finger_forward,back)
    # The wrist sits behind the handle; metacarpals and curled fingers wrap it.
    var wrist = view_to_rig*grip-finger_forward*.20+back*(.085 if closed else .025)
    var upper_length: float = skeleton.get_bone_rest(1).origin.length()
    var lower_length: float = skeleton.get_bone_rest(2).origin.length()
    arm.desired_wrist = rig_to_view*wrist
    var reach: Vector3 = arm.desired_wrist-rig_to_view.origin
    var maximum_reach: float = (upper_length+lower_length)*ARM_SCALE-.015
    if reach.length() > maximum_reach:
        # Shoulders remain below the camera, but yield slightly during cross-body swings.
        arm.root.position += reach.normalized()*(reach.length()-maximum_reach)
        rig_to_view = global_transform.affine_inverse()*skeleton.global_transform
        view_to_rig = rig_to_view.affine_inverse()
        wrist = view_to_rig*arm.desired_wrist
    var distance: float = clampf(wrist.length(),absf(upper_length-lower_length)+.001,upper_length+lower_length-.001)
    var direction = wrist.normalized()
    wrist = direction*distance
    var pole = (view_to_rig.basis*Vector3(arm.side,-.55,.20)).normalized()
    var bend = (pole-direction*pole.dot(direction)).normalized()
    var along: float = (upper_length*upper_length-lower_length*lower_length+distance*distance)/(2*distance)
    var elbow = direction*along+bend*sqrt(maxf(0,upper_length*upper_length-along*along))
    var upper_basis = Basis(Quaternion(rests[1].origin.normalized(),elbow.normalized()))*rests[0].basis
    var lower_rest_direction: Vector3 = (rests[2].origin-rests[1].origin).normalized()
    var lower_basis = Basis(Quaternion(lower_rest_direction,(wrist-elbow).normalized()))*rests[1].basis
    skeleton.set_bone_pose_rotation(0,upper_basis.get_rotation_quaternion())
    skeleton.set_bone_pose_rotation(1,(upper_basis.inverse()*lower_basis).get_rotation_quaternion())
    var hand_delta = hand_basis*rests[1].basis.inverse()
    for bone_name in FINGER_ROOTS:
        var index = skeleton.find_bone(bone_name)
        var basis = hand_delta*rests[index].basis
        if bone_name == "Bone.018" and closed:
            var thumb_direction = (hand_basis*Vector3(-.25,.60,-.75)).normalized()
            basis = Basis(Quaternion(basis.y.normalized(),thumb_direction))*basis
        skeleton.set_bone_pose_rotation(index,(lower_basis.inverse()*basis).get_rotation_quaternion())
    for chain in [["Bone.003","Bone.004","Bone.005"],["Bone.007","Bone.008","Bone.009"],["Bone.011","Bone.012","Bone.013"],["Bone.015","Bone.016","Bone.017"]]:
        for joint in range(chain.size()):
            var index = skeleton.find_bone(chain[joint])
            var curl: float = [-1.15,-1.20,-.65][joint] if closed else [-.12,-.18,-.08][joint]
            skeleton.set_bone_pose_rotation(index,skeleton.get_bone_rest(index).basis.get_rotation_quaternion()*Quaternion(Vector3.RIGHT,curl))
    for bone_name in ["Bone.019","Bone.020"]:
        var index = skeleton.find_bone(bone_name)
        if closed:
            var desired = hand_delta*rests[index].basis
            var thumb_tip_direction = (hand_basis*Vector3(.95,.15,-.20)).normalized()
            desired = Basis(Quaternion(desired.y.normalized(),thumb_tip_direction))*desired
            var parent_basis = skeleton.get_bone_global_pose(skeleton.get_bone_parent(index)).basis
            skeleton.set_bone_pose_rotation(index,(parent_basis.inverse()*desired).get_rotation_quaternion())
        else:
            skeleton.set_bone_pose_rotation(index,skeleton.get_bone_rest(index).basis.get_rotation_quaternion()*Quaternion(Vector3.RIGHT,-.10))

func _prepare_meshes(node: Node) -> void:
    if node is MeshInstance3D:
        node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        # Imported rest bounds do not contain the reaching and swinging poses.
        node.custom_aabb = AABB(Vector3(-3,-3,-3),Vector3(6,6,6))
    for child in node.get_children(): _prepare_meshes(child)
