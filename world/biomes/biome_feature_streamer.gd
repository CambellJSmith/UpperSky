extends Node3D
class_name BiomeFeatureStreamer

const VISUAL_RADIUS: int = 4
const ICE_GRID_SIZE: float = 64.0
const WATERFALL_SHADER: Shader = preload("res://world/biomes/waterfall.gdshader")
const FOAM_SHADER: Shader = preload("res://world/biomes/foam.gdshader")
const SMOKE_SHADER: Shader = preload("res://world/biomes/volcanic_smoke.gdshader")
const LAVA_SHADER: Shader = preload("res://world/biomes/lava.gdshader")

@onready var _terrain: InfiniteTerrain = $"../Terrain"
@onready var _player: FirstPersonPlayer = $"../../DynamicEntities/Player"
var _chunks: Dictionary[Vector2i, Node3D] = {}
var _pending: Array[Vector2i] = []
var _centre: Vector2i = Vector2i(2147483647, 2147483647)
var _elapsed: float = 0.0
var _ice_meshes: Array[ArrayMesh] = []
var _ice_shapes: Array[Shape3D] = []
var _fall_material: ShaderMaterial
var _lava_material: ShaderMaterial
var _foam_material: ShaderMaterial
var _rock_material: StandardMaterial3D
var _smoke_material: ShaderMaterial

func _ready() -> void:
    _fall_material = ShaderMaterial.new()
    _fall_material.shader = WATERFALL_SHADER
    _lava_material = ShaderMaterial.new()
    _lava_material.shader = LAVA_SHADER
    _foam_material = ShaderMaterial.new()
    _foam_material.shader = FOAM_SHADER
    _smoke_material = ShaderMaterial.new()
    _smoke_material.shader = SMOKE_SHADER
    _rock_material = StandardMaterial3D.new()
    _rock_material.albedo_color = Color(0.28, 0.34, 0.37)
    _rock_material.roughness = 0.95
    for variant: int in range(6):
        var mesh: ArrayMesh = _create_ice_mesh(variant)
        _ice_meshes.append(mesh)
        _ice_shapes.append(mesh.create_convex_shape())

func _process(delta: float) -> void:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__process(delta)
        return
    var _profile_token = RuntimeProfiler.begin("biomes.stream")
    _profile__process(delta)
    RuntimeProfiler.end(_profile_token)

func _profile__process(delta: float) -> void:
    if _terrain.get_loaded_chunk_count() == 0 or not _player.is_physics_processing():
        return
    _elapsed += delta
    if _elapsed >= 0.2:
        _elapsed = 0.0
        var world: Vector3 = _terrain.local_to_world_position(_player.global_position)
        var centre: Vector2i = Vector2i(floori(world.x / TerrainConfiguration.CHUNK_SIZE), floori(world.z / TerrainConfiguration.CHUNK_SIZE))
        if centre != _centre:
            _centre = centre
            _refresh()
    for cell: Vector2i in _chunks.keys():
        var origin: Vector3 = Vector3(cell.x * TerrainConfiguration.CHUNK_SIZE, 0.0, cell.y * TerrainConfiguration.CHUNK_SIZE)
        _chunks[cell].position = _terrain.world_to_local_position(origin)
    if not _pending.is_empty():
        _build_chunk(_pending.pop_front())

func _refresh() -> void:
    _pending.clear()
    for cell: Vector2i in _chunks.keys():
        if maxi(absi(cell.x - _centre.x), absi(cell.y - _centre.y)) > VISUAL_RADIUS:
            _chunks[cell].queue_free()
            _chunks.erase(cell)
    for ring: int in range(VISUAL_RADIUS + 1):
        for z: int in range(-ring, ring + 1):
            for x: int in range(-ring, ring + 1):
                if maxi(absi(x), absi(z)) != ring:
                    continue
                var cell: Vector2i = _centre + Vector2i(x, z)
                if not _chunks.has(cell):
                    _pending.append(cell)
    for cell: Vector2i in _chunks.keys():
        _set_collision(cell)

func _build_chunk(cell: Vector2i) -> void:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__build_chunk(cell)
        return
    var _profile_token = RuntimeProfiler.begin("biomes.build")
    _profile__build_chunk(cell)
    RuntimeProfiler.end(_profile_token)

func _profile__build_chunk(cell: Vector2i) -> void:
    var chunk: Node3D = Node3D.new()
    chunk.name = "BiomeFeatures_%d_%d" % [cell.x, cell.y]
    var corner: Vector2 = Vector2(cell) * TerrainConfiguration.CHUNK_SIZE
    chunk.position = _terrain.world_to_local_position(Vector3(corner.x, 0.0, corner.y))
    add_child(chunk)
    _chunks[cell] = chunk
    var first: Vector2i = Vector2i(floori(corner.x / ICE_GRID_SIZE), floori(corner.y / ICE_GRID_SIZE))
    for z: int in range(4):
        for x: int in range(4):
            _add_ice(chunk, corner, first + Vector2i(x, z))
    var region_cell: Vector2i = Vector2i(floori(corner.x / BiomeProfile.REGION_SIZE), floori(corner.y / BiomeProfile.REGION_SIZE))
    var definition: Dictionary = BiomeProfile.region(region_cell)
    if definition["kind"] == BiomeProfile.Kind.RIVER_VALLEY:
        for drop_z: float in [-320.0, 320.0]:
            var point: Vector2 = definition["centre"] + Vector2(BiomeProfile.river_x(drop_z, definition["phase"]), drop_z)
            if _owns(point, corner) and BiomeProfile.weight(point, definition) > 0.99:
                _add_waterfall(chunk, corner, point, definition, drop_z)
    elif definition["kind"] == BiomeProfile.Kind.VOLCANIC_ISLANDS:
        var point: Vector2 = definition["centre"]
        if _owns(point, corner) and BiomeProfile.weight(point, definition) > 0.99:
            _add_lava(chunk, corner, point, definition["sea"] + 165.0)
    _set_collision(cell)

func _add_ice(chunk: Node3D, corner: Vector2, cell: Vector2i) -> void:
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = hash("ice:742913:%d:%d" % [cell.x, cell.y])
    if rng.randf() > 0.65:
        return
    var point: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5)) * ICE_GRID_SIZE
    point += Vector2(rng.randf_range(-15.0, 15.0), rng.randf_range(-15.0, 15.0))
    var definition: Dictionary = BiomeProfile.region_at(point)
    if definition["kind"] != BiomeProfile.Kind.ICE_FLATS or BiomeProfile.weight(point, definition) < 0.85:
        return
    var scale_value: float = rng.randf_range(0.65, 1.4)
    for offset: Vector2 in [Vector2.ZERO, Vector2(18.0, 0.0), Vector2(-18.0, 0.0), Vector2(0.0, 18.0), Vector2(0.0, -18.0)]:
        if not _terrain.has_water_at(point + offset):
            return # Keep complete floes offshore rather than intersecting dry ice shelves.
    var variant: int = rng.randi_range(0, _ice_meshes.size() - 1)
    var body: FloatingIce = FloatingIce.new()
    body.name = "IceFloe_%d_%d" % [cell.x, cell.y]
    body.position = Vector3(point.x - corner.x, _terrain.get_water_level_at(point), point.y - corner.y)
    body.initialize(body.position.y, rng.randf_range(0.0, TAU))
    body.rotation.y = rng.randf_range(0.0, TAU)
    body.scale = Vector3(scale_value, 1.0, scale_value * rng.randf_range(0.72, 1.12))
    var visual: MeshInstance3D = MeshInstance3D.new()
    visual.mesh = _ice_meshes[variant]
    body.add_child(visual)
    var collision: CollisionShape3D = CollisionShape3D.new()
    collision.name = "IceCollision"
    collision.shape = _ice_shapes[variant]
    body.add_child(collision)
    chunk.add_child(body)

func _set_collision(cell: Vector2i) -> void:
    var near: bool = maxi(absi(cell.x - _centre.x), absi(cell.y - _centre.y)) <= 1
    for child: Node in _chunks[cell].get_children():
        if child is StaticBody3D:
            child.get_node("IceCollision").set_deferred("disabled", not near)

func _owns(point: Vector2, corner: Vector2) -> bool:
    return point.x >= corner.x and point.x < corner.x + TerrainConfiguration.CHUNK_SIZE and point.y >= corner.y and point.y < corner.y + TerrainConfiguration.CHUNK_SIZE

func _add_waterfall(chunk: Node3D, corner: Vector2, point: Vector2, definition: Dictionary, drop_z: float) -> void:
    var top: float = float(WaterBodyPlan.definition_at(point - Vector2(0.0, 0.01)).surface_height) # Reads the planned upstream reach at the waterfall lip.
    var curtain: MeshInstance3D = MeshInstance3D.new()
    curtain.name = "Waterfall"
    var surface: SurfaceTool = SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    # Tapered polygon strips follow the channel into its plunge pool.
    for strip: int in range(12):
        var x0: float = -120.0 + strip * 20.0
        var x1: float = x0 + 20.0
        var source_a: Vector2 = point + Vector2(x0, -0.01) # Locates the first upper endpoint in the upstream water body.
        var source_b: Vector2 = point + Vector2(x1, -0.01) # Locates the second upper endpoint.
        var sink_offset: float = BiomeProfile.river_x(drop_z + 16.0, definition["phase"]) - BiomeProfile.river_x(drop_z, definition["phase"]) # Follows the planned channel bend into the pool.
        var sink_a: Vector2 = point + Vector2(x0 * 0.73 + sink_offset, 16.0) # Locates the first plunge-pool endpoint.
        var sink_b: Vector2 = point + Vector2(x1 * 0.73 + sink_offset, 16.0) # Locates the second plunge-pool endpoint.
        if not (_terrain.has_water_at(source_a) and _terrain.has_water_at(source_b) and _terrain.has_water_at(sink_a) and _terrain.has_water_at(sink_b)): # Keeps waterfall strips within both connected water reaches.
            continue # Excludes decorative curtains over dry banks.
        var a: Vector3 = Vector3(x0, 16.0, 0.0)
        var b: Vector3 = Vector3(x1, 16.0, 0.0)
        var c: Vector3 = Vector3(x0 * 0.73 + BiomeProfile.river_x(drop_z + 16.0, definition["phase"]) - BiomeProfile.river_x(drop_z, definition["phase"]), -16.0, 15.0 + sin(strip * 1.3) * 0.5)
        var d: Vector3 = Vector3(x1 * 0.73 + BiomeProfile.river_x(drop_z + 16.0, definition["phase"]) - BiomeProfile.river_x(drop_z, definition["phase"]), -16.0, 15.0 + sin((strip + 1) * 1.3) * 0.5)
        var points: Array[Vector3] = [a, b, c, b, d, c]
        var uvs: Array[Vector2] = [Vector2(float(strip)/12.0, 0.0), Vector2(float(strip+1)/12.0, 0.0), Vector2(float(strip)/12.0, 1.0), Vector2(float(strip+1)/12.0, 0.0), Vector2(float(strip+1)/12.0, 1.0), Vector2(float(strip)/12.0, 1.0)]
        for index: int in range(points.size()):
            surface.set_uv(uvs[index])
            surface.add_vertex(points[index])
    surface.generate_normals()
    curtain.mesh = surface.commit()
    curtain.material_override = _fall_material
    curtain.position = Vector3(point.x - corner.x, top - BiomeProfile.WATERFALL_DROP * 0.5, point.y - corner.y)
    chunk.add_child(curtain)
    var foam: MeshInstance3D = MeshInstance3D.new()
    foam.name = "WaterfallFoam"
    foam.mesh = _foam_disk()
    foam.material_override = _foam_material
    foam.position = Vector3(point.x - corner.x, top - BiomeProfile.WATERFALL_DROP + 0.2, point.y - corner.y + 20.0)
    chunk.add_child(foam)
    for side: float in [-1.0, 1.0]:
        for index: int in range(3):
            var rock: MeshInstance3D = MeshInstance3D.new()
            var source: SphereMesh = SphereMesh.new()
            source.radius = 1.0
            source.height = 2.0
            source.radial_segments = 6
            source.rings = 3
            rock.mesh = _flat_mesh(source)
            rock.material_override = _rock_material
            var location: Vector2 = (point + Vector2(side * (110.0 + index * 12.0), -8.0 + index * 11.0)).snapped(Vector2(8.0, 8.0))
            rock.position = Vector3(location.x - corner.x, _terrain.get_height_at(location) + 1.0, location.y - corner.y)
            rock.scale = Vector3(7.0 + index * 2.0, 6.0 + index, 9.0)
            rock.rotation.y = index * 0.8 + side
            chunk.add_child(rock)

func _foam_disk() -> ArrayMesh:
    var surface: SurfaceTool = SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for index: int in range(12):
        var a: float = TAU * float(index) / 12.0
        var b: float = TAU * float(index + 1) / 12.0
        for vertex: Vector3 in [Vector3.ZERO, Vector3(cos(a) * 44.0, 0.0, sin(a) * 25.0), Vector3(cos(b) * 44.0, 0.0, sin(b) * 25.0)]:
            surface.set_uv(Vector2(vertex.x / 172.0 + 0.5, vertex.z / 50.0 + 0.5))
            surface.set_normal(Vector3.UP)
            surface.add_vertex(vertex)
    return surface.commit()

func _flat_mesh(source: PrimitiveMesh) -> ArrayMesh:
    var arrays: Array = source.get_mesh_arrays()
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
    var surface: SurfaceTool = SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for index: int in range(0, indices.size(), 3):
        var a: Vector3 = vertices[indices[index]]
        var b: Vector3 = vertices[indices[index + 1]]
        var c: Vector3 = vertices[indices[index + 2]]
        var normal: Vector3 = -(b - a).cross(c - a).normalized()
        for vertex: Vector3 in [a, b, c]:
            surface.set_normal(normal)
            surface.add_vertex(vertex)
    return surface.commit()

func _add_lava(chunk: Node3D, corner: Vector2, point: Vector2, height: float) -> void:
    var lava: MeshInstance3D = MeshInstance3D.new()
    lava.name = "CraterLava"
    var disk: CylinderMesh = CylinderMesh.new()
    disk.top_radius = 60.0
    disk.bottom_radius = 60.0
    disk.height = 0.2
    disk.radial_segments = 12
    lava.mesh = disk
    lava.material_override = _lava_material
    lava.position = Vector3(point.x - corner.x, height, point.y - corner.y)
    chunk.add_child(lava)
    var glow: OmniLight3D = OmniLight3D.new()
    glow.position = lava.position + Vector3.UP * 8.0
    glow.light_color = Color(1.0, 0.18, 0.025)
    glow.light_energy = 2.0
    glow.omni_range = 140.0
    chunk.add_child(glow)

    for index: int in range(5):
        var smoke: MeshInstance3D = MeshInstance3D.new()
        smoke.name = "VolcanicSmoke%d" % index
        var sphere: SphereMesh = SphereMesh.new()
        sphere.radius = 1.0
        sphere.height = 2.0
        sphere.radial_segments = 7
        sphere.rings = 4
        smoke.mesh = _flat_mesh(sphere)
        smoke.material_override = _smoke_material
        var size: float = 12.0 + index * 7.0
        smoke.scale = Vector3(size, size * 0.8, size)
        smoke.position = lava.position + Vector3(index * 7.0, 25.0 + index * 27.0, index * -3.0)
        chunk.add_child(smoke)

func _create_ice_mesh(variant: int) -> ArrayMesh:
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = variant + 19213
    var surface: SurfaceTool = SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var outer: Array[Vector3] = []
    var inner: Array[Vector3] = []
    var peak: float = 1.2 if variant < 3 else 3.5 + variant * 0.65
    for index: int in range(7):
        var angle: float = TAU * float(index) / 7.0
        var radius: float = rng.randf_range(7.0, 11.0)
        outer.append(Vector3(cos(angle) * radius, 0.15, sin(angle) * radius))
        inner.append(Vector3(cos(angle) * radius * 0.77, rng.randf_range(0.9, 1.65), sin(angle) * radius * 0.77))
    for index: int in range(7):
        var next: int = (index + 1) % 7
        var a: Vector3 = outer[index]
        var b: Vector3 = outer[next]
        var c: Vector3 = inner[index]
        var d: Vector3 = inner[next]
        var top: Color = Color(0.57, 0.73, 0.81) * rng.randf_range(0.93, 1.04)
        top.a = 1.0
        _ice_triangle(surface, Vector3(-1.0, peak, 0.7), d, c, top)
        _ice_triangle(surface, c, d, a, Color(0.38, 0.62, 0.74))
        _ice_triangle(surface, a, d, b, Color(0.38, 0.62, 0.74))
        _ice_triangle(surface, a, b, Vector3(b.x, -2.4, b.z), Color(0.14, 0.38, 0.53))
        _ice_triangle(surface, a, Vector3(b.x, -2.4, b.z), Vector3(a.x, -2.4, a.z), Color(0.14, 0.38, 0.53))
    var mesh: ArrayMesh = surface.commit()
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.vertex_color_use_as_albedo = true
    material.roughness = 0.7
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    mesh.surface_set_material(0, material)
    return mesh

func _ice_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, colour: Color) -> void:
    var normal: Vector3 = -(c - a).cross(b - a).normalized()
    for vertex: Vector3 in [a, c, b]:
        surface.set_color(colour)
        surface.set_normal(normal)
        surface.add_vertex(vertex)
