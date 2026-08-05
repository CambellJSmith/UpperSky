extends StaticBody3D # Streams one chunk of smooth trees and boulders with near-player collision.
class_name WorldDecorationChunk # Makes decoration chunks available to the independent decoration streamer.

const TREE_COLLISION_HEIGHT: float = 6.8 # Approximates the shared visible trunk while leaving non-solid foliage traversable.
const TREE_COLLISION_RADIUS: float = 0.66 # Approximates the shared tapered trunk with a stable cylinder.
const BOULDER_COLLISION_RADIUS_FACTOR: float = 1.36 # Covers each distorted base boulder silhouette with a conservative smooth sphere.
const DECORATION_CULL_MARGIN: float = 18.0 # Expands MultiMesh bounds around generated object origins for complete silhouettes.

var _placements: Array[WorldDecorationPlacement] = [] # Retains deterministic object transforms for visual grouping and near-player collision.
var _mesh_library: WorldDecorationMeshLibrary # Supplies shared non-cubic tree and boulder meshes.
var _collision_shapes: Array[CollisionShape3D] = [] # Stores currently active nearby trunk and rock collision nodes.
var _collision_active: bool = false # Tracks whether physical interaction is currently installed.

func configure(placements: Array[WorldDecorationPlacement], mesh_library: WorldDecorationMeshLibrary) -> void: # Stores generated placements and creates draw-batched smooth visuals.
    _placements = placements # Retains stable transforms so collision can match the visible objects.
    _mesh_library = mesh_library # Retains shared mesh access without duplicating geometry per chunk.
    _create_visuals() # Batches smooth trees and boulders into a small number of MultiMeshes.

func set_collision_active(enabled: bool) -> void: # Creates or releases decoration collision according to player distance.
    if enabled == _collision_active: # Avoids rebuilding collision when the requested state has not changed.
        return # Leaves the current state untouched.
    _collision_active = enabled # Stores the newly requested nearby collision state.
    if _collision_active: # Checks whether physical interaction must now be installed.
        _create_collisions() # Adds trunk cylinders and rounded rock collision for every visible placement.
        return # Stops after activating collision.
    _clear_collisions() # Removes every object collision node while retaining distant visuals.

func _create_visuals() -> void: # Groups every placement by shared mesh so rendering remains inexpensive.
    if _mesh_library == null or _placements.is_empty(): # Detects chunks without generated objects or mesh resources.
        return # Leaves this chunk empty.
    var tree_transforms: Array = [] # Collects every shared tree instance transform.
    var boulder_transforms_by_variant: Dictionary = {} # Groups rounded rocks by their shared silhouette variation.
    for placement: WorldDecorationPlacement in _placements: # Visits every deterministic object owned by this chunk.
        if placement.kind == WorldDecorationPlacement.Kind.TREE: # Detects the shared smooth tree family.
            tree_transforms.append(placement.transform) # Adds the transform to one batched tree draw.
            continue # Skips boulder grouping for this placement.
        if not boulder_transforms_by_variant.has(placement.variant): # Detects the first rock using this variation.
            boulder_transforms_by_variant[placement.variant] = [] # Creates the variation's transform collection.
        var variant_transforms: Array = boulder_transforms_by_variant[placement.variant] # Retrieves the mutable collection for this silhouette.
        variant_transforms.append(placement.transform) # Adds the rounded rock instance transform.
    _add_multimesh_visual("SmoothTrees", _mesh_library.get_tree_mesh(), tree_transforms) # Creates one draw-batched tree visual when trees exist.
    for variant_key: Variant in boulder_transforms_by_variant.keys(): # Visits every boulder silhouette used by this chunk.
        var variant: int = int(variant_key) # Converts the dictionary key into the authored variation index.
        var transforms: Array = boulder_transforms_by_variant[variant] # Retrieves every transform using this shared mesh.
        _add_multimesh_visual("SmoothBoulders_%d" % variant, _mesh_library.get_boulder_mesh(variant), transforms) # Creates one draw-batched rock visual per used silhouette.

func _add_multimesh_visual(node_name: String, mesh: Mesh, transforms: Array) -> void: # Creates one MultiMeshInstance3D from shared geometry and chunk-local transforms.
    if mesh == null or transforms.is_empty(): # Rejects unavailable geometry or empty groups.
        return # Avoids creating unused visual nodes.
    var multi_mesh: MultiMesh = MultiMesh.new() # Allocates the shared-instance data buffer.
    multi_mesh.transform_format = MultiMesh.TRANSFORM_3D # Enables complete three-dimensional transforms for each instance.
    multi_mesh.mesh = mesh # Assigns the one smooth mesh resource shared by the complete group.
    multi_mesh.instance_count = transforms.size() # Allocates exactly the required transform count.
    var bounds_minimum: Vector3 = Vector3(INF, INF, INF) # Starts local visibility bounds above every possible point.
    var bounds_maximum: Vector3 = Vector3(-INF, -INF, -INF) # Starts local visibility bounds below every possible point.
    for instance_index: int in range(transforms.size()): # Writes every generated transform into the instance buffer.
        var instance_transform: Transform3D = transforms[instance_index] # Retrieves one strongly typed chunk-local transform.
        multi_mesh.set_instance_transform(instance_index, instance_transform) # Applies translation, rotation, and nonuniform scale to the shared mesh.
        var origin: Vector3 = instance_transform.origin # Reads the object centre or base for visibility bounds.
        bounds_minimum.x = minf(bounds_minimum.x, origin.x - DECORATION_CULL_MARGIN) # Expands bounds left of the instance.
        bounds_minimum.y = minf(bounds_minimum.y, origin.y - DECORATION_CULL_MARGIN) # Expands bounds beneath embedded rocks and tree bases.
        bounds_minimum.z = minf(bounds_minimum.z, origin.z - DECORATION_CULL_MARGIN) # Expands bounds behind the instance.
        bounds_maximum.x = maxf(bounds_maximum.x, origin.x + DECORATION_CULL_MARGIN) # Expands bounds right of the instance.
        bounds_maximum.y = maxf(bounds_maximum.y, origin.y + DECORATION_CULL_MARGIN) # Expands bounds above complete canopies.
        bounds_maximum.z = maxf(bounds_maximum.z, origin.z + DECORATION_CULL_MARGIN) # Expands bounds ahead of the instance.
    multi_mesh.custom_aabb = AABB(bounds_minimum, bounds_maximum - bounds_minimum) # Supplies stable culling bounds without scanning instances at runtime.
    var instance_node: MultiMeshInstance3D = MultiMeshInstance3D.new() # Creates the scene node that submits the batch to rendering.
    instance_node.name = node_name # Gives the generated group a stable diagnostic name.
    instance_node.multimesh = multi_mesh # Connects the shared mesh and complete transform buffer.
    add_child(instance_node) # Keeps the batch aligned with streaming and floating-origin movement.

func _create_collisions() -> void: # Creates simple smooth collision approximations only for nearby visible objects.
    if not _collision_shapes.is_empty(): # Detects an already active collision set.
        return # Avoids duplicating shape nodes during repeated state updates.
    for placement: WorldDecorationPlacement in _placements: # Visits every visible object owned by this nearby chunk.
        var visual_scale: Vector3 = placement.transform.basis.get_scale() # Extracts positive instance dimensions from the visual transform.
        var collision_node: CollisionShape3D = CollisionShape3D.new() # Allocates one shape node attached directly to this StaticBody3D.
        if placement.kind == WorldDecorationPlacement.Kind.TREE: # Creates a narrow solid trunk while leaving foliage non-solid.
            var trunk_shape: CylinderShape3D = CylinderShape3D.new() # Allocates the smooth trunk collision primitive.
            trunk_shape.height = TREE_COLLISION_HEIGHT * visual_scale.y # Matches the visible trunk's scaled vertical extent.
            trunk_shape.radius = TREE_COLLISION_RADIUS * maxf(visual_scale.x, visual_scale.z) # Matches the visible trunk's broadest scaled radius.
            collision_node.name = "TreeCollision" # Gives tree collision a useful diagnostic name.
            collision_node.shape = trunk_shape # Assigns the configured smooth cylinder.
            collision_node.position = placement.transform.origin + Vector3.UP * trunk_shape.height * 0.5 # Centres the cylinder above the tree's ground-level origin.
        else: # Creates a rounded conservative collision volume for an irregular boulder.
            var boulder_shape: SphereShape3D = SphereShape3D.new() # Allocates an inexpensive smooth collision primitive.
            boulder_shape.radius = maxf(visual_scale.x, maxf(visual_scale.y, visual_scale.z)) * BOULDER_COLLISION_RADIUS_FACTOR # Covers the deformed shared rock silhouette.
            collision_node.name = "BoulderCollision" # Gives rock collision a useful diagnostic name.
            collision_node.shape = boulder_shape # Assigns the configured rounded volume.
            collision_node.position = placement.transform.origin # Aligns collision with the visible embedded boulder centre.
        add_child(collision_node) # Attaches the shape directly to this StaticBody3D.
        _collision_shapes.append(collision_node) # Retains the node for immediate release outside the collision radius.

func _clear_collisions() -> void: # Removes all nearby object collision while preserving batched visuals.
    for collision_node: CollisionShape3D in _collision_shapes: # Visits every currently active tree or rock shape.
        remove_child(collision_node) # Detaches it immediately so it no longer participates in physics.
        collision_node.queue_free() # Releases the shape node and resource at the end of the frame.
    _collision_shapes.clear() # Resets the active set for future re-entry into the collision radius.
