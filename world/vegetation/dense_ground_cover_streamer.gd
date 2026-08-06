extends Node3D
class_name DenseGroundCoverStreamer

const FLORA_SHADER: Shader = preload("res://world/vegetation/ground_flora.gdshader")
const VISUAL_RADIUS: int = 2
const INITIAL_BUILD_RADIUS: int = 0
const CHUNKS_BUILT_PER_FRAME: int = 1
const REFRESH_INTERVAL: float = 0.16
const INVALID_CHUNK: Vector2i = Vector2i(2_147_483_647, 2_147_483_647)
const HASH_MAXIMUM: float = 2147483647.0
const SLOPE_SAMPLE_DISTANCE: float = 3.5
const VISIBILITY_MARGIN: float = 80.0

enum Layer { GRASS, HERBS }

const LAYER_NAMES: Array[String] = ["DenseGrass", "LowHerbs"]
const CELL_SIZES: Array[float] = [4.5, 9.0]
const VISIBILITY_RANGES: Array[float] = [660.0, 500.0]
const SLOPE_LIMITS: Array[float] = [7.0, 5.2]
const ALTITUDE_FADE_STARTS: Array[float] = [1850.0, 1450.0]
const ALTITUDE_FADE_ENDS: Array[float] = [3000.0, 2400.0]
const MINIMUM_WATER_CLEARANCES: Array[float] = [2.5, 5.0]
const JITTERS: Array[float] = [0.94, 0.88]
const SALTS: Array[int] = [809, 907]

var _terrain: InfiniteTerrain
var _player: Node3D
var _water_sampler: TerrainWaterLevelSampler
var _fertility_noise: FastNoiseLite
var _moisture_noise: FastNoiseLite
var _coverage_noise: FastNoiseLite
var _meadow_noise: FastNoiseLite
var _meshes: Array[Mesh] = []
var _chunks: Dictionary[Vector2i, Node3D] = {}
var _desired_chunks: Dictionary[Vector2i, bool] = {}
var _pending_chunks: Array[Vector2i] = []
var _pending_index: int = 0
var _current_chunk: Vector2i = INVALID_CHUNK
var _last_local_origin: Vector2 = Vector2(INF, INF)
var _refresh_elapsed: float = 0.0
var _initialized: bool = false

func _ready() -> void:
    var terrain_node: Node = get_node_or_null("../World/Terrain")
    var player_node: Node = get_node_or_null("../DynamicEntities/Player")
    if terrain_node is InfiniteTerrain:
        _terrain = terrain_node as InfiniteTerrain
    if player_node is Node3D:
        _player = player_node as Node3D

func _process(delta: float) -> void:
    if not _initialized:
        _try_initialize()
        return
    if _terrain == null or _player == null:
        return
    _refresh_elapsed += delta
    if _refresh_elapsed >= REFRESH_INTERVAL:
        _refresh_elapsed = 0.0
        _update_positions_if_rebased()
        var player_chunk: Vector2i = _get_chunk_coordinate(_get_player_world_position())
        if player_chunk != _current_chunk:
            _current_chunk = player_chunk
            _refresh_streaming_set(_current_chunk)
    _build_pending_chunks()

func _try_initialize() -> void:
    if _terrain == null or _player == null:
        return
    if _terrain.get_loaded_chunk_count() <= 0 or not _player.is_physics_processing():
        return
    _water_sampler = TerrainWaterLevelSampler.new()
    _fertility_noise = _create_noise(733, 0.00078, 3, 0.54)
    _moisture_noise = _create_noise(751, 0.00128, 3, 0.52)
    _coverage_noise = _create_noise(773, 0.0068, 2, 0.47)
    _meadow_noise = _create_noise(797, 0.0021, 3, 0.53)
    _create_meshes()
    _current_chunk = _get_chunk_coordinate(_get_player_world_position())
    _refresh_streaming_set(_current_chunk)
    _build_initial_area(_current_chunk)
    _update_chunk_positions()
    _initialized = true

func _refresh_streaming_set(centre: Vector2i) -> void:
    _desired_chunks.clear()
    _pending_chunks.clear()
    _pending_index = 0
    for ring: int in range(VISUAL_RADIUS + 1):
        for offset_z: int in range(-ring, ring + 1):
            for offset_x: int in range(-ring, ring + 1):
                if maxi(absi(offset_x), absi(offset_z)) != ring:
                    continue
                var coordinate: Vector2i = centre + Vector2i(offset_x, offset_z)
                _desired_chunks[coordinate] = true
                if not _chunks.has(coordinate):
                    _pending_chunks.append(coordinate)
    var chunks_to_remove: Array[Vector2i] = []
    for coordinate: Vector2i in _chunks.keys():
        if not _desired_chunks.has(coordinate):
            chunks_to_remove.append(coordinate)
    for coordinate: Vector2i in chunks_to_remove:
        var chunk: Node3D = _chunks[coordinate]
        _chunks.erase(coordinate)
        chunk.queue_free()

func _build_initial_area(centre: Vector2i) -> void:
    for offset_z: int in range(-INITIAL_BUILD_RADIUS, INITIAL_BUILD_RADIUS + 1):
        for offset_x: int in range(-INITIAL_BUILD_RADIUS, INITIAL_BUILD_RADIUS + 1):
            var coordinate: Vector2i = centre + Vector2i(offset_x, offset_z)
            if not _chunks.has(coordinate):
                _build_chunk(coordinate)

func _build_pending_chunks() -> void:
    var built: int = 0
    while built < CHUNKS_BUILT_PER_FRAME and _pending_index < _pending_chunks.size():
        var coordinate: Vector2i = _pending_chunks[_pending_index]
        _pending_index += 1
        if not _desired_chunks.has(coordinate) or _chunks.has(coordinate):
            continue
        _build_chunk(coordinate)
        built += 1

func _build_chunk(coordinate: Vector2i) -> void:
    var chunk_origin: Vector2 = Vector2(float(coordinate.x), float(coordinate.y)) * TerrainConfiguration.CHUNK_SIZE
    var chunk: Node3D = Node3D.new()
    chunk.name = "DenseGroundCoverChunk_%d_%d" % [coordinate.x, coordinate.y]
    chunk.position = _get_chunk_local_position(coordinate)
    add_child(chunk)
    for layer: int in range(LAYER_NAMES.size()):
        var transforms: Array[Transform3D] = []
        var colours: Array[Color] = []
        _sample_layer(layer, chunk_origin, transforms, colours)
        _add_batch(chunk, layer, transforms, colours)
    _chunks[coordinate] = chunk

func _sample_layer(layer: int, chunk_origin: Vector2, transforms: Array[Transform3D], colours: Array[Color]) -> void:
    var cell_size: float = CELL_SIZES[layer]
    var minimum_cell_x: int = floori(chunk_origin.x / cell_size)
    var maximum_cell_x: int = floori((chunk_origin.x + TerrainConfiguration.CHUNK_SIZE - 0.001) / cell_size)
    var minimum_cell_z: int = floori(chunk_origin.y / cell_size)
    var maximum_cell_z: int = floori((chunk_origin.y + TerrainConfiguration.CHUNK_SIZE - 0.001) / cell_size)
    for cell_z: int in range(minimum_cell_z, maximum_cell_z + 1):
        for cell_x: int in range(minimum_cell_x, maximum_cell_x + 1):
            var candidate: Vector2 = _get_candidate(cell_x, cell_z, cell_size, JITTERS[layer], SALTS[layer])
            if not _inside_chunk(candidate, chunk_origin):
                continue
            var fertility: float = _sample_noise(_fertility_noise, candidate)
            var moisture: float = _sample_noise(_moisture_noise, candidate)
            var local_coverage: float = _sample_noise(_coverage_noise, candidate)
            var probability: float = _get_probability(layer, fertility, moisture, local_coverage, candidate)
            var roll: float = _hash01(cell_x, cell_z, SALTS[layer] + 13)
            if roll > probability:
                continue
            var terrain_height: float = _terrain.get_height_at(candidate)
            var altitude_weight: float = 1.0 - smoothstep(ALTITUDE_FADE_STARTS[layer], ALTITUDE_FADE_ENDS[layer], terrain_height)
            if roll > probability * altitude_weight:
                continue
            var water_clearance: float = terrain_height - _sample_water_level(candidate)
            if water_clearance < MINIMUM_WATER_CLEARANCES[layer]:
                continue
            var shore_weight: float = smoothstep(MINIMUM_WATER_CLEARANCES[layer], MINIMUM_WATER_CLEARANCES[layer] + 12.0, water_clearance)
            if roll > probability * altitude_weight * shore_weight:
                continue
            if _sample_slope(candidate, terrain_height) > SLOPE_LIMITS[layer]:
                continue
            transforms.append(_make_transform(layer, cell_x, cell_z, candidate, chunk_origin, terrain_height))
            colours.append(_get_colour(layer, cell_x, cell_z, fertility, moisture))

func _get_probability(layer: int, fertility: float, moisture: float, local_coverage: float, position: Vector2) -> float:
    if layer == Layer.GRASS:
        return clampf(0.86 + fertility * 0.06 + moisture * 0.04 + local_coverage * 0.05, 0.86, 0.995)
    var meadow: float = _sample_noise(_meadow_noise, position)
    return clampf(0.16 + smoothstep(0.36, 0.72, fertility) * 0.28 + smoothstep(0.40, 0.76, moisture) * 0.18 + smoothstep(0.48, 0.76, meadow) * 0.34 + local_coverage * 0.08, 0.10, 0.88)

func _make_transform(layer: int, cell_x: int, cell_z: int, position: Vector2, chunk_origin: Vector2, terrain_height: float) -> Transform3D:
    var width_minimum: float = 0.82 if layer == Layer.GRASS else 0.72
    var width_maximum: float = 1.24 if layer == Layer.GRASS else 1.32
    var height_minimum: float = 0.72 if layer == Layer.GRASS else 0.68
    var height_maximum: float = 1.42 if layer == Layer.GRASS else 1.28
    var width_scale: float = lerpf(width_minimum, width_maximum, _hash01(cell_x, cell_z, SALTS[layer] + 23))
    var height_scale: float = lerpf(height_minimum, height_maximum, _hash01(cell_x, cell_z, SALTS[layer] + 29))
    var yaw: float = _hash01(cell_x, cell_z, SALTS[layer] + 31) * TAU
    var basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3(width_scale, height_scale, width_scale))
    var local_position: Vector3 = Vector3(position.x - chunk_origin.x, terrain_height - 0.04, position.y - chunk_origin.y)
    return Transform3D(basis, local_position)

func _get_colour(layer: int, cell_x: int, cell_z: int, fertility: float, moisture: float) -> Color:
    var colour: Color
    if layer == Layer.GRASS:
        var dry_colour: Color = Color(0.30, 0.35, 0.09)
        var lush_colour: Color = Color(0.10, 0.43, 0.075)
        colour = dry_colour.lerp(lush_colour, clampf(moisture * 0.62 + fertility * 0.38, 0.0, 1.0))
    else:
        var dry_herb_colour: Color = Color(0.19, 0.29, 0.075)
        var lush_herb_colour: Color = Color(0.075, 0.36, 0.095)
        colour = dry_herb_colour.lerp(lush_herb_colour, clampf(moisture * 0.72 + fertility * 0.28, 0.0, 1.0))
    var brightness: float = lerpf(0.82, 1.18, _hash01(cell_x, cell_z, SALTS[layer] + 37))
    return Color(clampf(colour.r * brightness, 0.0, 1.0), clampf(colour.g * brightness, 0.0, 1.0), clampf(colour.b * brightness, 0.0, 1.0), 1.0)

func _add_batch(parent: Node3D, layer: int, transforms: Array[Transform3D], colours: Array[Color]) -> void:
    if transforms.is_empty():
        return
    var multimesh: MultiMesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.use_colors = true
    multimesh.mesh = _meshes[layer]
    multimesh.instance_count = transforms.size()
    var minimum_y: float = INF
    var maximum_y: float = -INF
    for index: int in range(transforms.size()):
        multimesh.set_instance_transform(index, transforms[index])
        multimesh.set_instance_color(index, colours[index])
        minimum_y = minf(minimum_y, transforms[index].origin.y)
        maximum_y = maxf(maximum_y, transforms[index].origin.y)
    multimesh.custom_aabb = AABB(Vector3(-8.0, minimum_y - 5.0, -8.0), Vector3(TerrainConfiguration.CHUNK_SIZE + 16.0, maxf(maximum_y - minimum_y + 12.0, 20.0), TerrainConfiguration.CHUNK_SIZE + 16.0))
    var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
    instance.name = LAYER_NAMES[layer]
    instance.multimesh = multimesh
    instance.visibility_range_end = VISIBILITY_RANGES[layer]
    instance.visibility_range_end_margin = VISIBILITY_MARGIN
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(instance)

func _create_meshes() -> void:
    _meshes.clear()
    _meshes.append(_create_patch_mesh(0.96, 0.048, 24, 2.45, 0.13, 0.12))
    _meshes.append(_create_patch_mesh(0.58, 0.092, 14, 1.25, 0.09, 0.075))

func _create_patch_mesh(height: float, half_width: float, blade_count: int, spread_radius: float, bend: float, wind: float) -> ArrayMesh:
    var vertices: PackedVector3Array = PackedVector3Array()
    var normals: PackedVector3Array = PackedVector3Array()
    var vertex_colours: PackedColorArray = PackedColorArray()
    var uvs: PackedVector2Array = PackedVector2Array()
    var indices: PackedInt32Array = PackedInt32Array()
    const GOLDEN_ANGLE: float = 2.39996323
    for blade: int in range(blade_count):
        var radial_fraction: float = sqrt((float(blade) + 0.5) / float(blade_count))
        var radial_angle: float = float(blade) * GOLDEN_ANGLE
        var base: Vector3 = Vector3(cos(radial_angle), 0.0, sin(radial_angle)) * spread_radius * radial_fraction
        var facing_angle: float = radial_angle + PI * 0.5 + sin(float(blade) * 12.9898) * 0.55
        var right: Vector3 = Vector3(cos(facing_angle), 0.0, sin(facing_angle))
        var forward: Vector3 = Vector3(-sin(facing_angle), 0.0, cos(facing_angle))
        var blade_height: float = height * lerpf(0.68, 1.0, float((blade * 37) % 17) / 16.0)
        var blade_width: float = half_width * lerpf(0.62, 1.08, float((blade * 23) % 13) / 12.0)
        var lean: float = bend * lerpf(0.58, 1.15, float((blade * 19) % 11) / 10.0)
        var start: int = vertices.size()
        vertices.append_array(PackedVector3Array([
            base - right * blade_width,
            base + right * blade_width,
            base + Vector3.UP * blade_height * 0.56 + forward * lean * 0.28 - right * blade_width * 0.58,
            base + Vector3.UP * blade_height * 0.56 + forward * lean * 0.28 + right * blade_width * 0.58,
            base + Vector3.UP * blade_height + forward * lean,
        ]))
        for _unused: int in range(5):
            normals.append(forward)
            vertex_colours.append(Color.WHITE)
        uvs.append_array(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0.18, 0.56), Vector2(0.82, 0.56), Vector2(0.5, 1)]))
        indices.append_array(PackedInt32Array([start, start + 1, start + 2, start + 1, start + 3, start + 2, start + 2, start + 3, start + 4]))
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_COLOR] = vertex_colours
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh: ArrayMesh = ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = FLORA_SHADER
    material.set_shader_parameter("wind_strength", wind)
    mesh.surface_set_material(0, material)
    return mesh

func _get_candidate(cell_x: int, cell_z: int, cell_size: float, jitter: float, salt: int) -> Vector2:
    var centre: Vector2 = Vector2((float(cell_x) + 0.5) * cell_size, (float(cell_z) + 0.5) * cell_size)
    var half_jitter: float = cell_size * jitter * 0.5
    return centre + Vector2(lerpf(-half_jitter, half_jitter, _hash01(cell_x, cell_z, salt)), lerpf(-half_jitter, half_jitter, _hash01(cell_x, cell_z, salt + 1)))

func _inside_chunk(position: Vector2, chunk_origin: Vector2) -> bool:
    return position.x >= chunk_origin.x and position.x < chunk_origin.x + TerrainConfiguration.CHUNK_SIZE and position.y >= chunk_origin.y and position.y < chunk_origin.y + TerrainConfiguration.CHUNK_SIZE

func _sample_slope(position: Vector2, centre_height: float) -> float:
    var diagonal: Vector2 = Vector2(SLOPE_SAMPLE_DISTANCE, SLOPE_SAMPLE_DISTANCE)
    return maxf(absf(_terrain.get_height_at(position + diagonal) - centre_height), absf(_terrain.get_height_at(position - diagonal) - centre_height))

func _sample_water_level(position: Vector2) -> float:
    var water_cell_size: float = TerrainConfiguration.CHUNK_SIZE / float(TerrainConfiguration.WATER_RESOLUTION - 1)
    var water_cell: Vector2i = Vector2i(floori(position.x / water_cell_size), floori(position.y / water_cell_size))
    return _water_sampler.sample_water_level((float(water_cell.x) + 0.5) * water_cell_size, (float(water_cell.y) + 0.5) * water_cell_size)

func _sample_noise(noise: FastNoiseLite, position: Vector2) -> float:
    return clampf((noise.get_noise_2d(position.x, position.y) + 1.0) * 0.5, 0.0, 1.0)

func _hash01(x: int, z: int, salt: int) -> float:
    var value: int = x * 374761393 + z * 668265263 + salt * 982451653 + TerrainHeightSampler.WORLD_SEED * 31
    value = (value ^ (value >> 13)) & 0x7fffffff
    value = (value * 1274126177) & 0x7fffffff
    value = value ^ (value >> 16)
    return float(value & 0x7fffffff) / HASH_MAXIMUM

func _create_noise(seed_offset: int, frequency: float, octaves: int, gain: float) -> FastNoiseLite:
    var noise: FastNoiseLite = FastNoiseLite.new()
    noise.seed = TerrainHeightSampler.WORLD_SEED + seed_offset
    noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    noise.frequency = frequency
    noise.fractal_type = FastNoiseLite.FRACTAL_FBM
    noise.fractal_octaves = octaves
    noise.fractal_gain = gain
    noise.fractal_lacunarity = 2.0
    return noise

func _get_player_world_position() -> Vector2:
    var world_position: Vector3 = _terrain.local_to_world_position(_player.global_position)
    return Vector2(world_position.x, world_position.z)

func _get_chunk_coordinate(world_position: Vector2) -> Vector2i:
    return Vector2i(floori(world_position.x / TerrainConfiguration.CHUNK_SIZE), floori(world_position.y / TerrainConfiguration.CHUNK_SIZE))

func _get_chunk_local_position(coordinate: Vector2i) -> Vector3:
    return _terrain.world_to_local_position(Vector3(float(coordinate.x) * TerrainConfiguration.CHUNK_SIZE, 0.0, float(coordinate.y) * TerrainConfiguration.CHUNK_SIZE))

func _update_positions_if_rebased() -> void:
    var local_origin: Vector3 = _terrain.world_to_local_position(Vector3.ZERO)
    var horizontal_origin: Vector2 = Vector2(local_origin.x, local_origin.z)
    if horizontal_origin.is_equal_approx(_last_local_origin):
        return
    _update_chunk_positions()

func _update_chunk_positions() -> void:
    var local_origin: Vector3 = _terrain.world_to_local_position(Vector3.ZERO)
    _last_local_origin = Vector2(local_origin.x, local_origin.z)
    for coordinate: Vector2i in _chunks.keys():
        var chunk: Node3D = _chunks[coordinate]
        chunk.position = _get_chunk_local_position(coordinate)
