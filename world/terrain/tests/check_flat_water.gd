extends SceneTree

func _initialize() -> void:
    call_deferred("check")

func check() -> void:
    var terrain := SeamlessInfiniteTerrain.new()
    terrain._height_sampler = SeamlessTerrainHeightSampler.new()
    terrain._water_level_sampler = SeamlessTerrainWaterLevelSampler.new()
    var builder := SeamlessTerrainWaterMeshBuilder.new(terrain._height_sampler, terrain._water_level_sampler, StandardMaterial3D.new())
    var triangles := 0
    var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(-1,-1), Vector2i((WaterBodyPlan.STARTING_LAKE_CENTRE / TerrainConfiguration.CHUNK_SIZE).floor())] # Includes the explicitly planned starting basin.
    for region_cell in [Vector2i.ZERO, Vector2i(-1,0), Vector2i(0,-1)]:
        var definition := BiomeProfile.region(region_cell)
        var centre: Vector2 = definition.centre
        for offset in [Vector2.ZERO, Vector2(0,-320), Vector2(0,320), Vector2(1400,0)]:
            var cell := Vector2i(((centre + offset) / TerrainConfiguration.CHUNK_SIZE).floor())
            for z in range(-1,2):
                for x in range(-1,2):
                    cells.append(cell + Vector2i(x,z))
    for cell in cells:
        var arrays := builder.build_chunk_arrays(cell)
        if arrays.is_empty(): continue
        var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
        for index in range(0, vertices.size(), 3):
            var a := vertices[index]
            var b := vertices[index+1]
            var c := vertices[index+2]
            assert(absf(a.y-b.y)<0.0001 and absf(a.y-c.y)<0.0001, "Inclined water triangle")
            assert(normals[index].is_equal_approx(Vector3.UP))
            for vertex: Vector3 in [a, b, c]: # Inspects surface endpoints rather than only triangle interiors.
                var absolute: Vector2 = Vector2(vertex.x, vertex.z) + Vector2(cell) * TerrainConfiguration.CHUNK_SIZE # Restores each endpoint to stable world coordinates.
                assert(WaterBodyPlan.boundary_at(absolute) > 0.01, "Water reaches an open footprint wall instead of a containing shore") # Requires ground clipping to end water inside the protected basin boundary.
            var midpoint := (a+b+c)/3.0
            var point := Vector2(midpoint.x,midpoint.z) + Vector2(cell)*TerrainConfiguration.CHUNK_SIZE
            assert(absf(terrain.get_water_level_at(point)-a.y)<0.001, "Gameplay differs from mesh")
            assert(terrain.has_water_at(point), "Rendered water missing from gameplay")
            triangles += 1
    assert(triangles>1000)
    var river := BiomeProfile.region(Vector2i(-1,0))
    var centre: Vector2 = river.centre
    for local_z in [-600.0,-320.01,-319.99,-304.01,-303.99,0.0,319.99,320.01,335.99,336.01,600.0]:
        var point := centre+Vector2(BiomeProfile.river_x(local_z, river.phase),local_z)
        var expected: float = river.sea + (64.0 if local_z < -320.0 else (32.0 if local_z<320.0 else 0.0))
        assert(is_equal_approx(terrain.get_water_level_at(point),expected), "River reach/pool height")
    # Flat height within cells, including negative coordinates and chunk seams.
    for point in [Vector2(-256.01,-16.01),Vector2(255.99,255.99),centre+Vector2(16,48)]:
        var origin: Vector2 = (point/WaterBodyPlan.GRID_SPACING).floor()*WaterBodyPlan.GRID_SPACING # Uses the actual final ground lattice.
        var height: float = WaterBodyPlan.definition_at(origin+Vector2.ONE*4.0).surface_height # Tests planned calm levels independently from dry occupancy.
        for offset in [Vector2(7.99,.01),Vector2(.01,7.99),Vector2(7.99,7.99)]:
            assert(is_equal_approx(height,float(WaterBodyPlan.definition_at(origin+offset).surface_height))) # Verifies the reach stays flat across the ground cell.
    terrain.free()
    print("PASS: ",triangles," horizontal water triangles; shoreline/gameplay parity; river levels and chunk boundaries")
    quit()
