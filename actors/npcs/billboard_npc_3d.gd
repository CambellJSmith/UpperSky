extends CharacterBody3D # Provides the shared moving physics root used by every non-player character while keeping character rendering strictly two-dimensional.
class_name BillboardNpc3D # Establishes the project-wide NPC presentation contract that all character NPC implementations should inherit.

const NPC_GROUP_NAME: StringName = &"npc" # Defines the stable scene-tree group used to identify billboard NPC actors without depending on scene paths.
const BILLBOARD_VISUAL_PATH: NodePath = NodePath("BillboardVisual") # Defines the required MeshInstance3D child path that owns the complete visible NPC character texture.

@onready var _billboard_visual: MeshInstance3D = get_node_or_null(BILLBOARD_VISUAL_PATH) as MeshInstance3D # Resolves the one required billboard mesh used for NPC character presentation.

func _ready() -> void: # Registers the NPC and validates that its scene obeys the billboard-only character presentation contract.
    add_to_group(NPC_GROUP_NAME) # Marks every actor inheriting this base as an NPC for world-management and future gameplay queries.
    assert(_billboard_visual != null, "BillboardNpc3D requires a MeshInstance3D child named BillboardVisual.") # Fails development builds when an NPC scene omits the required billboard mesh presentation node.

func configure_billboard(texture: Texture2D, physical_size: Vector2) -> void: # Builds the complete camera-facing textured quad used as this NPC's only character rendering geometry.
    if _billboard_visual == null or texture == null: # Rejects incomplete scene or texture state before allocating render resources.
        return # Leaves the NPC invisible instead of silently constructing an invalid model-based fallback.
    var quad_mesh: QuadMesh = QuadMesh.new() # Creates the single flat mesh permitted for NPC character presentation.
    quad_mesh.size = Vector2(maxf(physical_size.x, 0.01), maxf(physical_size.y, 0.01)) # Applies validated physical dimensions so the billboard matches gameplay collision scale.
    var material: StandardMaterial3D = StandardMaterial3D.new() # Creates a runtime material dedicated to the NPC texture without authored 3D model materials.
    material.albedo_texture = texture # Uses the supplied two-dimensional character image as the complete visible NPC appearance.
    material.albedo_color = Color.WHITE # Preserves authored texture colours without additional tinting by default.
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA # Enables transparent pixels around the character silhouette instead of showing the rectangular quad background.
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # Keeps the billboard readable and visually stable independently from terrain and dungeon lighting direction.
    material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y # Rotates the flat character quad around the vertical axis so it continuously faces the active camera while remaining upright.
    material.billboard_keep_scale = true # Prevents camera-facing orientation from altering the NPC's authored physical billboard scale.
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST # Preserves crisp source texture pixels instead of blurring the generated low-resolution character image.
    material.cull_mode = BaseMaterial3D.CULL_DISABLED # Keeps the billboard visible from either side during camera or transition edge cases.
    quad_mesh.material = material # Assigns the complete transparent billboard material directly to the permitted flat mesh.
    _billboard_visual.mesh = quad_mesh # Installs the textured quad on the required MeshInstance3D and completes NPC visual setup.

func get_billboard_visual() -> MeshInstance3D: # Returns the required billboard mesh for small animation offsets without exposing replacement 3D model paths.
    return _billboard_visual # Provides controlled access to the established texture-backed character presentation node.
