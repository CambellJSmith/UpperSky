extends RefCounted # Keep deterministic camp population generation separate from scenery.
class_name CampPopulation # Share the same residents between both streaming paths.

static func count(seed_value: int) -> int: # Resolve the shared tent and resident count.
    var rng: RandomNumberGenerator = RandomNumberGenerator.new() # Avoid consuming scenery randomness.
    rng.seed = hash("camp-population:%d" % seed_value) # Keep camp membership stable across reloads.
    return rng.randi_range(1, 4) # Provide one tent for each camper.

static func definitions(camp: Dictionary) -> Array[Dictionary]: # Build short unobstructed routes in the checked clearing.
    var result: Array[Dictionary] = [] # Retain a strongly typed resident collection.
    var centre: Vector2 = camp.position # Anchor every route to its owning camp.
    var residents: int = count(camp.seed) # Match the geometry population exactly.
    for index: int in range(residents): # Give each camper an independent identity and route.
        var seed_value: int = hash("camp-resident:%d:%d" % [camp.seed, index]) # Preserve loot and health across streaming.
        var rng: RandomNumberGenerator = RandomNumberGenerator.new() # Isolate resident appearance randomness.
        rng.seed = seed_value # Reproduce appearance after unloading.
        var route: Array[Vector2] = [] # Keep walking around the outside of the tent ring.
        for step: int in range(16): # Approximate a circle without cutting through the fire.
            var angle: float = float(camp.yaw) + TAU * float(step + index * 4) / 16.0 # Space resident starting positions.
            route.append(centre + Vector2(cos(angle), sin(angle)) * (10.0 + float(index) * 0.15)) # Avoid tents, stumps and the chest.
        result.append({"route": route, "role": "camper", "seed": seed_value, "model": rng.randi_range(0, 2), "start": 0}) # Reuse human and orc combat, animation and persistence.
    return result # Return one resident definition for every tent.
