extends Area3D # Implements one interactable procedural doorway used by both overworld endpoints and matching dungeon exits.
class_name DungeonDoor # Exposes stable pair and endpoint metadata to the central dungeon transition system.

const INTERACTION_COLLISION_LAYER: int = 1 << 7 # Reserves one isolated physics layer so the camera interaction ray can query doors without world geometry interference.
const OPENING_WIDTH: float = 1.9 # Defines the clear visual width inside each generated stone doorway.
const OPENING_HEIGHT: float = 2.75 # Defines the clear visual height of the dark procedural portal surface.
const FRAME_BLOCK_THICKNESS: float = 0.34 # Defines the square section used by generated stone jambs and lintels.
const FRAME_DEPTH: float = 0.62 # Gives the core doorway enough depth to bridge visually into the extended exterior tunnel masonry.
const INTERACTION_DEPTH: float = 0.85 # Makes the camera interaction target slightly thicker than the visible portal surface.
const LABEL_HEIGHT: float = 3.45 # Positions ordinary interior-door identification and interaction text above the compact dungeon frame.
const EXTERIOR_LABEL_HEIGHT: float = 4.72 # Raises exterior labels above the much larger hillside masonry crown so text remains unobstructed.
const MASONRY_BLOCK_WIDTH: float = 0.82 # Defines the nominal width of individual generated exterior retaining-wall stones.
const MASONRY_BLOCK_HEIGHT: float = 0.40 # Defines the nominal height of each staggered exterior stone course.
const MASONRY_BLOCK_DEPTH: float = 1.62 # Pushes each visible exterior stone well behind the portal plane so its rear portion disappears into terrain.
const MASONRY_WING_COLUMNS: int = 4 # Extends several block columns outward on both sides of the portal to blend the constructed opening into the hillside.
const MASONRY_WING_COURSES: int = 8 # Raises exterior retaining masonry above the complete portal height on both sides.
const MASONRY_CROWN_COLUMNS: int = 9 # Spans a broad generated stone crown across the doorway and both retaining-wall shoulders.
const MASONRY_CROWN_COURSES: int = 3 # Builds multiple upper courses so terrain can overlap the entrance without exposing a thin isolated lintel.
const MASONRY_COLUMN_STEP: float = 0.76 # Slightly overlaps neighbouring generated stones horizontally to avoid visible gaps on irregular terrain intersections.
const MASONRY_COURSE_STEP: float = 0.39 # Slightly overlaps vertical courses so the retaining wall remains visually continuous when buried into terrain.
const MASONRY_BACK_OFFSET: float = 0.64 # Centres visible exterior courses behind the portal face so they penetrate the uphill terrain side.
const TUNNEL_RETURN_DEPTH: float = 3.55 # Extends hidden structural masonry several metres backward into the hill to make the entrance read as a tunnel throat.
const TUNNEL_RETURN_WALL_THICKNESS: float = 0.46 # Gives buried side and ceiling returns enough visual mass where terrain edges expose them.

const FRAME_COLOUR: Color = Color(0.31, 0.295, 0.255, 1.0) # Defines the textureless weathered-stone colour shared by procedural entrance frames.
const FRAME_ACCENT_COLOUR: Color = Color(0.22, 0.205, 0.175, 1.0) # Defines darker generated foundation stones beneath each doorway.
const MASONRY_COLOUR: Color = Color(0.285, 0.267, 0.225, 1.0) # Defines the main dry-stone colour used by generated hillside retaining courses.
const MASONRY_BURIED_COLOUR: Color = Color(0.205, 0.192, 0.163, 1.0) # Defines darker stone for buried tunnel returns and foundation courses disappearing into terrain.
const PORTAL_COLOUR: Color = Color(0.018, 0.014, 0.026, 0.88) # Defines the nearly black translucent plane representing the world-space transition surface.

var _pair_id: int = -1 # Stores the deterministic dungeon pair identity represented by this physical door.
var _endpoint: DungeonPairDefinition.Endpoint = DungeonPairDefinition.Endpoint.A # Stores whether this door corresponds to side A or side B of the pair.
var _is_exterior: bool = true # Distinguishes overworld entrances from their matching interior dungeon exits.

func configure(pair_id: int, endpoint: DungeonPairDefinition.Endpoint, is_exterior: bool, yaw: float, display_name: String) -> void: # Assigns immutable transition metadata and builds the complete runtime-only doorway presentation.
    _pair_id = pair_id # Retains the stable pair identity required to resolve the correct deterministic interior.
    _endpoint = endpoint # Retains which paired side should be used for entry or return travel.
    _is_exterior = is_exterior # Records whether interaction should enter a dungeon or return to the overworld.
    rotation.y = yaw # Orients the generated doorway around the vertical axis before it enters the active scene tree.
    collision_layer = INTERACTION_COLLISION_LAYER # Places only the interaction Area3D on the dedicated dungeon-door raycast layer.
    collision_mask = 0 # Prevents the Area3D from requesting overlap monitoring against ordinary world collision layers.
    monitoring = false # Disables unnecessary overlap event processing because interaction uses a direct camera ray query instead.
    monitorable = true # Keeps the area visible to direct physics-space queries from the dungeon interaction system.
    _build_interaction_shape() # Creates the procedural raycast target covering the doorway opening.
    _build_frame_geometry() # Creates the compact core frame used by both exterior and interior versions of the paired doorway.
    if _is_exterior: # Detects an overworld entrance that must visually merge into a sampled cliff, hill, or mountain face.
        _build_exterior_masonry() # Builds broad staggered retaining courses and a buried tunnel throat extending backward into terrain.
    _build_portal_surface() # Creates the generated dark transition plane without loading an image or model asset.
    _build_label(display_name) # Creates a billboarded procedural text hint identifying the pair endpoint and interaction control.

func get_pair_id() -> int: # Returns the stable paired-dungeon identity associated with this doorway.
    return _pair_id # Exposes immutable configuration without allowing external mutation.

func get_endpoint() -> DungeonPairDefinition.Endpoint: # Returns whether this doorway is endpoint A or endpoint B.
    return _endpoint # Exposes the configured side used by deterministic entry and exit mapping.

func is_exterior() -> bool: # Reports whether this doorway currently exists in the procedural overworld rather than the generated interior.
    return _is_exterior # Allows the transition manager to choose entry or exit behavior from one shared door type.

func get_forward_direction() -> Vector3: # Returns the physical direction facing out through the visible portal plane.
    return -global_transform.basis.z.normalized() # Converts the doorway's local forward axis into a normalized world-space direction.

func _build_interaction_shape() -> void: # Creates a non-solid Area3D volume covering the visible doorway for direct camera interaction.
    var collision_shape: CollisionShape3D = CollisionShape3D.new() # Allocates the interaction collision node entirely at runtime.
    collision_shape.name = "InteractionShape" # Gives the generated child a stable diagnostic name in the remote scene tree.
    collision_shape.position = Vector3(0.0, OPENING_HEIGHT * 0.5, 0.0) # Centres the interaction volume vertically over the doorway opening.
    var box_shape: BoxShape3D = BoxShape3D.new() # Creates a runtime primitive collision resource with no authored scene dependency.
    box_shape.size = Vector3(OPENING_WIDTH + 0.28, OPENING_HEIGHT + 0.18, INTERACTION_DEPTH) # Covers the complete portal while remaining tightly scoped for camera targeting.
    collision_shape.shape = box_shape # Assigns the generated volume to the Area3D collision child.
    add_child(collision_shape) # Installs the interaction target beneath this doorway before scene-tree activation.

func _build_frame_geometry() -> void: # Creates the compact stone portal frame shared by exterior tunnel mouths and interior dungeon exits.
    var side_x: float = OPENING_WIDTH * 0.5 + FRAME_BLOCK_THICKNESS * 0.5 # Calculates the horizontal centre of each vertical jamb around the clear opening.
    var jamb_height: float = OPENING_HEIGHT + FRAME_BLOCK_THICKNESS # Extends jambs high enough to support the generated lintel visually.
    _add_box_visual("LeftJamb", Vector3(FRAME_BLOCK_THICKNESS, jamb_height, FRAME_DEPTH), Vector3(-side_x, jamb_height * 0.5, 0.0), FRAME_COLOUR) # Builds the complete left stone support.
    _add_box_visual("RightJamb", Vector3(FRAME_BLOCK_THICKNESS, jamb_height, FRAME_DEPTH), Vector3(side_x, jamb_height * 0.5, 0.0), FRAME_COLOUR.lightened(0.035)) # Builds the right support with subtle procedural material variation.
    _add_box_visual("Lintel", Vector3(OPENING_WIDTH + FRAME_BLOCK_THICKNESS * 2.0, FRAME_BLOCK_THICKNESS, FRAME_DEPTH), Vector3(0.0, OPENING_HEIGHT + FRAME_BLOCK_THICKNESS * 0.5, 0.0), FRAME_COLOUR.darkened(0.025)) # Bridges both jambs with a generated stone lintel.
    _add_box_visual("LeftFoot", Vector3(FRAME_BLOCK_THICKNESS * 1.55, 0.24, FRAME_DEPTH * 1.35), Vector3(-side_x, 0.12, 0.0), FRAME_ACCENT_COLOUR) # Adds a wider foundation block beneath the left jamb.
    _add_box_visual("RightFoot", Vector3(FRAME_BLOCK_THICKNESS * 1.55, 0.24, FRAME_DEPTH * 1.35), Vector3(side_x, 0.12, 0.0), FRAME_ACCENT_COLOUR.lightened(0.025)) # Adds the matching generated foundation beneath the right jamb.

func _build_exterior_masonry() -> void: # Creates extended procedural brickwork that visibly overlaps and disappears into the uphill terrain behind every exterior portal.
    var rng: RandomNumberGenerator = RandomNumberGenerator.new() # Creates local deterministic stone variation without touching global random state.
    rng.seed = _get_masonry_seed() # Reconstructs the same block colours, depths, and small offsets from the pair identity on every stream reload.
    _build_buried_tunnel_returns(rng) # Installs deep side and ceiling returns first so exposed gaps always reveal believable tunnel structure instead of empty space.
    _build_masonry_wing(-1, rng) # Builds the broad staggered retaining wall extending left from the doorway into surrounding terrain.
    _build_masonry_wing(1, rng) # Builds the matching right retaining wall with independent deterministic block variation.
    _build_masonry_crown(rng) # Adds several broad upper courses spanning the portal and disappearing into the terrain above both shoulders.
    _build_masonry_foundation(rng) # Adds partially buried lower courses so the constructed opening blends into uneven ground at the foot of the hill.

func _build_buried_tunnel_returns(rng: RandomNumberGenerator) -> void: # Extends structural stone backward along local positive z, which is the uphill direction for cliff-oriented exterior doors.
    var side_x: float = OPENING_WIDTH * 0.5 + TUNNEL_RETURN_WALL_THICKNESS * 0.5 # Places buried return walls immediately outside the clear portal opening.
    var return_z: float = TUNNEL_RETURN_DEPTH * 0.5 - 0.18 # Centres the deep return geometry mostly behind the portal plane while leaving a small visible front reveal.
    var return_wall_height: float = OPENING_HEIGHT + FRAME_BLOCK_THICKNESS # Matches the return walls to the complete core jamb and lintel envelope.
    _add_box_visual("BuriedTunnelLeft", Vector3(TUNNEL_RETURN_WALL_THICKNESS, return_wall_height, TUNNEL_RETURN_DEPTH), Vector3(-side_x, return_wall_height * 0.5, return_z), _vary_stone_colour(MASONRY_BURIED_COLOUR, rng)) # Pushes the left tunnel wall several metres into the sampled hillside.
    _add_box_visual("BuriedTunnelRight", Vector3(TUNNEL_RETURN_WALL_THICKNESS, return_wall_height, TUNNEL_RETURN_DEPTH), Vector3(side_x, return_wall_height * 0.5, return_z), _vary_stone_colour(MASONRY_BURIED_COLOUR, rng)) # Pushes the right tunnel wall into the same terrain mass.
    _add_box_visual("BuriedTunnelCeiling", Vector3(OPENING_WIDTH + TUNNEL_RETURN_WALL_THICKNESS * 2.0, TUNNEL_RETURN_WALL_THICKNESS, TUNNEL_RETURN_DEPTH), Vector3(0.0, OPENING_HEIGHT + TUNNEL_RETURN_WALL_THICKNESS * 0.5, return_z), _vary_stone_colour(MASONRY_BURIED_COLOUR, rng)) # Extends a stone roof backward beneath the terrain overburden.

func _build_masonry_wing(side: int, rng: RandomNumberGenerator) -> void: # Builds one staggered retaining-wall shoulder beside the exterior opening from individual deterministic procedural stones.
    var wing_start: float = OPENING_WIDTH * 0.5 + FRAME_BLOCK_THICKNESS + MASONRY_BLOCK_WIDTH * 0.36 # Starts the first wing column overlapping the core frame so no terrain seam can appear between systems.
    for course: int in range(MASONRY_WING_COURSES): # Builds vertical courses from partially buried foundation level to above the lintel.
        var stagger: float = MASONRY_COLUMN_STEP * 0.5 if course % 2 == 1 else 0.0 # Offsets alternating courses to produce believable interlocking brickwork rather than aligned vertical seams.
        for column: int in range(MASONRY_WING_COLUMNS): # Extends each course several generated stones outward into the surrounding hillside.
            var distance_from_centre: float = wing_start + float(column) * MASONRY_COLUMN_STEP + stagger # Calculates the horizontal block centre before applying the requested left or right side.
            var local_x: float = float(side) * distance_from_centre # Mirrors the same generated wall structure cleanly across the portal opening.
            var local_y: float = MASONRY_BLOCK_HEIGHT * 0.5 + float(course) * MASONRY_COURSE_STEP # Stacks courses with slight overlap so terrain clipping cannot reveal narrow horizontal gaps.
            var local_z: float = MASONRY_BACK_OFFSET + rng.randf_range(-0.08, 0.32) # Pushes every retaining stone backward into the uphill terrain by a slightly varied deterministic amount.
            var block_width: float = MASONRY_BLOCK_WIDTH * rng.randf_range(0.90, 1.10) # Varies horizontal stone size modestly while preserving a coherent masonry course.
            var block_height: float = MASONRY_BLOCK_HEIGHT * rng.randf_range(0.92, 1.07) # Varies course stones vertically enough to avoid perfectly machined repetition.
            var block_depth: float = MASONRY_BLOCK_DEPTH * rng.randf_range(0.90, 1.18) # Varies how deeply each block penetrates the hillside so exposed terrain intersections look naturally irregular.
            var block_name: String = "MasonryWing_%d_%d_%d" % [side, course, column] # Gives each generated retaining stone a stable diagnostic identity.
            _add_box_visual(block_name, Vector3(block_width, block_height, block_depth), Vector3(local_x, local_y, local_z), _vary_stone_colour(MASONRY_COLOUR, rng)) # Installs the complete deterministic retaining stone beneath the doorway transform.

func _build_masonry_crown(rng: RandomNumberGenerator) -> void: # Builds broad staggered courses above the lintel so the entrance visually disappears under substantial terrain overburden.
    var crown_span: float = float(MASONRY_CROWN_COLUMNS - 1) * MASONRY_COLUMN_STEP # Measures the horizontal centre-to-centre width occupied by each complete crown course.
    for course: int in range(MASONRY_CROWN_COURSES): # Builds multiple upper layers rather than leaving one isolated lintel exposed against the hill.
        var stagger: float = MASONRY_COLUMN_STEP * 0.5 if course % 2 == 1 else 0.0 # Offsets alternate rows to continue the interlocking retaining-wall pattern above the doorway.
        for column: int in range(MASONRY_CROWN_COLUMNS): # Spans the crown across the portal and well into both side shoulders.
            var local_x: float = -crown_span * 0.5 + float(column) * MASONRY_COLUMN_STEP + stagger # Calculates each crown block centre across the complete entrance width.
            var local_y: float = OPENING_HEIGHT + FRAME_BLOCK_THICKNESS + MASONRY_BLOCK_HEIGHT * 0.5 + float(course) * MASONRY_COURSE_STEP # Places crown courses directly above and overlapping the core lintel.
            var local_z: float = MASONRY_BACK_OFFSET + 0.12 + rng.randf_range(-0.06, 0.30) # Pushes the upper masonry farther into the hill where terrain overburden is expected to cover it.
            var block_width: float = MASONRY_BLOCK_WIDTH * rng.randf_range(0.92, 1.12) # Gives crown stones slight deterministic width irregularity.
            var block_height: float = MASONRY_BLOCK_HEIGHT * rng.randf_range(0.94, 1.08) # Varies upper-course height without breaking the overall retaining-wall silhouette.
            var block_depth: float = MASONRY_BLOCK_DEPTH * rng.randf_range(1.00, 1.24) # Makes upper stones especially deep so they remain visibly connected when terrain intersects from above.
            var block_name: String = "MasonryCrown_%d_%d" % [course, column] # Assigns a stable generated name to each upper retaining stone.
            _add_box_visual(block_name, Vector3(block_width, block_height, block_depth), Vector3(local_x, local_y, local_z), _vary_stone_colour(MASONRY_COLOUR, rng)) # Adds the generated crown stone with deterministic weathered colour variation.

func _build_masonry_foundation(rng: RandomNumberGenerator) -> void: # Builds low broad masonry partly below the portal threshold so the exterior construction visibly disappears into surrounding ground.
    var foundation_width: float = OPENING_WIDTH + float(MASONRY_WING_COLUMNS) * MASONRY_COLUMN_STEP * 2.0 + 1.2 # Extends the buried foundation beneath the complete frame and both retaining-wall wings.
    _add_box_visual("BuriedFoundationRear", Vector3(foundation_width, 0.30, 2.35), Vector3(0.0, 0.02, 0.72), _vary_stone_colour(MASONRY_BURIED_COLOUR, rng)) # Pushes one broad foundation course backward and slightly below ground so terrain overlaps its edges.
    _add_box_visual("BuriedFoundationFront", Vector3(OPENING_WIDTH + 1.55, 0.22, 1.10), Vector3(0.0, 0.07, 0.10), _vary_stone_colour(FRAME_ACCENT_COLOUR, rng)) # Keeps a smaller visible threshold course at the approach side while its rear portion remains buried.

func _build_portal_surface() -> void: # Creates the dark procedural plane that visually communicates a transition rather than an ordinary open archway.
    var portal_mesh_instance: MeshInstance3D = MeshInstance3D.new() # Allocates the runtime visual node for the portal plane.
    portal_mesh_instance.name = "PortalSurface" # Assigns a stable diagnostic child name.
    portal_mesh_instance.position = Vector3(0.0, OPENING_HEIGHT * 0.5, 0.025) # Places the plane just forward of the frame centre to avoid depth overlap.
    var portal_mesh: QuadMesh = QuadMesh.new() # Creates a runtime primitive quad rather than loading a texture-backed asset.
    portal_mesh.size = Vector2(OPENING_WIDTH, OPENING_HEIGHT) # Matches the generated plane exactly to the clear doorway opening.
    var portal_material: StandardMaterial3D = StandardMaterial3D.new() # Creates an isolated textureless portal material resource.
    portal_material.albedo_color = PORTAL_COLOUR # Applies the authored dark transition colour directly without any image texture.
    portal_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA # Enables the restrained alpha value on the procedural portal plane.
    portal_material.roughness = 1.0 # Prevents environmental highlights from making the portal read as glossy plastic.
    portal_material.cull_mode = BaseMaterial3D.CULL_DISABLED # Keeps the portal visible from either side of the generated frame where terrain does not occlude it.
    portal_mesh.material = portal_material # Assigns the generated material directly to the runtime primitive mesh.
    portal_mesh_instance.mesh = portal_mesh # Installs the complete procedural portal resource on its scene node.
    add_child(portal_mesh_instance) # Adds the visible transition surface beneath this Area3D doorway.

func _build_label(display_name: String) -> void: # Creates a billboarded endpoint label and interaction hint without a preauthored UI scene.
    var label: Label3D = Label3D.new() # Allocates the complete world-space text presentation at runtime.
    label.name = "DoorLabel" # Gives the generated hint a stable scene-tree name for debugging.
    label.position = Vector3(0.0, EXTERIOR_LABEL_HEIGHT if _is_exterior else LABEL_HEIGHT, -0.05) # Keeps exterior text above the masonry crown while preserving the compact interior placement.
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED # Keeps the interaction hint facing the active first-person camera from any approach direction.
    label.font_size = 28 # Uses a readable world-space size at the intended interaction distance.
    label.outline_size = 8 # Adds contrast against both bright overworld terrain and dark dungeon walls.
    label.modulate = Color(0.92, 0.90, 0.82, 1.0) # Gives the generated label a warm neutral dungeon-sign colour.
    var action_text: String = "ENTER" if _is_exterior else "EXIT" # Selects the transition verb from the configured world-space side.
    label.text = "%s\n[E / X] %s" % [display_name, action_text] # Combines deterministic endpoint identity with keyboard and controller interaction hints.
    add_child(label) # Installs the generated label beneath the doorway so it follows all world transforms automatically.

func _get_masonry_seed() -> int: # Derives deterministic exterior block variation solely from stable pair and endpoint metadata.
    var seed_value: int = _pair_id ^ 1_548_583 # Mixes the pair identity with a fixed odd constant so masonry randomness remains independent from dungeon layout randomness.
    seed_value = seed_value ^ ((int(_endpoint) + 1) * 97_531) # Separates A and B masonry patterns even when both doors belong to the same deterministic dungeon pair.
    seed_value = seed_value ^ (seed_value << 13) # Diffuses nearby pair IDs across higher and lower random-seed bits.
    seed_value = seed_value ^ (seed_value >> 7) # Folds the mixed state back across the integer for stronger visual decorrelation.
    return seed_value # Returns the stable seed consumed only by generated exterior stone variation.

func _vary_stone_colour(base_colour: Color, rng: RandomNumberGenerator) -> Color: # Applies restrained deterministic value variation so procedural blocks do not read as one perfectly uniform material.
    var variation: float = rng.randf_range(-0.065, 0.055) # Samples a small signed brightness shift while retaining the shared weathered-stone palette.
    if variation >= 0.0: # Detects a block selected to be slightly lighter than the base stone.
        return base_colour.lightened(variation) # Applies the positive brightness shift using Godot's colour interpolation helper.
    return base_colour.darkened(-variation) # Applies an equivalent darkening for negative deterministic variation values.

func _add_box_visual(node_name: String, size: Vector3, local_position: Vector3, colour: Color) -> void: # Adds one runtime primitive stone block to the procedural doorway frame or extended exterior masonry.
    var mesh_instance: MeshInstance3D = MeshInstance3D.new() # Creates the visible node for this generated stone element.
    mesh_instance.name = node_name # Assigns a descriptive remote-scene-tree name for debugging generated geometry.
    mesh_instance.position = local_position # Places the stone relative to the doorway root and its terrain-derived yaw.
    var box_mesh: BoxMesh = BoxMesh.new() # Creates the complete block geometry procedurally from primitive dimensions.
    box_mesh.size = size # Assigns the requested physical size without loading any authored model resource.
    var material: StandardMaterial3D = StandardMaterial3D.new() # Creates a dedicated textureless stone material for this generated block.
    material.albedo_color = colour # Uses the supplied deterministic stone colour directly as the material's base appearance.
    material.roughness = 0.94 # Keeps generated entrance stone broad and matte under both exterior and dungeon lighting.
    box_mesh.material = material # Assigns the runtime material directly to the generated primitive mesh.
    mesh_instance.mesh = box_mesh # Installs the complete generated stone block on its visual node.
    add_child(mesh_instance) # Adds the stone beneath the doorway so one transform controls the complete procedural asset.
