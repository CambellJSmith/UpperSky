extends Node3D # Owns and initializes the active world, player, and developer interface composition.

const PLAYER_SPAWN_FALLBACK_HORIZONTAL: Vector2 = Vector2.ZERO # Retains the guaranteed dry origin as an emergency fallback if no suitable shoreline is found.
const PLAYER_SPAWN_PROBE_DISTANCE: float = 512.0 # Starts the player collider high enough to sweep down onto any expected terrain elevation.
const PLAYER_SPAWN_CLEARANCE: float = 0.08 # Leaves a small separation above the collision surface after the downward shape cast.
const TERRAIN_COLLISION_MASK: int = 1 # Restricts spawn placement queries to the terrain physics layer.
const SPAWN_QUERY_ATTEMPTS: int = 3 # Allows physics synchronization more than one frame before using the height-sample fallback.
const PLAYER_SPAWN_FALLBACK_CLEARANCE: float = 16.0 # Keeps the emergency sampled-height fallback far above all nearby terrain variation.
const SHORE_SEARCH_DIRECTION_COUNT: int = 32 # Samples enough deterministic radial directions to find varied nearby shorelines without excessive startup work.
const SHORE_SEARCH_STEP: float = 64.0 # Advances outward in broad intervals before refining the first land-water transition on each ray.
const SHORE_SEARCH_MAXIMUM_RADIUS: float = 4096.0 # Searches several kilometres so the dry origin region can still resolve a genuine nearby shoreline.
const SHORE_SEARCH_REFINEMENT_STEPS: int = 7 # Narrows each detected transition to approximately half-metre precision.
const SHORE_SPAWN_INLAND_DISTANCE: float = 18.0 # Places the player safely on land while retaining an immediate view and walk to the water's edge.
const SHORE_SLOPE_SAMPLE_DISTANCE: float = 8.0 # Measures terrain variation across the same scale as the generated ground vertex spacing.
const SHORE_PREFERRED_CLEARANCE: float = 4.0 # Favours low banks a few metres above water instead of cliffs or barely dry polygons.
const SHORE_MINIMUM_DRY_CLEARANCE: float = 0.5 # Rejects candidates too close to the water plane to guarantee a visibly dry start.
const SHORE_MAXIMUM_PREFERRED_VARIATION: float = 6.0 # Penalizes steep local terrain while still allowing a fallback when every nearby shore is rough.

@onready var _terrain: InfiniteTerrain = $World/Terrain # Stores the active infinite terrain and water controller.
@onready var _dynamic_entities: Node3D = $DynamicEntities # Owns active entities that participate in floating-origin rebasing.
@onready var _player: FirstPersonPlayer = $DynamicEntities/Player # Stores the active first-person player instance.
@onready var _underwater_view: UnderwaterView = $UnderwaterView # Stores the camera-dependent underwater post-process controller.
@onready var _developer_console: DeveloperConsole = $DeveloperConsole # Stores the reusable tilde console that controls developer commands.

func _ready() -> void: # Connects environment and developer controls before deferring terrain-backed player initialization.
    _player.initialize_environment(_terrain) # Supplies authoritative terrain and water sampling directly to player movement.
    _underwater_view.initialize(_player, _terrain) # Supplies the active camera and water system to the underwater view effect.
    _developer_console.initialize(_player) # Supplies the active player directly without global state or signals.
    _initialize_game.call_deferred() # Starts the collision-synchronized spawn sequence outside the scene-tree ready callback.

func _initialize_game() -> void: # Builds nearby collision and places the complete player capsule onto dry terrain beside a resolved shoreline.
    _player.set_physics_process(false) # Prevents gravity and movement while terrain collision and spawn placement are unresolved.
    _player.velocity = Vector3.ZERO # Clears inherited movement before positioning the player for the downward collision query.
    var spawn_horizontal: Vector2 = _find_shoreline_spawn_horizontal() # Selects deterministic low-slope dry land immediately inland from real generated water.
    var sampled_height: float = _terrain.get_height_at(spawn_horizontal) # Samples terrain only to establish a high collision-query starting point.
    var provisional_position: Vector3 = Vector3(spawn_horizontal.x, sampled_height + PLAYER_SPAWN_PROBE_DISTANCE, spawn_horizontal.y) # Places the player collider well above the expected surface.
    _player.global_position = provisional_position # Keeps the active player completely clear while terrain collision enters the physics space.
    _terrain.initialize(_player, _dynamic_entities) # Builds the initial collision neighbourhood around the selected shoreline spawn and registers floating-origin participants.
    var resolved_position: Vector3 = await _resolve_player_spawn_position(provisional_position, sampled_height) # Sweeps the actual player capsule down against synchronized collision.
    _player.global_position = resolved_position # Places the player at the highest safe position immediately above the dry terrain surface.
    _player.velocity = Vector3.ZERO # Prevents any pre-spawn velocity from affecting the first active physics frame.
    await get_tree().physics_frame # Lets the physics server register the final player transform before movement begins.
    _player.set_physics_process(true) # Enables normal player movement only after collision-backed placement is complete.

func _find_shoreline_spawn_horizontal() -> Vector2: # Finds dry low-slope terrain immediately beside an actual clipped water body.
    var best_position: Vector2 = PLAYER_SPAWN_FALLBACK_HORIZONTAL # Starts with the guaranteed dry origin in case no shoreline transition can be resolved.
    var best_score: float = INF # Allows the first valid shoreline candidate to become the current best result.
    for direction_index: int in range(SHORE_SEARCH_DIRECTION_COUNT): # Searches evenly distributed deterministic rays around the world origin.
        var angle: float = TAU * float(direction_index) / float(SHORE_SEARCH_DIRECTION_COUNT) # Converts the direction index into a complete radial distribution.
        var direction: Vector2 = Vector2(cos(angle), sin(angle)) # Builds the normalized horizontal search direction.
        var previous_position: Vector2 = Vector2.ZERO # Begins each ray on the known dry origin platform.
        var previous_has_water: bool = _terrain.has_water_at(previous_position) # Reads exact rendered water occupancy at the start of the ray.
        var radius: float = SHORE_SEARCH_STEP # Starts outside the immediate flat spawn stamp before advancing outward.
        while radius <= SHORE_SEARCH_MAXIMUM_RADIUS: # Continues until finding the first shoreline transition or exhausting the search radius.
            var current_position: Vector2 = direction * radius # Calculates the next deterministic sample along the active ray.
            var current_has_water: bool = _terrain.has_water_at(current_position) # Tests exact clipped-water occupancy rather than comparing height alone.
            if current_has_water != previous_has_water: # Detects the first transition between dry terrain and a real water polygon.
                var dry_position: Vector2 = previous_position # Defaults the inner sample to the dry side of the transition.
                var wet_position: Vector2 = current_position # Defaults the outer sample to the wet side of the transition.
                if previous_has_water: # Handles the uncommon case where a ray exits water back onto dry terrain.
                    dry_position = current_position # Uses the outer dry sample when the transition direction is reversed.
                    wet_position = previous_position # Uses the inner wet sample when the transition direction is reversed.
                var refined_dry_position: Vector2 = _refine_shoreline_dry_position(dry_position, wet_position) # Narrows the transition while retaining the final point on land.
                var inland_direction: Vector2 = (dry_position - wet_position).normalized() # Points away from water and farther onto the resolved land mass.
                var candidate_position: Vector2 = refined_dry_position + inland_direction * SHORE_SPAWN_INLAND_DISTANCE # Moves the player a safe but still shoreline-adjacent distance inland.
                if _terrain.has_water_at(candidate_position): # Defensively handles irregular cell clipping that bends around the radial transition.
                    candidate_position = refined_dry_position # Falls back to the verified dry boundary sample rather than ever choosing water.
                var candidate_score: float = _score_shoreline_spawn(candidate_position) # Measures dryness, bank height, slope, and travel distance.
                if candidate_score < best_score: # Detects the safest and most natural shoreline start found so far.
                    best_score = candidate_score # Stores the improved deterministic score.
                    best_position = candidate_position # Stores the associated dry shoreline position.
                break # Uses only the nearest shoreline transition along each ray to keep startup work bounded.
            previous_position = current_position # Advances the previous sample for the next transition test.
            previous_has_water = current_has_water # Retains the current occupancy state for the next radial step.
            radius += SHORE_SEARCH_STEP # Advances outward by the fixed deterministic search interval.
    return best_position # Returns the best shoreline candidate or the guaranteed dry origin fallback.

func _refine_shoreline_dry_position(dry_position: Vector2, wet_position: Vector2) -> Vector2: # Narrows one dry-water interval while preserving a point that remains on land.
    var refined_dry: Vector2 = dry_position # Stores the currently verified dry side of the interval.
    var refined_wet: Vector2 = wet_position # Stores the currently verified wet side of the interval.
    for _step: int in range(SHORE_SEARCH_REFINEMENT_STEPS): # Repeatedly halves the transition interval to approach the rendered shoreline.
        var midpoint: Vector2 = (refined_dry + refined_wet) * 0.5 # Samples the centre of the current dry-water interval.
        if _terrain.has_water_at(midpoint): # Detects whether the midpoint lies inside the clipped water polygon.
            refined_wet = midpoint # Moves the wet boundary inward while retaining a verified wet point.
        else: # Handles a midpoint that remains on dry terrain.
            refined_dry = midpoint # Moves the dry boundary toward the water while retaining a verified land point.
    return refined_dry # Returns the closest verified dry sample after bounded refinement.

func _score_shoreline_spawn(candidate_position: Vector2) -> float: # Scores one dry shoreline point for low slope and a natural low-bank elevation.
    if _terrain.has_water_at(candidate_position): # Rejects any candidate that resolves inside rendered water.
        return INF # Prevents a wet point from becoming the selected player start.
    var centre_height: float = _terrain.get_height_at(candidate_position) # Reads the exact terrain elevation beneath the candidate.
    var water_level: float = _terrain.get_water_level_at(candidate_position) # Reads the local flat water band adjacent to the shoreline.
    var dry_clearance: float = centre_height - water_level # Measures how far the candidate stands above the local water surface.
    if dry_clearance < SHORE_MINIMUM_DRY_CLEARANCE: # Rejects land too close to the water plane for a reliable visibly dry start.
        return INF # Keeps the final spawn safely above the shoreline clipping tolerance.
    var east_height: float = _terrain.get_height_at(candidate_position + Vector2(SHORE_SLOPE_SAMPLE_DISTANCE, 0.0)) # Samples terrain one mesh interval east.
    var west_height: float = _terrain.get_height_at(candidate_position - Vector2(SHORE_SLOPE_SAMPLE_DISTANCE, 0.0)) # Samples terrain one mesh interval west.
    var south_height: float = _terrain.get_height_at(candidate_position + Vector2(0.0, SHORE_SLOPE_SAMPLE_DISTANCE)) # Samples terrain one mesh interval south.
    var north_height: float = _terrain.get_height_at(candidate_position - Vector2(0.0, SHORE_SLOPE_SAMPLE_DISTANCE)) # Samples terrain one mesh interval north.
    var maximum_variation: float = maxf(absf(east_height - centre_height), absf(west_height - centre_height)) # Measures the steepest east-west local change.
    maximum_variation = maxf(maximum_variation, absf(south_height - centre_height)) # Includes the southern local change.
    maximum_variation = maxf(maximum_variation, absf(north_height - centre_height)) # Includes the northern local change.
    var slope_penalty: float = maximum_variation * 8.0 # Strongly favours broad stable ground for the complete player capsule.
    if maximum_variation > SHORE_MAXIMUM_PREFERRED_VARIATION: # Detects terrain steeper than the preferred shoreline bank.
        slope_penalty += (maximum_variation - SHORE_MAXIMUM_PREFERRED_VARIATION) * 24.0 # Applies an additional penalty without making rough-shore fallback impossible.
    var clearance_penalty: float = absf(dry_clearance - SHORE_PREFERRED_CLEARANCE) * 1.6 # Favours a low bank several metres above the adjacent water.
    var distance_penalty: float = candidate_position.length() * 0.0005 # Slightly prefers nearer equivalent shorelines without overriding safety.
    return slope_penalty + clearance_penalty + distance_penalty # Returns the complete deterministic candidate score.

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
