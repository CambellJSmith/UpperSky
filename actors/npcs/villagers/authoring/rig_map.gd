extends RefCounted # Maps the authored Thumperman rig onto the imported humanoid character rigs.

const SOURCE_BONES: Dictionary[StringName, StringName] = { # Defines anatomical names for the source rig's numbered bones.
	&"Hips": &"Bone_001", &"Spine": &"Bone_004", &"Spine1": &"Bone_003", &"Spine2": &"Bone_002", # Maps the pelvis and torso chain.
	&"Neck": &"Bone_017", &"Head": &"Bone_016", &"HeadTop_End": &"Bone_015", # Maps the neck and head chain.
	&"LeftShoulder": &"Bone_022", &"LeftArm": &"Bone_021", &"LeftForeArm": &"Bone_020", &"LeftHand": &"Bone_019", # Maps the __swap_right__ upper limb.
	&"RightShoulder": &"Bone_027", &"RightArm": &"Bone_026", &"RightForeArm": &"Bone_025", &"RightHand": &"Bone_024", # Maps the right upper limb.
	&"LeftUpLeg": &"Bone_009", &"LeftLeg": &"Bone_008", &"LeftFoot": &"Bone_007", &"LeftToeBase": &"Bone_006", &"LeftToe_End": &"Bone_005", # Maps the __swap_right__ lower limb.
	&"RightUpLeg": &"Bone_014", &"RightLeg": &"Bone_013", &"RightFoot": &"Bone_012", &"RightToeBase": &"Bone_011", &"RightToe_End": &"Bone_010", # Maps the right lower limb.
	&"LeftHandThumb1": &"Bone_035", &"LeftHandThumb2": &"Bone_034", &"LeftHandThumb3": &"Bone_033", &"LeftHandThumb4": &"Bone_032", # Maps the __swap_right__ thumb.
	&"LeftHandIndex1": &"Bone_047", &"LeftHandIndex2": &"Bone_046", &"LeftHandIndex3": &"Bone_045", &"LeftHandIndex4": &"Bone_044", # Maps the __swap_right__ index finger.
	&"LeftHandMiddle1": &"Bone_051", &"LeftHandMiddle2": &"Bone_050", &"LeftHandMiddle3": &"Bone_049", &"LeftHandMiddle4": &"Bone_048", # Maps the __swap_right__ middle finger.
	&"LeftHandRing1": &"Bone_043", &"LeftHandRing2": &"Bone_042", &"LeftHandRing3": &"Bone_041", &"LeftHandRing4": &"Bone_040", # Maps the __swap_right__ ring finger.
	&"LeftHandPinky1": &"Bone_039", &"LeftHandPinky2": &"Bone_038", &"LeftHandPinky3": &"Bone_037", &"LeftHandPinky4": &"Bone_036", # Maps the __swap_right__ little finger.
	&"RightHandThumb1": &"Bone_055", &"RightHandThumb2": &"Bone_054", &"RightHandThumb3": &"Bone_053", &"RightHandThumb4": &"Bone_052", # Maps the right thumb.
	&"RightHandIndex1": &"Bone_063", &"RightHandIndex2": &"Bone_062", &"RightHandIndex3": &"Bone_061", &"RightHandIndex4": &"Bone_060", # Maps the right index finger.
	&"RightHandMiddle1": &"Bone_071", &"RightHandMiddle2": &"Bone_070", &"RightHandMiddle3": &"Bone_069", &"RightHandMiddle4": &"Bone_068", # Maps the right middle finger.
	&"RightHandRing1": &"Bone_067", &"RightHandRing2": &"Bone_066", &"RightHandRing3": &"Bone_065", &"RightHandRing4": &"Bone_064", # Maps the right ring finger.
	&"RightHandPinky1": &"Bone_059", &"RightHandPinky2": &"Bone_058", &"RightHandPinky3": &"Bone_057", &"RightHandPinky4": &"Bone_056", # Maps the right little finger.
} # Ends the source humanoid mapping.
const REQUIRED: Array[StringName] = [&"Hips", &"Spine", &"Spine1", &"Spine2", &"Neck", &"Head", &"RightArm", &"RightForeArm", &"RightHand", &"LeftArm", &"LeftForeArm", &"LeftHand", &"RightUpLeg", &"RightLeg", &"RightFoot", &"LeftUpLeg", &"LeftLeg", &"LeftFoot"] # Requires a complete locomotion skeleton while allowing omitted fingers and end bones.

static func find_target_bone(skeleton: Skeleton3D, semantic: StringName) -> int: # Resolves anatomy without depending on an exporter's Mixamo namespace spelling.
	for bone_index: int in range(skeleton.get_bone_count()): # Searches the small imported rig only during offline baking.
		var name: String = skeleton.get_bone_name(bone_index).replace("mixamorig:", "").replace("mixamorig_", "").replace("mixamorig", "") # Normalizes common Mixamo export prefixes.
		if name == String(semantic): # Requires an exact anatomical name after namespace removal.
			return bone_index # Returns the matching target index.
	if skeleton.find_bone("Bone_032") >= 0 and skeleton.find_bone("mixamorig:Hips") < 0:
		var demon = {"Hips":"Bone_001","Spine":"Bone_004","Spine1":"Bone_003","Spine2":"Bone_002","Neck":"Bone_028","Head":"Bone_027","HeadTop_End":"Bone_026","LeftShoulder":"Bone_032","LeftArm":"Bone_031","LeftForeArm":"Bone_030","LeftHand":"Bone_029","RightShoulder":"Bone_036","RightArm":"Bone_035","RightForeArm":"Bone_034","RightHand":"Bone_033","LeftUpLeg":"Bone_018","LeftLeg":"Bone_017","LeftFoot":"Bone_016","LeftToeBase":"Bone_015","LeftToe_End":"Bone_014","RightUpLeg":"Bone_023","RightLeg":"Bone_022","RightFoot":"Bone_021","RightToeBase":"Bone_020","RightToe_End":"Bone_019"}
		return skeleton.find_bone(demon.get(String(semantic),""))
	return -1 # Reports an optional anatomical bone missing from this rig.

static func skeleton_in_visual(skeleton: Skeleton3D, visual: Node3D) -> Transform3D: # Collects the authored transform below the visual root without gameplay scale or yaw.
	var transform: Transform3D = skeleton.transform # Starts from the imported skeleton's local unit conversion.
	var node: Node3D = skeleton.get_parent() as Node3D # Walks spatial ancestors below the visual root.
	while node != null and node != visual: # Excludes normalization and facing transforms applied to the whole visual.
		transform = node.transform * transform # Preserves import rotation and scale in parent-first order.
		node = node.get_parent() as Node3D # Continues toward the visual owner.
	return transform # Returns the rig's model-space transform.
