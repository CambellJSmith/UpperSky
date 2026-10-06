extends CanvasLayer # Displays reusable player resource bars through ordinary Godot interface nodes.
class_name PlayerStatusHud # Makes the status HUD available to typed gameplay systems without global state.

const HUD_LAYER: int = 90 # Places the player HUD above underwater effects but beneath inventory and developer console layers.
const MINIMUM_RESOURCE_MAXIMUM: float = 0.001 # Prevents invalid zero-range progress bars when future systems initialize values.

var _rings: ResourceRings

var _vitals: PlayerVitals # Supplies authoritative current and maximum resource values owned by the player.
var _displayed_revision: int = -1 # Caches the last rendered vitals revision for bounded polling without signals.

func _ready() -> void: # Applies draw order and resolves the player-owned resource model from the authored game scene.
    layer = HUD_LAYER # Keeps the status bars visible above world-space and underwater rendering.
    $StatusPanel.hide()
    _rings = ResourceRings.new()
    _rings.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _rings.position = Vector2(-190.0, 20.0)
    _rings.custom_minimum_size = Vector2(170.0, 170.0)
    _rings.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_rings)
    var vitals_node: Node = get_node_or_null("../DynamicEntities/Player/PlayerVitals") # Finds the authoritative vitals node mounted inside the active player scene.
    if vitals_node is PlayerVitals: # Verifies the authored dependency has the expected strong type.
        initialize(vitals_node as PlayerVitals) # Connects the status bars to the same stamina maximum used by inventory capacity.

func initialize(vitals: PlayerVitals) -> void: # Connects the HUD to the player-owned resource model.
    _vitals = vitals # Stores the authoritative source shared with inventory weight capacity.
    _refresh_from_vitals() # Displays accurate values immediately after game composition initializes the HUD.

func _process(_delta: float) -> void: # Refreshes the bars only when authoritative resource values have changed.
    if _vitals == null or _vitals.get_revision() == _displayed_revision: # Detects unavailable or unchanged player resources.
        return # Avoids redundant progress-bar assignments every frame.
    _refresh_from_vitals() # Applies the latest current and maximum health, stamina, and mana values.

func set_health(current_value: float, maximum_value: float) -> void: # Updates health using explicit current and maximum values for compatibility with direct callers.
    _rings.health = clampf(current_value / maxf(maximum_value, MINIMUM_RESOURCE_MAXIMUM), 0.0, 1.0)

func set_stamina(current_value: float, maximum_value: float) -> void: # Updates stamina using explicit current and maximum values for compatibility with direct callers.
    _rings.stamina = clampf(current_value / maxf(maximum_value, MINIMUM_RESOURCE_MAXIMUM), 0.0, 1.0)

func set_mana(current_value: float, maximum_value: float) -> void: # Updates mana using explicit current and maximum values for compatibility with direct callers.
    _rings.mana = clampf(current_value / maxf(maximum_value, MINIMUM_RESOURCE_MAXIMUM), 0.0, 1.0)
    _rings.queue_redraw()

func set_all_resources(health: float, health_maximum: float, stamina: float, stamina_maximum: float, mana: float, mana_maximum: float) -> void: # Updates every displayed player resource in one direct call.
    set_health(health, health_maximum) # Applies the supplied health state.
    set_stamina(stamina, stamina_maximum) # Applies the supplied stamina state.
    set_mana(mana, mana_maximum) # Applies the supplied mana state.

func _refresh_from_vitals() -> void: # Copies the complete player resource state into the three authored progress bars.
    if _vitals == null: # Handles calls before game composition supplies the resource model.
        return # Leaves authored defaults visible until initialization completes.
    set_all_resources(_vitals.get_health(), _vitals.get_maximum_health(), _vitals.get_stamina(), _vitals.get_maximum_stamina(), _vitals.get_mana(), _vitals.get_maximum_mana()) # Keeps all displayed resources synchronized with player-owned values.
    _displayed_revision = _vitals.get_revision() # Records the rendered resource revision.

class ResourceRings extends Control:
    var health := 1.0
    var stamina := 1.0
    var mana := 1.0
    func _draw() -> void:
        var centre := Vector2(85, 85)
        _ring(centre, 76, health, Color("d43b3b"))
        _ring(centre, 61, stamina, Color("39bd62"))
        _ring(centre, 46, mana, Color("4d8cff"))
    func _ring(centre: Vector2, radius: float, fraction: float, colour: Color) -> void:
        draw_arc(centre, radius, 0.0, TAU, 96, Color(0.06, 0.07, 0.09, 0.8), 7.0, true)
        if fraction > 0.001:
            draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * fraction, 96, colour, 7.0, true)
