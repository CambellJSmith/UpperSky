extends RefCounted # Converts validated logical dungeon cells into runtime-only meshes without authored model or texture assets.
class_name DungeonGeometryBuilder # Exposes procedural visual and collision mesh construction to each generated dungeon world.

const CELL_SIZE: float = 4.0 # Defines the physical width and depth represented by one logical dungeon cell.
const CEILING_HEIGHT: float = 3.8 # Defines a comfortable single-level interior height for rooms and corridors.
const WALL_TRIM_THICKNESS: float = 0.10 # Defines the shallow procedural stone band protrusion used to break up flat walls visually.
const WALL_TRIM_HEIGHT: float = 0.14 # Defines the vertical thickness of each generated wall band.
const WALL_TRIM_BOTTOM_Y: float = 0.46 # Places the lower decorative band above floor level around exposed dungeon walls.
const WALL_TRIM_TOP_Y: float = CEILING_HEIGHT - 0.48 # Places the upper decorative band below the generated ceiling.
const TRIM_PRESENCE_THRESHOLD: float = 0.24 # Leaves a deterministic minority of wall segments plain to avoid perfectly repeated architecture.

const FLOOR_BASE_COLOUR: Color = Color(0.255, 0.245, 0.225, 1.0) # Defines the neutral procedural stone floor family before seeded variation.
const WALL_BASE_COLOUR: Color = Color(0.335, 0.325, 0.295, 1.0) # Defines the slightly lighter stone used on dungeon walls.
const CEILING_BASE_COLOUR: Color = Color(0.205, 0.20, 0.19, 1.0) # Defines the darker overhead stone family used to enclose the dungeon.
const TRIM_BASE_COLOUR: Color = Color(0.285, 0.27, 0.235, 1.0) # Defines contrasting procedural architectural bands around selected wall sections.

static func get_cell_center(layout: DungeonLayout, cell: Vector2i, y: float = 0.0) -> Vector3: # Converts one logical dungeon cell into centred local world coordinates.
    var origin_x: float = -float(layout.width) * CELL_SIZE * 0.5 # Centres the complete generated grid around the dungeon world's local origin on x.
    var origin_z: float = -float(layout.height) * CELL_SIZE * 0.5 # Centres the complete generated grid around the dungeon world's local origin on z.
    var centre_x: float = origin_x + (float(cell.x) + 0.5) * CELL_SIZE # Places the requested coordinate at the horizontal centre of its logical cell.
    var centre_z: float = origin_z + (float(cell.y) + 0.5) * CELL_SIZE # Places the requested coordinate at the depth centre of its logical cell.
    return Vector3(centre_x, y, centre_z) # Returns the physical local-space centre used by doors, lights, and spawn placement.

func build_visual_mesh(layout: DungeonLayout, dungeon_seed: int) -> ArrayMesh: # Generates the complete visible floor, ceiling, walls, and deterministic architectural trim as one runtime mesh.
    var surface_tool: SurfaceTool = SurfaceTool.new() # Creates a transient procedural-geometry writer without scene-tree ownership.
    surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES) # Emits triangle geometry suitable for runtime ArrayMesh rendering.
    surface_tool.set_smooth_group(-1) # Requests flat face normals so generated masonry reads as hard architectural surfaces.
    for floor_index: int in range(layout.get_floor_cell_count()): # Visits every unique traversable cell exactly once.
        var cell: Vector2i = layout.get_floor_cell_at(floor_index) # Retrieves the current logical floor coordinate without allocating a copied floor array.
        _add_floor_and_ceiling(surface_tool, layout, cell, dungeon_seed) # Generates the horizontal surfaces enclosing this cell.
        _add_boundary_walls(surface_tool, layout, cell, dungeon_seed, true) # Generates only walls bordering blocked space plus seeded visual trim.
    surface_tool.generate_normals() # Calculates flat normals after all deterministic triangle positions have been authored.
    var mesh: ArrayMesh = surface_tool.commit() # Commits the accumulated runtime-only vertices into one renderable mesh resource.
    if mesh == null or mesh.get_surface_count() <= 0: # Detects a malformed empty layout that produced no renderable surface.
        return ArrayMesh.new() # Returns a valid empty resource so callers can fail safely without null mesh state.
    mesh.surface_set_material(0, _create_stone_material()) # Applies one vertex-colour-driven procedural material to the combined dungeon surface.
    return mesh # Returns the complete generated visual mesh with no imported model or texture dependency.

func build_collision_mesh(layout: DungeonLayout) -> ArrayMesh: # Generates simplified flat collision surfaces matching the logical dungeon without decorative protrusions.
    var surface_tool: SurfaceTool = SurfaceTool.new() # Creates an isolated writer for collision-only triangles.
    surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES) # Uses triangles because Godot can directly convert the resulting mesh into a concave collision shape.
    surface_tool.set_smooth_group(-1) # Keeps the collision mesh topology explicit even though its normals are not used for rendering.
    for floor_index: int in range(layout.get_floor_cell_count()): # Visits every traversable logical cell once for bounded collision generation.
        var cell: Vector2i = layout.get_floor_cell_at(floor_index) # Retrieves the current physical floor source coordinate.
        _add_floor_and_ceiling(surface_tool, layout, cell, 0) # Generates exact walkable floor and overhead collision using neutral deterministic input.
        _add_boundary_walls(surface_tool, layout, cell, 0, false) # Generates plain boundary walls while excluding all decorative trim geometry.
    surface_tool.generate_normals() # Produces complete triangle data required by the committed ArrayMesh resource.
    var collision_mesh: ArrayMesh = surface_tool.commit() # Converts the simplified geometry into a mesh that can create a trimesh collision shape.
    return collision_mesh if collision_mesh != null else ArrayMesh.new() # Always returns a valid mesh resource to keep dungeon construction defensive.

func _add_floor_and_ceiling(surface_tool: SurfaceTool, layout: DungeonLayout, cell: Vector2i, dungeon_seed: int) -> void: # Emits one cell's floor and ceiling with deterministic per-cell stone variation.
    var centre: Vector3 = get_cell_center(layout, cell) # Resolves the current logical cell into centred dungeon-local coordinates.
    var half_size: float = CELL_SIZE * 0.5 # Calculates the physical half extent used by each square floor and ceiling surface.
    var floor_colour: Color = _vary_colour(FLOOR_BASE_COLOUR, _hash_unit(dungeon_seed, cell, 11), 0.10) # Produces subtle stable floor variation from the dungeon seed and cell coordinate.
    var ceiling_colour: Color = _vary_colour(CEILING_BASE_COLOUR, _hash_unit(dungeon_seed, cell, 17), 0.075) # Produces darker independent overhead variation without textures.
    var floor_a: Vector3 = Vector3(centre.x - half_size, 0.0, centre.z - half_size) # Defines the north-west floor corner.
    var floor_b: Vector3 = Vector3(centre.x - half_size, 0.0, centre.z + half_size) # Defines the south-west floor corner.
    var floor_c: Vector3 = Vector3(centre.x + half_size, 0.0, centre.z + half_size) # Defines the south-east floor corner.
    var floor_d: Vector3 = Vector3(centre.x + half_size, 0.0, centre.z - half_size) # Defines the north-east floor corner.
    _add_quad(surface_tool, floor_a, floor_b, floor_c, floor_d, floor_colour) # Emits upward-facing floor triangles in consistent winding order.
    var ceiling_a: Vector3 = Vector3(centre.x - half_size, CEILING_HEIGHT, centre.z - half_size) # Defines the north-west ceiling corner.
    var ceiling_b: Vector3 = Vector3(centre.x + half_size, CEILING_HEIGHT, centre.z - half_size) # Defines the north-east ceiling corner.
    var ceiling_c: Vector3 = Vector3(centre.x + half_size, CEILING_HEIGHT, centre.z + half_size) # Defines the south-east ceiling corner.
    var ceiling_d: Vector3 = Vector3(centre.x - half_size, CEILING_HEIGHT, centre.z + half_size) # Defines the south-west ceiling corner.
    _add_quad(surface_tool, ceiling_a, ceiling_b, ceiling_c, ceiling_d, ceiling_colour) # Emits downward-facing ceiling triangles that enclose the playable interior.

func _add_boundary_walls(surface_tool: SurfaceTool, layout: DungeonLayout, cell: Vector2i, dungeon_seed: int, include_trim: bool) -> void: # Emits walls only where traversable floor borders blocked logical space.
    var centre: Vector3 = get_cell_center(layout, cell) # Resolves the current logical coordinate into dungeon-local physical space.
    var half_size: float = CELL_SIZE * 0.5 # Calculates the physical cell boundary offset around the centre.
    if not layout.is_walkable(cell + Vector2i.UP): # Detects blocked space immediately north of the current floor cell.
        var wall_colour: Color = _vary_colour(WALL_BASE_COLOUR, _hash_unit(dungeon_seed, cell, 31), 0.09) # Generates stable north-wall colour variation.
        _add_quad(surface_tool, Vector3(centre.x - half_size, 0.0, centre.z - half_size), Vector3(centre.x + half_size, 0.0, centre.z - half_size), Vector3(centre.x + half_size, CEILING_HEIGHT, centre.z - half_size), Vector3(centre.x - half_size, CEILING_HEIGHT, centre.z - half_size), wall_colour) # Builds the inward-facing north boundary wall.
        if include_trim: # Restricts decorative geometry to the visible mesh pass.
            _add_wall_trim(surface_tool, centre, Vector2i.UP, dungeon_seed, cell, 101) # Adds seeded horizontal masonry bands along the north wall.
    if not layout.is_walkable(cell + Vector2i.DOWN): # Detects blocked space immediately south of the current floor cell.
        var wall_colour: Color = _vary_colour(WALL_BASE_COLOUR, _hash_unit(dungeon_seed, cell, 37), 0.09) # Generates stable south-wall colour variation.
        _add_quad(surface_tool, Vector3(centre.x + half_size, 0.0, centre.z + half_size), Vector3(centre.x - half_size, 0.0, centre.z + half_size), Vector3(centre.x - half_size, CEILING_HEIGHT, centre.z + half_size), Vector3(centre.x + half_size, CEILING_HEIGHT, centre.z + half_size), wall_colour) # Builds the inward-facing south boundary wall.
        if include_trim: # Restricts trim to visible geometry rather than collision.
            _add_wall_trim(surface_tool, centre, Vector2i.DOWN, dungeon_seed, cell, 103) # Adds deterministic south-wall detail.
    if not layout.is_walkable(cell + Vector2i.RIGHT): # Detects blocked space immediately east of the current floor cell.
        var wall_colour: Color = _vary_colour(WALL_BASE_COLOUR, _hash_unit(dungeon_seed, cell, 41), 0.09) # Generates stable east-wall colour variation.
        _add_quad(surface_tool, Vector3(centre.x + half_size, 0.0, centre.z - half_size), Vector3(centre.x + half_size, 0.0, centre.z + half_size), Vector3(centre.x + half_size, CEILING_HEIGHT, centre.z + half_size), Vector3(centre.x + half_size, CEILING_HEIGHT, centre.z - half_size), wall_colour) # Builds the inward-facing east boundary wall.
        if include_trim: # Restricts decorative bands to rendering geometry.
            _add_wall_trim(surface_tool, centre, Vector2i.RIGHT, dungeon_seed, cell, 107) # Adds deterministic east-wall detail.
    if not layout.is_walkable(cell + Vector2i.LEFT): # Detects blocked space immediately west of the current floor cell.
        var wall_colour: Color = _vary_colour(WALL_BASE_COLOUR, _hash_unit(dungeon_seed, cell, 43), 0.09) # Generates stable west-wall colour variation.
        _add_quad(surface_tool, Vector3(centre.x - half_size, 0.0, centre.z + half_size), Vector3(centre.x - half_size, 0.0, centre.z - half_size), Vector3(centre.x - half_size, CEILING_HEIGHT, centre.z - half_size), Vector3(centre.x - half_size, CEILING_HEIGHT, centre.z + half_size), wall_colour) # Builds the inward-facing west boundary wall.
        if include_trim: # Restricts decorative bands to visible geometry.
            _add_wall_trim(surface_tool, centre, Vector2i.LEFT, dungeon_seed, cell, 109) # Adds deterministic west-wall detail.

func _add_wall_trim(surface_tool: SurfaceTool, centre: Vector3, direction: Vector2i, dungeon_seed: int, cell: Vector2i, salt: int) -> void: # Adds shallow procedural masonry bands to selected wall sections.
    var presence: float = _hash_unit(dungeon_seed, cell, salt) # Generates a stable wall-local choice without consuming mutable RNG state.
    if presence < TRIM_PRESENCE_THRESHOLD: # Selects a deterministic minority of wall segments to remain visually plain.
        return # Leaves this wall as uninterrupted stone for architectural variation.
    var half_size: float = CELL_SIZE * 0.5 # Calculates the wall boundary offset from the current cell centre.
    var trim_colour: Color = _vary_colour(TRIM_BASE_COLOUR, _hash_unit(dungeon_seed, cell, salt + 13), 0.08) # Gives the trim an independent stable stone tint.
    var lower_centre: Vector3 = centre # Starts the lower band from the current cell's physical centre.
    var upper_centre: Vector3 = centre # Starts the upper band from the same horizontal wall alignment.
    lower_centre.y = WALL_TRIM_BOTTOM_Y # Places the lower band at its authored architectural height.
    upper_centre.y = WALL_TRIM_TOP_Y # Places the upper band immediately below the generated ceiling.
    var size: Vector3 = Vector3(CELL_SIZE, WALL_TRIM_HEIGHT, WALL_TRIM_THICKNESS) # Defaults to a north-south-facing wall strip spanning the complete cell width.
    if direction == Vector2i.UP: # Detects a trim attached to the northern cell boundary.
        lower_centre.z -= half_size - WALL_TRIM_THICKNESS * 0.5 # Moves the lower band just inside the north wall surface.
        upper_centre.z = lower_centre.z # Aligns the upper band with the same north-wall plane.
    elif direction == Vector2i.DOWN: # Detects a trim attached to the southern cell boundary.
        lower_centre.z += half_size - WALL_TRIM_THICKNESS * 0.5 # Moves the lower band just inside the south wall surface.
        upper_centre.z = lower_centre.z # Aligns the upper band to the same south-wall plane.
    elif direction == Vector2i.RIGHT: # Detects a trim attached to the eastern cell boundary.
        size = Vector3(WALL_TRIM_THICKNESS, WALL_TRIM_HEIGHT, CELL_SIZE) # Rotates the band dimensions to span the complete wall depth.
        lower_centre.x += half_size - WALL_TRIM_THICKNESS * 0.5 # Moves the lower band just inside the east wall surface.
        upper_centre.x = lower_centre.x # Aligns the upper band to the same east-wall plane.
    else: # Handles a trim attached to the western cell boundary.
        size = Vector3(WALL_TRIM_THICKNESS, WALL_TRIM_HEIGHT, CELL_SIZE) # Rotates the band dimensions for the west wall.
        lower_centre.x -= half_size - WALL_TRIM_THICKNESS * 0.5 # Moves the lower band just inside the west wall surface.
        upper_centre.x = lower_centre.x # Aligns the upper band to the same west-wall plane.
    _add_box(surface_tool, lower_centre, size, trim_colour) # Emits the complete lower trim prism into the shared visible mesh.
    _add_box(surface_tool, upper_centre, size, trim_colour.darkened(0.06)) # Emits a slightly darker upper band for additional depth variation.

func _add_box(surface_tool: SurfaceTool, centre: Vector3, size: Vector3, colour: Color) -> void: # Emits a closed rectangular prism into the existing procedural triangle surface.
    var half: Vector3 = size * 0.5 # Calculates the local half extents required by all eight box corners.
    var p000: Vector3 = centre + Vector3(-half.x, -half.y, -half.z) # Defines the lower north-west box corner.
    var p001: Vector3 = centre + Vector3(-half.x, -half.y, half.z) # Defines the lower south-west box corner.
    var p010: Vector3 = centre + Vector3(-half.x, half.y, -half.z) # Defines the upper north-west box corner.
    var p011: Vector3 = centre + Vector3(-half.x, half.y, half.z) # Defines the upper south-west box corner.
    var p100: Vector3 = centre + Vector3(half.x, -half.y, -half.z) # Defines the lower north-east box corner.
    var p101: Vector3 = centre + Vector3(half.x, -half.y, half.z) # Defines the lower south-east box corner.
    var p110: Vector3 = centre + Vector3(half.x, half.y, -half.z) # Defines the upper north-east box corner.
    var p111: Vector3 = centre + Vector3(half.x, half.y, half.z) # Defines the upper south-east box corner.
    _add_quad(surface_tool, p001, p101, p111, p011, colour) # Emits the south-facing box face.
    _add_quad(surface_tool, p100, p000, p010, p110, colour) # Emits the north-facing box face.
    _add_quad(surface_tool, p000, p001, p011, p010, colour) # Emits the west-facing box face.
    _add_quad(surface_tool, p101, p100, p110, p111, colour) # Emits the east-facing box face.
    _add_quad(surface_tool, p010, p011, p111, p110, colour) # Emits the upper box face.
    _add_quad(surface_tool, p000, p100, p101, p001, colour.darkened(0.08)) # Emits the lower box face with subtle deterministic shading contrast.

func _add_quad(surface_tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color) -> void: # Emits one coloured quadrilateral as two consistently wound triangles.
    _add_vertex(surface_tool, a, colour) # Adds the first corner of the first triangle with vertex colour metadata.
    _add_vertex(surface_tool, b, colour) # Adds the second corner of the first triangle.
    _add_vertex(surface_tool, c, colour) # Adds the third corner of the first triangle.
    _add_vertex(surface_tool, a, colour) # Reuses the first corner as the first vertex of the second triangle.
    _add_vertex(surface_tool, c, colour) # Reuses the diagonal corner to complete the shared triangle edge.
    _add_vertex(surface_tool, d, colour) # Adds the final quad corner to complete the second triangle.

func _add_vertex(surface_tool: SurfaceTool, vertex: Vector3, colour: Color) -> void: # Adds one coloured vertex using the attribute ordering required by SurfaceTool.
    surface_tool.set_color(colour) # Sets the per-vertex procedural stone tint before submitting the position.
    surface_tool.add_vertex(vertex) # Appends the physical position using the currently assigned colour attribute.

func _create_stone_material() -> StandardMaterial3D: # Creates one textureless material whose appearance is driven entirely by generated vertex data.
    var material: StandardMaterial3D = StandardMaterial3D.new() # Allocates a runtime-only material resource rather than loading an authored asset.
    material.vertex_color_use_as_albedo = true # Uses deterministic vertex colours as the complete base stone colour source.
    material.roughness = 0.93 # Keeps procedural masonry broad and matte under generated dungeon lighting.
    material.metallic = 0.0 # Treats the complete architectural surface as non-metallic stone.
    material.cull_mode = BaseMaterial3D.CULL_DISABLED # Makes generated surfaces robustly visible from either side during procedural edge cases.
    return material # Returns the reusable material assigned to the combined dungeon visual surface.

func _vary_colour(base_colour: Color, unit_value: float, variation: float) -> Color: # Applies restrained deterministic brightness variation around one procedural base colour.
    var signed_variation: float = (unit_value * 2.0 - 1.0) * variation # Converts a stable zero-to-one hash into a centred brightness offset.
    return Color(clampf(base_colour.r + signed_variation, 0.0, 1.0), clampf(base_colour.g + signed_variation, 0.0, 1.0), clampf(base_colour.b + signed_variation, 0.0, 1.0), base_colour.a) # Returns the clamped textureless stone tint.

func _hash_unit(dungeon_seed: int, cell: Vector2i, salt: int) -> float: # Produces a stable pseudo-random scalar from immutable dungeon and cell identity without allocating RNG objects.
    var value: int = dungeon_seed # Starts from the dungeon's deterministic root seed.
    value = value ^ (cell.x * 73_856_093) # Mixes the logical x coordinate using a large pairwise-prime spatial constant.
    value = value ^ (cell.y * 19_349_663) # Mixes the logical z-grid coordinate independently.
    value = value ^ (salt * 83_492_791) # Mixes the requested visual channel so floor, wall, and trim choices remain decorrelated.
    value = value ^ (value >> 13) # Folds high and low bits together before the final bounded conversion.
    value *= 1_274_126_177 # Applies an additional integer avalanche step while remaining deterministic.
    value = value ^ (value >> 16) # Performs the final bit fold used by the stable local visual hash.
    var positive_value: int = absi(value % 10_000) # Restricts the mixed integer to a compact non-negative decimal range.
    return float(positive_value) / 9_999.0 # Converts the stable hash into an inclusive approximately uniform zero-to-one scalar.
