extends CanvasLayer # Displays reusable player resource bars through ordinary Godot interface nodes.
class_name PlayerStatusHud # Makes the status HUD available to typed gameplay systems without global state.

const HUD_LAYER: int = 90 # Places the player HUD above underwater effects but beneath inventory and developer console layers.
const MINIMUM_RESOURCE_MAXIMUM: float = 0.001 # Prevents invalid zero-range progress bars when future systems initialize values.

@onready var _health_bar: ProgressBar = $StatusPanel/ContentMargin/StatusStack/HealthRow/HealthBar # Stores the red health progress bar authored in the HUD scene.
@onready var _stamina_bar: ProgressBar = $StatusPanel/ContentMargin/StatusStack/StaminaRow/StaminaBar # Stores the green stamina progress bar authored in the HUD scene.
@onready var _mana_bar: ProgressBar = $StatusPanel/ContentMargin/StatusStack/ManaRow/ManaBar # Stores the blue mana progress bar authored in the HUD scene.

var _vitals: PlayerVitals # Supplies authoritative current and maximum resource values owned by the player.
var _displayed_revision: int = -1 # Caches the last rendered vitals revision for bounded polling without signals.

func _ready() -> void: # Applies the intended interface draw order after the reusable scene enters the tree.
    layer = HUD_LAYER # Keeps the status bars visible above world-space and underwater rendering.

func initialize(vitals: PlayerVitals) -> void: # Connects the HUD to the player-owned resource model.
    _vitals = vitals # Stores the authoritative source shared with inventory weight capacity.
    _refresh_from_vitals() # Displays accurate values immediately after game composition initializes the HUD.

func _process(_delta: float) -> void: # Refreshes the bars only when authoritative resource values have changed.
    if _vitals == null or _vitals.get_revision() == _displayed_revision: # Detects unavailable or unchanged player resources.
        return # Avoids redundant progress-bar assignments every frame.
    _refresh_from_vitals() # Applies the latest current and maximum health, stamina, and mana values.

func set_health(current_value: float, maximum_value: float) -> void: # Updates health using explicit current and maximum values for compatibility with direct callers.
    _set_resource_bar(_health_bar, current_value, maximum_value) # Clamps and applies the health range without signals.

func set_stamina(current_value: float, maximum_value: float) -> void: # Updates stamina using explicit current and maximum values for compatibility with direct callers.
    _set_resource_bar(_stamina_bar, current_value, maximum_value) # Clamps and applies the stamina range without signals.

func set_mana(current_value: float, maximum_value: float) -> void: # Updates mana using explicit current and maximum values for compatibility with direct callers.
    _set_resource_bar(_mana_bar, current_value, maximum_value) # Clamps and applies the mana range without signals.

func set_all_resources(health: float, health_maximum: float, stamina: float, stamina_maximum: float, mana: float, mana_maximum: float) -> void: # Updates every displayed player resource in one direct call.
    set_health(health, health_maximum) # Applies the supplied health state.
    set_stamina(stamina, stamina_maximum) # Applies the supplied stamina state.
    set_mana(mana, mana_maximum) # Applies the supplied mana state.

func _refresh_from_vitals() -> void: # Copies the complete player resource state into the three authored progress bars.
    if _vitals == null: # Handles calls before game composition supplies the resource model.
        return # Leaves authored defaults visible until initialization completes.
    set_all_resources(_vitals.get_health(), _vitals.get_maximum_health(), _vitals.get_stamina(), _vitals.get_maximum_stamina(), _vitals.get_mana(), _vitals.get_maximum_mana()) # Keeps all displayed resources synchronized with player-owned values.
    _displayed_revision = _vitals.get_revision() # Records the rendered resource revision.

func _set_resource_bar(bar: ProgressBar, current_value: float, maximum_value: float) -> void: # Applies one safe resource range to an authored Godot progress bar.
    var safe_maximum: float = maxf(maximum_value, MINIMUM_RESOURCE_MAXIMUM) # Guarantees a valid positive range even during partial initialization.
    bar.max_value = safe_maximum # Updates the progress bar's real maximum value for correct percentage display.
    bar.value = clampf(current_value, 0.0, safe_maximum) # Restricts the current value to the valid resource range.
