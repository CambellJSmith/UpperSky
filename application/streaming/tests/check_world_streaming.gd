extends SceneTree

class BarrierJob extends RefCounted:
    var gate := Semaphore.new()
    func generate() -> int:
        gate.wait()
        return 0

func _initialize(): run.call_deferred()
func counts(decorations: WorldDecorationStreamer) -> Vector2i:
    var result := Vector2i.ZERO
    for chunk in decorations._chunks.values():
        for placement in chunk._placements:
            if placement.kind==WorldDecorationPlacement.Kind.TREE: result.x += 1
            else: result.y += 1
    return result

func wait_until(check: Callable, seconds: float) -> bool:
    var deadline := Time.get_ticks_msec()+int(seconds*1000)
    while Time.get_ticks_msec()<deadline:
        if check.call(): return true
        await process_frame
    return check.call()

func run():
    var game: Node3D = load("res://application/game/game.tscn").instantiate()
    root.add_child(game)
    game.get_node("SaveSystem").startup = {}
    game.get_node("SaveSystem").set_process(false)
    var terrain: InfiniteTerrain = game.get_node("World/Terrain")
    var player: FirstPersonPlayer = game.get_node("DynamicEntities/Player")
    var decorations: WorldDecorationStreamer = game.get_node("WorldDecorations")
    var scheduler: GenerationScheduler = game.get_node("GenerationScheduler")
    # Keep the road/ferry search slot blocked throughout movement. Terrain,
    # trees, rocks and ground cover must continue independently of its result.
    var barrier := BarrierJob.new()
    assert(scheduler.submit(scheduler,barrier.generate,func(_data): pass,true))
    var spawned := await wait_until(func(): return player.is_physics_processing() and terrain._chunks.size()>=9,10)
    player.set_fly_mode_enabled(true)
    var populated := await wait_until(func():
        var objects := counts(decorations)
        return terrain._chunks.size()>40 and objects.x>0 and objects.y>0 and game.get_node("GroundFlora")._chunks.size()>0 and game.get_node("DenseGroundCover")._applied_mask_revision>=0
    ,30)
    print("INITIAL terrain ",terrain._chunks.size()," decorations ",decorations._chunks.size()," trees/rocks ",counts(decorations))
    var old_terrain := terrain._chunks.keys()
    var old_decor := decorations._chunks.keys()
    var world := terrain.local_to_world_position(player.global_position)
    world.x += 1024
    world.y = terrain.get_height_at(Vector2(world.x,world.z))+80
    player.global_position = terrain.world_to_local_position(world)
    player.velocity = Vector3.ZERO
    var moved := await wait_until(func():
        var new_ground := 0
        var new_objects := 0
        for cell in terrain._chunks:
            if cell not in old_terrain: new_ground += 1
        for cell in decorations._chunks:
            if cell not in old_decor: new_objects += 1
        return new_ground>=8 and new_objects>=3
    ,35)
    print("MOVED terrain ",terrain._chunks.size()," decorations ",decorations._chunks.size()," trees/rocks ",counts(decorations))
    barrier.gate.post()
    var grass: DenseGroundCoverStreamer = game.get_node("DenseGroundCover")
    grass._profile__update_density_lods()
    var ground_material: ShaderMaterial = terrain._mesh_builder._terrain_material
    assert(ground_material.get_shader_parameter("grass_detail_enabled"))
    assert(ground_material.get_shader_parameter("grass_map") == grass._terrain_texture)
    assert(ground_material.get_shader_parameter("grass_world_origin") == terrain._world_origin_offset)
    var player_point := Vector2(world.x,world.z)
    assert(ground_material.get_shader_parameter("grass_player_position").distance_to(player_point)<1.0)
    assert(spawned and populated and moved,"World streaming stalled while regional road searches were unavailable")
    # A road that finishes after decoration placement must clear its corridor.
    var network := WorldPathNetwork.for_terrain(terrain)
    var cell: Vector2i = decorations._chunks.keys()[0]
    var empty_roads: Array[Dictionary] = []
    network._chunks[cell] = empty_roads
    network.chunk_routes_ready.emit(cell)
    assert(not decorations._chunks.has(cell) or decorations._path_dirty.has(cell))
    game.queue_free()
    await process_frame
    print("PASS fresh startup, trees/boulders/grass, continued terrain/decorations after a kilometre of movement, blocked regional search and late mask refresh")
    quit()
