extends Area3D
class_name Wayshrine
const INTERACTION_COLLISION_LAYER: int = 1 << 9
var definition: Dictionary
var _crystal: Node3D
var _glow: StandardMaterial3D
var _light: OmniLight3D
var _clock: float = 0
var _active: bool = false
func _ready():
    collision_layer = INTERACTION_COLLISION_LAYER
    collision_mask = 0
    monitoring = false
    rotation.y = definition.yaw
    var stone = material([Color("566779"),Color("655b83"),Color("83775d")][definition.style])
    var dark = material(Color("2c3542"))
    var gold = material(Color("aa8950"))
    gold.metallic = .65
    _glow = material(Color("53727b"))
    _glow.emission_enabled = true
    _glow.emission = Color("3de9cd")
    _glow.emission_energy_multiplier = .12
    cylinder(3.1,.28,Vector3(0,-.08,0),dark,8,true)
    cylinder(2.8,.32,Vector3(0,.20,0),stone,8,true)
    cylinder(2.3,.15,Vector3(0,.43,0),dark,8,true)
    for side in [-1,1]:
        var x: float = side*1.6
        box(Vector3(.9,.25,1),Vector3(x,.6,0),gold)
        box(Vector3(.7,3.1,.8),Vector3(x,2.1,0),stone,true)
        box(Vector3(.95,.25,1.05),Vector3(x,3.7,0),gold)
        for rune in range(4):
            var glyph = box(Vector3(.22,.22,.025),Vector3(x,1.1+rune*.55,.414),_glow)
            glyph.rotation.z = PI/4
        var buttress = box(Vector3(.5,1.45,.6),Vector3(x+side*.5,1.0,0),dark,true)
        buttress.rotation.z = side*-.18
    var crown = box(Vector3(4.1,.55,1.1),Vector3(0,4.05,0),stone,true)
    crown.rotation.z = [.0,.08,-.08][definition.style]
    cylinder(.4,.35,Vector3(0,4.48,0),gold,6)
    box(Vector3(3.7,.08,.04),Vector3(0,3.92,.565),gold)
    var crest = box(Vector3(.32,.32,.04),Vector3(0,4.08,.57),_glow)
    crest.rotation.z = PI/4
    if definition.style == 1:
        for side in [-1,1]:
            var fin = box(Vector3(.22,.85,.3),Vector3(side*1.9,4.3,0),gold)
            fin.rotation.z = side*-.25
    elif definition.style == 2:
        for side in [-1,1]: cylinder(.45,.45,Vector3(side*1.6,4.13,0),gold,5)
    _crystal = Node3D.new()
    add_child(_crystal)
    _crystal.position = Vector3(0,2.25,0)
    for sign_value in [-1,1]:
        var mesh = CylinderMesh.new()
        mesh.top_radius = 0 if sign_value > 0 else .35
        mesh.bottom_radius = .35 if sign_value > 0 else 0
        mesh.height = .7
        mesh.radial_segments = 5
        var part = MeshInstance3D.new()
        part.mesh = mesh
        part.material_override = _glow
        part.position.y = sign_value*.35
        _crystal.add_child(part)
    for i in range(8):
        var angle = i*TAU/8
        var rune = box(Vector3(.22,.45,.22),Vector3(cos(angle)*1.05,.8,sin(angle)*1.05),_glow)
        rune.rotation.y = angle
    var shape = CollisionShape3D.new()
    var bounds = BoxShape3D.new()
    bounds.size = Vector3(3.7,4.4,1.6)
    shape.shape = bounds
    shape.position.y = 2.2
    add_child(shape)
    _light = OmniLight3D.new()
    _light.position.y = 2.3
    _light.light_color = Color("5cebd1")
    _light.omni_range = 7
    _light.distance_fade_enabled = true
    _light.distance_fade_begin = 70
    _light.distance_fade_length = 30
    add_child(_light)
    _update_activation()
func material(color: Color) -> StandardMaterial3D:
    var result = StandardMaterial3D.new()
    result.albedo_color = color
    result.roughness = .85
    return result
func box(size: Vector3, point: Vector3, mat: Material, solid: bool = false) -> MeshInstance3D:
    var mesh = BoxMesh.new()
    mesh.size = size
    return piece(mesh,point,mat,BoxShape3D.new() if solid else null)
func cylinder(radius: float, height: float, point: Vector3, mat: Material, sides: int, solid: bool = false):
    var mesh = CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = sides
    piece(mesh,point,mat,CylinderShape3D.new() if solid else null)
func piece(mesh: Mesh, point: Vector3, mat: Material, collision: Shape3D) -> MeshInstance3D:
    var visual = MeshInstance3D.new()
    visual.mesh = mesh
    visual.material_override = mat
    visual.position = point
    add_child(visual)
    if collision != null:
        if collision is BoxShape3D: collision.size = mesh.size
        if collision is CylinderShape3D:
            collision.radius = mesh.top_radius
            collision.height = mesh.height
        var body = StaticBody3D.new()
        visual.add_child(body)
        var shape = CollisionShape3D.new()
        shape.shape = collision
        body.add_child(shape)
    return visual
func _update_activation():
    _active = WayshrineRegistry.is_activated(definition.id)
    _glow.emission_energy_multiplier = 2.5 if _active else .12
    _glow.albedo_color = Color("9effe3") if _active else Color("53727b")
    _light.light_energy = 1.3 if _active else .12
func _process(delta: float):
    if _active != WayshrineRegistry.is_activated(definition.id): _update_activation()
    _clock += delta
    _crystal.position.y = 2.25+sin(_clock*1.8)*.12
    _crystal.rotation.y += delta*(.65 if _active else .15)
