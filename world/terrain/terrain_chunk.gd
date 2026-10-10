extends StaticBody3D # Provides an independently streamable visual, water, and collision terrain section.
class_name TerrainChunk # Makes the chunk type available to the infinite terrain controller.

var _mesh_instance: MeshInstance3D # Displays the generated terrain surface for this chunk.
var _water_mesh_instance: MeshInstance3D # Displays clipped local water surfaces only when the chunk contains submerged terrain.
var _collision_shape: CollisionShape3D # Holds collision only while the chunk is close enough to the player.
var _source_mesh: ArrayMesh # Retains the generated terrain mesh for rendering and optional collision creation.
var _cached_collision: ConcavePolygonShape3D # Retain reusable collision independently of physics activation.
var _collision_faces: PackedVector3Array # Retain worker-prepared triangles without reading the rendered mesh back.
var _collision_active: bool = false # Tracks whether an expensive concave collision shape is currently installed.

func configure(source_mesh: ArrayMesh, water_mesh: ArrayMesh, faces: PackedVector3Array = PackedVector3Array()) -> void: # Assigns generated ground and water geometry and creates the chunk's runtime child nodes.
    _collision_faces = faces # Take ownership of immutable worker-prepared collision triangles.
    _source_mesh = source_mesh # Retains the terrain mesh so collision can be enabled later without regenerating terrain.
    _mesh_instance = MeshInstance3D.new() # Creates the visual ground node owned by this chunk.
    _mesh_instance.name = "TerrainMesh" # Gives the runtime terrain visual a stable descriptive name.
    _mesh_instance.mesh = _source_mesh # Assigns the generated terrain mesh to the ground visual.
    add_child(_mesh_instance) # Adds the terrain visual beneath the streamable chunk.
    if water_mesh.get_surface_count() > 0: # Detects whether this chunk contains any clipped water geometry.
        _water_mesh_instance = MeshInstance3D.new() # Creates a water visual only for chunks that actually need one.
        _water_mesh_instance.name = "TerrainWater" # Gives the runtime water visual a stable descriptive name.
        _water_mesh_instance.mesh = water_mesh # Assigns the generated non-overlapping water mesh.
        add_child(_water_mesh_instance) # Adds water beneath the same chunk transform so floating-origin movement remains exact.
    _collision_shape = CollisionShape3D.new() # Creates one reusable collision node for near-player activation.
    _collision_shape.name = "TerrainCollision" # Gives the runtime collision node a stable descriptive name.
    add_child(_collision_shape) # Adds the collision node beneath the static body without an active shape.

func prepare_collision() -> void: # Build collision only when no reusable shape exists.
    if _cached_collision != null: return # Avoid repeating exact terrain collision construction.
    if _collision_faces.is_empty(): # Retain compatibility with synchronous preview meshes.
        _cached_collision = _source_mesh.create_trimesh_shape() # Build once for mesh-only callers.
    else: # Prefer CPU triangles already assembled by the terrain worker.
        _cached_collision = ConcavePolygonShape3D.new() # Allocate a private physics resource on the main thread.
        _cached_collision.set_faces(_collision_faces) # Avoid mesh readback and repeated indexed triangle expansion.

func set_collision_active(enabled: bool) -> void: # Toggle physics while retaining a reusable shape.
    if enabled == _collision_active: return # Avoid redundant physics changes.
    _collision_active = enabled # Record the required physical state.
    if enabled: prepare_collision() # Build only when the bounded cache did not retain this collider.
    _collision_shape.shape = _cached_collision if enabled else null # Detach distant physics without destroying cached geometry.

func release_cached_collision() -> void: # Evict inactive collision when the terrain cache reaches capacity.
    if not _collision_active: _cached_collision = null # Never discard a shape still required for movement.
