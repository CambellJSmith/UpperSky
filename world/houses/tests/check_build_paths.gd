extends SceneTree # Verify matching geometry from both procedural building paths.

class ImmediateScheduler extends GenerationScheduler: # Complete checkpoints immediately for deterministic comparison.
    func checkpoint(_owner: Node = null) -> bool: # Avoid frame timing affecting the geometry test.
        return true # Allow generation to continue.

func _initialize() -> void: # Start after class registration.
    _run.call_deferred() # Allow asynchronous generator calls.

func _signature(house: Node3D) -> Array: # Capture mesh and collision data together.
    var result: Array = [] # Retain ordered geometry signatures.
    for child: Node in house.get_children(): # Inspect generated components.
        if child is MeshInstance3D: # Compare final mesh arrays.
            result.append(hash(var_to_bytes(child.mesh.surface_get_arrays(0)))) # Include positions, normals and topology.
        elif child is StaticBody3D: # Compare collision ownership and shape data.
            for collider: CollisionShape3D in child.get_children(): # Inspect each collision shape.
                result.append(collider.transform) # Compare local collider placement.
                if collider.shape is BoxShape3D: # Compare solid wall and footing dimensions.
                    result.append(collider.shape.size) # Retain the box bounds.
                elif collider.shape is ConvexPolygonShape3D: # Compare roof collision geometry.
                    result.append(collider.shape.points) # Retain the roof hull.
    result.append(house.get_meta("bounds")) # Compare combined building bounds.
    return result # Return a deterministic geometry signature.

func _run() -> void: # Cover every layout and both roof styles.
    var scheduler: ImmediateScheduler = ImmediateScheduler.new() # Supply deterministic checkpoints.
    for layout: int in range(1, 7): # Exercise all supported building silhouettes.
        for roof: int in range(1, 3): # Exercise slate and thatch roofs.
            var recipe: HouseRecipe = HouseRecipe.new() # Prepare a reproducible recipe.
            recipe.seed_value = layout * 100 + roof # Seed both construction paths identically.
            recipe.layout = layout # Select the current layout.
            recipe.wall_style = (layout + roof) % 4 + 1 # Cover every wall style.
            recipe.roof_style = roof # Select the current roof style.
            var immediate: Node3D = HouseGeometry.new().build(recipe) # Build synchronous geometry.
            var incremental: Node3D = await HouseGeometry.new().build_incremental(recipe, true, scheduler) # Build scheduled geometry.
            assert(incremental != null) # Require completed incremental construction.
            assert(_signature(immediate) == _signature(incremental)) # Keep mesh and collision output identical across build paths.
            immediate.free() # Release synchronous geometry.
            incremental.free() # Release incremental geometry.
    scheduler.free() # Release the test scheduler.
    print("PASS simpler buildings: all layouts, both roofs, all wall styles, matching synchronous/incremental mesh buffers, bounds and collisions") # Report successful parity checks.
    quit() # Complete the test.
