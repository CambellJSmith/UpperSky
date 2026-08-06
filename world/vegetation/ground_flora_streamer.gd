extends Node3D
class_name GroundFloraStreamer

const FLORA_SHADER: Shader = preload("res://world/vegetation/ground_flora.gdshader")
const VISUAL_RADIUS := 3
const INITIAL_BUILD_RADIUS := 0
const CHUNKS_BUILT_PER_FRAME := 1
const REFRESH_INTERVAL := 0.18
const INVALID_CHUNK := Vector2i(2_147_483_647, 2_147_483_647)
const HASH_MAXIMUM := 2147483647.0
const VISIBILITY_MARGIN := 90.0
const SLOPE_SAMPLE_DISTANCE := 4.0

enum Species { GRASS, SHRUB, FERN, REED, FLOWER }

const SPECIES_NAMES := ["Grass", "Shrubs", "Ferns", "Reeds", "Wildflowers"]
const CELL_SIZES := [7.25, 25.0, 16.0, 10.5, 14.5]
const VISIBILITY_RANGES := [640.0, 1050.0, 720.0, 760.0, 560.0]
const SLOPE_LIMITS := [3.8, 5.4, 4.4, 3.0, 3.1]
const ALTITUDE_FADE_STARTS := [1500.0, 1200.0, 1050.0, 1450.0, 1250.0]
const ALTITUDE_FADE_ENDS := [2750.0, 2150.0, 1900.0, 2250.0, 2200.0]
const MIN_WATER_CLEARANCES := [7.0, 16.0, 10.0, -0.75, 8.0]
const MAX_WATER_CLEARANCES := [INF, INF, INF, 4.4, INF]
const JITTERS := [0.82, 0.72, 0.78, 0.84, 0.80]
const SALTS := [17, 71, 131, 191, 251]
const FLOWER_COLORS := [
    Color(0.94, 0.78, 0.20),
    Color(0.86, 0.84, 0.73),
    Color(0.56, 0.35, 0.72),
    Color(0.35, 0.53, 0.77),
]

var _terrain: InfiniteTerrain
var _player: Node3D
var _water_sampler: TerrainWaterLevelSampler
var _fertility_noise: FastNoiseLite
var _moisture_noise: FastNoiseLite
var _patch_noise: FastNoiseLite
var _wetland_noise: FastNoiseLite
var _flower_noise: FastNoiseLite
var _meshes: Array[Mesh] = []
var _chunks: Dictionary[Vector2i, Node3D] = {}
var _desired_chunks: Dictionary[Vector2i, bool] = {}
var _pending_chunks: Array[Vector2i] = []
var _pending_index := 0
var _current_chunk := INVALID_CHUNK
var _last_local_origin := Vector2(INF, INF)
var _refresh_elapsed := 0.0
var _initialized := false

func _ready() -> void:
    var terrain_node := get_node_or_null("../World/Terrain")
    var player_node := get_node_or_null("../DynamicEntities/Player")
    if terrain_node is InfiniteTerrain:
        _terrain = terrain_node
    if player_node is Node3D:
        _player = player_node

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
        var player_chunk := _get_chunk_coordinate(_get_player_world_position())
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
    _fertility_noise = _create_noise(601, 0.00085, 3, 0.54)
    _moisture_noise = _create_noise(617, 0.00145, 3, 0.52)
    _patch_noise = _create_noise(641, 0.0075, 2, 0.48)
    _wetland_noise = _create_noise(659, 0.0032, 2, 0.50)
    _flower_noise = _create_noise(683, 0.0023, 3, 0.53)
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
    for ring in range(VISUAL_RADIUS + 1):
        for offset_z in range(-ring, ring + 1):
            for offset_x in range(-ring, ring + 1):
                if maxi(absi(offset_x), absi(offset_z)) != ring:
                    continue
                var coordinate := centre + Vector2i(offset_x, offset_z)
                _desired_chunks[coordinate] = true
                if not _chunks.has(coordinate):
                    _pending_chunks.append(coordinate)
    var to_remove: Array[Vector2i] = []
    for coordinate in _chunks.keys():
        if not _desired_chunks.has(coordinate):
            to_remove.append(coordinate)
    for coordinate in to_remove:
        var chunk := _chunks[coordinate]
        _chunks.erase(coordinate)
        chunk.queue_free()

func _build_initial_area(centre: Vector2i) -> void:
    for z in range(-INITIAL_BUILD_RADIUS, INITIAL_BUILD_RADIUS + 1):
        for x in range(-INITIAL_BUILD_RADIUS, INITIAL_BUILD_RADIUS + 1):
            var coordinate := centre + Vector2i(x, z)
            if not _chunks.has(coordinate):
                _build_chunk(coordinate)

func _build_pending_chunks() -> void:
    var built := 0
    while built < CHUNKS_BUILT_PER_FRAME and _pending_index < _pending_chunks.size():
        var coordinate := _pending_chunks[_pending_index]
        _pending_index += 1
        if not _desired_chunks.has(coordinate) or _chunks.has(coordinate):
            continue
        _build_chunk(coordinate)
        built += 1

func _build_chunk(coordinate: Vector2i) -> void:
    var origin := Vector2(float(coordinate.x), float(coordinate.y)) * TerrainConfiguration.CHUNK_SIZE
    var chunk := Node3D.new()
    chunk.name = "GroundFloraChunk_%d_%d" % [coordinate.x, coordinate.y]
    chunk.position = _get_chunk_local_position(coordinate)
    add_child(chunk)
    for species in range(SPECIES_NAMES.size()):
        var transforms: Array[Transform3D] = []
        var colours: Array[Color] = []
        _sample_species(species, origin, transforms, colours)
        _add_batch(chunk, species, transforms, colours)
    _chunks[coordinate] = chunk

func _sample_species(species: int, chunk_origin: Vector2, transforms: Array[Transform3D], colours: Array[Color]) -> void:
    var cell_size: float = CELL_SIZES[species]
    var min_x := floori(chunk_origin.x / cell_size)
    var max_x := floori((chunk_origin.x + TerrainConfiguration.CHUNK_SIZE - 0.001) / cell_size)
    var min_z := floori(chunk_origin.y / cell_size)
    var max_z := floori((chunk_origin.y + TerrainConfiguration.CHUNK_SIZE - 0.001) / cell_size)
    for cell_z in range(min_z, max_z + 1):
        for cell_x in range(min_x, max_x + 1):
            var candidate := _get_candidate(cell_x, cell_z, cell_size, JITTERS[species], SALTS[species])
            if not _inside_chunk(candidate, chunk_origin):
                continue
            var fertility := _sample_noise(_fertility_noise, candidate)
            var moisture := _sample_noise(_moisture_noise, candidate)
            var patch := _sample_noise(_patch_noise, candidate)
            var probability := _get_probability(species, fertility, moisture, patch, candidate)
            var roll := _hash01(cell_x, cell_z, SALTS[species] + 11)
            if roll > probability:
                continue
            var height := _terrain.get_height_at(candidate)
            var altitude_weight := 1.0 - smoothstep(ALTITUDE_FADE_STARTS[species], ALTITUDE_FADE_ENDS[species], height)
            if roll > probability * altitude_weight:
                continue
            var water_clearance := height - _sample_water_level(candidate)
            if water_clearance < MIN_WATER_CLEARANCES[species] or water_clearance > MAX_WATER_CLEARANCES[species]:
                continue
            if species != Species.REED:
                var shore_weight := smoothstep(MIN_WATER_CLEARANCES[species], MIN_WATER_CLEARANCES[species] + 24.0, water_clearance)
                if roll > probability * altitude_weight * shore_weight:
                    continue
            if _sample_slope(candidate, height) > SLOPE_LIMITS[species]:
                continue
            transforms.append(_make_transform(species, cell_x, cell_z, candidate, chunk_origin, height))
            colours.append(_get_colour(species, cell_x, cell_z, fertility, moisture, candidate))

func _get_probability(species: int, fertility: float, moisture: float, patch: float, position: Vector2) -> float:
    match species:
        Species.GRASS:
            return clampf(0.52 + fertility * 0.27 + moisture * 0.10 + patch * 0.12, 0.0, 0.97)
        Species.SHRUB:
            return 0.06 + smoothstep(0.30, 0.78, fertility) * lerpf(0.45, 1.0, patch) * 0.48
        Species.FERN:
            return 0.04 + smoothstep(0.48, 0.78, moisture) * smoothstep(0.34, 0.72, fertility) * lerpf(0.45, 1.0, patch) * 0.62
        Species.REED:
            var wetland := _sample_noise(_wetland_noise, position)
            return clampf(0.28 + smoothstep(0.26, 0.76, wetland) * 0.60 + moisture * 0.08, 0.0, 0.94)
        Species.FLOWER:
            var flower_field := _sample_noise(_flower_noise, position)
            return 0.025 + smoothstep(0.52, 0.76, flower_field) * smoothstep(0.32, 0.70, fertility) * lerpf(0.45, 1.0, patch) * 0.54
    return 0.0

func _make_transform(species: int, cell_x: int, cell_z: int, position: Vector2, chunk_origin: Vector2, height: float) -> Transform3D:
    var width_min: float = [0.76, 0.72, 0.70, 0.78, 0.70][species]
    var width_max: float = [1.34, 1.65, 1.38, 1.42, 1.26][species]
    var height_min: float = [0.62, 0.62, 0.68, 0.72, 0.64][species]
    var height_max: float = [1.52, 1.45, 1.30, 1.58, 1.30][species]
    var width_scale: float = lerpf(width_min, width_max, _hash01(cell_x, cell_z, SALTS[species] + 23))
    var height_scale: float = lerpf(height_min, height_max, _hash01(cell_x, cell_z, SALTS[species] + 29))
    var yaw := _hash01(cell_x, cell_z, SALTS[species] + 31) * TAU
    var basis := Basis(Vector3.UP, yaw).scaled(Vector3(width_scale, height_scale, width_scale))
    var y_offset := 0.55 * height_scale if species == Species.SHRUB else (-0.08 if species == Species.REED else -0.02)
    var local_position := Vector3(position.x - chunk_origin.x, height + y_offset, position.y - chunk_origin.y)
    return Transform3D(basis, local_position)

func _get_colour(species: int, cell_x: int, cell_z: int, fertility: float, moisture: float, position: Vector2) -> Color:
    var colour: Color = Color.WHITE
    match species:
        Species.GRASS:
            colour = Color(0.30, 0.37, 0.11).lerp(Color(0.16, 0.42, 0.10), moisture * 0.62 + fertility * 0.38)
        Species.SHRUB:
            colour = Color(0.18, 0.29, 0.09).lerp(Color(0.09, 0.31, 0.08), moisture * 0.55 + fertility * 0.45)
        Species.FERN:
            colour = Color(0.07, 0.25, 0.09).lerp(Color(0.16, 0.43, 0.13), moisture * 0.70 + fertility * 0.30)
        Species.REED:
            var wetland := _sample_noise(_wetland_noise, position)
            colour = Color(0.42, 0.43, 0.16).lerp(Color(0.20, 0.42, 0.13), moisture * 0.65 + wetland * 0.35)
        Species.FLOWER:
            var index := mini(floori(_hash01(cell_x, cell_z, 281) * FLOWER_COLORS.size()), FLOWER_COLORS.size() - 1)
            colour = FLOWER_COLORS[index].lerp(Color(0.16, 0.42, 0.10), 0.18 + moisture * 0.10)
    var brightness := lerpf(0.84, 1.16, _hash01(cell_x, cell_z, SALTS[species] + 37))
    return Color(clampf(colour.r * brightness, 0.0, 1.0), clampf(colour.g * brightness, 0.0, 1.0), clampf(colour.b * brightness, 0.0, 1.0), 1.0)

func _add_batch(parent: Node3D, species: int, transforms: Array[Transform3D], colours: Array[Color]) -> void:
    if transforms.is_empty():
        return
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.use_colors = true
    multimesh.mesh = _meshes[species]
    multimesh.instance_count = transforms.size()
    var minimum_y := INF
    var maximum_y := -INF
    for index in range(transforms.size()):
        multimesh.set_instance_transform(index, transforms[index])
        multimesh.set_instance_color(index, colours[index])
        minimum_y = minf(minimum_y, transforms[index].origin.y)
        maximum_y = maxf(maximum_y, transforms[index].origin.y)
    multimesh.custom_aabb = AABB(Vector3(-6.0, minimum_y - 5.0, -6.0), Vector3(TerrainConfiguration.CHUNK_SIZE + 12.0, maxf(maximum_y - minimum_y + 12.0, 20.0), TerrainConfiguration.CHUNK_SIZE + 12.0))
    var instance := MultiMeshInstance3D.new()
    instance.name = SPECIES_NAMES[species]
    instance.multimesh = multimesh
    instance.visibility_range_end = VISIBILITY_RANGES[species]
    instance.visibility_range_end_margin = VISIBILITY_MARGIN
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if species == Species.SHRUB else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(instance)

func _create_meshes() -> void:
    _meshes.clear()
    _meshes.append(_create_blade_mesh(0.82, 0.052, 5, 0.12, 0.13))
    _meshes.append(_create_shrub_mesh())
    _meshes.append(_create_blade_mesh(0.70, 0.24, 7, 0.20, 0.09))
    _meshes.append(_create_blade_mesh(1.55, 0.045, 6, 0.10, 0.18))
    _meshes.append(_create_blade_mesh(0.48, 0.105, 5, 0.08, 0.08))

func _create_shrub_mesh() -> Mesh:
    var material := StandardMaterial3D.new()
    material.vertex_color_use_as_albedo = true
    material.albedo_color = Color.WHITE
    material.roughness = 0.97
    var mesh := SphereMesh.new()
    mesh.radius = 0.62
    mesh.height = 1.10
    mesh.radial_segments = 8
    mesh.rings = 5
    mesh.material = material
    return mesh

func _create_blade_mesh(height: float, half_width: float, blade_count: int, bend: float, wind: float) -> ArrayMesh:
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var colours := PackedColorArray()
    var uvs := PackedVector2Array()
    var indices := PackedInt32Array()
    for blade in range(blade_count):
        var angle := TAU * float(blade) / blade_count + sin(float(blade) * 12.9898) * 0.23
        var right := Vector3(cos(angle), 0.0, sin(angle))
        var forward := Vector3(-sin(angle), 0.0, cos(angle))
        var blade_height := height * lerpf(0.76, 1.0, float((blade * 37) % 11) / 10.0)
        var width := half_width * lerpf(0.72, 1.0, float((blade * 23) % 9) / 8.0)
        var base := right * sin(float(blade) * 4.17) * half_width * 0.85
        var start := vertices.size()
        vertices.append_array(PackedVector3Array([
            base - right * width,
            base + right * width,
            base + Vector3.UP * blade_height * 0.56 + forward * bend * 0.28 - right * width * 0.58,
            base + Vector3.UP * blade_height * 0.56 + forward * bend * 0.28 + right * width * 0.58,
            base + Vector3.UP * blade_height + forward * bend,
        ]))
        for _unused in range(5):
            normals.append(forward)
            colours.append(Color.WHITE)
        uvs.append_array(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0.18, 0.56), Vector2(0.82, 0.56), Vector2(0.5, 1)]))
        indices.append_array(PackedInt32Array([start, start + 1, start + 2, start + 1, start + 3, start + 2, start + 2, start + 3, start + 4]))
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_COLOR] = colours
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var material := ShaderMaterial.new()
    material.shader = FLORA_SHADER
    material.set_shader_parameter("wind_strength", wind)
    mesh.surface_set_material(0, material)
    return mesh

func _get_candidate(cell_x: int, cell_z: int, cell_size: float, jitter: float, salt: int) -> Vector2:
    var centre := Vector2((cell_x + 0.5) * cell_size, (cell_z + 0.5) * cell_size)
    var half_jitter := cell_size * jitter * 0.5
    return centre + Vector2(
        lerpf(-half_jitter, half_jitter, _hash01(cell_x, cell_z, salt)),
        lerpf(-half_jitter, half_jitter, _hash01(cell_x, cell_z, salt + 1))
    )

func _inside_chunk(position: Vector2, origin: Vector2) -> bool:
    return position.x >= origin.x and position.x < origin.x + TerrainConfiguration.CHUNK_SIZE and position.y >= origin.y and position.y < origin.y + TerrainConfiguration.CHUNK_SIZE

func _sample_slope(position: Vector2, centre_height: float) -> float:
    var diagonal := Vector2(SLOPE_SAMPLE_DISTANCE, SLOPE_SAMPLE_DISTANCE)
    return maxf(absf(_terrain.get_height_at(position + diagonal) - centre_height), absf(_terrain.get_height_at(position - diagonal) - centre_height))

func _sample_water_level(position: Vector2) -> float:
    var cell_size := TerrainConfiguration.CHUNK_SIZE / float(TerrainConfiguration.WATER_RESOLUTION - 1)
    var cell := Vector2i(floori(position.x / cell_size), floori(position.y / cell_size))
    return _water_sampler.sample_water_level((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)

func _sample_noise(noise: FastNoiseLite, position: Vector2) -> float:
    return clampf((noise.get_noise_2d(position.x, position.y) + 1.0) * 0.5, 0.0, 1.0)

func _hash01(x: int, z: int, salt: int) -> float:
    var value := x * 374761393 + z * 668265263 + salt * 982451653 + TerrainHeightSampler.WORLD_SEED * 31
    value = (value ^ (value >> 13)) & 0x7fffffff
    value = (value * 1274126177) & 0x7fffffff
    value = value ^ (value >> 16)
    return float(value & 0x7fffffff) / HASH_MAXIMUM

func _create_noise(seed_offset: int, frequency: float, octaves: int, gain: float) -> FastNoiseLite:
    var noise := FastNoiseLite.new()
    noise.seed = TerrainHeightSampler.WORLD_SEED + seed_offset
    noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    noise.frequency = frequency
    noise.fractal_type = FastNoiseLite.FRACTAL_FBM
    noise.fractal_octaves = octaves
    noise.fractal_gain = gain
    noise.fractal_lacunarity = 2.0
    return noise

func _get_player_world_position() -> Vector2:
    var world_position := _terrain.local_to_world_position(_player.global_position)
    return Vector2(world_position.x, world_position.z)

func _get_chunk_coordinate(world_position: Vector2) -> Vector2i:
    return Vector2i(floori(world_position.x / TerrainConfiguration.CHUNK_SIZE), floori(world_position.y / TerrainConfiguration.CHUNK_SIZE))

func _get_chunk_local_position(coordinate: Vector2i) -> Vector3:
    return _terrain.world_to_local_position(Vector3(coordinate.x * TerrainConfiguration.CHUNK_SIZE, 0.0, coordinate.y * TerrainConfiguration.CHUNK_SIZE))

func _update_positions_if_rebased() -> void:
    var local_origin := _terrain.world_to_local_position(Vector3.ZERO)
    var horizontal := Vector2(local_origin.x, local_origin.z)
    if horizontal.is_equal_approx(_last_local_origin):
        return
    _update_chunk_positions()

func _update_chunk_positions() -> void:
    var local_origin := _terrain.world_to_local_position(Vector3.ZERO)
    _last_local_origin = Vector2(local_origin.x, local_origin.z)
    for coordinate in _chunks.keys():
        _chunks[coordinate].position = _get_chunk_local_position(coordinate)
