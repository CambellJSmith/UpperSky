extends SceneTree
func _initialize(): run.call_deferred()
func run():
    var library = WorldDecorationMeshLibrary.new()
    var builder = TreeGeometry.new()
    var signatures: Dictionary = {}
    var counts: Array = []
    var placements: Array[WorldDecorationPlacement] = []
    for variant in range(TreeGeometry.VARIANT_COUNT):
        var previous = 100000
        var budget: Array = []
        for lod in range(3):
            var mesh = library.get_tree_mesh(lod,variant)
            assert(mesh == library.get_tree_mesh(lod,variant))
            var rebuilt = builder.build(variant,lod)
            var triangles = 0
            for surface in range(mesh.get_surface_count()):
                var arrays = mesh.surface_get_arrays(surface)
                var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
                var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
                assert(vertices == rebuilt.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
                assert(vertices.size() == normals.size())
                assert(arrays[Mesh.ARRAY_COLOR].size() == vertices.size())
                for i in range(0,vertices.size(),3):
                    assert(vertices[i].is_finite())
                    var cross = (vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i])
                    assert(cross.length_squared() > 0.00000001)
                    assert(cross.normalized().dot(normals[i]) < -.99)
                    assert(normals[i].is_equal_approx(normals[i+1]))
                triangles += vertices.size()/3
            assert(triangles < previous)
            previous = triangles
            budget.append(triangles)
            if lod == 0:
                var signature = hash(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
                assert(not signatures.has(signature))
                signatures[signature] = true
        counts.append(budget)
        var path = TreeGeometry.trunk_path(variant)
        var parts = library.get_tree_collision_parts(variant)
        assert(parts.size() == path.size()-1)
        for i in range(parts.size()):
            var direction: Vector3 = path[i+1]-path[i]
            var transform: Transform3D = parts[i].transform
            assert(transform.origin.is_equal_approx((path[i]+path[i+1])*.5))
            assert((transform.basis*Vector3.UP).dot(direction.normalized()) > .999)
        var placement = WorldDecorationPlacement.new(WorldDecorationPlacement.Kind.TREE,variant,Transform3D.IDENTITY)
        placement.kind = WorldDecorationPlacement.Kind.TREE
        placement.variant = variant
        placement.transform = Transform3D(Basis(Vector3.UP,.7).scaled(Vector3(.9,1.3,.9)),Vector3(variant*25,0,0))
        placements.append(placement)
    var chunk = WorldDecorationChunk.new()
    root.add_child(chunk)
    chunk.configure(placements,library,0)
    chunk.set_collision_active(true)
    assert(chunk.get_shape_owners().size() == 32)
    for lod in range(3):
        chunk.set_lod_level(lod)
        assert(chunk._visual_nodes.size() == 16)
        assert(chunk.get_shape_owners().size() == 32)
        for node in chunk._visual_nodes:
            var mm: MultiMesh = node.multimesh
            var expected = placements[int(str(node.name).split("_")[1])].transform*mm.mesh.get_aabb()
            assert(mm.custom_aabb.grow(.001).encloses(expected))
    await physics_frame
    await physics_frame
    for placement in placements:
        var path = TreeGeometry.trunk_path(placement.variant)
        var mid = placement.transform*((path[0]+path[1])*.5)
        var query = PhysicsRayQueryParameters3D.create(mid+Vector3(-3,0,0),mid+Vector3(3,0,0))
        assert(not chunk.get_world_3d().direct_space_state.intersect_ray(query).is_empty())
    chunk.set_collision_active(false)
    assert(chunk.get_shape_owners().is_empty())
    chunk.free()
    print("PASS: 16 unique deterministic forms, all 48 flat-shaded LOD meshes, winding, bounds, bent/scaled trunk ray collisions and unloading. Triangle counts: ",counts)
    quit()
