extends SceneTree
class FlatTerrain extends InfiniteTerrain:
    func _ready(): pass
    func get_height_at(_point: Vector2) -> float: return 0.0
    func has_water_at(_point: Vector2) -> bool: return false
class WorkerProbe extends RefCounted:
    var entered := Semaphore.new()
    var released := Semaphore.new()
    var token := -2
    func run():
        token = RuntimeProfiler.begin("worker.outer")
        entered.post()
        released.wait()
        var nested := RuntimeProfiler.begin("worker.inner")
        var terrain := FlatTerrain.new()
        var sampler := SettlementSampler.new(terrain)
        sampler.make_town(Vector2(700,700),0.0,12345,true)
        terrain.free()
        RuntimeProfiler.end(nested)
        RuntimeProfiler.end(token)
func _initialize(): run.call_deferred()
func run():
    var profiler := RuntimeProfiler.new()
    root.add_child(profiler)
    profiler.start()
    var parent := RuntimeProfiler.begin("npcs.physics")
    var probe := WorkerProbe.new()
    var thread := Thread.new()
    assert(thread.start(probe.run)==OK)
    probe.entered.wait()
    var token: int = probe.token
    var depth := RuntimeProfiler._stack.size()
    var child := RuntimeProfiler.begin("main.nested")
    RuntimeProfiler.end(child)
    probe.released.post()
    thread.wait_to_finish()
    RuntimeProfiler.end(parent)
    assert(token==-1 and depth==1,"Worker scopes must never enter the main-thread stack")
    assert(RuntimeProfiler._stack.is_empty())
    assert(RuntimeProfiler._totals.has("npcs.physics") and RuntimeProfiler._totals.has("main.nested"))
    assert(not RuntimeProfiler._totals.has("worker.outer") and not RuntimeProfiler._totals.has("settlements.plan_town"))
    var old := RuntimeProfiler.begin("previous.capture")
    profiler.stop()
    profiler.start()
    var current := RuntimeProfiler.begin("current.capture")
    RuntimeProfiler.end(old)
    assert(RuntimeProfiler._stack.size()==1 and RuntimeProfiler._stack[0].token==current)
    RuntimeProfiler.end(current)
    assert(RuntimeProfiler._stack.is_empty() and RuntimeProfiler._totals["current.capture"].calls==1)
    profiler.stop()
    profiler.queue_free()
    await process_frame
    print("PASS simultaneous worker settlement planning and main-thread NPC scopes, nested self timing, and stale tokens across recording restart")
    quit()
