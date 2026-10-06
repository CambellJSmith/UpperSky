extends RefCounted
class_name FerryGeometry

static func wood(colour: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = colour
    material.roughness = .95
    return material

static func dock(definition: Dictionary, terrain: InfiniteTerrain) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = "WoodenDock"
    body.collision_layer = 1
    body.collision_mask = 0
    var land: Vector2 = definition.land
    var tip: Vector2 = definition.tip
    var a := Vector3(land.x,definition.land_height,land.y)
    var b := Vector3(tip.x,definition.height,tip.y)
    var direction := (tip-land).normalized()
    var across := Vector3(-direction.y,0,direction.x)
    var timber := wood(Color(.32,.215,.12))
    var planks := wood(Color(.43,.30,.18))
    RoadBridge._beam(body,a-Vector3.UP*.12,b-Vector3.UP*.12,3.2,.24,timber,true)
    var count := ceili(land.distance_to(tip)/.65)
    for i in range(count+1):
        var p := a.lerp(b,float(i)/count)
        RoadBridge._beam(body,p-across*1.6,p+across*1.6,.56,.045,planks,false)
    var ground := CampSampler.new(terrain)
    var posts := ceili(land.distance_to(tip)/5)
    for i in range(1,posts+1):
        var p := a.lerp(b,float(i)/posts)
        for side in [-1,1]:
            var top: Vector3 = p+across*1.45*side
            var bottom: Vector3 = top
            bottom.y = ground.ground_height(Vector2(top.x,top.z))-.3
            RoadBridge._beam(body,bottom,top+Vector3.UP*.65,.22,.22,timber,false)
    # Mooring cleats and a simple sign make the landing recognizable.
    RoadBridge._beam(body,b+across*1.25,b+across*1.25+Vector3.UP*.5,.18,.18,timber,false)
    RoadBridge._beam(body,a+across*2,a+across*2+Vector3.UP*2,.18,.18,timber,false)
    var label := Label3D.new()
    label.text = "FERRY"
    label.font_size = 48
    label.pixel_size = .008
    label.position = a+across*2+Vector3.UP*2.1
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    body.add_child(label)
    CityStaticBatch.build_sync(body)
    for child in body.get_children():
        if child is MeshInstance3D and child.mesh == null: child.free()
    return body

static func boat() -> Node3D:
    var body := Node3D.new()
    body.name = "WoodenFerryBoat"
    var timber := wood(Color(.29,.17,.085))
    var trim := wood(Color(.46,.31,.16))
    # Faceted open hull: narrow keel, broad gunwales and tapered bow/stern.
    var top: Array[Vector3] = [Vector3(0,.5,-2.6),Vector3(1.15,.5,-1.45),Vector3(1.2,.5,1.4),Vector3(0,.5,2.3),Vector3(-1.2,.5,1.4),Vector3(-1.15,.5,-1.45)]
    var bottom: Array[Vector3] = []
    for p in top: bottom.append(Vector3(p.x*.55,-.3,p.z*.8))
    var stream := SurfaceTool.new()
    stream.begin(Mesh.PRIMITIVE_TRIANGLES)
    for i in range(top.size()):
        var j := (i+1)%top.size()
        for vertex in [bottom[i],top[i],top[j],bottom[i],top[j],bottom[j],Vector3(0,-.3,0),bottom[j],bottom[i]]: stream.add_vertex(vertex)
    stream.generate_normals()
    var mesh := stream.commit()
    timber.cull_mode = BaseMaterial3D.CULL_DISABLED
    mesh.surface_set_material(0,timber)
    var hull := MeshInstance3D.new()
    hull.mesh = mesh
    body.add_child(hull)
    for i in range(top.size()): RoadBridge._beam_visual(body,top[i],top[(i+1)%top.size()],.1,.12,trim)
    for z in [-1.1,.35,1.25]: RoadBridge._beam_visual(body,Vector3(-.95,.25,z),Vector3(.95,.25,z),.35,.1,trim)
    RoadBridge._beam_visual(body,Vector3(0,.05,-.7),Vector3(0,3.8,-.7),.13,.13,timber)
    RoadBridge._beam_visual(body,Vector3(-1.15,3.25,-.7),Vector3(1.15,3.25,-.7),.09,.09,trim)
    var sail := SurfaceTool.new()
    sail.begin(Mesh.PRIMITIVE_TRIANGLES)
    for p in [Vector3(-1.1,3.2,-.7),Vector3(0,1.2,-.9),Vector3(1.1,3.2,-.7)]: sail.add_vertex(p)
    sail.generate_normals()
    var cloth := wood(Color(.81,.75,.58))
    cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
    var canvas := MeshInstance3D.new()
    canvas.mesh = sail.commit()
    canvas.mesh.surface_set_material(0,cloth)
    body.add_child(canvas)
    return body
