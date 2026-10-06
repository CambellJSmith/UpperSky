extends RefCounted
class_name CavePopulation
static func populate(dungeon: ProceduralDungeonWorld):
    var rng = RandomNumberGenerator.new()
    rng.seed = hash("cave-npcs:%s:%d"%[dungeon._region_coordinate,dungeon._dungeon_seed])
    var layout = dungeon._layout
    var used: Dictionary = {}
    var count = 0
    for attempt in range(160):
        if count >= 4: break
        var cell = layout.get_floor_cell_at(rng.randi_range(0,layout.get_floor_cell_count()-1))
        if Vector2(cell-layout.door_a_cell).length() < 5 or Vector2(cell-layout.door_b_cell).length() < 5 or used.has(cell): continue
        var neighbour = cell+Vector2i(1,0)
        for direction in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
            if layout.is_walkable(cell+direction): neighbour = cell+direction; break
        if not layout.is_walkable(neighbour): continue
        var a = DungeonGeometryBuilder.get_cell_center(layout,cell)
        var b = DungeonGeometryBuilder.get_cell_center(layout,neighbour)
        var route: Array[Vector2] = [Vector2(a.x,a.z),Vector2(b.x,b.z)]
        var npc = Villager.new()
        npc.name = "Ghost" if count%2 == 0 else "Zombie"
        npc.configure_cave(dungeon,{"route":route,"model":4+count%2,"seed":hash("%d:%s"%[dungeon._dungeon_seed,cell])})
        dungeon.add_child(npc)
        used[cell] = true
        used[neighbour] = true
        count += 1
