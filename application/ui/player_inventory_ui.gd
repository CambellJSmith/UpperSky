extends CanvasLayer # Displays the player's held items and stamina-derived carrying capacity through ordinary Godot UI nodes.
class_name PlayerInventoryUi # Makes the openable inventory interface available to the game composition root through strong typing.

const INVENTORY_LAYER: int = 95 # Places inventory above the status HUD and underwater effect but beneath the developer console.
const INVENTORY_ACTION: StringName = &"Inventory" # Names the keyboard and controller action used to open or close the inventory.
const MINIMUM_WEIGHT_RANGE: float = 0.001 # Prevents an invalid zero-range weight progress bar before player vitals are initialized.
const NORMAL_TEXT_COLOUR: Color = Color(0.94, 0.94, 0.96, 1.0) # Defines ordinary readable inventory summary text.
const OVERWEIGHT_TEXT_COLOUR: Color = Color(1.0, 0.28, 0.22, 1.0) # Highlights a capacity reduction that leaves existing contents overweight.

@onready var _item_tree: Tree = $InventoryPanel/ContentMargin/Layout/ItemTree # Stores the editor-authored multi-column held-item list.
@onready var _weight_label: Label = $InventoryPanel/ContentMargin/Layout/WeightSummary/WeightLabel # Displays total carried weight and the current maximum.
@onready var _weight_bar: ProgressBar = $InventoryPanel/ContentMargin/Layout/WeightSummary/WeightBar # Visualizes carried weight against current maximum stamina.

var _player: FirstPersonPlayer # Stores the active player whose movement and look are suspended while inventory is open.
var _inventory: PlayerInventory # Supplies current held stacks, total weight, and stamina-derived capacity.
var _is_open: bool = false # Tracks whether the inventory currently owns interface input.
var _displayed_inventory_revision: int = -1 # Caches the last rendered content revision for bounded polling.
var _displayed_maximum_weight: float = -1.0 # Caches the last rendered stamina-derived capacity.

func _ready() -> void: # Configures the authored inventory interface and resolves player-owned dependencies from the game scene.
    layer = INVENTORY_LAYER # Applies the intended draw order relative to status HUD and console.
    process_mode = Node.PROCESS_MODE_ALWAYS # Keeps close input available if future gameplay pause states are introduced.
    _configure_item_tree() # Defines column titles and stable column sizing for the held-item list.
    visible = false # Starts hidden until the player requests the inventory.
    var player_node: Node = get_node_or_null("../DynamicEntities/Player") # Finds the active first-person player mounted by the game scene.
    var inventory_node: Node = get_node_or_null("../DynamicEntities/Player/PlayerInventory") # Finds the player-owned held-item model.
    if player_node is FirstPersonPlayer and inventory_node is PlayerInventory: # Verifies both authored dependencies have their expected strong types.
        initialize(player_node as FirstPersonPlayer, inventory_node as PlayerInventory) # Connects input ownership, item rows, and stamina-derived capacity.

func initialize(player: FirstPersonPlayer, inventory: PlayerInventory) -> void: # Connects the interface to the active player and inventory model.
    _player = player # Stores the movement owner that will be temporarily locked.
    _inventory = inventory # Stores the authoritative held-item collection and capacity source.
    _refresh_inventory() # Prepares accurate rows before the first time the interface is opened.

func is_open() -> bool: # Reports whether the inventory interface currently owns player input.
    return _is_open # Returns the current open state for future UI coordination.

func _unhandled_input(event: InputEvent) -> void: # Handles inventory toggling after focused controls have had an opportunity to consume input.
    if event is InputEventKey and (event as InputEventKey).echo: # Detects operating-system key repeat from a held inventory key.
        return # Prevents rapid repeated opening and closing.
    if event.is_action_pressed(INVENTORY_ACTION): # Detects the authored inventory toggle action.
        _set_inventory_open(not _is_open) # Alternates between gameplay and the visible inventory.
        get_viewport().set_input_as_handled() # Prevents the same action from reaching player or unrelated UI systems.
        return # Stops after completing the toggle.
    if _is_open and event.is_action_pressed("ui_cancel"): # Allows the standard cancel action to close an open inventory.
        _set_inventory_open(false) # Returns immediately to gameplay.
        get_viewport().set_input_as_handled() # Prevents Escape from reaching unrelated systems after closing.

func _process(_delta: float) -> void: # Keeps an open inventory synchronized with item and stamina changes without signals.
    if not _is_open or _inventory == null: # Skips polling while the interface is closed or uninitialized.
        return # Avoids unnecessary work during ordinary gameplay.
    if _player != null: # Checks whether an active player remains connected.
        _player.set_gameplay_input_enabled(false) # Maintains movement and mouse-look suppression while the inventory owns input.
    var maximum_weight: float = _inventory.get_maximum_weight() # Reads the current stamina-derived capacity.
    if _inventory.get_revision() != _displayed_inventory_revision or not is_equal_approx(maximum_weight, _displayed_maximum_weight): # Detects changed contents or stamina maximum.
        _refresh_inventory() # Rebuilds visible rows and the weight summary only when required.

func _configure_item_tree() -> void: # Configures the real Godot Tree used for the visible item list.
    _item_tree.set_column_title(0, "ITEM") # Labels the human-readable item-name column.
    _item_tree.set_column_title(1, "QTY") # Labels the held quantity column.
    _item_tree.set_column_title(2, "EACH") # Labels the per-item weight column.
    _item_tree.set_column_title(3, "WEIGHT") # Labels the complete stack-weight column.
    _item_tree.set_column_expand(0, true) # Lets item names consume remaining horizontal space.
    _item_tree.set_column_expand(1, false) # Keeps the quantity column compact.
    _item_tree.set_column_expand(2, false) # Keeps the unit-weight column compact.
    _item_tree.set_column_expand(3, false) # Keeps the stack-weight column compact.
    _item_tree.set_column_custom_minimum_width(1, 64) # Reserves enough width for useful stack quantities.
    _item_tree.set_column_custom_minimum_width(2, 90) # Reserves enough width for formatted unit weights.
    _item_tree.set_column_custom_minimum_width(3, 105) # Reserves enough width for formatted stack weights.

func _set_inventory_open(enabled: bool) -> void: # Transfers input ownership between gameplay and the inventory interface.
    if enabled == _is_open: # Detects a no-op state request.
        return # Avoids resetting mouse mode or rebuilding rows unnecessarily.
    if enabled and (_player == null or _inventory == null): # Rejects opening before game composition supplies required dependencies.
        return # Leaves the unavailable interface hidden.
    _is_open = enabled # Stores the newly requested interface state.
    visible = _is_open # Shows or hides every editor-authored inventory control at once.
    if _is_open: # Checks whether inventory input ownership is beginning.
        _player.set_gameplay_input_enabled(false) # Stops movement, swimming, flight, and camera look while browsing items.
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # Releases the mouse for the visible Godot interface.
        _refresh_inventory() # Shows the latest held items and current stamina-derived limit immediately.
        return # Stops after opening and synchronizing the interface.
    if _player != null: # Checks whether gameplay input can be restored safely.
        _player.set_gameplay_input_enabled(true) # Returns movement and camera ownership to the active player.

func _refresh_inventory() -> void: # Rebuilds the visible held-item list and total-weight summary from authoritative models.
    _item_tree.clear() # Removes every previously rendered TreeItem row.
    var root_item: TreeItem = _item_tree.create_item() # Creates the hidden root required by the Godot Tree control.
    if _inventory == null: # Handles interface initialization before an inventory model is available.
        var unavailable_item: TreeItem = _item_tree.create_item(root_item) # Creates one explanatory placeholder row.
        unavailable_item.set_text(0, "Inventory unavailable") # Reports the missing dependency visibly.
        _weight_label.text = "WEIGHT  0.00 / 0.00 kg" # Displays a neutral unavailable summary.
        _weight_bar.max_value = MINIMUM_WEIGHT_RANGE # Keeps the progress bar range valid.
        _weight_bar.value = 0.0 # Shows no carried weight.
        return # Stops until game composition supplies the inventory.
    if _inventory.get_stack_count() == 0: # Detects a player currently holding no items.
        var empty_item: TreeItem = _item_tree.create_item(root_item) # Creates one visible empty-state row.
        empty_item.set_text(0, "No items held") # Makes the empty inventory state explicit.
        empty_item.set_selectable(0, false) # Prevents the placeholder from behaving like an item selection.
    else: # Handles one or more currently held item stacks.
        for stack_index: int in range(_inventory.get_stack_count()): # Visits every stack in stable inventory order.
            var stack: InventoryStack = _inventory.get_stack_at(stack_index) # Retrieves one read-only held-item stack.
            if stack == null: # Handles a defensive invalid stack lookup.
                continue # Skips the unavailable row without breaking the remaining list.
            var row_item: TreeItem = _item_tree.create_item(root_item) # Creates one visible row beneath the hidden root.
            row_item.set_text(0, stack.get_display_name()) # Displays the human-readable item name.
            row_item.set_text(1, str(stack.get_quantity())) # Displays the held quantity.
            row_item.set_text(2, "%.2f kg" % stack.get_unit_weight()) # Displays weight contributed by one item.
            row_item.set_text(3, "%.2f kg" % stack.get_stack_weight()) # Displays complete quantity-weight contribution.
            row_item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT) # Aligns numeric quantity values for scanning.
            row_item.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT) # Aligns unit weights consistently.
            row_item.set_text_alignment(3, HORIZONTAL_ALIGNMENT_RIGHT) # Aligns total stack weights consistently.
    var total_weight: float = _inventory.get_total_weight() # Calculates the complete carried weight from all held stacks.
    var maximum_weight: float = _inventory.get_maximum_weight() # Copies the current maximum stamina as the visible capacity.
    var is_overweight: bool = total_weight > maximum_weight + PlayerInventory.WEIGHT_EPSILON # Detects a capacity reduction below already-held contents.
    _weight_label.text = "WEIGHT  %.2f / %.2f kg" % [total_weight, maximum_weight] # Displays exact current and maximum weight values.
    if is_overweight: # Checks whether existing contents exceed the newly reduced capacity.
        _weight_label.text += "  OVER LIMIT" # Makes the exceptional overloaded state explicit.
        _weight_label.add_theme_color_override("font_color", OVERWEIGHT_TEXT_COLOUR) # Highlights the overloaded summary visibly.
    else: # Handles contents within the current stamina-derived limit.
        _weight_label.add_theme_color_override("font_color", NORMAL_TEXT_COLOUR) # Restores ordinary summary text colour.
    _weight_bar.max_value = maxf(maximum_weight, MINIMUM_WEIGHT_RANGE) # Uses current maximum stamina as the real progress range.
    _weight_bar.value = clampf(total_weight, 0.0, _weight_bar.max_value) # Fills according to carried weight and caps visually when overloaded.
    _displayed_inventory_revision = _inventory.get_revision() # Records the rendered item-content revision.
    _displayed_maximum_weight = maximum_weight # Records the rendered stamina-derived capacity.
