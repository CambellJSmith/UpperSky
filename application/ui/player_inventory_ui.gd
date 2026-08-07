extends CanvasLayer
class_name PlayerInventoryUi

const INVENTORY_LAYER: int = 95
const INVENTORY_ACTION: StringName = &"Inventory"
const MINIMUM_WEIGHT_RANGE: float = 0.001
const NORMAL_TEXT_COLOUR: Color = Color(0.94, 0.94, 0.96, 1.0)
const OVERWEIGHT_TEXT_COLOUR: Color = Color(1.0, 0.28, 0.22, 1.0)

@onready var _item_tree: Tree = $InventoryPanel/ContentMargin/Layout/ItemTree
@onready var _weight_label: Label = $InventoryPanel/ContentMargin/Layout/WeightSummary/WeightLabel
@onready var _weight_bar: ProgressBar = $InventoryPanel/ContentMargin/Layout/WeightSummary/WeightBar

var _player: FirstPersonPlayer
var _inventory: PlayerInventory
var _equipment: PlayerEquipment
var _is_open: bool = false
var _displayed_inventory_revision: int = -1
var _displayed_equipment_revision: int = -1
var _displayed_maximum_weight: float = -1.0

func _ready() -> void:
    layer = INVENTORY_LAYER
    process_mode = Node.PROCESS_MODE_ALWAYS
    _configure_item_tree()
    if not _item_tree.item_activated.is_connected(_on_item_activated):
        _item_tree.item_activated.connect(_on_item_activated)
    visible = false

    var player_node: Node = get_node_or_null("../DynamicEntities/Player")
    var inventory_node: Node = get_node_or_null("../DynamicEntities/Player/PlayerInventory")
    var equipment_node: Node = get_node_or_null("../DynamicEntities/Player/PlayerEquipment")
    var resolved_equipment: PlayerEquipment = null
    if equipment_node is PlayerEquipment:
        resolved_equipment = equipment_node as PlayerEquipment
    if player_node is FirstPersonPlayer and inventory_node is PlayerInventory:
        initialize(player_node as FirstPersonPlayer, inventory_node as PlayerInventory, resolved_equipment)

func initialize(player: FirstPersonPlayer, inventory: PlayerInventory, equipment: PlayerEquipment = null) -> void:
    _player = player
    _inventory = inventory
    _equipment = equipment
    _refresh_inventory()

func is_open() -> bool:
    return _is_open

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and (event as InputEventKey).echo:
        return
    if event.is_action_pressed(INVENTORY_ACTION):
        _set_inventory_open(not _is_open)
        get_viewport().set_input_as_handled()
        return
    if _is_open and event.is_action_pressed("ui_cancel"):
        _set_inventory_open(false)
        get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
    if not _is_open or _inventory == null:
        return
    if _player != null:
        _player.set_gameplay_input_enabled(false)

    var maximum_weight: float = _inventory.get_maximum_weight()
    var equipment_revision: int = _equipment.get_revision() if _equipment != null else -1
    if (
        _inventory.get_revision() != _displayed_inventory_revision
        or equipment_revision != _displayed_equipment_revision
        or not is_equal_approx(maximum_weight, _displayed_maximum_weight)
    ):
        _refresh_inventory()

func _configure_item_tree() -> void:
    _item_tree.columns = 5
    _item_tree.set_column_title(0, "ITEM")
    _item_tree.set_column_title(1, "QTY")
    _item_tree.set_column_title(2, "EACH")
    _item_tree.set_column_title(3, "WEIGHT")
    _item_tree.set_column_title(4, "EQUIPPED")
    _item_tree.set_column_expand(0, true)
    for column: int in range(1, 5):
        _item_tree.set_column_expand(column, false)
    _item_tree.set_column_custom_minimum_width(1, 64)
    _item_tree.set_column_custom_minimum_width(2, 90)
    _item_tree.set_column_custom_minimum_width(3, 105)
    _item_tree.set_column_custom_minimum_width(4, 110)

func _set_inventory_open(enabled: bool) -> void:
    if enabled == _is_open:
        return
    if enabled and (_player == null or _inventory == null):
        return
    _is_open = enabled
    visible = _is_open
    if _is_open:
        _player.set_gameplay_input_enabled(false)
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        _refresh_inventory()
        return
    if _player != null:
        _player.set_gameplay_input_enabled(true)

func _on_item_activated() -> void:
    if not _is_open or _equipment == null:
        return
    var selected: TreeItem = _item_tree.get_selected()
    if selected == null:
        return
    var metadata: Variant = selected.get_metadata(0)
    if metadata == null:
        return
    var item_id := StringName(str(metadata))
    if not EquipmentCatalog.is_equippable(item_id):
        return
    if _equipment.get_equipped_item_id() == item_id:
        _equipment.unequip()
    else:
        _equipment.equip_item(item_id)
    _refresh_inventory()

func _refresh_inventory() -> void:
    _item_tree.clear()
    var root_item: TreeItem = _item_tree.create_item()
    if _inventory == null:
        var unavailable_item: TreeItem = _item_tree.create_item(root_item)
        unavailable_item.set_text(0, "Inventory unavailable")
        _weight_label.text = "WEIGHT  0.00 / 0.00 kg"
        _weight_bar.max_value = MINIMUM_WEIGHT_RANGE
        _weight_bar.value = 0.0
        return

    var equipped_item_id: StringName = _equipment.get_equipped_item_id() if _equipment != null else &""
    if _inventory.get_stack_count() == 0:
        var empty_item: TreeItem = _item_tree.create_item(root_item)
        empty_item.set_text(0, "No items held")
        empty_item.set_selectable(0, false)
    else:
        for stack_index: int in range(_inventory.get_stack_count()):
            var stack: InventoryStack = _inventory.get_stack_at(stack_index)
            if stack == null:
                continue
            var item_id: StringName = stack.get_item_id()
            var row_item: TreeItem = _item_tree.create_item(root_item)
            row_item.set_metadata(0, item_id)
            row_item.set_text(0, stack.get_display_name())
            row_item.set_text(1, str(stack.get_quantity()))
            row_item.set_text(2, "%.2f kg" % stack.get_unit_weight())
            row_item.set_text(3, "%.2f kg" % stack.get_stack_weight())
            if EquipmentCatalog.is_equippable(item_id):
                row_item.set_text(4, "YES" if item_id == equipped_item_id else "READY")
                row_item.set_tooltip_text(0, "Double-click or press Enter to equip/unequip.")
            else:
                row_item.set_text(4, "-")
            for numeric_column: int in range(1, 4):
                row_item.set_text_alignment(numeric_column, HORIZONTAL_ALIGNMENT_RIGHT)

    var total_weight: float = _inventory.get_total_weight()
    var maximum_weight: float = _inventory.get_maximum_weight()
    var is_overweight: bool = total_weight > maximum_weight + PlayerInventory.WEIGHT_EPSILON
    _weight_label.text = "WEIGHT  %.2f / %.2f kg" % [total_weight, maximum_weight]
    if is_overweight:
        _weight_label.text += "  OVER LIMIT"
        _weight_label.add_theme_color_override("font_color", OVERWEIGHT_TEXT_COLOUR)
    else:
        _weight_label.add_theme_color_override("font_color", NORMAL_TEXT_COLOUR)

    _weight_bar.max_value = maxf(maximum_weight, MINIMUM_WEIGHT_RANGE)
    _weight_bar.value = clampf(total_weight, 0.0, _weight_bar.max_value)
    _displayed_inventory_revision = _inventory.get_revision()
    _displayed_equipment_revision = _equipment.get_revision() if _equipment != null else -1
    _displayed_maximum_weight = maximum_weight
