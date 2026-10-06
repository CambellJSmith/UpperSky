extends SceneTree
# Rebuild the authored scenes with:
# godot --headless --path . --script res://items/equipment/authoring/build_weapon_collection.gd
# Optionally add -- --export-dir=/absolute/directory to export GLB copies.
var steel = material(Color("8395a4"), 0.65)
var edge = material(Color("c6d3d9"), 0.65)
var dark = material(Color("374654"), 0.6)
var leather = material(Color("483329"), 0.0)
var wrap = material(Color("73513a"), 0.0)
var wood = material(Color("95643f"), 0.0)
func material(color: Color, metal: float) -> StandardMaterial3D:
    var m = StandardMaterial3D.new()
    m.albedo_color = color
    m.metallic = metal
    m.roughness = 0.72
    return m
func part(root: Node3D, label: String, mesh: Mesh, mat: Material, pos = Vector3.ZERO) -> MeshInstance3D:
    var n = MeshInstance3D.new()
    n.name = label
    n.mesh = mesh
    n.material_override = mat
    n.position = pos
    root.add_child(n)
    n.owner = root
    n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return n
func cylinder(root: Node3D, label: String, radius: float, height: float, pos: Vector3, mat: Material):
    var mesh = CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 8
    mesh.rings = 1
    return part(root, label, mesh, mat, pos)
func faceted(root: Node3D, label: String, rings: Array, mat: Material):
    var st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    st.set_smooth_group(-1)
    for i in range(rings.size() - 1):
        for j in range(4):
            var k = (j + 1) % 4
            for v in [rings[i][j], rings[i+1][j], rings[i+1][k], rings[i][j], rings[i+1][k], rings[i][k]]:
                st.add_vertex(v)
    for i in [0, rings.size()-1]:
        var r = rings[i]
        var verts = [r[0],r[2],r[1],r[0],r[3],r[2]] if i == 0 else [r[0],r[1],r[2],r[0],r[2],r[3]]
        for v in verts: st.add_vertex(v)
    st.generate_normals()
    return part(root,label,st.commit(),mat)
func blade_ring(y: float, width: float, depth: float) -> Array:
    return [Vector3(-width,y,0),Vector3(0,y,-depth),Vector3(width,y,0),Vector3(0,y,depth)]
func head_ring(x: float, y: float, width: float, depth: float) -> Array:
    return [Vector3(x,y-width,0),Vector3(x,y,-depth),Vector3(x,y+width,0),Vector3(x,y,depth)]
func save_model(root: Node3D, file: String):
    var packed = PackedScene.new()
    packed.pack(root)
    assert(ResourceSaver.save(packed,"res://items/equipment/models/"+file+".tscn") == OK)
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--export-dir="):
            var export_dir = argument.trim_prefix("--export-dir=")
            DirAccess.make_dir_recursive_absolute(export_dir)
            var state = GLTFState.new()
            var doc = GLTFDocument.new()
            assert(doc.append_from_scene(root,state) == OK)
            assert(doc.write_to_filesystem(state,export_dir.path_join(file+".glb")) == OK)
    root.free()

var bronze = material(Color("b99250"), .55)
var bone = material(Color("d4c8a2"), .0)
var red = material(Color("793e38"), .0)
var blue = material(Color("345667"), .0)
var obsidian = material(Color("293247"), .25)

func box(root: Node3D, label: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
    var mesh = BoxMesh.new()
    mesh.size = size
    return part(root,label,mesh,mat,pos)

func face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3):
    # Godot front faces use clockwise winding.
    if (b-a).cross(c-a).dot(normal) > 0:
        var swap = b
        b = c
        c = swap
    for v in [a,b,c]:
        st.set_normal(normal)
        st.add_vertex(v)

func silhouette(root: Node3D, label: String, points: PackedVector2Array, mat: Material, thickness: float = .025):
    var centre = Vector2.ZERO
    for point in points: centre += point
    centre /= points.size()
    var inset = PackedVector2Array()
    for point in points: inset.append(centre+(point-centre)*.82)
    var indices = Geometry2D.triangulate_polygon(inset)
    assert(not indices.is_empty(), "Invalid blade silhouette: "+label)
    var st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for sign_z in [-1.0,1.0]:
        var normal = Vector3(0,0,sign_z)
        for i in range(0,indices.size(),3):
            var a = inset[indices[i]]
            var b = inset[indices[i+1]]
            var c = inset[indices[i+2]]
            face(st,Vector3(a.x,a.y,sign_z*thickness),Vector3(b.x,b.y,sign_z*thickness),Vector3(c.x,c.y,sign_z*thickness),normal)
        for i in range(points.size()):
            var j = (i+1)%points.size()
            var a = Vector3(points[i].x,points[i].y,0)
            var b = Vector3(points[j].x,points[j].y,0)
            var c = Vector3(inset[j].x,inset[j].y,sign_z*thickness)
            var d = Vector3(inset[i].x,inset[i].y,sign_z*thickness)
            var outward = Vector3((a.x+b.x)*.5-centre.x,(a.y+b.y)*.5-centre.y,sign_z)
            var n = (b-a).cross(c-a).normalized()
            if n.dot(outward) < 0: n = -n
            face(st,a,b,c,n)
            face(st,a,c,d,n)
    return part(root,label,st.commit(),mat)

func grip(root: Node3D, length: float, mat: Material, metal: Material):
    cylinder(root,"Grip",.032,length,Vector3(0,-length*.5,0),mat)
    for i in range(6):
        cylinder(root,"WrapBand",.034,.012,Vector3(0,-length+.025+i*(length-.05)/5,0),wrap if mat == leather else mat)
    cylinder(root,"GripFerrule",.042,.035,Vector3(0,.005,0),metal)
    var mesh = SphereMesh.new()
    mesh.radius = .048
    mesh.height = .075
    mesh.radial_segments = 8
    mesh.rings = 2
    part(root,"Pommel",mesh,metal,Vector3(0,-length-.024,0))

func weapon(id: String) -> Node3D:
    var root = Node3D.new()
    root.name = id.to_pascal_case()+"Model"
    return root

func sword(id: String, points: Array, grip_mat: Material, guard_mat: Material, guard_width: float):
    var root = weapon(id)
    grip(root,.24,grip_mat,guard_mat)
    box(root,"Crossguard",Vector3(guard_width,.035,.06),Vector3(0,.06,0),guard_mat)
    silhouette(root,"BevelledBlade",PackedVector2Array(points),steel)
    return root

func axe(id: String, points: Array, handle_length: float, head_mat: Material):
    var root = weapon(id)
    cylinder(root,"AshShaft",.034,handle_length,Vector3(0,handle_length*.5-.22,0),wood)
    cylinder(root,"Socket",.059,.15,Vector3(0,handle_length-.30,0),dark)
    for i in range(7): cylinder(root,"LeatherBinding",.039,.018,Vector3(0,-.18+i*.036,0),leather)
    cylinder(root,"ButtCap",.045,.045,Vector3(0,-.235,0),dark)
    silhouette(root,"BevelledAxeHead",PackedVector2Array(points),head_mat,.045)
    return root

func knife(id: String, points: Array, grip_mat: Material, bolster_mat: Material, guard_width: float):
    var root = weapon(id)
    grip(root,.17,grip_mat,bolster_mat)
    box(root,"Bolster",Vector3(guard_width,.026,.055),Vector3(0,.035,0),bolster_mat)
    silhouette(root,"BevelledKnifeBlade",PackedVector2Array(points),steel,.018)
    return root

func _initialize():
    var root = sword("bronze_longsword",[Vector2(-.065,.08),Vector2(-.065,.83),Vector2(0,1.05),Vector2(.065,.83),Vector2(.065,.08)],red,bronze,.32)
    cylinder(root,"GoldBladeCollar",.054,.055,Vector3(0,.1,0),bronze)
    save_model(root,"bronze_longsword")
    root = sword("duelist_rapier",[Vector2(-.023,.08),Vector2(-.018,.99),Vector2(0,1.15),Vector2(.018,.99),Vector2(.023,.08)],blue,bronze,.23)
    var ring = TorusMesh.new()
    ring.inner_radius = .10
    ring.outer_radius = .115
    ring.rings = 12
    ring.ring_segments = 6
    var basket = part(root,"SweptHandGuard",ring,bronze,Vector3(.05,-.04,0))
    basket.rotation.x = PI*.5
    save_model(root,"duelist_rapier")
    root = sword("desert_sabre",[Vector2(-.045,.08),Vector2(-.03,.48),Vector2(.035,.86),Vector2(.20,1.04),Vector2(.13,.77),Vector2(.065,.45),Vector2(.055,.08)],leather,bronze,.24)
    var knuckle = box(root,"KnuckleBow",Vector3(.024,.28,.04),Vector3(.12,-.08,0),bronze)
    knuckle.rotation.z = -.2
    save_model(root,"desert_sabre")
    root = sword("cleaver_falchion",[Vector2(-.075,.08),Vector2(-.075,.82),Vector2(.12,.97),Vector2(.15,.73),Vector2(.11,.35),Vector2(.065,.08)],leather,dark,.27)
    save_model(root,"cleaver_falchion")
    root = sword("highland_greatsword",[Vector2(-.083,.08),Vector2(-.083,.25),Vector2(-.13,.30),Vector2(-.07,.35),Vector2(-.065,1.15),Vector2(0,1.38),Vector2(.065,1.15),Vector2(.07,.35),Vector2(.13,.30),Vector2(.083,.25),Vector2(.083,.08)],red,dark,.40)
    root.scale = Vector3.ONE*.86
    save_model(root,"highland_greatsword")
    root = axe("woodsman_axe",[Vector2(-.05,.69),Vector2(.15,.76),Vector2(.29,.86),Vector2(.34,.63),Vector2(.30,.42),Vector2(.15,.51),Vector2(-.05,.54)],.95,steel)
    save_model(root,"woodsman_axe")
    root = axe("double_battleaxe",[Vector2(-.05,.83),Vector2(-.28,.94),Vector2(-.40,.87),Vector2(-.43,.59),Vector2(-.30,.40),Vector2(-.16,.56),Vector2(0,.59),Vector2(.16,.56),Vector2(.30,.40),Vector2(.43,.59),Vector2(.40,.87),Vector2(.28,.94),Vector2(.05,.83)],1.13,steel)
    save_model(root,"double_battleaxe")
    root = axe("crescent_axe",[Vector2(-.04,.76),Vector2(.20,.86),Vector2(.39,1.02),Vector2(.44,.85),Vector2(.42,.56),Vector2(.29,.37),Vector2(.22,.59),Vector2(.12,.65),Vector2(-.04,.62)],1.07,steel)
    cylinder(root,"BronzeSocketBand",.065,.025,Vector3(0,.77,0),bronze)
    save_model(root,"crescent_axe")
    root = axe("bearded_raider_axe",[Vector2(-.05,.76),Vector2(.18,.82),Vector2(.35,.86),Vector2(.39,.65),Vector2(.30,.32),Vector2(.16,.30),Vector2(.21,.61),Vector2(-.05,.62)],1.0,steel)
    save_model(root,"bearded_raider_axe")
    root = axe("obsidian_hatchet",[Vector2(-.04,.58),Vector2(.11,.68),Vector2(.18,.62),Vector2(.24,.76),Vector2(.31,.68),Vector2(.28,.49),Vector2(.33,.44),Vector2(.20,.32),Vector2(.14,.40),Vector2(-.04,.43)],.78,obsidian)
    for i in range(3): cylinder(root,"HeadLashing",.061,.014,Vector3(0,.44+i*.04,0),bone)
    save_model(root,"obsidian_hatchet")
    root = knife("crossguard_dagger",[Vector2(-.055,.05),Vector2(-.055,.30),Vector2(0,.52),Vector2(.055,.30),Vector2(.055,.05)],red,bronze,.20)
    save_model(root,"crossguard_dagger")
    root = knife("curved_kukri",[Vector2(-.036,.05),Vector2(-.03,.20),Vector2(.04,.39),Vector2(.18,.52),Vector2(.19,.37),Vector2(.10,.20),Vector2(.04,.05)],leather,dark,.10)
    save_model(root,"curved_kukri")
    root = knife("black_tanto",[Vector2(-.04,.05),Vector2(-.04,.39),Vector2(.012,.47),Vector2(.045,.39),Vector2(.045,.05)],blue,dark,.12)
    save_model(root,"black_tanto")
    root = knife("bone_seax",[Vector2(-.05,.05),Vector2(-.05,.29),Vector2(.06,.48),Vector2(.06,.05)],bone,bronze,.11)
    save_model(root,"bone_seax")
    root = knife("hunters_knife",[Vector2(-.045,.05),Vector2(-.045,.26),Vector2(-.01,.35),Vector2(.04,.39),Vector2(.065,.28),Vector2(.055,.05)],wood,dark,.14)
    for y in [-.045,-.125]:
        var pin = cylinder(root,"HandleRivet",.009,.073,Vector3(0,y,0),bronze)
        pin.rotation.x = PI*.5
    save_model(root,"hunters_knife")
    quit()
