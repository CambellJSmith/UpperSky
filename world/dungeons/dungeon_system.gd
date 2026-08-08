extends Node3D # Coordinates infinite deterministic overworld door pairs, camera interaction, world suspension, and procedural dungeon transitions.
class_name DungeonSystem # Exposes the complete streamed paired-dungeon runtime as one composition-owned game system.

const INTERACT_ACTION: StringName = &"Interact" # Defines the dedicated keyboard/controller action used to activate targeted dungeon doors.
const INTERACTION_DISTANCE: float = 4.5 # Limits camera door interaction to an intentional close first-person range.
const DUNGEON_REGION_SIZE: float = 2304.0 # Divides the unbounded procedural overworld into large deterministic regions that each own one dungeon pair.
const STREAM_REFRESH_CELL_SIZE: float = 384.0 # Rechecks nearby dungeon regions frequently enough that entrances appear before reaching normal terrain view distance.
const SOURCE_REGION_SCAN_RADIUS: int = 4 # Searches enough owning regions around the player to cover even the longest supported paired-door spans.
const PAIR_LOAD_DISTANCE: float = 2200.0 # Loads a pair when either exterior endpoint approaches the edge of the normal visible overworld neighbourhood.
const PAIR_UNLOAD_DISTANCE: float = 2700.0 # Keeps already loaded pairs slightly longer than the load distance to prevent streaming churn near the boundary.
const REGION_MIDPOINT_MARGIN: float = 0.14 # Keeps each pair midpoint away from its owning region boundary while still disguising the underlying region grid.
const MINIMUM_PAIR_SEPARATION: float = 120.0 # Allows compact local shortcut dungeons while keeping the two exterior endpoints clearly distinct after terrain correction.
const MAXIMUM_PAIR_SEPARATION: float = 8000.0 # Allows rare dungeon pairs to connect overworld locations several kilometres apart.
const ENDPOINT_GROUND_CLEARANCE: float = 0.035 # Prevents procedural door frames from visually z-fighting with sampled terrain.
const EXIT_PLAYER_CLEARANCE: float = 0.08 # Places the player root slightly above sampled terrain after returning from a dungeon.
const EXIT_FORWARD_DISTANCE: float = 2.55 # Places returning players safely outside the portal instead of immediately retriggering the same door.
const EXIT_COLLISION_SETTLE_FRAMES: int = 2 # Holds player physics briefly after long-range exits so terrain can stream exact collision around the destination first.
const DRY_SEARCH_RING_COUNT: int = 7 # Bounds deterministic nearby-ground searches when an intended door coordinate lands on water or rough terrain.
const DRY_SEARCH_DIRECTIONS: int = 12 # Samples enough directions per ring to find nearby suitable terrain without unbounded placement work.
const DRY_SEARCH_RING_STEP: float = 7.5 # Expands each placement search ring by a moderate physical distance around its intended endpoint.
const SLOPE_SAMPLE_DISTANCE: float = 2.5 # Measures local terrain variation across roughly the footprint of one generated doorway.
const MAXIMUM_DOOR_HEIGHT_VARIATION: float = 1.65 # Rejects steep local ground that would leave the freestanding procedural frame visibly floating or buried.
const DUNGEON_WORLD_ORIGIN: Vector3 = Vector3(0.0, 20_000.0, 0.0) # Isolates the active interior far above suspended overworld collision while keeping local dungeon coordinates near zero.
const INVALID_STREAM_CELL: Vector2i = Vector2i(2_147_483_647, 2_147_483_647) # Forces the first completed overworld spawn to perform an immediate dungeon-stream refresh.

@onready var _world: Node3D = $"../World" # Stores the complete overworld environment and terrain subtree that is suspended during dungeon traversal.
@onready var _terrain: InfiniteTerrain = $"../World/Terrain" # Stores the authoritative procedural terrain service used for absolute door placement and overworld return.
@onready var _dynamic_entities: Node3D = $"../DynamicEntities" # Stores the floating-origin root that must own exterior doors so rebasing keeps them aligned with terrain.
@onready var _player: FirstPersonPlayer = $"../DynamicEntities/Player" # Stores the existing first-person player that travels between overworld and generated interiors.
@onready var _training_dummy: Node3D = $"../DynamicEntities/TrainingDummy" # Stores the overworld-only combat target hidden while a dungeon world is active.
@onready var _world_decorations: Node3D = $"../WorldDecorations" # Stores streamed overworld decorations suspended while the player is in an interior world space.
@onready var _ground_flora: Node3D = $"../GroundFlora" # Stores streamed ground flora suspended alongside the overworld terrain.
@onready var _dense_ground_cover: Node3D = $"../DenseGroundCover" # Stores the dense grass streamer that should not follow dungeon-space player coordinates.
@onready var _underwater_view: CanvasLayer = $"../UnderwaterView" # Stores the overworld water view effect disabled while terrain sampling is intentionally detached.

var _camera: Camera3D # Stores the player's active first-person camera after the composed player scene is ready.
var _entrance_root: Node3D # Owns all currently streamed exterior doors as one top-level floating-origin entity.
var _streamed_pairs: Dictionary[int, DungeonPairDefinition] = {} # Stores only deterministic pair definitions currently relevant to the player's overworld neighbourhood.
var _streamed_pair_roots: Dictionary[int, Node3D] = {} # Stores the generated exterior-door node root corresponding to each currently streamed pair identity.
var _last_stream_cell: Vector2i = INVALID_STREAM_CELL # Tracks the coarse absolute player cell used to avoid rebuilding the dungeon stream every frame.
var _exit_collision_settle_frames_remaining: int = 0 # Counts frames while player physics is paused so a distant dungeon exit can acquire local terrain collision safely.
var _active_pair: DungeonPairDefinition # Stores the pair whose deterministic interior is currently active even when its endpoints are kilometres apart.
var _active_dungeon: ProceduralDungeonWorld # Stores the disposable generated interior world while the player is inside it.

func _ready() -> void: # Creates the floating-origin entrance owner and waits for terrain-backed player spawning before streaming nearby pairs.
    _camera = _player.get_view_camera() if _player != null else null # Resolves the existing first-person camera used by interaction and environment overrides.
    _entrance_root = Node3D.new() # Creates a runtime-only owner for every currently streamed procedural exterior doorway.
    _entrance_root.name = "DungeonEntrances" # Gives the generated door collection a stable remote-scene-tree identity.
    if _dynamic_entities != null: # Verifies the floating-origin root exists before parenting generated world entities.
        _dynamic_entities.add_child(_entrance_root) # Makes all exterior doors inherit the exact same world-rebase shifts as the player and training dummy.

func _process(_delta: float) -> void: # Streams deterministic dungeon pairs as the player explores the unbounded overworld.
    if _exit_collision_settle_frames_remaining > 0: # Detects a recent dungeon exit that may have moved the player beyond the previously loaded collision neighbourhood.
        _exit_collision_settle_frames_remaining -= 1 # Gives the resumed terrain streamer another complete frame to build near-player chunks in its normal near-to-far order.
        if _exit_collision_settle_frames_remaining <= 0 and _player != null: # Detects completion of the short collision-streaming grace period.
            _player.set_physics_process(true) # Restores gravity and movement only after destination terrain has had time to create active collision.
    if _active_dungeon != null: # Detects that the player currently occupies an isolated dungeon world space.
        return # Leaves the overworld pair stream frozen until the player returns through an interior exit.
    if _terrain == null or _player == null or _entrance_root == null: # Detects incomplete scene composition that cannot support deterministic entrance placement.
        return # Waits for valid dependencies rather than guessing coordinates.
    if _terrain.get_loaded_chunk_count() <= 0: # Detects terrain that has not yet generated the initial collision neighbourhood.
        return # Waits until authoritative height and water context is actively represented around the player.
    if not _player.is_physics_processing(): # Detects the initial spawn phase or the brief post-dungeon collision-settling phase.
        return # Waits until ordinary grounded player physics is safe to resume before updating entrance streaming.
    var player_world_position: Vector3 = _terrain.local_to_world_position(_player.global_position) # Converts the near-origin player transform into stable absolute procedural-world coordinates.
    var player_horizontal: Vector2 = Vector2(player_world_position.x, player_world_position.z) # Extracts the horizontal coordinate used by deterministic region streaming.
    var stream_cell: Vector2i = _get_stream_cell(player_horizontal) # Calculates the smaller coarse cell that controls entrance-stream refresh frequency.
    if stream_cell == _last_stream_cell: # Detects ordinary movement that has not crossed far enough to require pair-stream reconsideration.
        return # Reuses the currently streamed entrance set without repeated procedural placement work.
    _last_stream_cell = stream_cell # Stores the new stream cell before rebuilding the bounded nearby pair set.
    _refresh_overworld_pairs(player_horizontal) # Loads newly relevant deterministic pairs and unloads pairs that moved safely beyond the retention distance.

func _unhandled_input(event: InputEvent) -> void: # Resolves explicit first-person dungeon-door interaction without coupling doors directly to player input.
    if event is InputEventKey and (event as InputEventKey).echo: # Rejects repeated keyboard echo events while the interact key remains held.
        return # Ensures one press can trigger at most one world-space transition.
    if not event.is_action_pressed(INTERACT_ACTION): # Ignores unrelated gameplay input before performing any physics query work.
        return # Leaves the event available to other systems.
    if _camera == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: # Rejects interaction while first-person gameplay input is not actively captured.
        return # Prevents dungeon transitions while inventory or other mouse-visible interfaces are open.
    if _try_interact_with_door(): # Attempts one dedicated-layer camera raycast and performs the matching transition when a door is targeted.
        get_viewport().set_input_as_handled() # Prevents the accepted interaction press from reaching unrelated gameplay systems.

func _try_interact_with_door() -> bool: # Casts a short ray from the active camera and routes a targeted procedural door to entry or exit behavior.
    var ray_origin: Vector3 = _camera.global_position # Starts interaction exactly at the player's current first-person camera position.
    var ray_direction: Vector3 = -_camera.global_transform.basis.z.normalized() # Aims interaction through the current centre-screen view direction.
    var ray_end: Vector3 = ray_origin + ray_direction * INTERACTION_DISTANCE # Limits door targeting to the configured close interaction range.
    var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end) # Builds a strongly typed direct-space query for the current physics world.
    query.collision_mask = DungeonDoor.INTERACTION_COLLISION_LAYER # Restricts results to generated dungeon door areas so terrain and enemies cannot block the interaction ray.
    query.collide_with_areas = true # Allows the non-solid DungeonDoor Area3D volumes to be detected.
    query.collide_with_bodies = false # Excludes ordinary solid bodies because they cannot represent dungeon transitions on the dedicated layer.
    var result: Dictionary = _camera.get_world_3d().direct_space_state.intersect_ray(query) # Executes the camera-centred interaction query immediately.
    if result.is_empty(): # Detects that no generated door is currently targeted.
        return false # Reports an unused interaction press without changing world state.
    var collider: Object = result.get("collider") # Retrieves the Area3D object returned by the physics query.
    if not (collider is DungeonDoor): # Defensively rejects unexpected objects that may later share the interaction layer.
        return false # Leaves world state unchanged for non-door interaction targets.
    var door: DungeonDoor = collider as DungeonDoor # Converts the validated target to the strongly typed procedural doorway contract.
    if door.is_exterior(): # Detects an overworld endpoint that should enter its shared deterministic interior.
        return _enter_dungeon(door.get_pair_id(), door.get_endpoint()) # Generates or reconstructs the pair's interior and places the player at the matching inside door.
    return _exit_dungeon(door.get_pair_id(), door.get_endpoint()) # Returns through the matching side of the currently active pair to its exact exterior endpoint.

func _refresh_overworld_pairs(player_horizontal: Vector2) -> void: # Rebuilds the bounded set of pair regions whose endpoints are currently relevant to the exploring player.
    var desired_pair_ids: Dictionary[int, bool] = {} # Records every pair that should remain streamed after this refresh without mutating dictionaries during iteration.
    var centre_region: Vector2i = _get_region_coordinate(player_horizontal) # Finds the infinite owning region currently containing the player.
    for offset_y: int in range(-SOURCE_REGION_SCAN_RADIUS, SOURCE_REGION_SCAN_RADIUS + 1): # Scans enough source-region rows to include endpoints from long-distance dungeon pairs.
        for offset_x: int in range(-SOURCE_REGION_SCAN_RADIUS, SOURCE_REGION_SCAN_RADIUS + 1): # Scans enough source-region columns around the current absolute player region.
            var region_coordinate: Vector2i = centre_region + Vector2i(offset_x, offset_y) # Converts the bounded local offset into one stable infinite overworld region coordinate.
            var pair_id: int = _get_pair_id(region_coordinate) # Derives the unique practical pair identity directly from signed region coordinates.
            if _streamed_pairs.has(pair_id): # Detects a pair whose expensive terrain-ground resolution has already been performed.
                var existing_pair: DungeonPairDefinition = _streamed_pairs[pair_id] # Retrieves the existing deterministic metadata without regenerating it.
                if _is_pair_within_distance(existing_pair, player_horizontal, PAIR_UNLOAD_DISTANCE): # Applies the larger retention distance to avoid load/unload oscillation.
                    desired_pair_ids[pair_id] = true # Keeps the existing pair and both generated door nodes alive for this stream cycle.
                continue # Avoids reconstructing an already streamed pair from its seed.
            var new_pair: DungeonPairDefinition = _build_pair_if_nearby(region_coordinate, player_horizontal) # Generates metadata only when one intended endpoint is close enough to matter.
            if new_pair == null: # Detects a deterministic region whose two endpoints are currently outside the load neighbourhood.
                continue # Leaves that infinite region represented only by its implicit seed until the player approaches either endpoint later.
            desired_pair_ids[pair_id] = true # Marks the newly relevant pair before constructing its physical door nodes.
            _stream_pair(new_pair) # Creates both exterior endpoints and registers their deterministic metadata in the bounded active stream.
    var pairs_to_remove: Array[int] = [] # Collects stale pair identities so dictionaries are never erased while their keys are being iterated.
    for pair_id: int in _streamed_pairs.keys(): # Examines every currently retained deterministic pair after evaluating the new neighbourhood.
        if not desired_pair_ids.has(pair_id): # Detects a pair whose endpoints are now safely outside the unload distance or source scan.
            pairs_to_remove.append(pair_id) # Defers node release and dictionary mutation until key iteration has completed.
    for pair_id: int in pairs_to_remove: # Removes every stale pair after the immutable iteration phase.
        _unstream_pair(pair_id) # Releases its generated doors and metadata while preserving the ability to reconstruct them identically later.

func _build_pair_if_nearby(region_coordinate: Vector2i, player_horizontal: Vector2) -> DungeonPairDefinition: # Reconstructs one region-owned pair only when an endpoint is near enough to enter the streamed overworld set.
    var pair_id: int = _get_pair_id(region_coordinate) # Calculates the deterministic identity shared by placement, labels, interior generation, and return routing.
    var pair_seed: int = _get_pair_random_seed(pair_id) # Derives an isolated repeatable random stream from the world seed and unique pair identity.
    var rng: RandomNumberGenerator = RandomNumberGenerator.new() # Creates local pair-placement randomness without consuming any mutable global generator state.
    rng.seed = pair_seed # Resets all region placement decisions to the same sequence on every visit and playthrough.
    var region_origin: Vector2 = Vector2(float(region_coordinate.x) * DUNGEON_REGION_SIZE, float(region_coordinate.y) * DUNGEON_REGION_SIZE) # Calculates the stable absolute southwest corner of the owning dungeon region.
    var midpoint_margin: float = DUNGEON_REGION_SIZE * REGION_MIDPOINT_MARGIN # Converts the normalized margin into a physical region-edge inset.
    var midpoint: Vector2 = region_origin + Vector2(rng.randf_range(midpoint_margin, DUNGEON_REGION_SIZE - midpoint_margin), rng.randf_range(midpoint_margin, DUNGEON_REGION_SIZE - midpoint_margin)) # Places the pair centre at a seeded irregular position inside its region so entrances do not reveal a visible world grid.
    var separation: float = _sample_pair_separation(rng) # Chooses a broad logarithmically distributed distance ranging from local shortcuts to multi-kilometre connections.
    var separation_angle: float = rng.randf_range(0.0, TAU) # Chooses an unrestricted deterministic axis for the two exterior endpoints around the pair midpoint.
    var span_direction: Vector2 = Vector2(cos(separation_angle), sin(separation_angle)) # Converts the seeded angle into the normalized horizontal endpoint axis.
    var half_span: float = separation * 0.5 # Splits the complete requested door separation evenly around the deterministic pair midpoint.
    var intended_a: Vector2 = midpoint - span_direction * half_span # Calculates the first uncorrected exterior endpoint in stable procedural-world coordinates.
    var intended_b: Vector2 = midpoint + span_direction * half_span # Calculates the paired second endpoint on the opposite side of the shared midpoint.
    var ground_search_allowance: float = float(DRY_SEARCH_RING_COUNT) * DRY_SEARCH_RING_STEP # Measures the maximum distance terrain correction may move either intended endpoint.
    var prefetch_distance: float = PAIR_LOAD_DISTANCE + ground_search_allowance # Loads pairs slightly before corrected ground placement could cross the normal stream boundary.
    if intended_a.distance_to(player_horizontal) > prefetch_distance and intended_b.distance_to(player_horizontal) > prefetch_distance: # Detects a region whose raw pair endpoints are both safely irrelevant to the current player neighbourhood.
        return null # Avoids expensive water, height, and local-slope searches for the overwhelming majority of distant infinite regions.
    var endpoint_a: Vector2 = _find_suitable_door_ground(intended_a) # Moves endpoint A only as far as necessary to nearby dry low-slope terrain.
    var endpoint_b: Vector2 = _find_suitable_door_ground(intended_b) # Independently resolves endpoint B onto deterministic suitable terrain.
    var pair: DungeonPairDefinition = DungeonPairDefinition.new() # Allocates strongly typed metadata for this streamed exterior pair and shared interior.
    pair.pair_id = pair_id # Assigns the stable region-derived identity used by generated doors and transition lookup.
    pair.region_coordinate = region_coordinate # Retains the owning infinite-region coordinate for readable labels and diagnostics.
    pair.dungeon_seed = pair_seed ^ 7_919_357 # Derives the interior generation stream independently from exact overworld placement choices.
    pair.endpoint_a_world_position = Vector3(endpoint_a.x, _terrain.get_height_at(endpoint_a) + ENDPOINT_GROUND_CLEARANCE, endpoint_a.y) # Grounds endpoint A on the authoritative procedural terrain height.
    pair.endpoint_b_world_position = Vector3(endpoint_b.x, _terrain.get_height_at(endpoint_b) + ENDPOINT_GROUND_CLEARANCE, endpoint_b.y) # Grounds endpoint B on its independently resolved terrain point.
    pair.endpoint_a_yaw = _get_yaw_facing_target(endpoint_a, endpoint_b) # Faces exterior A broadly toward the paired destination to give the two freestanding portals a coherent relationship.
    pair.endpoint_b_yaw = _get_yaw_facing_target(endpoint_b, endpoint_a) # Faces exterior B back toward endpoint A while preserving independent terrain placement.
    return pair # Returns the complete deterministic pair ready for bounded scene-tree streaming and on-demand interior generation.

func _sample_pair_separation(rng: RandomNumberGenerator) -> float: # Samples door distance across several orders of magnitude without clustering nearly everything near the maximum.
    var minimum_log_distance: float = log(MINIMUM_PAIR_SEPARATION) # Converts the smallest supported pair span into logarithmic sampling space.
    var maximum_log_distance: float = log(MAXIMUM_PAIR_SEPARATION) # Converts the multi-kilometre maximum into the same logarithmic sampling space.
    var logarithmic_position: float = rng.randf() # Chooses an even deterministic position across distance magnitudes rather than raw metres.
    return exp(lerpf(minimum_log_distance, maximum_log_distance, logarithmic_position)) # Converts the sampled logarithmic position back into a physical overworld separation distance.

func _stream_pair(pair: DungeonPairDefinition) -> void: # Creates the bounded runtime nodes representing one deterministic infinite-world dungeon pair.
    if pair == null or _streamed_pairs.has(pair.pair_id): # Rejects malformed metadata and duplicate stream requests for an already active pair.
        return # Leaves the existing deterministic representation untouched.
    var pair_root: Node3D = Node3D.new() # Creates one lightweight owner so both paired exterior doors can be released together.
    pair_root.name = "DungeonPair_%d_%d" % [pair.region_coordinate.x, pair.region_coordinate.y] # Gives the generated pair a stable coordinate-derived remote-tree identity.
    _entrance_root.add_child(pair_root) # Parents the pair under the existing floating-origin owner before assigning absolute local-world positions.
    _create_exterior_door(pair_root, pair, DungeonPairDefinition.Endpoint.A) # Creates the first procedural overworld entrance for the streamed pair.
    _create_exterior_door(pair_root, pair, DungeonPairDefinition.Endpoint.B) # Creates its potentially distant partner linked to the exact same deterministic interior.
    _streamed_pairs[pair.pair_id] = pair # Registers metadata only after both endpoint nodes have been constructed successfully.
    _streamed_pair_roots[pair.pair_id] = pair_root # Registers the shared scene root used for later bounded unstreaming.

func _unstream_pair(pair_id: int) -> void: # Releases one distant streamed pair while retaining deterministic reconstruction through its infinite region identity.
    if _streamed_pair_roots.has(pair_id): # Detects a generated scene owner corresponding to the stale pair metadata.
        var pair_root: Node3D = _streamed_pair_roots[pair_id] # Retrieves the complete two-door owner before removing dictionary references.
        pair_root.queue_free() # Releases both procedural exterior doors and all runtime-only visual/collision resources at the end of the frame.
        _streamed_pair_roots.erase(pair_id) # Removes the stale node reference after scheduling release.
    _streamed_pairs.erase(pair_id) # Removes the pair metadata so returning later reconstructs it cleanly from its owning region and seed.

func _create_exterior_door(pair_root: Node3D, pair: DungeonPairDefinition, endpoint: DungeonPairDefinition.Endpoint) -> void: # Instantiates one runtime-only exterior frame from deterministic pair metadata.
    var door: DungeonDoor = DungeonDoor.new() # Allocates the complete procedural doorway implementation without loading a PackedScene asset.
    door.name = "DoorB" if endpoint == DungeonPairDefinition.Endpoint.B else "DoorA" # Gives each endpoint a compact stable identity beneath its coordinate-named pair root.
    pair_root.add_child(door) # Parents the new door before assigning a global position that correctly compensates for any prior floating-origin shift on its ancestors.
    door.configure(pair.pair_id, endpoint, true, pair.get_yaw(endpoint), pair.get_display_name(endpoint)) # Assigns immutable pair routing data and builds all procedural visual assets.
    door.global_position = _terrain.world_to_local_position(pair.get_world_position(endpoint)) # Places the endpoint at the exact current near-origin scene coordinate even when the entrance root has already been rebased.

func _is_pair_within_distance(pair: DungeonPairDefinition, player_horizontal: Vector2, distance: float) -> bool: # Tests whether either endpoint of a streamed pair remains close enough to retain its bounded runtime representation.
    var endpoint_a: Vector3 = pair.endpoint_a_world_position # Reads endpoint A's stable absolute procedural-overworld transform.
    var endpoint_b: Vector3 = pair.endpoint_b_world_position # Reads endpoint B's independently stable absolute transform.
    var distance_a_squared: float = Vector2(endpoint_a.x, endpoint_a.z).distance_squared_to(player_horizontal) # Measures squared player distance to A without an unnecessary square root.
    var distance_b_squared: float = Vector2(endpoint_b.x, endpoint_b.z).distance_squared_to(player_horizontal) # Measures squared player distance to B using the same efficient comparison space.
    var maximum_distance_squared: float = distance * distance # Converts the configured stream radius once into squared-distance space.
    return distance_a_squared <= maximum_distance_squared or distance_b_squared <= maximum_distance_squared # Retains the pair whenever either side remains relevant to current exploration.

func _get_stream_cell(world_position: Vector2) -> Vector2i: # Converts absolute player position into the smaller grid used only to throttle stream refresh work.
    return Vector2i(floori(world_position.x / STREAM_REFRESH_CELL_SIZE), floori(world_position.y / STREAM_REFRESH_CELL_SIZE)) # Uses floor division so refresh cells remain stable and symmetric across negative world coordinates.

func _get_region_coordinate(world_position: Vector2) -> Vector2i: # Converts absolute overworld position into the large infinite grid that deterministically owns dungeon pairs.
    return Vector2i(floori(world_position.x / DUNGEON_REGION_SIZE), floori(world_position.y / DUNGEON_REGION_SIZE)) # Uses mathematical floor so negative regions tile the world continuously without coordinate aliasing.

func _get_pair_id(region_coordinate: Vector2i) -> int: # Encodes two signed region coordinates into one practical unique non-negative integer identity.
    var encoded_x: int = _encode_signed_coordinate(region_coordinate.x) # Converts signed x into the non-negative integer sequence required by Cantor pairing.
    var encoded_y: int = _encode_signed_coordinate(region_coordinate.y) # Converts signed y independently so opposite regions cannot share an identity.
    var diagonal: int = encoded_x + encoded_y # Calculates the Cantor diagonal containing this exact non-negative coordinate pair.
    return ((diagonal * (diagonal + 1)) >> 1) + encoded_y # Uses an integer half-product to produce a unique identity across practical world-travel distances.

func _encode_signed_coordinate(value: int) -> int: # Maps every signed integer onto a distinct non-negative integer without storing extra region state.
    if value >= 0: # Detects zero and positive region coordinates.
        return value * 2 # Maps non-negative coordinates onto the even-number sequence.
    return (-value * 2) - 1 # Maps negative coordinates onto the odd-number sequence without colliding with positive values.

func _get_pair_random_seed(pair_id: int) -> int: # Mixes unique pair identity with the authoritative world seed to drive repeatable placement and interior generation.
    var seed_value: int = pair_id ^ (TerrainHeightSampler.WORLD_SEED * 1_000_003) # Combines world identity and region identity before bit diffusion.
    seed_value = seed_value ^ (seed_value << 13) # Mixes lower and higher bits so nearby region IDs do not produce visibly related random streams.
    seed_value = seed_value ^ (seed_value >> 7) # Folds the expanded state back across bit ranges for stronger spatial decorrelation.
    seed_value = seed_value ^ (seed_value << 17) # Applies a final deterministic diffusion step before assigning the RNG seed.
    return seed_value # Returns the stable signed integer accepted directly by Godot's local RandomNumberGenerator.

func _find_suitable_door_ground(intended_position: Vector2) -> Vector2: # Searches deterministically around an intended coordinate for dry locally level terrain suitable for a freestanding portal.
    for ring: int in range(DRY_SEARCH_RING_COUNT + 1): # Expands from the exact intended position through a bounded series of circular search rings.
        if ring == 0: # Handles the preferred coordinate before introducing any placement displacement.
            if _is_suitable_door_ground(intended_position): # Tests whether the intended point is already dry and locally level.
                return intended_position # Preserves the original deterministic placement when no correction is needed.
            continue # Advances to nearby ring samples only when the preferred point is unsuitable.
        var radius: float = float(ring) * DRY_SEARCH_RING_STEP # Calculates the physical displacement represented by the current bounded search ring.
        for direction_index: int in range(DRY_SEARCH_DIRECTIONS): # Samples evenly spaced deterministic directions around this ring.
            var angle: float = TAU * float(direction_index) / float(DRY_SEARCH_DIRECTIONS) # Converts the sample index into a complete circular angular distribution.
            var candidate: Vector2 = intended_position + Vector2(cos(angle), sin(angle)) * radius # Builds the absolute procedural-world point for the current nearby sample.
            if _is_suitable_door_ground(candidate): # Tests rendered-water occupancy and local terrain variation at the candidate.
                return candidate # Uses the first deterministic valid point in ring and direction order.
    return intended_position # Falls back to the original coordinate if no bounded nearby sample satisfies the preferred placement constraints.

func _is_suitable_door_ground(position: Vector2) -> bool: # Reports whether one absolute overworld point is dry and sufficiently level for a generated entrance frame.
    if _terrain.has_water_at(position): # Rejects coordinates occupied by the same clipped water surface rendered by the terrain system.
        return false # Prevents dungeon doors from spawning in lakes, rivers, or sea cells.
    var centre_height: float = _terrain.get_height_at(position) # Samples authoritative ground elevation at the intended doorway centre.
    var east_height: float = _terrain.get_height_at(position + Vector2(SLOPE_SAMPLE_DISTANCE, 0.0)) # Samples ground across the eastern side of the frame footprint.
    var west_height: float = _terrain.get_height_at(position - Vector2(SLOPE_SAMPLE_DISTANCE, 0.0)) # Samples ground across the western side of the frame footprint.
    var south_height: float = _terrain.get_height_at(position + Vector2(0.0, SLOPE_SAMPLE_DISTANCE)) # Samples ground across the southern side of the frame footprint.
    var north_height: float = _terrain.get_height_at(position - Vector2(0.0, SLOPE_SAMPLE_DISTANCE)) # Samples ground across the northern side of the frame footprint.
    var maximum_variation: float = maxf(absf(east_height - centre_height), absf(west_height - centre_height)) # Measures the steepest east-west elevation difference under the doorway.
    maximum_variation = maxf(maximum_variation, absf(south_height - centre_height)) # Includes the southern frame footprint in the slope measure.
    maximum_variation = maxf(maximum_variation, absf(north_height - centre_height)) # Includes the northern frame footprint before deciding placement suitability.
    return maximum_variation <= MAXIMUM_DOOR_HEIGHT_VARIATION # Accepts only terrain flat enough for the procedural freestanding frame to read naturally.

func _get_yaw_facing_target(origin: Vector2, target: Vector2) -> float: # Converts one horizontal look direction into a yaw matching Godot's default negative-z forward axis.
    var direction: Vector2 = (target - origin).normalized() # Points from the generated door toward the desired paired overworld target.
    if direction.is_zero_approx(): # Handles an impossible coincident target without producing an undefined atan2 orientation.
        direction = Vector2(0.0, -1.0) # Falls back to Godot's conventional default forward direction in horizontal space.
    return atan2(-direction.x, -direction.y) # Converts desired x/z forward direction into the player and doorway root yaw convention.

func _enter_dungeon(pair_id: int, endpoint: DungeonPairDefinition.Endpoint) -> bool: # Suspends the overworld, deterministically generates the selected pair's interior, and places the player inside the matching door.
    if _active_dungeon != null: # Rejects an entry request while another interior world is already active.
        return false # Prevents nested dungeon generation and ambiguous return routing.
    var pair: DungeonPairDefinition = _find_pair(pair_id) # Resolves the targeted streamed exterior pair from deterministic metadata.
    if pair == null: # Detects stale or malformed door metadata not represented by the current bounded stream set.
        return false # Leaves the overworld untouched when no matching deterministic interior can be resolved.
    _active_pair = pair # Stores the exact pair independently so return routing remains valid even for multi-kilometre endpoint spans.
    _active_dungeon = ProceduralDungeonWorld.new() # Creates a disposable runtime world that will be reconstructed from seed on every later visit.
    _active_dungeon.name = "ActiveDungeon_%d_%d" % [pair.region_coordinate.x, pair.region_coordinate.y] # Gives the generated interior a stable region-coordinate diagnostic name during this visit.
    _active_dungeon.position = DUNGEON_WORLD_ORIGIN # Places the isolated interior far above suspended terrain collision while keeping its own local geometry near zero.
    _active_dungeon.build(pair.pair_id, pair.dungeon_seed, pair.region_coordinate) # Reconstructs topology, meshes, materials, collision, doors, and lighting from the pair's stable region-derived seed.
    add_child(_active_dungeon) # Activates the generated interior in the same physics world immediately before player relocation.
    _set_overworld_active(false) # Stops overworld streaming and hides overworld-only presentation while preserving it in memory for return travel.
    _player.initialize_environment(null) # Detaches terrain-driven swimming queries while the player occupies the isolated dungeon world space.
    _player.set_fly_mode_enabled(false) # Restores ordinary grounded collision behavior before placing the player inside generated architecture.
    _player.velocity = Vector3.ZERO # Prevents overworld movement momentum from carrying through the world-space transition.
    _camera.environment = _active_dungeon.get_environment() # Overrides the still-instanced overworld WorldEnvironment directly at camera priority for the active interior.
    _player.global_position = _active_dungeon.global_position + _active_dungeon.get_spawn_position(endpoint) # Places the player just inside the exact interior door corresponding to the exterior side used.
    _player.rotation.y = _active_dungeon.get_spawn_yaw(endpoint) # Faces the player away from the arrival portal and into the generated dungeon route.
    return true # Reports that the complete deterministic entry transition succeeded.

func _exit_dungeon(pair_id: int, endpoint: DungeonPairDefinition.Endpoint) -> bool: # Frees the active interior and returns the player to the exact exterior side represented by the chosen inside door.
    if _active_dungeon == null or _active_pair == null: # Rejects an exit request when no deterministic interior transition is active.
        return false # Leaves world state unchanged for stale or malformed interaction calls.
    if pair_id != _active_pair.pair_id: # Detects an interior door that does not belong to the currently active pair.
        return false # Prevents accidental cross-pair teleportation from malformed generated metadata.
    var return_world_position: Vector3 = _active_pair.get_world_position(endpoint) # Reads the absolute procedural-overworld coordinate belonging to the selected inside exit.
    var return_local_position: Vector3 = _terrain.world_to_local_position(return_world_position) # Converts the stable exterior coordinate into current floating-origin scene space.
    var exit_yaw: float = _active_pair.get_yaw(endpoint) # Reads the deterministic exterior-facing orientation authored for this exact paired side.
    var exit_forward: Vector3 = Vector3(-sin(exit_yaw), 0.0, -cos(exit_yaw)).normalized() # Reconstructs the doorway's world-space forward vector from its stored yaw.
    _player.set_physics_process(false) # Prevents gravity from advancing before a distant destination's near-player terrain collision has streamed back into the physics world.
    _camera.environment = null # Removes the dungeon-specific override so the overworld WorldEnvironment becomes authoritative again.
    _set_overworld_active(true) # Restores terrain streaming, vegetation, decorations, underwater effects, training target, and exterior doors before player placement.
    _player.initialize_environment(_terrain) # Reconnects swimming and water-state queries to the authoritative procedural overworld terrain.
    _player.velocity = Vector3.ZERO # Clears any interior movement before restoring overworld physics position.
    _player.global_position = return_local_position + exit_forward * EXIT_FORWARD_DISTANCE + Vector3(0.0, EXIT_PLAYER_CLEARANCE, 0.0) # Places the player safely outside the chosen exterior portal at the matching paired endpoint even when it is kilometres from the entry side.
    _player.rotation.y = exit_yaw # Faces the player away from the returned-through doorway to reduce immediate re-entry confusion.
    _exit_collision_settle_frames_remaining = EXIT_COLLISION_SETTLE_FRAMES # Gives resumed terrain streaming a short bounded window to generate exact collision beneath a long-range exit destination.
    _active_dungeon.queue_free() # Releases all generated layout nodes, meshes, materials, collision, doors, fixtures, and lights after the transition.
    _active_dungeon = null # Clears active interior ownership immediately so future exterior interactions can regenerate the dungeon from seed.
    _active_pair = null # Clears the temporary pair reference while streamed or later reconstructed region metadata remains deterministic.
    _last_stream_cell = INVALID_STREAM_CELL # Forces the first safe overworld frame to rebuild the entrance stream around the potentially distant exit endpoint immediately.
    return true # Reports that paired return travel completed successfully.

func _set_overworld_active(enabled: bool) -> void: # Enables or suspends expensive overworld-only systems while retaining their deterministic state in memory.
    var process_mode_value: Node.ProcessMode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED # Selects ordinary inherited processing or complete subtree suspension from the requested world mode.
    if _world != null: # Verifies the composed overworld root before changing rendering and processing state.
        _world.visible = enabled # Hides or restores terrain, sun, moon, and world-environment-owned visible children together.
        _world.process_mode = process_mode_value # Stops or resumes terrain streaming and the day/night system as one subtree.
    if _world_decorations != null: # Verifies the independent decoration streamer before toggling overworld activity.
        _world_decorations.visible = enabled # Hides or restores generated trees, rocks, and other streamed decoration visuals.
        _world_decorations.process_mode = process_mode_value # Stops or resumes decoration streaming work while the player is not in overworld coordinates.
    if _ground_flora != null: # Verifies the independent flora streamer before changing mode.
        _ground_flora.visible = enabled # Hides or restores procedurally streamed shrubs, flowers, reeds, and ferns.
        _ground_flora.process_mode = process_mode_value # Stops or resumes flora placement work with the overworld.
    if _dense_ground_cover != null: # Verifies the dense grass streamer before changing world mode.
        _dense_ground_cover.visible = enabled # Hides or restores the procedural grass carpet.
        _dense_ground_cover.process_mode = process_mode_value # Prevents grass streaming from interpreting isolated dungeon coordinates as overworld travel.
    if _training_dummy != null: # Verifies the overworld training target before toggling its presentation and behavior.
        _training_dummy.visible = enabled # Hides the straw dummy while the player occupies a separate dungeon world space.
        _training_dummy.process_mode = process_mode_value # Suspends dummy health reset and presentation polling while it is irrelevant.
    if _entrance_root != null: # Verifies the floating-origin exterior entrance collection before toggling it.
        _entrance_root.visible = enabled # Hides all streamed overworld dungeon frames while their matching interior doors are active.
        _entrance_root.process_mode = process_mode_value # Suspends their otherwise minimal Area3D processing inheritance during dungeon traversal.
    if _underwater_view != null: # Verifies the overworld-only water presentation effect before changing world mode.
        _underwater_view.visible = enabled # Removes the terrain-dependent underwater overlay from generated interior rendering.
        _underwater_view.process_mode = process_mode_value # Stops or resumes its camera-water sampling work with the overworld.

func _find_pair(pair_id: int) -> DungeonPairDefinition: # Resolves stable pair metadata from a currently streamed generated doorway identity.
    if not _streamed_pairs.has(pair_id): # Detects an interaction request for metadata no longer represented in the bounded overworld stream.
        return null # Rejects stale door references instead of reconstructing from an unknown region coordinate.
    return _streamed_pairs[pair_id] # Returns the strongly typed deterministic pair metadata associated with the targeted exterior door.
