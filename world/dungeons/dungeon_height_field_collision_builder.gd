extends RefCounted # Builds stable collision from the same paired dungeon height maps without using concave triangles for routine wall contact.
class_name DungeonHeightFieldCollisionBuilder # Exposes ceiling-only mesh collision plus outward primitive wall blockers derived from exact walkable boundary edges.

const CELL_SIZE: float = DungeonHeightFieldMeshBuilder.CELL_SIZE # Reuses the authoritative physical cell spacing shared by height-map rendering, doors, and floor collision.
const WALL_THICKNESS: float = 0.30 # Gives each primitive wall enough blocked-side depth for robust CharacterBody contact without entering playable space.
const WALL_END_OVERLAP: float = 0.08 # Extends wall boxes slightly past cell corners along their tangent so neighbouring blockers cannot leave capsule-sized cracks.
const WALL_VERTICAL_OVERLAP: float = 0.12 # Extends each wall below its lowest floor endpoint and above its highest ceiling endpoint so sloped surface joins remain sealed.
const MINIMUM_WALL_HEIGHT: float = 0.50 # Guarantees a valid positive primitive height even if malformed height samples collapse unexpectedly.

func build_ceiling_collision_mesh(layout: DungeonLayout, height_field: DungeonHeightField) -> ArrayMesh: # Builds only downward-facing ceiling triangles so vertical player contact never touches concave wall triangles.
    if layout == null or height_field == null: # Rejects incomplete geometry dependencies before allocating collision mesh state.
        return ArrayMesh.new() # Returns a valid empty resource instead of propagating null collision data.
    var surface_tool: SurfaceTool = SurfaceTool.new() # Creates an isolated runtime writer used only for overhead static collision.
    surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES) # Emits ordinary triangles suitable for one static concave ceiling shape.
    surface_tool.set_smooth_group(-1) # Keeps the generated ceiling facets explicit while normals remain irrelevant to collision response.
    for floor_index: int in range(layout.get_floor_cell_count()): # Visits every traversable logical cell exactly once.
        var cell: Vector2i = layout.get_floor_cell_at(floor_index) # Retrieves the current walkable topology coordinate without copying the complete cell list.
        _add_ceiling_cell(surface_tool, layout, height_field, cell) # Emits only this cell's downward-facing ceiling quad from authoritative ceiling-map samples.
    surface_tool.generate_normals() # Completes valid committed mesh arrays for the static ceiling collision resource.
    var mesh: ArrayMesh = surface_tool.commit() # Converts the accumulated overhead triangles into one runtime ArrayMesh.
    return mesh if mesh != null else ArrayMesh.new() # Always returns a valid mesh resource so dungeon construction remains defensive.

func add_wall_collision_shapes(collision_body: StaticBody3D, layout: DungeonLayout, height_field: DungeonHeightField) -> void: # Adds primitive boxes only where a walkable cell borders blocked space.
    if collision_body == null or layout == null or height_field == null: # Rejects incomplete collision dependencies before allocating any physics nodes.
        return # Leaves the existing floor and ceiling collision untouched when wall generation cannot be completed safely.
    var wall_index: int = 0 # Produces unique deterministic diagnostic names for every generated primitive wall blocker.
    for floor_index: int in range(layout.get_floor_cell_count()): # Visits every traversable cell once to discover its exposed perimeter edges.
        var cell: Vector2i = layout.get_floor_cell_at(floor_index) # Reads the current logical cell directly from compact layout storage.
        if not layout.is_walkable(cell + Vector2i.UP): # Detects a north edge facing blocked or out-of-bounds space.
            _add_wall_box(collision_body, layout, height_field, cell, Vector2i.UP, wall_index) # Places one box entirely on the blocked north side of the exact visual wall plane.
            wall_index += 1 # Advances the stable diagnostic index after accepting the current boundary edge.
        if not layout.is_walkable(cell + Vector2i.DOWN): # Detects a south edge facing blocked or out-of-bounds space.
            _add_wall_box(collision_body, layout, height_field, cell, Vector2i.DOWN, wall_index) # Places one box entirely on the blocked south side while preserving the full walkable cell interior.
            wall_index += 1 # Advances the diagnostic index after generating the south blocker.
        if not layout.is_walkable(cell + Vector2i.RIGHT): # Detects an east edge facing blocked or out-of-bounds space.
            _add_wall_box(collision_body, layout, height_field, cell, Vector2i.RIGHT, wall_index) # Places one east-side primitive with its playable face exactly on the stitched visual boundary.
            wall_index += 1 # Advances the diagnostic index after generating the east blocker.
        if not layout.is_walkable(cell + Vector2i.LEFT): # Detects a west edge facing blocked or out-of-bounds space.
            _add_wall_box(collision_body, layout, height_field, cell, Vector2i.LEFT, wall_index) # Places one west-side primitive entirely outside the walkable cell.
            wall_index += 1 # Advances the diagnostic index after generating the west blocker.

func _add_wall_box(collision_body: StaticBody3D, layout: DungeonLayout, height_field: DungeonHeightField, cell: Vector2i, direction: Vector2i, wall_index: int) -> void: # Converts one exact exposed height-map edge into a blocked-side BoxShape3D.
    var edge_data: Dictionary[StringName, Variant] = _get_edge_data(layout, height_field, cell, direction) # Resolves wall position, dimensions, and vertical range from the two shared endpoint samples.
    if edge_data.is_empty(): # Detects an unsupported direction or malformed edge calculation defensively.
        return # Skips the invalid primitive rather than creating collision at an arbitrary location.
    var collision_shape: CollisionShape3D = CollisionShape3D.new() # Creates the lightweight physics child consumed directly by the shared dungeon StaticBody3D.
    collision_shape.name = "WallBox_%04d" % wall_index # Gives each primitive a stable compact name for collision-debug inspection.
    collision_shape.position = edge_data[&"position"] as Vector3 # Places the wall box so its playable face aligns with the visible boundary and all thickness extends outward.
    var box_shape: BoxShape3D = BoxShape3D.new() # Uses Godot's optimized convex primitive instead of concave wall triangles.
    box_shape.size = edge_data[&"size"] as Vector3 # Applies the complete edge length, vertical coverage, and outward wall thickness without node scaling.
    collision_shape.shape = box_shape # Assigns the primitive resource to the direct collision child.
    collision_body.add_child(collision_shape) # Installs the finished wall blocker under the existing static dungeon collision owner.

func _get_edge_data(layout: DungeonLayout, height_field: DungeonHeightField, cell: Vector2i, direction: Vector2i) -> Dictionary[StringName, Variant]: # Resolves one exposed edge into a box transform whose thickness lies only inside blocked space.
    var origin_x: float = -float(layout.width) * CELL_SIZE * 0.5 # Calculates the centred local x coordinate of height-map vertex column zero.
    var origin_z: float = -float(layout.height) * CELL_SIZE * 0.5 # Calculates the centred local z coordinate of height-map vertex row zero.
    var floor_a: float = 0.0 # Stores the first floor endpoint height belonging to the selected visual wall edge.
    var floor_b: float = 0.0 # Stores the second floor endpoint height belonging to the selected visual wall edge.
    var ceiling_a: float = 0.0 # Stores the first ceiling endpoint height paired with the selected floor edge.
    var ceiling_b: float = 0.0 # Stores the second ceiling endpoint height paired with the selected floor edge.
    var centre_x: float = 0.0 # Stores the primitive centre x before vertical placement is resolved.
    var centre_z: float = 0.0 # Stores the primitive centre z before vertical placement is resolved.
    var size_x: float = WALL_THICKNESS # Starts with wall-normal thickness and is replaced by edge length for north/south walls.
    var size_z: float = WALL_THICKNESS # Starts with wall-normal thickness and is replaced by edge length for east/west walls.
    if direction == Vector2i.UP: # Handles the north edge whose blocked side is local negative z.
        floor_a = height_field.get_floor_height(cell.x, cell.y) # Reads the western floor sample of the north visual edge.
        floor_b = height_field.get_floor_height(cell.x + 1, cell.y) # Reads the eastern floor sample of the same north edge.
        ceiling_a = height_field.get_ceiling_height(cell.x, cell.y) # Reads the paired western ceiling endpoint.
        ceiling_b = height_field.get_ceiling_height(cell.x + 1, cell.y) # Reads the paired eastern ceiling endpoint.
        centre_x = origin_x + (float(cell.x) + 0.5) * CELL_SIZE # Centres the blocker along the complete north cell edge.
        var boundary_z: float = origin_z + float(cell.y) * CELL_SIZE # Resolves the exact stitched north wall plane used by the visible mesh.
        centre_z = boundary_z - WALL_THICKNESS * 0.5 # Pushes all collision thickness into blocked north space while leaving the walkable side untouched.
        size_x = CELL_SIZE + WALL_END_OVERLAP * 2.0 # Extends tangent coverage slightly beyond both edge corners to seal adjoining wall joins.
    elif direction == Vector2i.DOWN: # Handles the south edge whose blocked side is local positive z.
        floor_a = height_field.get_floor_height(cell.x, cell.y + 1) # Reads the western floor sample of the south visual edge.
        floor_b = height_field.get_floor_height(cell.x + 1, cell.y + 1) # Reads the eastern floor sample of the same south edge.
        ceiling_a = height_field.get_ceiling_height(cell.x, cell.y + 1) # Reads the paired western ceiling endpoint.
        ceiling_b = height_field.get_ceiling_height(cell.x + 1, cell.y + 1) # Reads the paired eastern ceiling endpoint.
        centre_x = origin_x + (float(cell.x) + 0.5) * CELL_SIZE # Centres the blocker along the complete south cell edge.
        var boundary_z: float = origin_z + float(cell.y + 1) * CELL_SIZE # Resolves the exact stitched south wall plane.
        centre_z = boundary_z + WALL_THICKNESS * 0.5 # Pushes the complete primitive into blocked south space without shrinking the traversable cell.
        size_x = CELL_SIZE + WALL_END_OVERLAP * 2.0 # Overlaps tangent ends slightly so corner contacts remain continuous.
    elif direction == Vector2i.RIGHT: # Handles the east edge whose blocked side is local positive x.
        floor_a = height_field.get_floor_height(cell.x + 1, cell.y) # Reads the northern floor sample of the east visual edge.
        floor_b = height_field.get_floor_height(cell.x + 1, cell.y + 1) # Reads the southern floor sample of the same east edge.
        ceiling_a = height_field.get_ceiling_height(cell.x + 1, cell.y) # Reads the paired northern ceiling endpoint.
        ceiling_b = height_field.get_ceiling_height(cell.x + 1, cell.y + 1) # Reads the paired southern ceiling endpoint.
        var boundary_x: float = origin_x + float(cell.x + 1) * CELL_SIZE # Resolves the exact stitched east wall plane.
        centre_x = boundary_x + WALL_THICKNESS * 0.5 # Pushes all collision thickness into blocked east space while preserving the walkable side exactly.
        centre_z = origin_z + (float(cell.y) + 0.5) * CELL_SIZE # Centres the blocker along the complete east edge depth.
        size_z = CELL_SIZE + WALL_END_OVERLAP * 2.0 # Extends tangent coverage slightly beyond both corners to avoid seam catches.
    elif direction == Vector2i.LEFT: # Handles the west edge whose blocked side is local negative x.
        floor_a = height_field.get_floor_height(cell.x, cell.y) # Reads the northern floor sample of the west visual edge.
        floor_b = height_field.get_floor_height(cell.x, cell.y + 1) # Reads the southern floor sample of the same west edge.
        ceiling_a = height_field.get_ceiling_height(cell.x, cell.y) # Reads the paired northern ceiling endpoint.
        ceiling_b = height_field.get_ceiling_height(cell.x, cell.y + 1) # Reads the paired southern ceiling endpoint.
        var boundary_x: float = origin_x + float(cell.x) * CELL_SIZE # Resolves the exact stitched west wall plane.
        centre_x = boundary_x - WALL_THICKNESS * 0.5 # Pushes the complete primitive into blocked west space without entering the cell.
        centre_z = origin_z + (float(cell.y) + 0.5) * CELL_SIZE # Centres the blocker along the complete west edge depth.
        size_z = CELL_SIZE + WALL_END_OVERLAP * 2.0 # Overlaps tangent ends so adjacent primitive walls form one continuous contact boundary.
    else: # Handles any direction not represented by the four orthogonal topology neighbours.
        return {} # Reports an invalid edge rather than inventing collision geometry.
    var lowest_floor: float = minf(floor_a, floor_b) - WALL_VERTICAL_OVERLAP # Extends the primitive slightly below both sloped floor endpoints so no lower seam is exposed.
    var highest_ceiling: float = maxf(ceiling_a, ceiling_b) + WALL_VERTICAL_OVERLAP # Extends the primitive above both ceiling endpoints so the wall/ceiling join remains sealed.
    var wall_height: float = maxf(highest_ceiling - lowest_floor, MINIMUM_WALL_HEIGHT) # Produces a stable positive box height spanning the complete varying wall edge.
    var centre_y: float = lowest_floor + wall_height * 0.5 # Centres the primitive vertically across the resolved floor-to-ceiling coverage.
    return {&"position": Vector3(centre_x, centre_y, centre_z), &"size": Vector3(size_x, wall_height, size_z)} # Returns the complete primitive transform data without allocating a physics node prematurely.

func _add_ceiling_cell(surface_tool: SurfaceTool, layout: DungeonLayout, height_field: DungeonHeightField, cell: Vector2i) -> void: # Emits one downward-facing ceiling quad from the exact authoritative ceiling-map samples.
    var north_west: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x, cell.y) # Resolves the north-west ceiling corner shared with neighbouring cells.
    var north_east: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x + 1, cell.y) # Resolves the north-east shared ceiling corner.
    var south_east: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x + 1, cell.y + 1) # Resolves the south-east shared ceiling corner.
    var south_west: Vector3 = _get_ceiling_vertex(layout, height_field, cell.x, cell.y + 1) # Resolves the south-west shared ceiling corner.
    _add_plain_quad(surface_tool, north_west, north_east, south_east, south_west) # Emits the same inward-facing ceiling geometry as the visible height-field architecture.

func _get_ceiling_vertex(layout: DungeonLayout, height_field: DungeonHeightField, vertex_x: int, vertex_z: int) -> Vector3: # Converts one ceiling-map coordinate into centred dungeon-local physical space.
    var origin_x: float = -float(layout.width) * CELL_SIZE * 0.5 # Resolves the westernmost shared vertex x coordinate.
    var origin_z: float = -float(layout.height) * CELL_SIZE * 0.5 # Resolves the northernmost shared vertex z coordinate.
    var local_x: float = origin_x + float(vertex_x) * CELL_SIZE # Places the requested ceiling sample at its exact horizontal x coordinate.
    var local_z: float = origin_z + float(vertex_z) * CELL_SIZE # Places the requested ceiling sample at its exact horizontal z coordinate.
    return Vector3(local_x, height_field.get_ceiling_height(vertex_x, vertex_z), local_z) # Returns the full overhead position using authoritative ceiling height.

func _add_plain_quad(surface_tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void: # Emits one collision quadrilateral as two consistently wound triangles.
    surface_tool.add_vertex(a) # Adds the first corner of the first ceiling triangle.
    surface_tool.add_vertex(b) # Adds the second corner of the first ceiling triangle.
    surface_tool.add_vertex(c) # Adds the third corner of the first ceiling triangle.
    surface_tool.add_vertex(a) # Reuses the first corner to begin the second triangle across the shared diagonal.
    surface_tool.add_vertex(c) # Reuses the diagonal corner to continue the second triangle.
    surface_tool.add_vertex(d) # Adds the final corner completing the downward-facing ceiling quad.
