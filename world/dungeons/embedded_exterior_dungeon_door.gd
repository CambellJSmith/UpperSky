extends DungeonDoor # Specializes only overworld dungeon entrances so every visible stone penetrates deeply into the supporting terrain mass.
class_name EmbeddedExteriorDungeonDoor # Exposes deep hillside masonry and a separate low-complexity exterior collision shell without changing interior dungeon exits.

const DEEP_BRICK_DEPTH_MINIMUM: float = 3.75 # Guarantees every exterior retaining stone reaches several metres behind the visible portal face into the hill.
const DEEP_BRICK_DEPTH_MAXIMUM: float = 4.45 # Allows deterministic depth variation while staying within the cliff mass already validated behind each entrance.
const EXTERIOR_CORE_DEPTH: float = 4.10 # Extends the jambs, lintel, and footing stones backward instead of leaving the central frame as a shallow facade.
const EXTERIOR_STONE_FRONT_REVEAL: float = 0.18 # Keeps only a small stone reveal in front of the portal plane while the majority of every block remains buried uphill.
const EXTERIOR_COLLISION_DEPTH: float = 3.70 # Gives the simplified collision shell enough rear depth to cover the visible masonry volume without following individual bricks.
const EXTERIOR_COLLISION_FRONT_REVEAL: float = 0.14 # Keeps coarse collision slightly forward of the portal plane so the player cannot clip through visible retaining stone.
const PORTAL_BACKSTOP_DEPTH: float = 0.24 # Uses one thin primitive behind the transition surface to stop the player walking physically through the portal into terrain.
const PORTAL_BACKSTOP_Z: float = 0.18 # Places the portal blocker just behind the visible transition plane so interaction remains unobstructed from the approach side.
const WORLD_COLLISION_LAYER: int = 1 # Matches the ordinary solid-world layer already used by terrain and dungeon architecture for first-person movement collision.

func _build_frame_geometry() -> void: # Rebuilds the shared core frame with the same visible front edge while extending every exterior frame stone several metres into the hill.
    var side_x: float = OPENING_WIDTH * 0.5 + FRAME_BLOCK_THICKNESS * 0.5 # Calculates the horizontal centre of each vertical jamb around the clear opening.
    var jamb_height: float = OPENING_HEIGHT + FRAME_BLOCK_THICKNESS # Extends jambs high enough to support the generated lintel visually.
    var frame_z: float = EXTERIOR_CORE_DEPTH * 0.5 - FRAME_DEPTH * 0.5 # Preserves the original front face while moving the additional depth entirely into local positive z, the uphill direction.
    var original_foot_depth: float = FRAME_DEPTH * 1.35 # Reconstructs the previous visible footing depth so its front face remains visually unchanged.
    var foot_z: float = EXTERIOR_CORE_DEPTH * 0.5 - original_foot_depth * 0.5 # Pushes the extra footing volume backward into terrain rather than toward the player approach.
    _add_box_visual("LeftJamb", Vector3(FRAME_BLOCK_THICKNESS, jamb_height, EXTERIOR_CORE_DEPTH), Vector3(-side_x, jamb_height * 0.5, frame_z), FRAME_COLOUR) # Builds the left core stone as a deep structural return into the hillside.
    _add_box_visual("RightJamb", Vector3(FRAME_BLOCK_THICKNESS, jamb_height, EXTERIOR_CORE_DEPTH), Vector3(side_x, jamb_height * 0.5, frame_z), FRAME_COLOUR.lightened(0.035)) # Builds the right core stone with the same guaranteed rear penetration.
    _add_box_visual("Lintel", Vector3(OPENING_WIDTH + FRAME_BLOCK_THICKNESS * 2.0, FRAME_BLOCK_THICKNESS, EXTERIOR_CORE_DEPTH), Vector3(0.0, OPENING_HEIGHT + FRAME_BLOCK_THICKNESS * 0.5, frame_z), FRAME_COLOUR.darkened(0.025)) # Extends the central lintel backward under the terrain overburden instead of leaving a thin cap.
    _add_box_visual("LeftFoot", Vector3(FRAME_BLOCK_THICKNESS * 1.55, 0.24, EXTERIOR_CORE_DEPTH), Vector3(-side_x, 0.12, foot_z), FRAME_ACCENT_COLOUR) # Extends the left footing deep under the hillside while preserving its visible threshold edge.
    _add_box_visual("RightFoot", Vector3(FRAME_BLOCK_THICKNESS * 1.55, 0.24, EXTERIOR_CORE_DEPTH), Vector3(side_x, 0.12, foot_z), FRAME_ACCENT_COLOUR.lightened(0.025)) # Extends the right footing using the same rear-only depth rule.

func _build_exterior_masonry() -> void: # Builds all exterior retaining stones with guaranteed deep rear penetration, then adds one coarse collision shell independent from the visual blocks.
    var rng: RandomNumberGenerator = RandomNumberGenerator.new() # Creates local deterministic stone variation without consuming global randomness.
    rng.seed = _get_masonry_seed() # Reuses stable pair-and-endpoint identity so the deeper masonry remains identical after streaming reloads.
    _build_deep_tunnel_returns(rng) # Extends the hidden tunnel cheeks and roof beyond the visible portal into the same validated terrain mass.
    _build_deep_masonry_wing(-1, rng) # Builds the complete left retaining wall from individually varied but always deeply buried stones.
    _build_deep_masonry_wing(1, rng) # Builds the complete right retaining wall using the same rear-penetration contract.
    _build_deep_masonry_crown(rng) # Builds the over-door crown from stones whose rear faces all continue far into the hillside.
    _build_deep_masonry_foundation(rng) # Extends both foundation courses backward beneath the surrounding terrain instead of stopping near the facade.
    _build_low_poly_exterior_collision() # Adds a few primitive physics shapes rather than expensive per-brick collision geometry.

func _build_deep_tunnel_returns(rng: RandomNumberGenerator) -> void: # Builds continuous buried tunnel structure deep enough to remain behind every visible stone course.
    var return_depth: float = DEEP_BRICK_DEPTH_MAXIMUM # Uses the deepest supported masonry reach so exposed terrain gaps cannot reveal an empty rear cavity.
    var side_x: float = OPENING_WIDTH * 0.5 + TUNNEL_RETURN_WALL_THICKNESS * 0.5 # Places structural return walls immediately outside the clear portal opening.
    var return_z: float = return_depth * 0.5 - EXTERIOR_STONE_FRONT_REVEAL # Keeps a small front reveal while directing almost the entire tunnel-return volume uphill.
    var return_wall_height: float = OPENING_HEIGHT + FRAME_BLOCK_THICKNESS # Matches the buried return walls to the complete core portal envelope.
    _add_box_visual("BuriedTunnelLeft", Vector3(TUNNEL_RETURN_WALL_THICKNESS, return_wall_height, return_depth), Vector3(-side_x, return_wall_height * 0.5, return_z), _vary_stone_colour(MASONRY_BURIED_COLOUR, rng)) # Builds the left hidden tunnel cheek as one deep procedural stone mass.
    _add_box_visual("BuriedTunnelRight", Vector3(TUNNEL_RETURN_WALL_THICKNESS, return_wall_height, return_depth), Vector3(side_x, return_wall_height * 0.5, return_z), _vary_stone_colour(MASONRY_BURIED_COLOUR, rng)) # Builds the matching right hidden tunnel cheek into the terrain.
    _add_box_visual("BuriedTunnelCeiling", Vector3(OPENING_WIDTH + TUNNEL_RETURN_WALL_THICKNESS * 2.0, TUNNEL_RETURN_WALL_THICKNESS, return_depth), Vector3(0.0, OPENING_HEIGHT + TUNNEL_RETURN_WALL_THICKNESS * 0.5, return_z), _vary_stone_colour(MASONRY_BURIED_COLOUR, rng)) # Builds the buried roof deeply beneath the hill above the portal.

func _build_deep_masonry_wing(side: int, rng: RandomNumberGenerator) -> void: # Builds one retaining-wall shoulder while guaranteeing that every individual visual block reaches far behind the terrain surface.
    var wing_start: float = OPENING_WIDTH * 0.5 + FRAME_BLOCK_THICKNESS + MASONRY_BLOCK_WIDTH * 0.36 # Starts the first wing column overlapping the core frame so no facade seam can open beside the portal.
    for course: int in range(MASONRY_WING_COURSES): # Builds vertical courses from the partly buried threshold to above the door opening.
        var stagger: float = MASONRY_COLUMN_STEP * 0.5 if course % 2 == 1 else 0.0 # Offsets alternate courses to preserve the existing interlocking procedural brick pattern.
        for column: int in range(MASONRY_WING_COLUMNS): # Extends each course outward across the complete retaining-wall shoulder.
            var distance_from_centre: float = wing_start + float(column) * MASONRY_COLUMN_STEP + stagger # Calculates this block's horizontal centre before left/right mirroring.
            var local_x: float = float(side) * distance_from_centre # Mirrors the same deep masonry layout cleanly across the portal centre.
            var local_y: float = MASONRY_BLOCK_HEIGHT * 0.5 + float(course) * MASONRY_COURSE_STEP # Stacks the current block into its deterministic retaining-wall course.
            var block_width: float = MASONRY_BLOCK_WIDTH * rng.randf_range(0.90, 1.10) # Preserves restrained deterministic stone-width variation.
            var block_height: float = MASONRY_BLOCK_HEIGHT * rng.randf_range(0.92, 1.07) # Preserves slight irregularity between generated course stones.
            var block_depth: float = rng.randf_range(DEEP_BRICK_DEPTH_MINIMUM, DEEP_BRICK_DEPTH_MAXIMUM) # Guarantees every wing stone extends several metres into the cliff instead of stopping near the visible facade.
            var front_reveal: float = EXTERIOR_STONE_FRONT_REVEAL + rng.randf_range(-0.055, 0.055) # Varies only the small visible front projection while leaving the large buried rear depth intact.
            var local_z: float = block_depth * 0.5 - front_reveal # Derives centre depth from the requested front face so all extra block length goes uphill into terrain.
            var block_name: String = "MasonryWing_%d_%d_%d" % [side, course, column] # Gives the generated retaining stone a stable diagnostic identity.
            _add_box_visual(block_name, Vector3(block_width, block_height, block_depth), Vector3(local_x, local_y, local_z), _vary_stone_colour(MASONRY_COLOUR, rng)) # Installs the deeply embedded visual stone beneath the terrain-facing doorway transform.

func _build_deep_masonry_crown(rng: RandomNumberGenerator) -> void: # Builds upper retaining courses whose complete rear portions continue beneath the hill above the doorway.
    var crown_span: float = float(MASONRY_CROWN_COLUMNS - 1) * MASONRY_COLUMN_STEP # Measures the centre-to-centre span occupied by the broad crown above the entrance.
    for course: int in range(MASONRY_CROWN_COURSES): # Builds multiple interlocked upper layers across the portal and side shoulders.
        var stagger: float = MASONRY_COLUMN_STEP * 0.5 if course % 2 == 1 else 0.0 # Offsets alternate crown rows to avoid aligned vertical joints.
        for column: int in range(MASONRY_CROWN_COLUMNS): # Spans each upper row across the complete exterior construction.
            var local_x: float = -crown_span * 0.5 + float(column) * MASONRY_COLUMN_STEP + stagger # Calculates the horizontal centre for the current crown block.
            var local_y: float = OPENING_HEIGHT + FRAME_BLOCK_THICKNESS + MASONRY_BLOCK_HEIGHT * 0.5 + float(course) * MASONRY_COURSE_STEP # Places the block directly above and overlapping the deep central lintel.
            var block_width: float = MASONRY_BLOCK_WIDTH * rng.randf_range(0.92, 1.12) # Preserves deterministic width irregularity across the upper retaining courses.
            var block_height: float = MASONRY_BLOCK_HEIGHT * rng.randf_range(0.94, 1.08) # Preserves restrained vertical variation while keeping a readable crown silhouette.
            var block_depth: float = rng.randf_range(DEEP_BRICK_DEPTH_MINIMUM + 0.15, DEEP_BRICK_DEPTH_MAXIMUM) # Keeps crown stones at least as deeply buried as the side-wall blocks beneath them.
            var front_reveal: float = EXTERIOR_STONE_FRONT_REVEAL + rng.randf_range(-0.045, 0.045) # Varies the visible front edge without reducing required rear penetration.
            var local_z: float = block_depth * 0.5 - front_reveal # Pushes the additional crown depth entirely beneath the terrain overburden.
            var block_name: String = "MasonryCrown_%d_%d" % [course, column] # Assigns a stable generated name to this upper retaining stone.
            _add_box_visual(block_name, Vector3(block_width, block_height, block_depth), Vector3(local_x, local_y, local_z), _vary_stone_colour(MASONRY_COLOUR, rng)) # Adds the deep crown stone with the existing deterministic weathered colour family.

func _build_deep_masonry_foundation(rng: RandomNumberGenerator) -> void: # Builds threshold and rear foundation courses that continue under the hillside instead of ending immediately behind the visible entrance.
    var foundation_width: float = OPENING_WIDTH + float(MASONRY_WING_COLUMNS) * MASONRY_COLUMN_STEP * 2.0 + 1.2 # Extends the rear foundation beneath the complete frame and both retaining shoulders.
    var rear_depth: float = DEEP_BRICK_DEPTH_MAXIMUM # Uses maximum penetration for the broad buried rear foundation supporting the visual retaining wall.
    var rear_z: float = rear_depth * 0.5 - 0.10 # Leaves only a small forward reveal while burying almost the entire rear foundation into terrain.
    var front_depth: float = DEEP_BRICK_DEPTH_MINIMUM # Keeps even the more visible threshold course several metres deep beneath the hillside.
    var front_z: float = front_depth * 0.5 - 0.22 # Preserves a slightly stronger visible threshold projection while still extending far behind the portal.
    _add_box_visual("BuriedFoundationRear", Vector3(foundation_width, 0.30, rear_depth), Vector3(0.0, 0.02, rear_z), _vary_stone_colour(MASONRY_BURIED_COLOUR, rng)) # Builds the broad rear foundation as one deeply buried procedural stone course.
    _add_box_visual("BuriedFoundationFront", Vector3(OPENING_WIDTH + 1.55, 0.22, front_depth), Vector3(0.0, 0.07, front_z), _vary_stone_colour(FRAME_ACCENT_COLOUR, rng)) # Builds the visible threshold course with the same guaranteed rear penetration rule.

func _build_low_poly_exterior_collision() -> void: # Creates a four-shape primitive collision shell matching the exterior mass without generating collision for each visual stone.
    var collision_body: StaticBody3D = StaticBody3D.new() # Creates one static physics owner for the complete exterior entrance structure.
    collision_body.name = "ExteriorLowPolyCollision" # Gives the coarse collision shell a stable remote-scene-tree name for debugging and profiling.
    collision_body.collision_layer = WORLD_COLLISION_LAYER # Places the exterior masonry on the ordinary solid-world layer used by the player movement mask.
    collision_body.collision_mask = WORLD_COLLISION_LAYER # Keeps standard world-body collision behavior symmetric with existing terrain and architecture.
    add_child(collision_body) # Parents the physics owner beneath the doorway so cliff-derived yaw and floating-origin movement apply automatically.
    var outer_half_width: float = _get_exterior_outer_half_width() # Calculates the maximum horizontal visual reach including staggered outer wing stones.
    var side_width: float = outer_half_width - OPENING_WIDTH * 0.5 # Measures the solid retaining mass on either side while leaving the portal opening clear.
    var collision_z: float = EXTERIOR_COLLISION_DEPTH * 0.5 - EXTERIOR_COLLISION_FRONT_REVEAL # Keeps the shell front near the facade while pushing most collision volume into the hill.
    _add_box_collision(collision_body, "LeftRetainingCollision", Vector3(side_width, OPENING_HEIGHT, EXTERIOR_COLLISION_DEPTH), Vector3(-(OPENING_WIDTH * 0.5 + side_width * 0.5), OPENING_HEIGHT * 0.5, collision_z)) # Covers the complete left masonry shoulder with one primitive box.
    _add_box_collision(collision_body, "RightRetainingCollision", Vector3(side_width, OPENING_HEIGHT, EXTERIOR_COLLISION_DEPTH), Vector3(OPENING_WIDTH * 0.5 + side_width * 0.5, OPENING_HEIGHT * 0.5, collision_z)) # Covers the complete right masonry shoulder with one primitive box.
    var crown_height: float = FRAME_BLOCK_THICKNESS + MASONRY_BLOCK_HEIGHT + float(MASONRY_CROWN_COURSES - 1) * MASONRY_COURSE_STEP + MASONRY_BLOCK_HEIGHT * 0.35 # Covers the complete visual over-door crown without reproducing individual course boundaries.
    _add_box_collision(collision_body, "CrownCollision", Vector3(outer_half_width * 2.0, crown_height, EXTERIOR_COLLISION_DEPTH), Vector3(0.0, OPENING_HEIGHT + crown_height * 0.5, collision_z)) # Covers lintel and upper retaining masonry with one broad primitive box.
    _add_box_collision(collision_body, "PortalBackstopCollision", Vector3(OPENING_WIDTH, OPENING_HEIGHT, PORTAL_BACKSTOP_DEPTH), Vector3(0.0, OPENING_HEIGHT * 0.5, PORTAL_BACKSTOP_Z)) # Prevents physical walk-through at the portal opening while leaving the dedicated interaction Area3D unaffected.

func _get_exterior_outer_half_width() -> float: # Calculates the largest possible retaining-wall half-span so coarse collision never ends inside a visible outer brick.
    var wing_start: float = OPENING_WIDTH * 0.5 + FRAME_BLOCK_THICKNESS + MASONRY_BLOCK_WIDTH * 0.36 # Reconstructs the starting centre of the first visual wing column.
    var maximum_stagger: float = MASONRY_COLUMN_STEP * 0.5 # Accounts for the outward shift applied to alternating visual courses.
    var outer_column_centre: float = wing_start + float(MASONRY_WING_COLUMNS - 1) * MASONRY_COLUMN_STEP + maximum_stagger # Locates the furthest possible outer wing block centre.
    var maximum_half_block_width: float = MASONRY_BLOCK_WIDTH * 1.10 * 0.5 # Accounts for the maximum visual width variation allowed by the deep wing generator.
    return outer_column_centre + maximum_half_block_width # Returns the complete half-span required by the low-poly retaining collision shell.

func _add_box_collision(body: StaticBody3D, node_name: String, size: Vector3, local_position: Vector3) -> void: # Adds one primitive box shape to the shared low-complexity exterior collision body.
    var collision_shape: CollisionShape3D = CollisionShape3D.new() # Creates the lightweight scene child representing one coarse collision region.
    collision_shape.name = node_name # Assigns a descriptive name so each primitive is obvious in the remote scene tree.
    collision_shape.position = local_position # Places the primitive relative to the same terrain-oriented doorway transform used by the visual masonry.
    var box_shape: BoxShape3D = BoxShape3D.new() # Uses Godot's optimized primitive box shape instead of generated triangle-mesh collision.
    box_shape.size = size # Assigns the requested coarse collision dimensions around the visual retaining mass.
    collision_shape.shape = box_shape # Installs the primitive physics resource on the collision node.
    body.add_child(collision_shape) # Adds the primitive beneath the single shared StaticBody3D without creating per-brick physics bodies.
