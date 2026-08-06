extends Node3D # Streams dense deterministic smooth trees and boulders independently from terrain mesh generation.
class_name WorldDecorationStreamer # Makes the optimized decoration system available to the game composition root.

const VISUAL_RADIUS: int = 5 # Keeps a broad 2.8-kilometre decoration field while reducing loaded decoration chunks from 169 to 121.
const COLLISION_RADIUS: int = 1 # Keeps physical shapes in a three-by-three chunk area instead of the original five-by-five area.
const NEAR_LOD_RADIUS: int = 1 # Uses full decoration geometry only in chunks immediately surrounding the player.
const MEDIUM_LOD_RADIUS: int = 3 # Uses the middle detail tier before switching the outer visible rings to minimal silhouettes.
const INITIAL_BUILD_RADIUS: int = 0 # Builds only the current decoration chunk synchronously to reduce startup stalls.
const CHUNKS_BUILT_PER_FRAME: int = 1 # Limits dense placement and MultiMesh creation to one missing chunk per rendered frame.
const LOD_UPDATES_PER_FRAME: int = 4 # Spreads retained-chunk LOD buffer rebuilds across frames after crossing a chunk boundary.
const STREAM_STATE_REFRESH_INTERVAL: float = 0.15 # Avoids checking chunk, LOD, and floating-origin state every rendered frame.
const SPAWN_EXCLUSION_RADIUS: float = 32.0 # Keeps the immediate shoreline start clear of trunks, rocks, and spawn-cast interference.
const INVALID_CHUNK_COORDINATE: Vector2i = Vector2i(2_147_483_647, 2_147_483_647) # Forces the first streaming refresh after initialization.

var _terrain: InfiniteTerrain # Supplies authoritative height, water, and floating-origin coordinate conversion.
var _player: Node3D # Identifies the moving subject that controls decoration streaming.
var _sampler: WorldDecorationSampler # Generates deterministic dense placements from global scatter grids and density noise.
var _mesh_library: WorldDecorationMeshLibrary # Owns shared LOD meshes and reusable primitive collision resources.
var _current_chunk_coordinate: Vector2i = INVALID_CHUNK_COORDINATE # Stores the active streaming centre around the player.
var _chunks: Dictionary[Vector2i, WorldDecorationChunk] = {} # Stores every loaded decoration chunk by absolute world-grid coordinate.
var _desired_chunks: Dictionary[Vector2i, bool] = {} # Stores the current visible decoration set.
var _pending_chunks: Array[Vector2i] = [] # Holds missing chunks in near-to-far generation order.
var _pending_chunk_index: int = 0 # Tracks the next queued coordinate without repeatedly shifting the array.
var _pending_lod_updates: Array[Vector2i] = [] # Holds retained chunks that crossed a visual detail boundary.
var _pending_lod_index: int = 0 # Tracks the next LOD update without shifting the queue.
var _last_origin_local_position: Vector2 = Vector2(INF, INF) # Detects floating-origin changes so loaded decoration chunks remain aligned.
var _state_refresh_elapsed: float = 0.0 # Accumulates time between inexpensive stream-state checks.
var _initialized: bool = false # Tracks whether the terrain-backed initial decoration neighbourhood has been created.

func _ready() -> void: # Resolves game-scene dependencies while waiting for shoreline spawn initialization to finish.
    var terrain_node: Node = get_node_or_null("../World/Terrain") # Finds the active terrain controller mounted by the game scene.
    var player_node: Node = get_node_or_null("../DynamicEntities/Player") # Finds the active first-person player mounted by the game scene.
    if terrain_node is InfiniteTerrain: # Verifies the expected terrain type before storing it.
        _terrain = terrain_node as InfiniteTerrain # Stores exact height, water, and floating-origin services.
    if player_node is Node3D: # Verifies the expected spatial player dependency.
        _player = player_node as Node3D # Stores the subject that controls streaming and collision distance.

func initialize(terrain: InfiniteTerrain, player: Node3D, spawn_world_position: Vector2) -> void: # Connects the streamer and builds the current dense decoration chunk.
    if _initialized: # Detects an accidental repeated initialization request.
        return # Preserves the existing deterministic streamed state.
    _terrain = terrain # Stores the exact world query and coordinate-conversion service.
    _player = player # Stores the subject that controls streaming distance and collision.
    _mesh_library = WorldDecorationMeshLibrary.new() # Builds every shared smooth LOD and collision resource once.
    _sampler = WorldDecorationSampler.new(_terrain) # Creates deterministic dense scatter fields using the established terrain world seed.
    _sampler.set_exclusion_area(spawn_world_position, SPAWN_EXCLUSION_RADIUS) # Protects the immediate player start from generated obstacles.
    _current_chunk_coordinate = _get_chunk_coordinate(_get_player_world_position()) # Calculates the initial absolute decoration chunk coordinate.
    _refresh_streaming_set(_current_chunk_coordinate) # Builds desired and queued chunk coordinates around the player.
    _build_initial_area(_current_chunk_coordinate) # Creates only the current visible and collidable chunk synchronously.
    _refresh_collision_states() # Applies the reduced collision radius to the initial chunk.
    _update_chunk_local_positions() # Aligns all generated chunks with the terrain's current floating origin.
    _initialized = true # Marks the streamer ready for ordinary bounded updates.

func _process(delta: float) -> void: # Advances bounded dense streaming while checking expensive state at a reduced frequency.
    if not _initialized: # Detects the startup period before the game finishes collision-backed shoreline placement.
        _try_initialize_from_game_scene() # Initializes only after terrain chunks exist and player physics has resumed.
        return # Defers ordinary streaming until dependencies and spawn position are authoritative.
    if _terrain == null or _player == null: # Handles dependencies removed unexpectedly after initialization.
        return # Skips work while the active world is unavailable.
    _state_refresh_elapsed += delta # Accumulates rendered time between stream-centre and floating-origin checks.
    if _state_refresh_elapsed >= STREAM_STATE_REFRESH_INTERVAL: # Detects the next bounded state refresh.
        _state_refresh_elapsed = 0.0 # Restarts the inexpensive interval.
        _update_chunk_positions_if_origin_changed() # Keeps every loaded object aligned after terrain rebases the local world.
        var player_chunk_coordinate: Vector2i = _get_chunk_coordinate(_get_player_world_position()) # Finds the player's current absolute decoration chunk.
        if player_chunk_coordinate != _current_chunk_coordinate: # Detects movement across a chunk boundary.
            _current_chunk_coordinate = player_chunk_coordinate # Stores the new streaming centre.
            _refresh_streaming_set(_current_chunk_coordinate) # Rebuilds desired, queued, unloaded, LOD, and collision states.
    _build_pending_chunks() # Generates at most one missing dense object chunk this frame.
    _apply_pending_lod_updates() # Rebuilds only a few retained-chunk LOD buffers per frame to avoid boundary spikes.

func _try_initialize_from_game_scene() -> void: # Detects completion of the existing deferred terrain and player spawn sequence.
    if _terrain == null or _player == null: # Waits for both scene dependencies to resolve.
        return # Leaves startup polling active.
    if _terrain.get_loaded_chunk_count() <= 0: # Detects whether the terrain controller has completed its initial synchronous chunk build.
        return # Waits until authoritative nearby ground and water geometry exist.
    if not _player.is_physics_processing(): # Detects the period while the game root deliberately suspends movement for spawn placement.
        return # Waits until the final collision-safe player position has been applied.
    var player_world_position: Vector3 = _terrain.local_to_world_position(_player.global_position) # Converts the resolved shoreline start into stable absolute coordinates.
    initialize(_terrain, _player, Vector2(player_world_position.x, player_world_position.z)) # Builds decorations while protecting the complete immediate spawn area.

func get_loaded_chunk_count() -> int: # Reports the number of currently retained decoration chunks for profiling.
    return _chunks.size() # Returns both populated and empty generated chunk records.

func _refresh_streaming_set(centre: Vector2i) -> void: # Recalculates every decoration chunk required around a new streaming centre.
    _desired_chunks.clear() # Removes coordinates from the previous visible set.
    _pending_chunks.clear() # Discards stale queue ordering before rebuilding near-to-far work.
    _pending_chunk_index = 0 # Restarts sequential queue reading.
    for ring: int in range(VISUAL_RADIUS + 1): # Visits square chunk rings from nearest to farthest.
        _append_ring_coordinates(centre, ring) # Adds every coordinate belonging to the current ring.
    var chunks_to_remove: Array[Vector2i] = [] # Collects obsolete chunks without mutating the dictionary during iteration.
    for chunk_coordinate: Vector2i in _chunks.keys(): # Examines every currently loaded decoration chunk.
        if not _desired_chunks.has(chunk_coordinate): # Detects chunks that left the visible radius.
            chunks_to_remove.append(chunk_coordinate) # Defers removal until iteration has completed.
    for chunk_coordinate: Vector2i in chunks_to_remove: # Removes every no-longer-visible object chunk.
        var chunk: WorldDecorationChunk = _chunks[chunk_coordinate] # Retrieves the streamable chunk node.
        _chunks.erase(chunk_coordinate) # Removes the coordinate from active lookup immediately.
        chunk.queue_free() # Releases MultiMeshes, placements, collision owners, and the chunk node at frame end.
    _refresh_collision_states() # Re-evaluates physical interaction immediately around the new centre.
    _queue_lod_updates() # Defers retained-chunk visual LOD rebuilds across several rendered frames.

func _append_ring_coordinates(centre: Vector2i, ring: int) -> void: # Adds one deterministic square ring of desired chunk coordinates.
    for offset_z: int in range(-ring, ring + 1): # Visits each row crossing the current square ring.
        for offset_x: int in range(-ring, ring + 1): # Visits each column crossing the current square ring.
            if maxi(absi(offset_x), absi(offset_z)) != ring: # Skips coordinates inside the current perimeter.
                continue # Continues until reaching a coordinate exactly on the ring edge.
            var chunk_coordinate: Vector2i = centre + Vector2i(offset_x, offset_z) # Converts local ring offset into absolute chunk space.
            _desired_chunks[chunk_coordinate] = true # Marks the coordinate as required for rendering.
            if _chunks.has(chunk_coordinate): # Detects a chunk retained from the previous streaming set.
                continue # Avoids rebuilding existing objects.
            _pending_chunks.append(chunk_coordinate) # Queues the missing chunk in useful near-to-far order.

func _build_pending_chunks() -> void: # Builds a bounded number of queued dense decoration chunks during the current frame.
    var chunks_built: int = 0 # Tracks completed work against the per-frame budget.
    while chunks_built < CHUNKS_BUILT_PER_FRAME and _pending_chunk_index < _pending_chunks.size(): # Continues while budget and queued work remain.
        var chunk_coordinate: Vector2i = _pending_chunks[_pending_chunk_index] # Retrieves the next missing coordinate without shifting the queue.
        _pending_chunk_index += 1 # Advances sequentially to the next queued item.
        if not _desired_chunks.has(chunk_coordinate): # Detects stale work after rapid player movement.
            continue # Skips chunks that are no longer visible.
        if _chunks.has(chunk_coordinate): # Detects a chunk created synchronously or through an earlier queue entry.
            continue # Avoids duplicate generation.
        _build_chunk(chunk_coordinate) # Generates deterministic placements and their LOD-batched visuals.
        chunks_built += 1 # Consumes one unit of the current frame's generation budget.

func _build_initial_area(centre: Vector2i) -> void: # Builds only the current decoration chunk during startup.
    for offset_z: int in range(-INITIAL_BUILD_RADIUS, INITIAL_BUILD_RADIUS + 1): # Visits the configured startup rows.
        for offset_x: int in range(-INITIAL_BUILD_RADIUS, INITIAL_BUILD_RADIUS + 1): # Visits the configured startup columns.
            var chunk_coordinate: Vector2i = centre + Vector2i(offset_x, offset_z) # Converts the local offset into absolute chunk space.
            if _chunks.has(chunk_coordinate): # Detects a chunk already built through another path.
                continue # Avoids duplicate nodes and placements.
            _build_chunk(chunk_coordinate) # Creates the startup object chunk synchronously.

func _build_chunk(chunk_coordinate: Vector2i) -> void: # Generates one dense decoration chunk and installs it at the current floating-origin position.
    var placements: Array[WorldDecorationPlacement] = _sampler.sample_chunk(chunk_coordinate, _mesh_library.get_boulder_variant_count()) # Generates deterministic trees and rounded rocks for this absolute chunk.
    var chunk: WorldDecorationChunk = WorldDecorationChunk.new() # Creates the independently streamable decoration body.
    chunk.name = "DecorationChunk_%d_%d" % [chunk_coordinate.x, chunk_coordinate.y] # Gives the runtime node a coordinate-derived diagnostic name.
    chunk.position = _get_chunk_local_position(chunk_coordinate) # Places chunk-local transforms relative to the current floating origin.
    add_child(chunk) # Adds the chunk beneath the dedicated decoration streamer.
    var chunk_distance: int = _get_chunk_distance(chunk_coordinate) # Measures the new chunk against the active player-centred grid.
    chunk.configure(placements, _mesh_library, _get_lod_level(chunk_distance)) # Creates draw-batched visuals against the appropriate shared distance mesh.
    _chunks[chunk_coordinate] = chunk # Registers the chunk for streaming, collision, LOD, and rebase alignment.
    chunk.set_collision_active(chunk_distance <= COLLISION_RADIUS) # Enables physical objects only in the reduced near-player region.

func _get_player_world_position() -> Vector2: # Converts the player's current local scene transform into stable absolute world coordinates.
    var world_position: Vector3 = _terrain.local_to_world_position(_player.global_position) # Uses the same floating-origin conversion as movement and water systems.
    return Vector2(world_position.x, world_position.z) # Returns the horizontal coordinate used by decoration chunking.

func _get_chunk_coordinate(world_position: Vector2) -> Vector2i: # Converts an absolute horizontal position into the shared integer chunk grid.
    return Vector2i(floori(world_position.x / TerrainConfiguration.CHUNK_SIZE), floori(world_position.y / TerrainConfiguration.CHUNK_SIZE)) # Uses floor division so negative world coordinates remain stable.

func _get_chunk_local_position(chunk_coordinate: Vector2i) -> Vector3: # Converts an absolute decoration chunk coordinate into current near-origin scene space.
    var world_position: Vector3 = Vector3(float(chunk_coordinate.x) * TerrainConfiguration.CHUNK_SIZE, 0.0, float(chunk_coordinate.y) * TerrainConfiguration.CHUNK_SIZE) # Calculates the absolute back-left chunk origin.
    return _terrain.world_to_local_position(world_position) # Removes the terrain's accumulated floating-origin offset.

func _update_chunk_positions_if_origin_changed() -> void: # Detects terrain rebases without requiring internal origin state access.
    var local_world_origin: Vector3 = _terrain.world_to_local_position(Vector3.ZERO) # Reads where absolute world origin currently lies in local scene space.
    var local_origin_horizontal: Vector2 = Vector2(local_world_origin.x, local_world_origin.z) # Extracts the floating-origin translation signature.
    if local_origin_horizontal.is_equal_approx(_last_origin_local_position): # Detects whether terrain has retained the same local origin.
        return # Leaves every chunk transform unchanged.
    _update_chunk_local_positions() # Repositions all loaded object chunks after a terrain rebase.

func _update_chunk_local_positions() -> void: # Aligns all loaded decoration chunks with the terrain's current floating origin.
    var local_world_origin: Vector3 = _terrain.world_to_local_position(Vector3.ZERO) # Reads the current local representation of absolute origin.
    _last_origin_local_position = Vector2(local_world_origin.x, local_world_origin.z) # Stores the signature used to detect later changes.
    for chunk_coordinate: Vector2i in _chunks.keys(): # Visits every loaded decoration chunk.
        var chunk: WorldDecorationChunk = _chunks[chunk_coordinate] # Retrieves the chunk requiring alignment.
        chunk.position = _get_chunk_local_position(chunk_coordinate) # Repositions all batched visuals and collision together without regeneration.

func _get_chunk_distance(chunk_coordinate: Vector2i) -> int: # Measures square-grid distance from one decoration chunk to the player.
    var offset: Vector2i = chunk_coordinate - _current_chunk_coordinate # Calculates the signed chunk-grid offset.
    return maxi(absi(offset.x), absi(offset.y)) # Uses Chebyshev distance matching the square streamed rings.

func _get_lod_level(chunk_distance: int) -> int: # Selects the shared decoration mesh detail appropriate to one chunk ring.
    if chunk_distance <= NEAR_LOD_RADIUS: # Detects chunks where individual trunks, branches, and rocks are clearly readable.
        return WorldDecorationMeshLibrary.LOD_NEAR # Uses the fullest optimized smooth geometry.
    if chunk_distance <= MEDIUM_LOD_RADIUS: # Detects the middle visible distance band.
        return WorldDecorationMeshLibrary.LOD_MEDIUM # Uses substantially reduced shared geometry.
    return WorldDecorationMeshLibrary.LOD_FAR # Uses minimal smooth silhouettes and disables their shadows.

func _refresh_collision_states() -> void: # Applies reduced collision immediately to every retained decoration chunk.
    for chunk_coordinate: Vector2i in _chunks.keys(): # Visits every currently loaded decoration chunk.
        var chunk: WorldDecorationChunk = _chunks[chunk_coordinate] # Retrieves the streamable object body.
        chunk.set_collision_active(_get_chunk_distance(chunk_coordinate) <= COLLISION_RADIUS) # Retains physical shapes only in the immediate three-by-three area.

func _queue_lod_updates() -> void: # Queues retained chunks for bounded visual detail changes after the streaming centre moves.
    _pending_lod_updates.clear() # Discards stale LOD work from the previous centre.
    _pending_lod_index = 0 # Restarts sequential queue reading.
    for ring: int in range(VISUAL_RADIUS + 1): # Prioritizes nearby visual changes before distant rings.
        for offset_z: int in range(-ring, ring + 1): # Visits each row crossing the current square ring.
            for offset_x: int in range(-ring, ring + 1): # Visits each column crossing the current square ring.
                if maxi(absi(offset_x), absi(offset_z)) != ring: # Skips coordinates inside the current perimeter.
                    continue # Continues until reaching the active ring edge.
                var chunk_coordinate: Vector2i = _current_chunk_coordinate + Vector2i(offset_x, offset_z) # Converts the ring offset into absolute chunk space.
                if _chunks.has(chunk_coordinate): # Detects a retained chunk requiring a tier check.
                    _pending_lod_updates.append(chunk_coordinate) # Queues near-to-far work without rebuilding unchanged tiers immediately.

func _apply_pending_lod_updates() -> void: # Applies only a few retained-chunk LOD changes during the current rendered frame.
    var updates_applied: int = 0 # Tracks work against the per-frame LOD rebuild budget.
    while updates_applied < LOD_UPDATES_PER_FRAME and _pending_lod_index < _pending_lod_updates.size(): # Continues while budget and queued work remain.
        var chunk_coordinate: Vector2i = _pending_lod_updates[_pending_lod_index] # Retrieves the next retained coordinate without shifting the queue.
        _pending_lod_index += 1 # Advances sequentially to the next item.
        if not _chunks.has(chunk_coordinate): # Detects a chunk unloaded after the queue was built.
            continue # Skips stale work safely.
        var chunk: WorldDecorationChunk = _chunks[chunk_coordinate] # Retrieves the retained object chunk.
        chunk.set_lod_level(_get_lod_level(_get_chunk_distance(chunk_coordinate))) # Rebuilds buffers only if this chunk actually crossed an LOD tier.
        updates_applied += 1 # Consumes one bounded update slot even when the chunk was already on the correct tier.
