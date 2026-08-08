extends RefCounted # Converts the authoritative dungeon floor and ceiling height maps into visible surfaces and stitched perimeter-wall meshes.
class_name DungeonHeightFieldMeshBuilder # Keeps horizontal surfaces and wall geometry derived from the same shared vertex samples so seams cannot drift between systems.

const CELL_SIZE: float = DungeonGeometryBuilder.CELL_SIZE # Reuses the established logical dungeon cell size so topology, doors, and height-map geometry remain spatially compatible.
const FLOOR_BASE_COLOUR: Color = Color(0.275, 0.265, 0.245, 1.0) # Defines the textureless stone family used across the generated floor height map.
const WALL_BASE_COLOUR: Color = Color(0.355, 0.34, 0.305, 1.0) # Defines a slightly lighter vertical stone family so stitched perimeter walls remain readable.
const CEILING_BASE_COLOUR: Color = Color(0.235, 0.225, 0.215, 1.0) # Defines the overhead stone family generated from the independent ceiling height map.
const COLOUR_VARIATION: float = 0.075 # Adds restrained deterministic value variation without introducing image textures or per-brick geometry.

func build_visual_mesh(layout: DungeonLayout, height_field: DungeonHeightField, dungeon_seed: int) -> ArrayMesh: # Builds walkable floor cells, matching ceiling cells, and stitched boundary walls as one runtime triangle mesh.
    if layout == null or height_field == null: # Rejects incomplete geometry dependencies before allocating a procedural mesh writer.
        return ArrayMesh.new() # Returns an empty valid mesh so the caller can fail safely without null resources.
    var surface_tool: SurfaceTool = SurfaceTool.new() # Creates the runtime triangle writer used for every visible height-field surface.
    surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES) # Emits ordinary triangles suitable for a single combined ArrayMesh surface.
    surface_tool.set_smooth_group(-1) # Keeps the deliberately low-poly height-field facets and walls flat-shaded rather than smearing normals across hard boundaries.
    for floor_index: int in range(layout.get_floor_cell_count()): # Visits each unique walkable logical cell once.
        var cell: Vector2i = layout.get_floor_cell_at(floor_index) # Retrieves the current topology cell without allocating a copied walkable collection.
        _add_floor_cell(surface_tool, layout, height_field, cell, dungeon_seed) # Emits this cell's floor quad from the four shared floor-map samples.
        _add_ceiling_cell(surface_tool, layout, height_field, cell, dungeon_seed) # Emits the matching overhead quad from the four shared ceiling-map samples.
        _add_boundary_walls(surface_tool, layout, height_field, cell, dungeon_seed, true) # Stitches exposed floor edges directly to their paired ceiling edges with vertical wall quads.
    surface_tool.generate_normals() # Calculates flat normals after every deterministic triangle position has been authored.
    var mesh: ArrayMesh = surface_tool.commit() # Commits the complete connected height-field architecture into one renderable resource.
    if mesh == null or mesh.get_surface_count() <= 0: # Detects malformed topology that emitted no renderable triangles.
        return ArrayMesh.new() # Returns an empty valid resource rather than propagating null mesh state.
    mesh.surface_set_material(0, _create_stone_material()) # Applies one vertex-colour-driven procedural stone material to the complete generated surface.
    return mesh # Returns the visible floor-map, ceiling-map, and stitched-wall architecture.

func build_wall_and_ceiling_collision_mesh(layout: DungeonLayout, height_field: DungeonHeightField) -> ArrayMesh: # Builds only the ceiling and boundary walls because floor contact uses the dedicated HeightMapShape3D.
    if layout == null or height_field == null: # Rejects missing topology or height data before allocating collision geometry.
        return ArrayMesh.new() # Returns a safe empty collision resource when generation dependencies are incomplete.
    var surface_tool: SurfaceTool = SurfaceTool.new() # Creates an isolated collision-only triangle writer.
    surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES) # Emits triangles suitable for one static concave ceiling/wall collision shell.
    surface_tool.set_smooth_group(-1) # Keeps collision topology explicit while normals remain irrelevant to physics.
    for floor_index: int in range(layout.get_floor_cell_count()): # Visits every traversable cell once to discover its overhead surface and exposed perimeter edges.
        var cell: Vector2i = layout.get_floor_cell_at(floor_index) # Reads the current logical cell directly from compact layout storage.
        _add_ceiling_collision_cell(surface_tool, layout, height_field, cell) # Emits only the downward-facing ceiling triangles above this walkable cell.
        _add_boundary_walls(surface_tool, layout, height_field, cell, 0, false) # Emits only exposed perimeter wall quads without visual colour metadata.
    surface_tool.generate_normals() # Completes valid mesh arrays before committing the static collision shell.
    var mesh: ArrayMesh = surface_tool.commit() # Converts accumulated ceiling and wall triangles into the resource used by ConcavePolygonShape3D creation.
    return mesh if mesh != null else ArrayMesh.new() # Always returns a valid mesh object even when malformed topology emits nothing.

func _add_floor_cell(surface_tool: SurfaceTool, layout: DungeonLayout, height_field: DungeonHeightField, cell: Vector2i, dungeon_seed: int) -> void: # Emits one walkable floor quad using four shared samples from the authoritative floor map.
    var north_west: Vector3 = _get_floor_vertex(layout, height_field, cell.x, cell.y) # Resolves the shared north-west corner of this logical cell.
    var south_west: Vector3 = _get_floor_vertex(layout, height_field, cell.x, cell.y + 1) # Resolves the shared south-west corner reused by the adjacent cell when present.
    var south_east: Vector3 = _get_floor_vertex(layout, height_field, cell.x + 1, cell.y + 1) # Resolves the shared south-east floor-map corner.
    var north_east: Vector3 = _get_floor_vertex(layout, height_field, cell.x + 1, cell.y) # Resolves the shared north-east floor-map corner.
    var colour: Color = _vary_colour(FLOOR_BASE_COLOUR, _hash_unit(dungeon_seed, cell, 17)) # Derives one stable floor tint from immutable dungeon and cell identity.
    _add_coloured_quad(surface_tool, north_west, south_west, south_east, north_east, colour) # Emits upward-facing triangles across the current shared floor-map square.

func _add_ceiling_cell(surface_tool: SurfaceTool, layout: DungeonLayout, height_field: DungeonHeightField, cell: Vector2i, dungeon_seed: int) -> void: # Emits one walkable ceiling quad from the independent shared ceiling height map.
    var north_west: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x, cell.y) # Resolves the north-west overhead sample paired with the floor-map vertex below.
    var north_east: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x + 1, cell.y) # Resolves the north-east overhead sample.
    var south_east: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x + 1, cell.y + 1) # Resolves the south-east overhead sample.
    var south_west: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x, cell.y + 1) # Resolves the south-west overhead sample.
    var colour: Color = _vary_colour(CEILING_BASE_COLOUR, _hash_unit(dungeon_seed, cell, 29)) # Derives a stable ceiling tint independent from floor and wall variation.
    _add_coloured_quad(surface_tool, north_west, north_east, south_east, south_west, colour) # Emits downward-facing ceiling triangles so the visible normal points into traversable space.

func _add_ceiling_collision_cell(surface_tool: SurfaceTool, layout: DungeonLayout, height_field: DungeonHeightField, cell: Vector2i) -> void: # Emits one downward-facing ceiling quad without visual attributes for static interior collision.
    var north_west: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x, cell.y) # Resolves the first shared overhead collision vertex.
    var north_east: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x + 1, cell.y) # Resolves the second shared overhead collision vertex.
    var south_east: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x + 1, cell.y + 1) # Resolves the third shared overhead collision vertex.
    var south_west: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x, cell.y + 1) # Resolves the fourth shared overhead collision vertex.
    _add_plain_quad(surface_tool, north_west, north_east, south_east, south_west) # Emits the ceiling with inward-facing winding for collisions from the playable side below.

func _add_boundary_walls(surface_tool: SurfaceTool, layout: DungeonLayout, height_field: DungeonHeightField, cell: Vector2i, dungeon_seed: int, include_colour: bool) -> void: # Stitches each exposed walkable-cell edge directly between its floor-map and ceiling-map endpoints.
    if not layout.is_walkable(cell + Vector2i.UP): # Detects blocked or out-of-bounds space north of the current traversable cell.
        var floor_west: Vector3 = _get_floor_vertex(layout, height_field, cell.x, cell.y) # Resolves the north wall's western floor endpoint.
        var floor_east: Vector3 = _get_floor_vertex(layout, height_field, cell.x + 1, cell.y) # Resolves the north wall's eastern floor endpoint.
        var ceiling_east: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x + 1, cell.y) # Resolves the matching eastern ceiling endpoint.
        var ceiling_west: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x, cell.y) # Resolves the matching western ceiling endpoint.
        _emit_wall_quad(surface_tool, floor_west, floor_east, ceiling_east, ceiling_west, dungeon_seed, cell, 41, include_colour) # Builds the complete north boundary wall with inward-facing winding.
    if not layout.is_walkable(cell + Vector2i.DOWN): # Detects blocked or out-of-bounds space south of the current traversable cell.
        var floor_east: Vector3 = _get_floor_vertex(layout, height_field, cell.x + 1, cell.y + 1) # Resolves the south wall's eastern floor endpoint.
        var floor_west: Vector3 = _get_floor_vertex(layout, height_field, cell.x, cell.y + 1) # Resolves the south wall's western floor endpoint.
        var ceiling_west: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x, cell.y + 1) # Resolves the matching western ceiling endpoint.
        var ceiling_east: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x + 1, cell.y + 1) # Resolves the matching eastern ceiling endpoint.
        _emit_wall_quad(surface_tool, floor_east, floor_west, ceiling_west, ceiling_east, dungeon_seed, cell, 43, include_colour) # Builds the south boundary wall facing inward toward the current cell.
    if not layout.is_walkable(cell + Vector2i.RIGHT): # Detects blocked or out-of-bounds space east of the current traversable cell.
        var floor_north: Vector3 = _get_floor_vertex(layout, height_field, cell.x + 1, cell.y) # Resolves the east wall's northern floor endpoint.
        var floor_south: Vector3 = _get_floor_vertex(layout, height_field, cell.x + 1, cell.y + 1) # Resolves the east wall's southern floor endpoint.
        var ceiling_south: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x + 1, cell.y + 1) # Resolves the matching southern ceiling endpoint.
        var ceiling_north: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x + 1, cell.y) # Resolves the matching northern ceiling endpoint.
        _emit_wall_quad(surface_tool, floor_north, floor_south, ceiling_south, ceiling_north, dungeon_seed, cell, 47, include_colour) # Builds the east boundary wall facing inward toward negative local x.
    if not layout.is_walkable(cell + Vector2i.LEFT): # Detects blocked or out-of-bounds space west of the current traversable cell.
        var floor_south: Vector3 = _get_floor_vertex(layout, height_field, cell.x, cell.y + 1) # Resolves the west wall's southern floor endpoint.
        var floor_north: Vector3 = _get_floor_vertex(layout, height_field, cell.x, cell.y) # Resolves the west wall's northern floor endpoint.
        var ceiling_north: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x, cell.y) # Resolves the matching northern ceiling endpoint.
        var ceiling_south: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x, cell.y + 1) # Resolves the matching southern ceiling endpoint.
        _emit_wall_quad(surface_tool, floor_south, floor_north, ceiling_north, ceiling_south, dungeon_seed, cell, 53, include_colour) # Builds the west boundary wall facing inward toward positive local x.

func _emit_wall_quad(surface_tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, dungeon_seed: int, cell: Vector2i, salt: int, include_colour: bool) -> void: # Emits one complete perimeter wall either with visual tint metadata or as plain collision triangles.
    if include_colour: # Detects the visible mesh pass that needs deterministic vertex colour attributes.
        var colour: Color = _vary_colour(WALL_BASE_COLOUR, _hash_unit(dungeon_seed, cell, salt)) # Generates a stable wall-local stone variation from dungeon identity and edge channel.
        _add_coloured_quad(surface_tool, a, b, c, d, colour) # Emits the complete wall with the material-driving vertex colour.
        return # Stops after visible wall generation because collision attributes are intentionally separate.
    _add_plain_quad(surface_tool, a, b, c, d) # Emits the same physical wall geometry without unnecessary render metadata for collision.

func _get_floor_vertex(layout: DungeonLayout, height_field: DungeonHeightField, vertex_x: int, vertex_z: int) -> Vector3: # Converts one floor-map grid vertex into centred dungeon-local physical coordinates.
    var origin_x: float = -float(layout.width) * CELL_SIZE * 0.5 # Resolves the local x coordinate of the westernmost shared height-map column.
    var origin_z: float = -float(layout.height) * CELL_SIZE * 0.5 # Resolves the local z coordinate of the northernmost shared height-map row.
    var local_x: float = origin_x + float(vertex_x) * CELL_SIZE # Places the requested shared sample at its exact physical x coordinate.
    var local_z: float = origin_z + float(vertex_z) * CELL_SIZE # Places the requested shared sample at its exact physical z coordinate.
    return Vector3(local_x, height_field.get_floor_height(vertex_x, vertex_z), local_z) # Returns the full floor vertex using the authoritative floor height map.

func _get_ceiling_vertex(layout: DungeonLayout, height_field: DungeonHeightField, vertex_x: int, vertex_z: int) -> Vector3: # Converts one ceiling-map grid vertex into centred dungeon-local physical coordinates.
    var origin_x: float = -float(layout.width) * CELL_SIZE * 0.5 # Resolves the local x coordinate of the westernmost shared overhead column.
    var origin_z: float = -float(layout.height) * CELL_SIZE * 0.5 # Resolves the local z coordinate of the northernmost shared overhead row.
    var local_x: float = origin_x + float(vertex_x) * CELL_SIZE # Places the requested ceiling sample at the same horizontal x coordinate as its paired floor vertex.
    var local_z: float = origin_z + float(vertex_z) * CELL_SIZE # Places the requested ceiling sample at the same horizontal z coordinate as its paired floor vertex.
    return Vector3(local_x, height_field.get_ceiling_height(vertex_x, vertex_z), local_z) # Returns the full overhead vertex using the authoritative ceiling height map.

func _add_coloured_quad(surface_tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color) -> void: # Emits one visible quadrilateral as two triangles carrying the supplied deterministic stone tint.
    _add_coloured_vertex(surface_tool, a, colour) # Adds the first corner of the first visible triangle.
    _add_coloured_vertex(surface_tool, b, colour) # Adds the second corner of the first visible triangle.
    _add_coloured_vertex(surface_tool, c, colour) # Adds the third corner of the first visible triangle.
    _add_coloured_vertex(surface_tool, a, colour) # Reuses the first corner to begin the second triangle across the shared diagonal.
    _add_coloured_vertex(surface_tool, c, colour) # Reuses the diagonal corner to continue the second triangle.
    _add_coloured_vertex(surface_tool, d, colour) # Adds the final corner completing the visible quadrilateral.

func _add_plain_quad(surface_tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void: # Emits one collision quadrilateral as two consistently wound triangles without render attributes.
    surface_tool.add_vertex(a) # Adds the first corner of the first collision triangle.
    surface_tool.add_vertex(b) # Adds the second corner of the first collision triangle.
    surface_tool.add_vertex(c) # Adds the third corner of the first collision triangle.
    surface_tool.add_vertex(a) # Reuses the first corner to begin the second triangle.
    surface_tool.add_vertex(c) # Reuses the diagonal corner shared by both collision triangles.
    surface_tool.add_vertex(d) # Adds the final corner completing the collision quadrilateral.

func _add_coloured_vertex(surface_tool: SurfaceTool, vertex: Vector3, colour: Color) -> void: # Adds one visible vertex using the SurfaceTool attribute ordering required by Godot.
    surface_tool.set_color(colour) # Sets the material-driving tint before the associated vertex is submitted.
    surface_tool.add_vertex(vertex) # Appends the physical height-field position with the currently assigned colour attribute.

func _create_stone_material() -> StandardMaterial3D: # Creates one textureless material shared by floor, ceiling, and stitched wall surfaces.
    var material: StandardMaterial3D = StandardMaterial3D.new() # Allocates the runtime-only surface material without loading an authored texture asset.
    material.vertex_color_use_as_albedo = true # Uses deterministic generated vertex colours as the complete stone albedo source.
    material.roughness = 0.94 # Keeps low-poly dungeon stone broad and matte under procedural lantern and ambient lighting.
    material.metallic = 0.0 # Treats the complete height-field architecture as non-metallic stone.
    material.cull_mode = BaseMaterial3D.CULL_DISABLED # Keeps procedural surfaces visible from either side during edge cases while wall collision remains independently wound inward.
    return material # Returns the complete shared material assigned to the combined visible mesh.

func _vary_colour(base_colour: Color, unit_value: float) -> Color: # Applies a restrained deterministic brightness offset around one procedural stone family.
    var signed_variation: float = (unit_value * 2.0 - 1.0) * COLOUR_VARIATION # Converts a stable zero-to-one hash into a centred value shift.
    return Color(clampf(base_colour.r + signed_variation, 0.0, 1.0), clampf(base_colour.g + signed_variation, 0.0, 1.0), clampf(base_colour.b + signed_variation, 0.0, 1.0), base_colour.a) # Returns the clamped textureless stone tint.

func _hash_unit(dungeon_seed: int, cell: Vector2i, salt: int) -> float: # Produces a stable bounded pseudo-random scalar without relying on signed integer overflow behavior.
    var mixed: int = dungeon_seed % 1_000_003 # Starts from a bounded form of the immutable dungeon seed.
    mixed = (mixed + cell.x * 73_856_093) % 1_000_003 # Mixes logical x while reducing immediately to a safe bounded integer range.
    mixed = (mixed + cell.y * 19_349_663) % 1_000_003 # Mixes logical z independently while retaining bounded arithmetic.
    mixed = (mixed + salt * 83_492_791) % 1_000_003 # Mixes the requested visual channel so floor, ceiling, and wall edges remain decorrelated.
    mixed = absi((mixed * 482_071 + 69_621) % 1_000_003) # Applies one final bounded linear avalanche without approaching signed sixty-four-bit limits.
    return float(mixed) / 1_000_002.0 # Converts the stable bounded integer into an inclusive approximately uniform zero-to-one value.
