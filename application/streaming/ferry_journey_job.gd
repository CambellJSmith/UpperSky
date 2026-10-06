extends RefCounted
class_name FerryJourneyJob

var definition: Dictionary
var seamless: bool
var _mutex := Mutex.new()
var _cancelled := false
func _init(data: Dictionary, use_seamless: bool):
    definition = data.duplicate(true)
    seamless = use_seamless
func cancel():
    _mutex.lock()
    _cancelled = true
    _mutex.unlock()
func is_cancelled() -> bool:
    _mutex.lock()
    var value := _cancelled
    _mutex.unlock()
    return value

func generate() -> Dictionary:
    var task := TerrainRoadJob.new({"key":"journey","start":Vector2.ZERO,"end":Vector2.ZERO,"kind":"connection","a":{"position":Vector2.ZERO},"b":{"position":Vector2.ZERO}},seamless)
    var terrain := task.create_sampler()
    var network := WorldPathNetwork.new(terrain,false)
    network.cancel_check = is_cancelled
    var walker := VillagerPopulationSampler.new(terrain)
    walker._paths = network
    var roads: Array[Dictionary] = []
    var settlements: Array[Dictionary] = []
    for dock in definition.docks:
        if is_cancelled(): terrain.free(); return {}
        var centre := Vector2i((dock.land/SettlementSampler.TOWN_CELL_SIZE).floor())
        var candidates: Array[Dictionary] = []
        for z in range(-2,3):
            for x in range(-2,3):
                if is_cancelled(): terrain.free(); return {}
                var town := network._settlements.sample_town(centre+Vector2i(x,z))
                if not town.is_empty() and dock.land.distance_to(town.position)<WorldPathNetwork.MAX_CONNECTION:
                    candidates.append(town)
        candidates.sort_custom(func(a,b):
            var cost_a: float = dock.land.distance_to(a.position) * (0.55 if CityGeometry.is_city(a) else 1.0)
            var cost_b: float = dock.land.distance_to(b.position) * (0.55 if CityGeometry.is_city(b) else 1.0)
            return cost_a < cost_b
        )
        var chosen: Dictionary = {}
        var road: Dictionary = {}
        for i in range(mini(6,candidates.size())):
            if is_cancelled(): terrain.free(); return {}
            var town: Dictionary = candidates[i]
            if not settlements.is_empty() and town.position == settlements[0].position: continue
            var exits := network.exits(town)
            exits.sort_custom(func(a,b): return dock.land.distance_squared_to(a)<dock.land.distance_squared_to(b))
            var link := {"key":"%s:%s:%s"%[definition.key,dock.land,town.position],"start":dock.land,"end":exits[0],"kind":"connection","a":{"position":dock.land},"b":{"position":town.position}}
            road = network._road.call(link,null,false)
            if not road.is_empty():
                var points: Array[Vector2] = []; points.assign(road.points)
                if walker.route_safe(points,false): chosen = town; break
        if chosen.is_empty(): terrain.free(); return {}
        roads.append(road)
        settlements.append({"position":chosen.position,"kind":"city" if CityGeometry.is_city(chosen) else "town"})
    terrain.free()
    return {"roads":roads,"settlements":settlements}
