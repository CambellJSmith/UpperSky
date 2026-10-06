extends RefCounted
class_name CampGeometry

var _wood: StandardMaterial3D = _material(Color(0.25, 0.13, 0.06))
var _cut_wood: StandardMaterial3D = _material(Color(0.65, 0.43, 0.23))
var _stone: StandardMaterial3D = _material(Color(0.32, 0.33, 0.35))
var _metal: StandardMaterial3D = _material(Color(0.48, 0.52, 0.56))
var _canvas: StandardMaterial3D

func build(sampler: CampSampler, centre: Vector2, yaw: float, seed_value: int) -> Node3D:
    var camp: Node3D = Node3D.new()
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = seed_value
    _canvas = _material(Color(0.48 + rng.randf() * 0.12, 0.34, 0.19))
    var fire: Node3D = _anchor(camp, sampler, centre, Vector2.ZERO, yaw)
    fire.name = "Campfire"
    for index: int in range(12):
        var angle: float = TAU * float(index) / 12.0
        _mesh(fire, _sphere(0.21, 0.3), _stone, Vector3(cos(angle) * 0.9, 0.12, sin(angle) * 0.9))
    for index: int in range(3):
        var log_node: MeshInstance3D = _mesh(fire, _cylinder(0.12, 1.25), _wood, Vector3(0.0, 0.18 + index * 0.07, 0.0))
        log_node.rotation = Vector3(PI / 2.0, float(index) * PI / 3.0, 0.0)
    var flame_material: StandardMaterial3D = _material(Color(1.0, 0.36, 0.025))
    flame_material.emission_enabled = true
    flame_material.emission = Color(1.0, 0.20, 0.01)
    flame_material.emission_energy_multiplier = 3.0
    for index: int in range(3):
        var flame: CylinderMesh = CylinderMesh.new()
        flame.bottom_radius = 0.22
        flame.top_radius = 0.0
        flame.height = 0.65 + float(index) * 0.14
        _mesh(fire, flame, flame_material, Vector3(float(index - 1) * 0.19, 0.60, 0.0))
    var light: OmniLight3D = OmniLight3D.new()
    light.position.y = 1.1
    light.light_color = Color(1.0, 0.48, 0.16)
    light.light_energy = 1.5
    light.omni_range = 9.0
    fire.add_child(light)
    var tent_count: int = rng.randi_range(2, 4)
    for index: int in range(tent_count):
        var angle: float = TAU * float(index) / float(tent_count) + yaw
        var offset: Vector2 = Vector2(cos(angle), sin(angle)) * 6.5
        var tent: Node3D = _anchor(camp, sampler, centre, offset, atan2(offset.x, offset.y))
        tent.name = "Tent%d" % index
        _tent(tent)
    for index: int in range(2):
        var offset: Vector2 = Vector2(-3.0 + float(index) * 6.0, 2.5).rotated(yaw)
        var stump: Node3D = _anchor(camp, sampler, centre, offset, yaw + float(index))
        stump.name = "ChoppingStump%d" % index
        _mesh(stump, _cylinder(0.46, 0.7), _wood, Vector3(0.0, 0.35, 0.0), true)
        _mesh(stump, _cylinder(0.45, 0.035), _cut_wood, Vector3(0.0, 0.707, 0.0))
        var axe: Node3D = Node3D.new()
        axe.name = "Axe"
        axe.position = Vector3(0.0, 0.70, 0.0)
        axe.rotation.z = -0.3
        stump.add_child(axe)
        _mesh(axe, _cylinder(0.035, 0.85), _cut_wood, Vector3(0.0, 0.32, 0.0))
        _mesh(axe, _box(Vector3(0.36, 0.22, 0.07)), _metal, Vector3(0.10, 0.06, 0.0))
        _mesh(axe, _box(Vector3(0.035, 0.24, 0.075)), _stone, Vector3(0.28, 0.06, 0.0))
    return camp

func _anchor(camp: Node3D, sampler: CampSampler, centre: Vector2, offset: Vector2, yaw: float) -> Node3D:
    var root: Node3D = Node3D.new()
    root.position = Vector3(offset.x, sampler.ground_height(centre + offset) - sampler.ground_height(centre), offset.y)
    root.rotation.y = yaw
    camp.add_child(root)
    return root

func _tent(root: Node3D) -> void:
    # Open front, two sloping canvas panels, and a closed triangular rear.
    var surface: SurfaceTool = SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var vertices: Array[Vector3] = [Vector3(-1.6, 0.0, -1.8), Vector3(0.0, 2.0, -1.8), Vector3(0.0, 2.0, 1.8), Vector3(-1.6, 0.0, 1.8), Vector3(1.6, 0.0, -1.8), Vector3(1.6, 0.0, 1.8)]
    for index: int in [0, 1, 2, 0, 2, 3, 1, 4, 5, 1, 5, 2, 3, 2, 5]:
        surface.add_vertex(vertices[index])
    surface.generate_normals()
    var canvas: MeshInstance3D = _mesh(root, surface.commit(), _canvas, Vector3.ZERO)
    canvas.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
    var body: StaticBody3D = StaticBody3D.new()
    var shape: CollisionShape3D = CollisionShape3D.new()
    shape.shape = canvas.mesh.create_trimesh_shape()
    body.add_child(shape)
    root.add_child(body)
    for z: float in [-1.8, 1.8]:
        _mesh(root, _cylinder(0.045, 2.05), _wood, Vector3(0.0, 1.0, z))
    var ridge: MeshInstance3D = _mesh(root, _cylinder(0.05, 3.8), _wood, Vector3(0.0, 2.0, 0.0))
    ridge.rotation.x = PI / 2.0
    _bedroll(root)

func _bedroll(tent: Node3D) -> void:
    var bedroll: CampBedroll = CampBedroll.new()
    bedroll.name = "Bedroll"
    bedroll.position = Vector3(0.0, 0.025, 0.15)
    tent.add_child(bedroll)
    var blanket: StandardMaterial3D = _material(Color(0.23, 0.29, 0.20))
    var pillow: StandardMaterial3D = _material(Color(0.69, 0.62, 0.44))
    _mesh(bedroll, _box(Vector3(0.9, 0.12, 1.85)), blanket, Vector3(0.0, 0.06, 0.0))
    _mesh(bedroll, _box(Vector3(0.64, 0.16, 0.33)), pillow, Vector3(0.0, 0.17, 0.63))
    var roll: MeshInstance3D = _mesh(bedroll, _cylinder(0.13, 0.9), blanket, Vector3(0.0, 0.13, -0.82))
    roll.rotation.z = PI / 2.0

func _mesh(parent: Node3D, mesh: Mesh, material: Material, position: Vector3, collision: bool = false) -> MeshInstance3D:
    var visual: MeshInstance3D = MeshInstance3D.new()
    visual.mesh = mesh
    visual.material_override = material
    visual.position = position
    parent.add_child(visual)
    if collision:
        var body: StaticBody3D = StaticBody3D.new()
        var shape: CollisionShape3D = CollisionShape3D.new()
        shape.shape = mesh.create_convex_shape()
        body.add_child(shape)
        visual.add_child(body)
    return visual

func _material(colour: Color) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = colour
    material.roughness = 0.9
    return material

func _cylinder(radius: float, height: float) -> CylinderMesh:
    var mesh: CylinderMesh = CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 10
    return mesh

func _sphere(radius: float, height: float) -> SphereMesh:
    var mesh: SphereMesh = SphereMesh.new()
    mesh.radius = radius
    mesh.height = height
    mesh.radial_segments = 8
    mesh.rings = 4
    return mesh

func _box(size: Vector3) -> BoxMesh:
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = size
    return mesh
