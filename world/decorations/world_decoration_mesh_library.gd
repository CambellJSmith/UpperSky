extends RefCounted # Builds and retains the shared smooth meshes used by streamed trees and boulders.
class_name WorldDecorationMeshLibrary # Makes reusable decoration geometry available to every terrain chunk.

const BOULDER_VARIANT_COUNT: int = 3 # Provides several distinct silhouettes without creating unique geometry for every placed rock.
const TREE_TRUNK_HEIGHT: float = 7.2 # Defines the unscaled visible trunk height used by rendering and collision approximation.
const TREE_TRUNK_BASE_RADIUS: float = 0.72 # Defines the unscaled lower trunk radius.
const TREE_TRUNK_TOP_RADIUS: float = 0.38 # Tapers the trunk toward the canopy instead of producing a cylinder.

var _tree_mesh: ArrayMesh # Stores the shared smooth trunk, branches, and canopy geometry.
var _boulder_meshes: Array[ArrayMesh] = [] # Stores the shared irregular rounded boulder variations.
var _trunk_material: StandardMaterial3D # Shades every trunk and branch surface.
var _foliage_material: StandardMaterial3D # Shades every smooth foliage volume.
var _boulder_material: StandardMaterial3D # Shades every rounded rock variation.

func _init() -> void: # Builds all shared decoration geometry once for the complete streamed world.
    _trunk_material = _create_material(Color(0.20, 0.105, 0.045, 1.0), 0.96) # Creates a dark matte bark material.
    _foliage_material = _create_material(Color(0.075, 0.24, 0.075, 1.0), 0.92) # Creates dense desaturated green foliage.
    _boulder_material = _create_material(Color(0.28, 0.29, 0.285, 1.0), 0.98) # Creates a neutral weathered stone material.
    _tree_mesh = _build_tree_mesh() # Builds one multi-surface smooth tree mesh shared by all tree instances.
    for variant: int in range(BOULDER_VARIANT_COUNT): # Builds each authored boulder silhouette once.
        _boulder_meshes.append(_build_boulder_mesh(variant)) # Retains the smooth irregular rock geometry for chunk MultiMeshes.

func get_tree_mesh() -> ArrayMesh: # Returns the shared smooth tree geometry.
    return _tree_mesh # Reuses one mesh resource for every streamed tree instance.

func get_boulder_mesh(variant: int) -> ArrayMesh: # Returns one shared rounded boulder variation.
    if _boulder_meshes.is_empty(): # Handles unexpected access before construction defensively.
        return null # Reports that no boulder geometry is available.
    return _boulder_meshes[posmod(variant, _boulder_meshes.size())] # Wraps the requested variation into the available range.

func get_boulder_variant_count() -> int: # Reports how many shared boulder silhouettes are available.
    return _boulder_meshes.size() # Supplies the count used when grouping MultiMesh instances.

func _build_tree_mesh() -> ArrayMesh: # Combines tapered cylinders and rounded foliage volumes into one non-cubic tree mesh.
    var tree_mesh: ArrayMesh = ArrayMesh.new() # Allocates the multi-surface result shared by all tree instances.
    tree_mesh.resource_name = "SmoothProceduralTree" # Gives the generated resource a useful diagnostic name.

    var wood_surface: SurfaceTool = SurfaceTool.new() # Collects trunk and branch primitive surfaces into one material surface.
    wood_surface.begin(Mesh.PRIMITIVE_TRIANGLES) # Begins triangle geometry compatible with ordinary lighting and shadows.
    _append_cylinder(wood_surface, TREE_TRUNK_HEIGHT, TREE_TRUNK_BASE_RADIUS, TREE_TRUNK_TOP_RADIUS, Transform3D(Basis.IDENTITY, Vector3(0.0, TREE_TRUNK_HEIGHT * 0.5, 0.0))) # Adds the tapered main trunk with its base at ground level.
    _append_branch(wood_surface, Vector3(0.0, 5.0, 0.0), Vector3(2.2, 7.5, 0.7), 0.28, 0.12) # Adds one upward-reaching branch.
    _append_branch(wood_surface, Vector3(0.0, 5.8, 0.0), Vector3(-1.9, 8.3, -1.0), 0.25, 0.10) # Adds an opposing branch with a different elevation.
    _append_branch(wood_surface, Vector3(0.0, 6.4, 0.0), Vector3(0.8, 9.0, -1.9), 0.22, 0.09) # Adds a rear branch to break radial symmetry.
    wood_surface.commit(tree_mesh) # Adds the complete wood geometry as the first mesh surface.
    tree_mesh.surface_set_material(0, _trunk_material) # Applies bark to trunk and branches.

    var foliage_surface: SurfaceTool = SurfaceTool.new() # Collects overlapping rounded canopy masses into one second surface.
    foliage_surface.begin(Mesh.PRIMITIVE_TRIANGLES) # Begins lit triangle geometry for smooth foliage volumes.
    _append_foliage_blob(foliage_surface, Vector3(0.0, 9.0, 0.0), Vector3(3.4, 3.0, 3.2)) # Adds the principal canopy volume.
    _append_foliage_blob(foliage_surface, Vector3(1.7, 8.2, 0.7), Vector3(2.4, 2.2, 2.3)) # Extends foliage around the first major branch.
    _append_foliage_blob(foliage_surface, Vector3(-1.5, 8.7, -0.8), Vector3(2.3, 2.5, 2.1)) # Extends foliage around the opposing branch.
    _append_foliage_blob(foliage_surface, Vector3(0.6, 10.4, -1.2), Vector3(2.1, 2.0, 2.2)) # Adds an uneven upper crown.
    foliage_surface.commit(tree_mesh) # Adds the canopy as a separate material surface.
    tree_mesh.surface_set_material(1, _foliage_material) # Applies the foliage material without affecting bark.
    return tree_mesh # Returns the complete smooth tree resource.

func _append_cylinder(surface: SurfaceTool, height: float, bottom_radius: float, top_radius: float, transform: Transform3D) -> void: # Appends one tapered smooth cylinder to an active surface.
    var cylinder: CylinderMesh = CylinderMesh.new() # Allocates a temporary smooth primitive used only while building the shared mesh.
    cylinder.height = height # Sets the complete cylinder length along its local y axis.
    cylinder.bottom_radius = bottom_radius # Defines the wider lower end.
    cylinder.top_radius = top_radius # Defines the narrower upper end.
    cylinder.radial_segments = 10 # Keeps the silhouette rounded without excessive geometry.
    cylinder.rings = 3 # Provides vertical subdivisions for stable smooth normals.
    surface.append_from(cylinder, 0, transform) # Copies the primitive into the combined shared tree surface.

func _append_branch(surface: SurfaceTool, start: Vector3, end: Vector3, start_radius: float, end_radius: float) -> void: # Adds one tapered cylinder aligned between two arbitrary points.
    var direction: Vector3 = end - start # Calculates the branch axis and length.
    var length: float = direction.length() # Measures the required primitive height.
    if length <= 0.001: # Rejects degenerate branch descriptions.
        return # Avoids constructing an invalid zero-height cylinder.
    var branch_basis: Basis = _basis_from_y_axis(direction / length) # Rotates the cylinder's local y axis onto the branch direction.
    var midpoint: Vector3 = (start + end) * 0.5 # Positions the centered cylinder between its endpoints.
    _append_cylinder(surface, length, start_radius, end_radius, Transform3D(branch_basis, midpoint)) # Adds the aligned tapered branch.

func _append_foliage_blob(surface: SurfaceTool, centre: Vector3, scale: Vector3) -> void: # Appends one smooth ellipsoidal canopy mass.
    var sphere: SphereMesh = SphereMesh.new() # Allocates a temporary rounded primitive for the shared canopy mesh.
    sphere.radius = 1.0 # Uses a unit radius before the authored ellipsoid scale is applied.
    sphere.height = 2.0 # Keeps the unscaled primitive spherical.
    sphere.radial_segments = 10 # Keeps the canopy rounded while retaining an intentionally low-poly game silhouette.
    sphere.rings = 7 # Adds enough vertical segments to avoid block-like foliage.
    var blob_basis: Basis = Basis.IDENTITY.scaled(scale) # Stretches the sphere into an organic canopy mass.
    surface.append_from(sphere, 0, Transform3D(blob_basis, centre)) # Copies the smooth transformed volume into the foliage surface.

func _basis_from_y_axis(direction: Vector3) -> Basis: # Constructs an orthonormal basis whose local y axis follows the supplied direction.
    var y_axis: Vector3 = direction.normalized() # Normalizes the desired cylinder direction.
    var reference_axis: Vector3 = Vector3.RIGHT # Uses the world x axis unless it is nearly parallel to the branch.
    if absf(y_axis.dot(reference_axis)) > 0.92: # Detects a direction too parallel for a stable cross product.
        reference_axis = Vector3.FORWARD # Switches to a perpendicular reference axis.
    var z_axis: Vector3 = reference_axis.cross(y_axis).normalized() # Builds one perpendicular local axis.
    var x_axis: Vector3 = y_axis.cross(z_axis).normalized() # Builds the remaining perpendicular axis with consistent handedness.
    return Basis(x_axis, y_axis, z_axis) # Returns the cylinder-alignment basis.

func _build_boulder_mesh(variant: int) -> ArrayMesh: # Distorts a smooth sphere into one rounded, irregular, non-cubic boulder.
    var source_sphere: SphereMesh = SphereMesh.new() # Creates a temporary triangulated sphere with stable topology and winding.
    source_sphere.radius = 1.0 # Uses a unit radius before procedural distortion and instance scaling.
    source_sphere.height = 2.0 # Keeps the source primitive spherical.
    source_sphere.radial_segments = 14 # Provides enough horizontal resolution for rounded irregular silhouettes.
    source_sphere.rings = 9 # Provides enough vertical resolution for smooth weathered forms.
    var arrays: Array = source_sphere.surface_get_arrays(0) # Retrieves the generated vertex, normal, UV, and index arrays.
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] # Retrieves mutable source positions.
    var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] # Retrieves mutable source normals.
    var base_scale: Vector3 = _get_boulder_base_scale(variant) # Selects a distinct unscaled silhouette for this variation.
    for vertex_index: int in range(vertices.size()): # Distorts every source vertex while preserving topology and UVs.
        var source_vertex: Vector3 = vertices[vertex_index] # Reads the original unit-sphere position.
        var direction: Vector3 = source_vertex.normalized() # Converts the point into a stable angular direction.
        var radial_distortion: float = _sample_boulder_radial_distortion(direction, variant) # Calculates smooth directional surface variation.
        vertices[vertex_index] = Vector3(direction.x * base_scale.x, direction.y * base_scale.y, direction.z * base_scale.z) * radial_distortion # Applies ellipsoid shaping and smooth weathering noise.
        normals[vertex_index] = Vector3(direction.x / base_scale.x, direction.y / base_scale.y, direction.z / base_scale.z).normalized() # Approximates the smooth ellipsoid normal after deformation.
    arrays[Mesh.ARRAY_VERTEX] = vertices # Stores the distorted rounded positions back into the surface arrays.
    arrays[Mesh.ARRAY_NORMAL] = normals # Stores the updated smooth normals back into the surface arrays.
    var boulder_mesh: ArrayMesh = ArrayMesh.new() # Allocates the final shared variation resource.
    boulder_mesh.resource_name = "SmoothProceduralBoulder_%d" % variant # Gives the variation a stable diagnostic name.
    boulder_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays) # Creates the smooth triangulated boulder surface using the source topology.
    boulder_mesh.surface_set_material(0, _boulder_material) # Applies the shared weathered stone material.
    return boulder_mesh # Returns the completed non-cubic boulder variation.

func _get_boulder_base_scale(variant: int) -> Vector3: # Selects broad shape proportions for one shared boulder variation.
    match posmod(variant, BOULDER_VARIANT_COUNT): # Maps every requested variant into the authored set.
        0:
            return Vector3(1.35, 0.95, 1.10) # Creates a broad, slightly flattened rock.
        1:
            return Vector3(0.95, 1.25, 1.30) # Creates a taller, lengthened rock.
        _:
            return Vector3(1.25, 1.05, 0.90) # Creates a compact asymmetric rock.

func _sample_boulder_radial_distortion(direction: Vector3, variant: int) -> float: # Produces smooth repeatable surface irregularity from direction alone.
    var phase: float = float(variant) * 1.731 # Offsets each shared variation through the same continuous functions.
    var first_wave: float = sin(direction.x * 4.7 + direction.y * 2.1 + phase) * 0.10 # Adds one broad directional bulge field.
    var second_wave: float = sin(direction.z * 6.3 - direction.y * 3.8 + phase * 1.7) * 0.07 # Adds independent secondary weathering.
    var third_wave: float = sin((direction.x + direction.z) * 8.1 + phase * 0.63) * 0.04 # Adds restrained smaller-scale silhouette breakup.
    return 1.0 + first_wave + second_wave + third_wave # Keeps the surface rounded while avoiding a perfect primitive shape.

func _create_material(albedo: Color, roughness: float) -> StandardMaterial3D: # Creates one shared matte natural-surface material.
    var material: StandardMaterial3D = StandardMaterial3D.new() # Allocates the reusable physically based material.
    material.albedo_color = albedo # Applies the authored base colour.
    material.roughness = roughness # Keeps bark, leaves, and stone broadly diffuse.
    material.metallic = 0.0 # Prevents natural materials from behaving as metal.
    return material # Returns the configured shared material.
