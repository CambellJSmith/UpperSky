extends Node3D # Own one bounded spontaneous encounter independently of ordinary population streamers.
class_name RadiantEventDirector # Schedule offscreen challengers and coordinate approach, consent and retirement.

enum State { IDLE, APPROACHING, TALKING, FIGHTING, LEAVING } # Keep the event lifecycle explicit.
const UPDATE_INTERVAL: float = 0.25 # Bound scheduling and approach steering outside actor physics updates.
const APPROACH_TIMEOUT: float = 60.0 # Abort a pursuit that cannot reach a moving or obstructed player.
@onready var _player: FirstPersonPlayer = $"../DynamicEntities/Player" # Resolve the participant through ordinary game composition.
@onready var _terrain: InfiniteTerrain = $"../World/Terrain" # Resolve the authoritative overworld terrain.
@onready var _dialogue: DialogueInteraction = $"../Dialogue Interaction" # Reuse the conversation controller's ownership and consent handling.
var _sampler: RadiantSpawnSampler # Validate rare spawn attempts independently of scheduling.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new() # Vary encounter timing and human or orc appearance.
var _actor: Villager # Retain only the current radiant actor.
var _state: State = State.IDLE # Track whether this director is free to start another event.
var _elapsed: float = 0.0 # Accumulate bounded director update time.
var _remaining: float = 0.0 # Retain the next eligible spawn deadline.
var _age: float = 0.0 # Bound unsuccessful approach lifetime.
var _attempts: int = 0 # Bound placement retries without scanning a large region.
var _sequence: int = 0 # Keep event actor identities distinct within a game session.
var _session_seed: int = 0 # Separate new radiant actors from saved ordinary populations.
var _departure: Vector2 # Remember the original safe ground position for peaceful retreat.

func _ready() -> void: # Connect event completion and prepare session-local scheduling.
    _rng.randomize() # Vary encounters between play sessions.
    _session_seed = _rng.randi() # Keep event loot identities distinct from older sessions.
    _sampler = RadiantSpawnSampler.new(_terrain) # Prepare reusable spawn validation resources.
    _dialogue.encounter_resolved.connect(_resolved) # Apply consent outcomes after the conversation releases player input.
    _remaining = _rng.randf_range(60.0, 120.0) # Give fresh gameplay time before its first unsolicited encounter.

func _process(delta: float) -> void: # Update event state at a bounded cadence.
    _elapsed += delta # Retain elapsed scheduling time between updates.
    if _elapsed < UPDATE_INTERVAL: # Avoid per-frame geography and proximity work.
        return # Keep ordinary actor physics responsible for movement.
    var elapsed: float = _elapsed # Preserve the actual time consumed by this director update.
    _elapsed = 0.0 # Restart the bounded scheduling interval.
    if _state == State.IDLE: # Schedule only when no encounter actor is retained.
        if not _available(): # Wait during menus, loading, interiors and unavailable gameplay.
            return # Preserve the encounter cooldown until gameplay resumes.
        _remaining = maxf(0.0, _remaining - elapsed) # Advance the cooldown only during eligible outdoor gameplay.
        if _remaining <= 0.0: # Attempt one rare rear placement when the deadline arrives.
            _try_spawn() # Keep candidate validation bounded to one proposal per deadline.
        return # Avoid active actor work during idle scheduling.
    if not is_instance_valid(_actor): # Handle external actor removal or scene teardown safely.
        _reset() # Release the event slot and schedule a later event.
        return # Avoid accessing a previously freed actor.
    _age += elapsed # Track approach and retirement lifetime without affecting the NPC's combat clock.
    var world: Vector3 = _terrain.local_to_world_position(_player.global_position) # Resolve the current participant position after any origin shift.
    var destination: Vector2 = Vector2(world.x, world.z) # Keep pursuit steering in absolute coordinates.
    var distance: float = _player.global_position.distance_to(_actor.global_position) # Resolve current interaction and retirement reach.
    if _actor.health.is_dead() or _state == State.FIGHTING: # Leave battle motion and corpse interactions to ordinary actor systems.
        if distance > 80.0 and _offscreen(): # Retain nearby corpses for loot and avoid visible actor removal.
            _retire() # Release a departed event only after it is safely behind the camera.
        return # Do not overwrite combat targets or revive dead actors.
    if _state == State.TALKING: # Let the conversation controller own the speaker until a decision or cancellation.
        return # Avoid route changes while the event menu is active.
    if _state == State.APPROACHING: # Follow the player using ordinary NPC running and collision.
        if _age > APPROACH_TIMEOUT or distance > 120.0 or _actor.is_in_combat(): # Stop unsuccessful pursuits and interrupted invitations.
            _state = State.LEAVING # Convert the encounter into a peaceful departure unless ordinary combat has started.
        elif not _available(): # Wait rather than interrupt another menu or follow the player into an interior.
            _actor.set_encounter_destination(Vector2(_actor.world_position.x, _actor.world_position.z)) # Hold the actor at its current grounded position.
            return # Resume approaching when outdoor gameplay becomes available.
        elif distance <= 2.8 and _actor.combat.line_of_sight_to(_player): # Require actual arrival and an unobstructed participant before speaking.
            if _dialogue.open_encounter(_actor, RadiantEventPhrases.BATTLE_CHALLENGE): # Reuse ordinary input, range and actor eligibility checks.
                _state = State.TALKING # Wait for explicit player acceptance or refusal.
            return # Keep a rejected opening from immediately mutating NPC hostility.
        else: # Continue chasing the participant's latest ground position.
            _actor.set_encounter_destination(destination) # Update the actor's run destination without teleporting it.
            return # Leave collision-backed movement to Villager physics.
    if _state == State.LEAVING: # Retreat after refusal, cancellation or an unsuccessful approach.
        _actor.set_encounter_destination(_departure) # Run back toward the originally validated spawn ground.
        if distance > 40.0 and _offscreen(): # Require both separation and invisibility before removal.
            _retire() # Release the actor without popping it out of view.

func _available() -> bool: # Centralize outdoor encounter readiness through public gameplay capabilities.
    return _terrain.get_loaded_chunk_count() > 0 and _player.can_receive_radiant_encounter(_terrain) and _dialogue.can_start_encounter() # Respect terrain startup and all existing input owners.

func _try_spawn() -> bool: # Attempt exactly one candidate before allocating or loading an NPC.
    if _state != State.IDLE or not _available(): # Revalidate the event slot and gameplay state at the spawn deadline.
        return false # Avoid duplicate or unavailable encounters.
    var point: Vector2 = _sampler.candidate(_player, _rng) # Propose one location behind the current camera.
    if not _sampler.valid(point, _player): # Reject unsafe or newly visible placement before actor creation.
        _attempts += 1 # Record the bounded failure count.
        _remaining = 30.0 if _attempts >= 6 else 5.0 # Spread retries instead of scanning terrain in one frame.
        if _attempts >= 6: # Finish an unsuccessful placement round.
            _attempts = 0 # Allow later outdoor gameplay to try a new bounded round.
        return false # Skip the event rather than forcing an invalid spawn.
    _sequence += 1 # Assign a distinct event identity before configuring the actor.
    var seed_value: int = hash("radiant:%d:%d" % [_session_seed, _sequence]) # Keep loot and relationships stable for this actor's lifetime.
    var route: Array[Vector2] = [point, point + Vector2.RIGHT] # Supply the minimum initial actor route before live steering begins.
    _actor = Villager.new() # Reuse ordinary humanoid models, combat, collisions and loot.
    _actor.name = "Radiant Challenger %d" % _sequence # Identify event actors clearly in the scene tree.
    _actor.configure(_terrain, {"route": route, "seed": seed_value, "model": _rng.randi_range(0, 2), "role": "radiant_challenger", "start": 0}) # Select a male human, female human or orc challenger.
    _actor.set_affection(AffectionState.NEUTRAL) # Keep every invitation peaceful until the player explicitly accepts.
    add_child(_actor) # Register the actor only after placement has passed all checks.
    _departure = point # Retain a checked retreat destination.
    _state = State.APPROACHING # Begin the event's visible running approach.
    _age = 0.0 # Start the bounded pursuit timer.
    _attempts = 0 # Clear successful placement retry bookkeeping.
    var world: Vector3 = _terrain.local_to_world_position(_player.global_position) # Resolve the first live pursuit destination.
    _actor.set_encounter_destination(Vector2(world.x, world.z)) # Start running immediately instead of waiting on a patrol waypoint.
    return true # Confirm that one safely hidden encounter actor was created.

func _resolved(npc: Villager, accepted: bool) -> void: # Transition only the actor currently owned by this director.
    if not is_instance_valid(_actor) or npc != _actor: # Ignore unrelated conversations and invalid actor callbacks.
        return # Preserve the current event state.
    _state = State.FIGHTING if accepted else State.LEAVING # Let accepted hostility enter ordinary combat and refusal trigger retreat.
    _age = 0.0 # Start the post-conversation lifetime after input has been released.

func _offscreen() -> bool: # Recheck current visibility before actor retirement.
    return RadiantSpawnSampler.is_offscreen(_player.get_view_camera(), _actor.global_position) # Never remove the actor while its bounds face the camera.

func _retire() -> void: # Release a safely departed radiant actor and restart the cooldown.
    _actor.queue_free() # Free the event subtree and its normal actor resources.
    _reset() # Release ownership before scheduling a later event.

func _reset() -> void: # Restore the single-event scheduler after completion or external actor removal.
    _actor = null # Drop the prior event actor reference.
    _state = State.IDLE # Reopen the event slot after its cooldown.
    _age = 0.0 # Clear the completed event lifetime.
    _remaining = _rng.randf_range(180.0, 300.0) # Space repeated unsolicited encounters during eligible gameplay.
