extends Node3D

var caster: WeakRef
var direction := Vector3.ZERO
var damage := 20.0
var lifetime := 3.0
const SPEED := 16.0

func launch(source: Node3D, aim: Vector3, amount: float):
    caster = weakref(source)
    global_position = source.global_position+Vector3.UP*1.2
    direction = (aim-global_position).normalized()
    damage = amount
    var visual := MeshInstance3D.new()
    var mesh := SphereMesh.new()
    mesh.radius = .18
    mesh.height = .36
    mesh.radial_segments = 8
    mesh.rings = 4
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(1,.3,.03)
    material.emission_enabled = true
    material.emission = Color(1,.15,.01)
    mesh.material = material
    visual.mesh = mesh
    add_child(visual)

func _physics_process(delta: float):
    lifetime -= delta
    if lifetime <= 0: queue_free(); return
    var next := global_position+direction*SPEED*delta
    var query := PhysicsRayQueryParameters3D.create(global_position,next,1|4)
    var source = caster.get_ref() if caster != null else null
    if is_instance_valid(source): query.exclude = [source.get_rid()]
    var contact := get_world_3d().direct_space_state.intersect_ray(query)
    if not contact.is_empty():
        var body = contact.collider
        var hit := EquipmentHit.new()
        hit.source = source
        hit.damage = damage
        hit.position = contact.position
        if body.has_method("receive_equipment_hit"): body.receive_equipment_hit(hit)
        elif body.has_method("get_health_state"): body.get_health_state().apply_damage(damage)
        queue_free()
    else: global_position = next
