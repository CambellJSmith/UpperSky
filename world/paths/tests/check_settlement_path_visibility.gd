extends SceneTree
class Blocker extends RefCounted:
    var gate := Semaphore.new()
    func generate(): gate.wait(); return true
func _initialize(): run.call_deferred()
func run():
    var game=load("res://application/game/game.tscn").instantiate()
    root.add_child(game)
    game.get_node("SaveSystem").startup={}
    game.get_node("SaveSystem").set_process(false)
    var player: FirstPersonPlayer=game.get_node("DynamicEntities/Player")
    var terrain: InfiniteTerrain=game.get_node("World/Terrain")
    var scheduler: GenerationScheduler=game.get_node("GenerationScheduler")
    var blocker:=Blocker.new()
    assert(scheduler.submit(game,blocker.generate,func(_result): pass,true))
    while not player.is_physics_processing() or terrain.get_loaded_chunk_count()==0: await process_frame
    var network:=WorldPathNetwork.for_terrain(terrain)
    var town:=network._settlements.find_nearby(Vector2.ZERO,"town")
    var cell:=Vector2i((town.position/SettlementSampler.TOWN_CELL_SIZE).floor())
    game.get_node("World/Settlements")._build({"kind":"town","cell":cell,"definition":town})
    player.set_fly_mode_enabled(true)
    player.global_position=terrain.world_to_local_position(Vector3(town.position.x,terrain.get_height_at(town.position)+20,town.position.y))
    var paths: PathStreamer=game.get_node("World/Paths")
    var deadline:=Time.get_ticks_msec()+30000
    var count:=0
    while Time.get_ticks_msec()<deadline:
        await process_frame
        count=0
        for node in paths._chunks.values():
            if node.mesh!=null: count+=1
        if count>=2: break
    blocker.gate.post()
    assert(count>=2,"Actual village paths did not appear with regional workers blocked")
    print("PRODUCTION_LOCAL_PATHS ",count," meshes; city=",CityGeometry.is_city(town)," regional_completed=",network._chunks.size())
    game.queue_free(); await process_frame
    print("PASS actual game settlement paths visible before regional road planning")
    quit()
