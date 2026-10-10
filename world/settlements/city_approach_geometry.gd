extends RefCounted # Build a continuous terrain-fitted city approach with matching solid collision.
class_name CityApproachGeometry # Keep ramp geometry separate from city scenery and ground sampling.

static func build(root: Node3D, profile: Array, color: Color) -> void: # Join each pair of sampled approach edges with a supported stone wedge.
    var material: StandardMaterial3D = StandardMaterial3D.new() # Share one material across the bounded ramp sections.
    material.albedo_color = color # Match the retained foundation stone.
    material.roughness = 0.92 # Preserve the exterior's matte finish.
    for index: int in range(profile.size() - 1): # Build only the prepared adjacent approach sections.
        var start: Dictionary = profile[index] # Resolve the preceding walking edge.
        var finish: Dictionary = profile[index + 1] # Resolve the following walking edge.
        var bottom: float = minf(minf(float(start.bottom), float(finish.bottom)), minf(float(start.top), float(finish.top)) - 0.5) # Keep each solid wedge embedded below both endpoint grounds.
        var vertices: PackedVector3Array = PackedVector3Array([Vector3(-5, start.top, start.z), Vector3(5, start.top, start.z), Vector3(5, finish.top, finish.z), Vector3(-5, finish.top, finish.z), Vector3(-5, bottom, start.z), Vector3(5, bottom, start.z), Vector3(5, bottom, finish.z), Vector3(-5, bottom, finish.z)]) # Keep both walking endpoints exact instead of rotating an approximate box.
        var triangles: PackedInt32Array = PackedInt32Array([0,1,2,0,2,3,4,7,6,4,6,5,0,4,5,0,5,1,3,2,6,3,6,7,0,3,7,0,7,4,1,5,6,1,6,2]) # Close the convex prism with outward-facing triangle winding.
        var surface: SurfaceTool = SurfaceTool.new() # Create one small static ramp section.
        surface.begin(Mesh.PRIMITIVE_TRIANGLES) # Supply ordinary batch-compatible triangle geometry.
        for vertex: int in triangles: # Copy each face corner with hard edge normals.
            surface.add_vertex(vertices[vertex]) # Preserve the precomputed support and walking heights.
        surface.generate_normals() # Generate correct face normals for the sloped walking surface.
        var mesh: MeshInstance3D = MeshInstance3D.new() # Compose a normal static scenery mesh.
        mesh.mesh = surface.commit() # Upload the bounded section geometry.
        mesh.material_override = material # Reuse the shared city stone material.
        root.add_child(mesh) # Attach the ramp in the exterior's existing local coordinates.
        var body: StaticBody3D = StaticBody3D.new() # Keep the walking collision static and solid.
        var collision: CollisionShape3D = CollisionShape3D.new() # Compose the matching physics shape.
        var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new() # Use the exact supported prism as a solid collider.
        shape.points = vertices # Match all collision vertices to the visible stone wedge.
        collision.shape = shape # Assign the identical prepared geometry to physics.
        body.add_child(collision) # Attach the wedge shape to its static owner.
        mesh.add_child(body) # Preserve collision ownership through normal city scenery batching.
