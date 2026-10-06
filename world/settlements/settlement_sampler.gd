extends RefCounted
class_name SettlementSampler

const HOMESTEAD_CELL_SIZE: float = 768.0
const HOMESTEAD_CHANCE: float = .15
const TOWN_CELL_SIZE: float = 3072.0
const TOWN_CHANCE: float = .90
const MIN_TOWN_HOUSES: int = 8
const CACHE_LIMIT: int = 256
static var _shared: Dictionary = {}

var _terrain: InfiniteTerrain
var _ground: CampSampler
var _homesteads: Dictionary = {}
var _towns: Dictionary = {}

static func for_terrain(terrain: InfiniteTerrain) -> SettlementSampler:
    var id: int = terrain.get_instance_id()
    if _shared.has(id):
        var existing = (_shared[id] as WeakRef).get_ref()
        if existing != null:
            return existing
    if _shared.size() > 16:
        for key in _shared.keys():
            if (_shared[key] as WeakRef).get_ref() == null:
                _shared.erase(key)
    var sampler = SettlementSampler.new(terrain)
    _shared[id] = weakref(sampler)
    return sampler

func _init(terrain: InfiniteTerrain):
    _terrain = terrain
    _ground = CampSampler.new(terrain)

static func rotate(point: Vector2, yaw: float) -> Vector2:
    # Match Node3D's Y rotation in the horizontal X/Z plane.
    return point.rotated(-yaw)

func ground_height(point: Vector2) -> float:
    return _ground.ground_height(point)

func sample_homestead(cell: Vector2i) -> Dictionary:
    if _homesteads.has(cell):
        return _homesteads[cell]
    var rng = RandomNumberGenerator.new()
    rng.seed = hash("homestead:%d:%d:%d"%[TerrainHeightSampler.WORLD_SEED,cell.x,cell.y])
    var result: Dictionary = {}
    if rng.randf() < HOMESTEAD_CHANCE:
        var recipe = HouseRecipe.new()
        recipe.seed_value = rng.randi()
        recipe.layout = HouseRecipe.Layout.COTTAGE
        recipe.floors = 1
        recipe.wall_style = HouseRecipe.WallStyle.WOOD if rng.randf() < .65 else HouseRecipe.WallStyle.STONE
        recipe.roof_style = HouseRecipe.RoofStyle.THATCH
        recipe.include_porch = rng.randf() < .3
        var yaw: float = rng.randf_range(0,TAU)
        for attempt in range(12):
            var point = Vector2(cell)*HOMESTEAD_CELL_SIZE+Vector2(rng.randf_range(32,HOMESTEAD_CELL_SIZE-32),rng.randf_range(32,HOMESTEAD_CELL_SIZE-32))
            if _within_town(point,30.0):
                continue
            var patch = _house_patch(point,yaw,recipe,.90,.13)
            if not patch.is_empty():
                recipe.foundation_extension = patch["highest"]-patch["lowest"]+.12
                result = {"position":point,"height":patch["highest"]+.015,"yaw":yaw,"recipe":recipe,"bounds":house_bounds(recipe),"seed":recipe.seed_value}
                break
    _cache(_homesteads,cell,result)
    return result

func sample_town(cell: Vector2i) -> Dictionary:
    if _towns.has(cell):
        return _towns[cell]
    var rng = RandomNumberGenerator.new()
    rng.seed = hash("town:%d:%d:%d"%[TerrainHeightSampler.WORLD_SEED,cell.x,cell.y])
    var result: Dictionary = {}
    if rng.randf() < TOWN_CHANCE:
        for attempt in range(24):
            var centre = Vector2(cell)*TOWN_CELL_SIZE+Vector2(rng.randf_range(180,TOWN_CELL_SIZE-180),rng.randf_range(180,TOWN_CELL_SIZE-180))
            var yaw: float = rng.randf_range(0,TAU)
            if not _town_ground(centre,yaw):
                continue
            var seed_value: int = rng.randi()
            var town = make_town(centre,yaw,seed_value,true)
            if not town.is_empty():
                result = town
                break
    _cache(_towns,cell,result)
    return result

func make_town(centre: Vector2, yaw: float, seed_value: int, ground_checked: bool = false) -> Dictionary:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        return _profile_make_town(centre, yaw, seed_value, ground_checked)
    var _profile_token = RuntimeProfiler.begin("settlements.plan_town")
    var _profile_result = _profile_make_town(centre, yaw, seed_value, ground_checked)
    RuntimeProfiler.end(_profile_token)
    return _profile_result

func _profile_make_town(centre: Vector2, yaw: float, seed_value: int, ground_checked: bool = false) -> Dictionary:
    # This also serves deterministic previews and tests, using the same actual placement rules.
    if not ground_checked and not _town_ground(centre,yaw):
        return {}
    var rng = RandomNumberGenerator.new()
    rng.seed = seed_value
    var plots: Array = []
    for side in [-1,1]:
        for z in [-45.0,-21.0,21.0,45.0]:
            plots.append({"offset":Vector2(side*rng.randf_range(12.8,14.2),z+rng.randf_range(-1.5,1.5)),"yaw":side*PI*.5})
        for x in [30.0,53.0]:
            for z_side in [-1,1]:
                plots.append({"offset":Vector2(side*x,z_side*rng.randf_range(12.8,14.2)),"yaw":0.0 if z_side==1 else PI})
    var houses: Array[Dictionary] = []
    var styles: Array = [HouseRecipe.Layout.COTTAGE,HouseRecipe.Layout.JETTIED,HouseRecipe.Layout.L_SHAPED,HouseRecipe.Layout.CROSS,HouseRecipe.Layout.LONGHALL,HouseRecipe.Layout.TOWER]
    for i in range(plots.size()):
        var plot: Dictionary = plots[i]
        var recipe = HouseRecipe.new()
        recipe.seed_value = rng.randi()
        recipe.layout = styles[(i+rng.randi_range(0,5))%styles.size()]
        recipe.wall_style = rng.randi_range(1,4)
        recipe.roof_style = HouseRecipe.RoofStyle.THATCH if rng.randf() < .35 else HouseRecipe.RoofStyle.SLATE
        recipe.width = rng.randf_range(4.6,7.2)
        recipe.depth = rng.randf_range(5.5,8.5)
        recipe.floors = 1 if recipe.layout in [HouseRecipe.Layout.COTTAGE,HouseRecipe.Layout.LONGHALL] else rng.randi_range(2,3)
        recipe.include_porch = rng.randf() < .45
        var point: Vector2 = centre+rotate(plot["offset"],yaw)
        var facing: float = yaw+plot["yaw"]
        var patch = _house_patch(point,facing,recipe,1.35,.18)
        if patch.is_empty():
            continue
        var bounds = house_bounds(recipe)
        # Expanded corners must clear both streets and earlier plots.
        if not _plot_clear(plot["offset"],plot["yaw"],bounds,houses):
            continue
        var parameters = recipe.resolve()
        var door: Vector2 = plot["offset"]+rotate(Vector2(0,-parameters["depth"]*.5-.72),plot["yaw"])
        var main_road = Vector2(0,clampf(door.y,-74,74))
        var crossing_road = Vector2(clampf(door.x,-74,74),0)
        var path_start: Vector2 = main_road if door.distance_squared_to(main_road) < door.distance_squared_to(crossing_road) else crossing_road
        if not _walkable_path(centre,yaw,path_start,door):
            continue
        recipe.foundation_extension = patch["highest"]-patch["lowest"]+.12
        houses.append({"position":point,"height":patch["highest"]+.015,"yaw":facing,"recipe":recipe,"bounds":bounds,"offset":plot["offset"],"local_yaw":plot["yaw"],"path_start":path_start,"path_end":door})
    if houses.size() < MIN_TOWN_HOUSES:
        return {}
    return {"position":centre,"height":ground_height(centre),"yaw":yaw,"seed":seed_value,"houses":houses,"radius":86.0}

static func house_bounds(recipe: HouseRecipe) -> Rect2:
    var p = recipe.resolve()
    var x_min: float = -p["width"]*.5-.8
    var x_max: float = p["width"]*.5+.8
    if p["layout"] in [HouseRecipe.Layout.L_SHAPED,HouseRecipe.Layout.CROSS]:
        x_max += 5.2
        if p["layout"] == HouseRecipe.Layout.CROSS:
            x_min -= 5.2
    var z_min: float = -p["depth"]*.5-(2.9 if p["porch"] else .8)
    var z_max: float = p["depth"]*.5+.8
    return Rect2(Vector2(x_min,z_min),Vector2(x_max-x_min,z_max-z_min))

func _house_patch(point: Vector2, yaw: float, recipe: HouseRecipe, max_variation: float, max_grade: float) -> Dictionary:
    var bounds = house_bounds(recipe)
    var lowest: float = INF
    var highest: float = -INF
    var x_steps: int = ceili(bounds.size.x/3.0)
    var z_steps: int = ceili(bounds.size.y/3.0)
    for z in range(z_steps+1):
        for x in range(x_steps+1):
            var local = bounds.position+Vector2(bounds.size.x*x/x_steps,bounds.size.y*z/z_steps)
            var sample: Vector2 = point+rotate(local,yaw)
            if not _safe_ground(sample) or _ground.is_clearing(sample) or TerrainPathSampler.get_wilderness_grass_suppression(sample) > .1:
                return {}
            var height: float = ground_height(sample)
            highest = maxf(highest,height)
            lowest = minf(lowest,height)
            if highest-lowest > max_variation:
                return {}
            if absf(ground_height(sample+Vector2(2,0))-height) > max_grade*2 or absf(ground_height(sample+Vector2(0,2))-height) > max_grade*2:
                return {}
    return {"lowest":lowest,"highest":highest}

func _safe_ground(point: Vector2) -> bool:
    if point.length() < 160.0 or _terrain.has_water_at(point) or BiomeProfile.is_lava(point):
        return false
    var biome = BiomeProfile.region_at(point)
    if biome["kind"] in [BiomeProfile.Kind.ICE_FLATS,BiomeProfile.Kind.VOLCANIC_ISLANDS] and BiomeProfile.weight(point,biome) > .35:
        return false
    return true

func _town_ground(centre: Vector2, yaw: float) -> bool:
    # Check the entire travelled cross and central plaza before allocating recipes.
    var lowest: float = INF
    var highest: float = -INF
    for axis in range(2):
        for distance in range(-76,77,4):
            for across in [-4.5,0.0,4.5]:
                var offset = Vector2(across,distance) if axis==0 else Vector2(distance,across)
                var point = centre+rotate(offset,yaw)
                if not _safe_ground(point) or _ground.is_clearing(point):
                    return false
                var height: float = ground_height(point)
                lowest = minf(lowest,height)
                highest = maxf(highest,height)
                if highest-lowest > 10.0:
                    return false
                if absf(ground_height(point+Vector2(2,0))-height) > .40 or absf(ground_height(point+Vector2(0,2))-height) > .40:
                    return false
    return true

static func _plot_aabb(offset: Vector2, yaw: float, bounds: Rect2) -> Rect2:
    var corners = [bounds.position,bounds.position+Vector2(bounds.size.x,0),bounds.end,bounds.position+Vector2(0,bounds.size.y)]
    var result = Rect2(offset+rotate(corners[0],yaw),Vector2.ZERO)
    for corner in corners:
        result = result.expand(offset+rotate(corner,yaw))
    return result.grow(1.0)

func _plot_clear(offset: Vector2, yaw: float, bounds: Rect2, houses: Array[Dictionary]) -> bool:
    var aabb = _plot_aabb(offset,yaw,bounds)
    for street in [Rect2(-4.5,-76,9,152),Rect2(-76,-4.5,152,9),Rect2(-8,-8,16,16)]:
        if aabb.intersects(street):
            return false
    for house in houses:
        if aabb.intersects(_plot_aabb(house["offset"],house["local_yaw"],house["bounds"])):
            return false
    return true

func _within_town(point: Vector2, margin: float = 0.0) -> bool:
    var cell = Vector2i(floori(point.x/TOWN_CELL_SIZE),floori(point.y/TOWN_CELL_SIZE))
    var town = sample_town(cell)
    return not town.is_empty() and point.distance_to(town["position"]) < town["radius"]+margin

func is_clearing(point: Vector2, padding: float = 0.0) -> bool:
    if WorldPathNetwork.for_terrain(_terrain).get_local_mask(point,true,padding) > .05: return true
    var town_cell = Vector2i(floori(point.x/TOWN_CELL_SIZE),floori(point.y/TOWN_CELL_SIZE))
    var town = sample_town(town_cell)
    if not town.is_empty() and point.distance_squared_to(town["position"]) < pow(town["radius"]+padding,2):
        for house in town["houses"]:
            var relative = rotate(point-house["position"],-house["yaw"])
            if house["bounds"].grow(2.5+padding).has_point(relative):
                return true
    var home_cell = Vector2i(floori(point.x/HOMESTEAD_CELL_SIZE),floori(point.y/HOMESTEAD_CELL_SIZE))
    var home = sample_homestead(home_cell)
    if not home.is_empty():
        var relative = rotate(point-home["position"],-home["yaw"])
        if home["bounds"].grow(2.5+padding).has_point(relative):
            return true
    return false

func _cache(cache: Dictionary, cell: Vector2i, value: Dictionary):
    if cache.size() >= CACHE_LIMIT:
        cache.erase(cache.keys()[0])
    cache[cell] = value

static func _segment_distance(point: Vector2, start: Vector2, end: Vector2) -> float:
    var segment = end-start
    var t: float = clampf((point-start).dot(segment)/maxf(segment.length_squared(),.0001),0,1)
    return point.distance_to(start+segment*t)

func _walkable_path(centre: Vector2, yaw: float, start: Vector2, end: Vector2) -> bool:
    var steps: int = maxi(1,ceili(start.distance_to(end)/2.0))
    var previous: float = 0.0
    for i in range(steps+1):
        var point = centre+rotate(start.lerp(end,float(i)/steps),yaw)
        if not _safe_ground(point) or _ground.is_clearing(point):
            return false
        var height: float = ground_height(point)
        if i > 0 and absf(height-previous) > .45:
            return false
        previous = height
    return true

func find_nearby(point: Vector2, kind: String) -> Dictionary:
    var size: float = TOWN_CELL_SIZE if kind=="town" else HOMESTEAD_CELL_SIZE
    var centre = Vector2i(floori(point.x/size),floori(point.y/size))
    var max_radius: int = 2 if kind=="town" else 6
    for ring in range(max_radius+1):
        var best: Dictionary = {}
        var distance: float = INF
        for z in range(-ring,ring+1):
            for x in range(-ring,ring+1):
                if maxi(absi(x),absi(z)) != ring:
                    continue
                var cell = centre+Vector2i(x,z)
                var definition = sample_town(cell) if kind=="town" else sample_homestead(cell)
                if not definition.is_empty() and point.distance_squared_to(definition["position"]) < distance:
                    best = definition
                    distance = point.distance_squared_to(definition["position"])
        if not best.is_empty():
            return best
    return {}

func _town_ground_incremental(centre: Vector2, yaw: float, scheduler: GenerationScheduler) -> bool:
    # Check the entire travelled cross and central plaza before allocating recipes.
    var lowest: float = INF
    var highest: float = -INF
    for axis in range(2):
        if not await scheduler.checkpoint(): return false
        for distance in range(-76,77,4):
            if not await scheduler.checkpoint(): return false
            for across in [-4.5,0.0,4.5]:
                if not await scheduler.checkpoint(): return false
                var offset = Vector2(across,distance) if axis==0 else Vector2(distance,across)
                var point = centre+rotate(offset,yaw)
                if not _safe_ground(point) or _ground.is_clearing(point):
                    return false
                var height: float = ground_height(point)
                lowest = minf(lowest,height)
                highest = maxf(highest,height)
                if highest-lowest > 10.0:
                    return false
                if absf(ground_height(point+Vector2(2,0))-height) > .40 or absf(ground_height(point+Vector2(0,2))-height) > .40:
                    return false
    return true

func _house_patch_incremental(point: Vector2, yaw: float, recipe: HouseRecipe, max_variation: float, max_grade: float, scheduler: GenerationScheduler) -> Dictionary:
    var bounds = house_bounds(recipe)
    var lowest: float = INF
    var highest: float = -INF
    var x_steps: int = ceili(bounds.size.x/3.0)
    var z_steps: int = ceili(bounds.size.y/3.0)
    for z in range(z_steps+1):
        if not await scheduler.checkpoint(): return {}
        for x in range(x_steps+1):
            if not await scheduler.checkpoint(): return {}
            var local = bounds.position+Vector2(bounds.size.x*x/x_steps,bounds.size.y*z/z_steps)
            var sample: Vector2 = point+rotate(local,yaw)
            if not _safe_ground(sample) or _ground.is_clearing(sample) or TerrainPathSampler.get_wilderness_grass_suppression(sample) > .1:
                return {}
            var height: float = ground_height(sample)
            highest = maxf(highest,height)
            lowest = minf(lowest,height)
            if highest-lowest > max_variation:
                return {}
            if absf(ground_height(sample+Vector2(2,0))-height) > max_grade*2 or absf(ground_height(sample+Vector2(0,2))-height) > max_grade*2:
                return {}
    return {"lowest":lowest,"highest":highest}

func _walkable_path_incremental(centre: Vector2, yaw: float, start: Vector2, end: Vector2, scheduler: GenerationScheduler) -> bool:
    var steps: int = maxi(1,ceili(start.distance_to(end)/2.0))
    var previous: float = 0.0
    for i in range(steps+1):
        if not await scheduler.checkpoint(): return false
        var point = centre+rotate(start.lerp(end,float(i)/steps),yaw)
        if not _safe_ground(point) or _ground.is_clearing(point):
            return false
        var height: float = ground_height(point)
        if i > 0 and absf(height-previous) > .45:
            return false
        previous = height
    return true

func make_town_incremental(centre: Vector2, yaw: float, seed_value: int, ground_checked: bool, scheduler: GenerationScheduler) -> Dictionary:
    # This also serves deterministic previews and tests, using the same actual placement rules.
    if not ground_checked and not await _town_ground_incremental(centre,yaw, scheduler):
        return {}
    var rng = RandomNumberGenerator.new()
    rng.seed = seed_value
    var plots: Array = []
    for side in [-1,1]:
        if not await scheduler.checkpoint(): return {}
        for z in [-45.0,-21.0,21.0,45.0]:
            if not await scheduler.checkpoint(): return {}
            plots.append({"offset":Vector2(side*rng.randf_range(12.8,14.2),z+rng.randf_range(-1.5,1.5)),"yaw":side*PI*.5})
        for x in [30.0,53.0]:
            if not await scheduler.checkpoint(): return {}
            for z_side in [-1,1]:
                if not await scheduler.checkpoint(): return {}
                plots.append({"offset":Vector2(side*x,z_side*rng.randf_range(12.8,14.2)),"yaw":0.0 if z_side==1 else PI})
    var houses: Array[Dictionary] = []
    var styles: Array = [HouseRecipe.Layout.COTTAGE,HouseRecipe.Layout.JETTIED,HouseRecipe.Layout.L_SHAPED,HouseRecipe.Layout.CROSS,HouseRecipe.Layout.LONGHALL,HouseRecipe.Layout.TOWER]
    for i in range(plots.size()):
        if not await scheduler.checkpoint(): return {}
        var plot: Dictionary = plots[i]
        var recipe = HouseRecipe.new()
        recipe.seed_value = rng.randi()
        recipe.layout = styles[(i+rng.randi_range(0,5))%styles.size()]
        recipe.wall_style = rng.randi_range(1,4)
        recipe.roof_style = HouseRecipe.RoofStyle.THATCH if rng.randf() < .35 else HouseRecipe.RoofStyle.SLATE
        recipe.width = rng.randf_range(4.6,7.2)
        recipe.depth = rng.randf_range(5.5,8.5)
        recipe.floors = 1 if recipe.layout in [HouseRecipe.Layout.COTTAGE,HouseRecipe.Layout.LONGHALL] else rng.randi_range(2,3)
        recipe.include_porch = rng.randf() < .45
        var point: Vector2 = centre+rotate(plot["offset"],yaw)
        var facing: float = yaw+plot["yaw"]
        var patch = await _house_patch_incremental(point,facing,recipe,1.35,.18, scheduler)
        if patch.is_empty():
            continue
        var bounds = house_bounds(recipe)
        # Expanded corners must clear both streets and earlier plots.
        if not _plot_clear(plot["offset"],plot["yaw"],bounds,houses):
            continue
        var parameters = recipe.resolve()
        var door: Vector2 = plot["offset"]+rotate(Vector2(0,-parameters["depth"]*.5-.72),plot["yaw"])
        var main_road = Vector2(0,clampf(door.y,-74,74))
        var crossing_road = Vector2(clampf(door.x,-74,74),0)
        var path_start: Vector2 = main_road if door.distance_squared_to(main_road) < door.distance_squared_to(crossing_road) else crossing_road
        if not await _walkable_path_incremental(centre,yaw,path_start,door, scheduler):
            continue
        recipe.foundation_extension = patch["highest"]-patch["lowest"]+.12
        houses.append({"position":point,"height":patch["highest"]+.015,"yaw":facing,"recipe":recipe,"bounds":bounds,"offset":plot["offset"],"local_yaw":plot["yaw"],"path_start":path_start,"path_end":door})
    if houses.size() < MIN_TOWN_HOUSES:
        return {}
    return {"position":centre,"height":ground_height(centre),"yaw":yaw,"seed":seed_value,"houses":houses,"radius":86.0}

func sample_town_incremental(cell: Vector2i, scheduler: GenerationScheduler) -> Dictionary:
    if _towns.has(cell):
        return _towns[cell]
    var rng = RandomNumberGenerator.new()
    rng.seed = hash("town:%d:%d:%d"%[TerrainHeightSampler.WORLD_SEED,cell.x,cell.y])
    var result: Dictionary = {}
    if rng.randf() < TOWN_CHANCE:
        for attempt in range(24):
            if not await scheduler.checkpoint(): return {}
            var centre = Vector2(cell)*TOWN_CELL_SIZE+Vector2(rng.randf_range(180,TOWN_CELL_SIZE-180),rng.randf_range(180,TOWN_CELL_SIZE-180))
            var yaw: float = rng.randf_range(0,TAU)
            if not await _town_ground_incremental(centre,yaw, scheduler):
                continue
            var seed_value: int = rng.randi()
            var town = await make_town_incremental(centre,yaw,seed_value,true, scheduler)
            if not town.is_empty():
                result = town
                break
    _cache(_towns,cell,result)
    return result

func _within_town_incremental(point: Vector2, margin: float, scheduler: GenerationScheduler) -> bool:
    var cell = Vector2i(floori(point.x/TOWN_CELL_SIZE),floori(point.y/TOWN_CELL_SIZE))
    var town = await sample_town_incremental(cell, scheduler)
    return not town.is_empty() and point.distance_to(town["position"]) < town["radius"]+margin

func sample_homestead_incremental(cell: Vector2i, scheduler: GenerationScheduler) -> Dictionary:
    if _homesteads.has(cell):
        return _homesteads[cell]
    var rng = RandomNumberGenerator.new()
    rng.seed = hash("homestead:%d:%d:%d"%[TerrainHeightSampler.WORLD_SEED,cell.x,cell.y])
    var result: Dictionary = {}
    if rng.randf() < HOMESTEAD_CHANCE:
        var recipe = HouseRecipe.new()
        recipe.seed_value = rng.randi()
        recipe.layout = HouseRecipe.Layout.COTTAGE
        recipe.floors = 1
        recipe.wall_style = HouseRecipe.WallStyle.WOOD if rng.randf() < .65 else HouseRecipe.WallStyle.STONE
        recipe.roof_style = HouseRecipe.RoofStyle.THATCH
        recipe.include_porch = rng.randf() < .3
        var yaw: float = rng.randf_range(0,TAU)
        for attempt in range(12):
            if not await scheduler.checkpoint(): return {}
            var point = Vector2(cell)*HOMESTEAD_CELL_SIZE+Vector2(rng.randf_range(32,HOMESTEAD_CELL_SIZE-32),rng.randf_range(32,HOMESTEAD_CELL_SIZE-32))
            if await _within_town_incremental(point,30.0, scheduler):
                continue
            var patch = await _house_patch_incremental(point,yaw,recipe,.90,.13, scheduler)
            if not patch.is_empty():
                recipe.foundation_extension = patch["highest"]-patch["lowest"]+.12
                result = {"position":point,"height":patch["highest"]+.015,"yaw":yaw,"recipe":recipe,"bounds":house_bounds(recipe),"seed":recipe.seed_value}
                break
    _cache(_homesteads,cell,result)
    return result
