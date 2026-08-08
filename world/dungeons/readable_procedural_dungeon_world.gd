extends ProceduralDungeonWorld # Retains deterministic dungeon topology while replacing flat interior planes with paired floor and ceiling height maps.
class_name ReadableProceduralDungeonWorld # Provides height-field architecture, height-map floor collision, exact sloped-surface spawning, and brighter readable lighting.

const WORLD_COLLISION_LAYER: int = 1 # Matches the ordinary solid-world collision layer already used by the player, terrain, and generated dungeon architecture.
const HEIGHTMAP_COLLISION_SCALE: float = DungeonHeightFieldMeshBuilder.CELL_SIZE # Uniformly scales HeightMapShape3D's one-unit grid spacing to the dungeon's physical logical-cell spacing.
const LANTERN_ENERGY_MULTIPLIER: float = 1.65 # Raises each existing procedural lantern enough to illuminate nearby walls and floor clearly.
const LANTERN_RANGE_MULTIPLIER: float = 1.35 # Broadens each existing light pool so dark gaps between the bounded compatibility-renderer light count are less severe.
const READABLE_AMBIENT_COLOUR: Color = Color(0.25, 0.275, 0.32, 1.0) # Provides a cool neutral fill that preserves the warmer identity of local lanterns.
const READABLE_AMBIENT_ENERGY: float = 0.92 # Keeps unlit corridors navigable while leaving local fixtures visibly brighter than ambient stone.
const READABLE_BACKGROUND_ENERGY: float = 0.32 # Makes accidental clear-background exposure less black without competing with dungeon architecture.
const READABLE_FOG_COLOUR: Color = Color(0.13, 0.14, 0.155, 1.0) # Lightens atmospheric fill so distant corridors remain legible instead of disappearing into black.
const READABLE_FOG_ENERGY: float = 0.72 # Raises fog illumination enough to preserve depth cues under the stronger ambient baseline.
const READABLE_FOG_DENSITY: float = 0.006 # Reduces the original fog density so long corridors retain more visible geometry.

var _height_field: DungeonHeightField # Stores the authoritative paired floor and ceiling maps shared by rendering, collision, doors, and player spawn grounding.

func get_height_mapped_spawn_position(endpoint: DungeonPairDefinition.Endpoint, distance: float, vertical_clearance: float) -> Vector3: # Returns a global player landing point in front of the exact interior door and grounded to the generated floor map.
    var door: DungeonDoor = _door_b if endpoint == DungeonPairDefinition.Endpoint.B else _door_a # Selects only the physical interior endpoint corresponding to the requested paired side.
    if door == null or _height_field == null: # Detects calls before the generated endpoint and height maps are ready.
        return global_position + get_spawn_position(endpoint) # Falls back to the inherited deterministic flat-space spawn rather than returning an invalid world coordinate.
    var front_direction: Vector3 = door.get_forward_direction() # Reads the exact physical door axis already used by strict A/B transition routing.
    front_direction.y = 0.0 # Keeps landing distance horizontal even if future door transforms gain a small pitch component.
    if front_direction.is_zero_approx(): # Detects a degenerate generated door transform defensively.
        front_direction = Vector3.FORWARD # Uses a stable conventional fallback only when the physical doorway cannot provide direction.
    else: # Handles the normal valid generated-door orientation path.
        front_direction = front_direction.normalized() # Normalizes the horizontal direction before applying the requested physical landing distance.
    var safe_distance: float = maxf(distance, 0.0) # Prevents malformed callers from placing the player through the selected door onto its blocked outside side.
    var candidate_global: Vector3 = door.global_position + front_direction * safe_distance # Moves from the exact corresponding door into its traversable endpoint cell.
    var candidate_local: Vector3 = to_local(candidate_global) # Converts the horizontal landing point into dungeon-local coordinates for authoritative height-map sampling.
    candidate_local.y = _height_field.sample_floor(candidate_local.x, candidate_local.z, DungeonHeightFieldMeshBuilder.CELL_SIZE) + maxf(vertical_clearance, 0.0) # Grounds the player root directly above the exact bilinearly sampled visible floor height.
    return to_global(candidate_local) # Converts the height-corrected landing point back into the scene-space coordinates consumed by the player body.

func _build_geometry() -> void: # Generates both height maps first, then derives visible surfaces and physics from those exact shared samples.
    _height_field = DungeonHeightField.new() # Allocates one authoritative paired-height data source for this disposable deterministic dungeon instance.
    _height_field.generate(_layout, _dungeon_seed) # Reconstructs the complete floor and ceiling maps from immutable layout and dungeon seed.
    var mesh_builder: DungeonHeightFieldMeshBuilder = DungeonHeightFieldMeshBuilder.new() # Creates the isolated service that stitches height-field cells and perimeter walls into runtime meshes.
    var visual_mesh: ArrayMesh = mesh_builder.build_visual_mesh(_layout, _height_field, _dungeon_seed) # Generates walkable floor and ceiling surfaces plus walls joining their exposed edges.
    var mesh_instance: MeshInstance3D = MeshInstance3D.new() # Creates one render node for the complete height-field dungeon architecture.
    mesh_instance.name = "GeneratedArchitecture" # Preserves the established diagnostic scene-tree name used for runtime inspection.
    mesh_instance.mesh = visual_mesh # Installs the combined textureless floor-map, ceiling-map, and wall mesh resource.
    add_child(mesh_instance) # Adds the complete visible dungeon architecture beneath this disposable world root.
    var collision_body: StaticBody3D = StaticBody3D.new() # Creates one static physics owner for the height-map floor and stitched ceiling/wall collision shell.
    collision_body.name = "GeneratedCollision" # Preserves the existing collision owner name for remote-scene debugging.
    collision_body.collision_layer = WORLD_COLLISION_LAYER # Places the complete interior shell on the player's normal world-collision layer.
    collision_body.collision_mask = WORLD_COLLISION_LAYER # Retains ordinary static-world collision behavior for future dungeon actors using the same layer.
    add_child(collision_body) # Installs the physics owner before attaching its direct collision-shape children.
    _add_floor_heightmap_collision(collision_body) # Uses Godot's dedicated HeightMapShape3D for routine grounded contact against the generated floor map.
    var wall_ceiling_mesh: ArrayMesh = mesh_builder.build_wall_and_ceiling_collision_mesh(_layout, _height_field) # Rebuilds only overhead and perimeter triangles from the exact same authoritative height samples.
    if wall_ceiling_mesh.get_surface_count() <= 0: # Detects malformed topology that produced no ceiling or wall triangles.
        return # Leaves the valid floor heightmap collision active while avoiding an empty concave shape.
    var wall_ceiling_collision: CollisionShape3D = CollisionShape3D.new() # Creates one direct collision child for the less frequently contacted overhead and vertical mesh surfaces.
    wall_ceiling_collision.name = "WallCeilingCollision" # Gives the stitched non-floor shell a clear diagnostic identity distinct from the heightmap floor.
    wall_ceiling_collision.shape = wall_ceiling_mesh.create_trimesh_shape() # Converts inward/downward-wound perimeter and ceiling triangles into one static concave collision resource.
    collision_body.add_child(wall_ceiling_collision) # Adds the completed ceiling/wall shell directly beneath the shared static body.

func _add_floor_heightmap_collision(collision_body: StaticBody3D) -> void: # Creates one HeightMapShape3D whose samples are the same authoritative floor values used by the visible mesh.
    var floor_collision: CollisionShape3D = CollisionShape3D.new() # Allocates the direct collision child consumed by the shared dungeon static body.
    floor_collision.name = "FloorHeightMapCollision" # Gives the primary grounded-contact surface an explicit remote-scene diagnostic name.
    floor_collision.scale = Vector3.ONE * HEIGHTMAP_COLLISION_SCALE # Uniformly scales the heightmap so one physics-grid interval equals one logical dungeon cell in x and z.
    var floor_shape: HeightMapShape3D = HeightMapShape3D.new() # Uses Godot's dedicated grid-height collision type instead of a per-cell concave floor triangle shell.
    floor_shape.map_width = _height_field.vertex_width # Matches collision columns exactly to the authoritative shared floor-map vertex count.
    floor_shape.map_depth = _height_field.vertex_depth # Matches collision rows exactly to the authoritative shared floor-map depth count.
    floor_shape.map_data = _height_field.get_scaled_floor_map_data(HEIGHTMAP_COLLISION_SCALE) # Pre-scales vertical values so the uniform collision-node scale restores their intended world-space heights.
    floor_collision.shape = floor_shape # Assigns the complete deterministic floor heightmap resource to the collision node.
    collision_body.add_child(floor_collision) # Adds the primary floor collision directly beneath its owning StaticBody3D.

func _get_interior_door_position(endpoint: DungeonPairDefinition.Endpoint) -> Vector3: # Places each interior portal on the generated floor height map instead of assuming a flat zero-elevation threshold.
    var cell: Vector2i = _layout.door_b_cell if endpoint == DungeonPairDefinition.Endpoint.B else _layout.door_a_cell # Selects the guaranteed walkable endpoint cell corresponding to the requested paired side.
    var centre: Vector3 = DungeonGeometryBuilder.get_cell_center(_layout, cell, 0.0) # Resolves the horizontal centre of the logical endpoint cell using the established dungeon coordinate convention.
    var boundary_offset: float = DungeonGeometryBuilder.CELL_SIZE * 0.5 - 0.03 # Keeps the portal plane just inside the enclosing stitched boundary wall as before.
    if endpoint == DungeonPairDefinition.Endpoint.B: # Detects the east-side interior endpoint.
        centre.x += boundary_offset # Moves endpoint B onto the eastern boundary of its logical walkable cell.
    else: # Handles the west-side interior endpoint.
        centre.x -= boundary_offset # Moves endpoint A onto the western boundary of its logical walkable cell.
    if _height_field != null: # Confirms authoritative floor samples were generated during the preceding geometry pass.
        centre.y = _height_field.sample_floor(centre.x, centre.z, DungeonHeightFieldMeshBuilder.CELL_SIZE) # Grounds the physical doorway threshold directly onto the bilinearly sampled floor height map.
    return centre # Returns the complete dungeon-local portal position consumed by the inherited deterministic door builder.

func _build_procedural_lighting() -> void: # Builds the original deterministic fixtures, then strengthens only their light resources without increasing light count.
    super._build_procedural_lighting() # Reuses the established seeded fixture placement and compatibility-safe seven-light budget.
    for child: Node in get_children(): # Examines generated direct children after the base lighting pass has installed all fixtures and lights.
        if not (child is OmniLight3D): # Skips architecture, collision, doors, fixture meshes, and every other non-light child.
            continue # Advances directly to the next generated dungeon child.
        var light: OmniLight3D = child as OmniLight3D # Converts the validated generated light to its strongly typed resource owner.
        light.light_energy *= LANTERN_ENERGY_MULTIPLIER # Raises brightness while preserving each fixture's deterministic seeded variation.
        light.omni_range *= LANTERN_RANGE_MULTIPLIER # Broadens the existing pool without adding another per-mesh light to the compatibility renderer.

func _create_environment() -> Environment: # Starts from the existing dungeon environment and raises only the values responsible for baseline readability.
    var environment: Environment = super._create_environment() # Preserves the existing textureless background, fog mode, and overworld-independent camera environment contract.
    environment.background_energy_multiplier = READABLE_BACKGROUND_ENERGY # Prevents any procedural geometry gap from presenting as absolute black.
    environment.ambient_light_color = READABLE_AMBIENT_COLOUR # Replaces the very dark blue ambient fill with a brighter neutral-cool stone-readable tone.
    environment.ambient_light_energy = READABLE_AMBIENT_ENERGY # Raises baseline illumination across the complete dungeon so navigation never depends on standing beside a lantern.
    environment.fog_light_color = READABLE_FOG_COLOUR # Keeps the reduced fog compatible with the brighter ambient stone palette.
    environment.fog_light_energy = READABLE_FOG_ENERGY # Lets fog carry enough light to retain distant corridor silhouettes.
    environment.fog_density = READABLE_FOG_DENSITY # Reduces atmospheric extinction so the procedural layout remains visible over longer sight lines.
    return environment # Returns the readability-adjusted environment used directly by the player's dungeon camera override.
