extends RefCounted # Own distance-based update timing independently of villager behaviour.
class_name NpcUpdateCadence # Share one cadence policy across overworld and interior populations.

const DISTANCE_INTERVAL: float = 0.25 # Bound distance checks while retaining prompt proximity changes.
const FULL_PHYSICS_DISTANCE: float = 80.0 # Preserve collision-backed movement near the player.
const MEDIUM_PHYSICS_DISTANCE: float = 180.0 # Separate intermediate patrols from distant travel.
const FULL_ANIMATION_DISTANCE: float = 40.0 # Preserve smooth poses within clear viewing range.
const MEDIUM_ANIMATION_DISTANCE: float = 120.0 # Retain readable motion at intermediate distances.
const MEDIUM_PHYSICS_INTERVAL: float = 0.1 # Reduce intermediate route and perception work.
const FAR_PHYSICS_INTERVAL: float = 0.25 # Reduce distant patrol work while preserving elapsed travel time.
const MEDIUM_ANIMATION_INTERVAL: float = 1.0 / 15.0 # Reduce intermediate skeleton evaluations.
const FAR_ANIMATION_INTERVAL: float = 0.2 # Reduce distant skeleton evaluations.

var distance_squared: float = 0.0 # Retain the most recently measured player distance.
var _distance_elapsed: float = DISTANCE_INTERVAL # Resolve proximity on the first physics update.
var _physics_elapsed: float = 0.0 # Accumulate travel time between simulation updates.
var _animation_elapsed: float = 0.0 # Accumulate animation time between pose evaluations.
var _physics_phase: float = 1.0 # Distribute the first distant movement deadline.
var _animation_phase: float = 1.0 # Distribute the first distant pose deadline.

func configure(identity: int) -> void: # Spread distant update phases without changing elapsed simulation time.
    _distance_elapsed = DISTANCE_INTERVAL # Ensure the first distance sample uses the current positions.
    _physics_phase = float(identity % 16 + 1) / 16.0 # Spread the first distant movement update.
    _animation_phase = float(identity % 13 + 1) / 13.0 # Spread the first distant pose update.

func distance_check_due(delta: float) -> bool: # Report when the caller should resolve player proximity.
    _distance_elapsed += delta # Accumulate real physics time.
    if _distance_elapsed < DISTANCE_INTERVAL: # Retain the preceding distance between checks.
        return false # Avoid repeated spatial queries.
    _distance_elapsed = 0.0 # Restart the distance sampling delay.
    return true # Request a fresh relative distance.

func physics_step(delta: float, urgent: bool) -> float: # Return accumulated simulation time only when movement work is due.
    _physics_elapsed += delta # Preserve time between distant patrol updates.
    var interval: float = 0.0 if urgent or distance_squared <= FULL_PHYSICS_DISTANCE * FULL_PHYSICS_DISTANCE else MEDIUM_PHYSICS_INTERVAL if distance_squared <= MEDIUM_PHYSICS_DISTANCE * MEDIUM_PHYSICS_DISTANCE else FAR_PHYSICS_INTERVAL # Keep nearby interactions and combat responsive.
    if interval > 0.0 and _physics_elapsed < interval * _physics_phase: # Defer distant work until its cadence expires.
        return 0.0 # Skip the expensive movement path this tick.
    var elapsed: float = maxf(delta, _physics_elapsed) # Preserve accumulated travel time when returning to full updates.
    _physics_elapsed = 0.0 # Consume the pending simulation time.
    _physics_phase = 1.0 # Use the ordinary cadence after the initial phased deadline.
    return elapsed # Advance patrol state by the elapsed duration.

func animation_step(delta: float, urgent: bool) -> float: # Return accumulated animation time only when a pose evaluation is due.
    _animation_elapsed += delta # Preserve animation playback time between sampled poses.
    var interval: float = 0.0 if urgent or distance_squared <= FULL_ANIMATION_DISTANCE * FULL_ANIMATION_DISTANCE else MEDIUM_ANIMATION_INTERVAL if distance_squared <= MEDIUM_ANIMATION_DISTANCE * MEDIUM_ANIMATION_DISTANCE else FAR_ANIMATION_INTERVAL # Match pose frequency to viewing distance.
    if interval > 0.0 and _animation_elapsed < interval * _animation_phase: # Defer a distant skeleton evaluation.
        return 0.0 # Keep the previous pose until the next update.
    var elapsed: float = maxf(delta, _animation_elapsed) # Preserve playback progress when returning to full animation.
    _animation_elapsed = 0.0 # Consume the pending animation time.
    _animation_phase = 1.0 # Use the ordinary cadence after the initial phased deadline.
    return elapsed # Advance the manual animation player once.

func uses_distant_movement() -> bool: # Choose route simulation outside the close collision neighbourhood.
    return distance_squared > FULL_PHYSICS_DISTANCE * FULL_PHYSICS_DISTANCE # Keep near-player movement in the physics engine.

func reset() -> void: # Discard pending time when streaming suspends an actor.
    _physics_elapsed = 0.0 # Prevent catch-up movement after reactivation.
    _animation_elapsed = 0.0 # Prevent catch-up animation after reactivation.
    _distance_elapsed = DISTANCE_INTERVAL # Refresh proximity immediately after reactivation.
