extends RigidBody3D
class_name RagdollCorpse

const GRAB_DISTANCE := 3.2
const PULL_STRENGTH := 18.0
var _held_by: FirstPersonPlayer
var _floating := false

func _ready() -> void:
    contact_monitor = true
    max_contacts_reported = 2

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("Interact"):
        var player := get_tree().get_first_node_in_group("player") as FirstPersonPlayer
        if player != null and player.get_view_camera().global_position.distance_to(global_position) <= GRAB_DISTANCE:
            var query := PhysicsRayQueryParameters3D.create(player.get_view_camera().global_position, global_position)
            query.exclude = [player.get_rid()]
            var hit := get_world_3d().direct_space_state.intersect_ray(query)
            if hit.is_empty() or hit.collider == self:
                _held_by = player
                freeze = true
                get_viewport().set_input_as_handled()
    elif event.is_action_released("Interact") and _held_by != null:
        _held_by = null
        freeze = false

func _physics_process(delta: float) -> void:
    if _held_by != null and is_instance_valid(_held_by):
        var target := _held_by.get_view_camera().global_position - _held_by.get_view_camera().global_basis.z * 2.0
        global_position = global_position.lerp(target, clampf(delta * PULL_STRENGTH, 0.0, 1.0))
        linear_velocity = Vector3.ZERO
        angular_velocity = Vector3.ZERO
        return
    var player := get_tree().get_first_node_in_group("player") as FirstPersonPlayer
    if player == null: return
    var terrain := player.get("_terrain") as InfiniteTerrain
    if terrain == null: return
    var world := terrain.local_to_world_position(global_position)
    if terrain.has_water_at(Vector2(world.x, world.z)):
        freeze = false
        linear_velocity.y = maxf(linear_velocity.y, 0.0)
        var current := Vector2(sin(world.z * .002), cos(world.x * .002)) * .45
        linear_velocity.x = lerpf(linear_velocity.x, current.x, delta)
        linear_velocity.z = lerpf(linear_velocity.z, current.y, delta)
