extends CanvasLayer # Present the authored conversation through editor-defined controls.
class_name DialogueMenu # Keep presentation separate from world targeting and conversation state.

signal topic_selected(topic: String) # Report the player's authored response selection.
signal encounter_selected(accepted: bool) # Report explicit consent for a spontaneous event.
signal close_requested # Report an explicit goodbye request.

@onready var _shade: Control = $Shade # Own the modal backdrop and conversation panel.
@onready var _panel: PanelContainer = $Shade/Margins/Center/Panel # Resize the editor-authored panel with the viewport.
@onready var _title: Label = $Shade/Margins/Center/Panel/Scroll/Content/Title # Display the speaker's identity.
@onready var _response: Label = $Shade/Margins/Center/Panel/Scroll/Content/Response # Display plain text without interpreting world names as markup.
@onready var _topics: VBoxContainer = $Shade/Margins/Center/Panel/Scroll/Content/Topics # Retain authored keyboard and controller focus targets.
@onready var _encounter: VBoxContainer = $Shade/Margins/Center/Panel/Scroll/Content/Encounter # Own the authored event-specific choices.
@onready var _accept: Button = $Shade/Margins/Center/Panel/Scroll/Content/Encounter/Accept # Display the event consent choice.
@onready var _decline: Button = $Shade/Margins/Center/Panel/Scroll/Content/Encounter/Decline # Display the peaceful refusal choice.
@onready var _goodbye: Button = $Shade/Margins/Center/Panel/Scroll/Content/Goodbye # Provide an explicit conversation exit.

func _ready() -> void: # Connect scene-authored buttons once.
    var index: int = 0 # Map authored buttons to the stable topic order.
    for topic: String in DialoguePhrases.TOPICS: # Wire every supported conversation topic.
        var button: Button = _topics.get_child(index) as Button # Resolve an existing editor-defined control.
        button.text = DialoguePhrases.TOPICS[topic] # Use the authored player phrase.
        button.pressed.connect(func() -> void: topic_selected.emit(topic)) # Report the selected topic without embedding world logic.
        index += 1 # Advance to the next authored topic button.
    _accept.pressed.connect(func() -> void: encounter_selected.emit(true)) # Require an explicit acceptance button press.
    _decline.pressed.connect(func() -> void: encounter_selected.emit(false)) # Route refusal through event cleanup.
    _goodbye.pressed.connect(func() -> void: close_requested.emit()) # Route the exit through conversation cleanup.
    get_viewport().size_changed.connect(_resize) # Adapt the panel only when viewport dimensions change.
    _resize() # Apply the initial viewport constraints.
    _shade.hide() # Start with ordinary gameplay visible.

func present(title: String, response: String) -> void: # Open the menu with the resolved speaker and initial line.
    _topics.show() # Restore ordinary conversation topics after a radiant event.
    _encounter.hide() # Hide event-only consent choices for normal conversations.
    _goodbye.show() # Restore the ordinary conversation exit.
    _title.text = title # Show the actual species and occupation.
    _response.text = response # Present the first authored NPC response.
    _shade.show() # Reveal the modal controls.
    (_topics.get_child(0) as Button).grab_focus() # Enable immediate keyboard and controller navigation.

func show_response(response: String) -> void: # Replace the NPC's line while keeping the chosen button focused.
    _response.text = response # Present the newly expanded phrase.

func dismiss() -> void: # Release the visible conversation interface.
    _shade.hide() # Restore an unobstructed game view.

func _resize() -> void: # Fit the panel within the current viewport margins.
    _panel.custom_minimum_size.x = minf(640.0, maxf(0.0, get_viewport().get_visible_rect().size.x - 32.0)) # Keep the menu readable on smaller windows.
    _panel.custom_minimum_size.y = minf(460.0, maxf(0.0, get_viewport().get_visible_rect().size.y - 32.0)) # Allow scrolling instead of overflowing short windows.

func present_encounter(definition: Dictionary) -> void: # Replace ordinary topics with the event's explicit decision.
    _response.text = definition.opening # Show the authored unsolicited invitation.
    _accept.text = definition.accept # Explain the effect the player is agreeing to.
    _decline.text = definition.decline # Keep a peaceful refusal clearly available.
    _topics.hide() # Avoid mixing normal topics with an unresolved event decision.
    _goodbye.hide() # Use the explicit refusal button for event exits.
    _encounter.show() # Reveal the editor-authored consent controls.
    _decline.grab_focus() # Require a deliberate selection before agreeing to battle.
