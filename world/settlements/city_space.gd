extends Node3D
class_name CitySpace

signal build_progress(message: String)

var obstacles: Array[Rect2] = []
var definition: Dictionary
var house_count := 0
var resident_count := 0
var knight_count := 0
var king_count := 0
var shadow_count := 0

func build(source: Dictionary) -> void:
    definition = source
    var rng := RandomNumberGenerator.new()
    rng.seed = source.seed
    CityGeometry.box(self,Vector3(228,1,228),Vector3(0,-.5,0),Color(.32,.39,.25))
    for side in [-1,1]:
        CityGeometry.wall(self,Vector2(side*112,-112),Vector2(side*112,112),12)
    CityGeometry.wall(self,Vector2(-112,-112),Vector2(112,-112),12)
    CityGeometry.wall(self,Vector2(-112,112),Vector2(-5,112),12)
    CityGeometry.wall(self,Vector2(5,112),Vector2(112,112),12)
    for x in [-108,108]:
        for z in [-108,108]: CityGeometry.tower(self,Vector3(x,0,z),15,4)
    for street in range(-96,97,24):
        CityGeometry.box(self,Vector3(5,.06,204),Vector3(street,.03,0),Color(.47,.44,.38),false)
        CityGeometry.box(self,Vector3(204,.06,5),Vector3(0,.03,street),Color(.47,.44,.38),false)
    CityGeometry.box(self,Vector3(44,.1,44),Vector3(0,.05,0),Color(.49,.47,.41),false)
    for z in [-84,-60,-36,-12,12,36,60,84]:
        for x in [-84,-60,-36,-12,12,36,60,84]:
            # Reserve the central square and the castle's keep and courtyard.
            if abs(x) < 24 and abs(z) < 24: continue
            if abs(x) < 48 and z < -48: continue
            var recipe := HouseRecipe.new()
            recipe.seed_value = rng.randi()
            recipe.layout = rng.randi_range(1,6)
            recipe.width = rng.randf_range(8,12)
            recipe.depth = rng.randf_range(9,13)
            if recipe.layout == HouseRecipe.Layout.CROSS: recipe.width = 6.0
            elif recipe.layout == HouseRecipe.Layout.L_SHAPED: recipe.width = 8.0
            recipe.floors = 1 if rng.randf()<.2 else rng.randi_range(2,3)
            recipe.wall_style = rng.randi_range(1,4)
            recipe.roof_style = HouseRecipe.RoofStyle.THATCH if rng.randf() < .25 else HouseRecipe.RoofStyle.SLATE
            var house := HouseGeometry.new().build(recipe)
            house.name = "CityHouse_%d" % house_count
            house.position = Vector3(x,0,z)
            house.rotation.y = PI if z < 0 else 0
            add_child(house)
            var bounds := SettlementSampler.house_bounds(recipe)
            # All houses fit inside their blocks; the generous navigation bounds keep patrols clear.
            obstacles.append(Rect2(Vector2(x,z)-Vector2(10,10),Vector2(20,20)))
            var door_z := float(z) + (bounds.size.y*.5+1) * (-1 if z >= 0 else 1)
            CityGeometry.box(self,Vector3(1.4,.08,12-absf(door_z-z)),Vector3(x,.04,(door_z+z+(-12 if z>=0 else 12))*.5),Color(.47,.44,.38),false)
            house_count += 1
            var block_route: Array[Vector2] = [Vector2(x-12,z-12),Vector2(x+12,z-12),Vector2(x+12,z+12),Vector2(x-12,z+12)]
            _npc(0 if house_count%2==0 else 1,"city_peasant",source.seed+house_count*113,block_route,house_count%4)
            resident_count += 1
            build_progress.emit("Building city… %d houses"%house_count)
            # Building and actor import are spread over frames behind the loading screen.
            await get_tree().process_frame
    CityGeometry.castle(self)
    obstacles.append(Rect2(-14,-102,28,23))
    obstacles.append(Rect2(-25,-108,3,50))
    obstacles.append(Rect2(22,-108,3,50))
    obstacles.append(Rect2(-25,-108,50,5))
    obstacles.append(Rect2(-25,-64,20,5))
    obstacles.append(Rect2(5,-64,20,5))
    var court: Array[Vector2] = [Vector2(-9,-72),Vector2(9,-72),Vector2(9,-67),Vector2(-9,-67)]
    _npc(11,"city_king",source.seed+900001,court,0)
    king_count = 1
    var shadow_route: Array[Vector2] = [Vector2(-12,-77),Vector2(12,-77),Vector2(12,-74),Vector2(-12,-74)]
    _npc(12,"city_shadow",source.seed+900050,shadow_route,0)
    shadow_count = 1
    for i in range(6):
        var patrol: Array[Vector2] = []
        patrol.assign(court if i < 2 else [Vector2(-48,-48),Vector2(48,-48),Vector2(48,96),Vector2(-48,96)])
        _npc(9,"city_knight",source.seed+900100+i*113,patrol,i%4)
        knight_count += 1
        await get_tree().process_frame
    # A fountain, stalls and benches give the square a purpose without blocking its streets.
    CityGeometry.box(self,Vector3(5,1.2,5),Vector3(12,.6,12),CityGeometry.STONE)
    CityGeometry.box(self,Vector3(4,.1,4),Vector3(12,1.25,12),Color(.16,.42,.5),false)
    obstacles.append(Rect2(9,9,6,6))
    for x in [-12,12]:
        CityGeometry.box(self,Vector3(5,1,2),Vector3(x,.5,-12),CityGeometry.WOOD)
        CityGeometry.box(self,Vector3(6,.15,3),Vector3(x,2.5,-12),Color(.55,.17,.12),false)
        for side in [-1,1]: CityGeometry.box(self,Vector3(.12,2.5,.12),Vector3(x+side*2.5,1.25,-12),CityGeometry.WOOD,false)
        obstacles.append(Rect2(x-3,-14,6,4))
    var chest := LootChest.new()
    chest.loot_key = "city:%d:castle"%source.seed
    chest.seed_value = source.seed
    chest.position = Vector3(15,0,-74)
    add_child(chest)
    obstacles.append(Rect2(14,-75,2,2))
    build_progress.emit("Preparing city scenery…")
    await CityStaticBatch.build(self)

func _npc(model: int, role: String, seed_value: int, points: Array[Vector2], start: int) -> void:
    var npc := Villager.new()
    npc.name = "%s_%d"%[role,seed_value]
    npc.configure_space(self,{"model":model,"role":role,"seed":seed_value,"route":points,"start":start})
    add_child(npc)

func is_walkable(point: Vector2) -> bool:
    if absf(point.x) > 108 or absf(point.y) > 108: return false
    for bounds in obstacles:
        if bounds.grow(.4).has_point(point): return false
    return true

func persist_actors() -> void:
    for child in get_children():
        if child is Villager:
            child._loot_record["city_position"] = child.world_position
            child._loot_record["city_waypoint"] = child._waypoint
