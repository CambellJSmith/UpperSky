extends SceneTree # Verify scenery buffers and retained city hierarchy.

func _initialize() -> void: # Start after scene initialization.
    _run.call_deferred() # Allow asynchronous batching to use frame signals.

func _fixture() -> Node3D: # Prepare varied static and interactive geometry.
    var city: Node3D = Node3D.new() # Own the test scene.
    var holder: Node3D = Node3D.new() # Exercise nested transforms.
    holder.position = Vector3(13, 2, -9) # Move the nested geometry.
    holder.rotation.y = .4 # Rotate the nested geometry.
    city.add_child(holder) # Retain the parent hierarchy.
    for index: int in 48: # Populate several culling neighbourhoods.
        var node: MeshInstance3D = MeshInstance3D.new() # Create source scenery.
        var geometry: BoxMesh = BoxMesh.new() # Supply indexed hard-edged triangles.
        node.mesh = geometry # Assign the primitive.
        node.position = Vector3(index * 4, 0, index % 3 * 20) # Spread geometry across sectors.
        node.scale = Vector3(1, 2, 3) # Exercise inverse-transpose normal handling.
        node.rotation.y = index * .1 # Exercise local rotation.
        var material: StandardMaterial3D = StandardMaterial3D.new() # Define flat scenery shading.
        material.albedo_color = Color(index / 48.0, .4, .7) # Exercise palette preservation.
        material.roughness = .92 # Define compatible batch shading.
        node.material_override = material # Assign effective source shading.
        node.set_meta("house_parameters", {"seed": index}) # Exercise retained building metadata.
        node.add_child(StaticBody3D.new()) # Exercise retained collision ownership.
        holder.add_child(node) # Attach nested static scenery.
    var actor: RigidBody3D = RigidBody3D.new() # Exercise dynamic subtree exclusion.
    actor.name = "DynamicActor" # Identify the excluded subtree.
    var actor_mesh: MeshInstance3D = MeshInstance3D.new() # Supply interactive geometry.
    actor_mesh.mesh = BoxMesh.new() # Assign its mesh.
    actor.add_child(actor_mesh) # Keep geometry inside the dynamic subtree.
    city.add_child(actor) # Attach the excluded actor.
    var special: MeshInstance3D = MeshInstance3D.new() # Exercise unsupported material preservation.
    special.name = "TransparentScenery" # Identify special rendering.
    special.mesh = BoxMesh.new() # Supply special geometry.
    var transparent: StandardMaterial3D = StandardMaterial3D.new() # Define transparent shading.
    transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA # Require independent rendering.
    special.material_override = transparent # Assign special shading.
    city.add_child(special) # Attach the unsupported mesh.
    return city # Return a complete test hierarchy.

func _expected(city: Node3D) -> Dictionary: # Record transformed source buffers before batching.
    var groups: Dictionary = {} # Mirror existing neighbourhood boundaries.
    var holder: Node3D = city.get_child(0) # Resolve the nested source hierarchy.
    for node: MeshInstance3D in holder.get_children(): # Record every eligible source primitive.
        var transform: Transform3D = holder.transform * node.transform # Compose root-local transforms.
        var sector: Vector2i = Vector2i(floori(transform.origin.x / 48), floori(transform.origin.z / 48)) # Resolve the culling sector.
        var key: String = "%s:%.3f" % [sector, .92] # Resolve the expected batch group.
        if not groups.has(key): # Prepare an ordered group.
            groups[key] = [] # Retain expected vertices.
        var arrays: Array = node.mesh.surface_get_arrays(0) # Read authored geometry.
        var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] # Read source positions.
        var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] # Read hard normals.
        var basis: Basis = transform.basis.inverse().transposed() # Prepare correct normal transformation.
        for index: int in vertices.size(): # Retain every unique source vertex.
            groups[key].append([transform * vertices[index], (basis * normals[index]).normalized(), node.material_override.albedo_color]) # Record geometry and colour together.
    return groups # Return ordered expected output.

func _check(city: Node3D, expected: Dictionary) -> void: # Verify buffers, topology and retained scene data.
    var batch_index: int = 0 # Track output group order.
    for child: Node in city.get_children(): # Inspect root-level output meshes.
        if not str(child.name).begins_with("SceneryBatch"): # Skip original scene nodes.
            continue # Inspect only generated neighbourhoods.
        var arrays: Array = child.mesh.surface_get_arrays(0) # Read final GPU buffers.
        var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] # Read positions.
        var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] # Read normals.
        var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] # Read baked colours.
        var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] # Read indexed topology.
        var records: Array = expected[expected.keys()[batch_index]] # Resolve expected group vertices.
        assert(vertices.size() == records.size()) # Preserve unique source vertices.
        assert(indices.size() == vertices.size() / 24 * 36) # Preserve box triangle topology.
        for index: int in vertices.size(): # Compare every output vertex.
            assert(vertices[index].distance_to(records[index][0]) < .001) # Preserve composed positions.
            assert(normals[index].distance_to(records[index][1]) < .001) # Preserve hard normals under scaling.
            assert(colors[index].is_equal_approx(records[index][2])) # Preserve each source palette.
        for index: int in indices: # Validate rebased topology.
            assert(index >= 0 and index < vertices.size()) # Keep all references within the batch.
        batch_index += 1 # Advance expected group order.
    assert(batch_index == expected.size()) # Preserve neighbourhood draw-call grouping.
    for node: MeshInstance3D in city.get_child(0).get_children(): # Inspect original building nodes.
        assert(node.mesh == null and node.has_meta("house_parameters")) # Release rendering while retaining metadata.
        assert(node.get_child(0) is StaticBody3D) # Preserve physics ownership.
    assert(city.get_node("DynamicActor").get_child(0).mesh != null) # Preserve dynamic rendering.
    assert(city.get_node("TransparentScenery").mesh != null) # Preserve unsupported materials.

func _run() -> void: # Cover immediate and frame-spread construction.
    var immediate: Node3D = _fixture() # Prepare synchronous source geometry.
    var expected: Dictionary = _expected(immediate) # Capture authored source buffers.
    CityStaticBatch.build_sync(immediate) # Execute immediate batching.
    _check(immediate, expected) # Verify the synchronous output.
    immediate.free() # Release the immediate test hierarchy.
    var incremental: Node3D = _fixture() # Prepare asynchronous source geometry.
    expected = _expected(incremental) # Capture its authored source buffers.
    assert(await CityStaticBatch.build(incremental, self)) # Complete frame-spread batching.
    _check(incremental, expected) # Verify identical asynchronous output.
    incremental.free() # Release the asynchronous test hierarchy.
    print("PASS city batching positions, normals, colours, topology, neighbourhoods, metadata, collision and dynamic exclusions") # Report successful regression coverage.
    quit() # Finish the test process.
