extends Node
class_name CityTravel

const ORIGIN := Vector3(0,3000,0)
var active: CitySpace
var cell := Vector2i.ZERO
var return_position := Vector3.ZERO
var return_yaw := 0.0
var busy := false
var _cooldown := 0.0
var _world_states: Array[Dictionary] = []
var _player: FirstPersonPlayer
var _terrain: InfiniteTerrain

func initialize(player: FirstPersonPlayer, terrain: InfiniteTerrain) -> void:
    _player = player
    _terrain = terrain

func _process(delta: float) -> void:
    if _player == null or busy or not _player.is_physics_processing(): return
    _cooldown = maxf(0,_cooldown-delta)
    if _cooldown > 0: return
    if active != null:
        var point := active.to_local(_player.global_position)
        if point.z > 109 and absf(point.x) < 4.5: leave()
        return
    if get_parent().get_node("BuildingInteriors").get("_active_room") != null: return
    if get_parent().get_node("DungeonSystem").get("_active_dungeon") != null: return
    var settlements: SettlementStreamer = get_parent().get_node("World/Settlements")
    for key in settlements._towns:
        var root: Node3D = settlements._towns[key]
        for child in root.get_children():
            if not child.has_meta("city_gate"): continue
            var gate: Vector3 = child.get_meta("city_gate")
            var point: Vector3 = child.to_local(_player.global_position)
            if absf(point.x) < 3.8 and absf(point.z-gate.z) < 4.5 and absf(point.y-gate.y) < 3:
                enter(root.get_meta("definition"),key,child.to_global(gate+Vector3(0,.5,13)))
                return

func enter(definition: Dictionary, city_cell: Vector2i, exterior_exit: Vector3, saved: Dictionary = {}) -> void:
    if busy or active != null: return
    busy = true
    var loading: LoadingScreen = get_parent().get_node("LoadingScreen")
    await loading.begin("Entering %s…"%CityGeometry.city_name(definition.seed))
    _player.set_physics_process(false)
    _player.velocity = Vector3.ZERO
    cell = city_cell
    return_position = _terrain.local_to_world_position(exterior_exit)
    return_yaw = float(definition.yaw) + PI
    var world: Node3D = get_parent().get_node("World")
    _world_states.clear()
    for child in world.get_children():
        if child is DirectionalLight3D or child is WorldEnvironment: continue
        _pause_exterior(child)
    for name in ["WorldDecorations","GroundFlora","DenseGroundCover","EnemyCamps","DungeonSystem"]:
        var node := get_parent().get_node_or_null(name)
        if node != null: _pause_exterior(node)
    for child in get_parent().get_node("DynamicEntities").get_children():
        if child != _player: _pause_exterior(child)
    # Leave lighting and the clock active while generation and wilderness actors are suspended.
    active = CitySpace.new()
    active.name = "CitySpace"
    get_parent().add_child(active)
    active.global_position = ORIGIN
    active.build_progress.connect(loading.set_message)
    await active.build(definition)
    _player.initialize_environment(null)
    _player.global_position = active.to_global(saved.get("position",Vector3(0,1,100)))
    _player.rotation.y = float(saved.get("yaw",0.0))
    await get_tree().physics_frame
    await get_tree().physics_frame
    _player.set_physics_process(true)
    _cooldown = 2
    loading.finish()
    busy = false

func leave() -> void:
    if busy or active == null: return
    busy = true
    var loading: LoadingScreen = get_parent().get_node("LoadingScreen")
    await loading.begin("Leaving city…")
    _player.set_physics_process(false)
    _player.velocity = Vector3.ZERO
    _player.initialize_environment(_terrain)
    _player.global_position = _terrain.world_to_local_position(return_position)
    _player.rotation.y = return_yaw
    active.persist_actors()
    active.queue_free()
    active = null
    for state in _world_states:
        if not is_instance_valid(state.node): continue
        state.node.process_mode = state.mode
        if state.node is Node3D: state.node.visible = state.visible
    _world_states.clear()
    await get_tree().physics_frame
    await get_tree().physics_frame
    _player.set_physics_process(true)
    _cooldown = 3
    loading.finish()
    busy = false

func snapshot() -> Dictionary:
    if active == null: return {}
    active.persist_actors()
    var position := active.to_local(_player.global_position)
    var interiors: BuildingInteriors = get_parent().get_node("BuildingInteriors")
    var room := {}
    if interiors._active_room != null:
        position = active.to_local(_terrain.world_to_local_position(interiors._active_world_position))
        room = {"house":str(interiors._active_exterior.name),"position":_player.global_position}
    return {"cell":cell,"position":position,"yaw":_player.rotation.y,"return_position":return_position,"return_yaw":return_yaw,"room":room}

func _pause_exterior(node: Node) -> void:
    _world_states.append({"node":node,"mode":node.process_mode,"visible":node.visible if node is Node3D else true})
    node.process_mode = Node.PROCESS_MODE_DISABLED
    if node is Node3D: node.visible = false

func restore(state: Dictionary) -> void:
    if state.is_empty(): return
    var definition := SettlementSampler.for_terrain(_terrain).sample_town(state.cell)
    if definition.is_empty() or not CityGeometry.is_city(definition): return
    var settlements: SettlementStreamer = get_parent().get_node("World/Settlements")
    if not settlements._towns.has(state.cell):
        settlements._build({"kind":"town","cell":state.cell,"definition":definition})
    await enter(definition,state.cell,_terrain.world_to_local_position(state.return_position),state)
    return_position = state.return_position
    return_yaw = state.return_yaw
    var room: Dictionary = state.get("room",{})
    if not room.is_empty():
        var house := active.get_node_or_null(NodePath(room.house)) as Node3D
        if house != null and house.has_meta("house_parameters"):
            var interiors: BuildingInteriors = get_parent().get_node("BuildingInteriors")
            await interiors._enter_room(house)
            _player.global_position = room.position
            _player.rotation.y = state.yaw
