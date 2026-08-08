extends Node # Places and initializes the generic human NPC after terrain-backed player spawning has completed.
class_name GenericHumanNpcPlacement # Keeps world-composition placement separate from reusable NPC movement, combat, and billboard presentation logic.

const NPC_DISTANCE_FROM_PLAYER: float = 10.5 # Places the human near enough to encounter early while remaining outside its aggression radius at initial spawn.
const NPC_GROUND_CLEARANCE: float = 0.06 # Prevents the NPC capsule base from beginning slightly embedded in sampled terrain.
const CANDIDATE_DIRECTION_COUNT: int = 12 # Tests a bounded ring of possible placements around the completed player spawn.
const MAXIMUM_HEIGHT_DIFFERENCE: float = 1.35 # Rejects candidate terrain that is substantially above or below the player's nearby ground level.
const NPC_RANDOM_SEED_SALT: int = 5_823_119 # Separates this actor's deterministic wandering stream from terrain and dungeon random channels.

@onready var _terrain: InfiniteTerrain = $"../World/Terrain" # Stores the authoritative procedural terrain service used by game spawning and NPC grounding.
@onready var _player: FirstPersonPlayer = $"../DynamicEntities/Player" # Stores the completed player spawn used as the initial NPC placement anchor.
@onready var _npc: GenericHumanNpc = $"../DynamicEntities/GenericHumanNpc" # Stores the generic human instance that will be placed and initialized exactly once.

func _ready() -> void: # Begins bounded polling until the existing player and terrain startup flow has finished.
    set_process(true) # Keeps placement checks active until authoritative terrain chunks and final player physics are ready.

func _process(_delta: float) -> void: # Waits for the existing game spawn process before placing the moving hostile NPC.
    if _terrain == null or _player == null or _npc == null: # Detects incomplete scene composition that cannot safely initialize the NPC.
        return # Waits for valid authored dependencies instead of guessing scene positions or player references.
    if _terrain.get_loaded_chunk_count() <= 0: # Detects terrain that has not yet initialized around the selected shoreline spawn.
        return # Prevents grounding the NPC against unavailable procedural collision and height data.
    if not _player.is_physics_processing(): # Detects the phase where the game temporarily disables player physics during collision-backed spawn placement.
        return # Waits until the final player position has been resolved and activated.
    _place_and_initialize_npc() # Grounds the generic human near the completed player spawn and connects its player/terrain dependencies.
    set_process(false) # Stops composition-time polling permanently after the one required initialization pass.

func _place_and_initialize_npc() -> void: # Selects a dry nearby point, places the NPC at sampled terrain height, and seeds its autonomous wandering behavior.
    var player_world_position: Vector3 = _terrain.local_to_world_position(_player.global_position) # Converts the floating-origin scene transform into stable procedural world coordinates.
    var player_horizontal: Vector2 = Vector2(player_world_position.x, player_world_position.z) # Extracts the terrain-sampling coordinate used for candidate placement.
    var player_forward_3d: Vector3 = -_player.global_transform.basis.z.normalized() # Reads the player's current horizontal facing basis after startup placement completes.
    var player_forward: Vector2 = Vector2(player_forward_3d.x, player_forward_3d.z) # Projects the first-person forward direction onto the procedural world's horizontal plane.
    if player_forward.length_squared() <= 0.0001: # Handles a degenerate transform basis defensively.
        player_forward = Vector2(0.0, -1.0) # Falls back to Godot's conventional forward direction when no usable horizontal basis exists.
    else: # Handles the normal valid player-facing case.
        player_forward = player_forward.normalized() # Normalizes the placement direction before applying the configured physical distance.
    var npc_horizontal: Vector2 = _find_dry_candidate(player_horizontal, player_forward) # Chooses a nearby dry low-variation point around the player, preferring a side/rear encounter angle.
    var npc_ground_height: float = _terrain.get_height_at(npc_horizontal) # Samples the same deterministic terrain height used by the rendered and collidable world surface.
    var npc_world_position: Vector3 = Vector3(npc_horizontal.x, npc_ground_height + NPC_GROUND_CLEARANCE, npc_horizontal.y) # Builds the actor's stable absolute world-space foot position.
    _npc.global_position = _terrain.world_to_local_position(npc_world_position) # Converts the absolute coordinate into current floating-origin scene space under DynamicEntities.
    var stable_seed: int = int(npc_horizontal.x * 31.0) ^ int(npc_horizontal.y * 17.0) ^ TerrainHeightSampler.WORLD_SEED ^ NPC_RANDOM_SEED_SALT # Derives a reproducible local behavior seed from world position and the existing terrain seed.
    _npc.initialize(_player, _terrain, stable_seed) # Connects authoritative dependencies and starts deterministic wandering from the final grounded position.

func _find_dry_candidate(player_horizontal: Vector2, forward: Vector2) -> Vector2: # Searches around the player for a dry low-variation spawn that starts outside immediate attack range.
    var player_ground_height: float = _terrain.get_height_at(player_horizontal) # Measures nearby ground height so steep candidate differences can be rejected cheaply.
    var preferred_direction: Vector2 = forward.rotated(PI * 0.65) # Starts the human off to one side and slightly behind rather than directly blocking the initial camera view.
    for direction_index: int in range(CANDIDATE_DIRECTION_COUNT): # Tests evenly spaced alternatives around the player within a bounded amount of startup work.
        var angle: float = TAU * float(direction_index) / float(CANDIDATE_DIRECTION_COUNT) # Converts candidate index into one complete horizontal search ring.
        var direction: Vector2 = preferred_direction.rotated(angle) # Rotates through every ring candidate beginning from the preferred encounter side.
        var candidate: Vector2 = player_horizontal + direction * NPC_DISTANCE_FROM_PLAYER # Builds the stable absolute horizontal coordinate at the configured initial encounter distance.
        if _terrain.has_water_at(candidate): # Rejects candidates occupied by the procedural water surface.
            continue # Tries the next direction without placing the walking human in water.
        var candidate_height: float = _terrain.get_height_at(candidate) # Samples exact deterministic terrain elevation at the dry candidate.
        if absf(candidate_height - player_ground_height) > MAXIMUM_HEIGHT_DIFFERENCE: # Rejects abrupt nearby height changes that would make the initial encounter awkward or inaccessible.
            continue # Continues around the ring looking for a more naturally walkable placement.
        return candidate # Uses the first suitable candidate to keep startup placement deterministic and bounded.
    return player_horizontal + preferred_direction * NPC_DISTANCE_FROM_PLAYER # Falls back to the preferred side/rear location if every bounded terrain candidate is rejected.
