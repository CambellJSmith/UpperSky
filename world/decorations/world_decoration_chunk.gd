extends StaticBody3D # Streams one chunk of smooth trees and boulders with distance LOD and low-overhead nearby collision.
class_name WorldDecorationChunk # Makes decoration chunks available to the independent decoration streamer.

const DECORATION_CULL_MARGIN: float = 18.0 # Expands MultiMesh bounds around generated object origins for complete silhouettes.

var _placements: Array[WorldDecorationPlacement] = [] # Retains deterministic object transforms for visual LOD rebuilding and nearby collision.
var _mesh_library: WorldDecorationMeshLibrary # Supplies shared non-cubic meshes and reusable primitive collision resources.
var _visual_nodes: Array[MultiMeshInstance3D] = [] # Stores the small set of draw-batched visual nodes owned by this chunk.
var _collision_shape_owners: Array[int] = [] # Stores shape-owner IDs instead of allocating one CollisionShape3D node per dense object.
var _lod_level: int = -1 # Stores the active visual detail tier and forces initial visual construction.
var _collision_active: bool = false # Tracks whether physical interaction is currently installed.

func configure(placements: Array[WorldDecorationPlacement], mesh_library: WorldDecorationMeshLibrary, lod_level: int) -> void: # Stores generated placements and creates draw-batched visuals at the requested detail tier.
    _placements = placements # Retains stable transforms so visual LOD and collision always describe the same objects.
    _mesh_library = mesh_library # Retains shared resource access without duplicating geometry or primitive shapes per chunk.
    _lod_level = clampi(lod_level, WorldDecorationMeshLibrary.LOD_NEAR, WorldDecorationMeshLibrary.LOD_FAR) # Stores a valid initial distance tier.
    _create_visuals() # Batches smooth trees and boulders into a small number of MultiMeshes.

func set_lod_level(lod_level: int) -> void: # Rebuilds only the batched visual buffers when this chunk enters another distance tier.
    var next_lod: int = clampi(lod_level, WorldDecorationMeshLibrary.LOD_NEAR, WorldDecorationMeshLibrary.LOD_FAR) # Restricts the requested level to authored shared meshes.
    if next_lod == _lod_level: # Detects a chunk that remains inside the same distance band.
        return # Avoids reallocating MultiMesh buffers unnecessarily.
    _lod_level = next_lod # Stores the new distance tier before rebuilding visuals.
    _clear_visuals() # Releases the old LOD's small set of draw batches.
    _create_visuals() # Rebuilds instance buffers against the cheaper or richer shared meshes.

func set_collision_active(enabled: bool) -> void: # Creates or releases decoration collision according to player distance.
    if enabled == _collision_active: # Avoids rebuilding collision when the requested state has not changed.
        return # Leaves the current state untouched.
    _collision_active = enabled # Stores the newly requested nearby collision state.
    if _collision_active: # Checks whether physical interaction must now be installed.
        _create_collisions() # Adds shared primitive shapes directly to this body without child-node overhead.
        return # Stops after activating collision.
    _clear_collisions() # Removes every object shape owner while retaining distant visuals.

func _create_visuals() -> void: # Groups every placement by shared LOD mesh so dense rendering remains inexpensive.
    if _mesh_library == null or _placements.is_empty(): # Detects chunks without generated objects or mesh resources.
        return # Leaves this chunk empty.
    var tree_transforms: Array[Transform3D] = [] # Collects every shared tree instance transform.
    var boulder_transforms_by_variant: Dictionary = {} # Groups rounded rocks by the variations retained at this LOD.
    var boulder_sequence: int = 0 # Provides deterministic far-distance rock thinning without extra stored metadata.
    for placement: WorldDecorationPlacement in _placements: # Visits every deterministic object owned by this chunk.
        if placement.kind == WorldDecorationPlacement.Kind.TREE: # Detects the shared smooth tree family.
            tree_transforms.append(placement.transform) # Keeps the complete dense tree population visible at every LOD.
            continue # Skips boulder grouping for this placement.
        if _lod_level == WorldDecorationMeshLibrary.LOD_FAR and boulder_sequence % 2 == 1: # Draws half of the very dense rock population at the farthest tier.
            boulder_sequence += 1 # Advances the stable sequence before skipping this visual instance.
            continue # Reduces distant vertex work while near and middle tiers retain every generated rock.
        boulder_sequence += 1 # Advances the deterministic far-thinning sequence for retained rocks.
        var visual_variant: int = placement.variant # Retains all three silhouettes in the immediate area.
        if _lod_level == WorldDecorationMeshLibrary.LOD_MEDIUM: # Reduces middle-distance rock draw groups.
            visual_variant = posmod(placement.variant, 2) # Uses two shared silhouettes instead of three.
        elif _lod_level == WorldDecorationMeshLibrary.LOD_FAR: # Collapses far rocks into one cheapest mesh and one draw group.
            visual_variant = 0 # Uses one shared silhouette where individual variation is no longer readable.
        if not boulder_transforms_by_variant.has(visual_variant): # Detects the first rock using this visible variation.
            boulder_transforms_by_variant[visual_variant] = [] # Creates the variation's compact transform collection.
        var variant_transforms: Array = boulder_transforms_by_variant[visual_variant] # Retrieves the mutable collection for this silhouette.
        variant_transforms.append(placement.transform) # Adds the rounded rock instance transform.
        boulder_transforms_by_variant[visual_variant] = variant_transforms # Stores the updated collection explicitly.
    _add_multimesh_visual("SmoothTrees_LOD%d" % _lod_level, _mesh_library.get_tree_mesh(_lod_level), tree_transforms) # Creates one draw-batched tree visual.
    for variant_key: Variant in boulder_transforms_by_variant.keys(): # Visits every boulder silhouette used by this LOD.
        var variant: int = int(variant_key) # Converts the dictionary key into the authored variation index.
        var transforms: Array = boulder_transforms_by_variant[variant] # Retrieves every transform using this shared mesh.
        _add_multimesh_visual("SmoothBoulders_%d_LOD%d" % [variant, _lod_level], _mesh_library.get_boulder_mesh(variant, _lod_level), transforms) # Creates one draw-batched rock visual per retained silhouette.

func _add_multimesh_visual(node_name: String, mesh: Mesh, transforms: Array) -> void: # Creates one MultiMeshInstance3D from shared geometry and chunk-local transforms.
    if mesh == null or transforms.is_empty(): # Rejects unavailable geometry or empty groups.
        return # Avoids creating unused visual nodes.
    var multi_mesh: MultiMesh = MultiMesh.new() # Allocates the shared-instance data buffer.
    multi_mesh.transform_format = MultiMesh.TRANSFORM_3D # Enables complete three-dimensional transforms before allocating the instance buffer.
    multi_mesh.mesh = mesh # Assigns the one smooth mesh resource shared by the complete group.
    multi_mesh.instance_count = transforms.size() # Allocates exactly the required transform count after data format is configured.
    var bounds_minimum: Vector3 = Vector3(INF, INF, INF) # Starts local visibility bounds above every possible point.
    var bounds_maximum: Vector3 = Vector3(-INF, -INF, -INF) # Starts local visibility bounds below every possible point.
    for instance_index: int in range(transforms.size()): # Writes every generated transform into the GPU instance buffer.
        var instance_transform: Transform3D = transforms[instance_index] # Retrieves one chunk-local transform.
        multi_mesh.set_instance_transform(instance_index, instance_transform) # Applies translation, rotation, and nonuniform scale to the shared mesh.
        var origin: Vector3 = instance_transform.origin # Reads the object centre or base for visibility bounds.
        bounds_minimum.x = minf(bounds_minimum.x, origin.x - DECORATION_CULL_MARGIN) # Expands bounds left of the instance.
        bounds_minimum.y = minf(bounds_minimum.y, origin.y - DECORATION_CULL_MARGIN) # Expands bounds beneath embedded rocks and tree bases.
        bounds_minimum.z = minf(bounds_minimum.z, origin.z - DECORATION_CULL_MARGIN) # Expands bounds behind the instance.
        bounds_maximum.x = maxf(bounds_maximum.x, origin.x + DECORATION_CULL_MARGIN) # Expands bounds right of the instance.
        bounds_maximum.y = maxf(bounds_maximum.y, origin.y + DECORATION_CULL_MARGIN) # Expands bounds above complete canopies.
        bounds_maximum.z = maxf(bounds_maximum.z, origin.z + DECORATION_CULL_MARGIN) # Expands bounds ahead of the instance.
    multi_mesh.custom_aabb = AABB(bounds_minimum, bounds_maximum - bounds_minimum) # Prevents costly runtime bounds recalculation for the complete MultiMesh.
    var instance_node: MultiMeshInstance3D = MultiMeshInstance3D.new() # Creates the scene node that submits the batch to rendering.
    instance_node.name = node_name # Gives the generated group a stable diagnostic name.
    instance_node.multimesh = multi_mesh # Connects the shared mesh and complete transform buffer.
    if _lod_level == WorldDecorationMeshLibrary.LOD_FAR: # Detects the largest and most expensive visible population.
        instance_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # Prevents thousands of distant trees and rocks from entering directional shadow rendering.
    else: # Retains useful local and middle-distance grounding.
        instance_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON # Keeps shadows where individual objects remain readable.
    add_child(instance_node) # Keeps the batch aligned with streaming and floating-origin movement.
    _visual_nodes.append(instance_node) # Retains the node for later LOD replacement or chunk release.

func _clear_visuals() -> void: # Releases the current LOD's small set of visual batches.
    for instance_node: MultiMeshInstance3D in _visual_nodes: # Visits every tree or boulder draw group owned by this chunk.
        if not is_instance_valid(instance_node): # Handles an already released node defensively.
            continue # Skips invalid references.
        if instance_node.get_parent() == self: # Detects a node still attached to this chunk.
            remove_child(instance_node) # Removes it from rendering immediately.
        instance_node.queue_free() # Releases its MultiMesh resource and node at frame end.
    _visual_nodes.clear() # Resets the active draw-group set before rebuilding another LOD.

func _create_collisions() -> void: # Creates dense nearby collision with shared Shape3D resources and no CollisionShape3D child nodes.
    if not _collision_shape_owners.is_empty() or _mesh_library == null: # Detects existing collision or unavailable shared resources.
        return # Avoids duplicate shape owners and invalid setup.
    for placement: WorldDecorationPlacement in _placements: # Visits every generated nearby object.
        var visual_scale: Vector3 = placement.transform.basis.get_scale() # Extracts positive instance dimensions from the visual transform.
        var owner_id: int = create_shape_owner(self) # Creates one lightweight transform owner directly on this StaticBody3D.
        var shape_transform: Transform3D = Transform3D.IDENTITY # Starts with an unrotated chunk-local primitive transform.
        if placement.kind == WorldDecorationPlacement.Kind.TREE: # Creates a narrow solid trunk while leaving foliage non-solid.
            var trunk_shape: CylinderShape3D = _mesh_library.get_tree_collision_shape(visual_scale) # Reuses one of three shared trunk resources.
            shape_transform.origin = placement.transform.origin + Vector3.UP * trunk_shape.height * 0.5 # Centres the cylinder above the tree's ground-level origin.
            shape_owner_add_shape(owner_id, trunk_shape) # Adds the shared smooth cylinder to this object owner.
        else: # Creates a rounded conservative collision volume for an irregular boulder.
            var boulder_shape: SphereShape3D = _mesh_library.get_boulder_collision_shape(visual_scale) # Reuses one of three shared rock resources.
            shape_transform.origin = placement.transform.origin # Aligns collision with the visible embedded boulder centre.
            shape_owner_add_shape(owner_id, boulder_shape) # Adds the shared rounded volume to this object owner.
        shape_owner_set_transform(owner_id, shape_transform) # Applies the placement-specific local position without allocating a node.
        _collision_shape_owners.append(owner_id) # Retains the owner ID for immediate release outside the collision radius.

func _clear_collisions() -> void: # Removes all nearby object collision while preserving batched visuals.
    for owner_id: int in _collision_shape_owners: # Visits every currently active tree or rock shape owner.
        remove_shape_owner(owner_id) # Removes its shapes and transform from the physics body immediately.
    _collision_shape_owners.clear() # Resets the active set for future re-entry into the collision radius.
