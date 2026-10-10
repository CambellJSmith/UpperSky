extends RefCounted # Own the static scenery batching helpers.
class_name CityStaticBatch # Share batching between city interiors and exteriors.

class SceneryBatch extends RefCounted: # Accumulate indexed geometry without temporary mesh resources.
    var vertices: PackedVector3Array = PackedVector3Array() # Store positions in city coordinates.
    var normals: PackedVector3Array = PackedVector3Array() # Preserve the source hard edges.
    var colors: PackedColorArray = PackedColorArray() # Retain each building's palette.
    var indices: PackedInt32Array = PackedInt32Array() # Retain shared vertices within each source surface.
    var material: StandardMaterial3D # Retain the batch rendering material.

    func _init(roughness: float) -> void: # Prepare the shared opaque material.
        material = StandardMaterial3D.new() # Allocate one material per neighbourhood and roughness.
        material.roughness = roughness # Preserve surface roughness.
        material.vertex_color_use_as_albedo = true # Read the baked building colours.

    func append(arrays: Array, transform: Transform3D, color: Color) -> void: # Copy a surface directly into the accumulated arrays.
        var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] # Read source positions.
        var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] # Read source normals.
        var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array() # Support indexed and unindexed triangles.
        var offset: int = vertices.size() # Locate this surface in the combined vertex buffer.
        var normal_basis: Basis = transform.basis.inverse().transposed() # Correct normals under nonuniform scale.
        for index: int in source_vertices.size(): # Preserve unique source vertices instead of expanding triangle corners.
            vertices.append(transform * source_vertices[index]) # Bake the hierarchy transform.
            normals.append((normal_basis * source_normals[index]).normalized()) # Retain correctly oriented hard normals.
            colors.append(color) # Bake the flat material colour.
        if source_indices.is_empty(): # Supply indices for unindexed triangle geometry.
            for index: int in source_vertices.size(): # Reference each existing triangle corner.
                indices.append(offset + index) # Rebase the source vertex.
        else: # Preserve the source topology.
            for index: int in source_indices: # Visit the source triangle indices.
                indices.append(offset + index) # Rebase each shared vertex reference.

    func commit() -> ArrayMesh: # Upload the combined buffers once.
        var arrays: Array = [] # Prepare the Godot surface layout.
        arrays.resize(Mesh.ARRAY_MAX) # Reserve every surface channel.
        arrays[Mesh.ARRAY_VERTEX] = vertices # Supply baked positions.
        arrays[Mesh.ARRAY_NORMAL] = normals # Supply baked normals.
        arrays[Mesh.ARRAY_COLOR] = colors # Supply building colours.
        arrays[Mesh.ARRAY_INDEX] = indices # Supply the retained topology.
        var mesh: ArrayMesh = ArrayMesh.new() # Allocate only the final mesh resource.
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays) # Upload one indexed surface.
        mesh.surface_set_material(0, material) # Attach the neighbourhood material.
        return mesh # Return the completed static batch.

static func build(root: Node3D, tree: SceneTree = null, scheduler: GenerationScheduler = null, owner: Node = null) -> bool: # Spread batching work across scheduled frames.
    if tree == null: # Use the city's scene tree when none is supplied.
        tree = root.get_tree() # Resolve the frame signal provider.
    var meshes: Array[Dictionary] = [] # Retain the original mesh traversal order.
    _collect(root, Transform3D.IDENTITY, meshes) # Preserve physics and building metadata.
    var groups: Dictionary = {} # Group opaque geometry by neighbourhood and roughness.
    var processed: int = 0 # Track work since the last checkpoint.
    for entry: Dictionary in meshes: # Visit each static source mesh.
        _append(entry, groups) # Copy eligible surfaces into packed buffers.
        processed += 1 # Advance the checkpoint counter.
        if processed % 24 == 0: # Keep generation responsive between groups of source nodes.
            if scheduler != null: # Respect shared generation scheduling.
                if not await scheduler.checkpoint(owner): # Stop when the owner is cancelled.
                    return false # Let the caller discard the incomplete city.
            else: # Support loading-screen construction without a scheduler.
                await tree.process_frame # Yield until the next frame.
    for key: String in groups: # Upload each neighbourhood separately for spatial culling.
        if scheduler != null: # Share upload admission with terrain and procedural houses.
            if not await scheduler.operation_checkpoint(owner): return false # Cancel before uploading an obsolete neighbourhood.
        var started: int = Time.get_ticks_usec() # Measure the indivisible neighbourhood upload.
        _commit(root, groups[key]) # Add the completed batch.
        if scheduler != null: scheduler.record_operation(started) # Report oversized batch commits.
        else: await tree.process_frame # Retain loading-screen construction without a scheduler.
    return true # Report completed scenery preparation.

static func build_sync(root: Node3D) -> void: # Support immediate exterior and test construction.
    var meshes: Array[Dictionary] = [] # Retain static source meshes.
    _collect(root, Transform3D.IDENTITY, meshes) # Traverse the existing hierarchy.
    var groups: Dictionary = {} # Accumulate neighbourhood buffers.
    for entry: Dictionary in meshes: # Visit each source mesh.
        _append(entry, groups) # Bake its eligible geometry.
    for key: String in groups: # Visit the completed neighbourhoods.
        _commit(root, groups[key]) # Upload their buffers.

static func _append(entry: Dictionary, groups: Dictionary) -> void: # Batch opaque flat-colour scenery while retaining its node.
    var node: MeshInstance3D = entry.node # Read the source mesh instance.
    var transform: Transform3D = entry.transform # Read its transform relative to the city root.
    if is_zero_approx(transform.basis.determinant()): # Avoid undefined normal transforms.
        return # Retain degenerate source geometry unchanged.
    var surfaces: Array[Array] = [] # Read each eligible surface once.
    for surface: int in node.mesh.get_surface_count(): # Validate the whole mesh before modifying it.
        var material: StandardMaterial3D = node.get_active_material(surface) as StandardMaterial3D # Inspect the effective material.
        if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_texture != null: # Leave special rendering on its original mesh.
            return # Preserve all surfaces of unsupported meshes.
        if node.mesh is ArrayMesh and node.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: # Require triangle topology.
            return # Retain other primitive types unchanged.
        var arrays: Array = node.mesh.surface_get_arrays(surface) # Read the source buffers once.
        if arrays[Mesh.ARRAY_NORMAL] == null or arrays[Mesh.ARRAY_NORMAL].size() != arrays[Mesh.ARRAY_VERTEX].size(): # Require authored normals for flat scenery.
            return # Retain unsupported vertex layouts unchanged.
        surfaces.append(arrays) # Retain buffers for the copy pass.
    var sector: Vector2i = Vector2i(floori(transform.origin.x / 48), floori(transform.origin.z / 48)) # Preserve neighbourhood culling boundaries.
    for surface: int in surfaces.size(): # Copy each validated surface.
        var material: StandardMaterial3D = node.get_active_material(surface) as StandardMaterial3D # Read its flat colour and roughness.
        var key: String = "%s:%.3f" % [sector, material.roughness] # Preserve the existing batch grouping.
        if not groups.has(key): # Create a buffer accumulator only when needed.
            groups[key] = SceneryBatch.new(material.roughness) # Share one output material for the group.
        var batch: SceneryBatch = groups[key] # Resolve the reference-owned mutable buffers.
        batch.append(surfaces[surface], transform, material.albedo_color) # Bake geometry without an intermediate ArrayMesh or SurfaceTool.
    node.mesh = null # Release source rendering while keeping metadata and collision children.

static func _commit(root: Node3D, batch: SceneryBatch) -> void: # Attach one neighbourhood mesh.
    var node: MeshInstance3D = MeshInstance3D.new() # Allocate the final rendering node.
    node.name = "SceneryBatch_%d" % root.get_child_count() # Preserve batch naming for inspection.
    node.mesh = batch.commit() # Upload the completed packed arrays.
    root.add_child(node) # Add the batch without moving existing children.

static func _collect(node: Node, transform: Transform3D, output: Array[Dictionary]) -> void: # Gather static scenery in root-local coordinates.
    for child: Node in node.get_children(): # Walk the original scene hierarchy.
        if child is Villager or child is LootChest or child is RigidBody3D: # Exclude actors and interactive physics objects.
            continue # Preserve their independent rendering.
        var next: Transform3D = transform * child.transform if child is Node3D else transform # Compose nested spatial transforms.
        if child is MeshInstance3D and child.mesh != null: # Collect only populated mesh instances.
            output.append({"node": child, "transform": next}) # Retain the mesh and its city-local transform.
        _collect(child, next, output) # Preserve nested building geometry.
