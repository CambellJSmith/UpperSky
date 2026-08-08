extends CliffDungeonSystem # Retains cliff-only dungeon streaming while making every transition resolve from the exact corresponding physical door node.
class_name PreciseCliffDungeonSystem # Exposes endpoint-verified A/B travel with door-relative player landing positions on both sides of each dungeon.

const INTERIOR_PLAYER_FRONT_DISTANCE: float = 1.55 # Places dungeon arrivals immediately inside the selected interior portal while keeping the player capsule clear of its boundary wall.
const INTERIOR_PLAYER_FLOOR_CLEARANCE: float = 0.08 # Preserves the same small player-root separation used by terrain-backed overworld spawning.

func _enter_dungeon(pair_id: int, endpoint: DungeonPairDefinition.Endpoint) -> bool: # Generates the selected dungeon and places the player in front of the exact matching interior A or B door.
    if _active_dungeon != null: # Rejects nested entry while another deterministic interior is already active.
        return false # Leaves the current world-space transition state untouched.
    var pair: DungeonPairDefinition = _find_pair(pair_id) # Resolves the streamed pair represented by the exterior door that the player actually interacted with.
    if pair == null: # Detects stale exterior interaction metadata that no longer maps to an active deterministic pair.
        return false # Refuses to guess a destination when the authoritative pair cannot be resolved.
    _active_pair = pair # Retains the exact pair so the later interior A/B exit can map back to the correct overworld endpoint.
    _active_dungeon = ProceduralDungeonWorld.new() # Creates the disposable deterministic interior for this exact pair.
    _active_dungeon.name = "ActiveDungeon_%d_%d" % [pair.region_coordinate.x, pair.region_coordinate.y] # Gives the active interior its existing stable region-coordinate diagnostic identity.
    _active_dungeon.position = DUNGEON_WORLD_ORIGIN # Keeps generated interior geometry isolated vertically from suspended overworld collision.
    _active_dungeon.build(pair.pair_id, pair.dungeon_seed, pair.region_coordinate) # Reconstructs the exact deterministic layout, collision, doors, lighting, and materials for this pair.
    add_child(_active_dungeon) # Installs the generated interior so its physical door global transforms become authoritative before calculating the player landing point.
    var arrival_door: DungeonDoor = _find_matching_interior_door(pair_id, endpoint) # Finds only the physical interior door whose pair identity and endpoint exactly match the exterior door used.
    if arrival_door == null: # Detects any generation or metadata mismatch that would make a safe corresponding landing impossible.
        _active_dungeon.queue_free() # Releases the invalid generated interior instead of placing the player near an assumed or opposite doorway.
        _active_dungeon = null # Clears active dungeon ownership after rejecting the transition.
        _active_pair = null # Clears pair transition state because entry did not complete.
        return false # Fails closed so endpoint A can never silently become endpoint B or vice versa.
    var arrival_position: Vector3 = DungeonSpawnResolver.get_scene_position_in_front(arrival_door, INTERIOR_PLAYER_FRONT_DISTANCE, INTERIOR_PLAYER_FLOOR_CLEARANCE) # Derives the landing point from the exact generated door transform instead of hard-coded east/west axis assumptions.
    var arrival_yaw: float = DungeonSpawnResolver.get_yaw_facing_front(arrival_door) # Faces the player directly away from the selected interior portal and into its traversable dungeon side.
    _set_overworld_active(false) # Suspends terrain, vegetation, decorations, exterior doors, and other overworld-only systems before moving the player into interior coordinates.
    _player.initialize_environment(null) # Detaches terrain-driven water state while the player occupies the isolated dungeon world space.
    _player.set_fly_mode_enabled(false) # Restores normal grounded collision behavior before the interior placement is applied.
    _player.velocity = Vector3.ZERO # Prevents overworld momentum from carrying the player away from the exact door-relative arrival point.
    _camera.environment = _active_dungeon.get_environment() # Activates the generated dungeon environment for the first-person camera.
    _player.global_position = arrival_position # Places the player immediately in front of the exact corresponding interior A or B door.
    _player.rotation.y = arrival_yaw # Aligns the player's horizontal facing with the same exact door transform used for position calculation.
    return true # Reports successful endpoint-verified dungeon entry.

func _exit_dungeon(pair_id: int, endpoint: DungeonPairDefinition.Endpoint) -> bool: # Returns the player to a terrain-grounded point immediately in front of the exact corresponding exterior A or B door.
    if _active_dungeon == null or _active_pair == null: # Rejects exit interaction when no deterministic interior transition is active.
        return false # Leaves world state unchanged rather than inferring a missing pair.
    if pair_id != _active_pair.pair_id: # Detects an interior door whose pair identity does not match the currently active dungeon.
        return false # Prevents cross-pair teleportation from malformed or stale generated metadata.
    var exterior_door: DungeonDoor = _find_matching_exterior_door(pair_id, endpoint) # Resolves the exact streamed overworld door with matching pair ID, endpoint letter, and exterior role.
    if exterior_door == null: # Detects a missing or mismatched physical return portal.
        return false # Keeps the player safely inside the dungeon rather than falling back to a coordinate that could represent the wrong side.
    var return_position: Vector3 = DungeonSpawnResolver.get_grounded_overworld_position_in_front(exterior_door, _terrain, EXIT_FORWARD_DISTANCE, EXIT_PLAYER_CLEARANCE) # Places the player on sampled ground directly in front of this exact exterior portal, including downhill terrain-height changes.
    var return_yaw: float = DungeonSpawnResolver.get_yaw_facing_front(exterior_door) # Faces the player outward from the exact selected exterior doorway using its physical transform.
    _player.set_physics_process(false) # Holds gravity and movement while distant overworld terrain collision streams around the exact return point.
    _camera.environment = null # Removes the dungeon-specific camera override before restoring the overworld environment.
    _set_overworld_active(true) # Restores terrain streaming, vegetation, decorations, exterior portal visuals, and other overworld-only systems.
    _player.initialize_environment(_terrain) # Reconnects swimming and terrain-aware player state to the authoritative infinite terrain service.
    _player.velocity = Vector3.ZERO # Clears interior motion before applying the precise exterior landing transform.
    _player.global_position = return_position # Places the player immediately in front of the exact exterior endpoint corresponding to the interior door used.
    _player.rotation.y = return_yaw # Faces the player away from that same physical portal so the returned-through door is directly behind them.
    _exit_collision_settle_frames_remaining = EXIT_COLLISION_SETTLE_FRAMES # Preserves the established collision-streaming grace period for potentially multi-kilometre A/B travel.
    _active_dungeon.queue_free() # Releases the generated interior after the verified exterior landing transform has been resolved.
    _active_dungeon = null # Clears active interior ownership so another dungeon can be entered later.
    _active_pair = null # Clears the completed pair transition state while deterministic streamed metadata remains available.
    _last_stream_cell = INVALID_STREAM_CELL # Forces the next safe overworld frame to refresh dungeon entrance streaming around the possibly distant return endpoint.
    return true # Reports successful endpoint-verified return travel.

func _find_matching_interior_door(pair_id: int, endpoint: DungeonPairDefinition.Endpoint) -> DungeonDoor: # Finds the one generated interior door that exactly matches a requested pair and A/B endpoint.
    if _active_dungeon == null: # Detects calls before a generated interior exists.
        return null # Refuses to search an absent world space.
    for child: Node in _active_dungeon.get_children(): # Examines generated direct children, including the two interior DungeonDoor nodes.
        if not (child is DungeonDoor): # Skips procedural geometry, collision, fixtures, lights, and other non-door children.
            continue # Continues until reaching a physical transition door.
        var door: DungeonDoor = child as DungeonDoor # Converts the validated child to the strongly typed dungeon-door contract.
        if door.is_exterior(): # Rejects any unexpected exterior-role door that should never exist inside the generated interior.
            continue # Keeps interior and exterior transition roles strictly separated.
        if door.get_pair_id() != pair_id: # Rejects a generated door belonging to any pair other than the exact interaction source.
            continue # Prevents cross-pair destination ambiguity.
        if door.get_endpoint() != endpoint: # Rejects the opposite A/B side even though it belongs to the same dungeon pair.
            continue # Guarantees exterior A arrives at interior A and exterior B arrives at interior B.
        return door # Returns only the exact corresponding physical interior door.
    return null # Reports that no safe exact interior endpoint exists instead of guessing from coordinates.

func _find_matching_exterior_door(pair_id: int, endpoint: DungeonPairDefinition.Endpoint) -> DungeonDoor: # Finds the one streamed exterior door that exactly matches the active pair and selected interior A/B exit.
    if not _streamed_pair_roots.has(pair_id): # Detects a return pair whose physical overworld door owner is no longer retained.
        return null # Refuses to infer a portal location when the exact physical pair is unavailable.
    var pair_root: Node3D = _streamed_pair_roots[pair_id] # Retrieves the streamed owner containing both physical exterior endpoints for this exact pair.
    if pair_root == null: # Detects a stale dictionary reference defensively.
        return null # Prevents transition math from running against an invalid scene node.
    for child: Node in pair_root.get_children(): # Examines the pair's generated exterior door children without relying on names or child order.
        if not (child is DungeonDoor): # Skips any future non-door decoration that may be added under the pair root.
            continue # Continues until reaching a physical transition door.
        var door: DungeonDoor = child as DungeonDoor # Converts the validated child to the strongly typed dungeon-door contract.
        if not door.is_exterior(): # Rejects any incorrectly parented interior-role door.
            continue # Keeps overworld return routing bound exclusively to exterior portals.
        if door.get_pair_id() != pair_id: # Rejects any child whose immutable pair identity does not match the active dungeon.
            continue # Prevents cross-pair return travel even if scene-tree structure becomes malformed later.
        if door.get_endpoint() != endpoint: # Rejects the opposite endpoint letter within the otherwise correct pair.
            continue # Guarantees interior A exits at exterior A and interior B exits at exterior B.
        return door # Returns only the exact corresponding physical exterior doorway.
    return null # Reports failure when no exact endpoint exists rather than falling back to the opposite door or stored position.
