extends ProceduralDungeonWorld # Retains deterministic dungeon generation while improving grounded collision reliability and interior visibility.
class_name ReadableProceduralDungeonWorld # Provides primitive floor contact, simplified wall collision, brighter ambient fill, and stronger existing lanterns.

const FLOOR_COLLISION_THICKNESS: float = 0.30 # Gives the broad primitive dungeon floor enough thickness for reliable CharacterBody contact without changing the visible floor plane.
const CEILING_COLLISION_THICKNESS: float = 0.30 # Gives the broad primitive ceiling a simple reliable blocker while keeping its lower face aligned with visible ceiling height.
const WORLD_COLLISION_LAYER: int = 1 # Matches the ordinary solid-world collision layer already used by the player, terrain, and generated dungeon architecture.
const LANTERN_ENERGY_MULTIPLIER: float = 1.65 # Raises each existing procedural lantern enough to illuminate nearby walls and floor clearly.
const LANTERN_RANGE_MULTIPLIER: float = 1.35 # Broadens each existing light pool so dark gaps between the bounded compatibility-renderer light count are less severe.
const READABLE_AMBIENT_COLOUR: Color = Color(0.25, 0.275, 0.32, 1.0) # Provides a cool neutral fill that preserves the warmer identity of local lanterns.
const READABLE_AMBIENT_ENERGY: float = 0.92 # Keeps unlit corridors navigable while leaving local fixtures visibly brighter than ambient stone.
const READABLE_BACKGROUND_ENERGY: float = 0.32 # Makes accidental clear-background exposure less black without competing with dungeon architecture.
const READABLE_FOG_COLOUR: Color = Color(0.13, 0.14, 0.155, 1.0) # Lightens atmospheric fill so distant corridors remain legible instead of disappearing into black.
const READABLE_FOG_ENERGY: float = 0.72 # Raises fog illumination enough to preserve depth cues under the stronger ambient baseline.
const READABLE_FOG_DENSITY: float = 0.006 # Reduces the original fog density so long corridors retain more visible geometry.

func _build_geometry() -> void: # Builds the unchanged procedural visuals but replaces horizontal trimesh contact with broad primitive floor and ceiling collision.
    var geometry_builder: DungeonGeometryBuilder = DungeonGeometryBuilder.new() # Creates the established visual mesh service using the exact same deterministic layout and stone generation path.
    var visual_mesh: ArrayMesh = geometry_builder.build_visual_mesh(_layout, _dungeon_seed) # Generates the complete visible floor, ceiling, walls, and deterministic trim without changing dungeon appearance.
    var mesh_instance: MeshInstance3D = MeshInstance3D.new() # Creates one render node for the complete combined procedural architecture mesh.
    mesh_instance.name = "GeneratedArchitecture" # Preserves the established diagnostic scene-tree name used for runtime inspection.
    mesh_instance.mesh = visual_mesh # Installs the unchanged deterministic visible mesh resource.
    add_child(mesh_instance) # Adds the complete visible dungeon architecture beneath this disposable world root.
    var collision_body: StaticBody3D = StaticBody3D.new() # Creates one static physics owner for all reliable simplified dungeon collision shapes.
    collision_body.name = "GeneratedCollision" # Preserves the existing collision owner name for remote-scene debugging.
    collision_body.collision_layer = WORLD_COLLISION_LAYER # Places the complete simplified shell on the player's normal world-collision layer.
    collision_body.collision_mask = WORLD_COLLISION_LAYER # Retains ordinary static-world collision behavior for future dungeon actors using the same layer.
    add_child(collision_body) # Installs the physics owner before attaching direct CollisionShape3D children as required by Godot.
    var dungeon_width: float = float(_layout.width) * DungeonGeometryBuilder.CELL_SIZE # Calculates the complete centred grid width covered by the generated dungeon layout.
    var dungeon_depth: float = float(_layout.height) * DungeonGeometryBuilder.CELL_SIZE # Calculates the complete centred grid depth covered by the generated dungeon layout.
    _add_box_collision(collision_body, "FloorCollision", Vector3(dungeon_width, FLOOR_COLLISION_THICKNESS, dungeon_depth), Vector3(0.0, -FLOOR_COLLISION_THICKNESS * 0.5, 0.0)) # Uses one broad box whose top surface aligns exactly with visible floor height and contains no triangle seams.
    _add_box_collision(collision_body, "CeilingCollision", Vector3(dungeon_width, CEILING_COLLISION_THICKNESS, dungeon_depth), Vector3(0.0, DungeonGeometryBuilder.CEILING_HEIGHT + CEILING_COLLISION_THICKNESS * 0.5, 0.0)) # Uses one broad box whose lower surface aligns exactly with the visible ceiling plane.
    var wall_builder: StableDungeonCollisionBuilder = StableDungeonCollisionBuilder.new() # Creates the walls-only mesh service so vertical boundaries retain the exact logical dungeon shape.
    var wall_mesh: ArrayMesh = wall_builder.build_wall_collision_mesh(_layout) # Generates only simplified boundary-wall triangles with no horizontal floor or ceiling faces.
    if wall_mesh.get_surface_count() <= 0: # Detects a malformed layout that produced no valid boundary collision.
        return # Leaves the reliable floor and ceiling primitives active while avoiding an empty trimesh resource.
    var wall_collision: CollisionShape3D = CollisionShape3D.new() # Creates the single direct collision child that owns all generated vertical boundary triangles.
    wall_collision.name = "WallCollision" # Gives the simplified wall shell an explicit diagnostic name distinct from primitive horizontal contact.
    wall_collision.shape = wall_mesh.create_trimesh_shape() # Converts only vertical boundary geometry into one static concave collision shape.
    collision_body.add_child(wall_collision) # Adds the walls directly beneath the static body so Godot includes them in physics queries.

func _add_box_collision(body: StaticBody3D, node_name: String, size: Vector3, local_position: Vector3) -> void: # Adds one optimized primitive box collision shape directly beneath the shared dungeon StaticBody3D.
    var collision_shape: CollisionShape3D = CollisionShape3D.new() # Creates the direct physics-shape node required by the owning static body.
    collision_shape.name = node_name # Assigns a stable descriptive name for collision-debug inspection.
    collision_shape.position = local_position # Places the primitive so its usable face aligns with the corresponding visible architecture plane.
    var box_shape: BoxShape3D = BoxShape3D.new() # Uses Godot's reliable optimized primitive shape rather than additional horizontal trimesh triangles.
    box_shape.size = size # Assigns the complete requested floor or ceiling dimensions without scaling the CollisionShape3D node.
    collision_shape.shape = box_shape # Installs the primitive resource on the direct physics child.
    body.add_child(collision_shape) # Adds the completed primitive to the shared static collision owner.

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
