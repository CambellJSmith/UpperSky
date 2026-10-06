extends RefCounted
class_name CityStaticBatch

# Preserve building metadata and physics children, but combine opaque scenery
# by material and neighbourhood so rendering can cull distant blocks separately.
static func build(root: Node3D, tree: SceneTree = null, scheduler: GenerationScheduler = null, owner: Node = null) -> bool:
    if tree == null: tree = root.get_tree()
    var meshes: Array[Dictionary] = []
    _collect(root,Transform3D.IDENTITY,meshes)
    var groups: Dictionary = {}
    var processed := 0
    for entry in meshes:
        _append(entry,groups)
        processed += 1
        if processed%24 == 0:
            if scheduler != null:
                if not await scheduler.checkpoint(owner): return false
            else: await tree.process_frame
    for key in groups:
        _commit(root,groups[key])
        if scheduler != null:
            if not await scheduler.checkpoint(owner): return false
        else: await tree.process_frame
    return true

static func build_sync(root: Node3D) -> void:
    var meshes: Array[Dictionary] = []
    _collect(root,Transform3D.IDENTITY,meshes)
    var groups: Dictionary = {}
    for entry in meshes: _append(entry,groups)
    for key in groups: _commit(root,groups[key])

static func _append(entry: Dictionary, groups: Dictionary) -> void:
    var node: MeshInstance3D = entry.node
    var transform: Transform3D = entry.transform
    for surface in node.mesh.get_surface_count():
        var material := node.get_active_material(surface) as StandardMaterial3D
        if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_texture != null: return
    var sector := Vector2i(floori(transform.origin.x/48),floori(transform.origin.z/48))
    for surface in node.mesh.get_surface_count():
        var material := node.get_active_material(surface) as StandardMaterial3D
        var key := "%s:%.3f"%[sector,material.roughness]
        if not groups.has(key):
            var tool := SurfaceTool.new()
            tool.begin(Mesh.PRIMITIVE_TRIANGLES)
            var batch_material := StandardMaterial3D.new()
            batch_material.roughness = material.roughness
            batch_material.vertex_color_use_as_albedo = true
            tool.set_material(batch_material)
            groups[key] = tool
        # Bake each flat colour into vertices so differently coloured houses
        # can share a draw call without losing their palette or hard normals.
        var arrays := node.mesh.surface_get_arrays(surface)
        var colors := PackedColorArray()
        colors.resize(arrays[Mesh.ARRAY_VERTEX].size())
        colors.fill(material.albedo_color)
        arrays[Mesh.ARRAY_COLOR] = colors
        var colored_mesh := ArrayMesh.new()
        colored_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
        groups[key].append_from(colored_mesh,0,transform)
    node.mesh = null

static func _commit(root: Node3D, tool: SurfaceTool) -> void:
    var node := MeshInstance3D.new()
    node.name = "SceneryBatch_%d"%root.get_child_count()
    node.mesh = tool.commit()
    root.add_child(node)

static func _collect(node: Node, transform: Transform3D, output: Array[Dictionary]) -> void:
    for child in node.get_children():
        if child is Villager or child is LootChest or child is RigidBody3D: continue
        var next: Transform3D = transform * child.transform if child is Node3D else transform
        if child is MeshInstance3D and child.mesh != null:
            output.append({"node":child,"transform":next})
        _collect(child,next,output)
