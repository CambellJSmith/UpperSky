extends Node # Places the combat training dummy after terrain-backed player spawning has completed.
class_name TrainingDummyPlacement # Keeps world-composition placement logic separate from the reusable enemy scene itself.

const DUMMY_DISTANCE_FROM_PLAYER: float = 2.2 # Places the target close enough for the starting sword and pickaxe camera rays to reach immediately.
const DUMMY_GROUND_CLEARANCE: float = 0.04 # Prevents the dummy base from visually intersecting the sampled terrain surface.
const CANDIDATE_DIRECTION_COUNT: int = 8 # Tries enough directions around the spawn to avoid water while keeping placement work bounded.
const MAXIMUM_HEIGHT_DIFFERENCE: float = 2.5 # Avoids placing the target on a nearby cliff step that would make combat testing awkward.

@onready var _terrain: InfiniteTerrain = $"../World/Terrain" # Stores the authoritative terrain service used by player spawning and dummy ground placement.
@onready var _player: FirstPersonPlayer = $"../DynamicEntities/Player" # Stores the active player whose completed spawn position anchors the training target.
@onready var _training_dummy: StrawDummyEnemy = $"../DynamicEntities/TrainingDummy" # Stores the reusable combat target instance owned by the dynamic-entity root.

func _ready() -> void: # Starts in polling mode until terrain initialization and collision-backed player placement are complete.
    set_process(true) # Ensures placement checks run even though the node has no ongoing responsibility after spawn.

func _process(_delta: float) -> void: # Waits for the existing game spawn flow to finish without adding signal dependencies.
    if _terrain == null or _player == null or _training_dummy == null: # Detects an incomplete game composition that cannot place the target safely.
        return # Waits for valid authored dependencies rather than guessing a world position.
    if _terrain.get_loaded_chunk_count() <= 0: # Detects terrain that has not yet been initialized around the selected shoreline spawn.
        return # Prevents placement against an uninitialized procedural world.
    if not _player.is_physics_processing(): # Detects the phase where the game temporarily disables player physics during collision-backed spawn placement.
        return # Waits until the game has resolved and activated the final player position.
    _place_training_dummy() # Grounds the dummy near the completed player spawn using authoritative terrain sampling.
    set_process(false) # Permanently stops placement polling after the one required composition-time placement.

func _place_training_dummy() -> void: # Selects a nearby dry point and moves the dummy onto the exact procedural terrain height.
    var player_world_position: Vector3 = _terrain.local_to_world_position(_player.global_position) # Converts the near-origin player transform into stable procedural-world coordinates.
    var player_horizontal: Vector2 = Vector2(player_world_position.x, player_world_position.z) # Extracts the horizontal coordinate used by terrain and water sampling.
    var local_forward_3d: Vector3 = -_player.global_transform.basis.z.normalized() # Reads the player's current first-person forward direction from the scene transform.
    var forward: Vector2 = Vector2(local_forward_3d.x, local_forward_3d.z).normalized() # Converts the view-facing direction into horizontal placement space.
    if forward.length_squared() <= 0.0001: # Handles an invalid transform basis defensively.
        forward = Vector2(0.0, -1.0) # Falls back to Godot's conventional first-person forward direction.
    var dummy_horizontal: Vector2 = _find_dry_candidate(player_horizontal, forward) # Chooses the nearest suitable direction beginning directly in front of the player.
    var dummy_height: float = _terrain.get_height_at(dummy_horizontal) # Samples the same deterministic ground height used by rendered terrain.
    var dummy_world_position: Vector3 = Vector3(dummy_horizontal.x, dummy_height + DUMMY_GROUND_CLEARANCE, dummy_horizontal.y) # Builds a grounded absolute world transform for the target's feet.
    _training_dummy.global_position = _terrain.world_to_local_position(dummy_world_position) # Converts the stable world coordinate back into current floating-origin scene space.

func _find_dry_candidate(player_horizontal: Vector2, forward: Vector2) -> Vector2: # Searches clockwise around the player for a dry low-variation target position.
    var player_ground_height: float = _terrain.get_height_at(player_horizontal) # Measures the player's local ground elevation for nearby slope rejection.
    for direction_index: int in range(CANDIDATE_DIRECTION_COUNT): # Tests the forward point first and then evenly spaced alternatives around the player.
        var angle: float = TAU * float(direction_index) / float(CANDIDATE_DIRECTION_COUNT) # Converts the candidate index into a complete horizontal ring.
        var direction: Vector2 = forward.rotated(angle) # Rotates from the player's facing direction while preserving fixed target distance.
        var candidate: Vector2 = player_horizontal + direction * DUMMY_DISTANCE_FROM_PLAYER # Builds the absolute horizontal coordinate for this candidate.
        if _terrain.has_water_at(candidate): # Rejects positions occupied by the rendered clipped water surface.
            continue # Tries the next nearby direction without placing the dummy in water.
        var candidate_height: float = _terrain.get_height_at(candidate) # Samples the exact terrain elevation at this dry candidate.
        if absf(candidate_height - player_ground_height) > MAXIMUM_HEIGHT_DIFFERENCE: # Rejects abrupt local terrain changes that would make the target hard to reach.
            continue # Tries another nearby direction on more level ground.
        return candidate # Uses the first suitable point so the dummy remains directly ahead whenever possible.
    return player_horizontal + forward * DUMMY_DISTANCE_FROM_PLAYER # Falls back to the immediate forward point if every bounded alternative was rejected.
