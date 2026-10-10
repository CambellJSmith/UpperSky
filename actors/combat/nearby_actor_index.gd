extends RefCounted # Share one spatial snapshot between combat queries.
class_name NearbyActorIndex # Supply nearby targets without repeated whole-group scans.

const CELL_SIZE: float = 24.0 # Match ordinary combat perception scale.
static var _tree: WeakRef # Track the owning scene without retaining it.
static var _frame: int = -1 # Rebuild once per physics frame.
static var _cells: Dictionary = {} # Bucket actors by their local world position.

static func nearby(tree: SceneTree, point: Vector3, radius: float) -> Array[Node3D]: # Return only nearby target candidates.
    if _tree == null or _tree.get_ref() != tree or _frame != Engine.get_physics_frames(): # Refresh stale scene or frame snapshots.
        _tree = weakref(tree) # Avoid keeping a removed tree alive.
        _frame = Engine.get_physics_frames() # Record the shared snapshot frame.
        _cells.clear() # Release the preceding frame's actor references.
        var actors: Array[Node] = tree.get_nodes_in_group("npc") # Read the NPC group only once.
        actors.append_array(tree.get_nodes_in_group("player")) # Include player targets in the same index.
        for actor: Node in actors: # Insert current spatial actors.
            if not actor is Node3D or not actor.is_inside_tree(): # Exclude invalid spatial ownership.
                continue # Leave unavailable actors outside the snapshot.
            var cell: Vector3i = Vector3i((actor.global_position / CELL_SIZE).floor()) # Resolve the local spatial bucket.
            if not _cells.has(cell): # Allocate populated buckets only.
                _cells[cell] = [] # Prepare the actor list.
            _cells[cell].append(actor) # Insert the actor into its current bucket.
    var result: Array[Node3D] = [] # Collect only nearby spatial candidates.
    var first: Vector3i = Vector3i(((point - Vector3.ONE * radius) / CELL_SIZE).floor()) # Resolve the first intersecting bucket.
    var last: Vector3i = Vector3i(((point + Vector3.ONE * radius) / CELL_SIZE).floor()) # Resolve the last intersecting bucket.
    var radius_squared: float = radius * radius # Avoid square roots during rejection.
    for z: int in range(first.z, last.z + 1): # Visit nearby bucket depths.
        for y: int in range(first.y, last.y + 1): # Visit nearby bucket heights.
            for x: int in range(first.x, last.x + 1): # Visit nearby bucket columns.
                for actor: Node3D in _cells.get(Vector3i(x, y, z), []): # Inspect only populated neighbour buckets.
                    if is_instance_valid(actor) and actor.is_inside_tree() and point.distance_squared_to(actor.global_position) <= radius_squared: # Reject stale and distant actors before relationship checks.
                        result.append(actor) # Return a spatially eligible target candidate.
    return result # Supply the nearby snapshot.
