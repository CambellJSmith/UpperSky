extends RefCounted # Builds and retains shared tree and boulder meshes, LODs, materials, and collision resources.
class_name WorldDecorationMeshLibrary # Makes reusable decoration geometry available to every streamed decoration chunk.

const LOD_NEAR: int = 0 # Uses the fullest procedural silhouette in the immediate gameplay area.
const LOD_MEDIUM: int = 1 # Uses substantially simpler geometry across middle-distance chunks.
const LOD_FAR: int = 2 # Uses minimal faceted silhouettes for the largest visible area.
const LOD_COUNT: int = 3 # Defines the complete supported decoration detail range.
const BOULDER_VARIANT_COUNT: int = 3 # Provides several distinct silhouettes near the player without unique geometry per object.

var _tree_meshes: Array[ArrayMesh] = [] # Stores all tree families/forms for each distance LOD.
var _boulder_meshes: Array[ArrayMesh] = [] # Stores every LOD and silhouette variation in a flattened shared array.
var _tree_collision_parts: Array = []
var _boulder_collision_shapes: Array[SphereShape3D] = [] # Stores three reusable rounded rock collision sizes.
var _boulder_material: StandardMaterial3D # Shades every rounded rock variation.

func _init(defer_build: bool = false) -> void: # Builds all shared rendering and physics resources once for the complete streamed world.
    if defer_build: return
    var tree_geometry = TreeGeometry.new()
    _boulder_material = _create_material(Color(0.28, 0.29, 0.285, 1.0), 0.98) # Creates a neutral weathered stone material.
    for lod_level: int in range(LOD_COUNT): # Builds each tree and boulder detail tier once.
        for variant in range(TreeGeometry.VARIANT_COUNT):
            _tree_meshes.append(tree_geometry.build(variant,lod_level))
        for variant: int in range(BOULDER_VARIANT_COUNT): # Builds every rock silhouette required by this distance tier.
            _boulder_meshes.append(_build_boulder_mesh(variant, lod_level)) # Stores the flattened LOD and variation combination.
    _build_collision_shapes() # Creates reusable primitive collision resources shared by all nearby decoration chunks.

func get_tree_mesh(lod_level: int, variant: int = 0) -> ArrayMesh: # Returns the shared tree geometry for one distance tier.
    return _tree_meshes[clampi(lod_level,LOD_NEAR,LOD_FAR)*TreeGeometry.VARIANT_COUNT+posmod(variant,TreeGeometry.VARIANT_COUNT)] # Clamps defensive callers into the authored LOD range.

func get_boulder_mesh(variant: int, lod_level: int) -> ArrayMesh: # Returns one shared rounded boulder variation for one distance tier.
    if _boulder_meshes.is_empty(): # Handles unexpected access before construction defensively.
        return null # Reports that no boulder geometry is available.
    var safe_lod: int = clampi(lod_level, LOD_NEAR, LOD_FAR) # Restricts the requested detail tier.
    var safe_variant: int = posmod(variant, BOULDER_VARIANT_COUNT) # Wraps the requested silhouette variation.
    return _boulder_meshes[safe_lod * BOULDER_VARIANT_COUNT + safe_variant] # Returns the flattened shared mesh resource.

func get_boulder_variant_count() -> int: # Reports how many authored boulder silhouettes are available at full detail.
    return BOULDER_VARIANT_COUNT # Keeps deterministic placement independent from array construction details.

func get_tree_collision_parts(variant: int) -> Array:
    return _tree_collision_parts[posmod(variant,TreeGeometry.VARIANT_COUNT)]

func get_tree_variant_count() -> int:
    return TreeGeometry.VARIANT_COUNT

func get_boulder_collision_shape(visual_scale: Vector3) -> SphereShape3D: # Selects one reusable conservative rounded collision size.
    var largest_scale: float = maxf(visual_scale.x, maxf(visual_scale.y, visual_scale.z)) # Measures the broadest rendered instance axis.
    var bucket: int = 1 # Uses the middle rock volume for ordinary boulders.
    if largest_scale < 1.55: # Detects common small rocks.
        bucket = 0 # Uses the smallest rounded collision resource.
    elif largest_scale > 2.35: # Detects the largest generated boulders.
        bucket = 2 # Uses the largest rounded collision resource.
    return _boulder_collision_shapes[bucket] # Returns the immutable shared primitive resource.

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
    for variant in range(TreeGeometry.VARIANT_COUNT):
        var dimensions = TreeGeometry.trunk_dimensions(variant)
        var path = TreeGeometry.trunk_path(variant)
        var parts: Array = []
        for i in range(path.size()-1):
            var direction: Vector3 = path[i+1]-path[i]
            var capsule = CapsuleShape3D.new()
            capsule.radius = dimensions.x*(1.0 if i==0 else .68)
            capsule.height = direction.length()+capsule.radius*2.0
            var basis = Basis(Quaternion(Vector3.UP,direction.normalized()))
            parts.append({"shape":capsule,"transform":Transform3D(basis,(path[i]+path[i+1])*.5)})
        _tree_collision_parts.append(parts)
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

func initialize_incremental(scheduler: GenerationScheduler) -> void: # Builds all shared rendering and physics resources once for the complete streamed world.
    var tree_geometry = TreeGeometry.new()
    _boulder_material = _create_material(Color(0.28, 0.29, 0.285, 1.0), 0.98) # Creates a neutral weathered stone material.
    for lod_level: int in range(LOD_COUNT): # Builds each tree and boulder detail tier once.
        if not await scheduler.checkpoint(): return
        for variant in range(TreeGeometry.VARIANT_COUNT):
            if not await scheduler.checkpoint(): return
            _tree_meshes.append(tree_geometry.build(variant,lod_level))
        for variant: int in range(BOULDER_VARIANT_COUNT): # Builds every rock silhouette required by this distance tier.
            if not await scheduler.checkpoint(): return
            _boulder_meshes.append(_build_boulder_mesh(variant, lod_level)) # Stores the flattened LOD and variation combination.
    _build_collision_shapes() # Creates reusable primitive collision resources shared by all nearby decoration chunks.
