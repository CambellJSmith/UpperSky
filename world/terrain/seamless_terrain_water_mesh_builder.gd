extends TerrainWaterMeshBuilder
class_name SeamlessTerrainWaterMeshBuilder

# Horizontal, terrain-clipped water tops. No inclined sheets or vertical tier curtains.

const SEAMLESS_WATER_UV_SCALE: float = 0.0078125
const SEAMLESS_WATER_CLIP_EPSILON: float = 0.02
const SEAMLESS_MINIMUM_TRIANGLE_AREA_SQUARED: float = 0.000001

func _init(height_sampler: TerrainHeightSampler, water_level_sampler: TerrainWaterLevelSampler, water_material: Material) -> void:
    super(height_sampler, water_level_sampler, water_material)

func build_chunk_mesh(chunk_coordinate: Vector2i) -> ArrayMesh:
    return mesh_from_arrays(build_chunk_arrays(chunk_coordinate))

func build_chunk_arrays(chunk_coordinate: Vector2i) -> Array:
    var water_resolution: int = TerrainConfiguration.WATER_RESOLUTION
    var cell_count: int = water_resolution - 1
    var vertex_spacing: float = TerrainConfiguration.CHUNK_SIZE / float(cell_count)
    var chunk_world_x: float = float(chunk_coordinate.x) * TerrainConfiguration.CHUNK_SIZE
    var chunk_world_z: float = float(chunk_coordinate.y) * TerrainConfiguration.CHUNK_SIZE
    var terrain_height_cache: PackedFloat32Array = PackedFloat32Array()
    terrain_height_cache.resize(water_resolution * water_resolution)
    for vertex_z: int in range(water_resolution):
        var world_z: float = chunk_world_z + float(vertex_z) * vertex_spacing
        for vertex_x: int in range(water_resolution):
            var world_x: float = chunk_world_x + float(vertex_x) * vertex_spacing
            var cache_index: int = vertex_z * water_resolution + vertex_x
            terrain_height_cache[cache_index] = _height_sampler.sample_height(world_x, world_z)

    var vertices: Array[Vector3] = []
    var normals: Array[Vector3] = []
    var uvs: Array[Vector2] = []
    for cell_z: int in range(cell_count):
        for cell_x: int in range(cell_count):
            var top_left_index: int = cell_z * water_resolution + cell_x
            var top_right_index: int = top_left_index + 1
            var bottom_left_index: int = top_left_index + water_resolution
            var bottom_right_index: int = bottom_left_index + 1
            var local_left: float = float(cell_x) * vertex_spacing
            var local_right: float = float(cell_x + 1) * vertex_spacing
            var local_back: float = float(cell_z) * vertex_spacing
            var local_forward: float = float(cell_z + 1) * vertex_spacing
            var terrain_top_left: Vector3 = Vector3(local_left, terrain_height_cache[top_left_index], local_back)
            var terrain_top_right: Vector3 = Vector3(local_right, terrain_height_cache[top_right_index], local_back)
            var terrain_bottom_left: Vector3 = Vector3(local_left, terrain_height_cache[bottom_left_index], local_forward)
            var terrain_bottom_right: Vector3 = Vector3(local_right, terrain_height_cache[bottom_right_index], local_forward)
            var level := _water_level_sampler.sample_water_level(chunk_world_x + (local_left + local_right) * 0.5, chunk_world_z + (local_back + local_forward) * 0.5)
            var water_top_left: Vector3 = Vector3(local_left, level, local_back)
            var water_top_right: Vector3 = Vector3(local_right, level, local_back)
            var water_bottom_left: Vector3 = Vector3(local_left, level, local_forward)
            var water_bottom_right: Vector3 = Vector3(local_right, level, local_forward)
            _append_clipped_seamless_surface_triangle(terrain_top_left, terrain_top_right, terrain_bottom_left, water_top_left, water_top_right, water_bottom_left, chunk_world_x, chunk_world_z, vertices, normals, uvs)
            _append_clipped_seamless_surface_triangle(terrain_top_right, terrain_bottom_right, terrain_bottom_left, water_top_right, water_bottom_right, water_bottom_left, chunk_world_x, chunk_world_z, vertices, normals, uvs)
    if vertices.is_empty():
        return []
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices)
    arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(normals)
    arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(uvs)
    return arrays

func mesh_from_arrays(arrays: Array) -> ArrayMesh:
    var water_mesh = ArrayMesh.new()
    if arrays.is_empty(): return water_mesh
    water_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    water_mesh.surface_set_material(0, _water_material)
    return water_mesh

func _append_clipped_seamless_surface_triangle(terrain_a: Vector3, terrain_b: Vector3, terrain_c: Vector3, water_a: Vector3, water_b: Vector3, water_c: Vector3, chunk_world_x: float, chunk_world_z: float, vertices: Array[Vector3], normals: Array[Vector3], uvs: Array[Vector2]) -> void:
    var terrain_points: Array[Vector3] = [terrain_a, terrain_b, terrain_c]
    var water_points: Array[Vector3] = [water_a, water_b, water_c]
    var signed_depths: Array[float] = []
    for point_index: int in range(3):
        signed_depths.append(water_points[point_index].y - terrain_points[point_index].y - SEAMLESS_WATER_CLIP_EPSILON)
    var clipped_water_polygon: Array[Vector3] = []
    for edge_index: int in range(3):
        var following_index: int = (edge_index + 1) % 3
        var current_depth: float = signed_depths[edge_index]
        var following_depth: float = signed_depths[following_index]
        var current_submerged: bool = current_depth > 0.0
        var following_submerged: bool = following_depth > 0.0
        if current_submerged:
            clipped_water_polygon.append(water_points[edge_index])
        if current_submerged != following_submerged:
            var depth_delta: float = current_depth - following_depth
            if is_zero_approx(depth_delta):
                continue
            var intersection_weight: float = clampf(current_depth / depth_delta, 0.0, 1.0)
            var water_intersection: Vector3 = water_points[edge_index].lerp(water_points[following_index], intersection_weight)
            clipped_water_polygon.append(water_intersection)
    if clipped_water_polygon.size() < 3:
        return
    for fan_index: int in range(1, clipped_water_polygon.size() - 1):
        _append_surface_triangle(clipped_water_polygon[0], clipped_water_polygon[fan_index], clipped_water_polygon[fan_index + 1], chunk_world_x, chunk_world_z, vertices, normals, uvs)

func _append_surface_triangle(point_a: Vector3, point_b: Vector3, point_c: Vector3, chunk_world_x: float, chunk_world_z: float, vertices: Array[Vector3], normals: Array[Vector3], uvs: Array[Vector2]) -> void:
    var adjusted_b: Vector3 = point_b
    var adjusted_c: Vector3 = point_c
    var surface_cross: Vector3 = (adjusted_b - point_a).cross(adjusted_c - point_a)
    if surface_cross.length_squared() <= SEAMLESS_MINIMUM_TRIANGLE_AREA_SQUARED:
        return
    if surface_cross.y > 0.0:
        var swap_point: Vector3 = adjusted_b
        adjusted_b = adjusted_c
        adjusted_c = swap_point
        surface_cross = (adjusted_b - point_a).cross(adjusted_c - point_a)
    var surface_normal: Vector3 = Vector3.UP
    vertices.append(point_a)
    vertices.append(adjusted_b)
    vertices.append(adjusted_c)
    normals.append(surface_normal)
    normals.append(surface_normal)
    normals.append(surface_normal)
    uvs.append(Vector2(chunk_world_x + point_a.x, chunk_world_z + point_a.z) * SEAMLESS_WATER_UV_SCALE)
    uvs.append(Vector2(chunk_world_x + adjusted_b.x, chunk_world_z + adjusted_b.z) * SEAMLESS_WATER_UV_SCALE)
    uvs.append(Vector2(chunk_world_x + adjusted_c.x, chunk_world_z + adjusted_c.z) * SEAMLESS_WATER_UV_SCALE)
