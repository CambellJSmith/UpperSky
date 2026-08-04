extends StaticBody3D # Provides an independently streamable visual and collision terrain section.
class_name TerrainChunk # Makes the chunk type available to the infinite terrain controller.

var _mesh_instance: MeshInstance3D # Displays the generated terrain surface for this chunk.
var _collision_shape: CollisionShape3D # Holds collision only while the chunk is close enough to the player.
var _source_mesh: ArrayMesh # Retains the generated mesh for rendering and optional collision creation.
var _collision_active: bool = false # Tracks whether an expensive concave collision shape is currently installed.

func configure(source_mesh: ArrayMesh) -> void: # Assigns generated geometry and creates the chunk's runtime child nodes.
    _source_mesh = source_mesh # Retains the mesh so collision can be enabled later without regenerating terrain.
    _mesh_instance = MeshInstance3D.new() # Creates the visual node owned by this chunk.
    _mesh_instance.name = "TerrainMesh" # Gives the runtime visual node a stable descriptive name.
    _mesh_instance.mesh = _source_mesh # Assigns the generated terrain mesh to the visual node.
    add_child(_mesh_instance) # Adds the visual node beneath the streamable chunk.
    _collision_shape = CollisionShape3D.new() # Creates one reusable collision node for near-player activation.
    _collision_shape.name = "TerrainCollision" # Gives the runtime collision node a stable descriptive name.
    add_child(_collision_shape) # Adds the collision node beneath the static body without an active shape.

func set_collision_active(enabled: bool) -> void: # Creates or releases collision according to the player's distance from this chunk.
    if enabled == _collision_active: # Avoids rebuilding collision when the requested state has not changed.
        return # Leaves the current collision state untouched.
    _collision_active = enabled # Stores the newly requested collision state.
    if _collision_active: # Checks whether collision must now be installed.
        _collision_shape.shape = _source_mesh.create_trimesh_shape() # Creates exact concave terrain collision from the generated triangles.
        return # Stops after activating collision through its assigned shape.
    _collision_shape.shape = null # Releases the expensive concave collision data and removes its physical effect.
