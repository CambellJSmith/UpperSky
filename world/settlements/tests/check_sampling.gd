extends SceneTree
class TestTerrain extends InfiniteTerrain:
    var grade: float = 0.0
    var wet: bool = false
    func _ready(): pass
    func get_height_at(point: Vector2) -> float: return point.x*grade
    func has_water_at(_point: Vector2) -> bool: return wet
func _initialize(): run.call_deferred()
func same_town(a: Dictionary,b: Dictionary):
    assert(a["position"] == b["position"] and a["yaw"] == b["yaw"])
    assert(a["houses"].size() == b["houses"].size())
    for i in range(a["houses"].size()):
        assert(a["houses"][i]["position"] == b["houses"][i]["position"])
        assert(a["houses"][i]["recipe"].resolve() == b["houses"][i]["recipe"].resolve())
func run():
    var terrain = TestTerrain.new()
    var sampler = SettlementSampler.for_terrain(terrain)
    assert(SettlementSampler.for_terrain(terrain) == sampler)
    var homes = 0
    var example: Dictionary = {}
    var town_example: Dictionary = {}
    for z in range(-10,10):
        for x in range(-10,10):
            var home = sampler.sample_homestead(Vector2i(x,z))
            if home.is_empty(): continue
            homes += 1
            example = home
            assert(home["recipe"].floors == 1)
            assert(home["recipe"].roof_style == HouseRecipe.RoofStyle.THATCH)
            assert(home["recipe"].wall_style in [HouseRecipe.WallStyle.WOOD,HouseRecipe.WallStyle.STONE])
            assert(sampler.is_clearing(home["position"]))
            assert(not sampler._within_town(home["position"],30))
            var other = SettlementSampler.new(terrain).sample_homestead(Vector2i(x,z))
            assert(other["position"] == home["position"])
            assert(other["recipe"].resolve() == home["recipe"].resolve())
    assert(homes > 0 and homes < 60)
    for z in range(-2,3):
        for x in range(-2,3):
            var town = sampler.sample_town(Vector2i(x,z))
            if town.is_empty(): continue
            town_example = town
            same_town(town,SettlementSampler.new(terrain).sample_town(Vector2i(x,z)))
            assert(town["houses"].size() >= 8 and town["houses"].size() <= 16)
            assert(sampler.is_clearing(town["position"]))
            var previous: Array[Dictionary] = []
            var styles = {}
            for house in town["houses"]:
                assert(sampler._plot_clear(house["offset"],house["local_yaw"],house["bounds"],previous))
                previous.append(house)
                styles[house["recipe"].layout] = true
                var midpoint = (house["path_start"]+house["path_end"])*.5
                assert(sampler.is_clearing(town["position"]+SettlementSampler.rotate(midpoint,town["yaw"])))
            assert(styles.size() >= 2)
    assert(not example.is_empty() and not town_example.is_empty())
    var roads = SettlementGeometry.new().build_furniture(sampler,town_example)
    assert(roads.get_child_count() == 1)
    assert(roads.get_node_or_null("VillageWell") != null)
    roads.free()
    terrain.wet = true
    var wet = SettlementSampler.new(terrain)
    for x in range(-8,9):
        assert(wet.sample_homestead(Vector2i(x,0)).is_empty())
        assert(wet.sample_town(Vector2i(x,0)).is_empty())
    terrain.wet = false
    terrain.grade = .6
    var steep = SettlementSampler.new(terrain)
    for x in range(-8,9):
        assert(steep.sample_homestead(Vector2i(x,0)).is_empty())
        assert(steep.sample_town(Vector2i(x,0)).is_empty())
    terrain.free()
    print("PASS: rare primitive homes, varied street-facing towns, seeded repeatability, non-overlapping lots, shared clearing/paths, village furniture, water and steep-slope rejection.")
    quit()
