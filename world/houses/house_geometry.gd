@tool
extends RefCounted
class_name HouseGeometry

## Solid-colour low-poly details are batched by material, not one node per brick.
var _rng: RandomNumberGenerator
var _streams: Dictionary = {}
var _materials: Dictionary = {}
var _root: Node3D
var _body: StaticBody3D
var _parameters: Dictionary
const FOUNDATION: float = .45
const BRICK_COURSE_HEIGHT: float = .32 # Keep masonry readable with fewer brick courses.
const STONE_COURSE_HEIGHT: float = .52 # Reduce small stone courses on building walls.
const BRICK_BLOCK_WIDTH: float = .70 # Use broader bricks for simpler wall relief.
const STONE_BLOCK_WIDTH: float = 1.05 # Use broader stone blocks for simpler wall relief.
const PLANK_WIDTH: float = .56 # Reduce narrow wooden siding strips.
const SLATE_ROW_SPACING: float = .70 # Reduce small slate courses on pitched roofs.
const SLATE_COLUMN_SPACING: float = .75 # Use broader slate pieces.
const THATCH_COLUMN_SPACING: float = .50 # Reduce fine thatch bundles while retaining raised folds.
const THATCH_HIP_COLUMN_SPACING: float = .65 # Simplify thatch pieces on the triangular hip ends.

func build(recipe: HouseRecipe, collisions: bool = true) -> Node3D:
    _body = null
    _streams.clear()
    _materials.clear()
    _root = Node3D.new()
    _root.name = "GeneratedHouse"
    _parameters = recipe.resolve()
    _root.set_meta("house_parameters", _parameters.duplicate())
    _rng = RandomNumberGenerator.new()
    _rng.seed = recipe.seed_value ^ 938251
    _palette(_parameters["palette"])
    if collisions:
        _body = StaticBody3D.new()
        _body.name = "SolidHouseCollision"
        _root.add_child(_body)
    var w: float = _parameters["width"]
    var d: float = _parameters["depth"]
    var floors: int = _parameters["floors"]
    _module(Vector3.ZERO, w, d, floors, _parameters["wall"], _parameters["hipped"], true)
    if _parameters["layout"] in [HouseRecipe.Layout.L_SHAPED, HouseRecipe.Layout.CROSS]:
        var wing_width: float = _rng.randf_range(3.5, 5.2)
        var wing_depth: float = d * _rng.randf_range(.42, .62)
        var wing_z: float = d*.5-wing_depth*.5 if _parameters["layout"] == HouseRecipe.Layout.L_SHAPED else 0.0
        # Lower annexes meet the main walls, giving distinct L/cross footprints.
        var wing_floors: int = maxi(1, floors-1)
        _module(Vector3(w*.5+wing_width*.5-.20, 0, wing_z), wing_width, wing_depth, wing_floors, _parameters["wall"], false, false)
        if _parameters["layout"] == HouseRecipe.Layout.CROSS:
            _module(Vector3(-w*.5-wing_width*.5+.20, 0, -.35), wing_width, wing_depth*.88, wing_floors, _parameters["wall"], false, false)
    if _parameters["porch"]:
        _porch(w, d)
    if _parameters["chimney"]:
        _chimney(w, d, floors)
    _flush()
    return _root

func _palette(index: int):
    var plaster_colours = [Color("e1d2ad"),Color("cfbea0"),Color("e4dac2"),Color("c6c9b5")]
    _add_material("plaster", plaster_colours[index])
    _add_material("mortar",Color("555b59"))
    _add_material("brick_mortar",Color("82766b"))
    _add_material("timber",Color("423027"))
    _add_material("wood",Color("795238"))
    _add_material("door",Color("65432f"))
    _add_material("trim",Color("af8151"))
    _add_material("iron",Color("30373b"))
    _add_material("glass",Color("273d44"))
    _add_material("opening",Color("17232a"))
    var brick: Color = [Color("a76850"),Color("985940"),Color("aa7a5c"),Color("875a4d")][index]
    for i in range(5):
        _add_material("brick%d"%i,brick.lightened((float(i)-2.0)*.045))
        _add_material("stone%d"%i,Color("7c827d").lightened((float(i)-2.0)*.045))
        _add_material("plank%d"%i,Color("987453").lightened((float(i)-2.0)*.04))
        _add_material("slate%d"%i,Color("455563").lightened((float(i)-2.0)*.019))
        _add_material("thatch%d"%i,Color("bba16b").lightened((float(i)-2.0)*.027))

func _add_material(key: String, colour: Color):
    var material = StandardMaterial3D.new()
    material.albedo_color = colour
    material.roughness = .93
    _materials[key] = material

func _stream(key: String) -> SurfaceTool:
    if not _streams.has(key):
        var st = SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        _streams[key] = st
    return _streams[key]

func _triangle(key: String, a: Vector3, b: Vector3, c: Vector3, normal: Vector3):
    if (b-a).cross(c-a).length_squared() < 0.00000001:
        return
    if (b-a).cross(c-a).dot(normal) > 0:
        var swap = b
        b = c
        c = swap
    var st = _stream(key)
    for vertex in [a,b,c]:
        st.set_normal(normal)
        st.add_vertex(vertex)

func _quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3):
    _triangle(key,a,b,c,normal)
    _triangle(key,a,c,d,normal)

func _box(key: String, centre: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY):
    var s: Vector3 = size*.5
    var p: Array[Vector3] = []
    for offset in [Vector3(-s.x,-s.y,-s.z),Vector3(s.x,-s.y,-s.z),Vector3(s.x,s.y,-s.z),Vector3(-s.x,s.y,-s.z),Vector3(-s.x,-s.y,s.z),Vector3(s.x,-s.y,s.z),Vector3(s.x,s.y,s.z),Vector3(-s.x,s.y,s.z)]:
        p.append(centre+basis*offset)
    for face in [[0,1,2,3,Vector3.FORWARD],[5,4,7,6,Vector3.BACK],[4,0,3,7,Vector3.LEFT],[1,5,6,2,Vector3.RIGHT],[3,2,6,7,Vector3.UP],[4,5,1,0,Vector3.DOWN]]:
        _quad(key,p[face[0]],p[face[1]],p[face[2]],p[face[3]],basis*face[4])

func _beam(key: String, start: Vector3, end: Vector3, width: float, depth: float = -1):
    var direction: Vector3 = end-start
    var basis = Basis(Quaternion(Vector3.UP,direction.normalized()))
    _box(key,(start+end)*.5,Vector3(width,direction.length(),width if depth < 0 else depth),basis)

func _collision(centre: Vector3, size: Vector3):
    if _body == null:
        return
    var shape = BoxShape3D.new()
    shape.size = size
    var node = CollisionShape3D.new()
    node.name = "Footprint"
    node.position = centre
    node.shape = shape
    _body.add_child(node)

func _module(origin: Vector3, w: float, d: float, floors: int, wall: int, hip: bool, main: bool):
    var fh: float = _parameters["floor_height"]
    var height: float = FOUNDATION+floors*fh
    var extension: float = _parameters["foundation_extension"]
    _box("mortar",origin+Vector3(0,.18-extension*.5,0),Vector3(w+.24,.62+extension,d+.24))
    _collision(origin+Vector3(0,.18-extension*.5,0),Vector3(w+.24,.62+extension,d+.24))
    for level in range(floors):
        var jetty: bool = main and _parameters["layout"] == HouseRecipe.Layout.JETTIED and level > 0
        var extra: float = .7 if jetty else 0.0
        var lw: float = w+extra
        var ld: float = d+extra*.7
        var bottom: float = FOUNDATION+level*fh
        var style: int = HouseRecipe.WallStyle.TIMBER_FRAME if jetty else wall
        var base: String = "plaster" if style == HouseRecipe.WallStyle.TIMBER_FRAME else "brick_mortar" if style == HouseRecipe.WallStyle.BRICK else "wood" if style == HouseRecipe.WallStyle.WOOD else "mortar"
        _box(base,origin+Vector3(0,bottom+fh*.5,0),Vector3(lw,fh,ld))
        for side in range(4):
            var length: float = lw if side%2 == 0 else ld
            var face_origin: Vector3 = origin+Vector3(0,bottom,0)
            var yaw: float = side*PI*.5
            var basis = Basis(Vector3.UP,yaw)
            var distance: float = ld*.5 if side%2 == 0 else lw*.5
            face_origin += basis*Vector3(0,0,-distance)
            _wall_face(face_origin,basis,length,fh,style,level, main and side==0 and level==0)
        _box("timber",origin+Vector3(0,bottom+.04,0),Vector3(lw+.12,.12,ld+.12))
        if jetty and level == 1:
            for side in [-1,1]:
                for z in [-d*.35,0,d*.35]:
                    _beam("timber",origin+Vector3(side*(w*.5-.04),bottom-.62,z),origin+Vector3(side*(lw*.5),bottom-.10,z),.15)
        _collision(origin+Vector3(0,bottom+fh*.5,0),Vector3(lw,fh,ld))
    var roof_w: float = w + (.7 if main and _parameters["layout"] == HouseRecipe.Layout.JETTIED else 0.0)
    var roof_d: float = d + (.49 if main and _parameters["layout"] == HouseRecipe.Layout.JETTIED else 0.0)
    var rise: float = roof_w*.48 if not main else _parameters["roof_rise"]
    _roof(origin+Vector3(0,height,0),roof_w,roof_d,rise,hip)
    if not hip:
        _gables(origin+Vector3(0,height,0),roof_w,roof_d,rise)

func _wall_face(origin: Vector3, basis: Basis, length: float, height: float, style: int, level: int, entrance: bool):
    var courses: int = ceili(height / (BRICK_COURSE_HEIGHT if style == HouseRecipe.WallStyle.BRICK else STONE_COURSE_HEIGHT)) # Share simpler masonry spacing across build paths.
    if style in [HouseRecipe.WallStyle.STONE,HouseRecipe.WallStyle.BRICK]:
        var brick: bool = style == HouseRecipe.WallStyle.BRICK
        var course_h: float = height/courses
        var block_w: float = BRICK_BLOCK_WIDTH if brick else STONE_BLOCK_WIDTH # Keep fewer, broader masonry blocks.
        for row in range(courses):
            var left: float = -length*.5
            var first: bool = true
            while left < length*.5-.025:
                var width: float = block_w*(.52 if first and row%2==1 else _rng.randf_range(.85,1.15))
                width = minf(width,length*.5-left)
                var key: String = ("brick%d" if brick else "stone%d")%_rng.randi_range(0,4)
                _box(key,origin+basis*Vector3(left+width*.5,(row+.5)*course_h,-.033),Vector3(maxf(.01,width-.035),course_h-.03,.075),basis)
                left += width
                first = false
    elif style == HouseRecipe.WallStyle.WOOD:
        var count: int = ceili(length / PLANK_WIDTH) # Keep fewer, broader siding planks.
        var width: float = length/count
        for i in range(count):
            _box("plank%d"%_rng.randi_range(0,4),origin+basis*Vector3(-length*.5+(i+.5)*width,height*.5,-.028),Vector3(width-.025,height-.04,.065),basis)
        for y in [.16,height-.20]:
            _box("timber",origin+basis*Vector3(0,y,-.09),Vector3(length,.12,.11),basis)
    else:
        var bays: int = maxi(2,roundi(length/2.3))
        var span: float = length/bays
        for i in range(bays+1):
            _box("timber",origin+basis*Vector3(-length*.5+i*span,height*.5,-.065),Vector3(.14,height,.14),basis)
        for y in [.1,height-.08]:
            _box("timber",origin+basis*Vector3(0,y,-.07),Vector3(length,.16,.15),basis)
        for i in range(bays):
            if i%2 == 0:
                var start = origin+basis*Vector3(-length*.5+i*span+.16,.24,-.073)
                var end = origin+basis*Vector3(-length*.5+(i+1)*span-.16,height-.24,-.073)
                _beam("timber",start,end,.10)
    # Ground-floor door and upper windows sit proud of the textured wall plane.
    if entrance:
        _door(origin,basis)
    var count: int = maxi(1,floori(length/2.8))
    for i in range(count):
        var x: float = -length*.5+(i+1.0)*length/(count+1.0)
        if entrance and absf(x) < 1.25:
            continue
        _window(origin+basis*Vector3(x,height*.57,-.115),basis,level > 0 or _rng.randf() < .65)

func _door(origin: Vector3, basis: Basis):
    _box("opening",origin+basis*Vector3(0,1.08,-.115),Vector3(1.24,2.16,.08),basis)
    for i in range(6):
        _box("door",origin+basis*Vector3(-.5+(i+.5)/6.0,1.02,-.17),Vector3(1.0/6.0-.012,2.0,.05),basis)
    for x in [-.62,.62]:
        _box("trim",origin+basis*Vector3(x,1.08,-.18),Vector3(.14,2.2,.16),basis)
    _box("trim",origin+basis*Vector3(0,2.12,-.18),Vector3(1.38,.17,.16),basis)
    for y in [.40,1.60]:
        _box("iron",origin+basis*Vector3(0,y,-.21),Vector3(.88,.055,.025),basis)
    _box("iron",origin+basis*Vector3(.32,1.02,-.235),Vector3(.07,.12,.04),basis)
    _box("stone2",origin+basis*Vector3(0,-.20,-.42),Vector3(1.6,.34,.95),basis)

func _window(origin: Vector3, basis: Basis, shutters: bool):
    _box("glass",origin,Vector3(.72,.95,.065),basis)
    for x in [-.43,0,.43]:
        _box("timber",origin+basis*Vector3(x,0,-.07),Vector3(.07,1.12,.10),basis)
    for y in [-.55,0,.55]:
        _box("timber",origin+basis*Vector3(0,y,-.07),Vector3(.92,.07,.10),basis)
    _box("trim",origin+basis*Vector3(0,-.60,-.12),Vector3(1.04,.10,.27),basis)
    if shutters:
        for sign_x in [-1,1]:
            for i in range(3):
                _box("door",origin+basis*Vector3(sign_x*(.52+(i+.5)*.10),0,-.065),Vector3(.092,1.0,.06),basis)
            for y in [-.34,.34]:
                _box("timber",origin+basis*Vector3(sign_x*.67,y,-.11),Vector3(.32,.04,.035),basis)

func _roof_point(origin: Vector3, w: float, d: float, rise: float, hip: bool, side: float, t: float, v: float) -> Vector3:
    var half_w: float = w*.5+.38
    var half_d: float = d*.5+.38
    var hip_run: float = minf(half_w*.85,half_d*.65) if hip else 0.0
    return origin+Vector3(side*half_w*(1.0-t),rise*t,v*(half_d-hip_run*t))

func _roof(origin: Vector3, w: float, d: float, rise: float, hip: bool):
    var thatch: bool = _parameters["roof"] == HouseRecipe.RoofStyle.THATCH
    var key_prefix: String = "thatch" if thatch else "slate"
    var thickness: float = .24 if thatch else .09
    for side in [-1.0,1.0]:
        var a = _roof_point(origin,w,d,rise,hip,side,0,-1)
        var b = _roof_point(origin,w,d,rise,hip,side,0,1)
        var c = _roof_point(origin,w,d,rise,hip,side,1,1)
        var dd = _roof_point(origin,w,d,rise,hip,side,1,-1)
        var normal = Vector3(side*rise,w*.5+.38,0).normalized()
        _quad(key_prefix+"0",a,b,c,dd,normal)
        _quad("timber",a-Vector3(0,thickness,0),dd-Vector3(0,thickness,0),c-Vector3(0,thickness,0),b-Vector3(0,thickness,0),Vector3.DOWN)
        var rows: int = 4 if thatch else ceili(Vector2(w*.5+.38,rise).length() / SLATE_ROW_SPACING) # Simplify slate density while retaining thatch layering.
        var columns: int = ceili((d+.76) / (THATCH_COLUMN_SPACING if thatch else SLATE_COLUMN_SPACING)) # Use fewer roof pieces without changing the roof profile.
        for row in range(rows):
            var t0: float = float(row)/rows
            var t1: float = minf(1.0,float(row+1)/rows+.015)
            var v0: float = -1.0
            var nominal: float = 2.0/columns
            var column: int = 0
            while v0 < .999:
                var stride: float = nominal*(.5 if column==0 and row%2==1 else 1.0)
                var v1: float = minf(1.0,v0+stride)
                var gap: float = .005 if thatch else .004
                var offset = normal*(thickness+_rng.randf_range(0,.018))
                var p0 = _roof_point(origin,w,d,rise,hip,side,t0,v0+gap)+offset
                var p1 = _roof_point(origin,w,d,rise,hip,side,t0,v1-gap)+offset
                var p2 = _roof_point(origin,w,d,rise,hip,side,t1,v1-gap)+offset
                var p3 = _roof_point(origin,w,d,rise,hip,side,t1,v0+gap)+offset
                var key: String = key_prefix+str(_rng.randi_range(0,4))
                _quad(key,p0,p1,p2,p3,normal)
                _quad(key_prefix+"0",p0,p0-normal*.055,p1-normal*.055,p1,Vector3(side,0,0))
                if thatch:
                    # A narrow raised fold gives thatch a bundled silhouette.
                    var centre_v: float = (v0+v1)*.5
                    var start = _roof_point(origin,w,d,rise,hip,side,t0,centre_v)+normal*(thickness+.022)
                    var end = _roof_point(origin,w,d,rise,hip,side,t1,centre_v)+normal*(thickness+.022)
                    _round_beam(key,start,end,.065)
                    if row == 0:
                        var direction: Vector3 = (end-start).normalized()
                        _round_beam(key,start-direction*_rng.randf_range(.08,.18),start+direction*.22,.10)
                v0 = v1
                column += 1
        if not thatch:
            _beam("timber",a,b,.15)
        if not hip:
            _beam("thatch2" if thatch else "timber",a,dd,.23 if thatch else .13)
            _beam("thatch2" if thatch else "timber",b,c,.23 if thatch else .13)
    if hip:
        _hip_ends(origin,w,d,rise,thickness,key_prefix)
    var ridge_start = _roof_point(origin,w,d,rise,hip,1,1,-1)+Vector3(0,thickness*.75,0)
    var ridge_end = _roof_point(origin,w,d,rise,hip,1,1,1)+Vector3(0,thickness*.75,0)
    if thatch:
        _round_beam("thatch3",ridge_start,ridge_end,.22)
    else:
        _beam("slate3",ridge_start,ridge_end,.18)
    if _body != null:
        var half_w: float = w*.5+.38
        var half_d: float = d*.5+.38
        var run: float = minf(half_w*.85,half_d*.65) if hip else 0.0
        var shape = ConvexPolygonShape3D.new()
        shape.points = PackedVector3Array([
            origin+Vector3(-half_w,-.14,-half_d),origin+Vector3(half_w,-.14,-half_d),
            origin+Vector3(-half_w,-.14,half_d),origin+Vector3(half_w,-.14,half_d),
            origin+Vector3(0,rise+thickness,-half_d+run),origin+Vector3(0,rise+thickness,half_d-run)])
        var collider = CollisionShape3D.new()
        collider.name = "RoofCollision"
        collider.shape = shape
        _body.add_child(collider)

func _hip_ends(origin: Vector3, w: float, d: float, rise: float, thickness: float, prefix: String):
    var half_w: float = w*.5+.38
    var half_d: float = d*.5+.38
    var run: float = minf(half_w*.85,half_d*.65)
    var rows: int = 5 if prefix == "thatch" else ceili(Vector2(run,rise).length() / SLATE_ROW_SPACING) # Match hip-end slate courses to the main roof.
    for end in [-1.0,1.0]:
        var normal = Vector3(0,run,end*rise).normalized()
        _triangle(prefix+"0",origin+Vector3(-half_w,0,end*half_d),origin+Vector3(half_w,0,end*half_d),origin+Vector3(0,rise,end*(half_d-run)),normal)
        for row in range(rows):
            var t0: float = float(row)/rows
            var t1: float = float(row+1)/rows
            var count: int = maxi(1,ceili(w*(1.0-t0) / (THATCH_HIP_COLUMN_SPACING if prefix == "thatch" else SLATE_COLUMN_SPACING))) # Simplify hip-end pieces consistently with the main roof.
            for i in range(count):
                var x0: float = -1.0+2.0*i/count
                var x1: float = -1.0+2.0*(i+1)/count
                var a = origin+Vector3(half_w*(1-t0)*x0,rise*t0,end*(half_d-run*t0))+normal*thickness
                var b = origin+Vector3(half_w*(1-t0)*x1,rise*t0,end*(half_d-run*t0))+normal*thickness
                var c = origin+Vector3(half_w*(1-t1)*x1,rise*t1,end*(half_d-run*t1))+normal*thickness
                var dd = origin+Vector3(half_w*(1-t1)*x0,rise*t1,end*(half_d-run*t1))+normal*thickness
                var key: String = prefix+str(_rng.randi_range(0,4))
                _quad(key,a,b,c,dd,normal)
                if prefix == "thatch" and row < rows-1:
                    _round_beam(key,(a+b)*.5+normal*.035,(c+dd)*.5+normal*.035,.06)

func _gables(origin: Vector3, w: float, d: float, rise: float):
    for end in [-1.0,1.0]:
        var a = origin+Vector3(-w*.5,0,end*d*.5)
        var b = origin+Vector3(w*.5,0,end*d*.5)
        var c = origin+Vector3(0,rise,end*d*.5)
        var normal = Vector3(0,0,end)
        _triangle("plaster",a,b,c,normal)
        var offset = normal*.07
        _beam("timber",a+offset,b+offset,.16)
        _beam("timber",a+offset,c+offset,.16)
        _beam("timber",b+offset,c+offset,.16)
        _beam("timber",origin+Vector3(0,0,end*d*.5)+offset,c+offset,.13)
        for x in [-w*.25,w*.25]:
            _beam("timber",origin+Vector3(x,0,end*d*.5)+offset,origin+Vector3(x,rise*.5,end*d*.5)+offset,.09)

func _porch(w: float, d: float):
    var depth: float = _rng.randf_range(1.6,2.3)
    var width: float = minf(w-.7,3.4)
    var high: float = FOUNDATION+2.45
    var low: float = FOUNDATION+2.05
    var back_z: float = -d*.5-.05
    var front_z: float = back_z-depth
    var normal = Vector3(0,depth,-(high-low)).normalized()
    _quad("slate2" if _parameters["roof"] == HouseRecipe.RoofStyle.SLATE else "thatch2",Vector3(-width*.5,high,back_z),Vector3(width*.5,high,back_z),Vector3(width*.5,low,front_z),Vector3(-width*.5,low,front_z),normal)
    _beam("timber",Vector3(-width*.5,low,front_z),Vector3(width*.5,low,front_z),.16)
    for x in [-width*.5+.1,width*.5-.1]:
        _beam("timber",Vector3(x,.05,front_z+.1),Vector3(x,low,front_z+.1),.17)
        _collision(Vector3(x,low*.5,front_z+.1),Vector3(.17,low,.17))
        _beam("timber",Vector3(x,low-.48,front_z+.1),Vector3(x-signf(x)*.42,low,front_z+.1),.10)
    _box("stone1",Vector3(0,.025,front_z+depth*.5),Vector3(width+.3,.16,depth+.2))

func _chimney(w: float, d: float, floors: int):
    var top: float = FOUNDATION+floors*_parameters["floor_height"]+_parameters["roof_rise"]+_rng.randf_range(.65,1.3)
    var bottom: float = FOUNDATION+floors*_parameters["floor_height"]-.5
    var centre = Vector3(w*.22,0,d*.22)
    var width: float = _rng.randf_range(.65,.88)
    var depth: float = width*.85
    _box("brick_mortar",centre+Vector3(0,(top+bottom)*.5,0),Vector3(width,top-bottom,depth))
    var courses: int = ceili((top-bottom) / BRICK_COURSE_HEIGHT) # Match chimney masonry to the simpler wall courses.
    for row in range(courses):
        var y: float = bottom+(row+.5)*(top-bottom)/courses
        for side in range(4):
            var basis = Basis(Vector3.UP,side*PI*.5)
            var length: float = width if side%2 == 0 else depth
            var distance: float = depth*.5 if side%2 == 0 else width*.5
            for i in range(2):
                _box("brick%d"%_rng.randi_range(0,4),centre+Vector3(0,y,0)+basis*Vector3((i-.5)*length*.5,0,-distance-.015),Vector3(length*.5-.025,(top-bottom)/courses-.025,.045),basis)
    _box("stone1",centre+Vector3(0,top-.07,0),Vector3(width+.16,.16,depth+.16))
    _box("opening",centre+Vector3(0,top+.02,0),Vector3(width-.14,.035,depth-.14))
    for x in [-1,1]:
        _box("brick2",centre+Vector3(x*(width*.5+.015),top+.17,0),Vector3(.15,.34,depth+.17))
    for z in [-1,1]:
        _box("brick2",centre+Vector3(0,top+.17,z*(depth*.5+.015)),Vector3(width-.13,.34,.15))
    _collision(centre+Vector3(0,(top+bottom)*.5,0),Vector3(width,top-bottom,depth))
    _root.set_meta("chimney_count",1)

func _flush():
    var bounds: AABB
    var has_bounds: bool = false
    for key: String in _streams:
        var mesh = (_streams[key] as SurfaceTool).commit()
        mesh.surface_set_material(0,_materials[key])
        var node = MeshInstance3D.new()
        node.name = key.to_pascal_case()+"Geometry"
        node.mesh = mesh
        _root.add_child(node)
        bounds = bounds.merge(mesh.get_aabb()) if has_bounds else mesh.get_aabb()
        has_bounds = true
    _root.set_meta("bounds",bounds)
    _root.set_meta("footprint",Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)))
    _streams.clear()

func _round_beam(key: String, start: Vector3, end: Vector3, radius: float):
    var direction: Vector3 = (end-start).normalized()
    var basis = Basis(Quaternion(Vector3.UP,direction))
    for i in range(6):
        var a: float = TAU*i/6.0
        var b: float = TAU*(i+1)/6.0
        var offset_a = basis*Vector3(cos(a)*radius,0,sin(a)*radius)
        var offset_b = basis*Vector3(cos(b)*radius,0,sin(b)*radius)
        var normal = (offset_a+offset_b).normalized()
        _quad(key,start+offset_a,start+offset_b,end+offset_b,end+offset_a,normal)
        _triangle(key,start,start+offset_b,start+offset_a,-direction)
        _triangle(key,end,end+offset_a,end+offset_b,direction)

func _wall_face_incremental(origin: Vector3, basis: Basis, length: float, height: float, style: int, level: int, entrance: bool, scheduler: GenerationScheduler):
    var courses: int = ceili(height / (BRICK_COURSE_HEIGHT if style == HouseRecipe.WallStyle.BRICK else STONE_COURSE_HEIGHT)) # Share simpler masonry spacing across build paths.
    if style in [HouseRecipe.WallStyle.STONE,HouseRecipe.WallStyle.BRICK]:
        var brick: bool = style == HouseRecipe.WallStyle.BRICK
        var course_h: float = height/courses
        var block_w: float = BRICK_BLOCK_WIDTH if brick else STONE_BLOCK_WIDTH # Keep fewer, broader masonry blocks.
        for row in range(courses):
            if not await scheduler.checkpoint(): return
            var left: float = -length*.5
            var first: bool = true
            while left < length*.5-.025:
                if not await scheduler.checkpoint(): return
                var width: float = block_w*(.52 if first and row%2==1 else _rng.randf_range(.85,1.15))
                width = minf(width,length*.5-left)
                var key: String = ("brick%d" if brick else "stone%d")%_rng.randi_range(0,4)
                _box(key,origin+basis*Vector3(left+width*.5,(row+.5)*course_h,-.033),Vector3(maxf(.01,width-.035),course_h-.03,.075),basis)
                left += width
                first = false
    elif style == HouseRecipe.WallStyle.WOOD:
        var count: int = ceili(length / PLANK_WIDTH) # Keep fewer, broader siding planks.
        var width: float = length/count
        for i in range(count):
            if not await scheduler.checkpoint(): return
            _box("plank%d"%_rng.randi_range(0,4),origin+basis*Vector3(-length*.5+(i+.5)*width,height*.5,-.028),Vector3(width-.025,height-.04,.065),basis)
        for y in [.16,height-.20]:
            if not await scheduler.checkpoint(): return
            _box("timber",origin+basis*Vector3(0,y,-.09),Vector3(length,.12,.11),basis)
    else:
        var bays: int = maxi(2,roundi(length/2.3))
        var span: float = length/bays
        for i in range(bays+1):
            if not await scheduler.checkpoint(): return
            _box("timber",origin+basis*Vector3(-length*.5+i*span,height*.5,-.065),Vector3(.14,height,.14),basis)
        for y in [.1,height-.08]:
            if not await scheduler.checkpoint(): return
            _box("timber",origin+basis*Vector3(0,y,-.07),Vector3(length,.16,.15),basis)
        for i in range(bays):
            if not await scheduler.checkpoint(): return
            if i%2 == 0:
                var start = origin+basis*Vector3(-length*.5+i*span+.16,.24,-.073)
                var end = origin+basis*Vector3(-length*.5+(i+1)*span-.16,height-.24,-.073)
                _beam("timber",start,end,.10)
    # Ground-floor door and upper windows sit proud of the textured wall plane.
    if entrance:
        _door(origin,basis)
    var count: int = maxi(1,floori(length/2.8))
    for i in range(count):
        if not await scheduler.checkpoint(): return
        var x: float = -length*.5+(i+1.0)*length/(count+1.0)
        if entrance and absf(x) < 1.25:
            continue
        _window(origin+basis*Vector3(x,height*.57,-.115),basis,level > 0 or _rng.randf() < .65)

func _hip_ends_incremental(origin: Vector3, w: float, d: float, rise: float, thickness: float, prefix: String, scheduler: GenerationScheduler):
    var half_w: float = w*.5+.38
    var half_d: float = d*.5+.38
    var run: float = minf(half_w*.85,half_d*.65)
    var rows: int = 5 if prefix == "thatch" else ceili(Vector2(run,rise).length() / SLATE_ROW_SPACING) # Match hip-end slate courses to the main roof.
    for end in [-1.0,1.0]:
        if not await scheduler.checkpoint(): return
        var normal = Vector3(0,run,end*rise).normalized()
        _triangle(prefix+"0",origin+Vector3(-half_w,0,end*half_d),origin+Vector3(half_w,0,end*half_d),origin+Vector3(0,rise,end*(half_d-run)),normal)
        for row in range(rows):
            if not await scheduler.checkpoint(): return
            var t0: float = float(row)/rows
            var t1: float = float(row+1)/rows
            var count: int = maxi(1,ceili(w*(1.0-t0) / (THATCH_HIP_COLUMN_SPACING if prefix == "thatch" else SLATE_COLUMN_SPACING))) # Simplify hip-end pieces consistently with the main roof.
            for i in range(count):
                if not await scheduler.checkpoint(): return
                var x0: float = -1.0+2.0*i/count
                var x1: float = -1.0+2.0*(i+1)/count
                var a = origin+Vector3(half_w*(1-t0)*x0,rise*t0,end*(half_d-run*t0))+normal*thickness
                var b = origin+Vector3(half_w*(1-t0)*x1,rise*t0,end*(half_d-run*t0))+normal*thickness
                var c = origin+Vector3(half_w*(1-t1)*x1,rise*t1,end*(half_d-run*t1))+normal*thickness
                var dd = origin+Vector3(half_w*(1-t1)*x0,rise*t1,end*(half_d-run*t1))+normal*thickness
                var key: String = prefix+str(_rng.randi_range(0,4))
                _quad(key,a,b,c,dd,normal)
                if prefix == "thatch" and row < rows-1:
                    _round_beam(key,(a+b)*.5+normal*.035,(c+dd)*.5+normal*.035,.06)

func _gables_incremental(origin: Vector3, w: float, d: float, rise: float, scheduler: GenerationScheduler):
    for end in [-1.0,1.0]:
        if not await scheduler.checkpoint(): return
        var a = origin+Vector3(-w*.5,0,end*d*.5)
        var b = origin+Vector3(w*.5,0,end*d*.5)
        var c = origin+Vector3(0,rise,end*d*.5)
        var normal = Vector3(0,0,end)
        _triangle("plaster",a,b,c,normal)
        var offset = normal*.07
        _beam("timber",a+offset,b+offset,.16)
        _beam("timber",a+offset,c+offset,.16)
        _beam("timber",b+offset,c+offset,.16)
        _beam("timber",origin+Vector3(0,0,end*d*.5)+offset,c+offset,.13)
        for x in [-w*.25,w*.25]:
            if not await scheduler.checkpoint(): return
            _beam("timber",origin+Vector3(x,0,end*d*.5)+offset,origin+Vector3(x,rise*.5,end*d*.5)+offset,.09)

func _porch_incremental(w: float, d: float, scheduler: GenerationScheduler):
    var depth: float = _rng.randf_range(1.6,2.3)
    var width: float = minf(w-.7,3.4)
    var high: float = FOUNDATION+2.45
    var low: float = FOUNDATION+2.05
    var back_z: float = -d*.5-.05
    var front_z: float = back_z-depth
    var normal = Vector3(0,depth,-(high-low)).normalized()
    _quad("slate2" if _parameters["roof"] == HouseRecipe.RoofStyle.SLATE else "thatch2",Vector3(-width*.5,high,back_z),Vector3(width*.5,high,back_z),Vector3(width*.5,low,front_z),Vector3(-width*.5,low,front_z),normal)
    _beam("timber",Vector3(-width*.5,low,front_z),Vector3(width*.5,low,front_z),.16)
    for x in [-width*.5+.1,width*.5-.1]:
        if not await scheduler.checkpoint(): return
        _beam("timber",Vector3(x,.05,front_z+.1),Vector3(x,low,front_z+.1),.17)
        _collision(Vector3(x,low*.5,front_z+.1),Vector3(.17,low,.17))
        _beam("timber",Vector3(x,low-.48,front_z+.1),Vector3(x-signf(x)*.42,low,front_z+.1),.10)
    _box("stone1",Vector3(0,.025,front_z+depth*.5),Vector3(width+.3,.16,depth+.2))

func _chimney_incremental(w: float, d: float, floors: int, scheduler: GenerationScheduler):
    var top: float = FOUNDATION+floors*_parameters["floor_height"]+_parameters["roof_rise"]+_rng.randf_range(.65,1.3)
    var bottom: float = FOUNDATION+floors*_parameters["floor_height"]-.5
    var centre = Vector3(w*.22,0,d*.22)
    var width: float = _rng.randf_range(.65,.88)
    var depth: float = width*.85
    _box("brick_mortar",centre+Vector3(0,(top+bottom)*.5,0),Vector3(width,top-bottom,depth))
    var courses: int = ceili((top-bottom) / BRICK_COURSE_HEIGHT) # Match chimney masonry to the simpler wall courses.
    for row in range(courses):
        if not await scheduler.checkpoint(): return
        var y: float = bottom+(row+.5)*(top-bottom)/courses
        for side in range(4):
            if not await scheduler.checkpoint(): return
            var basis = Basis(Vector3.UP,side*PI*.5)
            var length: float = width if side%2 == 0 else depth
            var distance: float = depth*.5 if side%2 == 0 else width*.5
            for i in range(2):
                if not await scheduler.checkpoint(): return
                _box("brick%d"%_rng.randi_range(0,4),centre+Vector3(0,y,0)+basis*Vector3((i-.5)*length*.5,0,-distance-.015),Vector3(length*.5-.025,(top-bottom)/courses-.025,.045),basis)
    _box("stone1",centre+Vector3(0,top-.07,0),Vector3(width+.16,.16,depth+.16))
    _box("opening",centre+Vector3(0,top+.02,0),Vector3(width-.14,.035,depth-.14))
    for x in [-1,1]:
        if not await scheduler.checkpoint(): return
        _box("brick2",centre+Vector3(x*(width*.5+.015),top+.17,0),Vector3(.15,.34,depth+.17))
    for z in [-1,1]:
        if not await scheduler.checkpoint(): return
        _box("brick2",centre+Vector3(0,top+.17,z*(depth*.5+.015)),Vector3(width-.13,.34,.15))
    _collision(centre+Vector3(0,(top+bottom)*.5,0),Vector3(width,top-bottom,depth))
    _root.set_meta("chimney_count",1)

func _flush_incremental(scheduler: GenerationScheduler):
    var bounds: AABB
    var has_bounds: bool = false
    for key: String in _streams:
        if not await scheduler.operation_checkpoint(): return # Avoid combining expensive material uploads in one frame.
        var started: int = Time.get_ticks_usec() # Measure the indivisible surface commit separately.
        var mesh = (_streams[key] as SurfaceTool).commit()
        scheduler.record_operation(started) # Expose oversized commits in generation diagnostics.
        mesh.surface_set_material(0,_materials[key])
        var node = MeshInstance3D.new()
        node.name = key.to_pascal_case()+"Geometry"
        node.mesh = mesh
        _root.add_child(node)
        bounds = bounds.merge(mesh.get_aabb()) if has_bounds else mesh.get_aabb()
        has_bounds = true
    _root.set_meta("bounds",bounds)
    _root.set_meta("footprint",Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)))
    _streams.clear()

func _roof_incremental(origin: Vector3, w: float, d: float, rise: float, hip: bool, scheduler: GenerationScheduler):
    var thatch: bool = _parameters["roof"] == HouseRecipe.RoofStyle.THATCH
    var key_prefix: String = "thatch" if thatch else "slate"
    var thickness: float = .24 if thatch else .09
    for side in [-1.0,1.0]:
        if not await scheduler.checkpoint(): return
        var a = _roof_point(origin,w,d,rise,hip,side,0,-1)
        var b = _roof_point(origin,w,d,rise,hip,side,0,1)
        var c = _roof_point(origin,w,d,rise,hip,side,1,1)
        var dd = _roof_point(origin,w,d,rise,hip,side,1,-1)
        var normal = Vector3(side*rise,w*.5+.38,0).normalized()
        _quad(key_prefix+"0",a,b,c,dd,normal)
        _quad("timber",a-Vector3(0,thickness,0),dd-Vector3(0,thickness,0),c-Vector3(0,thickness,0),b-Vector3(0,thickness,0),Vector3.DOWN)
        var rows: int = 4 if thatch else ceili(Vector2(w*.5+.38,rise).length() / SLATE_ROW_SPACING) # Simplify slate density while retaining thatch layering.
        var columns: int = ceili((d+.76) / (THATCH_COLUMN_SPACING if thatch else SLATE_COLUMN_SPACING)) # Use fewer roof pieces without changing the roof profile.
        for row in range(rows):
            if not await scheduler.checkpoint(): return
            var t0: float = float(row)/rows
            var t1: float = minf(1.0,float(row+1)/rows+.015)
            var v0: float = -1.0
            var nominal: float = 2.0/columns
            var column: int = 0
            while v0 < .999:
                if not await scheduler.checkpoint(): return
                var stride: float = nominal*(.5 if column==0 and row%2==1 else 1.0)
                var v1: float = minf(1.0,v0+stride)
                var gap: float = .005 if thatch else .004
                var offset = normal*(thickness+_rng.randf_range(0,.018))
                var p0 = _roof_point(origin,w,d,rise,hip,side,t0,v0+gap)+offset
                var p1 = _roof_point(origin,w,d,rise,hip,side,t0,v1-gap)+offset
                var p2 = _roof_point(origin,w,d,rise,hip,side,t1,v1-gap)+offset
                var p3 = _roof_point(origin,w,d,rise,hip,side,t1,v0+gap)+offset
                var key: String = key_prefix+str(_rng.randi_range(0,4))
                _quad(key,p0,p1,p2,p3,normal)
                _quad(key_prefix+"0",p0,p0-normal*.055,p1-normal*.055,p1,Vector3(side,0,0))
                if thatch:
                    # A narrow raised fold gives thatch a bundled silhouette.
                    var centre_v: float = (v0+v1)*.5
                    var start = _roof_point(origin,w,d,rise,hip,side,t0,centre_v)+normal*(thickness+.022)
                    var end = _roof_point(origin,w,d,rise,hip,side,t1,centre_v)+normal*(thickness+.022)
                    _round_beam(key,start,end,.065)
                    if row == 0:
                        var direction: Vector3 = (end-start).normalized()
                        _round_beam(key,start-direction*_rng.randf_range(.08,.18),start+direction*.22,.10)
                v0 = v1
                column += 1
        if not thatch:
            _beam("timber",a,b,.15)
        if not hip:
            _beam("thatch2" if thatch else "timber",a,dd,.23 if thatch else .13)
            _beam("thatch2" if thatch else "timber",b,c,.23 if thatch else .13)
    if hip:
        await _hip_ends_incremental(origin,w,d,rise,thickness,key_prefix, scheduler)
    var ridge_start = _roof_point(origin,w,d,rise,hip,1,1,-1)+Vector3(0,thickness*.75,0)
    var ridge_end = _roof_point(origin,w,d,rise,hip,1,1,1)+Vector3(0,thickness*.75,0)
    if thatch:
        _round_beam("thatch3",ridge_start,ridge_end,.22)
    else:
        _beam("slate3",ridge_start,ridge_end,.18)
    if _body != null:
        var half_w: float = w*.5+.38
        var half_d: float = d*.5+.38
        var run: float = minf(half_w*.85,half_d*.65) if hip else 0.0
        var shape = ConvexPolygonShape3D.new()
        shape.points = PackedVector3Array([
            origin+Vector3(-half_w,-.14,-half_d),origin+Vector3(half_w,-.14,-half_d),
            origin+Vector3(-half_w,-.14,half_d),origin+Vector3(half_w,-.14,half_d),
            origin+Vector3(0,rise+thickness,-half_d+run),origin+Vector3(0,rise+thickness,half_d-run)])
        var collider = CollisionShape3D.new()
        collider.name = "RoofCollision"
        collider.shape = shape
        _body.add_child(collider)

func _module_incremental(origin: Vector3, w: float, d: float, floors: int, wall: int, hip: bool, main: bool, scheduler: GenerationScheduler):
    var fh: float = _parameters["floor_height"]
    var height: float = FOUNDATION+floors*fh
    var extension: float = _parameters["foundation_extension"]
    _box("mortar",origin+Vector3(0,.18-extension*.5,0),Vector3(w+.24,.62+extension,d+.24))
    _collision(origin+Vector3(0,.18-extension*.5,0),Vector3(w+.24,.62+extension,d+.24))
    for level in range(floors):
        if not await scheduler.checkpoint(): return
        var jetty: bool = main and _parameters["layout"] == HouseRecipe.Layout.JETTIED and level > 0
        var extra: float = .7 if jetty else 0.0
        var lw: float = w+extra
        var ld: float = d+extra*.7
        var bottom: float = FOUNDATION+level*fh
        var style: int = HouseRecipe.WallStyle.TIMBER_FRAME if jetty else wall
        var base: String = "plaster" if style == HouseRecipe.WallStyle.TIMBER_FRAME else "brick_mortar" if style == HouseRecipe.WallStyle.BRICK else "wood" if style == HouseRecipe.WallStyle.WOOD else "mortar"
        _box(base,origin+Vector3(0,bottom+fh*.5,0),Vector3(lw,fh,ld))
        for side in range(4):
            if not await scheduler.checkpoint(): return
            var length: float = lw if side%2 == 0 else ld
            var face_origin: Vector3 = origin+Vector3(0,bottom,0)
            var yaw: float = side*PI*.5
            var basis = Basis(Vector3.UP,yaw)
            var distance: float = ld*.5 if side%2 == 0 else lw*.5
            face_origin += basis*Vector3(0,0,-distance)
            await _wall_face_incremental(face_origin,basis,length,fh,style,level, main and side==0 and level==0, scheduler)
        _box("timber",origin+Vector3(0,bottom+.04,0),Vector3(lw+.12,.12,ld+.12))
        if jetty and level == 1:
            for side in [-1,1]:
                if not await scheduler.checkpoint(): return
                for z in [-d*.35,0,d*.35]:
                    if not await scheduler.checkpoint(): return
                    _beam("timber",origin+Vector3(side*(w*.5-.04),bottom-.62,z),origin+Vector3(side*(lw*.5),bottom-.10,z),.15)
        _collision(origin+Vector3(0,bottom+fh*.5,0),Vector3(lw,fh,ld))
    var roof_w: float = w + (.7 if main and _parameters["layout"] == HouseRecipe.Layout.JETTIED else 0.0)
    var roof_d: float = d + (.49 if main and _parameters["layout"] == HouseRecipe.Layout.JETTIED else 0.0)
    var rise: float = roof_w*.48 if not main else _parameters["roof_rise"]
    await _roof_incremental(origin+Vector3(0,height,0),roof_w,roof_d,rise,hip,scheduler)
    if not hip:
        _gables(origin+Vector3(0,height,0),roof_w,roof_d,rise)

func build_incremental(recipe: HouseRecipe, collisions: bool, scheduler: GenerationScheduler) -> Node3D:
    _body = null
    _streams.clear()
    _materials.clear()
    _root = Node3D.new()
    _root.name = "GeneratedHouse"
    _parameters = recipe.resolve()
    _root.set_meta("house_parameters", _parameters.duplicate())
    _rng = RandomNumberGenerator.new()
    _rng.seed = recipe.seed_value ^ 938251
    _palette(_parameters["palette"])
    if collisions:
        _body = StaticBody3D.new()
        _body.name = "SolidHouseCollision"
        _root.add_child(_body)
    var w: float = _parameters["width"]
    var d: float = _parameters["depth"]
    var floors: int = _parameters["floors"]
    await _module_incremental(Vector3.ZERO, w, d, floors, _parameters["wall"], _parameters["hipped"], true, scheduler)
    if _parameters["layout"] in [HouseRecipe.Layout.L_SHAPED, HouseRecipe.Layout.CROSS]:
        var wing_width: float = _rng.randf_range(3.5, 5.2)
        var wing_depth: float = d * _rng.randf_range(.42, .62)
        var wing_z: float = d*.5-wing_depth*.5 if _parameters["layout"] == HouseRecipe.Layout.L_SHAPED else 0.0
        # Lower annexes meet the main walls, giving distinct L/cross footprints.
        var wing_floors: int = maxi(1, floors-1)
        await _module_incremental(Vector3(w*.5+wing_width*.5-.20, 0, wing_z), wing_width, wing_depth, wing_floors, _parameters["wall"], false, false, scheduler)
        if _parameters["layout"] == HouseRecipe.Layout.CROSS:
            await _module_incremental(Vector3(-w*.5-wing_width*.5+.20, 0, -.35), wing_width, wing_depth*.88, wing_floors, _parameters["wall"], false, false, scheduler)
    if _parameters["porch"]:
        await _porch_incremental(w, d, scheduler)
    if _parameters["chimney"]:
        await _chimney_incremental(w, d, floors, scheduler)
    if not await scheduler.checkpoint():
        _root.free()
        return null
    await _flush_incremental(scheduler)
    if not await scheduler.checkpoint():
        _root.free()
        return null
    return _root
