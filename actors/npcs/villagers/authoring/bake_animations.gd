extends SceneTree # Bakes shared animation resources offline so gameplay never performs retargeting work.

const RigMap = preload("res://actors/npcs/villagers/authoring/rig_map.gd") # Shares explicit humanoid mapping and import-space conversion.
const TARGETS: Dictionary[String,String] = {"humble_pilgrim":"res://actors/npcs/villagers/models/humble_pilgrim.glb","village_weaver":"res://actors/npcs/villagers/models/village_weaver.glb","orc":"res://actors/npcs/villagers/models/orc.glb","demon":"res://actors/npcs/villagers/models/demon.glb","ghost":"res://actors/npcs/villagers/models/ghost.glb","zombie":"res://actors/npcs/villagers/models/zombie.glb","fish_man":"res://actors/npcs/villagers/models/fish_man.glb"}
const OUTPUT_DIRECTORY: String = "res://actors/npcs/villagers/animations" # Stores the baked resources shared by gameplay and temporary actors.
const SAMPLE_RATE: float = 30.0 # Matches the animation pack's authored sampling cadence.

func _initialize() -> void: # Starts baking after engine initialization can instantiate imported resources.
    _bake.call_deferred() # Defers resource work until the scene tree is ready.

func _bake() -> void:
    var source: Node3D = load("res://actors/npcs/villagers/animations/source/quaternius_source.tscn").instantiate()
    var source_rig: Skeleton3D = source.find_children("*","Skeleton3D",true,false)[0]
    var source_player: AnimationPlayer = source.find_child("AnimationPlayer",true,false)
    var source_transform: Transform3D = RigMap.skeleton_in_visual(source_rig,source)
    var neutral = _sample_globals(source_rig,source_player.get_animation("A_TPose"),0,source_transform)
    var clips = ["Idle_Loop","Walk_Loop","Jog_Fwd_Loop","Sprint_Loop","Punch_Jab","Punch_Cross"]
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIRECTORY))
    var targets := TARGETS.duplicate()
    targets["wizard"] = "res://actors/npcs/villagers/models/wizard.glb"
    targets["werewolf"] = "res://actors/npcs/villagers/models/werewolf.glb"
    targets["knight"] = "res://actors/npcs/villagers/models/knight.glb"
    targets["vampire"] = "res://actors/npcs/villagers/models/vampire.glb"
    targets["king"] = "res://actors/npcs/villagers/models/king.glb"
    for character in targets:
        if "king-only" in OS.get_cmdline_user_args() and character != "king": continue
        if "wizard-only" in OS.get_cmdline_user_args() and character != "wizard": continue
        if "werewolf-only" in OS.get_cmdline_user_args() and character != "werewolf": continue
        if "knight-only" in OS.get_cmdline_user_args() and character != "knight": continue
        if "vampire-only" in OS.get_cmdline_user_args() and character != "vampire": continue
        var target: Node3D = load(targets[character]).instantiate()
        var rig: Skeleton3D = target.find_children("*","Skeleton3D",true,false)[0]
        var player: AnimationPlayer = target.find_child("AnimationPlayer",true,false)
        if player == null:
            player = AnimationPlayer.new()
            player.name = "AnimationPlayer"
            target.add_child(player)
        var mapping = _bone_mapping(source_rig,rig)
        var target_transform = RigMap.skeleton_in_visual(rig,target)
        var target_rest = _rest_globals(rig,target_transform)
        var alignment = _anatomical_frame(rig,target_rest,false)*_anatomical_frame(source_rig,neutral,true).inverse()
        target_rest = _calibrate_limb_neutral(source_rig,neutral,rig,target_rest,alignment)
        var source_hips = source_rig.find_bone(RigMap.SOURCE_BONES[&"Hips"])
        var target_hips = RigMap.find_target_bone(rig,&"Hips")
        var ratio = _leg_length(rig,target_rest,false)/_leg_length(source_rig,neutral,true)
        var animation_root = player.get_node(player.root_node)
        var skeleton_path = str(animation_root.get_path_to(rig))
        var library = AnimationLibrary.new()
        for clip in clips:
            library.add_animation(clip,_retarget(source_rig,source_player.get_animation(clip),source_transform,neutral,rig,target_transform,target_rest,mapping,alignment,ratio,target_rest[target_hips].origin,source_hips,target_hips,skeleton_path))
        library.add_animation("Kick",_make_kick(rig,library.get_animation("Idle_Loop"),target_transform,skeleton_path))
        for style in ["Slash","Chop","Stab"]:
            library.add_animation("Weapon"+style,_make_weapon_attack(rig,library.get_animation("Idle_Loop"),target_transform,skeleton_path,style))
        var error = ResourceSaver.save(library,OUTPUT_DIRECTORY.path_join(character+".res"),ResourceSaver.FLAG_COMPRESS)
        assert(error == OK)
        print("BAKED ",character," clips=",library.get_animation_list().size()," mapped bones=",mapping.size())
        target.free()
    source.free()
    quit()

func _bone_mapping(source: Skeleton3D, target: Skeleton3D) -> Dictionary[int, int]: # Maps existing target bones to anatomical source bones without guessing missing limbs.
    var mapping: Dictionary[int, int] = {} # Stores target-to-source bone indices for offline retargeting.
    for semantic: StringName in RigMap.SOURCE_BONES: # Covers the complete supported body and optional finger anatomy.
        var target_index: int = RigMap.find_target_bone(target, semantic) # Resolves this semantic on the target rig.
        var source_index: int = source.find_bone(String(RigMap.SOURCE_BONES[semantic])) # Resolves the source's numbered anatomical bone.
        assert(source_index >= 0, "Missing Source Bone: " + String(semantic)) # Rejects a broken source rig.
        if target_index >= 0: # Copies motion only onto bones that actually exist.
            mapping[target_index] = source_index # Records the anatomical correspondence.
    for semantic: StringName in RigMap.REQUIRED: # Validates the complete required locomotion chain.
        assert(RigMap.find_target_bone(target, semantic) >= 0, "Missing Required Target Bone: " + String(semantic)) # Fails explicitly when a rig cannot carry the pack.
    return mapping # Returns the validated offline bone map.

func _rest_globals(rig: Skeleton3D, transform: Transform3D) -> Array[Transform3D]: # Captures bone rest transforms in unnormalized visual space.
    var globals: Array[Transform3D] = [] # Stores one model-space rest transform per bone.
    for bone: int in range(rig.get_bone_count()): # Visits the source hierarchy in engine bone order.
        globals.append(transform * rig.get_bone_global_rest(bone)) # Preserves original import scale and bone lengths.
    return globals # Returns the complete stable calibration array.

func _sample_globals(rig: Skeleton3D, animation: Animation, time: float, transform: Transform3D) -> Array[Transform3D]: # Evaluates source animation tracks without running animation players or scene callbacks.
    var locals: Array[Transform3D] = [] # Starts each bone from its original authored rest transform.
    for bone: int in range(rig.get_bone_count()): # Covers every parent and optional helper bone needed by the pose.
        locals.append(rig.get_bone_rest(bone)) # Supplies rest values for bones without animated tracks.
    for track: int in range(animation.get_track_count()): # Samples only actual skeletal transform tracks.
        var path: NodePath = animation.track_get_path(track) # Reads the source animation's bone target.
        if path.get_subname_count() != 1 or animation.track_get_key_count(track) == 0: # Skips non-bone tracks and empty channels.
            continue # Leaves the corresponding rest pose intact.
        var bone: int = rig.find_bone(String(path.get_subname(0))) # Resolves this exact rig bone.
        if bone < 0: # Skips tracks belonging to unrelated props or visual nodes.
            continue # Prevents external animation side effects during baking.
        match animation.track_get_type(track): # Applies only the source's actual local transform channels.
            Animation.TYPE_ROTATION_3D: # Samples the authored quaternion rotation channel.
                locals[bone].basis = Basis(animation.rotation_track_interpolate(track, time)).scaled(locals[bone].basis.get_scale()) # Preserves target-independent source rest scale.
            Animation.TYPE_POSITION_3D: # Samples the authored local translation channel.
                locals[bone].origin = animation.position_track_interpolate(track, time) # Includes pelvis motion and any animated source helpers.
    var globals: Array[Transform3D] = [] # Accumulates parent-first model-space transforms.
    for bone: int in range(rig.get_bone_count()): # Visits the imported hierarchy in parent-before-child order.
        var parent: int = rig.get_bone_parent(bone) # Resolves the current bone's parent index.
        globals.append((globals[parent] if parent >= 0 else transform) * locals[bone]) # Applies the complete ancestor transform to the sampled local pose.
    return globals # Returns the sampled anatomical source pose.

func _anatomical_frame(rig: Skeleton3D, globals: Array[Transform3D], source: bool) -> Basis: # Resolves a consistent anatomical frame independently of model yaw and import axis conversion.
    var right: int = rig.find_bone(String(RigMap.SOURCE_BONES[&"RightUpLeg"])) if source else RigMap.find_target_bone(rig, &"RightUpLeg") # Resolves the right hip landmark.
    var left: int = rig.find_bone(String(RigMap.SOURCE_BONES[&"LeftUpLeg"])) if source else RigMap.find_target_bone(rig, &"LeftUpLeg") # Resolves the left hip landmark.
    var head: int = rig.find_bone("Bone_016") if source else RigMap.find_target_bone(rig, &"Head") # Resolves the head landmark.
    var hips: int = rig.find_bone("Bone_001") if source else RigMap.find_target_bone(rig, &"Hips") # Resolves the pelvis landmark.
    var x: Vector3 = (globals[right].origin - globals[left].origin).normalized() # Resolves anatomical right across the two thighs.
    var y: Vector3 = (globals[head].origin - globals[hips].origin).slide(x).normalized() # Resolves upright torso direction orthogonal to the hip axis.
    return Basis(x, y, x.cross(y).normalized()).orthonormalized() # Returns the right-handed anatomical model-space frame.

func _leg_length(rig: Skeleton3D, globals: Array[Transform3D], source: bool) -> float: # Measures vertical-motion scale from the authored thigh and shin lengths.
    var thigh: int = rig.find_bone(String(RigMap.SOURCE_BONES[&"RightUpLeg"])) if source else RigMap.find_target_bone(rig, &"RightUpLeg") # Resolves the upper-leg origin.
    var shin: int = rig.find_bone(String(RigMap.SOURCE_BONES[&"RightLeg"])) if source else RigMap.find_target_bone(rig, &"RightLeg") # Resolves the knee origin.
    var foot: int = rig.find_bone(String(RigMap.SOURCE_BONES[&"RightFoot"])) if source else RigMap.find_target_bone(rig, &"RightFoot") # Resolves the ankle origin.
    return globals[thigh].origin.distance_to(globals[shin].origin) + globals[shin].origin.distance_to(globals[foot].origin) # Retains character proportions while scaling pelvis motion.

func _retarget(source_rig: Skeleton3D, source: Animation, source_transform: Transform3D, neutral: Array[Transform3D], rig: Skeleton3D, target_transform: Transform3D, target_rest: Array[Transform3D], mapping: Dictionary[int, int], alignment: Basis, ratio: float, standing_hips: Vector3, source_hips: int, target_hips: int, skeleton_path: String) -> Animation: # Bakes one complete quaternion animation onto the target's existing rest skeleton.
    var result: Animation = Animation.new() # Creates an independent target animation resource.
    result.length = source.length # Preserves the authored motion duration.
    result.loop_mode = source.loop_mode # Preserves the pack's actual loop policy.
    var rotation_tracks: Dictionary[int, int] = {} # Stores generated bone rotation channels.
    var position_tracks: Dictionary[int, int] = {} # Stores generated stable local bone-length channels.
    for bone: int in mapping: # Emits only mapped body bones and never cape or unsupported helper bones.
        var path: NodePath = NodePath(skeleton_path + ":" + rig.get_bone_name(bone)) # Targets the actual imported skeleton path and bone name.
        var rotation_track: int = result.add_track(Animation.TYPE_ROTATION_3D) # Creates the target quaternion rotation channel.
        result.track_set_path(rotation_track, path) # Associates the channel with its actual target bone.
        rotation_tracks[bone] = rotation_track # Caches the channel for key insertion.
        var position_track: int = result.add_track(Animation.TYPE_POSITION_3D) # Creates a stable local position channel for blending with original imported clips.
        result.track_set_path(position_track, path) # Uses the same actual target bone.
        position_tracks[bone] = position_track # Caches the stable-proportion channel.
    var sample_count: int = maxi(1, int(ceil(source.length * SAMPLE_RATE))) # Bakes a bounded number of authored-cadence samples including both endpoints.
    for sample: int in range(sample_count + 1): # Samples the complete motion without dropping its final pose.
        var time: float = source.length * float(sample) / float(sample_count) # Places the final sample exactly at the source endpoint.
        var source_pose: Array[Transform3D] = _sample_globals(source_rig, source, time, source_transform) # Evaluates the source motion with all relevant ancestors.
        var desired_globals: Array[Basis] = [] # Builds target parent rotations in hierarchy order.
        for bone: int in range(rig.get_bone_count()): # Preserves target hierarchy and unmapped helper transforms.
            var parent: int = rig.get_bone_parent(bone) # Resolves the target parent used to localize global motion.
            var parent_basis: Basis = desired_globals[parent] if parent >= 0 else target_transform.basis.orthonormalized() # Supplies the target parent's already-retargeted global rotation.
            var desired: Basis = parent_basis * rig.get_bone_rest(bone).basis.orthonormalized() # Keeps unmapped bones attached with their original local rest orientation.
            if mapping.has(bone): # Transfers source motion only to mapped anatomy.
                var source_bone: int = mapping[bone] # Resolves this target bone's anatomical source.
                desired = alignment * source_pose[source_bone].basis.orthonormalized() * neutral[source_bone].basis.orthonormalized().inverse() * alignment.inverse() * target_rest[bone].basis.orthonormalized() # Transfers neutral-relative global motion across different bone rest axes.
            desired_globals.append(desired.orthonormalized()) # Retains a normalized parent rotation for later target children.
            if not mapping.has(bone): # Omits animated tracks for unsupported source anatomy.
                continue # Leaves optional unmapped bones under their original target parent.
            var rotation: Quaternion = (parent_basis.inverse() * desired).orthonormalized().get_rotation_quaternion().normalized() # Converts anatomical global motion back into the target's local quaternion channel.
            var position: Vector3 = rig.get_bone_rest(bone).origin # Preserves the target's exact local bone length and placement.
            if bone == target_hips: # Transfers vertical pelvis motion while retaining controller-owned horizontal travel.
                var delta: Vector3 = alignment * (source_pose[source_hips].origin - neutral[source_hips].origin) * ratio # Scales source pelvis motion into target visual units.
                var world_position: Vector3 = standing_hips + Vector3.UP * delta.dot(Vector3.UP) # Locks horizontal translation to the target's original grounded standing origin.
                position = target_transform.affine_inverse() * world_position # Converts the grounded pelvis offset into the imported target skeleton's local units.
            if sample == sample_count and result.loop_mode == Animation.LOOP_LINEAR: # Makes looping endpoints exactly match without a wrap discontinuity.
                rotation = result.track_get_key_value(rotation_tracks[bone], 0) # Reuses the first quaternion at the loop endpoint.
                position = result.track_get_key_value(position_tracks[bone], 0) # Reuses the first local position at the loop endpoint.
            result.rotation_track_insert_key(rotation_tracks[bone], time, rotation) # Adds the target's normalized local skeletal rotation.
            result.position_track_insert_key(position_tracks[bone], time, position) # Adds target-proportion position and calibrated pelvis height.
    return result # Returns the complete source-duration target clip ready for resource saving.

func _calibrate_limb_neutral(source: Skeleton3D, neutral: Array[Transform3D], rig: Skeleton3D, rest: Array[Transform3D], alignment: Basis) -> Array[Transform3D]: # Calibrates bind limbs into the pack's neutral pose during offline baking.
    var result: Array[Transform3D] = rest.duplicate() # Keeps original rest data independent of the calibration.
    var segments: Dictionary[String, String] = {"Arm": "ForeArm", "ForeArm": "Hand", "Hand": "HandMiddle1", "UpLeg":"Leg", "Leg":"Foot", "Foot":"ToeBase"} # Names each neutral arm segment explicitly.
    for side: String in ["Left", "Right"]: # Calibrates both anatomical arm chains.
        for segment: String in segments: # Aligns each arm and leg segment independently.
            var semantic: StringName = StringName(side + segment) # Resolves the rotation joint.
            var child_semantic: StringName = StringName(side + segments[segment]) # Resolves its directional landmark.
            var bone: int = RigMap.find_target_bone(rig, semantic) # Finds the target joint.
            var child: int = RigMap.find_target_bone(rig, child_semantic) # Finds the target limb endpoint.
            var source_bone: int = source.find_bone(String(RigMap.SOURCE_BONES[semantic])) # Finds the corresponding source joint.
            var source_child: int = source.find_bone(String(RigMap.SOURCE_BONES[child_semantic])) # Finds the source neutral endpoint.
            if bone < 0 or child < 0 or source_bone < 0 or source_child < 0: continue # Optional finger landmarks may be absent on monster rigs.
            var current_direction: Vector3 = (result[child].origin - result[bone].origin).normalized() # Reads this target segment after ancestor calibration.
            var desired_direction: Vector3 = (alignment * (neutral[source_child].origin - neutral[source_bone].origin)).normalized() # Transfers the neutral anatomical direction.
            var correction: Basis = Basis(Quaternion(current_direction, desired_direction)) # Rotates through the shortest arc while retaining imported bone axes.
            var pivot: Vector3 = result[bone].origin # Keeps the calibrated segment attached at its original joint.
            for descendant: int in range(rig.get_bone_count()): # Carries every downstream finger and helper through the arm correction.
                var ancestor: int = descendant # Starts ancestry testing at the candidate.
                while ancestor >= 0 and ancestor != bone: # Looks for this arm joint in the hierarchy.
                    ancestor = rig.get_bone_parent(ancestor) # Advances toward the root.
                if ancestor == bone: # Applies correction only to this joint and its descendants.
                    result[descendant].origin = pivot + correction * (result[descendant].origin - pivot) # Preserves every downstream length and attachment.
                    result[descendant].basis = correction * result[descendant].basis # Retains the imported rest axes relative to the raised neutral arm.
    return result # Supplies a T-pose-compatible target frame for the selected clips.

func _make_kick(rig: Skeleton3D, idle: Animation, transform: Transform3D, skeleton_path: String) -> Animation:
    # A complementary front kick; the free Standard packs do not contain a kick clip.
    var result = Animation.new()
    result.length = 1.10
    var base = _sample_globals(rig,idle,0.0,transform)
    var keys = [[0.0,0.0,0.0],[.18,-48.0,98.0],[.38,-78.0,12.0],[.49,-78.0,12.0],[.70,-44.0,90.0],[1.10,0.0,0.0]]
    var thigh = RigMap.find_target_bone(rig,&"RightUpLeg")
    var shin = RigMap.find_target_bone(rig,&"RightLeg")
    var foot = RigMap.find_target_bone(rig,&"RightFoot")
    for bone in range(rig.get_bone_count()):
        var track = result.add_track(Animation.TYPE_ROTATION_3D)
        result.track_set_path(track,NodePath(skeleton_path+":"+rig.get_bone_name(bone)))
        var position_track = result.add_track(Animation.TYPE_POSITION_3D)
        result.track_set_path(position_track,result.track_get_path(track))
        for key in keys:
            var desired: Array[Basis] = []
            for current in range(rig.get_bone_count()):
                var correction = Basis.IDENTITY
                var ancestor = current
                var leg_segment = -1
                while ancestor >= 0:
                    if ancestor == foot: leg_segment = 2; break
                    if ancestor == shin: leg_segment = 1; break
                    if ancestor == thigh: leg_segment = 0; break
                    ancestor = rig.get_bone_parent(ancestor)
                if leg_segment >= 0:
                    var angle: float = key[1] if leg_segment == 0 else key[1]+key[2]
                    correction = Basis(Quaternion(Vector3.RIGHT,deg_to_rad(angle)))
                desired.append(correction*base[current].basis.orthonormalized())
            var parent = rig.get_bone_parent(bone)
            var parent_basis = desired[parent] if parent >= 0 else transform.basis.orthonormalized()
            result.rotation_track_insert_key(track,key[0],(parent_basis.inverse()*desired[bone]).get_rotation_quaternion().normalized())
            var position = rig.get_bone_rest(bone).origin
            var baseline = idle.find_track(result.track_get_path(track),Animation.TYPE_POSITION_3D)
            if baseline >= 0: position = idle.position_track_interpolate(baseline,0.0)
            result.position_track_insert_key(position_track,key[0],position)
    return result

func _make_weapon_attack(rig: Skeleton3D, idle: Animation, transform: Transform3D, skeleton_path: String, style: String) -> Animation:
    # Authored weapon motions complement the pack's locomotion and unarmed clips.
    # Keys hold [time, global upper-arm Euler degrees, additional elbow X, torso yaw].
    var motions = {
        "Slash":[[0.0,Vector3.ZERO,0.0,0.0],[.22,Vector3(65,-45,-55),-35.0,-15.0],[.42,Vector3(-85,30,10),20.0,15.0],[.60,Vector3(-35,45,20),10.0,10.0],[.95,Vector3.ZERO,0.0,0.0]],
        "Chop":[[0.0,Vector3.ZERO,0.0,0.0],[.26,Vector3(145,0,-15),-45.0,-8.0],[.48,Vector3(-80,0,5),20.0,8.0],[.65,Vector3(-30,0,5),10.0,5.0],[1.10,Vector3.ZERO,0.0,0.0]],
        "Stab":[[0.0,Vector3.ZERO,0.0,0.0],[.20,Vector3(0,-10,-10),45.0,-8.0],[.38,Vector3(-75,0,0),-10.0,12.0],[.60,Vector3(-60,0,0),0.0,8.0],[.85,Vector3.ZERO,0.0,0.0]]
    }
    var grips = {
        "Slash":[Vector3.ZERO,Vector3(-20,-50,-35),Vector3(70,25,45),Vector3(40,45,55),Vector3.ZERO],
        "Chop":[Vector3.ZERO,Vector3(-25,0,-5),Vector3(90,0,0),Vector3(65,0,0),Vector3.ZERO],
        "Stab":[Vector3.ZERO,Vector3(70,0,0),Vector3(90,0,0),Vector3(80,0,0),Vector3.ZERO]
    }
    var keys: Array = motions[style]
    var result = Animation.new()
    result.length = keys[-1][0]
    var base = _sample_globals(rig,idle,0,transform)
    var upper = RigMap.find_target_bone(rig,&"RightArm")
    var lower = RigMap.find_target_bone(rig,&"RightForeArm")
    var spine = RigMap.find_target_bone(rig,&"Spine2")
    var hand = RigMap.find_target_bone(rig,&"RightHand")
    var rotation_tracks: Array[int] = []
    var position_tracks: Array[int] = []
    for bone in range(rig.get_bone_count()):
        var track = result.add_track(Animation.TYPE_ROTATION_3D)
        result.track_set_path(track,NodePath(skeleton_path+":"+rig.get_bone_name(bone)))
        rotation_tracks.append(track)
        var position_track = result.add_track(Animation.TYPE_POSITION_3D)
        result.track_set_path(position_track,result.track_get_path(track))
        position_tracks.append(position_track)
    for key_index in range(keys.size()):
        var key = keys[key_index]
        var desired: Array[Basis] = []
        for bone in range(rig.get_bone_count()):
            var ancestor = bone
            var arm = false
            var forearm = false
            var torso = false
            var wrist = false
            while ancestor >= 0:
                arm = arm or ancestor == upper
                forearm = forearm or ancestor == lower
                torso = torso or ancestor == spine
                wrist = wrist or ancestor == hand
                ancestor = rig.get_bone_parent(ancestor)
            var correction = Basis(Quaternion(Vector3.UP,deg_to_rad(key[3]))) if torso else Basis.IDENTITY
            if arm:
                correction *= Basis.from_euler(Vector3(deg_to_rad(key[1].x),deg_to_rad(key[1].y),deg_to_rad(key[1].z)))
            if forearm: correction *= Basis(Quaternion(Vector3.RIGHT,deg_to_rad(key[2])))
            if wrist:
                # Orient the grip independently of the elbow so raised axes remain
                # blade-up and thrusts point forward rather than folding behind the hand.
                var grip: Vector3 = grips[style][key_index]
                correction = Basis(Quaternion(Vector3.UP,deg_to_rad(key[3])))*Basis.from_euler(Vector3(deg_to_rad(grip.x),deg_to_rad(grip.y),deg_to_rad(grip.z)))
            desired.append(correction*base[bone].basis.orthonormalized())
            var parent = rig.get_bone_parent(bone)
            var parent_basis = desired[parent] if parent >= 0 else transform.basis.orthonormalized()
            result.rotation_track_insert_key(rotation_tracks[bone],key[0],(parent_basis.inverse()*desired[bone]).get_rotation_quaternion().normalized())
            var baseline = idle.find_track(result.track_get_path(position_tracks[bone]),Animation.TYPE_POSITION_3D)
            var position = idle.position_track_interpolate(baseline,0) if baseline >= 0 else rig.get_bone_rest(bone).origin
            result.position_track_insert_key(position_tracks[bone],key[0],position)
    return result
