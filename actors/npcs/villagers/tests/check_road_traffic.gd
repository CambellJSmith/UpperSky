extends SceneTree
class FlatTerrain extends InfiniteTerrain:
    func _ready(): pass
class TrafficSampler extends VillagerPopulationSampler:
    var validations := 0
    func route_safe(_points: Array[Vector2],_closed: bool = true) -> bool:
        validations += 1
        return true
func _initialize(): run.call_deferred()
func run():
    var terrain := FlatTerrain.new()
    root.add_child(terrain)
    var sampler := TrafficSampler.new(terrain)
    var cell := Vector2i(4,4)
    var points: Array[Vector2] = []
    for i in range(33): points.append(Vector2(900+i*16,1152))
    var road := {"key":"traffic-test","kind":"arterial","from":points[0],"to":points[-1],"points":points}
    sampler._paths._roads[road.key]=road
    var sections: Array[Dictionary] = [road]
    sampler._paths._chunks[cell]=sections
    var previous: Array[Dictionary] = []
    var common := 0
    var total := 0
    for wave in range(100):
        sampler.set_traffic_wave(wave)
        var definitions := sampler.travellers(cell)
        assert(definitions.size()>=6 and definitions.size()<=10)
        assert(definitions==sampler.travellers(cell))
        var directions := {}
        var leaders := {}
        for npc in definitions:
            for old in previous: assert(old.seed!=npc.seed)
            assert(npc.journey.origin==points[0] and npc.journey.destination==points[-1])
            directions[npc.travel_direction]=true
            leaders[npc.leader_seed]=true
            if npc.model in [0,1,2]: common+=1
            if npc.seed==npc.leader_seed: assert(npc.model in [0,1,2])
            total+=1
        assert(directions.has(-1) and directions.has(1) and leaders.size()==2)
        previous=definitions
    assert(common>total*.85)
    assert(sampler.validations==1,"Traffic waves must reuse road safety validation")
    assert(VillagerPopulationStreamer.TRAFFIC_INTERVAL<300)
    assert(VillagerPopulationStreamer.MAX_NPCS-VillagerPopulationStreamer.RESIDENT_LIMIT>=24)
    terrain.free()
    print("PASS 100 replenishment waves, two opposite-direction parties, real endpoints, ",common,"/",total," peasants/orcs, unique identities, cached safety checks and reserved traveller budget")
    quit()
