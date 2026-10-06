extends Node3D
class_name FerryCrossing

const SPEED := 9.0
const WAITING_BOATS_PER_SIDE := 3
var vessels: Array[Dictionary] = []
var definition: Dictionary
var terrain: InfiniteTerrain
var boat: Node3D
var side := 0
var destination := 0
var moving := false
var progress := 0.0
var dwell := 0.0
var riders: Array[Dictionary] = []
var waiting: Array[Dictionary] = []
var passengers: Array[Villager] = []
var sail_speed := SPEED

func configure(source: InfiniteTerrain, data: Dictionary): terrain = source; definition = data

func _ready():
    position = terrain.world_to_local_position(Vector3.ZERO)
    for dock in definition.docks: add_child(FerryGeometry.dock(dock,terrain))
    _ensure_waiting_boats()
    boat = vessels[0].node
    for end in range(2):
        var dock: Dictionary = definition.docks[end]
        var area := Area3D.new()
        area.collision_layer = 1 << 17
        area.collision_mask = 0
        area.set_meta("ferry",self)
        area.set_meta("side",end)
        var shape := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = Vector3(3.3,2.4,6)
        shape.shape = box
        var towards: Vector2 = (dock.berth-dock.land).normalized()
        area.position = Vector3(dock.tip.x,dock.height+1,dock.tip.y)
        area.rotation.y = atan2(towards.x,towards.y)
        area.add_child(shape)
        add_child(area)

func landing(end: int) -> Vector3:
    var dock: Dictionary = definition.docks[end]
    return Vector3(dock.land.x,dock.land_height+.08,dock.land.y)

func deck_height(point: Vector2):
    for dock in definition.docks:
        var closest := Geometry2D.get_closest_point_to_segment(point,dock.land,dock.tip)
        if closest.distance_to(point)>1.55: continue
        var t: float = dock.land.distance_to(closest)/dock.land.distance_to(dock.tip)
        return lerpf(dock.land_height,dock.height,t)
    return null

func request(character: CharacterBody3D, end: int) -> bool:
    if end not in [0,1] or not is_instance_valid(character) or not terrain.is_visible_in_tree(): return false
    if not character is FirstPersonPlayer and not character is Villager: return false
    if character is Villager and (character.health.is_dead() or character.is_in_combat()): return false
    if character is FirstPersonPlayer and character.water_transport != null: return false
    for entry in riders+waiting:
        if entry.character.get_ref() == character: return true
    var world := terrain.local_to_world_position(character.global_position)
    if Vector2(world.x,world.z).distance_to(definition.docks[end].tip)>8: return false
    _ensure_waiting_boats()
    var vessel: Dictionary = {}
    var closest := INF
    for candidate in vessels:
        if not candidate.moving and candidate.side==end:
            var distance: float = world.distance_squared_to(candidate.node.position)
            if distance < closest:
                closest = distance
                vessel = candidate
    if vessel.is_empty(): return false
    var mask := character.collision_mask
    character.collision_mask = 0
    character.velocity = Vector3.ZERO
    var entry := {"character":weakref(character),"side":end,"mask":mask,"seat":0,"vessel":vessel}
    riders.append(entry)
    if character is FirstPersonPlayer: character.water_transport = self
    else: character.ferry_riding = self
    vessel.departure = Vector2(vessel.node.position.x,vessel.node.position.z)
    vessel.destination = 1-end
    vessel.progress = 0.0
    vessel.moving = true
    moving = true
    boat = vessel.node
    _place_riders()
    _ensure_waiting_boats()
    return true

func _ensure_waiting_boats():
    for end in range(2):
        var idle: Array[Dictionary] = []
        for vessel in vessels:
            if not vessel.moving and vessel.side==end: idle.append(vessel)
        while idle.size()>WAITING_BOATS_PER_SIDE:
            var surplus: Dictionary = idle.pop_back()
            vessels.erase(surplus)
            surplus.node.queue_free()
        while idle.size()<WAITING_BOATS_PER_SIDE:
            var node := FerryGeometry.boat()
            add_child(node)
            var vessel := {"node":node,"side":end,"destination":1-end,"progress":0.0,"moving":false,"departure":definition.lane[end]}
            vessels.append(vessel)
            idle.append(vessel)
        var direction: Vector2 = (definition.lane[1-end]-definition.lane[end]).normalized()
        var across := Vector2(-direction.y,direction.x)
        for index in range(idle.size()):
            var point: Vector2 = definition.lane[end]+across*float(index-1)*3.4
            if not terrain.has_water_at(point): point = definition.lane[end]+direction*float(index)*5.4
            idle[index].node.position = Vector3(point.x,terrain.get_water_level_at(point),point.y)
            idle[index].node.rotation.y = atan2(-direction.x,-direction.y)

func _physics_process(delta: float):
    if not terrain.is_visible_in_tree():
        for entry in riders.duplicate(): release(entry.character.get_ref(),entry.side)
        for vessel in vessels: vessel.moving = false
        waiting.clear()
        moving = false
        _ensure_waiting_boats()
        return
    position = terrain.world_to_local_position(Vector3.ZERO)
    for vessel in vessels.duplicate():
        if not vessel.moving: continue
        var a: Vector2 = vessel.departure
        var b: Vector2 = definition.lane[vessel.destination]
        vessel.progress = minf(1.0,vessel.progress+delta*sail_speed/maxf(a.distance_to(b),.01))
        var point := a.lerp(b,vessel.progress)
        vessel.node.position = Vector3(point.x,terrain.get_water_level_at(point),point.y)
        vessel.node.rotation.y = atan2(-(b-a).x,-(b-a).y)
        progress = vessel.progress
        destination = vessel.destination
        if vessel.progress>=1:
            vessel.side = vessel.destination
            vessel.moving = false
            side = vessel.side
            for entry in riders.duplicate():
                if entry.vessel==vessel: release(entry.character.get_ref(),vessel.side)
    _place_riders()
    _ensure_waiting_boats()
    if not is_instance_valid(boat) or boat.is_queued_for_deletion(): boat = vessels[0].node
    moving = false
    for vessel in vessels:
        if vessel.moving: moving = true

func _place_riders():
    for entry in riders.duplicate():
        var character = entry.character.get_ref()
        if not is_instance_valid(character): riders.erase(entry); continue
        var seat := Vector3(0,.38,-.5)
        var world: Vector3 = entry.vessel.node.transform*seat
        character.global_position = terrain.world_to_local_position(world)
        character.velocity = Vector3.ZERO
        if character is Villager: character.world_position = world

func release(character, end: int, place_at_dock: bool = true):
    for entry in riders.duplicate():
        if entry.character.get_ref() != character: continue
        riders.erase(entry)
        if not is_instance_valid(character): continue
        character.collision_mask = entry.mask
        var world := landing(end)
        if place_at_dock and character.is_inside_tree(): character.global_position = terrain.world_to_local_position(world)
        character.velocity = Vector3.ZERO
        if character is FirstPersonPlayer: character.water_transport = null
        else:
            character.ferry_riding = null
            character.world_position = world
            character.ferry_arrived(end)

func save_position(character: CharacterBody3D) -> Vector3:
    for entry in riders:
        if entry.character.get_ref() == character: return landing(entry.side)
    return terrain.local_to_world_position(character.global_position)

func _exit_tree():
    for entry in riders.duplicate(): release(entry.character.get_ref(),entry.side)
