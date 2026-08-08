extends RefCounted # Generates deterministic dungeon topology before any geometry, collision, lighting, or scene nodes are created.
class_name DungeonLayoutGenerator # Exposes a reusable seeded layout service to every paired dungeon instance.

const GRID_WIDTH: int = 31 # Defines the bounded east-west logical size of the initial single-level dungeon family.
const GRID_HEIGHT: int = 25 # Defines the bounded north-south logical size of the initial single-level dungeon family.
const EDGE_MARGIN: int = 2 # Keeps procedural branches away from the outer map edge except at the two authored exit sides.
const ROOM_ATTEMPTS: int = 9 # Adds several chambers to the mandatory traversal spine without making generation unbounded.
const BRANCH_ATTEMPTS: int = 18 # Adds optional side paths and natural loops around the guaranteed endpoint connection.
const MINIMUM_ROOM_SIZE: int = 3 # Keeps the smallest generated chamber visibly wider than a one-cell corridor.
const MAXIMUM_ROOM_SIZE: int = 7 # Caps room carving so individual chambers cannot consume most of the dungeon grid.
const MINIMUM_BRANCH_LENGTH: int = 4 # Ensures optional branches extend far enough to read as deliberate side routes.
const MAXIMUM_BRANCH_LENGTH: int = 11 # Bounds branch work and prevents long random walks from dominating the critical path.
const ROOM_AT_BRANCH_END_CHANCE: float = 0.42 # Gives a portion of side routes a destination chamber rather than ending as plain corridors.

var _rng: RandomNumberGenerator = RandomNumberGenerator.new() # Owns all pseudo-random choices so the supplied dungeon seed completely determines the result.

func generate(dungeon_seed: int) -> DungeonLayout: # Builds one complete connected logical dungeon from a stable deterministic seed.
    _rng.seed = dungeon_seed # Resets the local generator so revisiting the same dungeon reconstructs identical topology.
    var layout: DungeonLayout = DungeonLayout.new() # Creates lightweight logical storage independently of rendered scene state.
    layout.initialize(GRID_WIDTH, GRID_HEIGHT) # Allocates the fixed-size single-level dungeon grid.
    var door_a: Vector2i = Vector2i(1, _rng.randi_range(4, GRID_HEIGHT - 5)) # Places endpoint A just inside the western boundary at a deterministic vertical position.
    var door_b: Vector2i = Vector2i(GRID_WIDTH - 2, _rng.randi_range(4, GRID_HEIGHT - 5)) # Places endpoint B just inside the eastern boundary at an independently seeded position.
    layout.set_endpoints(door_a, door_b) # Records and immediately carves both mandatory paired-door cells.
    var critical_path: Array[Vector2i] = [] # Records the guaranteed A-to-B route so later room generation can remain anchored to connected floor.
    _carve_critical_path(layout, door_a, door_b, critical_path) # Creates the dungeon spine before any optional procedural structure is allowed.
    _carve_spine_rooms(layout, critical_path) # Expands selected spine locations into deterministic rectangular chambers.
    _carve_branches(layout) # Adds seeded side routes, dead ends, chambers, and incidental loops from already connected floor.
    return layout # Returns topology that is guaranteed to contain both endpoints in one connected traversable component.

func _carve_critical_path(layout: DungeonLayout, door_a: Vector2i, door_b: Vector2i, critical_path: Array[Vector2i]) -> void: # Creates a connected meandering route between the two paired interior doors.
    var current: Vector2i = door_a # Begins traversal exactly at the interior cell corresponding to exterior endpoint A.
    _carve_and_record(layout, current, critical_path) # Records the initial endpoint as the first critical-path cell.
    while current.x < door_b.x: # Advances monotonically eastward so the path can never fail to eventually reach endpoint B.
        if current.y != door_b.y and _rng.randf() < 0.58: # Periodically changes vertical position so the critical route does not become one straight hallway.
            var toward_target: int = 1 if door_b.y > current.y else -1 # Chooses the vertical direction that moves the route toward endpoint B's row.
            var vertical_step: int = toward_target # Defaults each vertical move to eventual progress toward the required exit.
            if _rng.randf() < 0.22: # Occasionally introduces a short deterministic detour away from the direct route.
                vertical_step = -toward_target # Reverses the vertical step while eastward progress still guarantees termination.
            var candidate_y: int = clampi(current.y + vertical_step, EDGE_MARGIN, GRID_HEIGHT - 1 - EDGE_MARGIN) # Keeps the detour inside safe generation margins.
            if candidate_y != current.y: # Detects a vertical movement that was not removed by boundary clamping.
                current.y = candidate_y # Applies the deterministic vertical meander to the current logical cell.
                _carve_and_record(layout, current, critical_path) # Connects and records the vertical segment before continuing east.
        current.x += 1 # Advances one guaranteed cell toward endpoint B along the dungeon's principal axis.
        _carve_and_record(layout, current, critical_path) # Carves the eastward segment so every recorded critical cell remains four-neighbour connected.
    while current.y != door_b.y: # Resolves any remaining row difference after reaching endpoint B's x coordinate.
        current.y += 1 if door_b.y > current.y else -1 # Moves one vertical cell at a time toward the exact endpoint row.
        _carve_and_record(layout, current, critical_path) # Carves each final connecting step to preserve continuous traversal.
    layout.set_walkable(door_b) # Reasserts endpoint B as floor in case future dimension changes alter the final traversal loop.

func _carve_spine_rooms(layout: DungeonLayout, critical_path: Array[Vector2i]) -> void: # Expands deterministic locations along the guaranteed route into connected chambers.
    if critical_path.is_empty(): # Handles malformed future generator changes that somehow fail to record the mandatory path.
        return # Leaves the already carved endpoint data untouched instead of indexing an empty path array.
    for _room_attempt: int in range(ROOM_ATTEMPTS): # Performs a bounded number of chamber placements for predictable generation cost.
        var path_index: int = _rng.randi_range(0, critical_path.size() - 1) # Selects a seeded existing spine cell as the room anchor.
        var room_centre: Vector2i = critical_path[path_index] # Uses a connected floor cell so every room automatically joins the traversable component.
        _carve_room(layout, room_centre) # Expands the anchor into a deterministic rectangular chamber.

func _carve_branches(layout: DungeonLayout) -> void: # Adds optional connected side structure without risking isolated rooms or broken endpoint traversal.
    for _branch_attempt: int in range(BRANCH_ATTEMPTS): # Performs a fixed number of branch attempts for deterministic bounded work.
        if layout.get_floor_cell_count() <= 0: # Defensively handles an impossible empty layout before selecting a connected branch origin.
            return # Stops optional generation rather than requesting an invalid floor-cell index.
        var origin_index: int = _rng.randi_range(0, layout.get_floor_cell_count() - 1) # Selects a deterministic already connected floor coordinate.
        var current: Vector2i = layout.get_floor_cell_at(origin_index) # Begins the side route from the existing traversable component.
        var branch_length: int = _rng.randi_range(MINIMUM_BRANCH_LENGTH, MAXIMUM_BRANCH_LENGTH) # Chooses the seeded number of random-walk steps for this branch.
        var previous_direction: Vector2i = Vector2i.ZERO # Tracks the last step so branches have some directional persistence rather than pure visual noise.
        for _step: int in range(branch_length): # Advances the branch one bounded cardinal cell at a time.
            var direction: Vector2i = _choose_branch_direction(previous_direction) # Chooses a deterministic cardinal step with mild continuation bias.
            var candidate: Vector2i = current + direction # Builds the next logical coordinate before applying safe-map constraints.
            if candidate.x < EDGE_MARGIN or candidate.x > GRID_WIDTH - 1 - EDGE_MARGIN or candidate.y < EDGE_MARGIN or candidate.y > GRID_HEIGHT - 1 - EDGE_MARGIN: # Detects a step that would crowd the exterior boundary.
                direction = -direction # Reflects the branch inward rather than abandoning deterministic branch length.
                candidate = current + direction # Rebuilds the candidate after reflecting away from the map edge.
            if not layout.is_in_bounds(candidate): # Defensively rejects any coordinate still invalid after the bounded reflection.
                continue # Skips only this malformed step while preserving the remainder of the branch attempt.
            layout.set_walkable(candidate) # Carves the side-route cell, automatically creating loops if it intersects existing floor.
            current = candidate # Advances the branch head to the newly carved coordinate.
            previous_direction = direction # Retains the accepted direction for the next persistence-biased choice.
        if _rng.randf() < ROOM_AT_BRANCH_END_CHANCE: # Selects a deterministic subset of branches to terminate in a destination room.
            _carve_room(layout, current) # Expands the connected branch endpoint into a small chamber.

func _choose_branch_direction(previous_direction: Vector2i) -> Vector2i: # Chooses one cardinal random-walk step while avoiding excessive zig-zagging.
    if previous_direction != Vector2i.ZERO and _rng.randf() < 0.46: # Gives nearly half of steps a chance to continue in the current direction.
        return previous_direction # Produces readable short corridors between turns instead of one-cell visual noise.
    var direction_index: int = _rng.randi_range(0, 3) # Selects one of the four cardinal grid directions from the local deterministic generator.
    match direction_index: # Converts the seeded integer into one strongly defined cardinal vector.
        0: # Handles the positive x direction.
            return Vector2i.RIGHT # Moves one logical cell east.
        1: # Handles the negative x direction.
            return Vector2i.LEFT # Moves one logical cell west.
        2: # Handles the positive z-grid direction.
            return Vector2i.DOWN # Moves one logical cell south in the dungeon map.
        _: # Handles the remaining negative z-grid direction.
            return Vector2i.UP # Moves one logical cell north in the dungeon map.

func _carve_room(layout: DungeonLayout, centre: Vector2i) -> void: # Carves one bounded rectangular room around an already connected floor coordinate.
    var room_width: int = _rng.randi_range(MINIMUM_ROOM_SIZE, MAXIMUM_ROOM_SIZE) # Chooses the deterministic east-west room span.
    var room_height: int = _rng.randi_range(MINIMUM_ROOM_SIZE, MAXIMUM_ROOM_SIZE) # Chooses the deterministic north-south room span independently.
    if room_width % 2 == 0: # Detects an even room width that would bias the selected centre between cells.
        room_width -= 1 # Converts the width to an odd span while preserving the configured upper bound.
    if room_height % 2 == 0: # Detects an even room height for the same centring reason.
        room_height -= 1 # Converts the height to an odd span around the connected anchor cell.
    var half_width: int = room_width / 2 # Calculates the integer horizontal radius around the selected room centre.
    var half_height: int = room_height / 2 # Calculates the integer vertical-grid radius around the selected room centre.
    for offset_y: int in range(-half_height, half_height + 1): # Visits every intended room row around the connected centre.
        for offset_x: int in range(-half_width, half_width + 1): # Visits every intended room column within the current row.
            var cell: Vector2i = centre + Vector2i(offset_x, offset_y) # Converts room-local offsets into a dungeon-grid coordinate.
            if cell.x < 1 or cell.x >= GRID_WIDTH - 1 or cell.y < 1 or cell.y >= GRID_HEIGHT - 1: # Preserves a solid outer boundary around procedural chambers.
                continue # Skips only cells that would carve directly through the dungeon's enclosing shell.
            layout.set_walkable(cell) # Carves the room cell while the layout suppresses duplicates automatically.

func _carve_and_record(layout: DungeonLayout, cell: Vector2i, critical_path: Array[Vector2i]) -> void: # Carves a mandatory-route cell and records its ordered traversal position.
    layout.set_walkable(cell) # Marks the logical coordinate as traversable floor.
    if critical_path.is_empty() or critical_path[critical_path.size() - 1] != cell: # Avoids consecutive duplicate entries when vertical and horizontal stages meet.
        critical_path.append(cell) # Retains the ordered critical route for connected room placement.
