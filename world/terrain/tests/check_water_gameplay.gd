extends SceneTree # Exercises real water consumers against one production body query.

func _initialize() -> void: run.call_deferred() # Loads gameplay dependencies after the tree is available.

func run() -> void: # Checks occupied volume, camera immersion and corpse currents before startup streaming begins.
    var game: Node3D = load("res://application/game/game.tscn").instantiate() # Loads the real player, camera and water effect composition.
    root.add_child(game) # Initializes production terrain and gameplay services.
    var terrain: SeamlessInfiniteTerrain = game.get_node("World/Terrain") # Uses the real planned triangle query.
    var player: FirstPersonPlayer = game.get_node("DynamicEntities/Player") # Exercises the real swimming state machine.
    var view: UnderwaterView = game.get_node("UnderwaterView") # Exercises the actual camera immersion effect.
    var point: Vector2 = WaterBodyPlan.STARTING_LAKE_CENTRE # Selects a known contained basin with a clear bed.
    var water: Dictionary = terrain.get_water_sample_at(point) # Reads its authoritative occupied surface.
    assert(water.present and water.depth > 0.0) # Requires a real volume before testing immersion.
    var level: float = float(water.surface_height) # Shares the same actual surface with every consumer.
    player.global_position = Vector3(point.x, level - 3.0, point.y) # Places body and camera below the calm surface.
    player._update_water_state() # Resolves swimming through the production query path.
    view._process(0.0) # Resolves camera depth through the same query.
    assert(player._swimming_enabled and view._is_underwater) # Requires body and camera to agree on immersion.
    player.global_position.y = level + 5.0 # Raises body and camera above occupied water.
    player._update_water_state() # Resolves the dry vertical state.
    view._process(0.0) # Clears the underwater camera effect.
    assert(not player._swimming_enabled and not view._is_underwater) # Prevents water behaviour throughout the sky above a lake.
    var corpse: RagdollCorpse = RagdollCorpse.new() # Exercises the existing corpse water callback.
    game.add_child(corpse) # Registers the body with the real player and terrain references.
    corpse.global_position = Vector3(point.x, level + 20.0, point.y) # Places a falling corpse well above the surface.
    corpse.linear_velocity = Vector3(0.0, -4.0, 0.0) # Gives the corpse an observable downward velocity.
    corpse._physics_process(0.1) # Samples the actual occupied surface before applying water behaviour.
    assert(corpse.linear_velocity.y < 0.0) # Keeps an airborne corpse falling rather than floating above the lake.
    corpse.global_position.y = level - 0.5 # Moves the corpse into the occupied volume.
    corpse._physics_process(0.1) # Applies the existing immersed-corpse behaviour.
    assert(corpse.linear_velocity.y >= 0.0 and Vector2(corpse.linear_velocity.x, corpse.linear_velocity.z).is_zero_approx()) # Keeps closed-lake currents still.
    var river: Dictionary = BiomeProfile.region(Vector2i(-1, 0)) # Selects an explicit downstream-flowing reach.
    var river_point: Vector2 = Vector2(river.centre) + Vector2(BiomeProfile.river_x(0.0, float(river.phase)), 0.0) # Locates its centreline.
    var river_water: Dictionary = terrain.get_water_sample_at(river_point) # Reads the planned occupied river surface and direction.
    corpse.global_position = Vector3(river_point.x, float(river_water.surface_height) - 0.5, river_point.y) # Places the corpse inside that river volume.
    corpse._physics_process(0.1) # Applies the planned current instead of unrelated world sine waves.
    assert(corpse.linear_velocity.z > 0.0) # Requires downstream movement along the connected river.
    player.global_position = Vector3.ZERO # Visits the protected starting origin.
    player._update_water_state() # Resolves explicit dry occupancy.
    view._process(0.0) # Resolves the dry camera state.
    assert(not player._swimming_enabled and not view._is_underwater) # Keeps both consumers dry where no body exists.
    game.free() # Releases the composition before deferred startup work begins.
    print("PASS shared swimming/camera immersion, dry origin, falling corpses above lakes and planned river currents") # Reports real gameplay-consumer agreement.
    quit() # Completes the integration check.
