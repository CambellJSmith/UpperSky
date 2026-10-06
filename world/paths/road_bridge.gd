extends RefCounted
class_name RoadBridge

static func build(definition: Dictionary, terrain: InfiniteTerrain, chunk: Vector2i) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = "RoadBridge"
    body.collision_layer = 1
    body.collision_mask = 0
    var origin := Vector2(chunk)*WorldPathNetwork.CHUNK_SIZE
    var a: Vector2 = definition.a
    var b: Vector2 = definition.b
    var direction := (b-a).normalized()
    var length := a.distance_to(b)
    var ramp := minf(10.0,length*.3)
    var deck_a: float = definition.get("height_a",definition.height)
    var deck_b: float = definition.get("height_b",definition.height)
    var ground := CampSampler.new(terrain)
    var start := Vector3(a.x-origin.x,ground.ground_height(a)+.06,a.y-origin.y)
    var end := Vector3(b.x-origin.x,ground.ground_height(b)+.06,b.y-origin.y)
    var top_a := Vector3(start.x+direction.x*ramp,lerpf(deck_a,deck_b,ramp/length),start.z+direction.y*ramp)
    var top_b := Vector3(end.x-direction.x*ramp,lerpf(deck_a,deck_b,1-ramp/length),end.z-direction.y*ramp)
    var wood := StandardMaterial3D.new()
    wood.albedo_color = Color(.28,.19,.11)
    wood.roughness = .95
    for pair in [[start,top_a],[top_a,top_b],[top_b,end]]:
        _beam(body,pair[0]-Vector3.UP*.12,pair[1]-Vector3.UP*.12,definition.width,.24,wood,true)
    var plank := StandardMaterial3D.new()
    plank.albedo_color = Color(.32,.225,.135)
    plank.roughness = wood.roughness
    var across: Vector3 = Vector3(-direction.y,0,direction.x)*definition.width*.5
    for i in range(1,ceili(length/2)):
        var t := i*2.0/length
        var point := start.lerp(end,t)
        var along := length*t
        if along < ramp: point.y = lerpf(start.y,top_a.y,along/ramp)
        elif along > length-ramp: point.y = lerpf(top_b.y,end.y,(along-(length-ramp))/ramp)
        else: point.y = lerpf(deck_a,deck_b,t)
        _beam(body,point-across+Vector3.UP*.015,point+across+Vector3.UP*.015,.15,.025,plank,false)
    var stone := StandardMaterial3D.new()
    stone.albedo_color = Color(.38,.37,.34)
    stone.roughness = 1.0
    for i in range(1,maxi(2,ceili(length/16))):
        var t := float(i)/maxi(2,ceili(length/16))
        var point := start.lerp(end,t)
        var world_point := Vector2(point.x,point.z)+origin
        var bottom := ground.ground_height(world_point)+.1
        var height := lerpf(deck_a,deck_b,t)-.12
        if height-bottom < 1: continue
        var wide := .45 if height-bottom < 8 else 1.4
        _beam(body,Vector3(point.x,bottom,point.z),Vector3(point.x,height,point.z),wide,wide,wood if height-bottom < 8 else stone,true)
    # Small deck boards and low rails keep crossings readable in the low-poly art.
    var count := maxi(2,ceili(length/4))
    var side: Vector3 = Vector3(-direction.y,0,direction.x)*definition.width*.48
    for sign_value in [-1,1]:
        var previous: Vector3
        for i in range(count+1):
            var p := start.lerp(end,float(i)/count)
            p.y = lerpf(deck_a,deck_b,float(i)/count)
            p += side*sign_value
            _beam(body,p-Vector3.UP*.1,p+Vector3.UP*1.0,.16,.16,wood,false)
            if i > 0: _beam(body,previous+Vector3.UP*.85,p+Vector3.UP*.85,.12,.12,wood,false)
            previous = p
    CityStaticBatch.build_sync(body)
    for child in body.get_children():
        if child is MeshInstance3D and child.mesh == null: child.free()
    return body

static func _beam(parent: StaticBody3D, a: Vector3, b: Vector3, width: float, depth: float, material: Material, collision: bool):
    var transform := Transform3D(Basis.looking_at((b-a).normalized(),Vector3.FORWARD if absf((b-a).normalized().y) > .95 else Vector3.UP),(a+b)*.5)
    var size := Vector3(width,depth,a.distance_to(b))
    var visual := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    visual.mesh = mesh
    visual.transform = transform
    parent.add_child(visual)
    if collision:
        var shape := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = size
        shape.shape = box
        shape.transform = transform
        parent.add_child(shape)

static func _beam_visual(parent: Node3D, a: Vector3, b: Vector3, width: float, depth: float, material: Material):
    var visual := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = Vector3(width,depth,a.distance_to(b))
    mesh.material = material
    visual.mesh = mesh
    visual.transform = Transform3D(Basis.looking_at((b-a).normalized(),Vector3.FORWARD if absf((b-a).normalized().y)>.95 else Vector3.UP),(a+b)*.5)
    parent.add_child(visual)
