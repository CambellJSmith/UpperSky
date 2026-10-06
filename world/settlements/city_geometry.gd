extends RefCounted
class_name CityGeometry

const STONE := Color(.43,.46,.49)
const DARK_STONE := Color(.28,.31,.34)
const WOOD := Color(.32,.19,.09)

static func is_city(definition: Dictionary) -> bool:
    return int(definition.seed) % 3 == 0

static func city_name(seed_value: int) -> String:
    var names := ["Stonewatch","Ravenhold","Kingsford","Greyhaven","Oakguard","Ashwick","Highcrest","Redwater"]
    return names[posmod(seed_value/3,names.size())]

static func exterior_reserved(local: Vector2, padding: float = 0.0) -> bool:
    return Rect2(-65,-65,130,130).grow(padding).has_point(local) or Rect2(-7,60,14,37).grow(padding).has_point(local)

static func box(root: Node3D, size: Vector3, offset: Vector3, color: Color, collision: bool = true) -> MeshInstance3D:
    var mesh := MeshInstance3D.new()
    var geometry := BoxMesh.new()
    geometry.size = size
    mesh.mesh = geometry
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = .92
    mesh.material_override = material
    mesh.position = offset
    root.add_child(mesh)
    if collision:
        var body := StaticBody3D.new()
        body.collision_layer = 1
        var shape := CollisionShape3D.new()
        var bounds := BoxShape3D.new()
        bounds.size = size
        shape.shape = bounds
        body.add_child(shape)
        mesh.add_child(body)
    return mesh

static func tower(root: Node3D, offset: Vector3, height: float, radius: float) -> void:
    var mesh := MeshInstance3D.new()
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = radius
    cylinder.bottom_radius = radius * 1.1
    cylinder.height = height
    cylinder.radial_segments = 10
    mesh.mesh = cylinder
    var material := StandardMaterial3D.new()
    material.albedo_color = STONE
    material.roughness = .95
    mesh.material_override = material
    mesh.position = offset + Vector3(0,height*.5,0)
    root.add_child(mesh)
    var body := StaticBody3D.new()
    var shape := CollisionShape3D.new()
    var bounds := CylinderShape3D.new()
    bounds.radius = radius*1.1
    bounds.height = height
    shape.shape = bounds
    body.add_child(shape)
    mesh.add_child(body)
    for i in range(10):
        var angle := TAU*i/10.0
        var block := box(root,Vector3(1.1,1.4,1.1),offset+Vector3(sin(angle)*radius,height+.7,cos(angle)*radius),STONE)
        block.rotation.y = angle

static func wall(root: Node3D, a: Vector2, b: Vector2, height: float, base: float = 0) -> void:
    var distance := a.distance_to(b)
    var midpoint := (a+b)*.5
    var yaw := atan2(b.x-a.x,b.y-a.y)
    var mesh := box(root,Vector3(2.4,height,distance),Vector3(midpoint.x,base+height*.5,midpoint.y),STONE)
    mesh.rotation.y = yaw
    for i in range(ceili(distance/3)):
        var point := a.lerp(b,(i+.5)/ceili(distance/3))
        var merlon := box(root,Vector3(2.5,1.25,1.3),Vector3(point.x,base+height+.625,point.y),STONE)
        merlon.rotation.y = yaw

static func exterior(definition: Dictionary) -> Node3D:
    var root := Node3D.new()
    root.set_meta("city_definition",definition)
    # A retained moat sits above the highest sampled site ground; no water clips into hills.
    var base := 1.0
    for house in definition.houses:
        base = maxf(base,float(house.height)-float(definition.height)+1.0)
    box(root,Vector3(122,base+2,122),Vector3(0,(base-2)*.5,0),DARK_STONE)
    box(root,Vector3(90,1.2,90),Vector3(0,base+.6,0),Color(.36,.39,.32))
    for side in [-1,1]:
        box(root,Vector3(12,.25,116),Vector3(side*52,base+.7,0),Color(.12,.36,.44),false)
        box(root,Vector3(92,.25,12),Vector3(0,base+.7,side*52),Color(.12,.36,.44),false)
        wall(root,Vector2(side*43,-43),Vector2(side*43,43),12,base+1.2)
    wall(root,Vector2(-43,-43),Vector2(43,-43),12,base+1.2)
    wall(root,Vector2(-43,43),Vector2(-5,43),12,base+1.2)
    wall(root,Vector2(5,43),Vector2(43,43),12,base+1.2)
    box(root,Vector3(10,5,3),Vector3(0,base+12,43),STONE)
    for x in [-43,43]:
        for z in [-43,43]: tower(root,Vector3(x,base+1.2,z),15,4)
    for x in [-7,7]: tower(root,Vector3(x,base+1.2,43),17,3.3)
    box(root,Vector3(9,.5,20),Vector3(0,base+1.35,52),WOOD)
    for side in [-1,1]:
        box(root,Vector3(.25,1.2,19),Vector3(side*4.35,base+2,52),WOOD)
        var chain := box(root,Vector3(.12,.12,15),Vector3(side*4,base+5,49),Color(.18,.19,.21),false)
        chain.rotation.x = -.5
    # A broad, gentle stone approach reaches natural ground outside the retained moat.
    var ramp := box(root,Vector3(10,.5,30),Vector3(0,(base+1.6)*.5-.25,77),DARK_STONE)
    ramp.rotation.x = atan2(base+1.6,30)
    # Cheap skyline proxies let roofs and the keep show above the exterior wall.
    # The populated, accessible streets are built only in the separate city space.
    for x in [-26,-10,10,26]:
        for z in [-22,0,22]:
            var height := 9.0 + posmod(int(definition.seed)+x+z,5)
            box(root,Vector3(8,height,11),Vector3(x,base+height*.5,z),Color(.56,.53,.45))
            var roof := MeshInstance3D.new()
            var prism := PrismMesh.new()
            prism.size = Vector3(9,3.5,12)
            roof.mesh = prism
            var material := StandardMaterial3D.new()
            material.albedo_color = Color(.24,.3,.36)
            material.roughness = .95
            roof.material_override = material
            roof.position = Vector3(x,base+height+1.75,z)
            root.add_child(roof)
    box(root,Vector3(15,19,13),Vector3(0,base+9.5,-27),STONE)
    for x in [-8,8]: tower(root,Vector3(x,base,-27),22,2.8)
    root.set_meta("city_gate",Vector3(0,base+1.6,51))
    return root

static func castle(root: Node3D) -> void:
    var origin := Vector3(0,0,-83)
    for side in [-1,1]: wall(root,Vector2(side*22,-105),Vector2(side*22,-61),8)
    wall(root,Vector2(-22,-105),Vector2(22,-105),8)
    wall(root,Vector2(-22,-61),Vector2(-5,-61),8)
    wall(root,Vector2(5,-61),Vector2(22,-61),8)
    for x in [-22,22]:
        for z in [-105,-61]: tower(root,Vector3(x,0,z),12,3.5)
    box(root,Vector3(24,13,18),origin+Vector3(0,6.5,-7),STONE)
    box(root,Vector3(25,.6,19),origin+Vector3(0,13.3,-7),DARK_STONE)
    for x in [-9,9]: tower(root,origin+Vector3(x,0,-7),18,2.8)
    for x in [-8,-4,0,4,8]:
        box(root,Vector3(1.1,2,.12),origin+Vector3(x,8.5,2.1),Color(.08,.1,.13),false)
    box(root,Vector3(3,4,.2),origin+Vector3(0,2,2.2),WOOD)
    for x in [-6,6]:
        box(root,Vector3(.15,6,.15),Vector3(x,9,-60),WOOD,false)
        box(root,Vector3(2,3,.12),Vector3(x+1,10,-60),Color(.5,.04,.06),false)
