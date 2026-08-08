extends RefCounted # Stores one generated dungeon as compact logical walkability data before any scene nodes or meshes are created.
class_name DungeonLayout # Exposes deterministic cell data to geometry, lighting, collision, and transition systems.

const EMPTY_CELL: int = 0 # Represents blocked space outside the generated dungeon floor plan.
const WALKABLE_CELL: int = 1 # Represents traversable dungeon floor used by rooms, corridors, and exits.

var width: int = 0 # Stores the horizontal cell count along the dungeon's local x axis.
var height: int = 0 # Stores the horizontal cell count along the dungeon's local z axis.
var door_a_cell: Vector2i = Vector2i.ZERO # Stores the logical cell occupied by interior endpoint A.
var door_b_cell: Vector2i = Vector2i.ZERO # Stores the logical cell occupied by interior endpoint B.
var _cells: PackedByteArray = PackedByteArray() # Stores one compact byte per logical dungeon cell without scene-tree overhead.
var _floor_cells: Array[Vector2i] = [] # Stores each unique walkable cell once for bounded geometry and decoration iteration.

func initialize(layout_width: int, layout_height: int) -> void: # Allocates an empty dungeon grid with validated dimensions.
    width = maxi(layout_width, 1) # Guarantees at least one horizontal cell even if malformed dimensions are supplied.
    height = maxi(layout_height, 1) # Guarantees at least one vertical grid row for safe indexing.
    _cells.resize(width * height) # Allocates one compact byte for every logical cell.
    _cells.fill(EMPTY_CELL) # Starts the complete layout as blocked space before the generator carves connected floor.
    _floor_cells.clear() # Clears any earlier generated floor list if this data object is intentionally reused.
    door_a_cell = Vector2i.ZERO # Resets endpoint A until the generator assigns its deterministic location.
    door_b_cell = Vector2i.ZERO # Resets endpoint B until the generator assigns its deterministic location.

func set_endpoints(endpoint_a: Vector2i, endpoint_b: Vector2i) -> void: # Stores the two mandatory cells linking this interior to its exterior door pair.
    door_a_cell = endpoint_a # Retains the logical position corresponding to exterior endpoint A.
    door_b_cell = endpoint_b # Retains the logical position corresponding to exterior endpoint B.
    set_walkable(door_a_cell) # Guarantees the first interior exit is connected to traversable floor data.
    set_walkable(door_b_cell) # Guarantees the second interior exit is connected to traversable floor data.

func is_in_bounds(cell: Vector2i) -> bool: # Reports whether one logical coordinate can be safely indexed inside this layout.
    return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height # Restricts access to the allocated rectangular grid.

func set_walkable(cell: Vector2i) -> void: # Carves one logical floor cell while preserving a unique iteration list.
    if not is_in_bounds(cell): # Rejects coordinates outside the allocated dungeon grid.
        return # Prevents malformed generation steps from indexing invalid packed-array memory.
    var cell_index: int = _get_cell_index(cell) # Converts the two-dimensional coordinate into the compact packed-array index.
    if _cells[cell_index] == WALKABLE_CELL: # Detects a room or corridor cell already carved by an earlier generation stage.
        return # Avoids duplicate entries in the floor-cell iteration list.
    _cells[cell_index] = WALKABLE_CELL # Marks the logical coordinate as traversable dungeon space.
    _floor_cells.append(cell) # Records the newly carved cell exactly once for later geometry and lighting passes.

func is_walkable(cell: Vector2i) -> bool: # Reports whether one logical coordinate belongs to the generated traversable dungeon.
    if not is_in_bounds(cell): # Treats every coordinate outside the allocated map as solid boundary space.
        return false # Allows geometry code to create perimeter walls without special edge checks.
    return _cells[_get_cell_index(cell)] == WALKABLE_CELL # Reads the compact cell state using the validated grid coordinate.

func get_floor_cell_count() -> int: # Reports how many unique traversable cells were carved into this dungeon.
    return _floor_cells.size() # Returns the bounded iteration count used by geometry and decoration generation.

func get_floor_cell_at(index: int) -> Vector2i: # Returns one stored walkable coordinate without allocating a duplicate floor array.
    if index < 0 or index >= _floor_cells.size(): # Rejects invalid callers defensively.
        return Vector2i(-1, -1) # Returns a guaranteed out-of-bounds sentinel instead of exposing invalid memory.
    return _floor_cells[index] # Returns the stable carved coordinate at the requested iteration index.

func _get_cell_index(cell: Vector2i) -> int: # Converts one in-bounds two-dimensional coordinate into packed row-major storage.
    return cell.y * width + cell.x # Places complete x rows consecutively for cache-friendly traversal.
