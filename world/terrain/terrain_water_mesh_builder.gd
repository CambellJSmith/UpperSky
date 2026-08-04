extends RefCounted # Converts terrain samples and local tier levels into clipped non-overlapping water meshes.
class_name TerrainWaterMeshBuilder # Makes water-surface construction available to the infinite terrain controller.

const WATER_UV_SCALE: float = 0.0078125 # Produces stable world-space coordinates for future animated water materials.
const WATER_CLIP_EPSILON: float = 0.02 # Keeps shoreline classification stable when terrain sits numerically on a water level.
const WATER_LEVEL_EPSILON: float = 0.01 # Treats nearly identical neighbouring water bands as one continuous surface.
const MINIMUM_TRIANGLE_AREA_SQUARED: float = 0.000001 # Prevents numerically collapsed shoreline and curtain triangles from entering the mesh.

var _height_sampler: TerrainHeightSampler # Supplies the authoritative terrain surface used for exact shoreline clipping.
var _water_level_sampler: TerrainWaterLevelSampler # Supplies one of the world's flat local water bands at every horizontal position.
var _water_material: StandardMaterial3D # Shades all generated water surfaces and level-transition curtains.

func _init(height_sampler: TerrainHeightSampler, water_level_sampler: TerrainWaterLevelSampler, water_material: StandardMaterial3D) -> void: # Captures the reusable generation services shared by every water chunk.
    _height_sampler = height_sampler # Stores the authoritative terrain-height service.
    _water_level_sampler = water_level_sampler # Stores the deterministic local water-level service.
    _water_material = water_material # Stores the shared transparent water material.

func build_chunk_mesh(chunk_coordinate: Vector2i) -> ArrayMesh: # Generates clipped water surfaces and sealed transitions for one terrain chunk.
    var water_resolution: int = TerrainConfiguration.WATER_RESOLUTION # Reads the deliberately lower water-grid resolution used for bounded generation cost.
    var cell_count: int = water_resolution - 1 # Calculates the number of water cells along one chunk axis.
    var vertex_spacing: float = TerrainConfiguration.CHUNK_SIZE / float(cell_count) # Calculates the world distance represented by one water cell.
    var chunk_world_x: float = float(chunk_coordinate.x) * TerrainConfiguration.CHUNK_SIZE # Calculates the chunk's absolute x origin.
    var chunk_world_z: float = float(chunk_coordinate.y) * TerrainConfiguration.CHUNK_SIZE # Calculates the chunk's absolute z origin.
    var height_cache: PackedFloat32Array = PackedFloat32Array() # Stores terrain heights at every water-grid corner.
    height_cache.resize(water_resolution * water_resolution) # Allocates the complete corner grid once.
    for vertex_z: int in range(water_resolution): # Samples each water-grid row.
        var world_z: float = chunk_world_z + float(vertex_z) * vertex_spacing # Converts the local row into absolute world z.
        for vertex_x: int in range(water_resolution): # Samples every water-grid corner in the current row.
            var world_x: float = chunk_world_x + float(vertex_x) * vertex_spacing # Converts the local column into absolute world x.
            var cache_index: int = vertex_z * water_resolution + vertex_x # Calculates the packed corner index.
            height_cache[cache_index] = _height_sampler.sample_height(world_x, world_z) # Samples the exact terrain function used by the rendered ground.
    var level_cache: PackedFloat32Array = PackedFloat32Array() # Stores one flat water level per cell plus east and south neighbour cells.
    level_cache.resize(water_resolution * water_resolution) # Allocates one extra neighbour centre along both positive chunk edges.
    for level_z: int in range(water_resolution): # Samples cell-centre levels through the positive neighbour row.
        var level_world_z: float = chunk_world_z + (float(level_z) + 0.5) * vertex_spacing # Converts the cell row into an absolute centre position.
        for level_x: int in range(water_resolution): # Samples cell-centre levels through the positive neighbour column.
            var level_world_x: float = chunk_world_x + (float(level_x) + 0.5) * vertex_spacing # Converts the cell column into an absolute centre position.
            var level_index: int = level_z * water_resolution + level_x # Calculates the packed water-level index.
            level_cache[level_index] = _water_level_sampler.sample_water_level(level_world_x, level_world_z) # Selects the local flat elevation band deterministically.
    var vertices: Array[Vector3] = [] # Collects non-indexed water vertices after terrain clipping.
    var normals: Array[Vector3] = [] # Collects upward surface normals and horizontal transition normals.
    var uvs: Array[Vector2] = [] # Collects continuous world-space water coordinates.
    for cell_z: int in range(cell_count): # Builds every water cell row inside this chunk.
        for cell_x: int in range(cell_count): # Builds each water cell in the current row.
            var top_left_index: int = cell_z * water_resolution + cell_x # Locates the terrain height at the cell's back-left corner.
            var top_right_index: int = top_left_index + 1 # Locates the back-right corner height.
            var bottom_left_index: int = top_left_index + water_resolution # Locates the forward-left corner height.
            var bottom_right_index: int = bottom_left_index + 1 # Locates the forward-right corner height.
            var local_left: float = float(cell_x) * vertex_spacing # Calculates the cell's local left edge.
            var local_right: float = float(cell_x + 1) * vertex_spacing # Calculates the cell's local right edge.
            var local_back: float = float(cell_z) * vertex_spacing # Calculates the cell's local back edge.
            var local_forward: float = float(cell_z + 1) * vertex_spacing # Calculates the cell's local forward edge.
            var top_left: Vector3 = Vector3(local_left, height_cache[top_left_index], local_back) # Builds the terrain-space back-left corner.
            var top_right: Vector3 = Vector3(local_right, height_cache[top_right_index], local_back) # Builds the terrain-space back-right corner.
            var bottom_left: Vector3 = Vector3(local_left, height_cache[bottom_left_index], local_forward) # Builds the terrain-space forward-left corner.
            var bottom_right: Vector3 = Vector3(local_right, height_cache[bottom_right_index], local_forward) # Builds the terrain-space forward-right corner.
            var level_index: int = cell_z * water_resolution + cell_x # Locates this cell's flat local water band.
            var water_level: float = level_cache[level_index] # Reads the selected water elevation for both terrain triangles in the cell.
            _append_clipped_surface_triangle(top_left, top_right, bottom_left, water_level, chunk_world_x, chunk_world_z, vertices, normals, uvs) # Clips the first triangle against the terrain so its shoreline terminates exactly on land.
            _append_clipped_surface_triangle(top_right, bottom_right, bottom_left, water_level, chunk_world_x, chunk_world_z, vertices, normals, uvs) # Clips the second triangle using the terrain's corrected diagonal and winding.
            var east_level: float = level_cache[level_index + 1] # Reads the neighbouring cell level across the positive x edge, including the next chunk when required.
            if absf(water_level - east_level) > WATER_LEVEL_EPSILON: # Detects a genuine step between local water bands.
                var east_normal: Vector3 = Vector3.RIGHT if water_level > east_level else Vector3.LEFT # Points the transition normal from the higher water body toward the lower one.
                _append_level_transition(Vector3(local_right, height_cache[top_right_index], local_back), Vector3(local_right, height_cache[bottom_right_index], local_forward), water_level, east_level, east_normal, chunk_world_x, chunk_world_z, vertices, normals, uvs) # Clips and seals the east-facing plane edge against both terrain and the lower water level.
            var south_level: float = level_cache[level_index + water_resolution] # Reads the neighbouring cell level across the positive z edge, including the next chunk when required.
            if absf(water_level - south_level) > WATER_LEVEL_EPSILON: # Detects a genuine step between north and south water bands.
                var south_normal: Vector3 = Vector3.BACK if water_level > south_level else Vector3.FORWARD # Points the transition normal from the higher water body toward the lower one.
                _append_level_transition(Vector3(local_left, height_cache[bottom_left_index], local_forward), Vector3(local_right, height_cache[bottom_right_index], local_forward), water_level, south_level, south_normal, chunk_world_x, chunk_world_z, vertices, normals, uvs) # Clips and seals the south-facing plane edge against both terrain and the lower water level.
    var water_mesh: ArrayMesh = ArrayMesh.new() # Creates the return mesh even when this chunk contains no submerged terrain.
    if vertices.is_empty(): # Detects a completely dry chunk before allocating an empty render surface.
        return water_mesh # Returns an empty mesh that the chunk node will omit from rendering.
    var arrays: Array = [] # Creates the fixed mesh-channel container expected by ArrayMesh.
    arrays.resize(Mesh.ARRAY_MAX) # Allocates every possible mesh channel slot.
    arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices) # Assigns all clipped surface and transition positions.
    arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(normals) # Assigns stable lighting normals for horizontal and vertical water geometry.
    arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(uvs) # Assigns continuous world-space water coordinates.
    water_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays) # Uploads the complete non-overlapping water geometry as one surface.
    water_mesh.surface_set_material(0, _water_material) # Shares one transparent material across every water chunk.
    return water_mesh # Returns the completed clipped water mesh.

func _append_clipped_surface_triangle(terrain_a: Vector3, terrain_b: Vector3, terrain_c: Vector3, water_level: float, chunk_world_x: float, chunk_world_z: float, vertices: Array[Vector3], normals: Array[Vector3], uvs: Array[Vector2]) -> void: # Clips one horizontal water triangle to the portion lying above submerged terrain.
    var terrain_polygon: Array[Vector3] = [terrain_a, terrain_b, terrain_c] # Starts with the terrain triangle in the same winding used by the ground mesh.
    var water_polygon: Array[Vector3] = [] # Collects the submerged polygon after edge intersection.
    for edge_index: int in range(terrain_polygon.size()): # Examines every directed triangle edge once.
        var current: Vector3 = terrain_polygon[edge_index] # Reads the current terrain vertex.
        var following: Vector3 = terrain_polygon[(edge_index + 1) % terrain_polygon.size()] # Reads the next terrain vertex around the triangle.
        var current_submerged: bool = current.y < water_level - WATER_CLIP_EPSILON # Determines whether the current corner lies meaningfully beneath the water surface.
        var following_submerged: bool = following.y < water_level - WATER_CLIP_EPSILON # Determines whether the following corner lies meaningfully beneath the surface.
        if current_submerged: # Retains every terrain corner that is covered by water.
            water_polygon.append(Vector3(current.x, water_level, current.z)) # Projects the retained horizontal position onto the cell's flat water level.
        if current_submerged != following_submerged: # Detects a terrain edge crossing the shoreline elevation.
            var height_delta: float = following.y - current.y # Calculates the vertical change along the terrain edge.
            if not is_zero_approx(height_delta): # Avoids division when a numerically flat edge straddles only because of tolerance.
                var intersection_weight: float = clampf((water_level - current.y) / height_delta, 0.0, 1.0) # Finds the exact terrain-plane intersection along the edge.
                var intersection: Vector3 = current.lerp(following, intersection_weight) # Interpolates the horizontal shoreline position on the terrain triangle.
                water_polygon.append(Vector3(intersection.x, water_level, intersection.z)) # Adds the exact flat-water shoreline vertex.
    if water_polygon.size() < 3: # Detects triangles containing no renderable submerged area.
        return # Omits dry or numerically degenerate water polygons.
    for fan_index: int in range(1, water_polygon.size() - 1): # Triangulates the clipped polygon as a stable fan.
        _append_triangle(water_polygon[0], water_polygon[fan_index], water_polygon[fan_index + 1], Vector3.UP, chunk_world_x, chunk_world_z, vertices, normals, uvs) # Appends one horizontal water triangle without overlapping neighbouring cell interiors.

func _append_level_transition(edge_start: Vector3, edge_end: Vector3, first_level: float, second_level: float, normal: Vector3, chunk_world_x: float, chunk_world_z: float, vertices: Array[Vector3], normals: Array[Vector3], uvs: Array[Vector2]) -> void: # Clips a vertical curtain so no higher water plane edge is exposed beside a lower level or shoreline.
    var lower_level: float = minf(first_level, second_level) # Finds the bottom water elevation available on either side of the boundary.
    var upper_level: float = maxf(first_level, second_level) # Finds the higher water surface whose horizontal edge must be sealed.
    var start_under_upper: bool = edge_start.y < upper_level - WATER_CLIP_EPSILON # Determines whether the first boundary endpoint lies beneath the higher surface.
    var end_under_upper: bool = edge_end.y < upper_level - WATER_CLIP_EPSILON # Determines whether the second boundary endpoint lies beneath the higher surface.
    if not start_under_upper and not end_under_upper: # Detects a boundary completely blocked by terrain above the higher water level.
        return # Leaves the boundary dry because no water plane reaches it.
    var clipped_start: Vector3 = edge_start # Starts with the complete first terrain endpoint.
    var clipped_end: Vector3 = edge_end # Starts with the complete second terrain endpoint.
    if start_under_upper != end_under_upper: # Detects a boundary that crosses the higher shoreline partway along its length.
        var edge_height_delta: float = edge_end.y - edge_start.y # Calculates the vertical terrain change along the shared cell boundary.
        if is_zero_approx(edge_height_delta): # Detects an unusable numerically flat crossing.
            return # Omits the degenerate curtain rather than exposing unstable geometry.
        var shoreline_weight: float = clampf((upper_level - edge_start.y) / edge_height_delta, 0.0, 1.0) # Finds the exact point where terrain reaches the upper water level.
        var shoreline_point: Vector3 = edge_start.lerp(edge_end, shoreline_weight) # Interpolates the shared boundary position at the higher shoreline.
        if start_under_upper: # Detects whether the submerged segment begins at the first endpoint.
            clipped_end = shoreline_point # Truncates the curtain where terrain rises into the upper water surface.
        else: # Handles the opposite boundary orientation.
            clipped_start = shoreline_point # Starts the curtain where terrain drops beneath the upper water surface.
    var upper_start: Vector3 = Vector3(clipped_start.x, upper_level, clipped_start.z) # Builds the first vertex on the exposed upper plane edge.
    var upper_end: Vector3 = Vector3(clipped_end.x, upper_level, clipped_end.z) # Builds the second vertex on the exposed upper plane edge.
    var lower_start_height: float = maxf(lower_level, clipped_start.y) # Uses the lower water surface where present and terrain where the lower side is dry.
    var lower_end_height: float = maxf(lower_level, clipped_end.y) # Clips the second curtain bottom against either lower water or terrain.
    var lower_start: Vector3 = Vector3(clipped_start.x, lower_start_height, clipped_start.z) # Builds the first clipped bottom vertex.
    var lower_end: Vector3 = Vector3(clipped_end.x, lower_end_height, clipped_end.z) # Builds the second clipped bottom vertex.
    _append_triangle(upper_start, upper_end, lower_start, normal, chunk_world_x, chunk_world_z, vertices, normals, uvs) # Adds the first terrain-clipped half of the vertical transition.
    _append_triangle(upper_end, lower_end, lower_start, normal, chunk_world_x, chunk_world_z, vertices, normals, uvs) # Adds the second half so no partial upper plane lip remains visible.

func _append_triangle(point_a: Vector3, point_b: Vector3, point_c: Vector3, normal: Vector3, chunk_world_x: float, chunk_world_z: float, vertices: Array[Vector3], normals: Array[Vector3], uvs: Array[Vector2]) -> void: # Appends one non-indexed water triangle and its shared attributes.
    var triangle_cross: Vector3 = (point_b - point_a).cross(point_c - point_a) # Measures triangle area before adding potentially collapsed clipping output.
    if triangle_cross.length_squared() <= MINIMUM_TRIANGLE_AREA_SQUARED: # Detects degenerate shoreline or curtain triangles.
        return # Omits zero-area geometry that could create rendering artifacts.
    vertices.append(point_a) # Stores the first triangle position.
    vertices.append(point_b) # Stores the second triangle position.
    vertices.append(point_c) # Stores the third triangle position.
    normals.append(normal) # Assigns the first vertex normal.
    normals.append(normal) # Assigns the second vertex normal.
    normals.append(normal) # Assigns the third vertex normal.
    uvs.append(Vector2(chunk_world_x + point_a.x, chunk_world_z + point_a.z) * WATER_UV_SCALE) # Assigns the first continuous world-space coordinate.
    uvs.append(Vector2(chunk_world_x + point_b.x, chunk_world_z + point_b.z) * WATER_UV_SCALE) # Assigns the second continuous world-space coordinate.
    uvs.append(Vector2(chunk_world_x + point_c.x, chunk_world_z + point_c.z) * WATER_UV_SCALE) # Assigns the third continuous world-space coordinate.
