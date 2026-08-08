extends DungeonSystem # Specializes the infinite paired-dungeon streamer so every overworld entrance is embedded into rising terrain.
class_name CliffDungeonSystem # Exposes cliff-, hill-, and mountain-only entrance placement while retaining the complete base transition system.

const CLIFF_SEARCH_RING_COUNT: int = 24 # Searches a broad deterministic neighbourhood around each intended endpoint so flat intended coordinates can still resolve onto nearby terrain faces.
const CLIFF_SEARCH_RING_STEP: float = 18.0 # Expands ordinary entrance placement in moderate increments without requiring dense continuous terrain sampling.
const CLIFF_SEARCH_DIRECTIONS: int = 16 # Samples enough directions around each search ring to resolve diagonal ridges and irregular hills reliably.
const CLIFF_GRADIENT_SAMPLE_DISTANCE: float = 6.0 # Measures the local terrain gradient across a scale wider than the doorway so tiny bumps never qualify as tunnel sites.
const CLIFF_BACK_NEAR_DISTANCE: float = 5.0 # Samples the first portion of the hillside directly behind the portal where masonry begins overlapping terrain.
const CLIFF_BACK_FAR_DISTANCE: float = 11.0 # Verifies that substantial terrain mass continues behind and above the complete doorway opening.
const CLIFF_FRONT_CLEAR_DISTANCE: float = 4.0 # Samples the approach side to ensure the portal faces out of the slope rather than deeper into uneven terrain.
const CLIFF_SHOULDER_BACK_DISTANCE: float = 7.0 # Samples terrain behind the left and right masonry wings to ensure both sides are embedded in the same landform.
const CLIFF_SHOULDER_HALF_WIDTH: float = 2.8 # Spreads rear shoulder samples beyond the doorway frame so narrow isolated spikes cannot qualify as a tunnel site.
const CLIFF_FOOT_HALF_WIDTH: float = 1.45 # Checks ground directly beneath both sides of the doorway before accepting a placement.
const MINIMUM_GRADIENT_SPAN: float = 1.35 # Requires a meaningful elevation difference across the local gradient sample before classifying terrain as a hill face.
const MINIMUM_NEAR_BACK_RISE: float = 1.35 # Requires the terrain to begin climbing immediately behind the portal so the frame visibly enters the landform.
const MINIMUM_FAR_BACK_RISE: float = 3.85 # Requires terrain behind the doorway to rise above the complete opening plus a visible overburden margin.
const MINIMUM_BACK_TO_FRONT_RISE: float = 4.1 # Requires a strong overall uphill-to-downhill difference so entrances do not appear on nearly flat ground.
const MINIMUM_SHOULDER_RISE: float = 2.15 # Requires both rear sides of the doorway to remain elevated enough for extended masonry to disappear into terrain.
const MAXIMUM_FRONT_RISE: float = 0.9 # Rejects sites where the supposed approach side climbs sharply and would make the portal face into another slope.
const MAXIMUM_FOOT_HEIGHT_DELTA: float = 1.25 # Rejects excessively uneven ground directly under the doorway while still allowing natural hillside toes.
const STARTING_FORWARD_MINIMUM_DISTANCE: float = 24.0 # Begins the startup cliff search far enough ahead for the complete terrain face and masonry to read clearly in view.
const STARTING_FORWARD_DISTANCE_STEP: float = 12.0 # Advances visible startup candidates through the camera view without leaving large unsampled distance gaps.
const STARTING_FORWARD_DISTANCE_ATTEMPTS: int = 22 # Searches the initial view cone out to several hundred metres before considering a camera reorientation fallback.
const STARTING_VIEW_ANGLE_STEP: float = deg_to_rad(6.0) # Moves startup candidates sideways through a narrow view cone while keeping every preferred result on screen.
const STARTING_VIEW_ANGLE_STEPS_PER_SIDE: int = 4 # Covers approximately twenty-four degrees to either side of the initial camera centre.
const STARTING_RADIAL_MINIMUM_DISTANCE: float = 36.0 # Begins the fallback terrain-face search outside the player's immediate spawn footprint and training area.
const STARTING_RADIAL_DISTANCE_STEP: float = 18.0 # Expands the fallback search smoothly enough to prefer the nearest viable cliff, hill, or mountain face.
const STARTING_RADIAL_DISTANCE_ATTEMPTS: int = 48 # Extends the fallback search to roughly nine hundred metres when the initial camera direction contains no suitable slope.
const STARTING_RADIAL_DIRECTIONS: int = 32 # Samples the full area around the player densely enough to locate a nearby terrain face before rotating the initial view toward it.
const STARTING_MINIMUM_FACING_DOT: float = 0.68 # Requires the selected portal's downhill-facing side to point broadly toward the player rather than presenting its buried rear face.
const SEARCH_ANGLE_SCALE_X: float = 0.0173 # Mixes absolute x position into deterministic ordinary search-ring angular rotation.
const SEARCH_ANGLE_SCALE_Z: float = 0.0137 # Mixes absolute z position independently so neighbouring searches do not share obvious radial spokes.

func _initialize_starting_pair(player_horizontal: Vector2) -> void: # Replaces the starting-region pair with one whose first door is both visible at load and physically embedded in rising terrain.
    _starting_region_coordinate = _get_region_coordinate(player_horizontal) # Assigns the startup pair to the same infinite region that already owns the resolved shoreline spawn.
    var pair_id: int = _get_pair_id(_starting_region_coordinate) # Reuses the normal region identity so no extra tutorial-only dungeon is introduced.
    var pair_seed: int = _get_pair_random_seed(pair_id) # Derives the same deterministic region random stream used by ordinary infinite dungeon pairs.
    var rng: RandomNumberGenerator = RandomNumberGenerator.new() # Creates isolated deterministic randomness for the startup partner distance and direction.
    rng.seed = pair_seed # Resets all startup pair choices identically for the same world seed and starting region.
    var camera_forward: Vector2 = _get_camera_horizontal_forward() # Reads the actual post-spawn view direction so the preferred terrain search remains inside the player's initial view.
    var endpoint_a_placement: DungeonEntrancePlacement = _find_starting_cliff_placement(player_horizontal, camera_forward) # Finds a real cliff, hill, or mountain face while preserving the existing startup visibility requirement.
    if endpoint_a_placement == null: # Detects the exceptional case where the large bounded startup search cannot find any meaningful rising terrain.
        return # Refuses to create a freestanding dungeon door because exterior entrances are now required to be tunnelled into terrain.
    var separation: float = _sample_pair_separation(rng) # Preserves the existing logarithmic short-to-eight-kilometre distance variety for the remote paired endpoint.
    var partner_angle: float = rng.randf_range(0.0, TAU) # Chooses the deterministic initial direction toward the remote paired entrance.
    var partner_direction: Vector2 = Vector2(cos(partner_angle), sin(partner_angle)) # Converts the sampled angle into a normalized horizontal world-space direction.
    var intended_b: Vector2 = endpoint_a_placement.world_position + partner_direction * separation # Places the second intended endpoint at the full sampled pair distance from the visible entrance.
    var endpoint_b_placement: DungeonEntrancePlacement = _find_cliff_placement(intended_b) # Relocates the second endpoint onto the nearest deterministic qualifying terrain face.
    if endpoint_b_placement == null: # Detects that no cliff, hill, or mountain face exists within the bounded search around the intended remote endpoint.
        return # Rejects the complete pair rather than silently creating one forbidden freestanding endpoint.
    var pair: DungeonPairDefinition = DungeonPairDefinition.new() # Allocates the same stable metadata contract consumed by the existing transition and interior systems.
    pair.pair_id = pair_id # Assigns the normal starting-region identity used by interaction and deterministic interior reconstruction.
    pair.region_coordinate = _starting_region_coordinate # Retains the infinite-region owner for streaming and diagnostics.
    pair.dungeon_seed = pair_seed ^ 7_919_357 # Derives the interior seed identically to ordinary paired dungeons so layout determinism remains unchanged.
    pair.endpoint_a_world_position = _get_grounded_world_position(endpoint_a_placement.world_position) # Grounds the visible cliff entrance against authoritative procedural terrain height.
    pair.endpoint_b_world_position = _get_grounded_world_position(endpoint_b_placement.world_position) # Grounds the remote cliff entrance independently against its selected terrain face.
    pair.endpoint_a_yaw = _get_yaw_from_outward_direction(endpoint_a_placement.outward_direction) # Faces startup Door A downhill and away from the terrain mass containing its tunnel mouth.
    pair.endpoint_b_yaw = _get_yaw_from_outward_direction(endpoint_b_placement.outward_direction) # Faces startup Door B downhill from its own independent cliff, hill, or mountain face.
    _starting_pair = pair # Retains the exact pair so ordinary stream unload/reload reconstructs the same embedded entrances during the session.
    _ensure_starting_door_is_visible(player_horizontal, endpoint_a_placement.world_position, camera_forward) # Rotates the player only when the selected qualifying terrain face fell outside the preferred initial camera cone.

func _build_pair_if_nearby(region_coordinate: Vector2i, player_horizontal: Vector2) -> DungeonPairDefinition: # Reconstructs one infinite-region pair only when both exterior endpoints can be embedded into qualifying terrain faces.
    var pair_id: int = _get_pair_id(region_coordinate) # Calculates the same stable identity used by the base streamer, labels, routing, and interior generation.
    var pair_seed: int = _get_pair_random_seed(pair_id) # Derives deterministic endpoint placement randomness from world seed and infinite region identity.
    var rng: RandomNumberGenerator = RandomNumberGenerator.new() # Creates a local pair-placement generator without mutating global random state.
    rng.seed = pair_seed # Resets midpoint, separation, and axis choices identically whenever the pair is reconstructed.
    var region_origin: Vector2 = Vector2(float(region_coordinate.x) * DUNGEON_REGION_SIZE, float(region_coordinate.y) * DUNGEON_REGION_SIZE) # Calculates the absolute southwest corner of the pair's owning infinite region.
    var midpoint_margin: float = DUNGEON_REGION_SIZE * REGION_MIDPOINT_MARGIN # Converts the inherited normalized region margin into physical world-space distance.
    var midpoint: Vector2 = region_origin + Vector2(rng.randf_range(midpoint_margin, DUNGEON_REGION_SIZE - midpoint_margin), rng.randf_range(midpoint_margin, DUNGEON_REGION_SIZE - midpoint_margin)) # Places the conceptual pair centre irregularly inside its region before terrain-face correction.
    var separation: float = _sample_pair_separation(rng) # Preserves the inherited logarithmic distance distribution from local shortcuts through rare multi-kilometre links.
    var separation_angle: float = rng.randf_range(0.0, TAU) # Chooses an unrestricted deterministic axis for the conceptual endpoint pair.
    var span_direction: Vector2 = Vector2(cos(separation_angle), sin(separation_angle)) # Converts the deterministic axis angle into a normalized horizontal direction.
    var half_span: float = separation * 0.5 # Splits the complete pair span evenly around its conceptual midpoint before terrain correction.
    var intended_a: Vector2 = midpoint - span_direction * half_span # Calculates the first conceptual endpoint before searching for a nearby valid terrain face.
    var intended_b: Vector2 = midpoint + span_direction * half_span # Calculates the second conceptual endpoint on the opposite side of the pair midpoint.
    var cliff_search_allowance: float = float(CLIFF_SEARCH_RING_COUNT) * CLIFF_SEARCH_RING_STEP # Measures the maximum endpoint correction introduced by the cliff-only terrain search.
    var prefetch_distance: float = PAIR_LOAD_DISTANCE + cliff_search_allowance # Expands the inherited prefetch threshold enough to include portals moved onto nearby hillsides.
    if intended_a.distance_to(player_horizontal) > prefetch_distance and intended_b.distance_to(player_horizontal) > prefetch_distance: # Detects a region whose conceptual endpoints cannot produce a currently relevant streamed entrance.
        return null # Avoids expensive cliff analysis for the overwhelming majority of distant implicit regions.
    var endpoint_a_placement: DungeonEntrancePlacement = _find_cliff_placement(intended_a) # Searches deterministically for a qualifying rising terrain face near conceptual endpoint A.
    if endpoint_a_placement == null: # Detects regions where endpoint A has no cliff, hill, or mountain face within the bounded correction radius.
        return null # Omits the complete dungeon pair so a forbidden freestanding entrance is never generated.
    var endpoint_b_placement: DungeonEntrancePlacement = _find_cliff_placement(intended_b) # Searches independently for a qualifying rising terrain face near conceptual endpoint B.
    if endpoint_b_placement == null: # Detects regions where only one side can satisfy the terrain-embedded entrance requirement.
        return null # Omits the complete pair because both linked exterior doors must obey the same terrain rule.
    var pair: DungeonPairDefinition = DungeonPairDefinition.new() # Allocates the unchanged pair metadata object consumed by the base streaming and transition systems.
    pair.pair_id = pair_id # Assigns the stable infinite-region identity after both terrain placements have been validated.
    pair.region_coordinate = region_coordinate # Retains the owning region coordinate for deterministic reconstruction and readable remote-tree labels.
    pair.dungeon_seed = pair_seed ^ 7_919_357 # Preserves the established independent deterministic stream for interior dungeon generation.
    pair.endpoint_a_world_position = _get_grounded_world_position(endpoint_a_placement.world_position) # Grounds exterior A at the foot of its validated rising terrain face.
    pair.endpoint_b_world_position = _get_grounded_world_position(endpoint_b_placement.world_position) # Grounds exterior B at the foot of its independently validated terrain face.
    pair.endpoint_a_yaw = _get_yaw_from_outward_direction(endpoint_a_placement.outward_direction) # Faces A downhill so its rear masonry and tunnel throat disappear into the hill behind it.
    pair.endpoint_b_yaw = _get_yaw_from_outward_direction(endpoint_b_placement.outward_direction) # Faces B downhill from its own terrain gradient rather than toward the geographically paired door.
    return pair # Returns a pair only after both endpoints satisfy the cliff-, hill-, or mountain-only placement contract.

func _find_cliff_placement(intended_position: Vector2) -> DungeonEntrancePlacement: # Searches outward from one conceptual endpoint until finding the nearest deterministic qualifying terrain face.
    var direct_placement: DungeonEntrancePlacement = _evaluate_cliff_site(intended_position) # Tests the intended coordinate first so existing deterministic placement changes only when terrain embedding requires it.
    if direct_placement != null: # Detects an intended endpoint that already sits at the foot of a valid rising landform.
        return direct_placement # Preserves that exact position and its sampled downhill-facing direction.
    var angle_offset: float = fposmod(intended_position.x * SEARCH_ANGLE_SCALE_X + intended_position.y * SEARCH_ANGLE_SCALE_Z, TAU) # Rotates each radial search deterministically so the world never reveals fixed cardinal placement spokes.
    for ring: int in range(1, CLIFF_SEARCH_RING_COUNT + 1): # Expands through bounded rings so the nearest qualifying terrain face wins naturally.
        var radius: float = float(ring) * CLIFF_SEARCH_RING_STEP # Converts the ring index into physical correction distance from the conceptual endpoint.
        for direction_index: int in range(CLIFF_SEARCH_DIRECTIONS): # Samples evenly distributed directions around the current search ring.
            var angle: float = angle_offset + TAU * float(direction_index) / float(CLIFF_SEARCH_DIRECTIONS) # Applies the endpoint-specific rotation before calculating this candidate direction.
            var candidate: Vector2 = intended_position + Vector2(cos(angle), sin(angle)) * radius # Builds the absolute procedural-world candidate coordinate for cliff analysis.
            var placement: DungeonEntrancePlacement = _evaluate_cliff_site(candidate) # Tests terrain mass, approach clearance, shoulder coverage, and doorway footing at the candidate.
            if placement != null: # Detects the first qualifying cliff, hill, or mountain face on the nearest successful ring.
                return placement # Returns the deterministic terrain-embedded entrance placement immediately.
    return null # Reports that this conceptual endpoint cannot support an exterior dungeon entrance without violating the terrain-only requirement.

func _find_starting_cliff_placement(player_horizontal: Vector2, camera_forward: Vector2) -> DungeonEntrancePlacement: # Finds the first qualifying terrain portal in view, then searches all directions only if the initial view contains no valid landform.
    for distance_index: int in range(STARTING_FORWARD_DISTANCE_ATTEMPTS): # Searches increasingly distant terrain while remaining inside the initial camera's useful visible range.
        var distance: float = STARTING_FORWARD_MINIMUM_DISTANCE + float(distance_index) * STARTING_FORWARD_DISTANCE_STEP # Calculates the current preferred distance from the resolved player spawn.
        var view_direction_count: int = STARTING_VIEW_ANGLE_STEPS_PER_SIDE * 2 + 1 # Counts the centre ray plus equal left and right angular alternatives.
        for view_index: int in range(view_direction_count): # Tests the centre of view first and then alternates through progressively wider angles.
            var signed_step: int = 0 # Keeps the first startup candidate exactly on the initial camera centre line.
            if view_index > 0: # Detects an off-centre candidate after the preferred centre ray has been tested.
                var magnitude: int = (view_index + 1) >> 1 # Converts alternating indices into one-based angular step magnitudes.
                signed_step = magnitude if view_index % 2 == 1 else -magnitude # Alternates right and left so both sides receive equal deterministic priority.
            var candidate_direction: Vector2 = camera_forward.rotated(float(signed_step) * STARTING_VIEW_ANGLE_STEP) # Rotates the camera-forward vector while retaining the candidate inside a narrow visible cone.
            var candidate: Vector2 = player_horizontal + candidate_direction * distance # Places the candidate at the current distance along the selected visible direction.
            var placement: DungeonEntrancePlacement = _evaluate_cliff_site(candidate) # Tests whether this visible point is a genuine terrain face suitable for tunnelling.
            if placement != null and _placement_faces_point(placement, player_horizontal): # Requires the downhill portal face to present broadly toward the player rather than away from the initial approach.
                return placement # Uses the first qualifying visible hillside so the opening appears naturally in the initial view without camera manipulation.
    var forward_angle: float = camera_forward.angle() # Uses the existing camera orientation as the deterministic starting angle for the all-direction fallback search.
    for distance_index: int in range(STARTING_RADIAL_DISTANCE_ATTEMPTS): # Expands outward from the player so the nearest qualifying terrain face remains preferred.
        var distance: float = STARTING_RADIAL_MINIMUM_DISTANCE + float(distance_index) * STARTING_RADIAL_DISTANCE_STEP # Calculates the physical radius of the current fallback search ring.
        for direction_index: int in range(STARTING_RADIAL_DIRECTIONS): # Samples the complete area around the spawn on the current radius.
            var angle: float = forward_angle + TAU * float(direction_index) / float(STARTING_RADIAL_DIRECTIONS) # Starts from the original view direction before sweeping around the player deterministically.
            var candidate: Vector2 = player_horizontal + Vector2(cos(angle), sin(angle)) * distance # Builds the absolute terrain coordinate for this fallback candidate.
            var placement: DungeonEntrancePlacement = _evaluate_cliff_site(candidate) # Applies the same strict terrain-mass test used by every ordinary dungeon entrance.
            if placement != null and _placement_faces_point(placement, player_horizontal): # Requires the portal's approach side to face broadly back toward the player's spawn position.
                return placement # Returns the nearest qualifying landform even when it requires centring the initial player view afterward.
    return null # Refuses a freestanding startup portal when no real cliff, hill, or mountain face exists inside the large bounded search area.

func _evaluate_cliff_site(position: Vector2) -> DungeonEntrancePlacement: # Validates that one terrain coordinate sits at the foot of a broad rising landform with a clear downhill approach.
    if _terrain.has_water_at(position): # Rejects any doorway root located inside the same clipped water representation rendered by the overworld.
        return null # Prevents tunnel entrances from being generated in lakes, rivers, or sea cells.
    var centre_height: float = _terrain.get_height_at(position) # Samples the authoritative ground height at the proposed doorway threshold.
    var east_height: float = _terrain.get_height_at(position + Vector2(CLIFF_GRADIENT_SAMPLE_DISTANCE, 0.0)) # Samples terrain east of the doorway to estimate the local uphill direction.
    var west_height: float = _terrain.get_height_at(position - Vector2(CLIFF_GRADIENT_SAMPLE_DISTANCE, 0.0)) # Samples terrain west of the doorway for the opposite side of the horizontal gradient.
    var south_height: float = _terrain.get_height_at(position + Vector2(0.0, CLIFF_GRADIENT_SAMPLE_DISTANCE)) # Samples terrain toward positive world z for the second gradient axis.
    var north_height: float = _terrain.get_height_at(position - Vector2(0.0, CLIFF_GRADIENT_SAMPLE_DISTANCE)) # Samples terrain toward negative world z for the opposite gradient axis.
    var gradient: Vector2 = Vector2(east_height - west_height, south_height - north_height) # Builds a horizontal vector pointing toward the strongest local increase in terrain height.
    if gradient.length() < MINIMUM_GRADIENT_SPAN: # Detects terrain too flat across the full doorway scale to read as a hill, cliff, or mountain face.
        return null # Rejects flat fields and gentle surface noise before performing more expensive directional samples.
    var uphill_direction: Vector2 = gradient.normalized() # Converts the measured local terrain rise into the direction the tunnel should extend into the landform.
    var outward_direction: Vector2 = -uphill_direction # Points the visible portal face downhill and away from the terrain mass containing the dungeon mouth.
    var right_direction: Vector2 = Vector2(-outward_direction.y, outward_direction.x).normalized() # Builds the doorway's horizontal right axis for footing and rear-shoulder coverage tests.
    var front_position: Vector2 = position + outward_direction * CLIFF_FRONT_CLEAR_DISTANCE # Samples the player's approach side several metres downhill from the proposed threshold.
    if _terrain.has_water_at(front_position): # Rejects approaches that immediately terminate in water even when the rear terrain shape is otherwise suitable.
        return null # Keeps generated tunnel mouths physically approachable on dry overworld ground.
    var back_near_position: Vector2 = position + uphill_direction * CLIFF_BACK_NEAR_DISTANCE # Samples terrain where the generated tunnel return and masonry first disappear behind the portal.
    var back_far_position: Vector2 = position + uphill_direction * CLIFF_BACK_FAR_DISTANCE # Samples deeper into the landform to verify substantial overburden above the doorway.
    var front_height: float = _terrain.get_height_at(front_position) # Reads the approach-side elevation used to confirm the portal genuinely faces downhill.
    var back_near_height: float = _terrain.get_height_at(back_near_position) # Reads the first uphill elevation behind the generated doorway.
    var back_far_height: float = _terrain.get_height_at(back_far_position) # Reads the deeper uphill elevation that must rise above the complete opening.
    if back_near_height - centre_height < MINIMUM_NEAR_BACK_RISE: # Detects terrain that does not begin enveloping the portal soon enough behind its frame.
        return null # Rejects sites where extended brickwork would remain visibly detached from the hillside.
    if back_far_height - centre_height < MINIMUM_FAR_BACK_RISE: # Detects hills too low to provide believable earth or rock above the complete doorway opening.
        return null # Requires real terrain mass over the tunnel mouth instead of a frame standing beside a small mound.
    if back_far_height - front_height < MINIMUM_BACK_TO_FRONT_RISE: # Detects terrain whose uphill and downhill sides lack enough total relief to read as a tunnel entrance.
        return null # Rejects broad almost-flat plateaus even if minor local gradient noise pointed in one direction.
    if front_height - centre_height > MAXIMUM_FRONT_RISE: # Detects an approach side that rises too sharply in front of the portal.
        return null # Prevents the doorway from being wedged between slopes or facing into another nearby bank.
    var left_shoulder_position: Vector2 = position + uphill_direction * CLIFF_SHOULDER_BACK_DISTANCE - right_direction * CLIFF_SHOULDER_HALF_WIDTH # Samples the elevated terrain mass behind the left masonry wing.
    var right_shoulder_position: Vector2 = position + uphill_direction * CLIFF_SHOULDER_BACK_DISTANCE + right_direction * CLIFF_SHOULDER_HALF_WIDTH # Samples the matching elevated terrain mass behind the right masonry wing.
    var left_shoulder_height: float = _terrain.get_height_at(left_shoulder_position) # Reads rear-left terrain height to reject narrow ridges that cannot visually contain the entrance.
    var right_shoulder_height: float = _terrain.get_height_at(right_shoulder_position) # Reads rear-right terrain height for the opposite side of the portal.
    if left_shoulder_height - centre_height < MINIMUM_SHOULDER_RISE: # Detects insufficient elevated terrain behind the left side of the extended brickwork.
        return null # Rejects landforms too narrow to make the portal appear genuinely embedded.
    if right_shoulder_height - centre_height < MINIMUM_SHOULDER_RISE: # Detects insufficient elevated terrain behind the right side of the extended brickwork.
        return null # Requires a broad hillside, cliff, or mountain face spanning the complete entrance width.
    var left_foot_height: float = _terrain.get_height_at(position - right_direction * CLIFF_FOOT_HALF_WIDTH) # Samples ground beneath the left edge of the generated portal threshold.
    var right_foot_height: float = _terrain.get_height_at(position + right_direction * CLIFF_FOOT_HALF_WIDTH) # Samples ground beneath the right edge of the generated portal threshold.
    if absf(left_foot_height - centre_height) > MAXIMUM_FOOT_HEIGHT_DELTA: # Detects a left doorway footing that would float or bury an excessive amount of masonry.
        return null # Rejects locally broken ground even when the larger terrain face is otherwise suitable.
    if absf(right_foot_height - centre_height) > MAXIMUM_FOOT_HEIGHT_DELTA: # Detects the equivalent excessive height difference under the right side of the doorway.
        return null # Keeps the portal threshold reasonably level for player approach and visual integration.
    return DungeonEntrancePlacement.new(position, outward_direction) # Returns the validated threshold position and downhill-facing direction for deterministic doorway construction.

func _placement_faces_point(placement: DungeonEntrancePlacement, point: Vector2) -> bool: # Tests whether a validated portal's visible downhill side broadly faces a required approach point.
    var toward_point: Vector2 = point - placement.world_position # Builds the horizontal direction from the portal threshold back toward the desired viewer or approach location.
    if toward_point.is_zero_approx(): # Handles the impossible case where the viewer and doorway occupy the same horizontal coordinate.
        return true # Treats the orientation as acceptable because no meaningful approach direction exists to compare.
    return placement.outward_direction.dot(toward_point.normalized()) >= STARTING_MINIMUM_FACING_DOT # Accepts only portals whose visible face points sufficiently toward the initial player position.

func _ensure_starting_door_is_visible(player_horizontal: Vector2, door_position: Vector2, original_camera_forward: Vector2) -> void: # Centres the initial view only when the nearest qualifying terrain face fell outside the preferred camera cone.
    var toward_door: Vector2 = door_position - player_horizontal # Calculates the horizontal direction from the resolved player spawn to startup Door A.
    if toward_door.is_zero_approx(): # Handles an invalid coincident position defensively.
        return # Leaves the current camera orientation unchanged because no stable yaw can be derived.
    var normalized_toward_door: Vector2 = toward_door.normalized() # Normalizes the selected direction before comparing it with the initial camera forward axis.
    if original_camera_forward.dot(normalized_toward_door) >= cos(STARTING_VIEW_ANGLE_STEP * float(STARTING_VIEW_ANGLE_STEPS_PER_SIDE)): # Detects a preferred placement already inside the narrow initial view cone.
        return # Preserves the player's authored initial orientation when the embedded entrance is already visible.
    _player.rotation.y = _get_yaw_facing_target(player_horizontal, door_position) # Rotates the player root so the fallback cliff entrance becomes centred in the first-person view at load.

func _get_grounded_world_position(horizontal_position: Vector2) -> Vector3: # Converts one validated horizontal threshold into the complete absolute terrain-backed doorway position.
    return Vector3(horizontal_position.x, _terrain.get_height_at(horizontal_position) + ENDPOINT_GROUND_CLEARANCE, horizontal_position.y) # Places the portal root just above sampled ground to avoid depth flicker at its buried threshold.

func _get_yaw_from_outward_direction(outward_direction: Vector2) -> float: # Converts a sampled downhill terrain direction into the same yaw convention used by existing exterior doors and return placement.
    return _get_yaw_facing_target(Vector2.ZERO, outward_direction) # Reuses the proven negative-z-forward yaw helper with direction represented as a target from the origin.
