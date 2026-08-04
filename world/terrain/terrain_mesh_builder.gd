extends RefCounted # Converts deterministic height samples into renderable seamless terrain meshes.
class_name TerrainMeshBuilder # Makes terrain mesh construction available to the streaming controller.

const LOWLAND_COLOR: Color = Color(0.19, 0.29, 0.13, 1.0) # Represents deep fertile valleys and sheltered low ground.
const GRASS_COLOR: Color = Color(0.28, 0.39, 0.17, 1.0) # Represents ordinary rolling grassland.
const HIGHLAND_COLOR: Color = Color(0.37, 0.34, 0.21, 1.0) # Represents dry elevated slopes and mountain foothills.
const ROCK_COLOR: Color = Color(0.34, 0.35, 0.37, 1.0) # Represents exposed steep rock faces.
const SNOW_COLOR: Color = Color(0.82, 0.84, 0.86, 1.0) # Represents high cold mountain shelves and summits.

var _height_sampler: TerrainHeightSampler # Supplies one continuous deterministic height function for every chunk.
var _terrain_material: StandardMaterial3D # Shades generated vertices using their authored terrain colours.

func _init(height_sampler: TerrainHeightSampler, terrain_material: StandardMaterial3D) -> void: # Captures reusable generation resources shared by every chunk.
    _height_sampler = height_sampler # Stores the authoritative procedural height service.
    _terrain_material = terrain_material # Stores the shared terrain surface material.

func build_chunk_mesh(chunk_coordinate: Vector2i) -> ArrayMesh: # Generates a seamless regular-grid terrain mesh for one world chunk.
    var vertex_spacing: float = TerrainConfiguration.CHUNK_SIZE / float(TerrainConfiguration.CHUNK_RESOLUTION - 1) # Calculates the distance between neighbouring terrain vertices.
    var cache_resolution: int = TerrainConfiguration.CHUNK_RESOLUTION + 2 # Adds a one-sample border around the chunk for seam-consistent normals.
    var height_cache: PackedFloat32Array = PackedFloat32Array() # Stores sampled heights for vertices and their external normal neighbours.
    height_cache.resize(cache_resolution * cache_resolution) # Allocates the complete bordered height grid once.
    var chunk_world_x: float = float(chunk_coordinate.x) * TerrainConfiguration.CHUNK_SIZE # Calculates the chunk's authoritative world-space x origin.
    var chunk_world_z: float = float(chunk_coordinate.y) * TerrainConfiguration.CHUNK_SIZE # Calculates the chunk's authoritative world-space z origin.
    for cache_z: int in range(cache_resolution): # Samples each row of the bordered height cache.
        var world_z: float = chunk_world_z + float(cache_z - 1) * vertex_spacing # Converts the bordered row into continuous world space.
        for cache_x: int in range(cache_resolution): # Samples each column of the bordered height cache.
            var world_x: float = chunk_world_x + float(cache_x - 1) * vertex_spacing # Converts the bordered column into continuous world space.
            var cache_index: int = cache_z * cache_resolution + cache_x # Calculates the packed cache index for this sample.
            height_cache[cache_index] = _height_sampler.sample_height(world_x, world_z) # Samples the shared height function so adjacent chunks match exactly.
    var vertex_count: int = TerrainConfiguration.CHUNK_RESOLUTION * TerrainConfiguration.CHUNK_RESOLUTION # Calculates the number of visible vertices in the unbordered grid.
    var vertices: PackedVector3Array = PackedVector3Array() # Stores local positions for the rendered terrain surface.
    var normals: PackedVector3Array = PackedVector3Array() # Stores smooth seam-consistent terrain normals.
    var colours: PackedColorArray = PackedColorArray() # Stores height and slope-driven terrain colouring per vertex.
    var uvs: PackedVector2Array = PackedVector2Array() # Stores continuous world-space coordinates for future texture materials.
    vertices.resize(vertex_count) # Allocates every vertex position once before indexed assignment.
    normals.resize(vertex_count) # Allocates every vertex normal once before indexed assignment.
    colours.resize(vertex_count) # Allocates every vertex colour once before indexed assignment.
    uvs.resize(vertex_count) # Allocates every terrain texture coordinate once before indexed assignment.
    for vertex_z: int in range(TerrainConfiguration.CHUNK_RESOLUTION): # Builds each visible terrain row from the bordered height cache.
        for vertex_x: int in range(TerrainConfiguration.CHUNK_RESOLUTION): # Builds each visible terrain column from the bordered height cache.
            var vertex_index: int = vertex_z * TerrainConfiguration.CHUNK_RESOLUTION + vertex_x # Calculates the packed visible vertex index.
            var cache_index: int = (vertex_z + 1) * cache_resolution + vertex_x + 1 # Locates the corresponding centre sample inside the bordered cache.
            var height: float = height_cache[cache_index] # Reads the authoritative height for this visible vertex.
            var left_height: float = height_cache[cache_index - 1] # Reads the neighbouring height beyond or inside the chunk's left edge.
            var right_height: float = height_cache[cache_index + 1] # Reads the neighbouring height beyond or inside the chunk's right edge.
            var backward_height: float = height_cache[cache_index - cache_resolution] # Reads the neighbouring height beyond or inside the chunk's back edge.
            var forward_height: float = height_cache[cache_index + cache_resolution] # Reads the neighbouring height beyond or inside the chunk's forward edge.
            var normal: Vector3 = Vector3(left_height - right_height, vertex_spacing * 2.0, backward_height - forward_height).normalized() # Derives a centred normal shared exactly across adjacent chunk boundaries.
            var local_x: float = float(vertex_x) * vertex_spacing # Calculates the vertex's local x position inside the chunk.
            var local_z: float = float(vertex_z) * vertex_spacing # Calculates the vertex's local z position inside the chunk.
            var world_x: float = chunk_world_x + local_x # Reconstructs world x for continuous texture coordinates.
            var world_z: float = chunk_world_z + local_z # Reconstructs world z for continuous texture coordinates.
            vertices[vertex_index] = Vector3(local_x, height, local_z) # Stores the final local terrain position.
            normals[vertex_index] = normal # Stores the centred height-field normal.
            colours[vertex_index] = _get_terrain_colour(height, normal) # Stores terrain colouring based on elevation and exposed slope.
            uvs[vertex_index] = Vector2(world_x, world_z) * TerrainConfiguration.TERRAIN_UV_SCALE # Stores seamless world-space texture coordinates.
    var quad_count: int = (TerrainConfiguration.CHUNK_RESOLUTION - 1) * (TerrainConfiguration.CHUNK_RESOLUTION - 1) # Calculates the number of regular grid quads.
    var indices: PackedInt32Array = PackedInt32Array() # Stores two reversed-winding triangles for every grid quad.
    indices.resize(quad_count * 6) # Allocates the complete terrain index buffer once.
    var write_index: int = 0 # Tracks the next index-buffer position during grid triangulation.
    for quad_z: int in range(TerrainConfiguration.CHUNK_RESOLUTION - 1): # Triangulates each row of terrain quads.
        for quad_x: int in range(TerrainConfiguration.CHUNK_RESOLUTION - 1): # Triangulates each terrain quad in the current row.
            var top_left: int = quad_z * TerrainConfiguration.CHUNK_RESOLUTION + quad_x # Locates the quad's back-left vertex.
            var top_right: int = top_left + 1 # Locates the quad's back-right vertex.
            var bottom_left: int = top_left + TerrainConfiguration.CHUNK_RESOLUTION # Locates the quad's forward-left vertex.
            var bottom_right: int = bottom_left + 1 # Locates the quad's forward-right vertex.
            indices[write_index] = top_left # Starts the first reversed-winding triangle at the back-left corner.
            indices[write_index + 1] = top_right # Continues the first triangle at the back-right corner.
            indices[write_index + 2] = bottom_left # Finishes the first triangle at the forward-left corner.
            indices[write_index + 3] = top_right # Starts the second reversed-winding triangle at the back-right corner.
            indices[write_index + 4] = bottom_right # Continues the second triangle at the forward-right corner.
            indices[write_index + 5] = bottom_left # Finishes the second triangle at the forward-left corner.
            write_index += 6 # Advances to the next quad's six index entries.
    var arrays: Array = [] # Creates the fixed mesh-array container expected by ArrayMesh.
    arrays.resize(Mesh.ARRAY_MAX) # Allocates every possible mesh channel slot.
    arrays[Mesh.ARRAY_VERTEX] = vertices # Assigns generated terrain positions.
    arrays[Mesh.ARRAY_NORMAL] = normals # Assigns generated smooth terrain normals.
    arrays[Mesh.ARRAY_COLOR] = colours # Assigns elevation and slope terrain colours.
    arrays[Mesh.ARRAY_TEX_UV] = uvs # Assigns seamless world-space texture coordinates.
    arrays[Mesh.ARRAY_INDEX] = indices # Assigns the regular-grid triangle index buffer.
    var terrain_mesh: ArrayMesh = ArrayMesh.new() # Creates the renderable mesh resource for this chunk.
    terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays) # Uploads all generated channels as one efficient triangle surface.
    terrain_mesh.surface_set_material(0, _terrain_material) # Shares one terrain material across every chunk surface.
    return terrain_mesh # Returns the completed seamless chunk mesh.

func _get_terrain_colour(height: float, normal: Vector3) -> Color: # Selects and blends a terrain colour from elevation and slope.
    var elevation_colour: Color = LOWLAND_COLOR # Starts low terrain with sheltered valley colouring.
    if height >= 12.0 and height < 72.0: # Detects ordinary hills and low uplands.
        var grass_blend: float = smoothstep(12.0, 72.0, height) # Calculates gradual lowland-to-grass transition weight.
        elevation_colour = LOWLAND_COLOR.lerp(GRASS_COLOR, grass_blend) # Blends fertile valleys into ordinary grassland.
    elif height >= 72.0 and height < 145.0: # Detects exposed foothills and highlands.
        var highland_blend: float = smoothstep(72.0, 145.0, height) # Calculates gradual grass-to-highland transition weight.
        elevation_colour = GRASS_COLOR.lerp(HIGHLAND_COLOR, highland_blend) # Blends grassland into drier high terrain.
    elif height >= 145.0: # Detects upper mountain elevations.
        var snow_blend: float = smoothstep(165.0, 225.0, height) * smoothstep(0.42, 0.82, normal.y) # Favours snow on high surfaces that are not near-vertical.
        elevation_colour = ROCK_COLOR.lerp(SNOW_COLOR, snow_blend) # Blends high exposed rock into summit snow.
    var steepness: float = 1.0 - clampf(normal.y, 0.0, 1.0) # Converts the surface normal into a slope exposure value.
    var rock_blend: float = smoothstep(0.26, 0.62, steepness) # Identifies steep faces where soil and grass should give way to rock.
    return elevation_colour.lerp(ROCK_COLOR, rock_blend) # Returns the final slope-aware terrain colour.
