extends RigidBody3D
class_name RagdollCorpse

const GRAB_DISTANCE := 3.2
const PULL_STRENGTH := 18.0
var _held_by: FirstPersonPlayer
var _floating := false

func _ready() -> void:
    contact_monitor = true
    max_contacts_reported = 2
    call_deferred("_start_full_ragdoll")

func _start_full_ragdoll() -> void:
    var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
    if skeleton == null: return
    freeze = true
    collision_layer = 0
    collision_mask = 0
    var simulator := PhysicalBoneSimulator3D.new()
    simulator.name = "FullSkeletonSimulator"
    skeleton.add_child(simulator)
    for index in range(skeleton.get_bone_count()):
        var bone_name := skeleton.get_bone_name(index)
        if bone_name.is_empty(): continue
        var physical := PhysicalBone3D.new()
        physical.name = "Ragdoll_%s" % bone_name
        physical.bone_name = bone_name
        physical.collision_layer = 4
        physical.collision_mask = 1 | 4
        physical.mass = 0.35 if skeleton.get_bone_parent(index) >= 0 else 1.0
        var pose := skeleton.get_bone_global_pose(index)
        physical.position = pose.origin
        physical.basis = pose.basis
        var shape := CollisionShape3D.new()
        var capsule := CapsuleShape3D.new()
        capsule.radius = 0.11
        capsule.height = 0.22
        shape.shape = capsule
        physical.add_child(shape)
        skeleton.add_child(physical)
    simulator.physical_bones_start_simulation()

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
    var water: Dictionary = terrain.get_water_sample_at(Vector2(world.x, world.z)) # Resolves the actual occupied surface and planned current.
    if bool(water.present) and world.y <= float(water.surface_height): # Applies water behaviour only after immersion rather than throughout the sky above a lake.
        freeze = false
        linear_velocity.y = maxf(linear_velocity.y, 0.0)
        var current: Vector2 = Vector2(water.flow) * .45 # Follows river drainage while keeping closed lakes still.
        linear_velocity.x = lerpf(linear_velocity.x, current.x, delta)
        linear_velocity.z = lerpf(linear_velocity.z, current.y, delta)
