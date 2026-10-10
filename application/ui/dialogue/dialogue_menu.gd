extends CanvasLayer # Present the authored conversation through editor-defined controls.
class_name DialogueMenu # Keep presentation separate from world targeting and conversation state.

signal topic_selected(topic: String) # Report the player's authored response selection.
signal close_requested # Report an explicit goodbye request.

@onready var _shade: Control = $Shade # Own the modal backdrop and conversation panel.
@onready var _panel: PanelContainer = $Shade/Margins/Center/Panel # Resize the editor-authored panel with the viewport.
@onready var _title: Label = $Shade/Margins/Center/Panel/Content/Title # Display the speaker's identity.
@onready var _response: Label = $Shade/Margins/Center/Panel/Content/Response # Display plain text without interpreting world names as markup.
@onready var _topics: VBoxContainer = $Shade/Margins/Center/Panel/Content/Topics # Retain authored keyboard and controller focus targets.
@onready var _goodbye: Button = $Shade/Margins/Center/Panel/Content/Goodbye # Provide an explicit conversation exit.

func _ready() -> void: # Connect scene-authored buttons once.
    var index: int = 0 # Map authored buttons to the stable topic order.
    for topic: String in DialoguePhrases.TOPICS: # Wire every supported conversation topic.
        var button: Button = _topics.get_child(index) as Button # Resolve an existing editor-defined control.
        button.text = DialoguePhrases.TOPICS[topic] # Use the authored player phrase.
        button.pressed.connect(func() -> void: topic_selected.emit(topic)) # Report the selected topic without embedding world logic.
        index += 1 # Advance to the next authored topic button.
    _goodbye.pressed.connect(func() -> void: close_requested.emit()) # Route the exit through conversation cleanup.
    get_viewport().size_changed.connect(_resize) # Adapt the panel only when viewport dimensions change.
    _resize() # Apply the initial viewport constraints.
    _shade.hide() # Start with ordinary gameplay visible.

func present(title: String, response: String) -> void: # Open the menu with the resolved speaker and initial line.
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
