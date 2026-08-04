extends StaticBody3D # Provides an independently streamable visual, water, and collision terrain section.
class_name TerrainChunk # Makes the chunk type available to the infinite terrain controller.

var _mesh_instance: MeshInstance3D # Displays the generated terrain surface for this chunk.
var _water_mesh_instance: MeshInstance3D # Displays clipped local water surfaces only when the chunk contains submerged terrain.
var _collision_shape: CollisionShape3D # Holds collision only while the chunk is close enough to the player.
var _source_mesh: ArrayMesh # Retains the generated terrain mesh for rendering and optional collision creation.
var _collision_active: bool = false # Tracks whether an expensive concave collision shape is currently installed.

func configure(source_mesh: ArrayMesh, water_mesh: ArrayMesh) -> void: # Assigns generated ground and water geometry and creates the chunk's runtime child nodes.
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

func set_collision_active(enabled: bool) -> void: # Creates or releases terrain collision according to the player's distance from this chunk.
    if enabled == _collision_active: # Avoids rebuilding collision when the requested state has not changed.
        return # Leaves the current collision state untouched.
    _collision_active = enabled # Stores the newly requested collision state.
    if _collision_active: # Checks whether terrain collision must now be installed.
        _collision_shape.shape = _source_mesh.create_trimesh_shape() # Creates exact concave ground collision from the generated terrain triangles.
        return # Stops after activating collision through its assigned shape.
    _collision_shape.shape = null # Releases the expensive concave collision data and removes its physical effect.
