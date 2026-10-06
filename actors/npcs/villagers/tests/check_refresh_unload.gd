extends SceneTree

class PausingScheduler extends GenerationScheduler:
    signal resume_checkpoint
    var calls = 0
    func checkpoint(_owner: Node = null) -> bool:
        calls += 1
        if calls <= 2: await resume_checkpoint
        return true

class EmptySampler extends VillagerPopulationSampler:
    func travellers_incremental(_cell: Vector2i, _scheduler: GenerationScheduler) -> Array[Dictionary]:
        return []

var finished = false
func _initialize(): run.call_deferred()

func refresh(population, scheduler):
    await population._refresh_incremental(Vector2.ZERO, scheduler)
    finished = true

func run():
    # A settlement may unload while population refresh awaits its next slice.
    var population = VillagerPopulationStreamer.new()
    var settlements = SettlementStreamer.new()
    var scheduler = PausingScheduler.new()
    var terrain = InfiniteTerrain.new()
    population._settlements = settlements
    population._sampler = EmptySampler.new(terrain)
    var cell = Vector2i(-1, -2)
    var town = Node3D.new()
    var home = Node3D.new()
    settlements._towns[cell] = town
    settlements._homes[cell] = home
    refresh(population, scheduler)
    assert(scheduler.calls == 1 and not finished)
    settlements._towns.erase(cell)
    town.free()
    scheduler.resume_checkpoint.emit()
    assert(scheduler.calls == 2 and not finished)
    settlements._homes.erase(cell)
    home.free()
    scheduler.resume_checkpoint.emit()
    assert(finished and population._groups.is_empty())
    population.free()
    settlements.free()
    terrain.free()
    scheduler.free()
    print("PASS: town and home unloading during suspended NPC refresh")
    quit()
