extends CanvasLayer
class_name LootUI
@onready var _player: FirstPersonPlayer = $"../DynamicEntities/Player"
@onready var _inventory: PlayerInventory = $"../DynamicEntities/Player/PlayerInventory"
var _target: Node3D
var _storage: LootStorage
var _panel: PanelContainer
var _title: Label
var _message: Label
var _prompt: Label
var _lists: Array[ItemList] = []
var _revision: Vector2i = Vector2i(-1,-1)
func _ready():
    layer = 30
    _prompt = Label.new()
    _prompt.position = Vector2(25,120)
    add_child(_prompt)
    _panel = PanelContainer.new()
    _panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    _panel.position = Vector2(100,75)
    _panel.size = Vector2(940,550)
    add_child(_panel)
    var column = VBoxContainer.new()
    _panel.add_child(column)
    _title = Label.new()
    column.add_child(_title)
    var columns = HBoxContainer.new()
    column.add_child(columns)
    for side in range(2):
        var group = VBoxContainer.new()
        columns.add_child(group)
        var label = Label.new()
        label.text = "Contents" if side == 0 else "Your inventory"
        group.add_child(label)
        var list = ItemList.new()
        list.custom_minimum_size = Vector2(440,385)
        group.add_child(list)
        _lists.append(list)
        list.item_activated.connect(func(index): _move(side,index,1))
        var buttons = HBoxContainer.new()
        group.add_child(buttons)
        for all in [false,true]:
            var button = Button.new()
            button.text = ("Take" if side == 0 else "Store")+(" stack" if all else " one")
            button.pressed.connect(func():
                var selected = list.get_selected_items()
                if not selected.is_empty(): _move(side,selected[0],-1 if all else 1))
            buttons.add_child(button)
    _message = Label.new()
    column.add_child(_message)
    var close = Button.new()
    close.text = "Close [Esc / E]"
    close.pressed.connect(close_loot)
    column.add_child(close)
    _panel.hide()
func _input(event: InputEvent):
    if event is InputEventKey and event.echo: return
    if _panel.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("Interact") or event.is_action_pressed("Inventory")):
        close_loot()
        get_viewport().set_input_as_handled()
func _unhandled_input(event: InputEvent):
    if event is InputEventKey and event.echo: return
    if not event.is_action_pressed("Interact") or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
    var target = _ray_target()
    if target != null:
        open_loot(target)
        get_viewport().set_input_as_handled()
func _process(_delta):
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__process(_delta)
        return
    var _profile_token = RuntimeProfiler.begin("ui.loot")
    _profile__process(_delta)
    RuntimeProfiler.end(_profile_token)

func _profile__process(_delta):
    if _panel.visible:
        _panel.position = (get_viewport().get_visible_rect().size-_panel.size)*.5
        if not is_instance_valid(_target) or not _target.is_visible_in_tree() or not _target.can_process() or _target.get_loot_inventory() == null or _player.global_position.distance_to(_target.global_position) > 4.5:
            close_loot()
            return
        _player.set_gameplay_input_enabled(false)
        var revision = Vector2i(_storage.get_revision(),_inventory.get_revision())
        if revision != _revision: _refresh()
        _prompt.hide()
    else:
        var target = _ray_target() if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _player.is_physics_processing() else null
        _prompt.visible = target != null
        if target != null: _prompt.text = "[E / X] Search "+target.get_loot_title()
func _ray_target() -> Node3D:
    if not _player.is_physics_processing(): return null
    var camera = _player.get_view_camera()
    var start = camera.global_position
    var query = PhysicsRayQueryParameters3D.create(start,start-camera.global_basis.z*3.0)
    query.exclude = [_player.get_rid()]
    query.collide_with_areas = true
    var hit = camera.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty(): return null
    var node = hit.collider
    for i in range(5):
        if node == null: return null
        if node.has_method("get_loot_inventory"):
            if node.is_visible_in_tree() and node.can_process() and node.get_loot_inventory() != null: return node
            return null
        if node.has_meta("loot_target") and is_instance_valid(node.get_meta("loot_target")):
            return node.get_meta("loot_target")
        node = node.get_parent()
    return null
func open_loot(target: Node3D):
    var storage = target.get_loot_inventory()
    if storage == null: return
    _target = target
    _storage = storage
    _panel.show()
    _message.text = "Double-click an item to move one."
    _player.set_gameplay_input_enabled(false)
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    if target.has_method("set_loot_open"): target.set_loot_open(true)
    _refresh()
func close_loot():
    if not _panel.visible: return
    if is_instance_valid(_target) and _target.has_method("set_loot_open"): _target.set_loot_open(false)
    _panel.hide()
    _target = null
    _storage = null
    _player.set_gameplay_input_enabled(true)
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
func _refresh():
    _title.text = _target.get_loot_title()+"   ·   Carrying %.1f / %.1f kg"%[_inventory.get_total_weight(),_inventory.get_maximum_weight()]
    for side in range(2):
        var list = _lists[side]
        var selected = list.get_selected_items()
        var selected_id = list.get_item_metadata(selected[0]) if not selected.is_empty() else null
        list.clear()
        var inventory: Object = _storage if side == 0 else _inventory
        for i in range(inventory.get_stack_count()):
            var stack: InventoryStack = inventory.get_stack_at(i)
            list.add_item("%s ×%d   (%.2f kg each)"%[stack.get_display_name(),stack.get_quantity(),stack.get_unit_weight()])
            list.set_item_metadata(i,stack.get_item_id())
            if stack.get_item_id() == selected_id: list.select(i)
    _revision = Vector2i(_storage.get_revision(),_inventory.get_revision())
func _move(side: int,index: int,amount: int):
    if not is_instance_valid(_target) or not _target.can_process() or _target.get_loot_inventory() == null:
        close_loot()
        return
    if not _panel.visible or index < 0 or index >= _lists[side].item_count: return
    var id: StringName = _lists[side].get_item_metadata(index)
    var source: Object = _storage if side == 0 else _inventory
    var destination: Object = _inventory if side == 0 else _storage
    var moved_stack: InventoryStack = source.get_stack_at(index)
    var quantity = amount
    if amount == -1:
        quantity = 0
        for i in range(source.get_stack_count()):
            if source.get_stack_at(i).get_item_id() == id: quantity = source.get_stack_at(i).get_quantity()
    var moved := LootStorage.transfer(source,destination,id,quantity)
    if moved and side == 0:
        var player_vitals = _player.get_node_or_null("PlayerVitals")
        if player_vitals != null and moved_stack != null and moved_stack.get_unit_weight() >= 1.0:
            player_vitals.add_experience(minf(15.0, moved_stack.get_unit_weight() * 2.0))
    _message.text = "Items moved." if moved else "Cannot move that quantity. Check your carrying capacity."
    _refresh()
