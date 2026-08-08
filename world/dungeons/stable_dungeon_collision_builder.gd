extends DungeonGeometryBuilder # Reuses the established logical boundary-wall generation while separating walls from the floor and ceiling collision surfaces.
class_name StableDungeonCollisionBuilder # Produces a walls-only trimesh so grounded player contact can use reliable primitive floor collision instead.

func build_wall_collision_mesh(layout: DungeonLayout) -> ArrayMesh: # Generates only simplified dungeon boundary walls without floor, ceiling, or decorative trim triangles.
    var surface_tool: SurfaceTool = SurfaceTool.new() # Creates an isolated runtime mesh writer for static wall collision only.
    surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES) # Emits the wall faces as triangles suitable for one static ConcavePolygonShape3D.
    surface_tool.set_smooth_group(-1) # Keeps wall topology explicit and consistent with the existing procedural collision generation path.
    for floor_index: int in range(layout.get_floor_cell_count()): # Visits every traversable cell exactly once to discover its exposed blocked-space boundaries.
        var cell: Vector2i = layout.get_floor_cell_at(floor_index) # Retrieves the logical floor coordinate without copying the complete layout.
        _add_boundary_walls(surface_tool, layout, cell, 0, false) # Emits only plain boundary walls while excluding visual trim and all horizontal surfaces.
    surface_tool.generate_normals() # Completes valid mesh data before committing the collision-only wall surface.
    var wall_mesh: ArrayMesh = surface_tool.commit() # Converts accumulated boundary triangles into the resource consumed by static trimesh collision.
    return wall_mesh if wall_mesh != null else ArrayMesh.new() # Always returns a valid mesh resource so dungeon construction can fail safely on malformed layouts.
