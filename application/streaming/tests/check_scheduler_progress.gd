extends SceneTree

class BarrierJob extends RefCounted:
    var gate := Semaphore.new()
    func generate() -> int:
        gate.wait()
        return 42

class BusyTask extends RefCounted:
    var running := true
    func run(scheduler: GenerationScheduler):
        while running:
            scheduler.active_priority = 0
            if not await scheduler.checkpoint(scheduler): return
            while Time.get_ticks_usec()<scheduler._deadline: pass

func _initialize(): run.call_deferred()
func low_priority(scheduler: GenerationScheduler, results: Array):
    scheduler.active_priority = 2
    if await scheduler.checkpoint(scheduler): results.append(true)

func run():
    var scheduler := GenerationScheduler.new()
    root.add_child(scheduler)
    var barrier := BarrierJob.new()
    var background: Array = []
    var foreground: Array = []
    assert(scheduler.submit(scheduler,barrier.generate,func(data): background.append(data),true))
    assert(not scheduler.has_worker_room(true) and scheduler.has_worker_room(),"Background searches consumed the reserved terrain slot")
    assert(not scheduler.submit(scheduler,func(): return 0,func(_data): pass,true))
    assert(scheduler.submit(scheduler,func(): return 123,func(data): foreground.append(data)))
    var deadline := Time.get_ticks_msec()+1500
    while foreground.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
    barrier.gate.post()
    assert(foreground==[123],"A blocked road search prevented terrain work from completing")
    while background.is_empty(): await process_frame
    assert(background==[42])
    scheduler._deadline = Time.get_ticks_usec()-1
    var busy := BusyTask.new()
    busy.run(scheduler)
    var low: Array = []
    low_priority(scheduler,low)
    deadline = Time.get_ticks_msec()+1500
    while low.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
    busy.running = false
    assert(not low.is_empty(),"Repeated high-priority generation starved queued world chunks")
    await process_frame
    scheduler.queue_free()
    await process_frame
    print("PASS terrain worker reservation and progress under continuous high-priority generation")
    quit()
