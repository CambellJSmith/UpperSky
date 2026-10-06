extends CanvasLayer
class_name WayshrineInteraction
@onready var player: FirstPersonPlayer = $"../DynamicEntities/Player"
@onready var terrain: InfiniteTerrain = $"../World/Terrain"
@onready var streamer: WayshrineStreamer = $"../World/Wayshrines"
var _source: Wayshrine
var _shade: ColorRect
var _panel: PanelContainer
var _prompt: Label
var _title: Label
var _message: Label
var _list: ItemList
var _travel_button: Button
var _travelling: bool = false
func _ready():
    layer = 32
    _prompt = Label.new()
    _prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _prompt.add_theme_font_size_override("font_size",20)
    _prompt.add_theme_color_override("font_shadow_color",Color.BLACK)
    _prompt.add_theme_constant_override("shadow_offset_x",2)
    _prompt.add_theme_constant_override("shadow_offset_y",2)
    add_child(_prompt)
    _prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
    _prompt.offset_left = -350
    _prompt.offset_right = 350
    _prompt.offset_top = -105
    _prompt.offset_bottom = -65
    _prompt.hide()
    _shade = ColorRect.new()
    _shade.color = Color(0.015,.025,.04,.78)
    add_child(_shade)
    _shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _panel = PanelContainer.new()
    _shade.add_child(_panel)
    var style = StyleBoxFlat.new()
    style.bg_color = Color("162a32")
    style.border_color = Color("a9905d")
    style.set_border_width_all(2)
    style.set_corner_radius_all(8)
    style.content_margin_left = 24
    style.content_margin_right = 24
    style.content_margin_top = 22
    style.content_margin_bottom = 22
    _panel.add_theme_stylebox_override("panel",style)
    var column = VBoxContainer.new()
    column.add_theme_constant_override("separation",14)
    _panel.add_child(column)
    _title = Label.new()
    _title.add_theme_font_size_override("font_size",26)
    _title.add_theme_color_override("font_color",Color("a3ffe0"))
    column.add_child(_title)
    _message = Label.new()
    _message.custom_minimum_size = Vector2(420,0)
    _message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(_message)
    _list = ItemList.new()
    _list.custom_minimum_size = Vector2(0,230)
    _list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _list.item_selected.connect(func(_index): _travel_button.disabled = false)
    _list.item_activated.connect(func(_index): _travel_selected())
    column.add_child(_list)
    var buttons = HBoxContainer.new()
    column.add_child(buttons)
    _travel_button = Button.new()
    _travel_button.text = "Travel to selected shrine"
    _travel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _travel_button.pressed.connect(_travel_selected)
    buttons.add_child(_travel_button)
    var close = Button.new()
    close.text = "Close [Esc / E]"
    close.pressed.connect(close_menu)
    buttons.add_child(close)
    _shade.hide()
func _process(_delta):
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__process(_delta)
        return
    var _profile_token = RuntimeProfiler.begin("ui.wayshrines")
    _profile__process(_delta)
    RuntimeProfiler.end(_profile_token)

func _profile__process(_delta):
    if _shade.visible:
        var viewport = get_viewport().get_visible_rect().size
        _panel.size = Vector2(minf(680,viewport.x-32),minf(480,viewport.y-32))
        _panel.position = (viewport-_panel.size)*.5
        _prompt.hide()
        if _travelling: return
        if not _source_valid(): close_menu()
        return
    var shrine = _ray_target() if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and player.is_physics_processing() and not player.get_health_state().is_dead() else null
    _prompt.visible = shrine != null
    if shrine != null:
        _prompt.text = "[E / X] "+("Travel · " if WayshrineRegistry.is_activated(shrine.definition.id) else "Activate · ")+shrine.definition.title
func _input(event: InputEvent):
    if event is InputEventKey and event.echo: return
    if _shade.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("Interact") or event.is_action_pressed("Inventory")):
        if not _travelling: close_menu()
        get_viewport().set_input_as_handled()
func _unhandled_input(event: InputEvent):
    if event is InputEventKey and event.echo: return
    if not event.is_action_pressed("Interact") or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
    var shrine = _ray_target()
    if shrine != null:
        open_shrine(shrine)
        get_viewport().set_input_as_handled()
func _ray_target() -> Wayshrine:
    if not player.is_physics_processing(): return null
    var camera = player.get_view_camera()
    var start = camera.global_position
    var query = PhysicsRayQueryParameters3D.create(start,start-camera.global_basis.z*3.5,1|4|Wayshrine.INTERACTION_COLLISION_LAYER|CampBedroll.INTERACTION_COLLISION_LAYER|DungeonDoor.INTERACTION_COLLISION_LAYER)
    query.collide_with_areas = true
    query.exclude = [player.get_rid()]
    var hit = camera.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty(): return null
    var node = hit.collider
    for depth in range(5):
        if node is Wayshrine: return node if node.is_visible_in_tree() and node.can_process() else null
        if node == null: return null
        node = node.get_parent()
    return null
func _source_valid() -> bool:
    return is_instance_valid(_source) and _source.is_visible_in_tree() and _source.can_process() and player.is_physics_processing() and not player.get_health_state().is_dead() and player.global_position.distance_to(_source.global_position) < 5.5
func open_shrine(shrine: Wayshrine) -> bool:
    _source = shrine
    if not _source_valid():
        _source = null
        return false
    var discovered = WayshrineRegistry.activate(shrine.definition)
    _title.text = shrine.definition.title
    _list.clear()
    var origin = terrain.local_to_world_position(player.global_position)
    for destination in WayshrineRegistry.destinations(shrine.definition.id):
        _list.add_item("%s  ·  %.1f km"%[destination.title,origin.distance_to(destination.position)/1000])
        _list.set_item_metadata(_list.item_count-1,destination.id)
    _message.text = ("Wayshrine awakened. " if discovered else "")+("Discover and activate another wayshrine to unlock travel." if _list.item_count == 0 else "Choose an awakened wayshrine to travel.")
    _travel_button.disabled = true
    if _list.item_count > 0:
        _list.select(0)
        _travel_button.disabled = false
    _shade.show()
    player.set_gameplay_input_enabled(false)
    _list.grab_focus()
    return true
func close_menu():
    if not _shade.visible or _travelling: return
    _shade.hide()
    _source = null
    player.set_gameplay_input_enabled(true)
func _travel_selected():
    var selected = _list.get_selected_items()
    if selected.is_empty() or _travelling: return
    _travel_button.disabled = true
    _message.text = "Following the shrine's light…"
    var success = await travel_to(_list.get_item_metadata(selected[0]))
    if success: close_menu()
    else:
        _message.text = "The way is not ready. Please try again."
        _travel_button.disabled = false
func travel_to(id: Vector2i) -> bool:
    if _travelling or not _source_valid() or not WayshrineRegistry.is_activated(_source.definition.id) or not WayshrineRegistry.is_activated(id) or id == _source.definition.id: return false
    _travelling = true
    var destination: Dictionary = WayshrineRegistry.activated[id]
    var original = terrain.local_to_world_position(player.global_position)
    var original_yaw = player.rotation.y
    player.set_physics_process(false)
    player.velocity = Vector3.ZERO
    player.global_position = terrain.world_to_local_position(destination.landing+Vector3.UP*12)
    terrain._rebase_world_if_needed()
    terrain.initialize(player,$"../DynamicEntities")
    streamer.ensure_cell(id)
    var safe = false
    for attempt in range(3):
        await get_tree().physics_frame
        var query = PhysicsShapeQueryParameters3D.new()
        query.shape = player.get_collision_shape()
        query.transform = player.global_transform*player.get_collision_local_transform()
        query.motion = Vector3.DOWN*24
        query.collision_mask = 1
        query.exclude = [player.get_rid()]
        query.margin = .04
        var cast = player.get_world_3d().direct_space_state.cast_motion(query)
        if cast.size() == 2 and cast[0] < 1:
            player.global_position += query.motion*cast[0]+Vector3.UP*.08
            player.rotation.y = destination.yaw
            safe = true
            break
    if not safe:
        player.global_position = terrain.world_to_local_position(original)
        player.rotation.y = original_yaw
        terrain.initialize(player,$"../DynamicEntities")
        await get_tree().physics_frame
    player.velocity = Vector3.ZERO
    await get_tree().physics_frame
    player.set_physics_process(true)
    _travelling = false
    return safe
