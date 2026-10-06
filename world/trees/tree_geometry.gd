extends RefCounted
class_name TreeGeometry

## Eight families, two seeded forms per family, with the same skeleton at every LOD.
enum Species { OAK, BIRCH, BEECH, PINE, SPRUCE, WILLOW, WIND_BENT, SNAG }
const SPECIES_COUNT: int = 8
const FORMS_PER_SPECIES: int = 2
const VARIANT_COUNT: int = SPECIES_COUNT*FORMS_PER_SPECIES
const NAMES = ["Oak","Birch","Beech","Scots pine","Spruce","Willow","Wind-bent oak","Dead snag"]
var _wood: StandardMaterial3D
var _leaves: StandardMaterial3D

func _init():
    _wood = _material()
    _leaves = _material()

static func species_of(variant: int) -> int:
    return floori(float(posmod(variant,VARIANT_COUNT))/FORMS_PER_SPECIES)

static func trunk_dimensions(variant: int) -> Vector2:
    match species_of(variant):
        Species.OAK: return Vector2(.62,3.6)
        Species.BIRCH: return Vector2(.31,6.0)
        Species.BEECH: return Vector2(.48,4.5)
        Species.PINE: return Vector2(.40,7.2)
        Species.SPRUCE: return Vector2(.48,5.0)
        Species.WILLOW: return Vector2(.60,3.3)
        Species.WIND_BENT: return Vector2(.60,3.0)
        _: return Vector2(.45,4.8)

func build(variant: int, lod: int) -> ArrayMesh:
    variant = posmod(variant,VARIANT_COUNT)
    var species: int = species_of(variant)
    var form: int = variant%FORMS_PER_SPECIES
    var rng = RandomNumberGenerator.new()
    rng.seed = 31871+variant*9277
    var wood = SurfaceTool.new()
    wood.begin(Mesh.PRIMITIVE_TRIANGLES)
    var leaves = SurfaceTool.new()
    leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
    var segments: int = 6 if lod==0 else 5 if lod==1 else 4
    var bark: Color = Color("594334")
    var foliage: Color = Color("416643")
    match species:
        Species.BIRCH: bark = Color("cdc9b2"); foliage = Color("668048")
        Species.BEECH: bark = Color("797568"); foliage = Color("726849") if form==1 else Color("4f7046")
        Species.PINE: bark = Color("83513b"); foliage = Color("3e6150")
        Species.SPRUCE: bark = Color("564639"); foliage = Color("36564c")
        Species.WILLOW: bark = Color("686046"); foliage = Color("7a8957")
        Species.WIND_BENT: bark = Color("615043"); foliage = Color("536747")
        Species.SNAG: bark = Color("8c8473")
    if species in [Species.PINE,Species.SPRUCE]:
        _conifer(wood,leaves,rng,species,form,lod,segments,bark,foliage)
    elif species == Species.SNAG:
        _snag(wood,rng,form,lod,segments,bark)
    else:
        _broadleaf(wood,leaves,rng,species,form,lod,segments,bark,foliage)
    var mesh = ArrayMesh.new()
    mesh.resource_name = "%s_Form%d_LOD%d"%[NAMES[species],form,lod]
    wood.commit(mesh)
    mesh.surface_set_material(0,_wood)
    if species != Species.SNAG:
        leaves.commit(mesh)
        mesh.surface_set_material(1,_leaves)
    return mesh

func _material() -> StandardMaterial3D:
    var material = StandardMaterial3D.new()
    material.vertex_color_use_as_albedo = true
    material.albedo_color = Color.WHITE
    material.roughness = 1.0
    material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
    return material

func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, colour: Color, outward: Vector3):
    var cross = (b-a).cross(c-a)
    if cross.length_squared() < .0000001: return
    if cross.dot(outward) > 0:
        var swap = b
        b = c
        c = swap
        cross = -cross
    var normal = -cross.normalized()
    st.set_color(colour)
    for v in [a,b,c]:
        st.set_normal(normal)
        st.add_vertex(v)

func _limb(st: SurfaceTool, path: Array, radii: Array, colour: Color, sides: int):
    var rings: Array = []
    for i in range(path.size()):
        var tangent: Vector3 = path[mini(i+1,path.size()-1)]-path[maxi(i-1,0)]
        var basis = Basis(Quaternion(Vector3.UP,tangent.normalized()))
        var ring: Array[Vector3] = []
        for j in range(sides):
            var angle: float = TAU*j/sides+.19
            ring.append(path[i]+basis*Vector3(cos(angle)*radii[i],0,sin(angle)*radii[i]))
        rings.append(ring)
    for i in range(path.size()-1):
        for j in range(sides):
            var k: int = (j+1)%sides
            var outward: Vector3 = (rings[i][j]+rings[i][k])*.5-path[i]
            var shade = colour.lightened((float(j%3)-1)*.035)
            _triangle(st,rings[i][j],rings[i+1][j],rings[i+1][k],shade,outward)
            _triangle(st,rings[i][j],rings[i+1][k],rings[i][k],shade,outward)
    for i in [0,path.size()-1]:
        var normal: Vector3 = (path[0]-path[1]).normalized() if i==0 else (path[-1]-path[-2]).normalized()
        for j in range(sides):
            _triangle(st,path[i],rings[i][j],rings[i][(j+1)%sides],colour.lightened(.09),normal)

func _roots(wood: SurfaceTool, radius: float, colour: Color, rng: RandomNumberGenerator, lod: int):
    for i in range(4):
        var angle: float = i*TAU/4+rng.randf_range(-.2,.2)
        if lod==2 or (lod==1 and i==3): continue
        var end = Vector3(cos(angle),0,sin(angle))*radius*2.7
        end.y = -.10
        _limb(wood,[Vector3(0,.55,0),end],[radius*.55,.035],colour,4)

func _crown(st: SurfaceTool, centre: Vector3, size: Vector3, colour: Color, seed_value: int, lod: int):
    # An irregular faceted hull, not a smooth sphere. Vertex positions stay seeded across LODs.
    var sides: int = 7 if lod==0 else 6 if lod==1 else 4
    var rng = RandomNumberGenerator.new()
    rng.seed = seed_value
    var lower: Array[Vector3] = []
    var shoulder: Array[Vector3] = []
    for i in range(sides):
        var angle: float = TAU*i/sides
        var radius: float = rng.randf_range(.85,1.12)
        lower.append(centre+Vector3(cos(angle)*size.x*.65*radius,-size.y*.32,sin(angle)*size.z*.65*radius))
        shoulder.append(centre+Vector3(cos(angle)*size.x*radius,size.y*rng.randf_range(.15,.35),sin(angle)*size.z*radius))
    var bottom = centre+Vector3(.08,-size.y*.75,.05)
    var top = centre+Vector3(size.x*.09,size.y*.94,.03)
    var cap: Array[Vector3] = []
    if lod < 2:
        for i in range(sides):
            var angle: float = TAU*i/sides
            cap.append(centre+Vector3(cos(angle)*size.x*.43,size.y*rng.randf_range(.68,.80),sin(angle)*size.z*.43))
    for i in range(sides):
        var j: int = (i+1)%sides
        var tone = colour.lightened(rng.randf_range(-.025,.035))
        _triangle(st,bottom,lower[i],lower[j],tone.darkened(.10),bottom-centre)
        _triangle(st,lower[i],shoulder[i],shoulder[j],tone,lower[i]-centre)
        _triangle(st,lower[i],shoulder[j],lower[j],tone,lower[i]-centre)
        if lod < 2:
            _triangle(st,shoulder[i],cap[i],cap[j],tone,shoulder[i]-centre)
            _triangle(st,shoulder[i],cap[j],shoulder[j],tone,shoulder[i]-centre)
            _triangle(st,cap[i],top,cap[j],tone.lightened(.015),Vector3.UP)
        else:
            _triangle(st,shoulder[i],top,shoulder[j],tone.lightened(.015),top-centre)

func _broadleaf(wood: SurfaceTool, leaves: SurfaceTool, rng: RandomNumberGenerator, species: int, form: int, lod: int, sides: int, bark: Color, foliage: Color):
    var dimensions = trunk_dimensions(species*2+form)
    var base_radius: float = dimensions.x
    var fork: float = dimensions.y
    var lean = Vector3(.16+form*.12,0,-.1)
    if species==Species.WIND_BENT: lean = Vector3(1.8+form*.3,0,.3)
    var trunk_top = lean+Vector3(0,fork+.9,0)
    _limb(wood,trunk_path(species*2+form),[base_radius,base_radius*.72,base_radius*.45],bark,sides)
    _roots(wood,base_radius,bark,rng,lod)
    var branch_count: int = 5 if species in [Species.OAK,Species.WILLOW,Species.WIND_BENT] else 4
    var crown_radius: float = 2.0 if species==Species.BIRCH else 2.5
    var spread: float = 2.2 if species==Species.BIRCH else 3.7 if species==Species.WILLOW else 3.0
    for i in range(branch_count):
        var angle: float = i*TAU/branch_count+.38+form*.43+rng.randf_range(-.22,.22)
        var start = trunk_top+Vector3(0,-.6+(i%3)*.35,0)
        var direction = Vector3(cos(angle),0,sin(angle))
        var end = trunk_top+direction*spread*rng.randf_range(.85,1.15)+Vector3(0,rng.randf_range(1.3,3.3),0)
        if species==Species.WIND_BENT: end += Vector3(1.1,-.9,0)
        var elbow = start.lerp(end,.55)+Vector3(0,.35,0)
        var radius: float = base_radius*.48
        if lod < 2 or i%2 == 0:
            _limb(wood,[start,elbow,end],[radius,radius*.58,.045],bark,4 if lod==2 else sides)
        if lod==0:
            var twig_end = end+direction*.75+Vector3(-direction.z*.45,.85,direction.x*.45)
            _limb(wood,[elbow,end,twig_end],[radius*.38,.055,.012],bark,4)
        var crown_size = Vector3(crown_radius,crown_radius*(1.20 if species==Species.BIRCH else .68),crown_radius*.87)
        if species==Species.WILLOW: crown_size = Vector3(2.5,1.55,2.3)
        if lod < 2 or i%2 == 0:
            _crown(leaves,end+Vector3(0,.45,0),crown_size,foliage,i*873+species*917+form*37,lod)
        if species==Species.WILLOW:
            # Long hanging leaf clusters follow the outer branch tips.
            var drop_end = end+direction*.85+Vector3(0,-2.5-rng.randf()*.8,0)
            if lod==0: _limb(wood,[end,drop_end],[.035,.008],bark,3)
            if lod < 2 or i%2 == 0:
                _hanging_foliage(leaves,end+direction*.5,drop_end,.75,foliage.lightened(.025),lod)
    # A smaller upper crown joins the branch-supported lobes without hiding the lower forks.
    _crown(leaves,trunk_top+Vector3(.1,3.3,0),Vector3(crown_radius*.90,crown_radius*.85,crown_radius*.85),foliage,447+species*5+form,lod)
    if species==Species.BIRCH and lod==0:
        for i in range(7):
            var y: float = .65+i*.65
            var r: float = base_radius*(1-y/(fork+1)*.45)+.01
            var angle: float = i*1.9
            _limb(wood,[Vector3(cos(angle)*r,y,sin(angle)*r),Vector3(cos(angle)*r,y+.055,sin(angle)*r)],[.08,.065],Color("57564e"),4)

func _conifer(wood: SurfaceTool, leaves: SurfaceTool, rng: RandomNumberGenerator, species: int, form: int, lod: int, sides: int, bark: Color, foliage: Color):
    var pine: bool = species==Species.PINE
    var height: float = (13.2 if pine else 14.0)+form*1.6
    var radius: float = .40 if pine else .48
    var lean = Vector3(.35+form*.28,0,.18)
    _limb(wood,trunk_path(species*2+form),[radius,radius*.61,.035],bark,sides)
    _roots(wood,radius,bark,rng,lod)
    var tiers: int = 4 if pine else 6
    for tier in range(tiers):
        var y: float = (7.0 if pine else 3.1)+tier*(1.6 if pine else 1.9)
        var spread: float = (3.2 if pine else 3.6)*(1.0-float(tier)/tiers*.78)
        var limbs: int = 3 if pine else 4
        for i in range(limbs):
            var angle: float = i*TAU/limbs+tier*1.19+form*.8
            var start = Vector3(lean.x*y/height,y,lean.z*y/height)
            var end = start+Vector3(cos(angle)*spread,-.28 if pine else -.65,sin(angle)*spread)
            if lod==0 or (lod==1 and i%2==0):
                _limb(wood,[start,start.lerp(end,.6)+Vector3(0,.12,0),end],[.14*(1.0-tier*.10),.075,.018],bark,4)
            if pine:
                _crown(leaves,end+Vector3(0,.45,0),Vector3(spread*.57,.65,spread*.53),foliage,901+tier*57+i*311+form,lod)
        if not pine:
            # Irregular downward skirt with an open gap between successive branch whorls.
            _needle_skirt(leaves,Vector3(lean.x*y/height,y,lean.z*y/height),spread,2.1,foliage,831+tier*51+form,lod)
    if pine:
        _crown(leaves,lean+Vector3(0,height-.35,0),Vector3(1.2,.8,1.1),foliage,322+form,lod)
    else:
        _needle_skirt(leaves,lean+Vector3(0,height-1.1,0),.9,2.0,foliage,325+form,lod)

func _needle_skirt(st: SurfaceTool, centre: Vector3, radius: float, height: float, colour: Color, seed_value: int, lod: int):
    var count: int = 7 if lod==0 else 6 if lod==1 else 5
    var rng = RandomNumberGenerator.new()
    rng.seed = seed_value
    var tip = centre+Vector3(.08,height*.68,0)
    var underside = centre+Vector3(0,-height*.30,0)
    var ring: Array[Vector3] = []
    for i in range(count):
        var angle: float = TAU*i/count
        ring.append(centre+Vector3(cos(angle)*radius*rng.randf_range(.88,1.07),-height*.38,sin(angle)*radius*rng.randf_range(.9,1.06)))
    for i in range(count):
        var angle: float = TAU*(i+.5)/count
        var va: Vector3 = ring[i]
        var vb: Vector3 = ring[(i+1)%count]
        _triangle(st,tip,va,vb,colour.lightened(rng.randf_range(-.025,.025)),Vector3(cos(angle),.5,sin(angle)))
        _triangle(st,underside,vb,va,colour.darkened(.13),Vector3.DOWN)

func _snag(wood: SurfaceTool, rng: RandomNumberGenerator, form: int, lod: int, sides: int, bark: Color):
    var top = Vector3(.55+form*.45,7.9+form*.8,-.25)
    _limb(wood,trunk_path(Species.SNAG*2+form),[.45,.31,.12],bark,sides)
    _roots(wood,.45,bark,rng,lod)
    for i in range(4 if lod<2 else 3):
        var start = Vector3(.2,3.0+i*.95,0)
        var angle: float = i*2.1+form
        var end = start+Vector3(cos(angle)*(1.5+i*.2),1.0+i*.3,sin(angle)*(1.5+i*.2))
        _limb(wood,[start,start.lerp(end,.6),end],[.19,.10,.028],bark,4)
        if lod==0:
            _limb(wood,[start.lerp(end,.65),end+Vector3(-.3,.8,.4)],[.07,.008],bark,3)
    if lod==0:
        _limb(wood,[top,top+Vector3(.08,.65,-.08)],[.11,.005],bark.lightened(.10),3)

func _hanging_foliage(st: SurfaceTool, start: Vector3, end: Vector3, width: float, colour: Color, lod: int):
    var middle = start.lerp(end,.5)+Vector3(.12,0,.1)
    var path = [start,middle,end]
    var radii = [width*.65,width,.07]
    # Long tapered, curved curtain clusters replace dangling spherical leaf blobs.
    _limb(st,path,radii,colour,5 if lod==0 else 4)

static func trunk_path(variant: int) -> Array[Vector3]:
    var species: int = species_of(variant)
    var form: int = posmod(variant,FORMS_PER_SPECIES)
    if species in [Species.PINE,Species.SPRUCE]:
        var height: float = (13.2 if species==Species.PINE else 14.0)+form*1.6
        return [Vector3(0,-.18,0),Vector3(0,height*.45,0),Vector3(.35+form*.28,height,.18)]
    if species==Species.SNAG:
        return [Vector3(0,-.18,0),Vector3(.15,3.5,0),Vector3(.55+form*.45,7.9+form*.8,-.25)]
    var fork: float = trunk_dimensions(variant).y
    var lean = Vector3(.16+form*.12,0,-.1)
    if species==Species.WIND_BENT: lean = Vector3(1.8+form*.3,0,.3)
    return [Vector3(0,-.18,0),Vector3(lean.x*.25,fork*.55,lean.z*.25),lean+Vector3(0,fork+.9,0)]
