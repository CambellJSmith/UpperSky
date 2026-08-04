extends Node3D # Streams deterministic procedural terrain and tiered water chunks around a tracked player.
class_name InfiniteTerrain # Makes the terrain controller available to the game composition root.

const WATER_PRESENCE_EPSILON: float = 0.02 # Matches shoreline clipping tolerance when deciding whether a real water volume exists.

var _height_sampler: TerrainHeightSampler # Supplies one continuous deterministic height function for every terrain chunk.
var _mesh_builder: TerrainMeshBuilder # Converts height samples into seam-consistent renderable ground meshes.
var _terrain_material: StandardMaterial3D # Shades generated ground vertices using their authored terrain colours.
var _water_level_sampler: TerrainWaterLevelSampler # Selects flat local water elevations corresponding to the world's major terrain tiers.
var _water_mesh_builder: TerrainWaterMeshBuilder # Clips local water surfaces against terrain and seals transitions between different levels.
var _water_material: StandardMaterial3D # Shades all generated water surfaces with one shared transparent material.
var _player: Node3D # Identifies the moving world subject that controls streaming.
var _rebase_root: Node3D # Owns active world entities that must remain aligned when the floating origin moves.
var _world_origin_offset: Vector2 = Vector2.ZERO # Tracks the absolute world coordinate represented by local scene origin.
var _current_chunk_coordinate: Vector2i = Vector2i(2_147_483_647, 2_147_483_647) # Forces the first streaming refresh after initialization.
var _chunks: Dictionary[Vector2i, TerrainChunk] = {} # Stores every currently loaded terrain and water chunk by world-grid coordinate.
var _desired_chunks: Dictionary[Vector2i, bool] = {} # Stores the current visible streaming set around the player.
var _pending_chunks: Array[Vector2i] = [] # Holds missing chunks in near-to-far generation order.
var _pending_chunk_index: int = 0 # Tracks the next queued coordinate without shifting the array on every build.

func _ready() -> void: # Creates reusable terrain and water resources before the game composition root initializes the player.
    _height_sampler = TerrainHeightSampler.new() # Creates the deterministic world-height service.
    _terrain_material = _create_terrain_material() # Creates one shared material for every streamed ground chunk.
    _mesh_builder = TerrainMeshBuilder.new(_height_sampler, _terrain_material) # Creates the isolated ground mesh-construction service.
    _water_level_sampler = TerrainWaterLevelSampler.new() # Creates the tier-aware flat water-level service.
    _water_material = _create_water_material() # Creates one shared transparent material for every streamed water surface.
    _water_mesh_builder = TerrainWaterMeshBuilder.new(_height_sampler, _water_level_sampler, _water_material) # Creates the clipped water mesh-construction service.

func initialize(player: Node3D, rebase_root: Node3D) -> void: # Connects terrain streaming, active entities, and safe initial spawn geometry.
    _player = player # Stores the tracked player without introducing global state or signals.
    _rebase_root = rebase_root # Stores the active-entity root used by floating-origin adjustments.
    _current_chunk_coordinate = _get_chunk_coordinate(_get_player_world_position()) # Calculates the player's initial absolute world-grid coordinate.
    _refresh_streaming_set(_current_chunk_coordinate) # Builds the desired set and unloads anything outside it.
    _build_initial_collision_area(_current_chunk_coordinate) # Builds a complete collision neighbourhood before any spawn query or movement occurs.
    _update_collision_states() # Activates collision on all currently available near-player chunks.

func _physics_process(_delta: float) -> void: # Keeps active entities close to local origin during unbounded travel.
    if _player == null or _rebase_root == null: # Waits until the composition root provides both required world references.
        return # Skips floating-origin work until terrain initialization is complete.
    _rebase_world_if_needed() # Repositions active entities and loaded chunks before transforms lose useful precision.

func _process(_delta: float) -> void: # Advances bounded terrain and water streaming work each rendered frame.
    if _player == null: # Waits until the game composition root provides a player reference.
        return # Skips streaming without a tracked subject.
    var player_chunk_coordinate: Vector2i = _get_chunk_coordinate(_get_player_world_position()) # Finds the player's current absolute world-grid coordinate.
    if player_chunk_coordinate != _current_chunk_coordinate: # Detects movement across a terrain chunk boundary.
        _current_chunk_coordinate = player_chunk_coordinate # Stores the new streaming centre.
        _refresh_streaming_set(_current_chunk_coordinate) # Rebuilds desired, queued, unloaded, and collision states.
    _build_pending_chunks() # Generates a fixed number of missing terrain and water chunks without blocking the full frame.

func get_height_at(world_position: Vector2) -> float: # Exposes the authoritative ground height field to spawning and future world systems.
    return _height_sampler.sample_height(world_position.x, world_position.y) # Samples the same function used by every generated terrain mesh vertex.

func get_water_level_at(world_position: Vector2) -> float: # Exposes the local flat water band to swimming, audio, weather, and placement systems.
    return _water_level_sampler.sample_water_level(world_position.x, world_position.y) # Samples the same deterministic level used by generated water geometry.

func has_water_at(world_position: Vector2) -> bool: # Reports whether the clipped water mesh occupies one absolute horizontal position.
    var terrain_height: float = get_height_at(world_position) # Samples the exact ground surface used to clip water geometry.
    var water_level: float = get_water_level_at(world_position) # Samples the exact local flat level used to generate water.
    return terrain_height < water_level - WATER_PRESENCE_EPSILON # Matches mesh clipping so dry high ground never behaves as water.

func local_to_world_position(local_position: Vector3) -> Vector3: # Converts a near-origin scene position into a stable absolute procedural-world position.
    return Vector3(local_position.x + _world_origin_offset.x, local_position.y, local_position.z + _world_origin_offset.y) # Adds the accumulated horizontal world offset without changing elevation.

func world_to_local_position(world_position: Vector3) -> Vector3: # Converts a stable absolute procedural-world position into the current near-origin scene space.
    return Vector3(world_position.x - _world_origin_offset.x, world_position.y, world_position.z - _world_origin_offset.y) # Removes the accumulated horizontal world offset without changing elevation.

func get_loaded_chunk_count() -> int: # Reports the current loaded chunk count for profiling and future diagnostics.
    return _chunks.size() # Returns the number of visual chunk nodes currently retained.

func _refresh_streaming_set(centre: Vector2i) -> void: # Recalculates all chunks required around a new streaming centre.
    _desired_chunks.clear() # Removes coordinates from the previous streaming set.
    _pending_chunks.clear() # Discards stale queue ordering before rebuilding it around the new centre.
    _pending_chunk_index = 0 # Restarts sequential queue reading for the rebuilt near-to-far order.
    for ring: int in range(TerrainConfiguration.VISUAL_RADIUS + 1): # Visits chunk rings from nearest to farthest for useful loading priority.
        _append_ring_coordinates(centre, ring) # Adds every coordinate belonging to the current square ring.
    var chunks_to_remove: Array[Vector2i] = [] # Collects unloaded coordinates without mutating the dictionary during iteration.
    for chunk_coordinate: Vector2i in _chunks.keys(): # Examines every currently loaded terrain chunk.
        if not _desired_chunks.has(chunk_coordinate): # Detects chunks that have left the visible streaming radius.
            chunks_to_remove.append(chunk_coordinate) # Defers removal until dictionary iteration has completed.
    for chunk_coordinate: Vector2i in chunks_to_remove: # Removes every chunk no longer required around the player.
        var chunk: TerrainChunk = _chunks[chunk_coordinate] # Retrieves the streamable chunk node being discarded.
        _chunks.erase(chunk_coordinate) # Removes the coordinate from the active chunk lookup immediately.
        chunk.queue_free() # Releases the chunk node, ground mesh, water mesh, and any collision at the end of the frame.
    _update_collision_states() # Re-evaluates collision for retained chunks around the new centre.

func _append_ring_coordinates(centre: Vector2i, ring: int) -> void: # Adds one square ring of desired chunks in deterministic order.
    for offset_z: int in range(-ring, ring + 1): # Visits each row crossing the current square ring.
        for offset_x: int in range(-ring, ring + 1): # Visits each column crossing the current square ring.
            if maxi(absi(offset_x), absi(offset_z)) != ring: # Skips coordinates inside the current ring perimeter.
                continue # Continues until reaching a coordinate exactly on the ring edge.
            var chunk_coordinate: Vector2i = centre + Vector2i(offset_x, offset_z) # Converts the local ring offset into a world chunk coordinate.
            _desired_chunks[chunk_coordinate] = true # Marks the coordinate as required for rendering.
            if _chunks.has(chunk_coordinate): # Detects terrain that is already loaded from the previous streaming set.
                continue # Avoids rebuilding an existing chunk.
            _pending_chunks.append(chunk_coordinate) # Queues the missing chunk in near-to-far ring order.

func _build_pending_chunks() -> void: # Builds a bounded number of queued chunks during the current frame.
    var chunks_built: int = 0 # Tracks work completed against the per-frame generation budget.
    while chunks_built < TerrainConfiguration.CHUNKS_BUILT_PER_FRAME and _pending_chunk_index < _pending_chunks.size(): # Continues while budget and queued work remain.
        var chunk_coordinate: Vector2i = _pending_chunks[_pending_chunk_index] # Retrieves the next missing chunk without shifting the queue array.
        _pending_chunk_index += 1 # Advances sequentially to the next queued coordinate.
        if not _desired_chunks.has(chunk_coordinate): # Detects stale work after a rapid player movement.
            continue # Skips chunks that are no longer visible.
        if _chunks.has(chunk_coordinate): # Detects a chunk created immediately or through another queue path.
            continue # Skips duplicate generation.
        _build_chunk(chunk_coordinate) # Generates and installs one complete visual terrain and water chunk.
        chunks_built += 1 # Consumes one unit of the current frame's generation budget.

func _build_initial_collision_area(centre: Vector2i) -> void: # Builds all chunks required for safe spawn collision before ordinary bounded streaming begins.
    for offset_z: int in range(-TerrainConfiguration.INITIAL_COLLISION_RADIUS, TerrainConfiguration.INITIAL_COLLISION_RADIUS + 1): # Visits every initial collision row around the spawn chunk.
        for offset_x: int in range(-TerrainConfiguration.INITIAL_COLLISION_RADIUS, TerrainConfiguration.INITIAL_COLLISION_RADIUS + 1): # Visits every initial collision column around the spawn chunk.
            var chunk_coordinate: Vector2i = centre + Vector2i(offset_x, offset_z) # Converts the local spawn-neighbourhood offset into a world chunk coordinate.
            _build_chunk_immediately(chunk_coordinate) # Creates the visual meshes and exact ground collision outside the ordinary per-frame budget.

func _build_chunk_immediately(chunk_coordinate: Vector2i) -> void: # Builds one required chunk outside the ordinary frame budget for safe spawning.
    if _chunks.has(chunk_coordinate): # Detects whether the required chunk already exists.
        return # Avoids duplicate mesh and collision creation.
    _build_chunk(chunk_coordinate) # Generates and installs the requested terrain and water chunk now.

func _build_chunk(chunk_coordinate: Vector2i) -> void: # Generates one terrain chunk with clipped water and installs its streamable runtime node.
    var terrain_mesh: ArrayMesh = _mesh_builder.build_chunk_mesh(chunk_coordinate) # Generates ground vertices, normals, colours, indices, and material assignment.
    var water_mesh: ArrayMesh = _water_mesh_builder.build_chunk_mesh(chunk_coordinate) # Generates only submerged water polygons and sealed local level transitions.
    var chunk: TerrainChunk = TerrainChunk.new() # Creates a lightweight streamable terrain body.
    chunk.name = "TerrainChunk_%d_%d" % [chunk_coordinate.x, chunk_coordinate.y] # Gives the runtime node a coordinate-derived diagnostic name.
    chunk.position = _get_chunk_local_position(chunk_coordinate) # Places local vertices relative to the current floating-world origin.
    add_child(chunk) # Adds the generated chunk to the active world scene.
    chunk.configure(terrain_mesh, water_mesh) # Assigns the generated ground and optional water geometry and creates runtime nodes.
    _chunks[chunk_coordinate] = chunk # Registers the chunk for streaming, collision, and unloading.
    chunk.set_collision_active(_is_collision_coordinate(chunk_coordinate)) # Enables exact ground collision immediately when the chunk is near the player.

func _get_player_world_position() -> Vector2: # Converts the player's local scene position into an absolute procedural-world coordinate.
    return Vector2(_player.global_position.x, _player.global_position.z) + _world_origin_offset # Adds the accumulated floating-origin offset to the local position.

func _get_chunk_coordinate(world_position: Vector2) -> Vector2i: # Converts an absolute horizontal position into the terrain's integer chunk grid.
    return Vector2i(floori(world_position.x / TerrainConfiguration.CHUNK_SIZE), floori(world_position.y / TerrainConfiguration.CHUNK_SIZE)) # Uses floor division so negative coordinates stream correctly.

func _get_chunk_local_position(chunk_coordinate: Vector2i) -> Vector3: # Converts an absolute chunk coordinate into its current near-origin scene position.
    var world_x: float = float(chunk_coordinate.x) * TerrainConfiguration.CHUNK_SIZE - _world_origin_offset.x # Removes the accumulated x-axis origin offset from the absolute chunk position.
    var world_z: float = float(chunk_coordinate.y) * TerrainConfiguration.CHUNK_SIZE - _world_origin_offset.y # Removes the accumulated z-axis origin offset from the absolute chunk position.
    return Vector3(world_x, 0.0, world_z) # Returns the chunk position kept close to local scene origin.

func _rebase_world_if_needed() -> void: # Moves active transforms toward local origin while preserving absolute procedural coordinates.
    var local_horizontal_position: Vector2 = Vector2(_player.global_position.x, _player.global_position.z) # Reads the player's current near-origin horizontal position.
    if maxf(absf(local_horizontal_position.x), absf(local_horizontal_position.y)) < TerrainConfiguration.ORIGIN_REBASE_DISTANCE: # Detects whether local precision remains comfortably inside the threshold.
        return # Leaves the current origin unchanged while the player remains nearby.
    var shift_x: float = float(roundi(local_horizontal_position.x / TerrainConfiguration.CHUNK_SIZE)) * TerrainConfiguration.CHUNK_SIZE # Aligns the x-axis rebase shift to terrain chunk boundaries.
    var shift_z: float = float(roundi(local_horizontal_position.y / TerrainConfiguration.CHUNK_SIZE)) * TerrainConfiguration.CHUNK_SIZE # Aligns the z-axis rebase shift to terrain chunk boundaries.
    var local_shift: Vector3 = Vector3(shift_x, 0.0, shift_z) # Builds the local scene-space translation applied to active entities.
    _world_origin_offset += Vector2(shift_x, shift_z) # Advances the absolute world coordinate represented by local origin.
    for child: Node in _rebase_root.get_children(): # Visits every top-level active entity owned by the rebase root.
        if child is Node3D: # Restricts spatial translation to three-dimensional active entities.
            var spatial_child: Node3D = child as Node3D # Converts the generic child into its strongly typed spatial form.
            spatial_child.global_position -= local_shift # Keeps each active entity visually fixed while moving it closer to local origin.
    for chunk_coordinate: Vector2i in _chunks.keys(): # Visits every loaded terrain and water chunk after updating the origin offset.
        var chunk: TerrainChunk = _chunks[chunk_coordinate] # Retrieves the chunk requiring a new near-origin position.
        chunk.position = _get_chunk_local_position(chunk_coordinate) # Repositions ground and water together without regenerating absolute-coordinate geometry.

func _is_collision_coordinate(chunk_coordinate: Vector2i) -> bool: # Determines whether one loaded chunk is close enough for physical interaction.
    var offset: Vector2i = chunk_coordinate - _current_chunk_coordinate # Measures chunk-grid distance from the player.
    return maxi(absi(offset.x), absi(offset.y)) <= TerrainConfiguration.COLLISION_RADIUS # Uses a square near-player collision region that fully surrounds movement.

func _update_collision_states() -> void: # Enables exact ground collision nearby and releases it from distant visual chunks.
    for chunk_coordinate: Vector2i in _chunks.keys(): # Visits every currently loaded chunk.
        var chunk: TerrainChunk = _chunks[chunk_coordinate] # Retrieves the streamable terrain body for this coordinate.
        chunk.set_collision_active(_is_collision_coordinate(chunk_coordinate)) # Applies the collision state required by player distance.

func _create_terrain_material() -> StandardMaterial3D: # Creates the shared material used by every generated terrain surface.
    var material: StandardMaterial3D = StandardMaterial3D.new() # Allocates one reusable physically based terrain material.
    material.vertex_color_use_as_albedo = true # Uses generated elevation and slope colours as the material's base colour.
    material.roughness = 0.96 # Keeps untextured natural terrain broadly matte.
    material.metallic = 0.0 # Prevents ordinary soil, grass, rock, and snow from behaving as metal.
    return material # Returns the shared terrain material.

func _create_water_material() -> StandardMaterial3D: # Creates the shared transparent material used by every clipped water surface and transition curtain.
    var material: StandardMaterial3D = StandardMaterial3D.new() # Allocates one reusable physically based water material.
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA # Enables ordinary alpha blending without requiring overlapping sea planes.
    material.cull_mode = BaseMaterial3D.CULL_DISABLED # Renders horizontal surfaces and vertical level transitions from either viewing side.
    material.albedo_color = Color(0.045, 0.19, 0.25, 0.74) # Gives water a deep desaturated blue-green colour with visible transparency.
    material.roughness = 0.18 # Keeps broad water surfaces smoother and more reflective than the surrounding terrain.
    material.metallic = 0.0 # Keeps water dielectric rather than metallic.
    return material # Returns the shared water material.
