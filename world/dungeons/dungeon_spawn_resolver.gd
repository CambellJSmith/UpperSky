extends RefCounted # Resolves player landing positions directly from the exact physical dungeon door selected by a transition.
class_name DungeonSpawnResolver # Centralizes door-relative spawn math so interior and exterior travel cannot drift into separate coordinate conventions.

const DIRECTION_EPSILON_SQUARED: float = 0.000001 # Defines the minimum usable horizontal door-facing magnitude before a defensive fallback is required.

static func get_horizontal_front_direction(door: DungeonDoor) -> Vector3: # Returns the normalized horizontal direction extending straight out from the visible front of one exact door node.
    if door == null: # Detects a missing transition target before reading its transform.
        return Vector3.FORWARD # Uses Godot's conventional negative-z forward direction only as a defensive non-transition fallback.
    var direction: Vector3 = door.get_forward_direction() # Reads the physical door's transformed forward axis instead of reconstructing it independently from stored metadata.
    direction.y = 0.0 # Removes any accidental vertical component so player landing distance remains horizontal and predictable.
    if direction.length_squared() <= DIRECTION_EPSILON_SQUARED: # Detects a degenerate transform that cannot provide a stable front direction.
        return Vector3.FORWARD # Returns a stable fallback direction while allowing the caller's separate door-identity validation to remain authoritative.
    return direction.normalized() # Returns the exact normalized horizontal front direction represented by the selected physical door.

static func get_scene_position_in_front(door: DungeonDoor, distance: float, vertical_clearance: float) -> Vector3: # Places a player root immediately in front of a selected door in the current scene coordinate space.
    if door == null: # Detects a missing physical door defensively.
        return Vector3.ZERO # Returns a neutral value that callers never use after their mandatory door validation fails.
    var front_direction: Vector3 = get_horizontal_front_direction(door) # Resolves the selected door's exact transformed front axis once for this landing calculation.
    var safe_distance: float = maxf(distance, 0.0) # Prevents malformed configuration from placing the player through the portal onto its buried or opposite side.
    var safe_clearance: float = maxf(vertical_clearance, 0.0) # Prevents malformed configuration from intentionally burying the player below the door threshold.
    return door.global_position + front_direction * safe_distance + Vector3.UP * safe_clearance # Offsets from the physical door itself so A and B can never share an assumed axis or origin.

static func get_grounded_overworld_position_in_front(door: DungeonDoor, terrain: InfiniteTerrain, distance: float, vertical_clearance: float) -> Vector3: # Resolves a terrain-grounded scene position immediately outside one exact exterior door.
    if door == null or terrain == null: # Detects incomplete transition dependencies before sampling the infinite terrain field.
        return Vector3.ZERO # Returns a neutral value that callers never apply after mandatory dependency validation fails.
    var front_direction: Vector3 = get_horizontal_front_direction(door) # Reads the exact exterior portal's downhill-facing physical front direction.
    var safe_distance: float = maxf(distance, 0.0) # Keeps the landing point on the visible approach side rather than allowing a negative distance into the cliff tunnel.
    var door_world_position: Vector3 = terrain.local_to_world_position(door.global_position) # Converts the currently rebased physical doorway transform back into stable absolute procedural-world coordinates.
    var landing_horizontal: Vector2 = Vector2(door_world_position.x + front_direction.x * safe_distance, door_world_position.z + front_direction.z * safe_distance) # Moves outward from this exact doorway while retaining the world's stable horizontal coordinate system.
    var landing_height: float = terrain.get_height_at(landing_horizontal) # Samples ground at the player's actual landing point instead of reusing the potentially higher doorway-threshold elevation.
    var safe_clearance: float = maxf(vertical_clearance, 0.0) # Preserves a small non-negative gap between the player root and sampled ground collision.
    var landing_world_position: Vector3 = Vector3(landing_horizontal.x, landing_height + safe_clearance, landing_horizontal.y) # Builds the complete absolute terrain-backed landing position directly in front of the selected exterior door.
    return terrain.world_to_local_position(landing_world_position) # Converts the stable result back into the current floating-origin scene coordinate space used by the player body.

static func get_yaw_facing_front(door: DungeonDoor) -> float: # Returns the player yaw that faces in the same horizontal direction as the exact selected door's visible front.
    var front_direction: Vector3 = get_horizontal_front_direction(door) # Resolves the physical front axis through the same path used by landing position calculations.
    return atan2(-front_direction.x, -front_direction.z) # Converts Godot's negative-z-forward convention into the yaw that points the player directly away from the portal surface.
