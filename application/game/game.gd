extends Node3D # Owns and initializes the active world and player composition.

const PLAYER_SPAWN_CHUNK_COORDINATE: Vector2i = Vector2i.ZERO # Identifies the terrain chunk used for the initial player start.
const PLAYER_SPAWN_PROBE_DISTANCE: float = 512.0 # Starts the player collider high enough to sweep down onto any expected terrain elevation.
const PLAYER_SPAWN_CLEARANCE: float = 0.08 # Leaves a small separation above the collision surface after the downward shape cast.
const TERRAIN_COLLISION_MASK: int = 1 # Restricts spawn placement queries to the terrain physics layer.
const SPAWN_QUERY_ATTEMPTS: int = 3 # Allows physics synchronization more than one frame before using the height-sample fallback.
const PLAYER_SPAWN_FALLBACK_CLEARANCE: float = 16.0 # Keeps the emergency sampled-height fallback far above all nearby terrain variation.

@onready var _terrain: InfiniteTerrain = $World/Terrain # Stores the active infinite terrain controller.
@onready var _dynamic_entities: Node3D = $DynamicEntities # Owns active entities that participate in floating-origin rebasing.
@onready var _player: FirstPersonPlayer = $DynamicEntities/Player # Stores the active first-person player instance.

func _ready() -> void: # Defers world initialization until every child node has completed its own ready sequence.
    _initialize_game.call_deferred() # Starts the collision-synchronized spawn sequence outside the scene-tree ready callback.

func _initialize_game() -> void: # Builds nearby collision and places the complete player capsule onto the resolved physical surface.
    _player.set_physics_process(false) # Prevents gravity and movement while terrain collision and spawn placement are unresolved.
    _player.velocity = Vector3.ZERO # Clears inherited movement before positioning the player for the downward collision query.
    var spawn_horizontal: Vector2 = _get_player_spawn_horizontal() # Calculates a spawn point safely inside the selected terrain chunk.
    var sampled_height: float = _terrain.get_height_at(spawn_horizontal) # Samples terrain only to establish a high collision-query starting point.
    var provisional_position: Vector3 = Vector3(spawn_horizontal.x, sampled_height + PLAYER_SPAWN_PROBE_DISTANCE, spawn_horizontal.y) # Places the player collider well above the expected surface.
    _player.global_position = provisional_position # Keeps the active player completely clear while terrain collision enters the physics space.
    _terrain.initialize(_player, _dynamic_entities) # Builds the initial collision neighbourhood and registers floating-origin participants.
    var resolved_position: Vector3 = await _resolve_player_spawn_position(provisional_position, sampled_height) # Sweeps the actual player capsule down against synchronized collision.
    _player.global_position = resolved_position # Places the player at the highest safe position immediately above the terrain surface.
    _player.velocity = Vector3.ZERO # Prevents any pre-spawn velocity from affecting the first active physics frame.
    await get_tree().physics_frame # Lets the physics server register the final player transform before movement begins.
    _player.set_physics_process(true) # Enables normal player movement only after collision-backed placement is complete.

func _resolve_player_spawn_position(provisional_position: Vector3, sampled_height: float) -> Vector3: # Finds a non-overlapping root position using the player's complete collision capsule.
    var downward_motion: Vector3 = Vector3.DOWN * PLAYER_SPAWN_PROBE_DISTANCE * 2.0 # Sweeps from safely above the surface to safely below every expected terrain elevation.
    for _attempt: int in range(SPAWN_QUERY_ATTEMPTS): # Retries across physics frames while newly created terrain shapes synchronize.
        await get_tree().physics_frame # Waits for generated collision shapes to become queryable in the physics space.
        var safe_fraction: float = _cast_player_toward_terrain(downward_motion) # Finds the maximum safe fraction of the downward capsule motion.
        if safe_fraction < 1.0: # Detects a terrain collision along the complete downward sweep.
            return provisional_position + downward_motion * safe_fraction + Vector3.UP * PLAYER_SPAWN_CLEARANCE # Returns the collision-safe player root with a small separation margin.
    return Vector3(provisional_position.x, sampled_height + PLAYER_SPAWN_FALLBACK_CLEARANCE, provisional_position.z) # Falls back above the authored height sample rather than ever placing the player inside terrain.

func _cast_player_toward_terrain(downward_motion: Vector3) -> float: # Queries how far the player's full collision shape can descend without intersecting terrain.
    var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new() # Creates the reusable parameter container required by direct-space shape queries.
    query.shape = _player.get_collision_shape() # Uses the exact capsule resource that controls player movement collision.
    query.transform = _player.global_transform * _player.get_collision_local_transform() # Places the query shape at the player's current high provisional transform.
    query.motion = downward_motion # Requests one continuous downward sweep instead of trusting a centre-point height sample.
    query.collision_mask = TERRAIN_COLLISION_MASK # Limits the query to the terrain collision layer.
    query.collide_with_bodies = true # Allows the shape cast to detect streamed StaticBody3D terrain chunks.
    query.collide_with_areas = false # Excludes non-solid trigger areas from spawn placement.
    query.margin = PLAYER_SPAWN_CLEARANCE # Preserves a small separation from the contacted terrain surface.
    var excluded_bodies: Array[RID] = [_player.get_rid()] # Prevents the player's own body from appearing in its spawn query.
    query.exclude = excluded_bodies # Applies the explicit body exclusion list to the query.
    var cast_result: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query) # Performs the capsule sweep against synchronized world collision.
    if cast_result.size() < 2: # Handles an invalid or unavailable query result defensively.
        return 1.0 # Reports no resolved collision so the caller can wait and retry.
    return cast_result[0] # Returns the documented maximum safe proportion of the requested motion.

func _get_player_spawn_horizontal() -> Vector2: # Converts the selected spawn chunk into a point centred away from exposed chunk edges.
    var chunk_origin: Vector2 = Vector2(PLAYER_SPAWN_CHUNK_COORDINATE) * TerrainConfiguration.CHUNK_SIZE # Calculates the selected chunk's horizontal world origin.
    var chunk_centre_offset: Vector2 = Vector2.ONE * TerrainConfiguration.CHUNK_SIZE * 0.5 # Calculates the offset from the chunk origin to its centre.
    return chunk_origin + chunk_centre_offset # Returns a stable spawn point fully surrounded by the chunk surface.
