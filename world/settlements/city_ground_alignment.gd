extends RefCounted # Fit retained city geometry to the rendered terrain triangles once during construction.
class_name CityGroundAlignment # Keep terrain fitting separate from city scenery and streaming ownership.

var _ground: CampSampler # Resolve the same triangle interpolation used by terrain-backed buildings.
var _definition: Dictionary # Retain absolute placement and yaw while sampling local footprints.
var _cache: Dictionary[Vector2, float] = {} # Reuse shared boundary and lattice samples during one build.

func _init(terrain: InfiniteTerrain, definition: Dictionary) -> void: # Bind one city to its authoritative terrain.
    _ground = CampSampler.new(terrain) # Query rendered ground rather than finer procedural noise.
    _definition = definition # Preserve the external root's existing placement and rotation.

func _height(local: Vector2) -> float: # Convert local footprint points to absolute terrain coordinates.
    if not _cache.has(local): # Sample each reused point only once.
        var world: Vector2 = _definition.position + SettlementSampler.rotate(local, float(_definition.yaw)) # Apply the same horizontal transform as the city root.
        _cache[local] = _ground.ground_height(world) - float(_definition.height) # Return elevation relative to the external city root.
    return _cache[local] # Reuse the bounded construction snapshot.

func _points(bounds: Rect2) -> Array[Vector2]: # Find every possible extremum of the piecewise planar terrain inside a rotated rectangle.
    var corners: Array[Vector2] = [bounds.position, bounds.position + Vector2(bounds.size.x, 0.0), bounds.end, bounds.position + Vector2(0.0, bounds.size.y)] # Include footprint corners and ordered boundary edges.
    var world_corners: Array[Vector2] = [] # Retain absolute corners for terrain lattice intersections.
    var result: Array[Vector2] = corners.duplicate() # Rectangle corners are potential clipped-triangle extrema.
    var minimum: Vector2 = Vector2(INF, INF) # Accumulate the absolute lattice range.
    var maximum: Vector2 = Vector2(-INF, -INF) # Accumulate the opposite lattice extent.
    for corner: Vector2 in corners: # Transform each rectangle boundary endpoint.
        var world: Vector2 = _definition.position + SettlementSampler.rotate(corner, float(_definition.yaw)) # Match the city root's actual rotation.
        world_corners.append(world) # Keep the transformed edge endpoint.
        minimum = minimum.min(world) # Expand the enclosing lattice bounds.
        maximum = maximum.max(world) # Expand the enclosing lattice bounds.
    var spacing: float = TerrainConfiguration.CHUNK_SIZE / float(TerrainConfiguration.CHUNK_RESOLUTION - 1) # Match the rendered triangle lattice.
    for z: int in range(ceili(minimum.y / spacing), floori(maximum.y / spacing) + 1): # Visit lattice rows intersecting the footprint.
        for x: int in range(ceili(minimum.x / spacing), floori(maximum.x / spacing) + 1): # Visit candidate terrain vertices.
            var local: Vector2 = SettlementSampler.rotate(Vector2(x, z) * spacing - _definition.position, -float(_definition.yaw)) # Transform the lattice vertex back into city space.
            if local.x >= bounds.position.x and local.x <= bounds.end.x and local.y >= bounds.position.y and local.y <= bounds.end.y: # Keep only terrain vertices contained by the footprint.
                result.append(local) # Include interior terrain extrema.
    for edge: int in range(corners.size()): # Clip the terrain grid against every footprint boundary.
        var start: Vector2 = world_corners[edge] # Resolve the absolute edge start.
        var finish: Vector2 = world_corners[(edge + 1) % corners.size()] # Resolve the absolute edge end.
        for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.ONE]: # Intersect vertical, horizontal and anti-diagonal terrain triangle edges.
            var first: float = start.dot(direction) # Project onto this lattice line family.
            var last: float = finish.dot(direction) # Project the other boundary endpoint.
            if is_equal_approx(first, last): # Skip parallel edges whose endpoints already cover extrema.
                continue # Avoid dividing by a degenerate projection.
            for line: int in range(ceili(minf(first, last) / spacing), floori(maxf(first, last) / spacing) + 1): # Visit only lattice lines crossing this boundary.
                var fraction: float = (float(line) * spacing - first) / (last - first) # Locate the exact clipped-triangle boundary vertex.
                result.append(corners[edge].lerp(corners[(edge + 1) % corners.size()], fraction)) # Preserve exact local placement for sampling.
    return result # Supply bounded exact extrema candidates without dense arbitrary sampling.

func _include(points: Array[Vector2], result: Dictionary) -> void: # Accumulate a terrain height interval for a local footprint.
    for point: Vector2 in points: # Visit all contained and clipped terrain vertices.
        var height: float = _height(point) # Read the actual rendered surface elevation.
        result.lowest = minf(float(result.lowest), height) # Retain the deepest support requirement.
        result.highest = maxf(float(result.highest), height) # Retain the highest obstruction.

func fit() -> Dictionary: # Build a complete alignment snapshot for immediate construction.
    var result: Dictionary = {"lowest": INF, "highest": -INF} # Track the entire retained foundation footprint.
    _include(_points(Rect2(-61.0, -61.0, 122.0, 122.0)), result) # Fit the full exterior rather than unrelated village house plots.
    return _finish(result) # Add a grounded approach snapshot.

func fit_incremental(scheduler: GenerationScheduler) -> Dictionary: # Share admission with scheduled settlement construction.
    var result: Dictionary = {"lowest": INF, "highest": -INF} # Accumulate the same footprint as immediate construction.
    var points: Array[Vector2] = _points(Rect2(-61.0, -61.0, 122.0, 122.0)) # Enumerate bounded geometry before querying terrain.
    for point: Vector2 in points: # Spread terrain queries across scheduled frames.
        if not await scheduler.checkpoint(): # Respect owner cancellation and frame budgets.
            return {} # Leave cancelled city geometry unallocated.
        _include([point], result) # Reuse the exact immediate-mode extrema rule.
    for index: int in range(16): # Admit approach terrain queries through the same frame budget.
        var z: float = 62.0 + float(index) * 2.0 # Match the prepared approach edge layout.
        for point: Vector2 in _points(Rect2(-5.0, z - 0.01, 10.0, 0.02)): # Prewarm each exact approach boundary query.
            if not await scheduler.checkpoint(): # Respect cancellation while fitting the entrance.
                return {} # Avoid allocating an incomplete entrance.
            _height(point) # Cache the sampled ground before assembling the profile.
    return _finish(result) # Assemble the complete snapshot from admitted cached queries.

func _finish(result: Dictionary) -> Dictionary: # Resolve a supported platform and terrain-aware approach profile.
    result["base"] = float(result.highest) + 0.25 # Clear all terrain under the retained moat without relying on house heights.
    result["bottom"] = float(result.lowest) - 0.5 # Embed the foundation below every part of its footprint.
    var approach: Array[Dictionary] = [] # Retain exact ground bounds for adjacent approach sections.
    for index: int in range(16): # Include both drawbridge and natural-ground endpoints.
        var z: float = 62.0 + float(index) * 2.0 # Match the existing approach footprint and road connection.
        var interval: Dictionary = {"lowest": INF, "highest": -INF} # Resolve terrain across the full walking width.
        _include(_points(Rect2(-5.0, z - 0.01, 10.0, 0.02)), interval) # Include triangle intersections across the approach edge.
        approach.append({"z": z, "ground": float(interval.highest), "bottom": float(interval.lowest) - 0.5}) # Keep support and surface requirements separate.
    var start: float = float(result.base) + 1.6 # Meet the existing drawbridge walking surface exactly.
    var finish: float = float(approach.back().ground) + 0.05 # Meet real terrain at the road end rather than the city's centre height.
    for index: int in range(approach.size()): # Create a continuous terrain-clearing walking profile.
        approach[index]["top"] = maxf(lerpf(start, finish, float(index) / float(approach.size() - 1)), float(approach[index].ground) + 0.05) # Retain intermediate hills while connecting both known endpoints.
    result["approach"] = approach # Return the immutable construction profile with footprint bounds.
    return result # Keep all later geometry free of terrain queries.
