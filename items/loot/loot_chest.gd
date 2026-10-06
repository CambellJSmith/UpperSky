extends StaticBody3D
class_name LootChest
var loot_key: String
var seed_value: int
var _record: Dictionary
var _lid: MeshInstance3D
func _ready():
    collision_layer = 1
    _record = LootSession.get_record(loot_key,seed_value)
    _box(Vector3(0,.28,0),Vector3(1.15,.56,.70),Color("65492f"))
    _lid = _box(Vector3(0,.60,0),Vector3(1.22,.13,.76),Color("7e5c39"))
    for x in [-.42,.42]: _box(Vector3(x,.36,-.36),Vector3(.075,.58,.035),Color("404346"))
    _box(Vector3(0,.47,-.39),Vector3(.13,.17,.05),Color("b09953"))
    var collider = CollisionShape3D.new()
    var shape = BoxShape3D.new()
    shape.size = Vector3(1.22,.73,.76)
    collider.shape = shape
    collider.position.y = .36
    add_child(collider)
func _box(point: Vector3,size_value: Vector3,colour: Color) -> MeshInstance3D:
    var node = MeshInstance3D.new()
    var mesh = BoxMesh.new()
    mesh.size = size_value
    node.mesh = mesh
    node.position = point
    var material = StandardMaterial3D.new()
    material.albedo_color = colour
    material.roughness = .9
    node.material_override = material
    add_child(node)
    return node
func get_loot_inventory() -> LootStorage: return _record.inventory
func get_loot_title() -> String: return "Wooden chest"
func set_loot_open(open: bool):
    _lid.rotation.x = -.65 if open else 0.0
