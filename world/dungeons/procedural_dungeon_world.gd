extends Node3D # Owns one active deterministic dungeon interior and every runtime-only asset generated for it.
class_name ProceduralDungeonWorld # Exposes generated geometry, lighting, exits, and player spawn positions to the transition manager.

const PLAYER_FLOOR_CLEARANCE: float = 0.08 # Matches the small player spawn separation used by the overworld terrain placement flow.
const INTERIOR_SPAWN_DISTANCE: float = 1.55 # Places the player safely inside the dungeon after arriving through either paired endpoint.
const GENERATED_LIGHT_COUNT: int = 7 # Stays below Compatibility's default eight-omni-lights-per-mesh limit for the single combined dungeon architecture mesh.
const LIGHT_HEIGHT: float = 2.85 # Places generated dungeon lights above eye level while keeping them below the ceiling.
const LIGHT_RANGE: float = 11.5 # Gives each generated source enough reach to create alternating illuminated and dark areas.
const LIGHT_ENERGY: float = 1.55 # Defines a readable but restrained intensity for the generated warm dungeon lighting.

var _layout: DungeonLayout # Stores the deterministic logical floor plan used by all generated physical systems.
var _dungeon_seed: int = 0 # Stores the stable root seed used to reconstruct this exact interior on every visit.
var _pair_id: int = -1 # Stores the exterior pair identity currently represented by this active world space.
var _region_coordinate: Vector2i = Vector2i.ZERO # Stores the infinite overworld region that owns the active pair for readable interior labels.
var _environment: Environment # Stores the runtime camera environment used while the overworld is suspended.
var _door_a: DungeonDoor # Stores the generated interior exit linked back to exterior endpoint A.
var _door_b: DungeonDoor # Stores the generated interior exit linked back to exterior endpoint B.

func build(pair_id: int, dungeon_seed: int, region_coordinate: Vector2i) -> void: # Generates the complete deterministic dungeon world from immutable pair identity, seed, and owning region.
    _pair_id = pair_id # Retains the pair identity for transition routing and generated diagnostics.
    _dungeon_seed = dungeon_seed # Retains the seed shared by topology, visual variation, and lighting placement.
    _region_coordinate = region_coordinate # Retains the source overworld region so interior endpoints use compact stable labels instead of large numeric IDs.
    var layout_generator: DungeonLayoutGenerator = DungeonLayoutGenerator.new() # Creates the isolated logical topology service without scene-tree ownership.
    _layout = layout_generator.generate(_dungeon_seed) # Reconstructs the complete guaranteed-connected A-to-B floor plan from the stable seed.
    _build_geometry() # Converts validated logical cells into combined procedural visual and collision meshes.
    _build_interior_doors() # Creates the two generated exits that map one-to-one onto the exterior paired doors.
    _build_procedural_lighting() # Adds seeded runtime light fixtures across connected floor cells.
    _environment = _create_environment() # Creates the textureless dungeon-specific camera environment used during this world mode.

func get_environment() -> Environment: # Returns the generated environment resource that should override the overworld while this dungeon is active.
    return _environment # Exposes the runtime resource without introducing a second WorldEnvironment node.

func get_spawn_position(endpoint: DungeonPairDefinition.Endpoint) -> Vector3: # Returns the dungeon-local player root position immediately inside the requested paired door.
    if _layout == null: # Handles transition requests before generation has completed defensively.
        return Vector3(0.0, PLAYER_FLOOR_CLEARANCE, 0.0) # Returns a safe local fallback near the generated world's origin.
    if endpoint == DungeonPairDefinition.Endpoint.B: # Detects arrival through exterior endpoint B.
        var door_position_b: Vector3 = _get_interior_door_position(DungeonPairDefinition.Endpoint.B) # Resolves the generated east-side portal position.
        return door_position_b + Vector3(-INTERIOR_SPAWN_DISTANCE, PLAYER_FLOOR_CLEARANCE, 0.0) # Places the player west of the B portal, safely inside traversable dungeon floor.
    var door_position_a: Vector3 = _get_interior_door_position(DungeonPairDefinition.Endpoint.A) # Resolves the generated west-side portal position.
    return door_position_a + Vector3(INTERIOR_SPAWN_DISTANCE, PLAYER_FLOOR_CLEARANCE, 0.0) # Places the player east of the A portal, safely inside traversable dungeon floor.

func get_spawn_yaw(endpoint: DungeonPairDefinition.Endpoint) -> float: # Returns a player yaw that faces away from the entered portal and into the generated dungeon.
    if endpoint == DungeonPairDefinition.Endpoint.B: # Detects arrival through the eastern endpoint.
        return PI * 0.5 # Faces the default first-person forward vector toward negative x from endpoint B.
    return -PI * 0.5 # Faces the default first-person forward vector toward positive x from endpoint A.

func _build_geometry() -> void: # Creates runtime-only dungeon rendering and simplified concave collision from the logical layout.
    var geometry_builder: DungeonGeometryBuilder = DungeonGeometryBuilder.new() # Creates the isolated mesh-construction service for this generation pass.
    var visual_mesh: ArrayMesh = geometry_builder.build_visual_mesh(_layout, _dungeon_seed) # Generates all visible architectural surfaces and deterministic detail.
    var mesh_instance: MeshInstance3D = MeshInstance3D.new() # Creates one scene node for the complete combined visible dungeon mesh.
    mesh_instance.name = "GeneratedArchitecture" # Assigns a stable diagnostic name in the remote scene tree.
    mesh_instance.mesh = visual_mesh # Installs the runtime-only generated architecture resource.
    add_child(mesh_instance) # Adds the complete visible interior beneath this disposable dungeon world root.
    var collision_mesh: ArrayMesh = geometry_builder.build_collision_mesh(_layout) # Generates a simpler geometry copy without decorative wall protrusions.
    if collision_mesh.get_surface_count() <= 0: # Detects an invalid empty layout that cannot create useful world collision.
        return # Leaves rendering available for diagnostics without attempting to construct an empty physics shape.
    var dungeon_body: StaticBody3D = StaticBody3D.new() # Creates one static physics owner for the complete generated interior shell.
    dungeon_body.name = "GeneratedCollision" # Assigns a stable diagnostic name to the procedural collision body.
    dungeon_body.collision_layer = 1 # Places dungeon architecture on the same ordinary solid world layer used by player movement and melee rays.
    dungeon_body.collision_mask = 1 # Retains ordinary world collision behavior for future dungeon actors using the default layer.
    var collision_shape: CollisionShape3D = CollisionShape3D.new() # Creates the shape child consumed by the generated static body.
    collision_shape.name = "CollisionShape3D" # Uses the conventional collision child name for remote-scene inspection.
    collision_shape.shape = collision_mesh.create_trimesh_shape() # Converts the simplified runtime mesh directly into a concave static collision resource.
    dungeon_body.add_child(collision_shape) # Installs the generated collision shape under its static owner before scene activation.
    add_child(dungeon_body) # Adds the complete collision shell beneath this disposable dungeon world root.

func _build_interior_doors() -> void: # Creates exactly two procedural interior exits mapped to the pair's exterior A and B endpoints.
    var label_prefix: String = "DUNGEON [%d,%d]" % [_region_coordinate.x, _region_coordinate.y] # Builds one compact stable label shared by both inside exits of this streamed infinite-region pair.
    _door_a = DungeonDoor.new() # Allocates endpoint A directly from the reusable runtime-generated door implementation.
    _door_a.name = "InteriorDoorA" # Gives the generated exit a stable diagnostic scene-tree identity.
    _door_a.position = _get_interior_door_position(DungeonPairDefinition.Endpoint.A) # Places endpoint A against the western boundary wall of its logical cell.
    _door_a.configure(_pair_id, DungeonPairDefinition.Endpoint.A, false, -PI * 0.5, "%s A" % label_prefix) # Maps the west interior exit directly back to exterior door A with the owning region displayed.
    add_child(_door_a) # Adds endpoint A to the active dungeon physics and interaction world.
    _door_b = DungeonDoor.new() # Allocates endpoint B from the exact same procedural door implementation.
    _door_b.name = "InteriorDoorB" # Gives the second generated exit a stable diagnostic identity.
    _door_b.position = _get_interior_door_position(DungeonPairDefinition.Endpoint.B) # Places endpoint B against the eastern boundary wall of its logical cell.
    _door_b.configure(_pair_id, DungeonPairDefinition.Endpoint.B, false, PI * 0.5, "%s B" % label_prefix) # Maps the east interior exit directly back to exterior door B with matching region identity.
    add_child(_door_b) # Adds endpoint B to the active dungeon interaction world.

func _get_interior_door_position(endpoint: DungeonPairDefinition.Endpoint) -> Vector3: # Resolves one interior endpoint from logical grid coordinates to its matching boundary-wall position.
    var cell: Vector2i = _layout.door_b_cell if endpoint == DungeonPairDefinition.Endpoint.B else _layout.door_a_cell # Selects the logical floor cell belonging to the requested paired side.
    var centre: Vector3 = DungeonGeometryBuilder.get_cell_center(_layout, cell, 0.0) # Converts the logical cell into centred dungeon-local physical coordinates.
    var boundary_offset: float = DungeonGeometryBuilder.CELL_SIZE * 0.5 - 0.03 # Keeps the generated portal plane just inside the enclosing collision wall.
    if endpoint == DungeonPairDefinition.Endpoint.B: # Detects the east-side paired exit.
        centre.x += boundary_offset # Moves endpoint B from the cell centre onto its eastern boundary wall.
    else: # Handles the west-side paired exit.
        centre.x -= boundary_offset # Moves endpoint A from the cell centre onto its western boundary wall.
    return centre # Returns the dungeon-local root position used by the procedural door and player spawn calculations.

func _build_procedural_lighting() -> void: # Adds deterministic runtime fixtures and OmniLight3D nodes across the generated connected floor plan.
    if _layout == null or _layout.get_floor_cell_count() <= 0: # Detects a malformed dungeon without any valid placement cells.
        return # Avoids requesting random indices from an empty logical floor list.
    var rng: RandomNumberGenerator = RandomNumberGenerator.new() # Creates a local lighting generator isolated from topology RNG state.
    rng.seed = _dungeon_seed + 404_873 # Derives the lighting stream independently so later layout algorithm changes need not alter light choices accidentally.
    var light_count: int = mini(GENERATED_LIGHT_COUNT, _layout.get_floor_cell_count()) # Caps fixtures to both the authored performance budget and available floor cells.
    var used_cells: Dictionary = {} # Tracks chosen logical cells so multiple generated lights cannot occupy the same location.
    var attempts: int = 0 # Bounds duplicate-resolution work if the floor plan is unusually small.
    while used_cells.size() < light_count and attempts < light_count * 8: # Continues selecting seeded unique floor cells within a predictable attempt budget.
        attempts += 1 # Consumes one bounded placement attempt before selecting a candidate.
        var floor_index: int = rng.randi_range(0, _layout.get_floor_cell_count() - 1) # Selects a deterministic connected floor coordinate.
        var cell: Vector2i = _layout.get_floor_cell_at(floor_index) # Retrieves the logical position without allocating a copied cell collection.
        if used_cells.has(cell): # Detects a seeded duplicate fixture location.
            continue # Tries another deterministic sample while preserving the unique-light requirement.
        if cell == _layout.door_a_cell or cell == _layout.door_b_cell: # Keeps fixtures away from the two transition portals and their player spawn zones.
            continue # Resamples instead of visually crowding a dungeon exit.
        used_cells[cell] = true # Records the accepted logical cell before creating its visual and light nodes.
        _add_generated_light_fixture(cell, rng) # Builds the textureless fixture and matching local light at this deterministic position.

func _add_generated_light_fixture(cell: Vector2i, rng: RandomNumberGenerator) -> void: # Creates one procedural hanging fixture plus its warm local light.
    var centre: Vector3 = DungeonGeometryBuilder.get_cell_center(_layout, cell, LIGHT_HEIGHT) # Places the fixture within the selected traversable cell below the generated ceiling.
    var fixture: MeshInstance3D = MeshInstance3D.new() # Creates the runtime node for a small generated metal light housing.
    fixture.name = "GeneratedLantern_%d_%d" % [cell.x, cell.y] # Gives the fixture a deterministic coordinate-derived diagnostic name.
    fixture.position = centre # Places the generated housing at the seeded logical cell centre.
    var fixture_mesh: CylinderMesh = CylinderMesh.new() # Uses a runtime primitive cylinder as the textureless lantern body.
    fixture_mesh.top_radius = 0.11 # Narrows the generated fixture top for a compact hanging-light silhouette.
    fixture_mesh.bottom_radius = 0.16 # Widens the lower fixture body slightly for visible shape variation.
    fixture_mesh.height = 0.34 # Keeps the generated fixture small relative to corridor headroom.
    fixture_mesh.radial_segments = 8 # Uses a deliberately faceted low-cost procedural silhouette.
    var fixture_material: StandardMaterial3D = StandardMaterial3D.new() # Creates the textureless fixture surface material entirely at runtime.
    fixture_material.albedo_color = Color(0.12, 0.095, 0.065, 1.0) # Gives the generated housing a dark oxidized-metal appearance without image assets.
    fixture_material.metallic = 0.58 # Adds restrained metallic response under the fixture's own generated light.
    fixture_material.roughness = 0.67 # Keeps the procedural metal worn rather than mirror-like.
    fixture_mesh.material = fixture_material # Assigns the generated material directly to the runtime primitive mesh.
    fixture.mesh = fixture_mesh # Installs the complete generated fixture resource on its scene node.
    add_child(fixture) # Adds the textureless lantern housing to the active dungeon world.
    var light: OmniLight3D = OmniLight3D.new() # Creates the actual runtime light corresponding to the generated fixture.
    light.name = "GeneratedLight_%d_%d" % [cell.x, cell.y] # Gives the light the same deterministic coordinate identity.
    light.position = centre + Vector3(0.0, -0.18, 0.0) # Places illumination immediately beneath the hanging fixture body.
    var warmth: float = rng.randf_range(-0.035, 0.035) # Produces restrained seeded colour variation among independent dungeon lights.
    light.light_color = Color(clampf(1.0 + warmth, 0.0, 1.0), clampf(0.72 + warmth * 0.4, 0.0, 1.0), clampf(0.42 - warmth * 0.25, 0.0, 1.0), 1.0) # Generates a warm flame-like colour without a texture or particle asset.
    light.light_energy = LIGHT_ENERGY * rng.randf_range(0.86, 1.12) # Varies fixture brightness deterministically while remaining within a narrow readable range.
    light.omni_range = LIGHT_RANGE * rng.randf_range(0.9, 1.08) # Varies illumination reach slightly so light pools do not repeat perfectly.
    light.shadow_enabled = false # Avoids multiplying compatibility-renderer shadow cost across many procedural fixtures.
    add_child(light) # Adds the generated local illumination to the active dungeon world.

func _create_environment() -> Environment: # Creates a dungeon-specific textureless environment resource for camera override during interior traversal.
    var environment: Environment = Environment.new() # Allocates the complete runtime environment without loading an authored resource file.
    environment.background_mode = Environment.BG_COLOR # Uses a solid dark clear colour because the generated dungeon is fully enclosed.
    environment.background_color = Color(0.006, 0.007, 0.009, 1.0) # Provides a near-black fallback behind any procedural geometry edge cases.
    environment.background_energy_multiplier = 0.18 # Keeps accidental clear-background exposure visually subordinate to generated lighting.
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR # Uses a fixed efficient ambient colour rather than sampling the suspended overworld sky.
    environment.ambient_light_color = Color(0.12, 0.135, 0.16, 1.0) # Provides cool low-level fill so completely unlit corridors retain minimal readability.
    environment.ambient_light_energy = 0.42 # Keeps local generated lights visually dominant while preventing absolute black surfaces.
    environment.ambient_light_sky_contribution = 0.0 # Ensures the active overworld sky contributes no lighting while the dungeon camera override is active.
    environment.fog_enabled = true # Adds restrained depth separation inside longer procedurally generated corridors.
    environment.fog_light_color = Color(0.075, 0.08, 0.09, 1.0) # Uses a neutral dark fog colour compatible with the generated stone palette.
    environment.fog_light_energy = 0.45 # Prevents fog from washing out the dark interior lighting model.
    environment.fog_density = 0.012 # Applies only subtle atmospheric falloff across the bounded single-level dungeon size.
    return environment # Returns the complete runtime environment for assignment directly to the first-person camera.
