extends EquippedItem # Provides reusable first-person melee behaviour for PNG-based weapons and tools.
class_name MeleeEquipment # Exposes the melee runtime type for authored held-item scenes.

const RECEIVER_SEARCH_DEPTH: int = 4 # Bounds parent traversal when locating an equipment-hit receiver.

var _rest_position: Vector3 = Vector3.ZERO # Stores the authored held-item position used after each swing.
var _rest_rotation: Vector3 = Vector3.ZERO # Stores the authored held-item rotation used after each swing.
var _swing_tween: Tween # Owns the active staged swing animation so it can be replaced safely.

func _ready() -> void: # Captures the authored pose before runtime swing motion begins.
    _rest_position = position # Preserves the scene-defined held-item position.
    _rest_rotation = rotation # Preserves the scene-defined held-item rotation.

func _perform_primary_use() -> bool: # Starts a staged melee swing when the required equipment dependencies are available.
    if _definition == null or _player == null or _camera == null: # Rejects use when equipment initialization is incomplete.
        return false # Prevents animation and hit work without valid dependencies.
    _play_use_motion() # Runs the appropriate weapon or tool swing and schedules contact at the strike phase.
    return true # Reports that the primary action was accepted.

func _apply_melee_hit() -> void: # Resolves the melee ray exactly when the animated strike reaches its contact pose.
    if _definition == null or _player == null or _camera == null: # Revalidates dependencies because impact happens after the input frame.
        return # Stops safely if the equipped item was invalidated before contact.
    var ray_origin: Vector3 = _camera.global_position # Starts the interaction ray at the active first-person camera.
    var ray_direction: Vector3 = -_camera.global_transform.basis.z.normalized() # Aims the interaction ray through the current view direction.
    var ray_end: Vector3 = ray_origin + ray_direction * _definition.reach # Limits the interaction ray to the equipped definition's reach.
    var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end) # Builds a strongly typed 3D ray query for the melee contact.
    var excluded_bodies: Array[RID] = [_player.get_rid()] # Excludes the player body so the held item cannot strike its owner.
    query.exclude = excluded_bodies # Applies the player exclusion list to the ray query.
    query.collide_with_bodies = true # Allows ordinary physics bodies to receive melee contact.
    query.collide_with_areas = true # Allows interaction areas to receive melee contact.
    var result: Dictionary = _camera.get_world_3d().direct_space_state.intersect_ray(query) # Executes the contact test against the current physics world.
    if result.is_empty(): # Detects a swing that did not intersect an eligible collider.
        return # Ends the contact phase without creating a hit payload.
    var collider: Object = result.get("collider") # Retrieves the collider returned by the physics query.
    var receiver: Object = _find_hit_receiver(collider) # Resolves the collider or nearby parent responsible for equipment hits.
    if receiver == null: # Detects world geometry that does not implement equipment-hit handling.
        return # Leaves non-interactive geometry unaffected.
    var hit_position: Vector3 = result.get("position", ray_end) # Reads the exact world-space contact position with a safe ray-end fallback.
    var hit_normal: Vector3 = result.get("normal", Vector3.UP) # Reads the world-space contact normal with a stable fallback.
    var hit: EquipmentHit = EquipmentHit.create(_player, _definition, hit_position, hit_normal) # Packages equipment, source, and contact data for the target.
    receiver.call("receive_equipment_hit", hit) # Delivers the strongly structured hit to the resolved receiver.

func _find_hit_receiver(collider: Object) -> Object: # Searches the collider ancestry for the nearest equipment-hit receiver.
    var current: Object = collider # Begins receiver lookup at the actual object struck by the ray.
    var depth: int = 0 # Tracks bounded ancestry traversal without walking arbitrary scene depth.
    while current != null and depth <= RECEIVER_SEARCH_DEPTH: # Visits the collider and a limited number of parent nodes.
        if current.has_method("receive_equipment_hit"): # Detects the interaction contract without coupling to a concrete target class.
            return current # Uses the nearest object that explicitly accepts equipment hits.
        if current is Node: # Checks whether ancestry traversal is valid for the current object.
            current = (current as Node).get_parent() # Continues lookup at the current node's parent.
        else: # Handles non-node colliders that cannot expose a scene-tree parent.
            break # Stops ancestry traversal when no parent relationship is available.
        depth += 1 # Advances the bounded receiver-search depth.
    return null # Reports that the struck object has no compatible equipment-hit receiver.

func _play_use_motion() -> void: # Selects a swing profile that matches the equipped item's authored category.
    if _swing_tween != null and _swing_tween.is_valid(): # Detects an existing runtime swing animation.
        _swing_tween.kill() # Prevents overlapping tweens from fighting over the same held-item transform.
    position = _rest_position # Resets the item to its authored translation before beginning a new swing.
    rotation = _rest_rotation # Resets the item to its authored rotation before beginning a new swing.
    if _definition.category == EquipmentDefinition.Category.WEAPON: # Routes weapons to a fast diagonal slash profile.
        _play_weapon_swing() # Animates a lighter lateral weapon strike.
    else: # Routes tools to a heavier overhead working motion.
        _play_tool_swing() # Animates a weightier tool chop with longer recovery.

func _play_weapon_swing() -> void: # Animates windup, diagonal strike, follow-through, and recovery for a melee weapon.
    var windup_position: Vector3 = _rest_position + Vector3(0.055, 0.035, 0.045) # Moves the weapon slightly back toward the ready shoulder before the cut.
    var windup_rotation: Vector3 = _rest_rotation + Vector3(deg_to_rad(-12.0), deg_to_rad(-24.0), deg_to_rad(34.0)) # Cocks the weapon into a diagonal preparation pose.
    var strike_position: Vector3 = _rest_position + Vector3(-0.095, -0.055, -0.035) # Drives the weapon across and forward through the visible strike path.
    var strike_rotation: Vector3 = _rest_rotation + Vector3(deg_to_rad(18.0), deg_to_rad(32.0), deg_to_rad(-46.0)) # Rotates the weapon through a broad diagonal cutting arc.
    var follow_position: Vector3 = _rest_position + Vector3(-0.12, -0.075, 0.02) # Carries momentum slightly beyond the actual impact position.
    var follow_rotation: Vector3 = _rest_rotation + Vector3(deg_to_rad(24.0), deg_to_rad(38.0), deg_to_rad(-55.0)) # Continues the blade rotation after contact instead of stopping abruptly.
    _swing_tween = create_tween() # Creates a node-bound tween that is discarded automatically with the equipped item.
    _swing_tween.set_trans(Tween.TRANS_QUAD) # Uses smooth acceleration curves across the staged weapon motion.
    _swing_tween.set_ease(Tween.EASE_IN_OUT) # Blends each weapon stage without mechanical linear movement.
    _swing_tween.tween_property(self, "position", windup_position, 0.09) # Pulls the weapon into the short anticipatory windup.
    _swing_tween.parallel().tween_property(self, "rotation", windup_rotation, 0.09) # Rotates into the windup at the same time as the translation.
    _swing_tween.tween_property(self, "position", strike_position, 0.10).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN) # Accelerates quickly through the active cutting stroke.
    _swing_tween.parallel().tween_property(self, "rotation", strike_rotation, 0.10).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN) # Drives the visual blade arc through the same strike interval.
    _swing_tween.tween_callback(_apply_melee_hit) # Applies gameplay contact when the visible weapon reaches its strike pose.
    _swing_tween.tween_property(self, "position", follow_position, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT) # Lets the weapon continue naturally after contact.
    _swing_tween.parallel().tween_property(self, "rotation", follow_rotation, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT) # Carries rotational momentum through the follow-through.
    _swing_tween.tween_property(self, "position", _rest_position, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) # Returns the weapon smoothly to the ready position.
    _swing_tween.parallel().tween_property(self, "rotation", _rest_rotation, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) # Settles the weapon back into its authored ready angle.

func _play_tool_swing() -> void: # Animates a heavier overhead work swing for pickaxes and similar tools.
    var windup_position: Vector3 = _rest_position + Vector3(0.02, 0.085, 0.055) # Raises the tool and pulls it back before the downward stroke.
    var windup_rotation: Vector3 = _rest_rotation + Vector3(deg_to_rad(-52.0), deg_to_rad(-5.0), deg_to_rad(10.0)) # Rotates the tool into a high overhead preparation pose.
    var strike_position: Vector3 = _rest_position + Vector3(-0.025, -0.105, -0.045) # Drives the tool down and slightly forward into the contact point.
    var strike_rotation: Vector3 = _rest_rotation + Vector3(deg_to_rad(50.0), deg_to_rad(7.0), deg_to_rad(-8.0)) # Rotates the tool through a forceful downward working arc.
    var follow_position: Vector3 = _rest_position + Vector3(-0.03, -0.125, 0.015) # Carries the heavy tool below contact to preserve visible momentum.
    var follow_rotation: Vector3 = _rest_rotation + Vector3(deg_to_rad(58.0), deg_to_rad(8.0), deg_to_rad(-10.0)) # Continues the tool rotation briefly after impact.
    _swing_tween = create_tween() # Creates a node-bound tween for the complete staged tool motion.
    _swing_tween.set_trans(Tween.TRANS_QUAD) # Uses smooth acceleration curves while retaining a weighty feel.
    _swing_tween.set_ease(Tween.EASE_IN_OUT) # Blends preparation and recovery without abrupt transform changes.
    _swing_tween.tween_property(self, "position", windup_position, 0.15) # Raises the tool into a visibly heavier windup.
    _swing_tween.parallel().tween_property(self, "rotation", windup_rotation, 0.15) # Rotates overhead throughout the windup translation.
    _swing_tween.tween_property(self, "position", strike_position, 0.13).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN) # Accelerates the tool down through the active impact stroke.
    _swing_tween.parallel().tween_property(self, "rotation", strike_rotation, 0.13).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN) # Rotates through the heavy impact arc alongside the translation.
    _swing_tween.tween_callback(_apply_melee_hit) # Applies gameplay contact only when the visible tool reaches impact.
    _swing_tween.tween_property(self, "position", follow_position, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT) # Lets the tool sink slightly through the contact before recovery.
    _swing_tween.parallel().tween_property(self, "rotation", follow_rotation, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT) # Preserves rotational follow-through after the strike.
    _swing_tween.tween_property(self, "position", _rest_position, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) # Returns the heavier tool to its ready position at a slower rate.
    _swing_tween.parallel().tween_property(self, "rotation", _rest_rotation, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) # Settles the tool back into its authored ready angle.
