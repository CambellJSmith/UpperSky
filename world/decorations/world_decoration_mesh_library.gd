extends RefCounted # Builds and retains shared smooth decoration meshes, LODs, materials, and collision resources.
class_name WorldDecorationMeshLibrary # Makes reusable decoration geometry available to every streamed decoration chunk.

const LOD_NEAR: int = 0 # Uses the fullest procedural silhouette in the immediate gameplay area.
const LOD_MEDIUM: int = 1 # Uses substantially simpler geometry across middle-distance chunks.
const LOD_FAR: int = 2 # Uses minimal smooth silhouettes for the largest visible area.
const LOD_COUNT: int = 3 # Defines the complete supported decoration detail range.
const BOULDER_VARIANT_COUNT: int = 3 # Provides several distinct silhouettes near the player without unique geometry per object.
const TREE_TRUNK_HEIGHT: float = 7.2 # Defines the unscaled visible trunk height used by rendering and collision approximation.
const TREE_TRUNK_BASE_RADIUS: float = 0.72 # Defines the unscaled lower trunk radius.
const TREE_TRUNK_TOP_RADIUS: float = 0.38 # Tapers the trunk toward the canopy instead of producing a cylinder.

var _tree_meshes: Array[ArrayMesh] = [] # Stores one shared tree mesh for each distance LOD.
var _boulder_meshes: Array[ArrayMesh] = [] # Stores every LOD and silhouette variation in a flattened shared array.
var _tree_collision_shapes: Array[CylinderShape3D] = [] # Stores three reusable trunk collision sizes instead of allocating one shape resource per tree.
var _boulder_collision_shapes: Array[SphereShape3D] = [] # Stores three reusable rounded rock collision sizes.
var _trunk_material: StandardMaterial3D # Shades every trunk and branch surface.
var _foliage_material: StandardMaterial3D # Shades every smooth foliage volume.
var _boulder_material: StandardMaterial3D # Shades every rounded rock variation.

func _init() -> void: # Builds all shared rendering and physics resources once for the complete streamed world.
    _trunk_material = _create_material(Color(0.20, 0.105, 0.045, 1.0), 0.96) # Creates a dark matte bark material.
    _foliage_material = _create_material(Color(0.075, 0.24, 0.075, 1.0), 0.92) # Creates dense desaturated green foliage.
    _boulder_material = _create_material(Color(0.28, 0.29, 0.285, 1.0), 0.98) # Creates a neutral weathered stone material.
    for lod_level: int in range(LOD_COUNT): # Builds each tree and boulder detail tier once.
        _tree_meshes.append(_build_tree_mesh(lod_level)) # Retains one shared tree silhouette for this distance tier.
        for variant: int in range(BOULDER_VARIANT_COUNT): # Builds every rock silhouette required by this distance tier.
            _boulder_meshes.append(_build_boulder_mesh(variant, lod_level)) # Stores the flattened LOD and variation combination.
    _build_collision_shapes() # Creates reusable primitive collision resources shared by all nearby decoration chunks.

func get_tree_mesh(lod_level: int) -> ArrayMesh: # Returns the shared tree geometry for one distance tier.
    return _tree_meshes[clampi(lod_level, LOD_NEAR, LOD_FAR)] # Clamps defensive callers into the authored LOD range.

func get_boulder_mesh(variant: int, lod_level: int) -> ArrayMesh: # Returns one shared rounded boulder variation for one distance tier.
    if _boulder_meshes.is_empty(): # Handles unexpected access before construction defensively.
        return null # Reports that no boulder geometry is available.
    var safe_lod: int = clampi(lod_level, LOD_NEAR, LOD_FAR) # Restricts the requested detail tier.
    var safe_variant: int = posmod(variant, BOULDER_VARIANT_COUNT) # Wraps the requested silhouette variation.
    return _boulder_meshes[safe_lod * BOULDER_VARIANT_COUNT + safe_variant] # Returns the flattened shared mesh resource.

func get_boulder_variant_count() -> int: # Reports how many authored boulder silhouettes are available at full detail.
    return BOULDER_VARIANT_COUNT # Keeps deterministic placement independent from array construction details.

func get_tree_collision_shape(visual_scale: Vector3) -> CylinderShape3D: # Selects one reusable trunk shape matching the visible tree's broad size.
    var bucket: int = 1 # Uses the middle collision size for ordinary trees.
    if visual_scale.y < 0.94 and maxf(visual_scale.x, visual_scale.z) < 0.92: # Detects compact trees.
        bucket = 0 # Uses the smallest shared trunk.
    elif visual_scale.y > 1.18 or maxf(visual_scale.x, visual_scale.z) > 1.08: # Detects tall or broad trees.
        bucket = 2 # Uses the largest shared trunk.
    return _tree_collision_shapes[bucket] # Returns the immutable shared primitive resource.

func get_boulder_collision_shape(visual_scale: Vector3) -> SphereShape3D: # Selects one reusable conservative rounded collision size.
    var largest_scale: float = maxf(visual_scale.x, maxf(visual_scale.y, visual_scale.z)) # Measures the broadest rendered instance axis.
    var bucket: int = 1 # Uses the middle rock volume for ordinary boulders.
    if largest_scale < 1.55: # Detects common small rocks.
        bucket = 0 # Uses the smallest rounded collision resource.
    elif largest_scale > 2.35: # Detects the largest generated boulders.
        bucket = 2 # Uses the largest rounded collision resource.
    return _boulder_collision_shapes[bucket] # Returns the immutable shared primitive resource.

func _build_tree_mesh(lod_level: int) -> ArrayMesh: # Builds one smooth procedural tree silhouette appropriate to a distance tier.
    var tree_mesh: ArrayMesh = ArrayMesh.new() # Allocates the multi-surface result shared by all instances using this LOD.
    tree_mesh.resource_name = "SmoothProceduralTree_LOD%d" % lod_level # Gives the generated resource a useful diagnostic name.
    var trunk_segments: int = 8 # Defaults to a rounded but restrained near trunk.
    var trunk_rings: int = 2 # Retains enough vertical subdivision for stable near normals.
    var foliage_segments: int = 8 # Defaults to a rounded near canopy silhouette.
    var foliage_rings: int = 5 # Retains smooth vertical curvature near the player.
    if lod_level == LOD_MEDIUM: # Selects the middle-distance geometry budget.
        trunk_segments = 6 # Reduces cylindrical vertex count substantially.
        trunk_rings = 1 # Removes unnecessary vertical subdivision.
        foliage_segments = 6 # Simplifies each rounded canopy mass.
        foliage_rings = 4 # Retains an organic silhouette with fewer rings.
    elif lod_level == LOD_FAR: # Selects the cheapest visible geometry.
        trunk_segments = 5 # Uses a minimal tapered trunk that remains non-cubic.
        trunk_rings = 1 # Keeps only the required vertical structure.
        foliage_segments = 6 # Uses a compact rounded canopy silhouette.
        foliage_rings = 3 # Minimizes far canopy vertices.

    var wood_surface: SurfaceTool = SurfaceTool.new() # Collects trunk and optional branch primitives into one material surface.
    wood_surface.begin(Mesh.PRIMITIVE_TRIANGLES) # Begins triangle geometry compatible with ordinary lighting and shadows.
    _append_cylinder(wood_surface, TREE_TRUNK_HEIGHT, TREE_TRUNK_BASE_RADIUS, TREE_TRUNK_TOP_RADIUS, Transform3D(Basis.IDENTITY, Vector3(0.0, TREE_TRUNK_HEIGHT * 0.5, 0.0)), trunk_segments, trunk_rings) # Adds the tapered main trunk with its base at ground level.
    if lod_level == LOD_NEAR: # Retains the complete asymmetric branch silhouette only in nearby chunks.
        _append_branch(wood_surface, Vector3(0.0, 5.0, 0.0), Vector3(2.2, 7.5, 0.7), 0.28, 0.12, trunk_segments, 1) # Adds one upward-reaching branch.
        _append_branch(wood_surface, Vector3(0.0, 5.8, 0.0), Vector3(-1.9, 8.3, -1.0), 0.25, 0.10, trunk_segments, 1) # Adds an opposing branch.
        _append_branch(wood_surface, Vector3(0.0, 6.4, 0.0), Vector3(0.8, 9.0, -1.9), 0.22, 0.09, trunk_segments, 1) # Adds a rear branch to break radial symmetry.
    elif lod_level == LOD_MEDIUM: # Retains one broad branch in middle-distance silhouettes.
        _append_branch(wood_surface, Vector3(0.0, 5.5, 0.0), Vector3(1.8, 7.8, 0.6), 0.25, 0.10, trunk_segments, 1) # Preserves a recognisable asymmetric outline.
    wood_surface.commit(tree_mesh) # Adds the complete wood geometry as the first mesh surface.
    tree_mesh.surface_set_material(0, _trunk_material) # Applies bark to trunk and branches.

    var foliage_surface: SurfaceTool = SurfaceTool.new() # Collects rounded canopy masses into one second surface.
    foliage_surface.begin(Mesh.PRIMITIVE_TRIANGLES) # Begins lit triangle geometry for smooth foliage volumes.
    if lod_level == LOD_NEAR: # Uses three overlapping masses near the player instead of the original four expensive spheres.
        _append_foliage_blob(foliage_surface, Vector3(0.0, 9.0, 0.0), Vector3(3.4, 3.0, 3.2), foliage_segments, foliage_rings) # Adds the principal canopy volume.
        _append_foliage_blob(foliage_surface, Vector3(1.6, 8.4, 0.6), Vector3(2.3, 2.1, 2.2), foliage_segments, foliage_rings) # Extends foliage around one branch.
        _append_foliage_blob(foliage_surface, Vector3(-1.4, 9.0, -0.8), Vector3(2.2, 2.4, 2.0), foliage_segments, foliage_rings) # Extends the opposing side.
    elif lod_level == LOD_MEDIUM: # Uses two simple rounded masses at middle distance.
        _append_foliage_blob(foliage_surface, Vector3(0.0, 9.0, 0.0), Vector3(3.5, 3.1, 3.3), foliage_segments, foliage_rings) # Creates the dominant canopy.
        _append_foliage_blob(foliage_surface, Vector3(1.0, 9.4, -0.5), Vector3(2.3, 2.1, 2.2), foliage_segments, foliage_rings) # Retains mild asymmetry.
    else: # Uses one rounded canopy volume at far distance.
        _append_foliage_blob(foliage_surface, Vector3(0.0, 9.0, 0.0), Vector3(3.7, 3.3, 3.5), foliage_segments, foliage_rings) # Preserves the complete tree silhouette with minimal geometry.
    foliage_surface.commit(tree_mesh) # Adds the canopy as a separate material surface.
    tree_mesh.surface_set_material(1, _foliage_material) # Applies the foliage material without affecting bark.
    return tree_mesh # Returns the complete smooth tree resource.

func _append_cylinder(surface: SurfaceTool, height: float, bottom_radius: float, top_radius: float, transform: Transform3D, radial_segments: int, rings: int) -> void: # Appends one tapered smooth cylinder to an active surface.
    var cylinder: CylinderMesh = CylinderMesh.new() # Allocates a temporary smooth primitive used only while building a shared mesh.
    cylinder.height = height # Sets the complete cylinder length along its local y axis.
    cylinder.bottom_radius = bottom_radius # Defines the wider lower end.
    cylinder.top_radius = top_radius # Defines the narrower upper end.
    cylinder.radial_segments = maxi(radial_segments, 3) # Keeps the silhouette rounded without invalid primitive settings.
    cylinder.rings = maxi(rings, 1) # Provides only the vertical subdivisions required by this LOD.
    surface.append_from(cylinder, 0, transform) # Copies the primitive into the combined shared tree surface.

func _append_branch(surface: SurfaceTool, start: Vector3, end: Vector3, start_radius: float, end_radius: float, radial_segments: int, rings: int) -> void: # Adds one tapered cylinder aligned between two arbitrary points.
    var direction: Vector3 = end - start # Calculates the branch axis and length.
    var length: float = direction.length() # Measures the required primitive height.
    if length <= 0.001: # Rejects degenerate branch descriptions.
        return # Avoids constructing an invalid zero-height cylinder.
    var branch_basis: Basis = _basis_from_y_axis(direction / length) # Rotates the cylinder's local y axis onto the branch direction.
    var midpoint: Vector3 = (start + end) * 0.5 # Positions the centered cylinder between its endpoints.
    _append_cylinder(surface, length, start_radius, end_radius, Transform3D(branch_basis, midpoint), radial_segments, rings) # Adds the aligned tapered branch.

func _append_foliage_blob(surface: SurfaceTool, centre: Vector3, scale: Vector3, radial_segments: int, rings: int) -> void: # Appends one smooth ellipsoidal canopy mass.
    var sphere: SphereMesh = SphereMesh.new() # Allocates a temporary rounded primitive for the shared canopy mesh.
    sphere.radius = 1.0 # Uses a unit radius before the authored ellipsoid scale is applied.
    sphere.height = 2.0 # Keeps the unscaled primitive spherical.
    sphere.radial_segments = maxi(radial_segments, 3) # Keeps the canopy rounded at the selected LOD.
    sphere.rings = maxi(rings, 2) # Retains valid vertical curvature with a small far-distance budget.
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

func _build_boulder_mesh(variant: int, lod_level: int) -> ArrayMesh: # Distorts a rounded primitive into one smooth irregular boulder at the requested detail tier.
    var source_sphere: SphereMesh = SphereMesh.new() # Creates a temporary triangulated sphere with stable topology and winding.
    source_sphere.radius = 1.0 # Uses a unit radius before procedural distortion and instance scaling.
    source_sphere.height = 2.0 # Keeps the source primitive spherical.
    if lod_level == LOD_NEAR: # Uses the fullest rock silhouette in nearby chunks.
        source_sphere.radial_segments = 12 # Retains rounded local weathering without the original fourteen-segment cost.
        source_sphere.rings = 8 # Retains smooth vertical curvature.
    elif lod_level == LOD_MEDIUM: # Uses a reduced middle-distance silhouette.
        source_sphere.radial_segments = 9 # Removes substantial vertex work.
        source_sphere.rings = 6 # Retains a recognisably rounded rock.
    else: # Uses the cheapest far-distance silhouette.
        source_sphere.radial_segments = 7 # Preserves a non-cubic outline with minimal horizontal subdivision.
        source_sphere.rings = 4 # Uses only enough vertical structure for an irregular rounded mass.
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
    boulder_mesh.resource_name = "SmoothProceduralBoulder_%d_LOD%d" % [variant, lod_level] # Gives the variation a stable diagnostic name.
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

func _build_collision_shapes() -> void: # Creates a few reusable primitive resources for dense nearby collision.
    var tree_heights: Array[float] = [5.9, 7.1, 8.6] # Defines compact, ordinary, and large trunk heights.
    var tree_radii: Array[float] = [0.54, 0.70, 0.88] # Defines matching conservative trunk radii.
    for bucket: int in range(tree_heights.size()): # Builds each reusable trunk size once.
        var trunk_shape: CylinderShape3D = CylinderShape3D.new() # Allocates one shared smooth cylinder.
        trunk_shape.height = tree_heights[bucket] # Applies the bucket's complete vertical extent.
        trunk_shape.radius = tree_radii[bucket] # Applies the bucket's broad collision radius.
        _tree_collision_shapes.append(trunk_shape) # Retains the resource for every nearby chunk.
    var boulder_radii: Array[float] = [2.15, 3.25, 4.35] # Defines collision volumes for small, ordinary, and very large rounded rocks.
    for radius: float in boulder_radii: # Builds each reusable boulder size once.
        var boulder_shape: SphereShape3D = SphereShape3D.new() # Allocates one shared smooth sphere.
        boulder_shape.radius = radius # Applies the conservative rounded extent.
        _boulder_collision_shapes.append(boulder_shape) # Retains the resource for every nearby chunk.

func _create_material(albedo: Color, roughness: float) -> StandardMaterial3D: # Creates one shared matte natural-surface material.
    var material: StandardMaterial3D = StandardMaterial3D.new() # Allocates the reusable physically based material.
    material.albedo_color = albedo # Applies the authored base colour.
    material.roughness = roughness # Keeps bark, leaves, and stone broadly diffuse.
    material.metallic = 0.0 # Prevents natural materials from behaving as metal.
    return material # Returns the configured shared material.
