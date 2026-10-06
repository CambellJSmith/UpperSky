extends Node3D
class_name BuildingInteriors

const INTERIOR_ORIGIN := Vector3(0.0, 1000.0, 0.0)
const INTERACTION_DISTANCE := 4.5
var _player: FirstPersonPlayer
var _terrain: InfiniteTerrain
var _active_room: Node3D
var _active_exterior: Node3D
var _active_world_position := Vector3.ZERO
var _busy := false

func initialize(player: FirstPersonPlayer, terrain: InfiniteTerrain) -> void:
    _player = player
    _terrain = terrain

func _unhandled_input(event: InputEvent) -> void:
    if _busy or not event.is_action_pressed("Interact"): return
    if _active_room != null:
        _leave_room()
        get_viewport().set_input_as_handled()
        return
    var building := _nearest_building()
    if building != null:
        _enter_room(building)
        get_viewport().set_input_as_handled()

func _nearest_building() -> Node3D:
    var best: Node3D
    var best_distance := INTERACTION_DISTANCE
    var cities: CityTravel = get_node_or_null("../CityTravel")
    if cities != null and cities.active != null:
        return _nearest_house(cities.active)
    for collection_name in ["_homes", "_towns"]:
        var collection: Dictionary = get_node("../World/Settlements").get(collection_name)
        for root in collection.values():
            if not is_instance_valid(root): continue
            var candidate: Node3D = root if root.has_meta("house_parameters") else _nearest_house(root)
            if candidate == null: continue
            var distance := _player.global_position.distance_to(candidate.global_position)
            if distance < best_distance:
                best = candidate
                best_distance = distance
    return best

func _nearest_house(town: Node3D) -> Node3D:
    var best: Node3D
    var distance := INTERACTION_DISTANCE
    for child in town.get_children():
        if child.has_meta("house_parameters"):
            var parameters: Dictionary = child.get_meta("house_parameters")
            var door: Vector3 = child.to_global(Vector3(0,1,-float(parameters.depth)*.5-.8))
            var value := _player.global_position.distance_to(door)
            if value < distance: best = child; distance = value
    return best

func _enter_room(exterior: Node3D) -> void:
    _busy = true
    var loading: LoadingScreen = get_node_or_null("../LoadingScreen")
    if loading != null: await loading.begin("Entering building…")
    _active_exterior = exterior
    _active_world_position = _terrain.local_to_world_position(exterior.global_position)
    var parameters: Dictionary = exterior.get_meta("house_parameters", {"width": 8.0, "depth": 8.0, "floors": 1})
    _active_world_position = _terrain.local_to_world_position(exterior.to_global(Vector3(0,1,-float(parameters.depth)*.5-2)))
    _active_room = _build_room(parameters)
    add_child(_active_room)
    _player.set_physics_process(false)
    _player.velocity = Vector3.ZERO
    _player.initialize_environment(null)
    _player.global_position = INTERIOR_ORIGIN + Vector3(0.0, 1.0, maxf(1.0, float(parameters.depth) * .35))
    _player.rotation.y = PI
    await get_tree().physics_frame
    _player.set_physics_process(true)
    if loading != null: loading.finish()
    _busy = false

func _leave_room() -> void:
    _busy = true
    var loading: LoadingScreen = get_node_or_null("../LoadingScreen")
    if loading != null: await loading.begin("Leaving building…")
    _active_room.queue_free()
    _active_room = null
    var cities: CityTravel = get_node_or_null("../CityTravel")
    _player.initialize_environment(null if cities != null and cities.active != null else _terrain)
    _player.global_position = _terrain.world_to_local_position(_active_world_position)
    await get_tree().physics_frame
    if loading != null: loading.finish()
    _active_exterior = null
    _busy = false

func _build_room(parameters: Dictionary) -> Node3D:
    var room := Node3D.new()
    var width := maxf(4.0, float(parameters.get("width", 8.0)))
    var depth := maxf(4.0, float(parameters.get("depth", 8.0)))
    var height := 3.2 * maxf(1.0, float(parameters.get("floors", 1)))
    _panel(room, Vector3(width, .2, depth), Vector3(0, 0, 0))
    _panel(room, Vector3(width, .2, depth), Vector3(0, height, 0))
    _panel(room, Vector3(.2, height, depth), Vector3(-width*.5, height*.5, 0))
    _panel(room, Vector3(.2, height, depth), Vector3(width*.5, height*.5, 0))
    _panel(room, Vector3(width, height, .2), Vector3(0, height*.5, -depth*.5))
    _panel(room, Vector3(width, height, .2), Vector3(0, height*.5, depth*.5))
    return room

func _panel(root: Node3D, size: Vector3, position: Vector3) -> void:
    var body := StaticBody3D.new()
    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new(); box.size = size
    mesh.mesh = box
    var shape := CollisionShape3D.new(); var collision := BoxShape3D.new(); collision.size = size; shape.shape = collision
    body.position = INTERIOR_ORIGIN + position
    body.add_child(mesh); body.add_child(shape); root.add_child(body)
