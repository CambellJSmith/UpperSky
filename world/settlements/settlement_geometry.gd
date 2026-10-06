extends RefCounted
class_name SettlementGeometry

var _sampler: SettlementSampler
var _definition: Dictionary
var _root: Node3D

func build_furniture(sampler: SettlementSampler, definition: Dictionary) -> Node3D:
    _sampler = sampler
    _definition = definition
    _root = Node3D.new()
    _root.name = "VillageFurniture"
    # Paths are owned by the shared world path streamer; only plaza furniture lives here.
    _well(Vector2(-5,5))
    return _root

func _vertex(local: Vector2, lift: float) -> Vector3:
    var point: Vector2 = _definition["position"]+SettlementSampler.rotate(local,_definition["yaw"])
    return Vector3(local.x,_sampler.ground_height(point)-_definition["height"]+lift,local.y)

func _box(parent: Node3D, name_value: String, centre: Vector3, size: Vector3, colour: Color, collision: bool = false) -> MeshInstance3D:
    var mesh = BoxMesh.new()
    mesh.size = size
    var material = StandardMaterial3D.new()
    material.albedo_color = colour
    material.roughness = .9
    var node = MeshInstance3D.new()
    node.name = name_value
    node.mesh = mesh
    node.material_override = material
    node.position = centre
    parent.add_child(node)
    if collision:
        var body = StaticBody3D.new()
        var shape_node = CollisionShape3D.new()
        var shape = BoxShape3D.new()
        shape.size = size
        shape_node.shape = shape
        body.add_child(shape_node)
        node.add_child(body)
    return node

func _well(point: Vector2):
    var root = Node3D.new()
    root.name = "VillageWell"
    root.position = _vertex(point,.09)
    _root.add_child(root)
    for i in range(12):
        var angle: float = TAU*i/12.0
        var stone = _box(root,"WellStone",Vector3(cos(angle)*.80,.40,sin(angle)*.80),Vector3(.43,.8,.30),Color("797c70"),true)
        stone.rotation.y = -angle+PI*.5
    var water = MeshInstance3D.new()
    var mesh = CylinderMesh.new()
    mesh.top_radius = .62
    mesh.bottom_radius = .62
    mesh.height = .03
    mesh.radial_segments = 12
    water.mesh = mesh
    water.position.y = .45
    var material = StandardMaterial3D.new()
    material.albedo_color = Color("294b51")
    water.material_override = material
    root.add_child(water)
    for x in [-.9,.9]:
        _box(root,"WellPost",Vector3(x,1.3,0),Vector3(.13,2.6,.13),Color("57422f"),true)
    _box(root,"WellCrossbeam",Vector3(0,2.4,0),Vector3(2.2,.16,.16),Color("57422f"))
    for side in [-1,1]:
        var roof = _box(root,"WellCanopy",Vector3(side*.60,2.63,0),Vector3(1.45,.10,1.65),Color("45525b"))
        roof.rotation.z = -side*.40
    _box(root,"WellRope",Vector3(0,1.5,0),Vector3(.025,1.7,.025),Color("b19a6e"))
