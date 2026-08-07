extends Node3D
class_name DenseGroundCoverStreamer

const GRASS_SHADER: Shader = preload("res://world/vegetation/dense_ground_cover.gdshader")

const CARPET_SIZE: float = 320.0
const HALF_CARPET_SIZE: float = 160.0
const PATCH_SPACING: float = 3.2
const GRID_SIZE: int = 100
const TILE_AXIS_COUNT: int = 4
const TILE_GRID_SIZE: int = 25
const TILE_SIZE: float = 80.0
const HEIGHTMAP_RESOLUTION: int = 65
const HEIGHTMAP_STEP: float = 5.0
const RECENTER_STEP: float = 32.0
const REFRESH_INTERVAL: float = 0.12
const PATCH_BLADE_COUNT: int = 28
const PATCH_SPREAD_RADIUS: float = 2.35
const WATER_SHORE_START: float = 3.0
const WATER_SHORE_FULL: float = 14.0
const GRASS_ALTITUDE_FADE_START: float = 1750.0
const GRASS_ALTITUDE_FADE_END: float = 3000.0
const SLOPE_FADE_START: float = 0.22
const SLOPE_FADE_END: float = 0.95

var _terrain: InfiniteTerrain
var _player: Node3D
var _water_sampler: TerrainWaterLevelSampler
var _coverage_noise: FastNoiseLite
var _material: ShaderMaterial
var _terrain_image: Image
var _terrain_texture: ImageTexture
var _tiles: Array[MultiMeshInstance3D] = []
var _carpet_world_centre: Vector2 = Vector2(INF, INF)
var _carpet_world_origin: Vector2 = Vector2.ZERO
var _last_local_world_origin: Vector2 = Vector2(INF, INF)
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
    if _refresh_elapsed < REFRESH_INTERVAL:
        return
    _refresh_elapsed = 0.0
    _reposition_after_origin_change()
    _recenter_if_needed()

func _try_initialize() -> void:
    if _terrain == null or _player == null:
        return
    if _terrain.get_loaded_chunk_count() <= 0 or not _player.is_physics_processing():
        return
    _water_sampler = TerrainWaterLevelSampler.new()
    _coverage_noise = _create_noise(1031, 0.0048, 2, 0.48)
    _terrain_image = Image.create_empty(HEIGHTMAP_RESOLUTION, HEIGHTMAP_RESOLUTION, false, Image.FORMAT_RGF)
    _terrain_texture = ImageTexture.create_from_image(_terrain_image)
    _material = ShaderMaterial.new()
    _material.shader = GRASS_SHADER
    _material.set_shader_parameter("terrain_map", _terrain_texture)
    _material.set_shader_parameter("carpet_size", CARPET_SIZE)
    _material.set_shader_parameter("patch_spacing", PATCH_SPACING)
    _create_tiles()
    _recenter_if_needed(true)
    _initialized = true

func _recenter_if_needed(force_refresh: bool = false) -> void:
    var player_world_position: Vector3 = _terrain.local_to_world_position(_player.global_position)
    var snapped_centre: Vector2 = Vector2(
        roundf(player_world_position.x / RECENTER_STEP) * RECENTER_STEP,
        roundf(player_world_position.z / RECENTER_STEP) * RECENTER_STEP
    )
    if not force_refresh and snapped_centre == _carpet_world_centre:
        return
    _carpet_world_centre = snapped_centre
    _carpet_world_origin = _carpet_world_centre - Vector2(HALF_CARPET_SIZE, HALF_CARPET_SIZE)
    _material.set_shader_parameter("carpet_world_origin", _carpet_world_origin)
    _refresh_terrain_map()
    _reposition_tiles()

func _reposition_after_origin_change() -> void:
    var local_world_origin: Vector3 = _terrain.world_to_local_position(Vector3.ZERO)
    var signature: Vector2 = Vector2(local_world_origin.x, local_world_origin.z)
    if signature.is_equal_approx(_last_local_world_origin):
        return
    _reposition_tiles()

func _reposition_tiles() -> void:
    if _tiles.is_empty():
        return
    var local_origin: Vector3 = _terrain.world_to_local_position(Vector3(_carpet_world_origin.x, 0.0, _carpet_world_origin.y))
    for tile_z: int in range(TILE_AXIS_COUNT):
        for tile_x: int in range(TILE_AXIS_COUNT):
            var tile_index: int = tile_z * TILE_AXIS_COUNT + tile_x
            _tiles[tile_index].position = local_origin + Vector3(float(tile_x) * TILE_SIZE, 0.0, float(tile_z) * TILE_SIZE)
    var local_world_origin: Vector3 = _terrain.world_to_local_position(Vector3.ZERO)
    _last_local_world_origin = Vector2(local_world_origin.x, local_world_origin.z)

func _create_tiles() -> void:
    var patch_mesh: ArrayMesh = _create_patch_mesh()
    _tiles.clear()
    for tile_z: int in range(TILE_AXIS_COUNT):
        for tile_x: int in range(TILE_AXIS_COUNT):
            var multimesh: MultiMesh = MultiMesh.new()
            multimesh.transform_format = MultiMesh.TRANSFORM_3D
            multimesh.use_custom_data = true
            multimesh.mesh = patch_mesh
            multimesh.instance_count = TILE_GRID_SIZE * TILE_GRID_SIZE
            var instance_index: int = 0
            for local_z: int in range(TILE_GRID_SIZE):
                for local_x: int in range(TILE_GRID_SIZE):
                    var global_x: int = tile_x * TILE_GRID_SIZE + local_x
                    var global_z: int = tile_z * TILE_GRID_SIZE + local_z
                    var origin: Vector3 = Vector3((float(local_x) + 0.5) * PATCH_SPACING, 0.0, (float(local_z) + 0.5) * PATCH_SPACING)
                    multimesh.set_instance_transform(instance_index, Transform3D(Basis.IDENTITY, origin))
                    var sample_u: float = (float(global_x) + 0.5) / float(GRID_SIZE)
                    var sample_v: float = (float(global_z) + 0.5) / float(GRID_SIZE)
                    multimesh.set_instance_custom_data(instance_index, Color(sample_u, sample_v, 0.0, 0.0))
                    instance_index += 1
            multimesh.custom_aabb = AABB(Vector3(-3.0, -600.0, -3.0), Vector3(TILE_SIZE + 6.0, 6400.0, TILE_SIZE + 6.0))
            var tile: MultiMeshInstance3D = MultiMeshInstance3D.new()
            tile.name = "GrassTile_%d_%d" % [tile_x, tile_z]
            tile.multimesh = multimesh
            tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            tile.extra_cull_margin = 3.0
            add_child(tile)
            _tiles.append(tile)

func _refresh_terrain_map() -> void:
    var sample_count: int = HEIGHTMAP_RESOLUTION * HEIGHTMAP_RESOLUTION
    var heights: PackedFloat32Array = PackedFloat32Array()
    var water_levels: PackedFloat32Array = PackedFloat32Array()
    heights.resize(sample_count)
    water_levels.resize(sample_count)
    var water_cache: Dictionary[Vector2i, float] = {}
    var minimum_height: float = INF
    var maximum_height: float = -INF

    for sample_z: int in range(HEIGHTMAP_RESOLUTION):
        var world_z: float = _carpet_world_origin.y + float(sample_z) * HEIGHTMAP_STEP
        for sample_x: int in range(HEIGHTMAP_RESOLUTION):
            var world_x: float = _carpet_world_origin.x + float(sample_x) * HEIGHTMAP_STEP
            var index: int = sample_z * HEIGHTMAP_RESOLUTION + sample_x
            var position: Vector2 = Vector2(world_x, world_z)
            var height: float = _terrain.get_height_at(position)
            var water_level: float = _sample_water_level_cached(position, water_cache)
            heights[index] = height
            water_levels[index] = water_level
            minimum_height = minf(minimum_height, height)
            maximum_height = maxf(maximum_height, height)

    for sample_z: int in range(HEIGHTMAP_RESOLUTION):
        var previous_z: int = maxi(sample_z - 1, 0)
        var next_z: int = mini(sample_z + 1, HEIGHTMAP_RESOLUTION - 1)
        for sample_x: int in range(HEIGHTMAP_RESOLUTION):
            var previous_x: int = maxi(sample_x - 1, 0)
            var next_x: int = mini(sample_x + 1, HEIGHTMAP_RESOLUTION - 1)
            var index: int = sample_z * HEIGHTMAP_RESOLUTION + sample_x
            var left_height: float = heights[sample_z * HEIGHTMAP_RESOLUTION + previous_x]
            var right_height: float = heights[sample_z * HEIGHTMAP_RESOLUTION + next_x]
            var back_height: float = heights[previous_z * HEIGHTMAP_RESOLUTION + sample_x]
            var forward_height: float = heights[next_z * HEIGHTMAP_RESOLUTION + sample_x]
            var x_distance: float = maxf(float(next_x - previous_x) * HEIGHTMAP_STEP, HEIGHTMAP_STEP)
            var z_distance: float = maxf(float(next_z - previous_z) * HEIGHTMAP_STEP, HEIGHTMAP_STEP)
            var x_grade: float = absf(right_height - left_height) / x_distance
            var z_grade: float = absf(forward_height - back_height) / z_distance
            var terrain_grade: float = maxf(x_grade, z_grade)
            var slope_weight: float = 1.0 - smoothstep(SLOPE_FADE_START, SLOPE_FADE_END, terrain_grade)

            var height: float = heights[index]
            var water_clearance: float = height - water_levels[index]
            var shore_weight: float = smoothstep(WATER_SHORE_START, WATER_SHORE_FULL, water_clearance)
            var altitude_weight: float = 1.0 - smoothstep(GRASS_ALTITUDE_FADE_START, GRASS_ALTITUDE_FADE_END, height)
            var world_position: Vector2 = Vector2(
                _carpet_world_origin.x + float(sample_x) * HEIGHTMAP_STEP,
                _carpet_world_origin.y + float(sample_z) * HEIGHTMAP_STEP
            )
            var regional_density: float = lerpf(0.90, 1.0, _sample_noise(_coverage_noise, world_position))
            var coverage: float = clampf(shore_weight * slope_weight * altitude_weight * regional_density, 0.0, 1.0)
            _terrain_image.set_pixel(sample_x, sample_z, Color(height, coverage, 0.0, 1.0))

    _terrain_texture.update(_terrain_image)
    _update_tile_bounds(minimum_height, maximum_height)

func _update_tile_bounds(minimum_height: float, maximum_height: float) -> void:
    var vertical_size: float = maxf(maximum_height - minimum_height + 8.0, 16.0)
    for tile: MultiMeshInstance3D in _tiles:
        if tile.multimesh == null:
            continue
        tile.multimesh.custom_aabb = AABB(
            Vector3(-3.0, minimum_height - 3.0, -3.0),
            Vector3(TILE_SIZE + 6.0, vertical_size, TILE_SIZE + 6.0)
        )

func _sample_water_level_cached(position: Vector2, cache: Dictionary[Vector2i, float]) -> float:
    var water_cell_size: float = TerrainConfiguration.CHUNK_SIZE / float(TerrainConfiguration.WATER_RESOLUTION - 1)
    var water_cell: Vector2i = Vector2i(floori(position.x / water_cell_size), floori(position.y / water_cell_size))
    if cache.has(water_cell):
        return cache[water_cell]
    var sample_x: float = (float(water_cell.x) + 0.5) * water_cell_size
    var sample_z: float = (float(water_cell.y) + 0.5) * water_cell_size
    var water_level: float = _water_sampler.sample_water_level(sample_x, sample_z)
    cache[water_cell] = water_level
    return water_level

func _create_patch_mesh() -> ArrayMesh:
    var vertices: PackedVector3Array = PackedVector3Array()
    var normals: PackedVector3Array = PackedVector3Array()
    var uvs: PackedVector2Array = PackedVector2Array()
    var indices: PackedInt32Array = PackedInt32Array()
    const GOLDEN_ANGLE: float = 2.39996323

    for blade: int in range(PATCH_BLADE_COUNT):
        var radial_fraction: float = sqrt((float(blade) + 0.5) / float(PATCH_BLADE_COUNT))
        var radial_angle: float = float(blade) * GOLDEN_ANGLE
        var base: Vector3 = Vector3(cos(radial_angle), 0.0, sin(radial_angle)) * PATCH_SPREAD_RADIUS * radial_fraction
        var facing_angle: float = radial_angle * 1.37 + sin(float(blade) * 5.17) * 0.72
        var right: Vector3 = Vector3(cos(facing_angle), 0.0, sin(facing_angle))
        var forward: Vector3 = Vector3(-sin(facing_angle), 0.0, cos(facing_angle))
        var blade_height: float = lerpf(0.56, 1.08, float((blade * 37) % 19) / 18.0)
        var blade_width: float = lerpf(0.075, 0.14, float((blade * 23) % 17) / 16.0)
        var lean: float = lerpf(0.06, 0.18, float((blade * 29) % 13) / 12.0)
        var start: int = vertices.size()
        vertices.append_array(PackedVector3Array([
            base - right * blade_width,
            base + right * blade_width,
            base + Vector3.UP * blade_height * 0.58 + forward * lean * 0.30 - right * blade_width * 0.58,
            base + Vector3.UP * blade_height * 0.58 + forward * lean * 0.30 + right * blade_width * 0.58,
            base + Vector3.UP * blade_height + forward * lean
        ]))
        for _unused: int in range(5):
            normals.append(forward)
        uvs.append_array(PackedVector2Array([
            Vector2(0.0, 0.0),
            Vector2(1.0, 0.0),
            Vector2(0.18, 0.58),
            Vector2(0.82, 0.58),
            Vector2(0.5, 1.0)
        ]))
        indices.append_array(PackedInt32Array([
            start,
            start + 1,
            start + 2,
            start + 1,
            start + 3,
            start + 2,
            start + 2,
            start + 3,
            start + 4
        ]))

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh: ArrayMesh = ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    mesh.surface_set_material(0, _material)
    return mesh

func _sample_noise(noise: FastNoiseLite, position: Vector2) -> float:
    return clampf((noise.get_noise_2d(position.x, position.y) + 1.0) * 0.5, 0.0, 1.0)

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
