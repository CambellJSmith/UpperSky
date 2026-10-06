extends SceneTree
func _initialize(): run.call_deferred()
func signature(house: Node3D) -> Array:
    var hashes: Array = []
    for child in house.get_children():
        if child is MeshInstance3D:
            hashes.append(hash(var_to_bytes(child.mesh.surface_get_arrays(0))))
    return hashes
func validate(house: Node3D):
    assert(house.get_meta("footprint").size.x > 4)
    assert(house.get_meta("bounds").size.y > 4)
    var mesh_count = 0
    var vertex_count = 0
    for child in house.get_children():
        if child is MeshInstance3D:
            mesh_count += 1
            assert(child.mesh.get_surface_count() == 1)
            var arrays = child.mesh.surface_get_arrays(0)
            var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
            vertex_count += vertices.size()
            assert(vertices.size()%3 == 0 and vertices.size() == normals.size())
            assert(child.mesh.get_aabb().size.y < 24.0)
            for i in range(0,vertices.size(),3):
                var a = vertices[i]
                var b = vertices[i+1]
                var c = vertices[i+2]
                assert(a.is_finite() and b.is_finite() and c.is_finite())
                assert(normals[i].is_normalized())
                assert((b-a).cross(c-a).length_squared() > 0.000000001)
                assert((b-a).cross(c-a).dot(normals[i]) < 0)
    assert(mesh_count <= 37 and mesh_count >= 10)
    assert(vertex_count < 500000)
func run():
    var recipes: Array[HouseRecipe] = []
    var distinct: Dictionary = {}
    for layout in range(1,7):
        for wall in range(1,5):
            for roof in range(1,3):
                var recipe = HouseRecipe.new()
                recipe.seed_value = layout*100+wall*10+roof
                recipe.layout = layout
                recipe.wall_style = wall
                recipe.roof_style = roof
                var house = HouseGeometry.new().build(recipe)
                assert(house.get_meta("chimney_count") == 1)
                assert(house.get_node("SolidHouseCollision").get_child_count() >= 4)
                validate(house)
                distinct[hash(var_to_bytes(signature(house)))] = true
                house.free()
                recipes.append(recipe)
    assert(distinct.size() == 48)
    var recipe = recipes[0]
    var first = HouseGeometry.new().build(recipe)
    var second = HouseGeometry.new().build(recipe)
    assert(signature(first) == signature(second))
    first.free()
    second.free()
    recipe = HouseRecipe.new()
    recipe.width = 14
    recipe.depth = 18
    recipe.floors = 3
    recipe.layout = HouseRecipe.Layout.CROSS
    recipe.include_chimney = false
    recipe.include_porch = false
    var builder = HouseGeometry.new()
    first = builder.build(recipe,false)
    assert(first.get_meta("house_parameters")["width"] == 14)
    assert(not first.has_meta("chimney_count"))
    assert(first.get_node_or_null("SolidHouseCollision") == null)
    validate(first)
    first.free()
    var node = ProceduralHouse.new()
    node.recipe = HouseRecipe.new()
    root.add_child(node)
    var old = signature(node.generated)
    node.recipe.seed_value += 1
    await process_frame
    await process_frame
    assert(signature(node.generated) != old)
    assert(node.get_child_count() == 1)
    # Solid exterior walls and the roof must block ordinary world physics rays.
    await physics_frame
    var world = node.get_world_3d().direct_space_state
    var parameters = node.get_meta("house_parameters")
    var w: float = parameters["width"]
    var d: float = parameters["depth"]
    for from in [Vector3(w+20,1.5,0),Vector3(-w-20,1.5,0),Vector3(0,1.5,d+20),Vector3(0,1.5,-d-20),Vector3(0,30,0)]:
        var query = PhysicsRayQueryParameters3D.create(from,Vector3(0,1.5,0))
        assert(not world.intersect_ray(query).is_empty())
    node.queue_free()
    await process_frame
    print("PASS: 48 layout/material/roof combinations, deterministic meshes, valid normals/winding, bounded mesh counts, dimension overrides, collision and live regeneration.")
    quit()
