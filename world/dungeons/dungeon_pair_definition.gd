extends RefCounted # Stores one deterministic relationship between two overworld entrances and one shared dungeon interior.
class_name DungeonPairDefinition # Exposes strongly typed pair data to overworld streaming and dungeon transitions.

enum Endpoint { A, B } # Identifies which side of the paired dungeon connection a door represents.

var pair_id: int = 0 # Stores the stable numeric identity derived from the pair's infinite overworld region coordinate.
var region_coordinate: Vector2i = Vector2i.ZERO # Stores the deterministic infinite-region coordinate that owns this dungeon pair.
var dungeon_seed: int = 0 # Stores the deterministic seed used to reconstruct the exact same interior on every visit.
var endpoint_a_world_position: Vector3 = Vector3.ZERO # Stores exterior endpoint A in absolute procedural-overworld coordinates.
var endpoint_b_world_position: Vector3 = Vector3.ZERO # Stores exterior endpoint B in absolute procedural-overworld coordinates.
var endpoint_a_yaw: float = 0.0 # Stores endpoint A's deterministic overworld facing angle in radians.
var endpoint_b_yaw: float = 0.0 # Stores endpoint B's deterministic overworld facing angle in radians.

func get_world_position(endpoint: Endpoint) -> Vector3: # Returns the absolute overworld position associated with one endpoint.
    if endpoint == Endpoint.B: # Detects requests for the second side of the paired connection.
        return endpoint_b_world_position # Returns endpoint B's stable procedural-world position.
    return endpoint_a_world_position # Returns endpoint A for every other valid endpoint request.

func get_yaw(endpoint: Endpoint) -> float: # Returns the authored-facing angle associated with one exterior endpoint.
    if endpoint == Endpoint.B: # Detects requests for the second side of the pair.
        return endpoint_b_yaw # Returns endpoint B's deterministic orientation.
    return endpoint_a_yaw # Returns endpoint A's deterministic orientation.

func get_display_name(endpoint: Endpoint) -> String: # Builds a concise diagnostic label for one exterior or interior door.
    var endpoint_name: String = "B" if endpoint == Endpoint.B else "A" # Converts the stable endpoint enum into the player-facing side letter.
    return "DUNGEON [%d,%d] %s" % [region_coordinate.x, region_coordinate.y, endpoint_name] # Uses the owning infinite-region coordinate so streamed pairs remain identifiable without sequential numbering.
