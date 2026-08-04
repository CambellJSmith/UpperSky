extends CanvasLayer # Displays reusable player resource bars through ordinary Godot interface nodes.
class_name PlayerStatusHud # Makes the status HUD available to typed gameplay systems without global state.

const HUD_LAYER: int = 90 # Places the player HUD above underwater effects but beneath the developer console.
const MINIMUM_RESOURCE_MAXIMUM: float = 0.001 # Prevents invalid zero-range progress bars when future systems initialize values.

@onready var _health_bar: ProgressBar = $StatusPanel/ContentMargin/StatusStack/HealthRow/HealthBar # Stores the red health progress bar authored in the HUD scene.
@onready var _stamina_bar: ProgressBar = $StatusPanel/ContentMargin/StatusStack/StaminaRow/StaminaBar # Stores the green stamina progress bar authored in the HUD scene.
@onready var _mana_bar: ProgressBar = $StatusPanel/ContentMargin/StatusStack/ManaRow/ManaBar # Stores the blue mana progress bar authored in the HUD scene.

func _ready() -> void: # Applies the intended interface draw order after the reusable scene enters the tree.
    layer = HUD_LAYER # Keeps the status bars visible above world-space and underwater rendering.

func set_health(current_value: float, maximum_value: float) -> void: # Updates health using explicit current and maximum values from a future health system.
    _set_resource_bar(_health_bar, current_value, maximum_value) # Clamps and applies the health range without signals.

func set_stamina(current_value: float, maximum_value: float) -> void: # Updates stamina using explicit current and maximum values from movement or action systems.
    _set_resource_bar(_stamina_bar, current_value, maximum_value) # Clamps and applies the stamina range without signals.

func set_mana(current_value: float, maximum_value: float) -> void: # Updates mana using explicit current and maximum values from future ability systems.
    _set_resource_bar(_mana_bar, current_value, maximum_value) # Clamps and applies the mana range without signals.

func set_all_resources(health: float, health_maximum: float, stamina: float, stamina_maximum: float, mana: float, mana_maximum: float) -> void: # Updates every displayed player resource in one direct call.
    set_health(health, health_maximum) # Applies the supplied health state.
    set_stamina(stamina, stamina_maximum) # Applies the supplied stamina state.
    set_mana(mana, mana_maximum) # Applies the supplied mana state.

func _set_resource_bar(bar: ProgressBar, current_value: float, maximum_value: float) -> void: # Applies one safe resource range to an authored Godot progress bar.
    var safe_maximum: float = maxf(maximum_value, MINIMUM_RESOURCE_MAXIMUM) # Guarantees a valid positive range even during partial initialization.
    bar.max_value = safe_maximum # Updates the progress bar's real maximum value for correct percentage display.
    bar.value = clampf(current_value, 0.0, safe_maximum) # Restricts the current value to the valid resource range.
