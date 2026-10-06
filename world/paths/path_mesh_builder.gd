extends RefCounted
class_name PathMeshBuilder

var _network: WorldPathNetwork
var _terrain: InfiniteTerrain
var _material: StandardMaterial3D
func _init(terrain: InfiniteTerrain):
    _terrain = terrain
    _network = WorldPathNetwork.for_terrain(terrain)
    _material = StandardMaterial3D.new()
    _material.vertex_color_use_as_albedo = true
    _material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _material.roughness = .94
    _material.metallic_specular = .12

func build(cell: Vector2i) -> ArrayMesh:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        return _profile_build(cell)
    var _profile_token = RuntimeProfiler.begin("paths.mesh")
    var _profile_result = _profile_build(cell)
    RuntimeProfiler.end(_profile_token)
    return _profile_result

func _profile_build(cell: Vector2i) -> ArrayMesh:
    var origin = Vector2(cell)*WorldPathNetwork.CHUNK_SIZE
    var bounds = Rect2(origin,Vector2.ONE*WorldPathNetwork.CHUNK_SIZE)
    var clip = PackedVector2Array([bounds.position,bounds.position+Vector2(bounds.size.x,0),bounds.end,bounds.position+Vector2(0,bounds.size.y)])
    var stream = SurfaceTool.new()
    stream.begin(Mesh.PRIMITIVE_TRIANGLES)
    var count = 0
    for road in _network.routes_in_chunk(cell):
        for i in range(road.points.size()-1):
            var a: Vector2 = road.points[i]
            var b: Vector2 = road.points[i+1]
            var steps = maxi(1,ceili(a.distance_to(b)/4.0))
            var normal = Vector2(-(b-a).y,(b-a).x).normalized()
            for step in range(steps):
                var start = a.lerp(b,float(step)/steps)
                var end = a.lerp(b,float(step+1)/steps)
                # Split core and shoulders to keep fades visible on narrow paths too.
                var widths = [-road.edge,-road.core,0.0,road.core,road.edge]
                for lane in range(widths.size()-1):
                    var polygon = PackedVector2Array([start+normal*widths[lane],end+normal*widths[lane],end+normal*widths[lane+1],start+normal*widths[lane+1]])
                    for clipped in _ground_polygons(polygon,clip):
                        for j in range(1,clipped.size()-1):
                            var triangle = [clipped[0],clipped[j],clipped[j+1]]
                            var vertices: Array[Vector3] = []
                            var colours: Array[Color] = []
                            var dry = true
                            for point: Vector2 in triangle:
                                if _terrain.has_water_at(point): dry = false; break
                                var height = _network._settlements.ground_height(point)
                                vertices.append(Vector3(point.x-origin.x,height+.035,point.y-origin.y))
                                var mask = TerrainPathSampler.get_wear_mask(point,_terrain)
                                var colour = WorldPathNetwork.EDGE_COLOUR.lerp(WorldPathNetwork.CORE_COLOUR,smoothstep(.48,.92,mask))
                                colour.a = mask
                                colours.append(colour)
                            if not dry: continue
                            var face = -(vertices[1]-vertices[0]).cross(vertices[2]-vertices[0])
                            if face.length_squared() < .00000001: continue
                            if face.y < 0:
                                vertices.reverse()
                                colours.reverse()
                                face = -face
                            for k in range(3):
                                stream.set_normal(face.normalized())
                                stream.set_color(colours[k])
                                stream.add_vertex(vertices[k])
                            count += 1
    if count == 0: return null
    var mesh = stream.commit()
    mesh.surface_set_material(0,_material)
    mesh.resource_name = "SharedPaths_%d_%d"%[cell.x,cell.y]
    return mesh

func _ground_polygons(polygon: PackedVector2Array, chunk: PackedVector2Array) -> Array[PackedVector2Array]:
    # Every road face follows a single authoritative terrain triangle, preventing
    # buried strips or floating patches at changes in the terrain slope.
    var result: Array[PackedVector2Array] = []
    var spacing: float = TerrainConfiguration.CHUNK_SIZE/float(TerrainConfiguration.CHUNK_RESOLUTION-1)
    for clipped in Geometry2D.intersect_polygons(polygon,chunk):
        var bounds = Rect2(clipped[0],Vector2.ZERO)
        for point in clipped: bounds = bounds.expand(point)
        var first = Vector2i(floori(bounds.position.x/spacing),floori(bounds.position.y/spacing))
        var last = Vector2i(floori(bounds.end.x/spacing),floori(bounds.end.y/spacing))
        for z in range(first.y,last.y+1):
            for x in range(first.x,last.x+1):
                var a = Vector2(x,z)*spacing
                var b = a+Vector2(spacing,0)
                var c = a+Vector2(0,spacing)
                var d = a+Vector2.ONE*spacing
                for triangle in [PackedVector2Array([a,b,c]),PackedVector2Array([d,c,b])]:
                    for face in Geometry2D.intersect_polygons(clipped,triangle):
                        if face.size() >= 3: result.append(face)
    return result

func build_incremental(cell: Vector2i, scheduler: GenerationScheduler) -> ArrayMesh:
    var origin = Vector2(cell)*WorldPathNetwork.CHUNK_SIZE
    var bounds = Rect2(origin,Vector2.ONE*WorldPathNetwork.CHUNK_SIZE)
    var clip = PackedVector2Array([bounds.position,bounds.position+Vector2(bounds.size.x,0),bounds.end,bounds.position+Vector2(0,bounds.size.y)])
    var stream = SurfaceTool.new()
    stream.begin(Mesh.PRIMITIVE_TRIANGLES)
    var count = 0
    var sample_cache: Dictionary = {}
    for road in await _network.routes_in_chunk_incremental(cell,scheduler):
        if not await scheduler.checkpoint(): return null
        for i in range(road.points.size()-1):
            if not await scheduler.checkpoint(): return null
            var a: Vector2 = road.points[i]
            var b: Vector2 = road.points[i+1]
            if not Rect2(a,Vector2.ZERO).expand(b).grow(road.edge).intersects(bounds): continue
            var steps = maxi(1,ceili(a.distance_to(b)/4.0))
            var normal = Vector2(-(b-a).y,(b-a).x).normalized()
            for step in range(steps):
                if not await scheduler.checkpoint(): return null
                var start = a.lerp(b,float(step)/steps)
                var end = a.lerp(b,float(step+1)/steps)
                # Split core and shoulders to keep fades visible on narrow paths too.
                var widths = [-road.edge,-road.core,0.0,road.core,road.edge]
                for lane in range(widths.size()-1):
                    if not await scheduler.checkpoint(): return null
                    var polygon = PackedVector2Array([start+normal*widths[lane],end+normal*widths[lane],end+normal*widths[lane+1],start+normal*widths[lane+1]])
                    for clipped in _ground_polygons(polygon,clip):
                        if not await scheduler.checkpoint(): return null
                        for j in range(1,clipped.size()-1):
                            if not await scheduler.checkpoint(): return null
                            var triangle = [clipped[0],clipped[j],clipped[j+1]]
                            var vertices: Array[Vector3] = []
                            var colours: Array[Color] = []
                            var dry = true
                            for point: Vector2 in triangle:
                                if not await scheduler.checkpoint(): return null
                                if not sample_cache.has(point):
                                    var mask = TerrainPathSampler.get_wear_mask(point,_terrain)
                                    var colour = WorldPathNetwork.EDGE_COLOUR.lerp(WorldPathNetwork.CORE_COLOUR,smoothstep(.48,.92,mask))
                                    colour.a = mask
                                    sample_cache[point] = [_terrain.has_water_at(point),_network._settlements.ground_height(point),colour]
                                var sample = sample_cache[point]
                                if sample[0]: dry = false; break
                                vertices.append(Vector3(point.x-origin.x,sample[1]+.035,point.y-origin.y))
                                colours.append(sample[2])
                            if not dry: continue
                            var face = -(vertices[1]-vertices[0]).cross(vertices[2]-vertices[0])
                            if face.length_squared() < .00000001: continue
                            if face.y < 0:
                                vertices.reverse()
                                colours.reverse()
                                face = -face
                            for k in range(3):
                                if not await scheduler.checkpoint(): return null
                                stream.set_normal(face.normalized())
                                stream.set_color(colours[k])
                                stream.add_vertex(vertices[k])
                            count += 1
    if count == 0: return null
    var mesh = stream.commit()
    mesh.surface_set_material(0,_material)
    mesh.resource_name = "SharedPaths_%d_%d"%[cell.x,cell.y]
    return mesh
