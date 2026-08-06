extends RefCounted # Converts deterministic height samples into renderable seamless terrain meshes.
class_name TerrainMeshBuilder # Makes terrain mesh construction available to the streaming controller.

const TERRAIN_SURFACE_SHADER: Shader = preload("res://world/terrain/terrain_surface.gdshader") # Adds procedural sand grain while preserving authored vertex colours.

const DEEP_VALLEY_COLOR: Color = Color(0.12, 0.20, 0.10, 1.0) # Represents the deepest sheltered valley floors and basin bottoms.
const LOWLAND_COLOR: Color = Color(0.19, 0.29, 0.13, 1.0) # Represents fertile low shelves and broad valley corridors.
const GRASS_COLOR: Color = Color(0.28, 0.39, 0.17, 1.0) # Represents ordinary midland shelves and rolling uplands.
const HIGHLAND_COLOR: Color = Color(0.37, 0.34, 0.21, 1.0) # Represents dry upper plateaus and mountain approaches.
const ALPINE_COLOR: Color = Color(0.38, 0.39, 0.36, 1.0) # Represents exposed high shelves below permanent snow.
const ROCK_COLOR: Color = Color(0.29, 0.30, 0.32, 1.0) # Represents steep cliffs and immense mountain walls.
const SNOW_COLOR: Color = Color(0.82, 0.84, 0.86, 1.0) # Represents the highest cold mountain shelves and rounded summits.
const DRY_SAND_COLOR: Color = Color(0.62, 0.51, 0.31, 1.0) # Represents sun-dried beaches and exposed sandy banks.
const WET_SAND_COLOR: Color = Color(0.42, 0.35, 0.23, 1.0) # Represents saturated sand immediately beside and below water.
const SUBMERGED_SAND_COLOR: Color = Color(0.48, 0.44, 0.29, 1.0) # Represents shallow sandy lake, river, and sea beds.
const DEEP_SEDIMENT_COLOR: Color = Color(0.28, 0.29, 0.22, 1.0) # Represents darker compacted sandy sediment in deep water.

const DRY_SAND_FULL_HEIGHT: float = 14.0 # Keeps the beach strongly sandy close to the waterline.
const DRY_SAND_FADE_HEIGHT: float = 54.0 # Blends sand into inland soil across a broad shoreline margin.
const SHALLOW_SAND_DEPTH: float = 90.0 # Keeps shallow underwater shelves visibly sandy.
const DEEP_SEDIMENT_DEPTH: float = 320.0 # Gradually darkens deep submerged sand into compacted sediment.
const SAND_SLOPE_FADE_START: float = 0.16 # Begins reducing deposited sand on noticeably inclined terrain.
const SAND_SLOPE_FADE_END: float = 0.52 # Removes sand from steep faces that should remain exposed rock.

var _height_sampler: TerrainHeightSampler # Supplies one continuous deterministic height function for every chunk.
var _water_level_sampler: TerrainWaterLevelSampler # Supplies the same deterministic local water bands used by rendered water.
var _terrain_material: ShaderMaterial # Shades terrain vertex colours and adds procedural grain only where the alpha channel marks sand.

func _init(height_sampler: TerrainHeightSampler, _unused_terrain_material: StandardMaterial3D) -> void: # Captures generation resources shared by every chunk.
    _height_sampler = height_sampler # Stores the authoritative procedural height service.
    _water_level_sampler = TerrainWaterLevelSampler.new() # Recreates the deterministic water-band service for shoreline classification.
    _terrain_material = ShaderMaterial.new() # Creates one reusable shader material for every generated terrain surface.
    _terrain_material.shader = TERRAIN_SURFACE_SHADER # Uses vertex alpha as the sand mask and world-space UVs for seamless grain.

func build_chunk_mesh(chunk_coordinate: Vector2i) -> ArrayMesh: # Generates a seamless regular-grid terrain mesh for one world chunk.
    var vertex_spacing: float = TerrainConfiguration.CHUNK_SIZE / float(TerrainConfiguration.CHUNK_RESOLUTION - 1) # Calculates the distance between neighbouring terrain vertices.
    var cache_resolution: int = TerrainConfiguration.CHUNK_RESOLUTION + 2 # Adds a one-sample border around the chunk for seam-consistent normals.
    var height_cache: PackedFloat32Array = PackedFloat32Array() # Stores sampled heights for vertices and their external normal neighbours.
    height_cache.resize(cache_resolution * cache_resolution) # Allocates the complete bordered height grid once.
    var water_cell_count: int = TerrainConfiguration.WATER_RESOLUTION - 1 # Matches the rendered water grid used for exact local water levels.
    var water_cell_size: float = TerrainConfiguration.CHUNK_SIZE / float(water_cell_count) # Calculates the world size of one rendered water cell.
    var water_level_cache: Dictionary[Vector2i, float] = {} # Reuses one water-band sample for every terrain vertex inside the same water cell.
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
    var colours: PackedColorArray = PackedColorArray() # Stores base terrain colour in RGB and the procedural sand mask in alpha.
    var uvs: PackedVector2Array = PackedVector2Array() # Stores continuous world-space coordinates for seamless terrain detail.
    vertices.resize(vertex_count) # Allocates every vertex position once before indexed assignment.
    normals.resize(vertex_count) # Allocates every vertex normal once before indexed assignment.
    colours.resize(vertex_count) # Allocates every terrain colour and sand mask once.
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
            var world_x: float = chunk_world_x + local_x # Reconstructs world x for deterministic water and texture sampling.
            var world_z: float = chunk_world_z + local_z # Reconstructs world z for deterministic water and texture sampling.
            var water_cell_coordinate: Vector2i = Vector2i(floori(world_x / water_cell_size), floori(world_z / water_cell_size)) # Selects the exact global rendered water cell containing this vertex.
            var water_level: float = 0.0 # Receives the deterministic flat level assigned to the selected water cell.
            if water_level_cache.has(water_cell_coordinate): # Detects a level already sampled for another terrain vertex in the same cell.
                water_level = water_level_cache[water_cell_coordinate] # Reuses the cached level without repeating procedural noise.
            else: # Handles the first terrain vertex encountered inside one rendered water cell.
                var water_sample_x: float = (float(water_cell_coordinate.x) + 0.5) * water_cell_size # Reconstructs the exact x centre sampled by water mesh generation.
                var water_sample_z: float = (float(water_cell_coordinate.y) + 0.5) * water_cell_size # Reconstructs the exact z centre sampled by water mesh generation.
                water_level = _water_level_sampler.sample_water_level(water_sample_x, water_sample_z) # Reads the same local flat water band used by the visible water polygon.
                water_level_cache[water_cell_coordinate] = water_level # Caches the result for remaining vertices in this water cell.
            vertices[vertex_index] = Vector3(local_x, height, local_z) # Stores the final local terrain position.
            normals[vertex_index] = normal # Stores the centred height-field normal.
            colours[vertex_index] = _get_terrain_colour(height, normal, water_level) # Stores terrain colour plus the slope-aware shoreline sand mask.
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
    arrays[Mesh.ARRAY_COLOR] = colours # Assigns generated terrain colours and sand masks.
    arrays[Mesh.ARRAY_TEX_UV] = uvs # Assigns seamless world-space texture coordinates.
    arrays[Mesh.ARRAY_INDEX] = indices # Assigns the regular-grid triangle index buffer.
    var terrain_mesh: ArrayMesh = ArrayMesh.new() # Creates the renderable mesh resource for this chunk.
    terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays) # Uploads all generated channels as one efficient triangle surface.
    terrain_mesh.surface_set_material(0, _terrain_material) # Shares one procedural terrain material across every chunk.
    return terrain_mesh # Returns the completed seamless chunk mesh.

func _get_terrain_colour(height: float, normal: Vector3, water_level: float) -> Color: # Selects geological colour and a sand mask using elevation, slope, and local water depth.
    var elevation_colour: Color = DEEP_VALLEY_COLOR # Starts the deepest world regions with sheltered dark vegetation.
    if height < 80.0: # Detects deep valleys, basins, and lowland floors.
        var lowland_blend: float = smoothstep(-260.0, 80.0, height) # Calculates the deep-valley-to-lowland transition.
        elevation_colour = DEEP_VALLEY_COLOR.lerp(LOWLAND_COLOR, lowland_blend) # Blends basin bottoms into fertile lowlands.
    elif height < 520.0: # Detects lower and middle elevation shelves.
        var grass_blend: float = smoothstep(80.0, 520.0, height) # Calculates the lowland-to-grass transition.
        elevation_colour = LOWLAND_COLOR.lerp(GRASS_COLOR, grass_blend) # Blends fertile corridors into broad grass shelves.
    elif height < 1250.0: # Detects upper regional tiers and mountain foothills.
        var highland_blend: float = smoothstep(520.0, 1250.0, height) # Calculates the grass-to-highland transition.
        elevation_colour = GRASS_COLOR.lerp(HIGHLAND_COLOR, highland_blend) # Blends green shelves into dry high plateaus.
    elif height < 2300.0: # Detects alpine shelves and the lower faces of immense ranges.
        var alpine_blend: float = smoothstep(1250.0, 2300.0, height) # Calculates the highland-to-alpine transition.
        elevation_colour = HIGHLAND_COLOR.lerp(ALPINE_COLOR, alpine_blend) # Blends high plateaus into exposed alpine terrain.
    else: # Detects the upper faces and summits of the largest mountain systems.
        var snow_blend: float = smoothstep(2850.0, 4700.0, height) * smoothstep(0.34, 0.80, normal.y) # Favours snow on extremely high surfaces that are not near-vertical.
        elevation_colour = ROCK_COLOR.lerp(SNOW_COLOR, snow_blend) # Blends immense exposed rock into summit snow.

    var steepness: float = 1.0 - clampf(normal.y, 0.0, 1.0) # Converts the surface normal into a slope exposure value.
    var rock_blend: float = smoothstep(0.20, 0.58, steepness) # Identifies dramatic walls and cliffs where vegetation should give way to rock.
    var terrain_colour: Color = elevation_colour.lerp(ROCK_COLOR, rock_blend) # Resolves the ordinary slope-aware terrain colour before shoreline deposition.

    var height_above_water: float = height - water_level # Measures signed vertical distance from the local water surface.
    var sand_colour: Color = DRY_SAND_COLOR # Starts shoreline deposition with the exposed dry-sand colour.
    var sand_weight: float = 0.0 # Defaults inland and unsupported terrain to no sand texture.
    if height_above_water <= 0.0: # Detects terrain beneath the local water band.
        var water_depth: float = -height_above_water # Converts submerged height into a positive depth.
        var shallow_depth_blend: float = smoothstep(0.0, SHALLOW_SAND_DEPTH, water_depth) # Transitions wet edge sand into ordinary submerged sand.
        var deep_depth_blend: float = smoothstep(SHALLOW_SAND_DEPTH, DEEP_SEDIMENT_DEPTH, water_depth) # Darkens deep sandy beds into compacted sediment.
        sand_colour = WET_SAND_COLOR.lerp(SUBMERGED_SAND_COLOR, shallow_depth_blend).lerp(DEEP_SEDIMENT_COLOR, deep_depth_blend) # Resolves depth-aware seabed colour.
        sand_weight = 1.0 # Treats all sufficiently level underwater terrain as deposited sand or sandy sediment.
    else: # Handles dry terrain above the local waterline.
        var wet_to_dry_blend: float = smoothstep(0.0, DRY_SAND_FULL_HEIGHT, height_above_water) # Changes saturated edge sand into dry beach sand.
        sand_colour = WET_SAND_COLOR.lerp(DRY_SAND_COLOR, wet_to_dry_blend) # Resolves the exposed shoreline colour.
        sand_weight = 1.0 - smoothstep(DRY_SAND_FULL_HEIGHT, DRY_SAND_FADE_HEIGHT, height_above_water) # Fades beaches and banks naturally into inland ground.

    var deposition_weight: float = 1.0 - smoothstep(SAND_SLOPE_FADE_START, SAND_SLOPE_FADE_END, steepness) # Prevents loose sand from coating steep cliffs.
    sand_weight *= deposition_weight * (1.0 - rock_blend * 0.90) # Preserves rocky shores and underwater escarpments while covering gentle ground.
    var final_colour: Color = terrain_colour.lerp(sand_colour, sand_weight) # Blends sandy deposition over the underlying geology.
    return Color(final_colour.r, final_colour.g, final_colour.b, sand_weight) # Stores the shader sand mask in alpha without making terrain transparent.
