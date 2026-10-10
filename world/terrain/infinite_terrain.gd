extends Node3D # Streams deterministic procedural terrain and tiered water chunks around a tracked player.
class_name InfiniteTerrain # Makes the terrain controller available to the game composition root.

signal origin_shifted # Notify static scenery after a completed floating-origin shift.

const WATER_PRESENCE_EPSILON: float = 0.02 # Matches shoreline clipping tolerance when deciding whether a real water volume exists.
const INVALID_WATER_CELL: Vector2i = Vector2i(2_147_483_647, 2_147_483_647) # Forces the first exact water query to populate its cell cache.

const INACTIVE_COLLISION_LIMIT: int = 16 # Bound reusable distant physics independently of the visual radius.
var _inactive_collisions: Array[TerrainChunk] = [] # Keep inactive shapes in least-recently-used order.
const HEIGHT_CACHE_LIMIT = 32768
var _height_cache: Dictionary = {}
var _building: Dictionary = {}
var _height_sampler: TerrainHeightSampler # Supplies one continuous deterministic height function for every terrain chunk.
var _mesh_builder: TerrainMeshBuilder # Converts height samples into seam-consistent renderable ground meshes.
var _terrain_material: StandardMaterial3D # Shades generated ground vertices using their authored terrain colours.
var _water_level_sampler: TerrainWaterLevelSampler # Selects flat local water elevations corresponding to the world's major terrain tiers.
var _water_mesh_builder: TerrainWaterMeshBuilder # Clips local water surfaces against terrain and seals transitions between different levels.
var _water_material: Material # Shades all generated water surfaces with one shared transparent material.
var _player: Node3D # Identifies the moving world subject that controls streaming.
var _rebase_root: Node3D # Owns active world entities that must remain aligned when the floating origin moves.
var _world_origin_offset: Vector2 = Vector2.ZERO # Tracks the absolute world coordinate represented by local scene origin.
var _current_chunk_coordinate: Vector2i = INVALID_WATER_CELL # Forces the first streaming refresh after initialization.
var _chunks: Dictionary[Vector2i, TerrainChunk] = {} # Stores every currently loaded terrain and water chunk by world-grid coordinate.
var _desired_chunks: Dictionary[Vector2i, bool] = {} # Stores the current visible streaming set around the player.
var _pending_chunks: Array[Vector2i] = [] # Holds missing chunks in near-to-far generation order.
var _pending_chunk_index: int = 0 # Tracks the next queued coordinate without shifting the array on every build.
var _water_query_cell_coordinate: Vector2i = INVALID_WATER_CELL # Stores the last exact water cell sampled for gameplay and view effects.
var _water_query_level: float = 0.0 # Caches the rendered flat level assigned to the active water cell.
var _water_query_top_left_height: float = 0.0 # Caches the terrain height at the active cell's back-left corner.
var _water_query_top_right_height: float = 0.0 # Caches the terrain height at the active cell's back-right corner.
var _water_query_bottom_left_height: float = 0.0 # Caches the terrain height at the active cell's forward-left corner.
var _water_query_bottom_right_height: float = 0.0 # Caches the terrain height at the active cell's forward-right corner.

func _ready() -> void: # Creates reusable terrain and water resources before the game composition root initializes the player.
    _height_sampler = TerrainHeightSampler.new() # Creates the deterministic world-height service.
    _terrain_material = _create_terrain_material() # Creates one shared material for every streamed ground chunk.
    _mesh_builder = TerrainMeshBuilder.new(_height_sampler, _terrain_material,self) # Creates the isolated ground mesh-construction service.
    _water_level_sampler = TerrainWaterLevelSampler.new() # Creates the tier-aware flat water-level service.
    _water_material = _create_water_material() # Creates one shared transparent material for every streamed water surface.
    _water_mesh_builder = TerrainWaterMeshBuilder.new(_height_sampler, _water_level_sampler, _water_material) # Creates the clipped water mesh-construction service.

func initialize(player: Node3D, rebase_root: Node3D) -> void:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile_initialize(player, rebase_root)
        return
    var _profile_token = RuntimeProfiler.begin("terrain.initialize")
    _profile_initialize(player, rebase_root)
    RuntimeProfiler.end(_profile_token)

func _profile_initialize(player: Node3D, rebase_root: Node3D) -> void: # Connects terrain streaming, active entities, and safe initial spawn geometry.
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

func _process(_delta: float) -> void:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__process(_delta)
        return
    var _profile_token = RuntimeProfiler.begin("terrain.stream")
    _profile__process(_delta)
    RuntimeProfiler.end(_profile_token)

func _profile__process(_delta: float) -> void: # Advances bounded terrain and water streaming work each rendered frame.
    if _player == null: # Waits until the game composition root provides a player reference.
        return # Skips streaming without a tracked subject.
    var player_chunk_coordinate: Vector2i = _get_chunk_coordinate(_get_player_world_position()) # Finds the player's current absolute world-grid coordinate.
    if player_chunk_coordinate != _current_chunk_coordinate: # Detects movement across a terrain chunk boundary.
        _current_chunk_coordinate = player_chunk_coordinate # Stores the new streaming centre.
        _refresh_streaming_set(_current_chunk_coordinate) # Rebuilds desired, queued, unloaded, and collision states.
    _build_pending_chunks() # Generates a fixed number of missing terrain and water chunks without blocking the full frame.

func get_height_at(world_position: Vector2) -> float: # Exposes the authoritative ground height field to spawning and future world systems.
    if _height_cache.has(world_position): return _height_cache[world_position]
    var height = _height_sampler.sample_height(world_position.x,world_position.y)
    CacheEviction.make_room(_height_cache, HEIGHT_CACHE_LIMIT) # Retain most cached heights at the capacity boundary.
    _height_cache[world_position] = height
    return height

func get_water_sample_at(world_position: Vector2) -> Dictionary: # Exposes one water-result interface for production and legacy terrain.
    var present: bool = has_water_at(world_position) # Respects custom terrain occupancy implementations.
    var level: float = get_water_level_at(world_position) if present else -INF # Returns an absent surface for dry legacy results.
    var ground: float = get_height_at(world_position) # Preserves custom terrain height providers in legacy fixtures.
    return {"present": present, "surface_height": level, "ground_height": ground, "depth": maxf(0.0, level - ground) if present else 0.0, "body_id": "", "downstream_id": "", "flow": Vector2.ZERO} # Leaves body metadata to the production planner override.

func get_water_level_at(world_position: Vector2) -> float: # Exposes the exact flat water-cell level used by rendering and gameplay systems.
    _update_water_query_cache(world_position) # Populates the active rendered-cell data only when the query crosses a cell boundary.
    return _water_query_level # Returns the same deterministic level assigned to the visible water polygon.

func has_water_at(world_position: Vector2) -> bool: # Reports whether the clipped water mesh occupies one absolute horizontal position.
    _update_water_query_cache(world_position) # Ensures the exact rendered cell level and corner heights are available.
    var rendered_terrain_height: float = _sample_cached_water_grid_terrain_height(world_position) # Reconstructs the linearly interpolated terrain surface used by water clipping.
    return rendered_terrain_height < _water_query_level - WATER_PRESENCE_EPSILON # Matches shoreline clipping so dry high ground never behaves as water.

func local_to_world_position(local_position: Vector3) -> Vector3: # Converts a near-origin scene position into a stable absolute procedural-world position.
    return Vector3(local_position.x + _world_origin_offset.x, local_position.y, local_position.z + _world_origin_offset.y) # Adds the accumulated horizontal world offset without changing elevation.

func world_to_local_position(world_position: Vector3) -> Vector3: # Converts a stable absolute procedural-world position into the current near-origin scene space.
    return Vector3(world_position.x - _world_origin_offset.x, world_position.y, world_position.z - _world_origin_offset.y) # Removes the accumulated horizontal world offset without changing elevation.

func get_loaded_chunk_count() -> int: # Reports the current loaded chunk count for profiling and future diagnostics.
    return _chunks.size() # Returns the number of visual chunk nodes currently retained.

func _update_water_query_cache(world_position: Vector2) -> void: # Caches one exact rendered water cell so continuous player queries avoid repeated terrain generation.
    var water_cell_count: int = TerrainConfiguration.WATER_RESOLUTION - 1 # Calculates the number of water cells along one terrain chunk axis.
    var water_cell_size: float = TerrainConfiguration.CHUNK_SIZE / float(water_cell_count) # Matches the cell size used by the water mesh builder.
    var cell_coordinate: Vector2i = Vector2i(floori(world_position.x / water_cell_size), floori(world_position.y / water_cell_size)) # Finds the globally stable rendered water cell, including negative coordinates.
    if cell_coordinate == _water_query_cell_coordinate: # Detects repeated player and camera queries inside the same cell.
        return # Reuses the cached level and four terrain corners without running procedural noise again.
    _water_query_cell_coordinate = cell_coordinate # Stores the new active cell before populating its deterministic data.
    var cell_origin_x: float = float(cell_coordinate.x) * water_cell_size # Calculates the absolute x coordinate of the cell's back-left corner.
    var cell_origin_z: float = float(cell_coordinate.y) * water_cell_size # Calculates the absolute z coordinate of the cell's back-left corner.
    var level_sample_x: float = cell_origin_x + water_cell_size * 0.5 # Reconstructs the exact x centre sampled by water mesh generation.
    var level_sample_z: float = cell_origin_z + water_cell_size * 0.5 # Reconstructs the exact z centre sampled by water mesh generation.
    _water_query_level = _water_level_sampler.sample_water_level(level_sample_x, level_sample_z) # Caches the exact flat level owned by the rendered cell.
    _water_query_top_left_height = get_height_at(Vector2(cell_origin_x, cell_origin_z)) # Caches the back-left terrain corner used by water clipping.
    _water_query_top_right_height = get_height_at(Vector2(cell_origin_x + water_cell_size, cell_origin_z)) # Caches the back-right terrain corner used by water clipping.
    _water_query_bottom_left_height = get_height_at(Vector2(cell_origin_x, cell_origin_z + water_cell_size)) # Caches the forward-left terrain corner used by water clipping.
    _water_query_bottom_right_height = get_height_at(Vector2(cell_origin_x + water_cell_size, cell_origin_z + water_cell_size)) # Caches the forward-right terrain corner used by water clipping.

func _sample_cached_water_grid_terrain_height(world_position: Vector2) -> float: # Interpolates the active cached terrain triangle exactly as the rendered water clipper does.
    var water_cell_count: int = TerrainConfiguration.WATER_RESOLUTION - 1 # Calculates the water grid cell count shared with mesh generation.
    var water_cell_size: float = TerrainConfiguration.CHUNK_SIZE / float(water_cell_count) # Calculates the world size of one rendered water cell.
    var cell_origin_x: float = float(_water_query_cell_coordinate.x) * water_cell_size # Reconstructs the cached cell's absolute x origin.
    var cell_origin_z: float = float(_water_query_cell_coordinate.y) * water_cell_size # Reconstructs the cached cell's absolute z origin.
    var local_x: float = clampf((world_position.x - cell_origin_x) / water_cell_size, 0.0, 1.0) # Converts the query x coordinate into cell-local interpolation space.
    var local_z: float = clampf((world_position.y - cell_origin_z) / water_cell_size, 0.0, 1.0) # Converts the query z coordinate into cell-local interpolation space.
    if local_x + local_z <= 1.0: # Selects the first triangle matching the terrain and water mesh diagonal.
        return _water_query_top_left_height + local_x * (_water_query_top_right_height - _water_query_top_left_height) + local_z * (_water_query_bottom_left_height - _water_query_top_left_height) # Interpolates height across the back-left triangle.
    return _water_query_bottom_right_height + (1.0 - local_z) * (_water_query_top_right_height - _water_query_bottom_right_height) + (1.0 - local_x) * (_water_query_bottom_left_height - _water_query_bottom_right_height) # Interpolates height across the forward-right triangle.

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
        _inactive_collisions.erase(chunk) # Release cache ownership when a visual chunk unloads.
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

func _build_pending_chunks() -> void:
    var scheduler = GenerationScheduler.instance
    if scheduler == null or not _water_mesh_builder is SeamlessTerrainWaterMeshBuilder:
        var built = 0
        while built < TerrainConfiguration.CHUNKS_BUILT_PER_FRAME and _pending_chunk_index < _pending_chunks.size():
            var cell = _pending_chunks[_pending_chunk_index]
            _pending_chunk_index += 1
            if not _desired_chunks.has(cell) or _chunks.has(cell): continue
            _build_chunk(cell)
            built += 1
        return
    if _building.size() >= GenerationScheduler.WORKER_LIMIT: return
    while _pending_chunk_index < _pending_chunks.size():
        var cell = _pending_chunks[_pending_chunk_index]
        _pending_chunk_index += 1
        if not _desired_chunks.has(cell) or _chunks.has(cell) or _building.has(cell): continue
        _building[cell] = true
        _prepare_background_chunk(cell,scheduler)
        break

func _prepare_background_chunk(cell: Vector2i, scheduler: GenerationScheduler):
    scheduler.active_owner = self
    scheduler.active_priority = 0 if maxi(absi(cell.x-_current_chunk_coordinate.x),absi(cell.y-_current_chunk_coordinate.y)) <= TerrainConfiguration.COLLISION_RADIUS+1 else 2
    var routes: Dictionary = {}
    var network = WorldPathNetwork.for_terrain(self)
    for offset in [Vector2i.ZERO,Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)]:
        if not await scheduler.checkpoint(self):
            _building.erase(cell)
            return
        routes[cell+offset] = network.cached_routes_in_chunk(cell+offset).duplicate(true)
    while not scheduler.has_worker_room():
        await scheduler.frame_started
        if not is_inside_tree() or scheduler._closing: return
    if not _desired_chunks.has(cell) or _chunks.has(cell):
        _building.erase(cell)
        return
    var job = TerrainGenerationJob.new(cell,routes)
    if not scheduler.submit(self,job.generate,func(data): _install_background_chunk(cell,data)):
        _building.erase(cell)
        _pending_chunks.append(cell)

func _install_background_chunk(cell: Vector2i, data: Array) -> void: # Spread uploads and physics preparation across admitted engine-operation frames.
    var scheduler: GenerationScheduler = GenerationScheduler.instance # Keep the owning scheduler stable across yields.
    if not await scheduler.operation_checkpoint(self): return # Stop safely during pause or teardown.
    if not _can_install(cell): return # Discard obsolete buffers before uploading anything.
    var started: int = Time.get_ticks_usec() # Measure only the ground upload stage.
    var ground: ArrayMesh = _mesh_builder.mesh_from_arrays(data[0]) # Upload the ground surface without combining other heavy stages.
    scheduler.record_operation(started) # Expose indivisible ground upload cost.
    if not await scheduler.operation_checkpoint(self): return # Defer the water upload to a later frame.
    if not _can_install(cell): return # Recheck streaming demand after every yield.
    started = Time.get_ticks_usec() # Begin the water upload measurement.
    var water: ArrayMesh = _water_mesh_builder.mesh_from_arrays(data[1]) # Upload the optional water surface separately.
    scheduler.record_operation(started) # Expose indivisible water upload cost.
    if not await scheduler.operation_checkpoint(self): return # Defer node and physics installation to another frame.
    if not _can_install(cell): return # Avoid duplicate installation after an explicit teleport build.
    started = Time.get_ticks_usec() # Begin the node and near-collider installation measurement.
    _install_meshes(cell, ground, water, data[2]) # Install consistent ground, water and exact CPU collision triangles together.
    scheduler.record_operation(started) # Record the final installation cost.
    _building.erase(cell) # Retain the in-flight guard until all stages have completed.

func _can_install(cell: Vector2i) -> bool: # Guard every resumed stage against travel and synchronous replacement.
    if _chunks.has(cell) or not _desired_chunks.has(cell): # Detect an obsolete generation result.
        _building.erase(cell) # Release the pending guard before discarding the result.
        if GenerationScheduler.instance != null: GenerationScheduler.instance.stale_jobs += 1 # Report stale staged results.
        return false # Release staged resources without touching the active scene.
    return true # Continue while the current streaming set still requires this coordinate.


func _build_initial_collision_area(centre: Vector2i) -> void: # Builds all chunks required for safe spawn collision before ordinary bounded streaming begins.
    for offset_z: int in range(-TerrainConfiguration.INITIAL_COLLISION_RADIUS, TerrainConfiguration.INITIAL_COLLISION_RADIUS + 1): # Visits every initial collision row around the spawn chunk.
        for offset_x: int in range(-TerrainConfiguration.INITIAL_COLLISION_RADIUS, TerrainConfiguration.INITIAL_COLLISION_RADIUS + 1): # Visits every initial collision column around the spawn chunk.
            var chunk_coordinate: Vector2i = centre + Vector2i(offset_x, offset_z) # Converts the local spawn-neighbourhood offset into a world chunk coordinate.
            _build_chunk_immediately(chunk_coordinate) # Creates the visual meshes and exact ground collision outside the ordinary per-frame budget.

func _build_chunk_immediately(chunk_coordinate: Vector2i) -> void: # Builds one required chunk outside the ordinary frame budget for safe spawning.
    if _chunks.has(chunk_coordinate): # Detects whether the required chunk already exists.
        return # Avoids duplicate mesh and collision creation.
    _build_chunk(chunk_coordinate) # Generates and installs the requested terrain and water chunk now.

func _build_chunk(chunk_coordinate: Vector2i) -> void:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__build_chunk(chunk_coordinate)
        return
    var _profile_token = RuntimeProfiler.begin("terrain.build_chunk")
    _profile__build_chunk(chunk_coordinate)
    RuntimeProfiler.end(_profile_token)

func _profile__build_chunk(chunk_coordinate: Vector2i) -> void: # Generates one terrain chunk with clipped water and installs its streamable runtime node.
    if _water_mesh_builder is SeamlessTerrainWaterMeshBuilder: # Shares final ground arrays during synchronous production startup.
        var ground: Array = _mesh_builder.build_chunk_arrays(chunk_coordinate) # Builds the final ground once before water clipping.
        var ground_mesh: ArrayMesh = _mesh_builder.mesh_from_arrays(ground) # Uploads the authoritative ground buffer.
        var water_arrays: Array = (_water_mesh_builder as SeamlessTerrainWaterMeshBuilder).build_chunk_arrays(chunk_coordinate, ground) # Clips water against completed ground without repeating terrain sampling.
        _install_meshes(chunk_coordinate, ground_mesh, _water_mesh_builder.mesh_from_arrays(water_arrays)) # Installs matching synchronous ground and water surfaces.
        return # Avoids the legacy independent sampling path.
    var terrain_mesh: ArrayMesh = _mesh_builder.build_chunk_mesh(chunk_coordinate) # Generates ground vertices, normals, colours, indices, and material assignment.
    var water_mesh: ArrayMesh = _water_mesh_builder.build_chunk_mesh(chunk_coordinate) # Generates only submerged water polygons and sealed local level transitions.
    _install_meshes(chunk_coordinate,terrain_mesh,water_mesh)

func _install_meshes(chunk_coordinate: Vector2i, terrain_mesh: ArrayMesh, water_mesh: ArrayMesh, faces: PackedVector3Array = PackedVector3Array()):
    var chunk: TerrainChunk = TerrainChunk.new() # Creates a lightweight streamable terrain body.
    chunk.name = "TerrainChunk_%d_%d" % [chunk_coordinate.x, chunk_coordinate.y] # Gives the runtime node a coordinate-derived diagnostic name.
    chunk.position = _get_chunk_local_position(chunk_coordinate) # Places local vertices relative to the current floating-world origin.
    add_child(chunk) # Adds the generated chunk to the active world scene.
    chunk.configure(terrain_mesh, water_mesh, faces) # Assigns the generated ground and optional water geometry and creates runtime nodes.
    _chunks[chunk_coordinate] = chunk # Registers the chunk for streaming, collision, and unloading.
    _set_chunk_collision(chunk, _is_collision_coordinate(chunk_coordinate)) # Enables exact ground collision immediately when the chunk is near the player.

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
    NearbyActorIndex.invalidate() # Discard combat buckets expressed in the preceding local origin.
    origin_shifted.emit() # Reposition static scenery only after the origin actually changes.

func _is_collision_coordinate(chunk_coordinate: Vector2i) -> bool: # Determines whether one loaded chunk is close enough for physical interaction.
    var offset: Vector2i = chunk_coordinate - _current_chunk_coordinate # Measures chunk-grid distance from the player.
    return maxi(absi(offset.x), absi(offset.y)) <= TerrainConfiguration.COLLISION_RADIUS # Uses a square near-player collision region that fully surrounds movement.

func _update_collision_states() -> void: # Enables exact ground collision nearby and releases it from distant visual chunks.
    for chunk_coordinate: Vector2i in _chunks.keys(): # Visits every currently loaded chunk.
        var chunk: TerrainChunk = _chunks[chunk_coordinate] # Retrieves the streamable terrain body for this coordinate.
        _set_chunk_collision(chunk, _is_collision_coordinate(chunk_coordinate)) # Applies the collision state required by player distance.

func _set_chunk_collision(chunk: TerrainChunk, enabled: bool) -> void: # Retain recently used distant shapes within a fixed memory bound.
    var was_active: bool = chunk.is_collision_active() # Identify actual transitions out of the physical neighbourhood.
    chunk.set_collision_active(enabled) # Reattach cached geometry before considering a rebuild.
    if enabled: # Remove active shapes from the inactive eviction queue.
        _inactive_collisions.erase(chunk) # Keep active collision outside the inactive cache limit.
    elif was_active: # Record only newly inactive shapes in recency order.
        _inactive_collisions.erase(chunk) # Avoid retaining duplicate cache entries.
        _inactive_collisions.append(chunk) # Prefer shapes from the most recently visited neighbourhood.
    while _inactive_collisions.size() > INACTIVE_COLLISION_LIMIT: # Enforce the bound during unbounded travel.
        var oldest: TerrainChunk = _inactive_collisions.pop_front() # Evict the least recently active retained collider.
        oldest.release_cached_collision() # Release expensive physics data without unloading the visible terrain.

func _create_terrain_material() -> StandardMaterial3D: # Creates the shared material used by every generated terrain surface.
    var material: StandardMaterial3D = StandardMaterial3D.new() # Allocates one reusable physically based terrain material.
    material.vertex_color_use_as_albedo = true # Uses generated elevation and slope colours as the material's base colour.
    material.roughness = 0.96 # Keeps untextured natural terrain broadly matte.
    material.metallic = 0.0 # Prevents ordinary soil, grass, rock, and snow from behaving as metal.
    return material # Returns the shared terrain material.

func _create_water_material() -> Material:
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = preload("res://world/biomes/stylized_water.gdshader")
    return material
