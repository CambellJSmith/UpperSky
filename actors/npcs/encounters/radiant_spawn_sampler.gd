extends RefCounted # Isolate offscreen spawn validation from radiant event scheduling.
class_name RadiantSpawnSampler # Require streamed dry ground and a physically clear approach.

var _terrain: InfiniteTerrain # Retain the terrain used by the overworld actors.
var _ground: CampSampler # Match the rendered terrain triangles for actor grounding.
var _capsule: CapsuleShape3D = CapsuleShape3D.new() # Reuse one shape throughout rare spawn checks.

func _init(terrain: InfiniteTerrain) -> void: # Prepare bounded placement queries without generating settlements.
    _terrain = terrain # Keep coordinate conversion consistent with the director.
    _ground = CampSampler.new(terrain) # Reuse actual terrain triangle interpolation.
    _capsule.radius = 0.4 # Reserve walking clearance around the actor's body.
    _capsule.height = 1.65 # Match ordinary villager collision height.

static func is_offscreen(camera: Camera3D, local_position: Vector3) -> bool: # Conservatively require the entire actor bounds to be behind the camera.
    for x: float in [-2.0, 2.0]: # Include the actor's potential horizontal model extent.
        for y: float in [0.0, 2.8]: # Include the grounded feet and animated head extent.
            for z: float in [-2.0, 2.0]: # Include the model's forward and backward extent.
                if not camera.is_position_behind(local_position + Vector3(x, y, z)): # Reject any bound corner on the visible side of the camera plane.
                    return false # Prevent the new actor from appearing in view.
    return true # Accept only a wholly hidden rear spawn or retirement position.

func candidate(player: FirstPersonPlayer, rng: RandomNumberGenerator) -> Vector2: # Propose one rear position without retrying indefinitely in a frame.
    var camera: Camera3D = player.get_view_camera() # Use the player's actual current view.
    var rear: Vector2 = Vector2(camera.global_basis.z.x, camera.global_basis.z.z).normalized() # Project the rear camera direction onto the ground plane.
    if rear.is_zero_approx(): # Handle a camera looking directly up or down.
        rear = Vector2(player.global_basis.z.x, player.global_basis.z.z).normalized() # Use the body's horizontal rear direction.
    var world: Vector3 = _terrain.local_to_world_position(player.global_position) # Resolve an absolute player anchor.
    return Vector2(world.x, world.z) + rear.rotated(rng.randf_range(-0.8, 0.8)) * rng.randf_range(28.0, 44.0) # Place the actor behind the player at a believable approach distance.

func valid(candidate_point: Vector2, player: FirstPersonPlayer) -> bool: # Validate one bounded candidate before allocating an NPC or loading a model.
    var world: Vector3 = _terrain.local_to_world_position(player.global_position) # Resolve the current absolute destination.
    var destination: Vector2 = Vector2(world.x, world.z) # Keep the route stable across origin rebasing.
    var spawn: Vector3 = Vector3(candidate_point.x, _ground.ground_height(candidate_point) + 0.04, candidate_point.y) # Ground the candidate on actual terrain triangles.
    if not is_offscreen(player.get_view_camera(), _terrain.world_to_local_position(spawn)): # Recheck the current camera before doing physics work.
        return false # Reject a player camera turn that exposes the proposed spawn.
    var previous: float = spawn.y - 0.04 # Begin slope checking at the grounded candidate.
    var steps: int = maxi(1, ceili(candidate_point.distance_to(destination))) # Bound route probes to the proposed approach distance.
    var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state # Use only currently registered world collisions.
    for index: int in range(steps + 1): # Check the entire initial approach rather than only its endpoints.
        var point: Vector2 = candidate_point.lerp(destination, float(index) / float(steps)) # Resolve the next absolute ground probe.
        if _terrain.has_water_at(point) or BiomeProfile.is_lava(point): # Exclude water and lava along the approach.
            return false # Never route a challenger across unsafe surfaces.
        var height: float = _ground.ground_height(point) # Match the actual ground triangle beneath the route.
        if absf(height - previous) > 0.4: # Avoid abrupt slopes that ordinary NPC movement would reject.
            return false # Keep the planned approach within the actor's walking tolerance.
        previous = height # Retain the preceding checked ground height.
        var local: Vector3 = _terrain.world_to_local_position(Vector3(point.x, height, point.y)) # Convert the probe into the current physics space.
        var ground_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(local + Vector3.UP * 2.0, local - Vector3.UP * 2.0, 1) # Require real streamed collision beneath every route point.
        ground_query.exclude = [player.get_rid()] # Ignore the participant while checking ground.
        var hit: Dictionary = space.intersect_ray(ground_query) # Resolve the first solid surface beneath this probe.
        if hit.is_empty() or absf((hit.position as Vector3).y - height) > 0.2: # Reject unloaded terrain, roofs and mismatched collision surfaces.
            return false # Avoid airborne or building-interior spawns.
        var shape_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new() # Check physical body clearance along the route.
        shape_query.shape = _capsule # Reuse the prepared actor-sized collision volume.
        shape_query.transform = Transform3D(Basis.IDENTITY, local + Vector3.UP * 0.92) # Leave enough foot clearance for ordinary ground slopes.
        shape_query.collision_mask = 1 | 4 # Respect scenery and other actor bodies.
        shape_query.exclude = [player.get_rid()] # Allow the route to approach its intended participant.
        if not space.intersect_shape(shape_query, 1).is_empty(): # Reject tents, walls, trees and occupied spawn positions.
            return false # Never create the actor inside a collider or plan a blocked straight approach.
    return true # Accept only offscreen, dry, loaded and clear initial approaches.
