extends ReadableProceduralDungeonWorld # Retains paired height-map rendering, floor collision, exact door grounding, and brighter lighting while replacing concave wall contact.
class_name StableWallProceduralDungeonWorld # Provides primitive blocked-side wall collision so the player capsule slides cleanly along dungeon boundaries.

func _build_geometry() -> void: # Rebuilds the same authoritative height-field architecture while separating floor, wall, and ceiling physics by contact type.
    _height_field = DungeonHeightField.new() # Allocates the paired floor and ceiling height maps used by every visible and physical interior surface.
    _height_field.generate(_layout, _dungeon_seed) # Reconstructs deterministic surface elevations from the immutable dungeon seed and logical topology.
    var mesh_builder: DungeonHeightFieldMeshBuilder = DungeonHeightFieldMeshBuilder.new() # Creates the existing renderer that stitches floor, ceiling, and visible wall mesh from shared samples.
    var visual_mesh: ArrayMesh = mesh_builder.build_visual_mesh(_layout, _height_field, _dungeon_seed) # Generates the unchanged visible height-field dungeon architecture.
    var mesh_instance: MeshInstance3D = MeshInstance3D.new() # Creates one render node for the complete procedural interior mesh.
    mesh_instance.name = "GeneratedArchitecture" # Preserves the established diagnostic name used for remote scene-tree inspection.
    mesh_instance.mesh = visual_mesh # Installs the deterministic visible floor, ceiling, and stitched wall geometry.
    add_child(mesh_instance) # Adds the complete visual architecture beneath this disposable dungeon world root.
    var collision_body: StaticBody3D = StaticBody3D.new() # Creates one static physics owner shared by the floor height map, primitive walls, and ceiling-only mesh.
    collision_body.name = "GeneratedCollision" # Preserves the existing collision owner name for debugging and profiling.
    collision_body.collision_layer = WORLD_COLLISION_LAYER # Places all generated interior blockers on the same solid world layer used by player movement.
    collision_body.collision_mask = WORLD_COLLISION_LAYER # Retains ordinary static-world interaction semantics for future dungeon actors.
    add_child(collision_body) # Installs the physics owner before attaching any direct CollisionShape3D children.
    _add_floor_heightmap_collision(collision_body) # Keeps routine grounded contact on the dedicated HeightMapShape3D generated from the authoritative floor map.
    var collision_builder: DungeonHeightFieldCollisionBuilder = DungeonHeightFieldCollisionBuilder.new() # Creates the specialized collision service that removes concave wall triangles from player contact.
    collision_builder.add_wall_collision_shapes(collision_body, _layout, _height_field) # Adds outward-only BoxShape3D blockers along every exposed walkable boundary edge.
    var ceiling_mesh: ArrayMesh = collision_builder.build_ceiling_collision_mesh(_layout, _height_field) # Generates only downward-facing ceiling triangles from the authoritative ceiling map.
    if ceiling_mesh.get_surface_count() <= 0: # Detects malformed topology that produced no valid overhead collision.
        return # Leaves the reliable height-map floor and primitive walls active without constructing an empty concave shape.
    var ceiling_collision: CollisionShape3D = CollisionShape3D.new() # Creates one direct collision child for the comparatively infrequent overhead contacts.
    ceiling_collision.name = "CeilingCollision" # Distinguishes overhead trimesh collision from the floor height map and primitive wall blockers.
    ceiling_collision.shape = ceiling_mesh.create_trimesh_shape() # Converts only the ceiling surface into a static concave collision resource with no vertical wall triangles.
    collision_body.add_child(ceiling_collision) # Adds the ceiling-only shape directly beneath the shared static dungeon collision owner.
