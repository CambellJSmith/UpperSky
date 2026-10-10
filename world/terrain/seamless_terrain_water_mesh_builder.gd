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

func build_chunk_arrays(chunk_coordinate: Vector2i, ground_arrays: Array = []) -> Array: # Accepts the final ground buffer to avoid repeated terrain sampling.
    var water_resolution: int = TerrainConfiguration.CHUNK_RESOLUTION # Uses the final ground grid for exact shoreline agreement.
    var cell_count: int = water_resolution - 1
    var vertex_spacing: float = TerrainConfiguration.CHUNK_SIZE / float(cell_count)
    var chunk_world_x: float = float(chunk_coordinate.x) * TerrainConfiguration.CHUNK_SIZE
    var chunk_world_z: float = float(chunk_coordinate.y) * TerrainConfiguration.CHUNK_SIZE
    var boundary_cache: PackedFloat32Array = PackedFloat32Array() # Stores the planned footprint at ground vertices.
    boundary_cache.resize(water_resolution * water_resolution) # Allocates the shared boundary lattice.
    var terrain_height_cache: PackedFloat32Array = PackedFloat32Array()
    terrain_height_cache.resize(water_resolution * water_resolution)
    var ground_vertices: PackedVector3Array = PackedVector3Array() if ground_arrays.is_empty() else ground_arrays[Mesh.ARRAY_VERTEX] # Reuses worker-owned final positions when supplied.
    for vertex_z: int in range(water_resolution):
        var world_z: float = chunk_world_z + float(vertex_z) * vertex_spacing
        for vertex_x: int in range(water_resolution):
            var world_x: float = chunk_world_x + float(vertex_x) * vertex_spacing
            var cache_index: int = vertex_z * water_resolution + vertex_x
            terrain_height_cache[cache_index] = _height_sampler.sample_height(world_x, world_z) if ground_vertices.is_empty() else ground_vertices[cache_index].y # Clips against the supplied final ground without rebuilding it.
            boundary_cache[cache_index] = float(WaterBodyPlan.definition_at(Vector2(world_x, world_z)).boundary) # Samples the same footprint used by gameplay.

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
            if maxf(maxf(boundary_cache[top_left_index], boundary_cache[top_right_index]), maxf(boundary_cache[bottom_left_index], boundary_cache[bottom_right_index])) <= 0.0: # Rejects cells outside explicit water bodies.
                continue # Avoids emitting water merely because terrain is low.
            var plan: Dictionary = WaterBodyPlan.definition_at(Vector2(chunk_world_x + (local_left + local_right) * 0.5, chunk_world_z + (local_back + local_forward) * 0.5)) # Resolves one body and reach for the ground cell.
            var level: float = float(plan.surface_height) # Keeps calm connected water at its planned elevation.
            var water_top_left: Vector3 = Vector3(local_left, level, local_back)
            var water_top_right: Vector3 = Vector3(local_right, level, local_back)
            var water_bottom_left: Vector3 = Vector3(local_left, level, local_forward)
            var water_bottom_right: Vector3 = Vector3(local_right, level, local_forward)
            _append_clipped_seamless_surface_triangle(terrain_top_left, terrain_top_right, terrain_bottom_left, water_top_left, water_top_right, water_bottom_left, PackedFloat32Array([boundary_cache[top_left_index], boundary_cache[top_right_index], boundary_cache[bottom_left_index]]), chunk_world_x, chunk_world_z, vertices, normals, uvs)
            _append_clipped_seamless_surface_triangle(terrain_top_right, terrain_bottom_right, terrain_bottom_left, water_top_right, water_bottom_right, water_bottom_left, PackedFloat32Array([boundary_cache[top_right_index], boundary_cache[bottom_right_index], boundary_cache[bottom_left_index]]), chunk_world_x, chunk_world_z, vertices, normals, uvs)
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

func _append_clipped_seamless_surface_triangle(terrain_a: Vector3, terrain_b: Vector3, terrain_c: Vector3, water_a: Vector3, water_b: Vector3, water_c: Vector3, boundaries: PackedFloat32Array, chunk_world_x: float, chunk_world_z: float, vertices: Array[Vector3], normals: Array[Vector3], uvs: Array[Vector2]) -> void:
    var terrain_points: Array[Vector3] = [terrain_a, terrain_b, terrain_c]
    var water_points: Array[Vector3] = [water_a, water_b, water_c]
    var signed_depths: Array[float] = []
    for point_index: int in range(3):
        signed_depths.append(water_points[point_index].y - terrain_points[point_index].y - SEAMLESS_WATER_CLIP_EPSILON)
    var polygon: Array[Vector3] = [] # Carries the water vertices through both half-space clips.
    var depths: PackedFloat32Array = PackedFloat32Array() # Carries depth through the footprint clip.
    for edge_index: int in range(3): # Clips the explicit planned footprint first.
        var following_index: int = (edge_index + 1) % 3 # Visits the next polygon endpoint.
        var current: float = boundaries[edge_index] # Reads the signed footprint distance.
        var following: float = boundaries[following_index] # Reads the next signed distance.
        if current > 0.0: # Retains vertices inside the body.
            polygon.append(water_points[edge_index]) # Preserves the original surface point.
            depths.append(signed_depths[edge_index]) # Preserves its terrain clearance.
        if (current > 0.0) != (following > 0.0): # Finds an edge crossing the planned boundary.
            var weight: float = current / (current - following) # Locates the linear boundary intersection.
            polygon.append(water_points[edge_index].lerp(water_points[following_index], weight)) # Adds the clipped surface endpoint.
            depths.append(lerpf(signed_depths[edge_index], signed_depths[following_index], weight)) # Interpolates clearance on the same ground triangle.
    var clipped_water_polygon: Array[Vector3] = [] # Collects footprint vertices that also lie above actual ground.
    for edge_index: int in range(polygon.size()): # Clips the intermediate polygon against terrain.
        var following_index: int = (edge_index + 1) % polygon.size() # Visits the next endpoint.
        var current_depth: float = depths[edge_index] # Reads current clearance.
        var following_depth: float = depths[following_index] # Reads next clearance.
        if current_depth > 0.0: # Retains submerged ground locations.
            clipped_water_polygon.append(polygon[edge_index]) # Preserves the visible surface endpoint.
        if (current_depth > 0.0) != (following_depth > 0.0): # Detects the exact ground shoreline.
            var weight: float = current_depth / (current_depth - following_depth) # Solves clearance along the linear triangle edge.
            clipped_water_polygon.append(polygon[edge_index].lerp(polygon[following_index], weight)) # Adds the terrain shoreline endpoint.
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
