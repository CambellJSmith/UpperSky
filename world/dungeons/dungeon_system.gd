extends Node3D # Coordinates deterministic overworld door pairs, camera interaction, world suspension, and procedural dungeon transitions.
class_name DungeonSystem # Exposes the complete paired-dungeon runtime as one composition-owned game system.

const INTERACT_ACTION: StringName = &"Interact" # Defines the dedicated keyboard/controller action used to activate targeted dungeon doors.
const INTERACTION_DISTANCE: float = 4.5 # Limits camera door interaction to an intentional close first-person range.
const DUNGEON_PAIR_COUNT: int = 3 # Creates several deterministic paired dungeons around the initial overworld region for the first complete implementation.
const FIRST_PAIR_RADIUS: float = 42.0 # Places the nearest dungeon pair within practical discovery distance of the deterministic player spawn.
const PAIR_RADIUS_STEP: float = 34.0 # Spreads later pair midpoints progressively farther through the surrounding overworld.
const MINIMUM_HALF_PAIR_SPAN: float = 20.0 # Keeps the two exterior doors of one dungeon meaningfully separated in overworld space.
const MAXIMUM_HALF_PAIR_SPAN: float = 30.0 # Keeps each pair close enough that both endpoints remain inside the initial terrain collision neighbourhood.
const ENDPOINT_GROUND_CLEARANCE: float = 0.035 # Prevents procedural door frames from visually z-fighting with sampled terrain.
const EXIT_PLAYER_CLEARANCE: float = 0.08 # Places the player root slightly above sampled terrain after returning from a dungeon.
const EXIT_FORWARD_DISTANCE: float = 2.55 # Places returning players safely outside the portal instead of immediately retriggering the same door.
const DRY_SEARCH_RING_COUNT: int = 7 # Bounds deterministic nearby-ground searches when an intended door coordinate lands on water or rough terrain.
const DRY_SEARCH_DIRECTIONS: int = 12 # Samples enough directions per ring to find nearby suitable terrain without unbounded placement work.
const DRY_SEARCH_RING_STEP: float = 7.5 # Expands each placement search ring by a moderate physical distance around its intended endpoint.
const SLOPE_SAMPLE_DISTANCE: float = 2.5 # Measures local terrain variation across roughly the footprint of one generated doorway.
const MAXIMUM_DOOR_HEIGHT_VARIATION: float = 1.65 # Rejects steep local ground that would leave the freestanding procedural frame visibly floating or buried.
const DUNGEON_WORLD_ORIGIN: Vector3 = Vector3(0.0, 20_000.0, 0.0) # Isolates the active interior far above suspended overworld collision while keeping local dungeon coordinates near zero.

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
var _entrance_root: Node3D # Owns all generated exterior doors as one top-level floating-origin entity.
var _pairs: Array[DungeonPairDefinition] = [] # Stores deterministic pair definitions reconstructed from the stable world seed and initial spawn.
var _entrances_ready: bool = false # Tracks whether overworld spawning has completed enough to place paired dungeon entrances safely.
var _active_pair: DungeonPairDefinition # Stores the pair whose deterministic interior is currently active.
var _active_dungeon: ProceduralDungeonWorld # Stores the disposable generated interior world while the player is inside it.

func _ready() -> void: # Creates the floating-origin entrance owner and waits for terrain-backed player spawning before deterministic pair placement.
    _camera = _player.get_view_camera() if _player != null else null # Resolves the existing first-person camera used by interaction and environment overrides.
    _entrance_root = Node3D.new() # Creates a runtime-only owner for every procedural exterior doorway.
    _entrance_root.name = "DungeonEntrances" # Gives the generated door collection a stable remote-scene-tree identity.
    if _dynamic_entities != null: # Verifies the floating-origin root exists before parenting generated world entities.
        _dynamic_entities.add_child(_entrance_root) # Makes all exterior doors inherit the exact same world-rebase shifts as the player and training dummy.

func _process(_delta: float) -> void: # Waits only as long as necessary for the existing asynchronous terrain/player spawn sequence to finish.
    if _entrances_ready or _active_dungeon != null: # Detects that placement is complete or an interior transition is currently active.
        return # Avoids unnecessary overworld placement checks during ordinary play and dungeon traversal.
    if _terrain == null or _player == null or _entrance_root == null: # Detects incomplete scene composition that cannot support deterministic entrance placement.
        return # Waits for valid dependencies rather than guessing coordinates.
    if _terrain.get_loaded_chunk_count() <= 0: # Detects terrain that has not yet generated the initial collision neighbourhood.
        return # Waits until authoritative height and water context is actively represented around the player.
    if not _player.is_physics_processing(): # Detects the phase where Game temporarily disables player physics during collision-backed shoreline placement.
        return # Waits until the player's final deterministic overworld spawn position has been resolved.
    _build_overworld_pairs() # Generates all requested paired exterior doors from stable world and spawn data.
    _entrances_ready = true # Permanently records successful initial pair placement for this game session.

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

func _build_overworld_pairs() -> void: # Creates several stable paired entrances around the deterministic initial player spawn using only procedural terrain data.
    _pairs.clear() # Removes any earlier pair metadata before constructing the one authoritative deterministic set.
    _clear_generated_exterior_doors() # Removes earlier generated door nodes if this initialization path is intentionally rerun during development.
    var player_world_position: Vector3 = _terrain.local_to_world_position(_player.global_position) # Converts the final near-origin player spawn into stable absolute procedural-world coordinates.
    var spawn_horizontal: Vector2 = Vector2(player_world_position.x, player_world_position.z) # Extracts the horizontal anchor shared by deterministic nearby pair placement.
    for pair_index: int in range(DUNGEON_PAIR_COUNT): # Generates each independent exterior pair from its own stable local random stream.
        var pair_seed: int = TerrainHeightSampler.WORLD_SEED + (pair_index + 1) * 1_000_003 # Derives a repeatable pair seed without consuming mutable global random state.
        var rng: RandomNumberGenerator = RandomNumberGenerator.new() # Creates an isolated placement generator for this pair.
        rng.seed = pair_seed # Resets every positional choice to the same sequence on every playthrough with the same world seed.
        var base_angle: float = TAU * float(pair_index) / float(DUNGEON_PAIR_COUNT) # Spreads pair regions evenly around the deterministic player spawn.
        var midpoint_angle: float = base_angle + rng.randf_range(-0.22, 0.22) # Adds restrained seeded angular variation so pair locations do not form an obvious perfect pattern.
        var midpoint_radius: float = FIRST_PAIR_RADIUS + float(pair_index) * PAIR_RADIUS_STEP + rng.randf_range(-5.0, 5.0) # Spreads later dungeons farther while varying each distance modestly.
        var midpoint_direction: Vector2 = Vector2(cos(midpoint_angle), sin(midpoint_angle)) # Converts the seeded polar direction into horizontal procedural-world space.
        var midpoint: Vector2 = spawn_horizontal + midpoint_direction * midpoint_radius # Establishes the approximate overworld centre between this pair's two endpoints.
        var span_angle_offset: float = PI * 0.5 + rng.randf_range(-0.52, 0.52) # Rotates the door-pair axis away from the radial placement line with deterministic variation.
        var span_direction: Vector2 = midpoint_direction.rotated(span_angle_offset).normalized() # Produces the normalized axis separating exterior endpoint A from endpoint B.
        var half_span: float = rng.randf_range(MINIMUM_HALF_PAIR_SPAN, MAXIMUM_HALF_PAIR_SPAN) # Chooses a meaningful but collision-neighbourhood-safe endpoint separation.
        var intended_a: Vector2 = midpoint - span_direction * half_span # Calculates the first intended overworld portal coordinate.
        var intended_b: Vector2 = midpoint + span_direction * half_span # Calculates the second intended overworld portal coordinate.
        var endpoint_a: Vector2 = _find_suitable_door_ground(intended_a) # Moves endpoint A only as far as necessary to nearby dry low-slope terrain.
        var endpoint_b: Vector2 = _find_suitable_door_ground(intended_b) # Independently resolves endpoint B onto deterministic suitable terrain.
        var pair: DungeonPairDefinition = DungeonPairDefinition.new() # Allocates strongly typed metadata for this one exterior pair and shared interior.
        pair.pair_id = pair_index # Assigns a stable compact pair identity used by generated doors and transition lookup.
        pair.dungeon_seed = pair_seed + 7_919 # Derives the interior seed independently from exact overworld placement choices.
        pair.endpoint_a_world_position = Vector3(endpoint_a.x, _terrain.get_height_at(endpoint_a) + ENDPOINT_GROUND_CLEARANCE, endpoint_a.y) # Grounds endpoint A on the authoritative procedural terrain height.
        pair.endpoint_b_world_position = Vector3(endpoint_b.x, _terrain.get_height_at(endpoint_b) + ENDPOINT_GROUND_CLEARANCE, endpoint_b.y) # Grounds endpoint B on its independently resolved terrain point.
        pair.endpoint_a_yaw = _get_yaw_facing_target(endpoint_a, spawn_horizontal) # Faces endpoint A generally back toward the starting region for easier visual discovery and safe exits.
        pair.endpoint_b_yaw = _get_yaw_facing_target(endpoint_b, spawn_horizontal) # Faces endpoint B toward the same regional anchor while preserving its own location.
        _pairs.append(pair) # Registers the complete deterministic definition before creating either physical doorway.
        _create_exterior_door(pair, DungeonPairDefinition.Endpoint.A) # Creates the first procedural overworld entrance under the floating-origin entity root.
        _create_exterior_door(pair, DungeonPairDefinition.Endpoint.B) # Creates the paired second overworld entrance linked to the exact same interior seed.

func _create_exterior_door(pair: DungeonPairDefinition, endpoint: DungeonPairDefinition.Endpoint) -> void: # Instantiates one runtime-only exterior frame from deterministic pair metadata.
    var door: DungeonDoor = DungeonDoor.new() # Allocates the complete procedural doorway implementation without loading a PackedScene asset.
    door.name = "Dungeon%dDoor%s" % [pair.pair_id + 1, "B" if endpoint == DungeonPairDefinition.Endpoint.B else "A"] # Gives the generated endpoint a stable human-readable remote-tree identity.
    door.position = _terrain.world_to_local_position(pair.get_world_position(endpoint)) # Converts the absolute pair coordinate into the current floating-origin scene space.
    door.configure(pair.pair_id, endpoint, true, pair.get_yaw(endpoint), pair.get_display_name(endpoint)) # Assigns immutable pair routing data and builds all procedural visual assets.
    _entrance_root.add_child(door) # Adds the doorway beneath the rebased entrance root so future origin shifts preserve terrain alignment.

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
    var direction: Vector2 = (target - origin).normalized() # Points from the generated door toward the desired overworld-facing target.
    if direction.is_zero_approx(): # Handles an impossible coincident target without producing an undefined atan2 orientation.
        direction = Vector2(0.0, -1.0) # Falls back to Godot's conventional default forward direction in horizontal space.
    return atan2(-direction.x, -direction.y) # Converts desired x/z forward direction into the player and doorway root yaw convention.

func _enter_dungeon(pair_id: int, endpoint: DungeonPairDefinition.Endpoint) -> bool: # Suspends the overworld, deterministically generates the selected pair's interior, and places the player inside the matching door.
    if _active_dungeon != null: # Rejects an entry request while another interior world is already active.
        return false # Prevents nested dungeon generation and ambiguous return routing.
    var pair: DungeonPairDefinition = _find_pair(pair_id) # Resolves the targeted exterior pair from deterministic metadata.
    if pair == null: # Detects stale or malformed door metadata not represented by the current world pair set.
        return false # Leaves the overworld untouched when no matching deterministic interior can be resolved.
    _active_pair = pair # Stores the exact pair before changing world visibility or player position.
    _active_dungeon = ProceduralDungeonWorld.new() # Creates a disposable runtime world that will be reconstructed from seed on every later visit.
    _active_dungeon.name = "ActiveDungeon_%d" % [pair.pair_id + 1] # Gives the generated interior a stable diagnostic name during this visit.
    _active_dungeon.position = DUNGEON_WORLD_ORIGIN # Places the isolated interior far above suspended terrain collision while keeping its own local geometry near zero.
    _active_dungeon.build(pair.pair_id, pair.dungeon_seed) # Reconstructs topology, meshes, materials, collision, doors, and lighting from the pair's stable seed.
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
    _camera.environment = null # Removes the dungeon-specific override so the overworld WorldEnvironment becomes authoritative again.
    _set_overworld_active(true) # Restores terrain streaming, vegetation, decorations, underwater effects, training target, and exterior doors before player placement.
    _player.initialize_environment(_terrain) # Reconnects swimming and water-state queries to the authoritative procedural overworld terrain.
    _player.velocity = Vector3.ZERO # Clears any interior movement before restoring overworld physics position.
    _player.global_position = return_local_position + exit_forward * EXIT_FORWARD_DISTANCE + Vector3(0.0, EXIT_PLAYER_CLEARANCE, 0.0) # Places the player safely outside the chosen exterior portal at the matching paired endpoint.
    _player.rotation.y = exit_yaw # Faces the player away from the returned-through doorway to reduce immediate re-entry confusion.
    _active_dungeon.queue_free() # Releases all generated layout nodes, meshes, materials, collision, doors, fixtures, and lights after the transition.
    _active_dungeon = null # Clears active interior ownership immediately so future exterior interactions can regenerate the dungeon from seed.
    _active_pair = null # Clears the temporary pair reference while deterministic pair metadata remains available in the overworld registry.
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
        _entrance_root.visible = enabled # Hides all overworld dungeon frames while their matching interior doors are active.
        _entrance_root.process_mode = process_mode_value # Suspends their otherwise minimal Area3D processing inheritance during dungeon traversal.
    if _underwater_view != null: # Verifies the overworld-only water presentation effect before changing world mode.
        _underwater_view.visible = enabled # Removes the terrain-dependent underwater overlay from generated interior rendering.
        _underwater_view.process_mode = process_mode_value # Stops or resumes its camera-water sampling work with the overworld.

func _find_pair(pair_id: int) -> DungeonPairDefinition: # Resolves stable pair metadata from a generated doorway's compact identity.
    for pair: DungeonPairDefinition in _pairs: # Visits the small bounded deterministic pair registry.
        if pair != null and pair.pair_id == pair_id: # Compares the requested identity against the current pair definition.
            return pair # Returns immediately when the matching exterior/interior routing metadata is found.
    return null # Reports an unknown pair identity without guessing a transition destination.

func _clear_generated_exterior_doors() -> void: # Removes previously generated entrance nodes while preserving the floating-origin root itself.
    if _entrance_root == null: # Handles initialization before the generated entrance owner exists.
        return # Avoids traversing a missing runtime root.
    for child: Node in _entrance_root.get_children(): # Visits every generated exterior door currently owned by the entrance collection.
        child.queue_free() # Releases the complete procedural door hierarchy at the end of the current frame.
