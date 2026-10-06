extends Area3D
class_name CampBedroll

const INTERACTION_COLLISION_LAYER: int = 1 << 8
const REST_HOURS: float = 8.0

func _init() -> void:
    collision_layer = INTERACTION_COLLISION_LAYER
    collision_mask = 0
    monitoring = false
    var shape: CollisionShape3D = CollisionShape3D.new()
    var box: BoxShape3D = BoxShape3D.new()
    box.size = Vector3(0.95, 0.28, 2.05)
    shape.shape = box
    shape.position.y = 0.14
    add_child(shape)

func rest(cycle: DayNightCycle) -> bool:
    if cycle == null or not is_inside_tree() or not is_visible_in_tree() or not can_process():
        return false
    cycle.set_time_of_day_hours(cycle.get_time_of_day_hours() + REST_HOURS)
    return true
