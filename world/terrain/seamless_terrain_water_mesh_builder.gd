extends TerrainWaterMeshBuilder # Reuses the established water-builder contract while replacing flat stepped cells and vertical curtains with one continuous shared-vertex surface.
class_name SeamlessTerrainWaterMeshBuilder # Generates terrain-clipped water whose neighbouring cells and chunks join without exposed vertical water faces.

const SEAMLESS_WATER_UV_SCALE: float = 0.0078125 # Keeps water texture coordinates continuous in stable world space using the established water scale.
const SEAMLESS_WATER_CLIP_EPSILON: float = 0.02 # Matches gameplay shoreline tolerance while preventing numerically marginal water slivers.
const SEAMLESS_MINIMUM_TRIANGLE_AREA_SQUARED: float = 0.000001 # Rejects collapsed shoreline triangles before they reach rendering.

func _init(height_sampler: TerrainHeightSampler, water_level_sampler: TerrainWaterLevelSampler, water_material: StandardMaterial3D) -> void: # Forwards the coordinated terrain, water, and material services into the established builder state.
    super(height_sampler, water_level_sampler, water_material) # Initializes the inherited authoritative service references without duplicating state.

func build_chunk_mesh(chunk_coordinate: Vector2i) -> ArrayMesh: # Generates one continuous terrain-clipped water surface for an absolute world chunk.
    var water_resolution: int = TerrainConfiguration.WATER_RESOLUTION # Reads the shared water grid resolution used by rendering and gameplay interpolation.
    var cell_count: int = water_resolution - 1 # Calculates the number of water cells represented along each chunk axis.
    var vertex_spacing: float = TerrainConfiguration.CHUNK_SIZE / float(cell_count) # Calculates the exact stable-world spacing shared by neighbouring water vertices.
    var chunk_world_x: float = float(chunk_coordinate.x) * TerrainConfiguration.CHUNK_SIZE # Calculates the chunk's absolute stable-world x origin.
    var chunk_world_z: float = float(chunk_coordinate.y) * TerrainConfiguration.CHUNK_SIZE # Calculates the chunk's absolute stable-world z origin.
    var terrain_height_cache: PackedFloat32Array = PackedFloat32Array() # Stores authoritative terrain height at every shared water-grid vertex.
    terrain_height_cache.resize(water_resolution * water_resolution) # Allocates one terrain sample for every water-grid vertex exactly once.
    var water_height_cache: PackedFloat32Array = PackedFloat32Array() # Stores continuous water elevation at every shared water-grid vertex.
    water_height_cache.resize(water_resolution * water_resolution) # Allocates one water sample for every water-grid vertex exactly once.
    for vertex_z: int in range(water_resolution): # Samples every shared water-grid row in stable world coordinates.
        var world_z: float = chunk_world_z + float(vertex_z) * vertex_spacing # Converts the current local row into its absolute stable-world z coordinate.
        for vertex_x: int in range(water_resolution): # Samples every shared water-grid column in the current row.
            var world_x: float = chunk_world_x + float(vertex_x) * vertex_spacing # Converts the current local column into its absolute stable-world x coordinate.
            var cache_index: int = vertex_z * water_resolution + vertex_x # Calculates the packed index shared by terrain and water caches.
            terrain_height_cache[cache_index] = _height_sampler.sample_height(world_x, world_z) # Samples the exact terrain function used by the visible ground mesh.
            water_height_cache[cache_index] = _water_level_sampler.sample_water_level(world_x, world_z) # Samples the continuous water function at the exact shared world vertex.
    var vertices: Array[Vector3] = [] # Collects non-indexed clipped surface vertices for the completed water mesh.
    var normals: Array[Vector3] = [] # Collects geometry-derived upward normals for flat and gradually sloped water surfaces.
    var uvs: Array[Vector2] = [] # Collects continuous stable-world texture coordinates for every water vertex.
    for cell_z: int in range(cell_count): # Builds each water cell row inside the current chunk.
        for cell_x: int in range(cell_count): # Builds each water cell from exactly four shared terrain and water vertices.
            var top_left_index: int = cell_z * water_resolution + cell_x # Locates the back-left shared grid sample.
            var top_right_index: int = top_left_index + 1 # Locates the back-right shared grid sample.
            var bottom_left_index: int = top_left_index + water_resolution # Locates the forward-left shared grid sample.
            var bottom_right_index: int = bottom_left_index + 1 # Locates the forward-right shared grid sample.
            var local_left: float = float(cell_x) * vertex_spacing # Calculates the cell's local left x coordinate.
            var local_right: float = float(cell_x + 1) * vertex_spacing # Calculates the cell's local right x coordinate.
            var local_back: float = float(cell_z) * vertex_spacing # Calculates the cell's local back z coordinate.
            var local_forward: float = float(cell_z + 1) * vertex_spacing # Calculates the cell's local forward z coordinate.
            var terrain_top_left: Vector3 = Vector3(local_left, terrain_height_cache[top_left_index], local_back) # Builds the terrain-space back-left sample used for shoreline clipping.
            var terrain_top_right: Vector3 = Vector3(local_right, terrain_height_cache[top_right_index], local_back) # Builds the terrain-space back-right sample used for shoreline clipping.
            var terrain_bottom_left: Vector3 = Vector3(local_left, terrain_height_cache[bottom_left_index], local_forward) # Builds the terrain-space forward-left sample used for shoreline clipping.
            var terrain_bottom_right: Vector3 = Vector3(local_right, terrain_height_cache[bottom_right_index], local_forward) # Builds the terrain-space forward-right sample used for shoreline clipping.
            var water_top_left: Vector3 = Vector3(local_left, water_height_cache[top_left_index], local_back) # Builds the continuous water surface at the shared back-left grid vertex.
            var water_top_right: Vector3 = Vector3(local_right, water_height_cache[top_right_index], local_back) # Builds the continuous water surface at the shared back-right grid vertex.
            var water_bottom_left: Vector3 = Vector3(local_left, water_height_cache[bottom_left_index], local_forward) # Builds the continuous water surface at the shared forward-left grid vertex.
            var water_bottom_right: Vector3 = Vector3(local_right, water_height_cache[bottom_right_index], local_forward) # Builds the continuous water surface at the shared forward-right grid vertex.
            _append_clipped_surface_triangle(terrain_top_left, terrain_top_right, terrain_bottom_left, water_top_left, water_top_right, water_bottom_left, chunk_world_x, chunk_world_z, vertices, normals, uvs) # Clips the first cell triangle against terrain while retaining the exact shared water surface.
            _append_clipped_surface_triangle(terrain_top_right, terrain_bottom_right, terrain_bottom_left, water_top_right, water_bottom_right, water_bottom_left, chunk_world_x, chunk_world_z, vertices, normals, uvs) # Clips the second cell triangle using the same diagonal as terrain and gameplay interpolation.
    var water_mesh: ArrayMesh = ArrayMesh.new() # Creates a valid empty return mesh even when the complete chunk is dry.
    if vertices.is_empty(): # Detects a chunk with no terrain lying below the continuous water surface.
        return water_mesh # Returns the empty mesh so the terrain chunk can omit its water renderer.
    var arrays: Array = [] # Creates the fixed channel container expected by ArrayMesh surface construction.
    arrays.resize(Mesh.ARRAY_MAX) # Allocates every standard mesh channel slot before assigning populated channels.
    arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices) # Uploads all clipped continuous surface positions.
    arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(normals) # Uploads geometry-derived surface normals matching local water slope.
    arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(uvs) # Uploads stable-world water texture coordinates without chunk seams.
    water_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays) # Creates one surface containing only the continuous top water geometry.
    water_mesh.surface_set_material(0, _water_material) # Applies the established shared transparent water material to the seamless surface.
    return water_mesh # Returns the completed water mesh containing no vertical transition curtains or side faces.

func _append_clipped_surface_triangle(terrain_a: Vector3, terrain_b: Vector3, terrain_c: Vector3, water_a: Vector3, water_b: Vector3, water_c: Vector3, chunk_world_x: float, chunk_world_z: float, vertices: Array[Vector3], normals: Array[Vector3], uvs: Array[Vector2]) -> void: # Clips one sloped water triangle against the corresponding linearly interpolated terrain triangle.
    var terrain_points: Array[Vector3] = [terrain_a, terrain_b, terrain_c] # Stores terrain vertices in the exact triangle order shared by ground rendering.
    var water_points: Array[Vector3] = [water_a, water_b, water_c] # Stores corresponding continuous water vertices in the same horizontal positions.
    var signed_depths: Array[float] = [] # Stores water-minus-terrain clearance after shoreline tolerance at each triangle vertex.
    for point_index: int in range(3): # Calculates the authoritative submerged classification value for every triangle vertex.
        signed_depths.append(water_points[point_index].y - terrain_points[point_index].y - SEAMLESS_WATER_CLIP_EPSILON) # Treats positive clearance as visible water and zero as the exact clipped shoreline boundary.
    var clipped_water_polygon: Array[Vector3] = [] # Collects the continuous water polygon remaining after clipping against the terrain plane.
    for edge_index: int in range(3): # Examines each directed triangle edge once for retained vertices and shoreline intersections.
        var following_index: int = (edge_index + 1) % 3 # Locates the following vertex around the same triangle winding.
        var current_depth: float = signed_depths[edge_index] # Reads current signed water clearance from terrain.
        var following_depth: float = signed_depths[following_index] # Reads following signed water clearance from terrain.
        var current_submerged: bool = current_depth > 0.0 # Detects a current vertex with enough water depth to render visibly.
        var following_submerged: bool = following_depth > 0.0 # Detects whether the following vertex remains on the submerged side of the shoreline.
        if current_submerged: # Retains the continuous water vertex wherever terrain lies meaningfully below it.
            clipped_water_polygon.append(water_points[edge_index]) # Adds the exact sampled water position rather than projecting onto a flat cell level.
        if current_submerged != following_submerged: # Detects an edge crossing the terrain-water boundary inside the triangle.
            var depth_delta: float = current_depth - following_depth # Calculates signed-clearance change along the shared terrain and water edge.
            if is_zero_approx(depth_delta): # Rejects a numerically unusable crossing before dividing by an effectively zero value.
                continue # Leaves the degenerate edge without an unstable shoreline vertex.
            var intersection_weight: float = clampf(current_depth / depth_delta, 0.0, 1.0) # Solves the linearly interpolated position where tolerated water clearance reaches zero.
            var water_intersection: Vector3 = water_points[edge_index].lerp(water_points[following_index], intersection_weight) # Interpolates on the actual continuous water edge so neighbouring triangles share the same shoreline point.
            clipped_water_polygon.append(water_intersection) # Adds the exact continuous shoreline position with no vertical closure geometry.
    if clipped_water_polygon.size() < 3: # Detects a dry or numerically collapsed clipped result.
        return # Omits cells that contain no renderable water surface area.
    for fan_index: int in range(1, clipped_water_polygon.size() - 1): # Triangulates the retained convex shoreline polygon as a stable fan.
        _append_surface_triangle(clipped_water_polygon[0], clipped_water_polygon[fan_index], clipped_water_polygon[fan_index + 1], chunk_world_x, chunk_world_z, vertices, normals, uvs) # Appends one continuous top-surface triangle without any side or curtain geometry.

func _append_surface_triangle(point_a: Vector3, point_b: Vector3, point_c: Vector3, chunk_world_x: float, chunk_world_z: float, vertices: Array[Vector3], normals: Array[Vector3], uvs: Array[Vector2]) -> void: # Appends one valid upward-facing continuous water triangle and its stable-world attributes.
    var adjusted_b: Vector3 = point_b # Copies the second point so winding can be corrected locally without mutating caller data.
    var adjusted_c: Vector3 = point_c # Copies the third point so winding can be corrected locally without mutating caller data.
    var surface_cross: Vector3 = (adjusted_b - point_a).cross(adjusted_c - point_a) # Calculates triangle orientation and twice-area from the current winding.
    if surface_cross.length_squared() <= SEAMLESS_MINIMUM_TRIANGLE_AREA_SQUARED: # Detects a collapsed shoreline triangle before normal normalization.
        return # Omits degenerate geometry that could produce invalid normals or rendering artifacts.
    if surface_cross.y < 0.0: # Detects downward winding relative to the expected water top surface.
        var swap_point: Vector3 = adjusted_b # Temporarily stores the second point while reversing the two trailing vertices.
        adjusted_b = adjusted_c # Moves the original third point into the second position to reverse winding.
        adjusted_c = swap_point # Moves the original second point into the third position to complete the upward winding correction.
        surface_cross = (adjusted_b - point_a).cross(adjusted_c - point_a) # Recalculates the surface normal after the winding correction.
    var surface_normal: Vector3 = surface_cross.normalized() # Converts the valid upward area vector into the smooth local water-plane normal.
    vertices.append(point_a) # Stores the first continuous water vertex.
    vertices.append(adjusted_b) # Stores the winding-corrected second continuous water vertex.
    vertices.append(adjusted_c) # Stores the winding-corrected third continuous water vertex.
    normals.append(surface_normal) # Assigns the local plane normal to the first triangle vertex.
    normals.append(surface_normal) # Assigns the same local plane normal to the second triangle vertex.
    normals.append(surface_normal) # Assigns the same local plane normal to the third triangle vertex.
    uvs.append(Vector2(chunk_world_x + point_a.x, chunk_world_z + point_a.z) * SEAMLESS_WATER_UV_SCALE) # Assigns continuous stable-world coordinates to the first triangle vertex.
    uvs.append(Vector2(chunk_world_x + adjusted_b.x, chunk_world_z + adjusted_b.z) * SEAMLESS_WATER_UV_SCALE) # Assigns continuous stable-world coordinates to the second triangle vertex.
    uvs.append(Vector2(chunk_world_x + adjusted_c.x, chunk_world_z + adjusted_c.z) * SEAMLESS_WATER_UV_SCALE) # Assigns continuous stable-world coordinates to the third triangle vertex.
