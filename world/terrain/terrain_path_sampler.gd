extends RefCounted # Provides deterministic world-space worn-path masks without scene ownership.
class_name TerrainPathSampler # Makes the shared path network available to terrain and vegetation systems.

const PATH_SPACING: float = 1024.0 # Spaces the primary connected path families roughly one kilometre apart.
const HALF_PATH_SPACING: float = PATH_SPACING * 0.5 # Keeps repeated-line distance sampling centred around each path.
const PATH_CORE_RADIUS: float = 8.0 # Defines the consistently worn grassless centre of each path.
const PATH_EDGE_RADIUS: float = 20.0 # Blends worn ground back into untouched terrain over a soft shoulder.
const GRASS_CLEAR_RADIUS: float = 12.0 # Clears dense grass slightly beyond the visibly compacted centre.
const GRASS_FADE_RADIUS: float = 27.0 # Lets grass return gradually at irregular path edges.
const MAXIMUM_WEAR_DEPTH: float = 0.38 # Lowers the most travelled path centre by a restrained amount.

static func get_wear_mask(position: Vector2) -> float: # Returns the visual and terrain-depression weight for one absolute world position.
    var vertical_distance: float = _distance_to_repeated_line(position.x - _get_vertical_meander(position.y)) # Measures distance to the nearest north-south meandering path.
    var horizontal_distance: float = _distance_to_repeated_line(position.y - _get_horizontal_meander(position.x)) # Measures distance to the nearest east-west meandering path.
    var vertical_mask: float = _get_axis_mask(vertical_distance, position.y, PATH_CORE_RADIUS, PATH_EDGE_RADIUS, 0.40) # Builds the softened north-south worn corridor.
    var horizontal_mask: float = _get_axis_mask(horizontal_distance, position.x, PATH_CORE_RADIUS, PATH_EDGE_RADIUS, 2.10) # Builds the softened east-west worn corridor.
    return maxf(vertical_mask, horizontal_mask) # Joins both families into one deterministic connected path network.

static func get_grass_suppression(position: Vector2) -> float: # Returns how strongly dense ground grass should be removed around a path.
    var vertical_distance: float = _distance_to_repeated_line(position.x - _get_vertical_meander(position.y)) # Measures distance to the nearest north-south grass-clearing corridor.
    var horizontal_distance: float = _distance_to_repeated_line(position.y - _get_horizontal_meander(position.x)) # Measures distance to the nearest east-west grass-clearing corridor.
    var vertical_mask: float = _get_axis_mask(vertical_distance, position.y, GRASS_CLEAR_RADIUS, GRASS_FADE_RADIUS, 0.40) # Creates a wider north-south vegetation clearing than the compacted soil.
    var horizontal_mask: float = _get_axis_mask(horizontal_distance, position.x, GRASS_CLEAR_RADIUS, GRASS_FADE_RADIUS, 2.10) # Creates the matching east-west vegetation clearing.
    return maxf(vertical_mask, horizontal_mask) # Uses the strongest nearby path so intersections remain completely grassless.

static func get_height_offset(position: Vector2) -> float: # Returns the small negative terrain offset caused by repeated foot and cart traffic.
    var wear_mask: float = get_wear_mask(position) # Samples the shared compacted-ground corridor at this world position.
    return -MAXIMUM_WEAR_DEPTH * pow(wear_mask, 1.45) # Concentrates most depression in the centre while leaving soft shoulders nearly unchanged.

static func _distance_to_repeated_line(coordinate: float) -> float: # Measures distance to the nearest member of one evenly spaced path family.
    return absf(fposmod(coordinate + HALF_PATH_SPACING, PATH_SPACING) - HALF_PATH_SPACING) # Wraps signed distance into the centred repeated interval.

static func _get_axis_mask(distance: float, along_coordinate: float, core_radius: float, edge_radius: float, phase: float) -> float: # Builds one irregularly widening and narrowing path profile.
    var width_scale: float = _get_width_scale(along_coordinate, phase) # Samples slow deterministic variation so paths never keep one mechanical width.
    var scaled_core_radius: float = core_radius * width_scale # Applies width variation to the fully worn centre.
    var scaled_edge_radius: float = edge_radius * width_scale # Applies the same variation to the soft outer shoulder.
    return 1.0 - smoothstep(scaled_core_radius, scaled_edge_radius, distance) # Returns full strength in the centre and a smooth fade toward untouched terrain.

static func _get_width_scale(along_coordinate: float, phase: float) -> float: # Varies path width without allocating noise resources or introducing nondeterminism.
    var broad_variation: float = sin(along_coordinate * 0.0027 + phase) * 0.10 # Adds long gradual widening and narrowing.
    var local_variation: float = sin(along_coordinate * 0.0079 + phase * 1.73) * 0.05 # Adds a smaller secondary irregularity to the path edge.
    return clampf(1.0 + broad_variation + local_variation, 0.82, 1.18) # Prevents variation from making paths implausibly thin or wide.

static func _get_vertical_meander(world_z: float) -> float: # Offsets north-south paths sideways using several broad wave scales.
    var broad_curve: float = (sin(world_z * 0.00140 + 0.35) - sin(0.35)) * 96.0 # Produces kilometre-scale bends while keeping the origin path anchored.
    var regional_curve: float = (sin(world_z * 0.00053 + 1.90) - sin(1.90)) * 126.0 # Adds slower regional drift across long journeys.
    var local_curve: float = (sin(world_z * 0.00370 + 2.45) - sin(2.45)) * 50.0 # Adds visible shorter meanders without creating sharp turns.
    return broad_curve + regional_curve + local_curve # Combines the three scales into one smooth continuous offset.

static func _get_horizontal_meander(world_x: float) -> float: # Offsets east-west paths independently so intersections and bends remain organic.
    var broad_curve: float = (sin(world_x * 0.00118 + 1.10) - sin(1.10)) * 104.0 # Produces broad east-west bends while anchoring the path through the origin.
    var regional_curve: float = (sin(world_x * 0.00061 + 2.65) - sin(2.65)) * 118.0 # Adds a second slower drift that prevents mirrored path families.
    var local_curve: float = (sin(world_x * 0.00325 + 0.70) - sin(0.70)) * 44.0 # Adds smaller irregular bends suitable for a travelled trail.
    return broad_curve + regional_curve + local_curve # Combines every horizontal meander scale into one continuous offset.
