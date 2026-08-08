extends BillboardNpc3D # Implements the generic human as a moving NPC while inheriting the mandatory billboard-only character presentation contract.
class_name GenericHumanNpc # Exposes a reusable wandering human actor that becomes hostile when the player approaches.

const MAXIMUM_HEALTH: float = 60.0 # Defines the generic human's damageable health pool before the actor is removed from the world.
const BILLBOARD_SIZE: Vector2 = Vector2(1.08, 1.92) # Matches the flat human texture to approximately ordinary human collision dimensions.
const WANDER_SPEED: float = 1.35 # Defines the relaxed walking speed used while the human is not aware of the player.
const CHASE_SPEED: float = 2.65 # Defines the faster approach speed used after the player enters the aggression radius.
const AGGRO_DISTANCE: float = 7.0 # Makes the human hostile only when the player comes intentionally close.
const ATTACK_DISTANCE: float = 1.45 # Stops the human outside capsule overlap while keeping melee attacks visibly close-range.
const ATTACK_DAMAGE: float = 8.0 # Removes a modest amount of player health on each successful close-range attack.
const ATTACK_COOLDOWN_SECONDS: float = 1.1 # Prevents attack damage from being applied every physics frame while the player remains nearby.
const ATTACK_VISUAL_SECONDS: float = 0.16 # Defines the brief billboard squash used as lightweight attack feedback without skeletal animation.
const WANDER_MINIMUM_SECONDS: float = 1.7 # Defines the shortest duration the NPC keeps one wandering heading before choosing another.
const WANDER_MAXIMUM_SECONDS: float = 4.2 # Defines the longest bounded wandering interval before a new heading is selected.
const WANDER_RADIUS: float = 8.0 # Keeps ordinary wandering near the actor's authored spawn area instead of drifting indefinitely across the world.
const WATER_LOOKAHEAD_DISTANCE: float = 0.85 # Samples ahead of movement so the wandering human avoids deliberately walking into generated water.
const MAXIMUM_GROUND_HEIGHT_CHANGE: float = 0.85 # Rejects movement toward abrupt terrain steps that ordinary CharacterBody walking should not attempt.
const REMOTE_WORLD_VERTICAL_DISTANCE: float = 64.0 # Pauses the NPC while the player occupies a remote world space such as the below-world dungeon pocket.
const WALK_BOB_HEIGHT: float = 0.035 # Adds a restrained vertical billboard bob while the NPC is moving without changing collision.
const WALK_BOB_SPEED: float = 9.0 # Controls the pace of the lightweight billboard walking motion.
const DEFAULT_RANDOM_SEED: int = 941_773 # Provides deterministic fallback wandering before composition supplies a location-derived seed.

@onready var _health: DamageableHealth = $Health # Stores reusable damageable health state consumed by player equipment hits.

var _player: FirstPersonPlayer # Stores the active player used for proximity aggression, chasing, and close-range attacks.
var _player_vitals: PlayerVitals # Stores the player's authoritative health model so NPC attacks use the existing resource system.
var _terrain: InfiniteTerrain # Stores the active procedural terrain service used to keep wandering movement out of obvious water and cliff steps.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new() # Owns isolated wandering randomness so NPC behavior does not consume unrelated global random state.
var _home_world_horizontal: Vector2 = Vector2.ZERO # Stores the stable floating-origin-independent spawn coordinate that bounds ordinary wandering.
var _wander_direction: Vector2 = Vector2.ZERO # Stores the current normalized horizontal heading used by non-hostile wandering movement.
var _wander_seconds_remaining: float = 0.0 # Counts down until the NPC selects another deterministic wandering heading.
var _attack_seconds_remaining: float = 0.0 # Counts down the damage cooldown after a successful attack against the player.
var _attack_visual_seconds_remaining: float = 0.0 # Counts down the short visual squash that communicates an attack from the flat billboard actor.
var _walk_phase: float = 0.0 # Accumulates the procedural billboard bob phase while the NPC moves across the ground.
var _billboard_base_position: Vector3 = Vector3.ZERO # Stores the authored billboard position so movement animation never drifts away from the collision body.

func _ready() -> void: # Initializes billboard presentation, damageable state, and fallback wandering before game composition injects world dependencies.
    super._ready() # Registers this actor under the shared NPC policy and validates the required MeshInstance3D billboard child.
    configure_billboard(GenericHumanBillboardTexture.create_texture(), BILLBOARD_SIZE) # Builds the complete human appearance as one transparent texture on the required billboard mesh.
    _health.initialize(MAXIMUM_HEALTH) # Starts the reusable health component at the generic human's full configured health.
    _rng.seed = DEFAULT_RANDOM_SEED # Gives pre-initialization wandering a deterministic local random stream.
    _billboard_base_position = get_billboard_visual().position # Captures the authored visual offset before any procedural walk or attack motion is applied.
    _choose_new_wander_direction() # Selects an initial heading so the actor can begin walking as soon as composition finishes initialization.

func initialize(player: FirstPersonPlayer, terrain: InfiniteTerrain, random_seed: int) -> void: # Connects the generic human to the active player and terrain after terrain-backed game spawning has completed.
    _player = player # Stores the exact composed player instance that this NPC may detect, chase, and attack.
    _terrain = terrain # Stores the authoritative terrain service used for floating-origin-safe movement checks.
    _player_vitals = null # Clears any earlier player-health reference before resolving the supplied composed player instance.
    if _player != null: # Confirms a valid player exists before querying its authoritative vitals child.
        _player_vitals = _player.get_node_or_null(NodePath("PlayerVitals")) as PlayerVitals # Resolves player health through the existing child component rather than introducing a second combat resource model.
    _rng.seed = random_seed # Seeds wandering from stable composition data so this NPC's initial movement is reproducible for the same spawn.
    if _terrain != null: # Confirms stable world-coordinate conversion is available before recording the wander origin.
        var home_world_position: Vector3 = _terrain.local_to_world_position(global_position) # Converts the current near-origin scene position into floating-origin-independent procedural world space.
        _home_world_horizontal = Vector2(home_world_position.x, home_world_position.z) # Stores only the horizontal coordinate needed to bound wandering around the spawn area.
    _choose_new_wander_direction() # Re-selects the initial heading using the final stable random seed and completed world position.

func _physics_process(delta: float) -> void: # Advances wandering, hostility, attacks, grounded movement, and lightweight billboard animation each physics frame.
    if _health.is_dead(): # Detects the short deferred-free interval after a lethal equipment hit.
        velocity = Vector3.ZERO # Prevents any final movement while the defeated NPC waits for scene-tree removal.
        return # Stops all AI and attack processing for the defeated actor.
    _attack_seconds_remaining = maxf(_attack_seconds_remaining - delta, 0.0) # Advances the bounded attack cooldown without allowing negative timer values.
    _attack_visual_seconds_remaining = maxf(_attack_visual_seconds_remaining - delta, 0.0) # Advances the short attack presentation timer independently from combat cooldown.
    if _player == null or _terrain == null: # Detects an NPC that has not yet received required game-composition dependencies.
        _apply_gravity(delta) # Keeps an uninitialized actor physically grounded instead of suspending it in the air.
        velocity.x = 0.0 # Prevents horizontal autonomous movement until player and terrain references are authoritative.
        velocity.z = 0.0 # Prevents depth movement for the same incomplete initialization state.
        move_and_slide() # Resolves only gravity and ordinary static collision while waiting for composition initialization.
        _update_billboard_animation(delta) # Keeps the visual reset and attack state coherent even during initialization delay.
        return # Stops before proximity or terrain queries that require the missing dependencies.
    if absf(_player.global_position.y - global_position.y) > REMOTE_WORLD_VERTICAL_DISTANCE: # Detects the player occupying a separated world space such as a dungeon interior far below the overworld.
        velocity = Vector3.ZERO # Freezes the NPC in place so suspended overworld collision cannot cause it to fall while the player is elsewhere.
        _reset_billboard_pose() # Restores the flat character texture to its stable idle pose while world spaces are separated.
        return # Stops all wandering, chasing, gravity, and attacks until the player returns to the same world space.
    var player_offset: Vector3 = _player.global_position - global_position # Measures current scene-space separation because both actors share the same floating-origin root while in the overworld.
    var player_horizontal_offset: Vector2 = Vector2(player_offset.x, player_offset.z) # Extracts horizontal separation used by aggression and ground movement.
    var player_distance: float = player_horizontal_offset.length() # Calculates exact horizontal range to the player independently from small terrain-height differences.
    var desired_direction: Vector2 = Vector2.ZERO # Starts each frame with no requested horizontal movement until AI state selects one.
    var desired_speed: float = 0.0 # Starts each frame stopped and is raised only by wandering or chase behavior.
    if player_distance <= AGGRO_DISTANCE: # Detects the hostile state entered when the player approaches this generic human closely.
        if player_distance <= ATTACK_DISTANCE: # Detects close range where further approach would unnecessarily press character capsules together.
            _try_attack_player() # Applies bounded damage through PlayerVitals when the attack cooldown permits.
        elif player_distance > 0.0001: # Confirms the player offset can be normalized safely for chase movement.
            desired_direction = player_horizontal_offset / player_distance # Points the NPC directly toward the nearby player on the horizontal plane.
            desired_speed = CHASE_SPEED # Uses the faster hostile approach speed while outside melee attack range.
    else: # Handles the ordinary non-hostile state when the player remains outside the aggression radius.
        _wander_seconds_remaining = maxf(_wander_seconds_remaining - delta, 0.0) # Advances the current wandering-heading lifetime.
        if _wander_seconds_remaining <= 0.0: # Detects expiration of the current bounded wander segment.
            _choose_new_wander_direction() # Selects another stable random heading and duration around the spawn area.
        desired_direction = _get_home_corrected_wander_direction() # Uses either the random heading or a return-home vector if the actor has wandered too far.
        desired_speed = WANDER_SPEED # Uses the relaxed walking speed for ordinary ambient NPC movement.
    if not _is_direction_safe(desired_direction): # Detects movement that would step into water or across an excessive terrain-height discontinuity.
        desired_direction = Vector2.ZERO # Stops before the unsafe terrain sample instead of relying on collision after entering unsuitable ground.
        desired_speed = 0.0 # Removes horizontal speed for the rejected movement direction.
        if player_distance > AGGRO_DISTANCE: # Detects an unsafe direction during wandering rather than deliberate player pursuit.
            _choose_new_wander_direction() # Immediately tries another ambient heading instead of remaining stationary for the rest of the wander timer.
    velocity.x = desired_direction.x * desired_speed # Applies the selected horizontal x velocity while leaving gravity responsible for vertical motion.
    velocity.z = desired_direction.y * desired_speed # Applies the selected horizontal z velocity using the two-dimensional movement direction's y component.
    _apply_gravity(delta) # Applies project gravity whenever the CharacterBody is not grounded on ordinary world collision.
    move_and_slide() # Resolves terrain, player, and world collisions using the actor's capsule while preserving floor handling.
    if is_on_wall() and player_distance > AGGRO_DISTANCE: # Detects ambient wandering that has physically reached an obstacle despite terrain lookahead.
        _choose_new_wander_direction() # Chooses a different heading immediately so the NPC does not continuously push against the same wall or prop.
    _update_billboard_animation(delta) # Animates only the flat MeshInstance3D presentation based on the final resolved movement and attack state.

func receive_equipment_hit(hit: EquipmentHit) -> void: # Accepts the same structured melee hit contract already used by the existing training target.
    if hit == null or _health.is_dead(): # Rejects malformed impacts and repeated hits after the NPC has already been defeated.
        return # Leaves health and actor state unchanged for invalid or redundant contacts.
    var applied_damage: float = _health.apply_damage(hit.damage) # Applies the equipped weapon or tool's exact authored damage through the reusable health component.
    if applied_damage <= 0.0: # Detects hits whose configured damage produces no health change.
        return # Avoids false defeat or reaction behavior when the impact did not damage the NPC.
    _attack_visual_seconds_remaining = ATTACK_VISUAL_SECONDS # Reuses the brief billboard scale reaction to make successful player hits visible without model animation.
    if not _health.is_dead(): # Detects a damaging but non-lethal player equipment hit.
        return # Keeps the hostile actor active with its remaining health.
    velocity = Vector3.ZERO # Stops movement immediately on the lethal hit before deferred node removal.
    collision_layer = 0 # Removes the defeated actor from subsequent melee and body collision queries during the deferred-free interval.
    collision_mask = 0 # Prevents the defeated actor from resolving additional world or player collision before deletion.
    queue_free() # Removes the generic hostile human cleanly after lethal damage rather than leaving an inert character model in the world.

func _try_attack_player() -> void: # Applies one close-range attack through the player's authoritative health component when the cooldown is ready.
    if _attack_seconds_remaining > 0.0 or _player_vitals == null: # Rejects repeated frame-rate damage and attacks before player health has been resolved.
        return # Leaves player health unchanged until the cooldown expires and a valid vitals component exists.
    if _player_vitals.get_health() <= 0.0: # Detects a player whose current health has already reached zero.
        return # Avoids repeatedly attacking an already depleted health pool while a future death system handles that state.
    _player_vitals.apply_damage(ATTACK_DAMAGE) # Removes configured melee damage through the same clamped revision-tracked health model consumed by the HUD.
    _attack_seconds_remaining = ATTACK_COOLDOWN_SECONDS # Starts the bounded interval before another close-range hit may be applied.
    _attack_visual_seconds_remaining = ATTACK_VISUAL_SECONDS # Starts a short texture-only attack motion so damage has immediate visual feedback.

func _apply_gravity(delta: float) -> void: # Applies ordinary project gravity only while the NPC is airborne.
    if is_on_floor(): # Detects stable ground contact from the previous CharacterBody movement result.
        if velocity.y < 0.0: # Detects residual downward velocity that should be cleared after landing.
            velocity.y = 0.0 # Removes accumulated fall velocity so grounded walking remains stable on terrain.
        return # Skips gravity while the NPC is already supported by a floor surface.
    var gravity: Vector3 = get_gravity() # Reads the project-configured gravity vector provided by the shared billboard NPC base class.
    velocity += gravity * delta # Integrates gravity into the current velocity for this physics step.

func _choose_new_wander_direction() -> void: # Selects one bounded random ambient movement segment from the NPC's isolated random stream.
    var angle: float = _rng.randf_range(0.0, TAU) # Samples a complete horizontal heading without favouring cardinal directions.
    _wander_direction = Vector2(cos(angle), sin(angle)).normalized() # Converts the sampled angle into a stable normalized x/z movement vector.
    _wander_seconds_remaining = _rng.randf_range(WANDER_MINIMUM_SECONDS, WANDER_MAXIMUM_SECONDS) # Assigns a varied but bounded lifetime to the selected heading.

func _get_home_corrected_wander_direction() -> Vector2: # Keeps ambient movement within a loose radius around the floating-origin-independent spawn position.
    if _terrain == null: # Detects missing world-coordinate conversion defensively.
        return _wander_direction # Uses the current random heading when no stable home comparison can be performed.
    var current_world_position: Vector3 = _terrain.local_to_world_position(global_position) # Converts current scene position into absolute procedural world coordinates after any floating-origin shifts.
    var current_horizontal: Vector2 = Vector2(current_world_position.x, current_world_position.z) # Extracts the horizontal coordinate used by the wander-radius check.
    var home_offset: Vector2 = _home_world_horizontal - current_horizontal # Points from the NPC's current position back toward its original spawn area.
    if home_offset.length() <= WANDER_RADIUS: # Detects an actor still within its permitted ordinary wandering neighbourhood.
        return _wander_direction # Preserves the current random ambient heading while the NPC remains near home.
    if home_offset.length_squared() <= 0.0001: # Handles the degenerate zero-length return vector defensively.
        return Vector2.ZERO # Stops rather than attempting to normalize an invalid direction.
    return home_offset.normalized() # Guides the actor back toward its stable spawn neighbourhood after it crosses the wander radius.

func _is_direction_safe(direction: Vector2) -> bool: # Uses authoritative terrain samples to reject obvious water entry and abrupt ground-height steps ahead of movement.
    if direction.length_squared() <= 0.0001 or _terrain == null: # Treats stationary movement and missing terrain as states requiring no directional rejection.
        return true # Allows the actor to remain still without performing unnecessary world queries.
    var current_world_position: Vector3 = _terrain.local_to_world_position(global_position) # Converts the actor's current near-origin position to stable procedural world coordinates.
    var current_horizontal: Vector2 = Vector2(current_world_position.x, current_world_position.z) # Extracts the terrain-sampling coordinate beneath the actor.
    var lookahead_horizontal: Vector2 = current_horizontal + direction.normalized() * WATER_LOOKAHEAD_DISTANCE # Samples a short distance ahead along the requested movement heading.
    if _terrain.has_water_at(lookahead_horizontal): # Detects generated water occupying the immediate movement destination.
        return false # Rejects the direction so the generic walking NPC does not intentionally enter water.
    var current_ground_height: float = _terrain.get_height_at(current_horizontal) # Samples authoritative terrain elevation beneath the current actor location.
    var lookahead_ground_height: float = _terrain.get_height_at(lookahead_horizontal) # Samples authoritative terrain elevation at the short movement lookahead point.
    return absf(lookahead_ground_height - current_ground_height) <= MAXIMUM_GROUND_HEIGHT_CHANGE # Accepts only terrain changes small enough for ordinary grounded movement.

func _update_billboard_animation(delta: float) -> void: # Applies small presentation-only motion to the mandatory billboard MeshInstance3D without affecting collision or world position.
    var visual: MeshInstance3D = get_billboard_visual() # Resolves the required billboard presentation node through the shared NPC base contract.
    if visual == null: # Handles an invalid scene defensively even though the base class asserts this requirement in development builds.
        return # Skips presentation animation when no permitted billboard mesh exists.
    var horizontal_speed_squared: float = velocity.x * velocity.x + velocity.z * velocity.z # Measures resolved ground movement without including gravity or slope settling.
    if horizontal_speed_squared > 0.04 and is_on_floor(): # Detects active grounded walking or chasing that should display a lightweight step rhythm.
        _walk_phase += delta * WALK_BOB_SPEED # Advances the procedural walking phase according to elapsed physics time.
        visual.position = _billboard_base_position + Vector3(0.0, sin(_walk_phase) * WALK_BOB_HEIGHT, 0.0) # Bobs only the flat character texture while leaving the gameplay capsule stable.
    else: # Handles idle, airborne, blocked, or attack-range states without ordinary walking motion.
        visual.position = _billboard_base_position # Restores the texture to its authored centred position instead of accumulating animation drift.
    if _attack_visual_seconds_remaining > 0.0: # Detects a recent attack or received hit that should produce immediate flat-sprite feedback.
        visual.scale = Vector3(1.08, 0.94, 1.0) # Briefly widens and compresses the billboard without adding skeletal or model-based animation.
        return # Preserves the reaction scale until its short timer expires.
    visual.scale = Vector3.ONE # Restores the billboard to exact authored scale after walking and attack presentation updates.

func _reset_billboard_pose() -> void: # Restores all procedural visual offsets while the NPC is paused in a separated world space.
    var visual: MeshInstance3D = get_billboard_visual() # Resolves the required flat presentation mesh through the common NPC base class.
    if visual == null: # Handles malformed scenes defensively.
        return # Stops without attempting to modify missing presentation state.
    visual.position = _billboard_base_position # Restores the human texture to its authored vertical centre.
    visual.scale = Vector3.ONE # Removes any partially completed attack or hit squash while the NPC is paused.
