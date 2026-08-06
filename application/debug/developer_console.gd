extends CanvasLayer # Displays a reusable in-game command console above the active three-dimensional scene.
class_name DeveloperConsole # Makes the console available to the game composition root through strong typing.

const CONSOLE_HEIGHT: float = 320.0 # Defines the fixed upper-screen height occupied while the console is open.
const CONSOLE_LAYER: int = 100 # Keeps developer controls above ordinary game interface layers.
const TOGGLE_UNICODE_GRAVE: int = 96 # Recognizes the unshifted physical tilde key as a grave accent character.
const TOGGLE_UNICODE_TILDE: int = 126 # Recognizes the shifted physical tilde character on keyboard layouts that report it directly.

var _player: FirstPersonPlayer # Stores the active player controlled by developer movement commands.
var _day_night_cycle: DayNightCycle # Caches the active world clock resolved through its scene-tree group.
var _panel: PanelContainer # Owns the visible console surface.
var _output: RichTextLabel # Displays command history and results.
var _command_line: LineEdit # Receives the current command.
var _command_history: Array[String] = [] # Retains submitted commands for keyboard navigation.
var _history_index: int = 0 # Tracks the selected command-history entry.
var _is_open: bool = false # Tracks whether the console owns keyboard and mouse input.

func _ready() -> void: # Builds the interface and begins hidden.
    layer = CONSOLE_LAYER # Places the console above ordinary interface layers.
    process_mode = Node.PROCESS_MODE_ALWAYS # Keeps console input available independently from future pause states.
    _build_interface() # Creates the complete interface programmatically.
    _resolve_day_night_cycle() # Caches the active world clock when already available.
    _set_console_open(false) # Starts with gameplay active.

func initialize(player: FirstPersonPlayer) -> void: # Connects the console to the active player.
    _player = player # Stores the strongly typed player reference.

func _input(event: InputEvent) -> void: # Handles console keyboard input before gameplay consumes it.
    if not event is InputEventKey: # Restricts handling to keyboard events.
        return # Leaves unrelated input untouched.
    var key_event: InputEventKey = event as InputEventKey # Converts the event to its keyboard type.
    if not key_event.pressed or key_event.echo: # Ignores releases and operating-system repeat events.
        return # Prevents duplicate actions from held keys.
    if _is_console_toggle_key(key_event): # Detects grave or tilde regardless of shift state.
        _set_console_open(not _is_open) # Alternates console ownership.
        get_viewport().set_input_as_handled() # Prevents the toggle from reaching gameplay or the input field.
        return # Stops after toggling.
    if not _is_open: # Checks whether console-specific keys should be active.
        return # Leaves ordinary gameplay keys untouched.
    if key_event.keycode == KEY_ESCAPE: # Allows Escape to close the console.
        _set_console_open(false) # Returns input to gameplay.
        get_viewport().set_input_as_handled() # Prevents Escape from reaching other systems.
        return # Stops after closing.
    if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER: # Detects command submission.
        _submit_current_command() # Parses and executes the current line.
        get_viewport().set_input_as_handled() # Prevents separate LineEdit processing.
        return # Stops after submission.
    if key_event.keycode == KEY_UP: # Detects older-history navigation.
        _navigate_history(-1) # Loads the preceding command.
        get_viewport().set_input_as_handled() # Prevents caret movement.
        return # Stops after navigation.
    if key_event.keycode == KEY_DOWN: # Detects newer-history navigation.
        _navigate_history(1) # Loads the following command or an empty line.
        get_viewport().set_input_as_handled() # Prevents caret movement.

func _build_interface() -> void: # Creates the console panel, output history, and command field.
    _panel = PanelContainer.new() # Allocates the upper-screen console surface.
    _panel.name = "ConsolePanel" # Gives the panel a stable diagnostic name.
    _panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE) # Stretches across the viewport width.
    _panel.offset_bottom = CONSOLE_HEIGHT # Sets the fixed authored height.
    _panel.mouse_filter = Control.MOUSE_FILTER_STOP # Prevents clicks passing through to gameplay.
    var panel_style: StyleBoxFlat = StyleBoxFlat.new() # Allocates a dark readable style.
    panel_style.bg_color = Color(0.025, 0.03, 0.035, 0.96) # Gives the console an almost opaque charcoal background.
    panel_style.border_color = Color(0.22, 0.28, 0.32, 1.0) # Defines a restrained lower border.
    panel_style.border_width_bottom = 2 # Separates the console from the world beneath it.
    _panel.add_theme_stylebox_override("panel", panel_style) # Applies the authored style.
    add_child(_panel) # Adds the console surface to this canvas layer.

    var margin: MarginContainer = MarginContainer.new() # Creates consistent internal padding.
    margin.add_theme_constant_override("margin_left", 12) # Pads the left edge.
    margin.add_theme_constant_override("margin_top", 10) # Pads the top edge.
    margin.add_theme_constant_override("margin_right", 12) # Pads the right edge.
    margin.add_theme_constant_override("margin_bottom", 10) # Pads the bottom edge.
    _panel.add_child(margin) # Places the padded region inside the panel.

    var layout: VBoxContainer = VBoxContainer.new() # Stacks history above input.
    layout.add_theme_constant_override("separation", 8) # Separates the two controls clearly.
    margin.add_child(layout) # Places the layout inside the padded region.

    _output = RichTextLabel.new() # Allocates command and result history.
    _output.name = "Output" # Gives the control a stable diagnostic name.
    _output.size_flags_vertical = Control.SIZE_EXPAND_FILL # Uses available panel height.
    _output.scroll_following = true # Keeps the newest result visible.
    _output.selection_enabled = true # Allows text selection and copying.
    _output.bbcode_enabled = false # Treats output as literal text.
    _output.add_theme_font_size_override("normal_font_size", 15) # Keeps history readable.
    layout.add_child(_output) # Adds the history display.

    _command_line = LineEdit.new() # Allocates the editable input field.
    _command_line.name = "CommandLine" # Gives the field a stable diagnostic name.
    _command_line.placeholder_text = "Enter command" # Shows its purpose when empty.
    _command_line.clear_button_enabled = true # Allows partial commands to be discarded directly.
    _command_line.add_theme_font_size_override("font_size", 16) # Keeps entered commands readable.
    layout.add_child(_command_line) # Adds the input below history.

    _write_line("UpperSky developer console") # Identifies the console.
    _write_line("Type 'help' for available commands.") # Directs developers toward command discovery.

func _set_console_open(enabled: bool) -> void: # Transfers input ownership between console and gameplay.
    _is_open = enabled # Stores the requested state.
    if _panel != null: # Checks whether the generated interface exists.
        _panel.visible = _is_open # Shows or hides the complete console.
    if _player != null: # Checks whether an active player is connected.
        _player.set_gameplay_input_enabled(not _is_open) # Suppresses gameplay input while typing.
    if _is_open: # Checks whether console input should receive focus.
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # Releases the mouse for text editing.
        if _command_line != null: # Verifies the command field exists.
            _command_line.call_deferred("grab_focus") # Focuses after the current event finishes.
        return # Stops after opening.
    if _command_line != null: # Checks whether a focused field exists while closing.
        _command_line.release_focus() # Removes interface keyboard focus.

func _submit_current_command() -> void: # Records and executes the current command line.
    var command: String = _command_line.text.strip_edges() # Removes accidental surrounding whitespace.
    _command_line.clear() # Clears input for the next command.
    if command.is_empty(): # Detects blank submissions.
        return # Ignores empty commands.
    _command_history.append(command) # Retains the command for history navigation.
    _history_index = _command_history.size() # Resets navigation to the live empty position.
    _write_line("> %s" % command) # Echoes the submitted command.
    _execute_command(command) # Dispatches it to an implementation.

func _execute_command(command: String) -> void: # Parses and executes one complete command.
    var arguments: PackedStringArray = command.split(" ", false) # Splits into non-empty tokens.
    if arguments.is_empty(): # Handles an empty defensive parse result.
        return # Leaves the console unchanged.
    match arguments[0].to_lower(): # Selects the command by case-insensitive first token.
        "help": # Lists available commands.
            _write_help() # Writes the compact reference.
        "clear": # Clears output history.
            _output.clear() # Removes previous lines.
        "fly": # Controls collision-free movement.
            _execute_fly_command(arguments) # Parses optional state and updates the player.
        "time": # Inspects or modifies the world clock.
            _execute_time_command(arguments) # Parses status, speed, or direct-time arguments.
        _: # Handles unregistered commands.
            _write_line("Unknown command: %s" % arguments[0]) # Reports the unrecognized token.

func _write_help() -> void: # Lists supported commands and syntax.
    _write_line("Commands:") # Starts the reference.
    _write_line("  help                       Show this command list.") # Documents discovery.
    _write_line("  clear                      Clear console output.") # Documents output clearing.
    _write_line("  fly [on|off]               Toggle or set fly mode.") # Documents flight control.
    _write_line("  time                       Show world time and cycle speed.") # Documents clock inspection.
    _write_line("  time speed <multiplier>    Set cycle speed; 0 pauses, 1 is normal.") # Documents cycle-speed control.
    _write_line("  time set <hour>            Set time directly using 0-24 hours.") # Documents direct time changes.

func _execute_fly_command(arguments: PackedStringArray) -> void: # Applies toggle, on, or off semantics to fly mode.
    if _player == null: # Detects a console without an active player.
        _write_line("Fly mode unavailable: no active player.") # Reports the missing dependency.
        return # Avoids dereferencing it.
    var enabled: bool = not _player.is_fly_mode_enabled() # Uses toggle behavior by default.
    if arguments.size() > 1: # Detects an explicit state.
        match arguments[1].to_lower(): # Parses the state case-insensitively.
            "on": # Detects activation.
                enabled = true # Requests fly mode.
            "off": # Detects deactivation.
                enabled = false # Requests ordinary movement.
            _: # Handles unsupported state arguments.
                _write_line("Usage: fly [on|off]") # Reports accepted syntax.
                return # Leaves current state unchanged.
    _player.set_fly_mode_enabled(enabled) # Applies movement and collision changes.
    if enabled: # Checks whether flight is now active.
        _write_line("Fly mode enabled. WASD move, Space ascends, Ctrl descends, Shift accelerates.") # Reports controls.
        return # Stops after enabled-state output.
    _write_line("Fly mode disabled.") # Confirms ordinary movement.

func _execute_time_command(arguments: PackedStringArray) -> void: # Inspects or modifies the active world clock.
    var cycle: DayNightCycle = _resolve_day_night_cycle() # Resolves the controller lazily.
    if cycle == null: # Detects a scene without the cycle.
        _write_line("Time controls unavailable: no active day/night cycle.") # Reports the missing dependency.
        return # Avoids operating on null.
    if arguments.size() == 1: # Treats a bare command as a status query.
        _write_time_status(cycle) # Reports time, multiplier, and duration.
        return # Stops after status output.
    match arguments[1].to_lower(): # Selects a time subcommand.
        "speed": # Changes how quickly the cycle advances.
            _set_time_speed(arguments, cycle) # Validates and applies the multiplier.
        "set": # Moves directly to a requested hour.
            _set_world_time(arguments, cycle) # Validates and applies the hour.
        _: # Handles unsupported subcommands.
            _write_line("Usage: time [speed <multiplier>|set <hour>]") # Reports complete syntax.

func _set_time_speed(arguments: PackedStringArray, cycle: DayNightCycle) -> void: # Validates and applies a cycle multiplier.
    var maximum_speed: int = int(DayNightCycle.MAXIMUM_SPEED_MULTIPLIER) # Converts the supported maximum into console-friendly integer text.
    if arguments.size() != 3 or not arguments[2].is_valid_float(): # Requires exactly one numeric argument.
        _write_line("Usage: time speed <0-%d>" % maximum_speed) # Reports syntax and range.
        return # Leaves speed unchanged.
    var multiplier: float = float(arguments[2]) # Converts the validated token.
    if multiplier < 0.0 or multiplier > DayNightCycle.MAXIMUM_SPEED_MULTIPLIER: # Rejects unsupported values.
        _write_line("Time speed must be between 0 and %d." % maximum_speed) # Reports the valid range.
        return # Leaves speed unchanged.
    cycle.set_speed_multiplier(multiplier) # Applies the new multiplier immediately.
    _write_line("Day/night speed set to %.3fx." % cycle.get_speed_multiplier()) # Confirms the applied value.
    _write_time_status(cycle) # Reports the resulting effective day duration.

func _set_world_time(arguments: PackedStringArray, cycle: DayNightCycle) -> void: # Validates and applies a direct hour.
    if arguments.size() != 3 or not arguments[2].is_valid_float(): # Requires exactly one numeric argument.
        _write_line("Usage: time set <0-24>") # Reports accepted syntax.
        return # Leaves time unchanged.
    var requested_hour: float = float(arguments[2]) # Converts the validated token.
    if requested_hour < 0.0 or requested_hour > 24.0: # Restricts input to one intuitive day range.
        _write_line("Time must be between 0 and 24 hours.") # Reports the valid range.
        return # Leaves time unchanged.
    cycle.set_time_of_day_hours(requested_hour) # Applies and renders the requested condition immediately.
    _write_line("World time set to %s." % cycle.get_formatted_time()) # Confirms the normalized clock value.

func _write_time_status(cycle: DayNightCycle) -> void: # Reports current world time and real-time cycle duration.
    var speed: float = cycle.get_speed_multiplier() # Reads the exact active multiplier.
    if is_zero_approx(speed): # Detects a paused cycle.
        _write_line("World time %s | cycle paused (0x)." % cycle.get_formatted_time()) # Reports the paused state.
        return # Stops because there is no finite day duration.
    var full_day_seconds: float = cycle.get_effective_full_day_seconds() # Calculates the current full-day duration.
    var duration_text: String = "%.1f seconds" % full_day_seconds # Defaults fast cycles to seconds.
    if full_day_seconds >= 60.0: # Detects durations clearer in minutes.
        duration_text = "%.2f minutes" % (full_day_seconds / 60.0) # Converts them for readable output.
    _write_line("World time %s | speed %.3fx | full day %s." % [cycle.get_formatted_time(), speed, duration_text]) # Reports complete status.

func _resolve_day_night_cycle() -> DayNightCycle: # Finds the active cycle without hard-coding scene hierarchy.
    if is_instance_valid(_day_night_cycle): # Detects whether the cached cycle remains valid.
        return _day_night_cycle # Reuses it.
    var cycle_node: Node = get_tree().get_first_node_in_group(DayNightCycle.GROUP_NAME) # Finds the controller through its stable group.
    _day_night_cycle = cycle_node as DayNightCycle # Stores the strongly typed result when available.
    return _day_night_cycle # Returns the active cycle or null.

func _navigate_history(direction: int) -> void: # Moves through submitted commands.
    if _command_history.is_empty(): # Detects absent history.
        return # Leaves input unchanged.
    _history_index = clampi(_history_index + direction, 0, _command_history.size()) # Keeps navigation within saved entries and the final empty position.
    if _history_index == _command_history.size(): # Detects the live empty position.
        _command_line.clear() # Restores an empty input field.
        return # Stops after clearing.
    _command_line.text = _command_history[_history_index] # Loads the selected command.
    _command_line.caret_column = _command_line.text.length() # Places the caret at the end.

func _is_console_toggle_key(key_event: InputEventKey) -> bool: # Recognizes grave or tilde across physical and logical reports.
    if key_event.physical_keycode == KEY_QUOTELEFT: # Prefers the physical grave-key position.
        return true # Reports a toggle regardless of modifiers.
    if key_event.keycode == KEY_QUOTELEFT: # Handles logical grave-key reports.
        return true # Reports a toggle.
    return key_event.unicode == TOGGLE_UNICODE_GRAVE or key_event.unicode == TOGGLE_UNICODE_TILDE # Handles text-producing reports defensively.

func _write_line(message: String) -> void: # Appends one literal line to console output.
    _output.append_text(message + "\n") # Adds the message and advances to a fresh line.
