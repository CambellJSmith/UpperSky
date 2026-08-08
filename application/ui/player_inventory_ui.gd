extends CanvasLayer # Presents the player inventory as a pause-safe categorized interface.
class_name PlayerInventoryUi # Exposes the inventory interface for game composition and state queries.

const INVENTORY_LAYER: int = 95 # Places the inventory above ordinary HUD elements while leaving room for higher-priority overlays.
const INVENTORY_ACTION: StringName = &"Inventory" # Reuses the authored inventory input action for opening and closing the interface.
const MINIMUM_WEIGHT_RANGE: float = 0.001 # Keeps the progress bar numerically valid when carrying capacity is zero.
const NORMAL_TEXT_COLOUR: Color = Color(0.94, 0.94, 0.96, 1.0) # Colours ordinary carry-weight text consistently with the inventory panel.
const OVERWEIGHT_TEXT_COLOUR: Color = Color(1.0, 0.28, 0.22, 1.0) # Highlights an exceeded carrying limit clearly.

@onready var _category_tabs: TabBar = $InventoryPanel/ContentMargin/Layout/CategoryTabs # Resolves the horizontal inventory-category selector authored in the scene.
@onready var _item_tree: Tree = $InventoryPanel/ContentMargin/Layout/ItemTree # Resolves the tab-filtered item table.
@onready var _weight_label: Label = $InventoryPanel/ContentMargin/Layout/WeightSummary/WeightLabel # Resolves the global carried-weight summary.
@onready var _weight_bar: ProgressBar = $InventoryPanel/ContentMargin/Layout/WeightSummary/WeightBar # Resolves the global carrying-capacity progress bar.

var _player: FirstPersonPlayer # Stores the active player whose gameplay input is suspended while inventory is open.
var _inventory: PlayerInventory # Stores the authoritative categorized inventory model.
var _equipment: PlayerEquipment # Stores optional equipment state so Weapons/Tools rows can show and toggle equipped status.
var _is_open: bool = false # Tracks whether the inventory overlay currently owns player interaction.
var _displayed_inventory_revision: int = -1 # Tracks the inventory revision represented by the current table contents.
var _displayed_equipment_revision: int = -1 # Tracks the equipment revision represented by the current status column.
var _displayed_maximum_weight: float = -1.0 # Tracks the carrying limit represented by the current weight summary.
var _displayed_category: int = -1 # Tracks the category currently represented by the item table.

func _ready() -> void: # Configures controls and resolves the active player-owned inventory dependencies.
    layer = INVENTORY_LAYER # Applies the dedicated inventory draw layer.
    process_mode = Node.PROCESS_MODE_ALWAYS # Keeps inventory interaction responsive while gameplay is paused or input-disabled.
    _configure_category_tabs() # Builds the six stable tabs from the shared category model.
    _configure_item_tree() # Configures table columns and sizing once.
    if not _item_tree.item_activated.is_connected(_on_item_activated): # Preserves the existing equip-on-activation interaction without duplicate connections.
        _item_tree.item_activated.connect(_on_item_activated) # Routes row activation into equipment toggling for equippable items.
    visible = false # Starts the overlay hidden until the player explicitly opens inventory.

    var player_node: Node = get_node_or_null("../DynamicEntities/Player") # Locates the active first-person player instance.
    var inventory_node: Node = get_node_or_null("../DynamicEntities/Player/PlayerInventory") # Locates the authoritative inventory model owned by the player.
    var equipment_node: Node = get_node_or_null("../DynamicEntities/Player/PlayerEquipment") # Locates optional equipment state for status presentation.
    var resolved_equipment: PlayerEquipment = null # Starts with no equipment dependency so inventory remains usable without it.
    if equipment_node is PlayerEquipment: # Verifies the equipment node has the expected strong type.
        resolved_equipment = equipment_node as PlayerEquipment # Retains the typed equipment model for equip interactions.
    if player_node is FirstPersonPlayer and inventory_node is PlayerInventory: # Verifies the two required dependencies before initialization.
        initialize(player_node as FirstPersonPlayer, inventory_node as PlayerInventory, resolved_equipment) # Connects the interface to the active player models.

func initialize(player: FirstPersonPlayer, inventory: PlayerInventory, equipment: PlayerEquipment = null) -> void: # Connects the inventory interface to authoritative runtime models.
    _player = player # Stores the player whose gameplay controls are suspended while inventory is open.
    _inventory = inventory # Stores the categorized inventory source used for every tab.
    _equipment = equipment # Stores optional equipment state for Weapons/Tools interactions.
    _refresh_inventory() # Builds the initial table and category counts immediately.

func is_open() -> bool: # Reports whether the inventory overlay is currently visible and interactive.
    return _is_open # Returns the interface's explicit open state.

func _unhandled_input(event: InputEvent) -> void: # Handles inventory open and close actions that gameplay did not consume.
    if event is InputEventKey and (event as InputEventKey).echo: # Rejects repeated keyboard echo events from held keys.
        return # Prevents one press from rapidly toggling the inventory multiple times.
    if event.is_action_pressed(INVENTORY_ACTION): # Detects the authored inventory toggle action.
        _set_inventory_open(not _is_open) # Toggles between the current open and closed state.
        get_viewport().set_input_as_handled() # Prevents the same action from reaching lower-priority gameplay handlers.
        return # Stops further inventory input processing for this event.
    if _is_open and event.is_action_pressed("ui_cancel"): # Allows the standard UI cancel action to close an open inventory.
        _set_inventory_open(false) # Closes the inventory without changing the selected category.
        get_viewport().set_input_as_handled() # Prevents cancel from affecting gameplay beneath the overlay.

func _process(_delta: float) -> void: # Keeps the open inventory synchronized with model revisions and the selected category without new signals.
    if not _is_open or _inventory == null: # Skips refresh work while the overlay is closed or uninitialized.
        return # Leaves hidden inventory controls untouched.
    if _player != null: # Verifies the player reference remains valid while the overlay is open.
        _player.set_gameplay_input_enabled(false) # Continually enforces inventory ownership of interaction.

    var maximum_weight: float = _inventory.get_maximum_weight() # Reads the live stamina-derived carrying capacity.
    var equipment_revision: int = _equipment.get_revision() if _equipment != null else -1 # Reads equipment changes only when equipment support is present.
    var selected_category: int = _get_selected_category() # Reads the active TabBar category through the shared category indices.
    if ( # Detects every state change that can affect visible inventory content.
        _inventory.get_revision() != _displayed_inventory_revision # Refreshes when held stacks or quantities change.
        or equipment_revision != _displayed_equipment_revision # Refreshes when equipped status changes.
        or not is_equal_approx(maximum_weight, _displayed_maximum_weight) # Refreshes when the live carrying capacity changes.
        or selected_category != _displayed_category # Refreshes when the user selects another category tab.
    ): # Completes the refresh condition.
        _refresh_inventory() # Rebuilds only when visible state actually changed.

func _configure_category_tabs() -> void: # Builds the stable inventory tabs directly from the shared category definition.
    _category_tabs.clear_tabs() # Removes any scene-authored placeholder tabs before deterministic setup.
    for category: int in range(InventoryCategory.get_count()): # Visits categories in the exact requested display order.
        _category_tabs.add_tab(InventoryCategory.get_display_name(category)) # Adds one visible tab using the centralized user-facing label.
    _category_tabs.current_tab = InventoryCategory.Type.WEAPONS_TOOLS # Opens inventory on Weapons/Tools by default for the current equipment-heavy starting loadout.

func _configure_item_tree() -> void: # Configures the reusable table columns shared by every inventory category.
    _item_tree.columns = 5 # Provides item identity, quantity, unit weight, stack weight, and status columns.
    _item_tree.set_column_title(0, "ITEM") # Labels the item-name column.
    _item_tree.set_column_title(1, "QTY") # Labels the held-quantity column.
    _item_tree.set_column_title(2, "EACH") # Labels the per-item weight column.
    _item_tree.set_column_title(3, "WEIGHT") # Labels the complete stack-weight column.
    _item_tree.set_column_title(4, "STATUS") # Uses a general status heading so non-equipment categories are not mislabeled.
    _item_tree.set_column_expand(0, true) # Gives remaining horizontal room to item names.
    for column: int in range(1, 5): # Visits every compact numeric or status column.
        _item_tree.set_column_expand(column, false) # Prevents compact columns from consuming unnecessary width.
    _item_tree.set_column_custom_minimum_width(1, 64) # Reserves readable width for quantities.
    _item_tree.set_column_custom_minimum_width(2, 90) # Reserves readable width for per-item weights.
    _item_tree.set_column_custom_minimum_width(3, 105) # Reserves readable width for stack weights.
    _item_tree.set_column_custom_minimum_width(4, 110) # Reserves readable width for equipment status text.

func _set_inventory_open(enabled: bool) -> void: # Applies inventory visibility and gameplay-input ownership atomically.
    if enabled == _is_open: # Detects requests that would not change interface state.
        return # Avoids redundant visibility and input mutations.
    if enabled and (_player == null or _inventory == null): # Rejects opening before required runtime models are available.
        return # Leaves the interface closed when it cannot present authoritative state.
    _is_open = enabled # Stores the new explicit overlay state.
    visible = _is_open # Mirrors the state into CanvasLayer visibility.
    if _is_open: # Handles the transition into inventory interaction.
        _player.set_gameplay_input_enabled(false) # Suspends ordinary player gameplay controls.
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # Exposes the pointer for tab and row interaction.
        _refresh_inventory() # Ensures category counts and rows are current the moment the panel opens.
        return # Leaves close-only behavior out of the open path.
    if _player != null: # Verifies the player still exists when leaving the inventory.
        _player.set_gameplay_input_enabled(true) # Restores ordinary gameplay controls after the overlay closes.

func _on_item_activated() -> void: # Toggles equipment when the activated inventory row represents an equippable item.
    if not _is_open or _equipment == null: # Rejects activation outside an interactive inventory or without equipment support.
        return # Leaves non-equipment inventory behavior unchanged.
    var selected: TreeItem = _item_tree.get_selected() # Reads the currently activated table row.
    if selected == null: # Detects activation without a valid item row.
        return # Stops without attempting metadata access.
    var metadata: Variant = selected.get_metadata(0) # Reads the stable item identifier stored on the row.
    if metadata == null: # Detects informational rows such as empty-category messages.
        return # Leaves informational rows inert.
    var item_id: StringName = StringName(str(metadata)) # Converts row metadata back into the stable item identifier type.
    if not EquipmentCatalog.is_equippable(item_id): # Rejects rows that are not registered weapon or tool definitions.
        return # Leaves potion, book, ingredient, armour, and miscellaneous rows unaffected.
    if _equipment.get_equipped_item_id() == item_id: # Detects activation of the item currently in hand.
        _equipment.unequip() # Removes the active equipment item.
    else: # Handles activation of another equippable inventory row.
        _equipment.equip_item(item_id) # Equips the selected registered item.
    _refresh_inventory() # Updates status text immediately after the equipment mutation.

func _refresh_inventory() -> void: # Rebuilds category counts, filtered rows, equipment status, and the global carrying summary.
    _refresh_category_tab_titles() # Updates every tab label with its current held item-unit count.
    _item_tree.clear() # Removes rows from the previously displayed category.
    var root_item: TreeItem = _item_tree.create_item() # Creates the hidden Tree root required before adding rows.
    var selected_category: int = _get_selected_category() # Captures the currently active category for this complete refresh.
    if _inventory == null: # Handles interface composition before an authoritative inventory is available.
        var unavailable_item: TreeItem = _item_tree.create_item(root_item) # Creates one inert diagnostic row.
        unavailable_item.set_text(0, "Inventory unavailable") # Explains why no items can be displayed.
        unavailable_item.set_selectable(0, false) # Prevents the diagnostic row from behaving like an item.
        _weight_label.text = "WEIGHT  0.00 / 0.00 kg" # Resets the weight summary to a safe unavailable state.
        _weight_bar.max_value = MINIMUM_WEIGHT_RANGE # Keeps the progress bar's numerical range valid.
        _weight_bar.value = 0.0 # Clears any previous carrying-progress value.
        _displayed_category = selected_category # Records the category represented by the unavailable view.
        return # Stops before reading missing inventory state.

    var equipped_item_id: StringName = _equipment.get_equipped_item_id() if _equipment != null else &"" # Reads the currently held equipment identifier for row status.
    var visible_stack_count: int = 0 # Counts rows matching the selected category so empty tabs can show a useful message.
    for stack_index: int in range(_inventory.get_stack_count()): # Visits every stored stack while preserving stable insertion order.
        var stack: InventoryStack = _inventory.get_stack_at(stack_index) # Reads one immutable stack reference from the authoritative model.
        if stack == null or stack.get_category() != selected_category: # Rejects invalid rows and stacks assigned to another tab.
            continue # Leaves nonmatching categories out of the current table without allocating filtered copies.
        visible_stack_count += 1 # Records one visible stack in the active category.
        var item_id: StringName = stack.get_item_id() # Reads the stable item identifier used for equipment lookup and row metadata.
        var row_item: TreeItem = _item_tree.create_item(root_item) # Creates one table row under the hidden root.
        row_item.set_metadata(0, item_id) # Stores the stable identifier for activation behavior.
        row_item.set_text(0, stack.get_display_name()) # Shows the human-readable item name.
        row_item.set_text(1, str(stack.get_quantity())) # Shows the number of held units in this stack.
        row_item.set_text(2, "%.2f kg" % stack.get_unit_weight()) # Shows the weight contributed by one unit.
        row_item.set_text(3, "%.2f kg" % stack.get_stack_weight()) # Shows the complete weight contributed by this stack.
        if EquipmentCatalog.is_equippable(item_id): # Detects registered weapons and tools that support direct inventory equipping.
            row_item.set_text(4, "EQUIPPED" if item_id == equipped_item_id else "READY") # Shows whether the equipment is active or available.
            row_item.set_tooltip_text(0, "Double-click or press Enter to equip/unequip.") # Documents the existing activation interaction on equippable rows.
        else: # Handles all ordinary inventory items without equipment behavior.
            row_item.set_text(4, "-") # Leaves the general status column intentionally empty for unsupported item actions.
        for numeric_column: int in range(1, 4): # Visits quantity and weight columns.
            row_item.set_text_alignment(numeric_column, HORIZONTAL_ALIGNMENT_RIGHT) # Aligns numeric values consistently for easier scanning.
    if visible_stack_count == 0: # Detects a valid category with no currently held stacks.
        var empty_item: TreeItem = _item_tree.create_item(root_item) # Creates one inert empty-state row.
        empty_item.set_text(0, "No items in %s" % InventoryCategory.get_display_name(selected_category)) # Names the empty category explicitly rather than implying the whole inventory is empty.
        empty_item.set_selectable(0, false) # Prevents the empty-state row from receiving item activation.

    var total_weight: float = _inventory.get_total_weight() # Calculates weight across every category because carrying capacity is global.
    var maximum_weight: float = _inventory.get_maximum_weight() # Reads the live stamina-derived global capacity.
    var is_overweight: bool = total_weight > maximum_weight + PlayerInventory.WEIGHT_EPSILON # Detects a meaningful capacity overrun while tolerating floating-point noise.
    _weight_label.text = "WEIGHT  %.2f / %.2f kg" % [total_weight, maximum_weight] # Shows total carried mass independently of the active tab.
    if is_overweight: # Handles an exceeded carrying limit.
        _weight_label.text += "  OVER LIMIT" # Adds an explicit textual warning alongside the numeric summary.
        _weight_label.add_theme_color_override("font_color", OVERWEIGHT_TEXT_COLOUR) # Colours the warning state clearly.
    else: # Handles ordinary carrying weight within the live limit.
        _weight_label.add_theme_color_override("font_color", NORMAL_TEXT_COLOUR) # Restores the normal summary colour.

    _weight_bar.max_value = maxf(maximum_weight, MINIMUM_WEIGHT_RANGE) # Applies a valid progress range even if carrying capacity reaches zero.
    _weight_bar.value = clampf(total_weight, 0.0, _weight_bar.max_value) # Shows total carried mass clamped to the visible bar range.
    _displayed_inventory_revision = _inventory.get_revision() # Records the inventory version represented by this refresh.
    _displayed_equipment_revision = _equipment.get_revision() if _equipment != null else -1 # Records the equipment version represented by status text.
    _displayed_maximum_weight = maximum_weight # Records the carrying limit represented by the weight controls.
    _displayed_category = selected_category # Records the category represented by the current item rows.

func _refresh_category_tab_titles() -> void: # Updates every tab with its current number of held item units.
    for category: int in range(InventoryCategory.get_count()): # Visits each category in stable tab order.
        var item_count: int = _inventory.get_total_item_count_for_category(category) if _inventory != null else 0 # Reads the authoritative quantity total without creating filtered arrays.
        _category_tabs.set_tab_title(category, "%s (%d)" % [InventoryCategory.get_display_name(category), item_count]) # Shows a concise live count beside each category name.

func _get_selected_category() -> int: # Resolves the active TabBar index into a safe inventory category.
    var category: int = _category_tabs.current_tab # Reads the current tab directly so no category-change signal is required.
    if not InventoryCategory.is_valid(category): # Handles startup or malformed TabBar state defensively.
        return InventoryCategory.Type.WEAPONS_TOOLS # Falls back to the first requested category.
    return category # Returns the valid category matching the active tab.
