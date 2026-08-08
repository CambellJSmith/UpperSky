extends Area3D # Implements one interactable procedural doorway used by both overworld endpoints and matching dungeon exits.
class_name DungeonDoor # Exposes stable pair and endpoint metadata to the central dungeon transition system.

const INTERACTION_COLLISION_LAYER: int = 1 << 7 # Reserves one isolated physics layer so the camera interaction ray can query doors without world geometry interference.
const OPENING_WIDTH: float = 1.9 # Defines the clear visual width inside each generated stone doorway.
const OPENING_HEIGHT: float = 2.75 # Defines the clear visual height of the dark procedural portal surface.
const FRAME_BLOCK_THICKNESS: float = 0.34 # Defines the square section used by generated stone jambs and lintels.
const FRAME_DEPTH: float = 0.52 # Gives the procedural doorway enough depth to read as freestanding architecture in the overworld.
const INTERACTION_DEPTH: float = 0.85 # Makes the camera interaction target slightly thicker than the visible portal surface.
const LABEL_HEIGHT: float = 3.45 # Positions the generated identification and interaction hint above the doorway.

const FRAME_COLOUR: Color = Color(0.31, 0.295, 0.255, 1.0) # Defines the textureless weathered-stone colour shared by procedural entrance frames.
const FRAME_ACCENT_COLOUR: Color = Color(0.22, 0.205, 0.175, 1.0) # Defines darker generated foundation stones beneath each doorway.
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
    _build_frame_geometry() # Creates the complete stone frame from runtime primitive mesh resources.
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

func _build_frame_geometry() -> void: # Creates a freestanding stone portal frame from runtime primitive meshes.
    var side_x: float = OPENING_WIDTH * 0.5 + FRAME_BLOCK_THICKNESS * 0.5 # Calculates the horizontal centre of each vertical jamb around the clear opening.
    var jamb_height: float = OPENING_HEIGHT + FRAME_BLOCK_THICKNESS # Extends jambs high enough to support the generated lintel visually.
    _add_box_visual("LeftJamb", Vector3(FRAME_BLOCK_THICKNESS, jamb_height, FRAME_DEPTH), Vector3(-side_x, jamb_height * 0.5, 0.0), FRAME_COLOUR) # Builds the complete left stone support.
    _add_box_visual("RightJamb", Vector3(FRAME_BLOCK_THICKNESS, jamb_height, FRAME_DEPTH), Vector3(side_x, jamb_height * 0.5, 0.0), FRAME_COLOUR.lightened(0.035)) # Builds the right support with subtle procedural material variation.
    _add_box_visual("Lintel", Vector3(OPENING_WIDTH + FRAME_BLOCK_THICKNESS * 2.0, FRAME_BLOCK_THICKNESS, FRAME_DEPTH), Vector3(0.0, OPENING_HEIGHT + FRAME_BLOCK_THICKNESS * 0.5, 0.0), FRAME_COLOUR.darkened(0.025)) # Bridges both jambs with a generated stone lintel.
    _add_box_visual("LeftFoot", Vector3(FRAME_BLOCK_THICKNESS * 1.55, 0.24, FRAME_DEPTH * 1.35), Vector3(-side_x, 0.12, 0.0), FRAME_ACCENT_COLOUR) # Adds a wider foundation block beneath the left jamb.
    _add_box_visual("RightFoot", Vector3(FRAME_BLOCK_THICKNESS * 1.55, 0.24, FRAME_DEPTH * 1.35), Vector3(side_x, 0.12, 0.0), FRAME_ACCENT_COLOUR.lightened(0.025)) # Adds the matching generated foundation beneath the right jamb.

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
    portal_material.cull_mode = BaseMaterial3D.CULL_DISABLED # Keeps the portal visible from either side of the freestanding generated frame.
    portal_mesh.material = portal_material # Assigns the generated material directly to the runtime primitive mesh.
    portal_mesh_instance.mesh = portal_mesh # Installs the complete procedural portal resource on its scene node.
    add_child(portal_mesh_instance) # Adds the visible transition surface beneath this Area3D doorway.

func _build_label(display_name: String) -> void: # Creates a billboarded endpoint label and interaction hint without a preauthored UI scene.
    var label: Label3D = Label3D.new() # Allocates the complete world-space text presentation at runtime.
    label.name = "DoorLabel" # Gives the generated hint a stable scene-tree name for debugging.
    label.position = Vector3(0.0, LABEL_HEIGHT, 0.0) # Places the text immediately above the procedural stone frame.
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED # Keeps the interaction hint facing the active first-person camera from any approach direction.
    label.font_size = 28 # Uses a readable world-space size at the intended interaction distance.
    label.outline_size = 8 # Adds contrast against both bright overworld terrain and dark dungeon walls.
    label.modulate = Color(0.92, 0.90, 0.82, 1.0) # Gives the generated label a warm neutral dungeon-sign colour.
    var action_text: String = "ENTER" if _is_exterior else "EXIT" # Selects the transition verb from the configured world-space side.
    label.text = "%s\n[E / X] %s" % [display_name, action_text] # Combines deterministic endpoint identity with keyboard and controller interaction hints.
    add_child(label) # Installs the generated label beneath the doorway so it follows all world transforms automatically.

func _add_box_visual(node_name: String, size: Vector3, local_position: Vector3, colour: Color) -> void: # Adds one runtime primitive stone block to the procedural doorway frame.
    var mesh_instance: MeshInstance3D = MeshInstance3D.new() # Creates the visible node for this generated frame element.
    mesh_instance.name = node_name # Assigns a descriptive remote-scene-tree name for debugging generated geometry.
    mesh_instance.position = local_position # Places the frame block relative to the doorway root and its configured yaw.
    var box_mesh: BoxMesh = BoxMesh.new() # Creates the complete block geometry procedurally from primitive dimensions.
    box_mesh.size = size # Assigns the requested physical size without loading any authored model resource.
    var material: StandardMaterial3D = StandardMaterial3D.new() # Creates a dedicated textureless stone material for this small generated block.
    material.albedo_color = colour # Uses the supplied deterministic frame colour directly as the material's base appearance.
    material.roughness = 0.94 # Keeps generated entrance stone broad and matte under both exterior and dungeon lighting.
    box_mesh.material = material # Assigns the runtime material directly to the generated primitive mesh.
    mesh_instance.mesh = box_mesh # Installs the complete generated stone block on its visual node.
    add_child(mesh_instance) # Adds the frame element beneath the doorway so one transform controls the complete procedural asset.
