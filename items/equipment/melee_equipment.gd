extends EquippedItem
class_name MeleeEquipment

const RECEIVER_SEARCH_DEPTH: int = 4

func _perform_primary_use() -> bool:
    if _definition == null or _player == null or _camera == null:
        return false

    var ray_origin: Vector3 = _camera.global_position
    var ray_direction: Vector3 = -_camera.global_transform.basis.z.normalized()
    var ray_end: Vector3 = ray_origin + ray_direction * _definition.reach
    var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
    var excluded_bodies: Array[RID] = [_player.get_rid()]
    query.exclude = excluded_bodies
    query.collide_with_bodies = true
    query.collide_with_areas = true

    var result: Dictionary = _camera.get_world_3d().direct_space_state.intersect_ray(query)
    _play_use_motion()
    if result.is_empty():
        return true

    var collider: Object = result.get("collider")
    var receiver: Object = _find_hit_receiver(collider)
    if receiver == null:
        return true

    var hit_position: Vector3 = result.get("position", ray_end)
    var hit_normal: Vector3 = result.get("normal", Vector3.UP)
    var hit := EquipmentHit.create(_player, _definition, hit_position, hit_normal)
    receiver.call("receive_equipment_hit", hit)
    return true

func _find_hit_receiver(collider: Object) -> Object:
    var current: Object = collider
    var depth: int = 0
    while current != null and depth <= RECEIVER_SEARCH_DEPTH:
        if current.has_method("receive_equipment_hit"):
            return current
        if current is Node:
            current = (current as Node).get_parent()
        else:
            break
        depth += 1
    return null

func _play_use_motion() -> void:
    var rest_rotation: Vector3 = rotation
    rotation.x -= deg_to_rad(18.0)
    rotation.y += deg_to_rad(7.0)
    var duration: float = 0.12
    if _definition != null:
        duration = minf(maxf(_definition.primary_cooldown * 0.45, 0.06), 0.18)
    var tween: Tween = create_tween()
    tween.set_trans(Tween.TRANS_QUAD)
    tween.set_ease(Tween.EASE_OUT)
    tween.tween_property(self, "rotation", rest_rotation, duration)
