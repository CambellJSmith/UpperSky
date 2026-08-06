extends CanvasLayer # Displays a reusable in-game command console above the active three-dimensional scene.
class_name DeveloperConsole # Makes the console available to the game composition root through strong typing.

const CONSOLE_HEIGHT: float = 320.0 # Defines the fixed upper-screen height occupied while the console is open.
const CONSOLE_LAYER: int = 100 # Keeps developer controls above ordinary game interface layers.
const TOGGLE_UNICODE_GRAVE: int = 96 # Recognizes the unshifted physical tilde key as a grave accent character.
const TOGGLE_UNICODE_TILDE: int = 126 # Recognizes the shifted physical tilde character on keyboard layouts that report it directly.

var _player: FirstPersonPlayer # Stores the active player whose movement commands and input lock are controlled by the console.
var _day_night_cycle: DayNightCycle # Caches the active world clock resolved through its scene-tree group.
var _panel: PanelContainer # Owns the complete visible console surface.
var _output: RichTextLabel # Displays command history, status text, and command results.
var _command_line: LineEdit # Receives the current command without relying on signals.
var _command_history: Array[String] = [] # Retains submitted commands for keyboard history navigation.
var _history_index: int = 0 # Tracks the currently selected command-history entry.
var _is_open: bool = false # Tracks whether the console currently owns keyboard and mouse input.

func _ready() -> void: # Builds the console interface when the node enters the active scene tree.
    layer = CONSOLE_LAYER # Places the canvas above normal game rendering and interface elements.
    process_mode = Node.PROCESS_MODE_ALWAYS # Keeps console input available independently from future tree pause states.
    _build_interface() # Creates the complete interface programmatically to keep the console reusable and self-contained.
    _resolve_day_night_cycle() # Caches the active world clock when it is already present in the scene.
    _set_console_open(false) # Starts with gameplay active and the console hidden.

func initialize(player: FirstPersonPlayer) -> void: # Connects the console to the active player without signals or global state.
    _player = player # Stores the strongly typed player reference used by console commands.

func _input(event: InputEvent) -> void: # Handles console keyboard input before focused controls or gameplay consume it.
    if not event is InputEventKey: # Restricts console handling to keyboard events.
        return # Leaves mouse, controller, and unrelated input untouched.
    var key_event: InputEventKey = event as InputEventKey # Converts the generic input event into its strongly typed keyboard form.
    if not key_event.pressed or key_event.echo: # Ignores releases and operating-system key-repeat events.
        return # Prevents repeated toggles or duplicate command execution from one held key.
    if _is_console_toggle_key(key_event): # Detects the physical grave or tilde key regardless of shift state.
        _set_console_open(not _is_open) # Alternates between gameplay and console ownership.
        get_viewport().set_input_as_handled() # Prevents the toggle character from entering the command line or reaching gameplay.
        return # Stops after completing the console toggle.
    if not _is_open: # Checks whether console-specific navigation should currently be active.
        return # Leaves ordinary gameplay keyboard input untouched while the console is closed.
    if key_event.keycode == KEY_ESCAPE: # Allows Escape to close the console without submitting text.
        _set_console_open(false) # Returns keyboard and mouse ownership to gameplay.
        get_viewport().set_input_as_handled() # Prevents Escape from reaching unrelated interface systems.
        return # Stops after closing the console.
    if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER: # Detects either ordinary or keypad command submission.
        _submit_current_command() # Parses and executes the complete current command line.
        get_viewport().set_input_as_handled() # Prevents the focused LineEdit from processing Enter separately.
        return # Stops after command execution.
    if key_event.keycode == KEY_UP: # Detects backward command-history navigation.
        _navigate_history(-1) # Loads the preceding submitted command into the input field.
        get_viewport().set_input_as_handled() # Prevents caret movement inside the LineEdit.
        return # Stops after history navigation.
    if key_event.keycode == KEY_DOWN: # Detects forward command-history navigation.
        _navigate_history(1) # Loads the following command or returns to an empty input line.
        get_viewport().set_input_as_handled() # Prevents caret movement inside the LineEdit.

func _build_interface() -> void: # Creates the complete console panel, output history, and command field.
    _panel = PanelContainer.new() # Allocates the upper-screen console background and layout root.
    _panel.name = "ConsolePanel" # Gives the generated panel a stable diagnostic name.
    _panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE) # Stretches the console across the complete viewport width.
    _panel.offset_bottom = CONSOLE_HEIGHT # Sets the authored console height beneath the top viewport edge.
    _panel.mouse_filter = Control.MOUSE_FILTER_STOP # Prevents clicks through the open console into gameplay.
    var panel_style: StyleBoxFlat = StyleBoxFlat.new() # Allocates a dark readable panel style without external theme resources.
    panel_style.bg_color = Color(0.025, 0.03, 0.035, 0.96) # Gives the console an almost opaque charcoal background.
    panel_style.border_color = Color(0.22, 0.28, 0.32, 1.0) # Defines a restrained cool-grey lower border.
    panel_style.border_width_bottom = 2 # Separates the console clearly from the rendered world beneath it.
    _panel.add_theme_stylebox_override("panel", panel_style) # Applies the authored panel style to the generated container.
    add_child(_panel) # Adds the complete console surface to this canvas layer.

    var margin: MarginContainer = MarginContainer.new() # Creates consistent internal padding around console contents.
    margin.add_theme_constant_override("margin_left", 12) # Adds readable space along the left edge.
    margin.add_theme_constant_override("margin_top", 10) # Adds readable space above the output history.
    margin.add_theme_constant_override("margin_right", 12) # Adds readable space along the right edge.
    margin.add_theme_constant_override("margin_bottom", 10) # Adds readable space below the command field.
    _panel.add_child(margin) # Places the padded content region inside the panel.

    var vertical_layout: VBoxContainer = VBoxContainer.new() # Stacks output history above the command input.
    vertical_layout.add_theme_constant_override("separation", 8) # Separates the history and command field clearly.
    margin.add_child(vertical_layout) # Places the vertical layout inside the padded region.

    _output = RichTextLabel.new() # Allocates the scrolling command and status history display.
    _output.name = "Output" # Gives the output control a stable diagnostic name.
    _output.size_flags_vertical = Control.SIZE_EXPAND_FILL # Uses all panel height not required by the command field.
    _output.scroll_following = true # Keeps the newest command result visible automatically.
    _output.selection_enabled = true # Allows developers to select and copy console output.
    _output.bbcode_enabled = false # Treats commands and results as literal text rather than markup.
    _output.add_theme_font_size_override("normal_font_size", 15) # Keeps console history readable at ordinary desktop resolutions.
    vertical_layout.add_child(_output) # Adds the scrolling output above the command line.

    _command_line = LineEdit.new() # Allocates the editable command input control.
    _command_line.name = "CommandLine" # Gives the generated input a stable diagnostic name.
    _command_line.placeholder_text = "Enter command" # Shows the field purpose whenever it is empty.
    _command_line.clear_button_enabled = true # Provides a direct way to discard partially typed commands.
    _command_line.add_theme_font_size_override("font_size", 16) # Makes entered commands visually distinct and readable.
    vertical_layout.add_child(_command_line) # Places the command input beneath the output history.

    _write_line("UpperSky developer console") # Identifies the console when it is first opened.
    _write_line("Type 'help' for available commands.") # Directs the developer toward command discovery.

func _set_console_open(enabled: bool) -> void: # Transfers input ownership between the console and ordinary gameplay.
    _is_open = enabled # Stores the requested console state.
    if _panel != null: # Checks whether the generated interface is available during initialization.
        _panel.visible = _is_open # Shows or hides the complete console surface.
    if _player != null: # Checks whether the game has supplied the active player reference.
        _player.set_gameplay_input_enabled(not _is_open) # Suppresses movement and look while console text input is active.
    if _is_open: # Checks whether the command line should receive immediate keyboard focus.
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # Releases the mouse for console text selection and editing.
        if _command_line != null: # Verifies that the command field has already been created.
            _command_line.call_deferred("grab_focus") # Focuses after the current input event finishes propagating.
        return # Stops after opening and focusing the console.
    if _command_line != null: # Checks whether a focused command field exists while closing.
        _command_line.release_focus() # Removes interface keyboard focus before gameplay resumes.

func _submit_current_command() -> void: # Reads, records, and executes the command currently entered by the developer.
    var command: String = _command_line.text.strip_edges() # Removes accidental leading and trailing whitespace from the entered command.
    _command_line.clear() # Clears the input immediately for the next command.
    if command.is_empty(): # Detects a blank submission.
        return # Ignores empty commands without adding noise to the history.
    _command_history.append(command) # Retains the exact submitted command for history navigation.
    _history_index = _command_history.size() # Resets navigation to the empty position after the newest entry.
    _write_line("> %s" % command) # Echoes the submitted command into the output history.
    _execute_command(command) # Dispatches the parsed command to its implementation.

func _execute_command(command: String) -> void: # Parses and executes one complete console command without signals.
    var arguments: PackedStringArray = command.split(" ", false) # Splits the command into non-empty space-separated tokens.
    if arguments.is_empty(): # Handles a defensive empty parse result.
        return # Leaves the console unchanged when no command token exists.
    var command_name: String = arguments[0].to_lower() # Makes command names case-insensitive while preserving argument text.
    match command_name: # Selects the implementation associated with the first token.
        "help": # Lists all currently supported developer commands.
            _write_help() # Writes the compact command reference.
        "clear": # Clears all visible console history.
            _output.clear() # Removes previous commands and results from the output control.
        "fly": # Controls collision-free first-person flight.
            _execute_fly_command(arguments) # Parses the optional on or off argument and updates the player.
        "time": # Inspects or modifies the active day and night cycle.
            _execute_time_command(arguments) # Parses status, speed, or direct-time arguments.
        _: # Handles every unregistered command name.
            _write_line("Unknown command: %s" % arguments[0]) # Reports the unrecognized command without changing game state.

func _write_help() -> void: # Lists every supported command and its accepted syntax.
    _write_line("Commands:") # Starts the compact command reference.
    _write_line("  help                       Show this command list.") # Documents command discovery.
    _write_line("  clear                      Clear console output.") # Documents output clearing.
    _write_line("  fly [on|off]               Toggle or set fly mode.") # Documents collision-free movement.
    _write_line("  time                       Show world time and cycle speed.") # Documents clock inspection.
    _write_line("  time speed <multiplier>    Set cycle speed; 0 pauses, 1 is normal.") # Documents the requested cycle-speed control.
    _write_line("  time set <hour>            Set time directly using 0-24 hours.") # Documents direct lighting-condition testing.

func _execute_fly_command(arguments: PackedStringArray) -> void: # Applies toggle, on, or off fly-mode semantics to the active player.
    if _player == null: # Detects a console that has not yet received an active player reference.
        _write_line("Fly mode unavailable: no active player.") # Reports the missing gameplay dependency clearly.
        return # Avoids dereferencing an unavailable player.
    var fly_enabled: bool = not _player.is_fly_mode_enabled() # Uses toggle behaviour when no explicit argument is supplied.
    if arguments.size() > 1: # Detects an explicit fly-mode state argument.
        var state_argument: String = arguments[1].to_lower() # Makes the state argument case-insensitive.
        if state_argument == "on": # Detects explicit activation.
            fly_enabled = true # Requests enabled fly mode.
        elif state_argument == "off": # Detects explicit deactivation.
            fly_enabled = false # Requests ordinary collision-aware movement.
        else: # Handles unsupported fly arguments.
            _write_line("Usage: fly [on|off]") # Reports the accepted command syntax.
            return # Leaves the current fly-mode state unchanged.
    _player.set_fly_mode_enabled(fly_enabled) # Applies collision, gravity, and movement-mode changes to the player.
    if fly_enabled: # Checks whether flight was just enabled.
        _write_line("Fly mode enabled. WASD move, Space ascends, Ctrl descends, Shift accelerates.") # Reports active controls and state.
        return # Stops after the enabled-state message.
    _write_line("Fly mode disabled.") # Confirms restoration of ordinary gravity and collision.

func _execute_time_command(arguments: PackedStringArray) -> void: # Inspects or modifies the active world clock through explicit subcommands.
    var cycle: DayNightCycle = _resolve_day_night_cycle() # Resolves the active world cycle lazily in case the scene changed after console startup.
    if cycle == null: # Detects a scene without an active day and night controller.
        _write_line("Time controls unavailable: no active day/night cycle.") # Reports the missing dependency clearly.
        return # Avoids operating on an unavailable world clock.
    if arguments.size() == 1: # Treats a bare time command as a status query.
        _write_time_status(cycle) # Reports current clock time, multiplier, and effective day duration.
        return # Stops after the status response.

    var subcommand: String = arguments[1].to_lower() # Makes time subcommands case-insensitive.
    match subcommand: # Selects speed or direct-time behavior.
        "speed": # Changes the real-time rate at which the day advances.
            if arguments.size() != 3 or not arguments[2].is_valid_float(): # Requires exactly one numeric multiplier.
                _write_line("Usage: time speed <0-%g>" % DayNightCycle.MAXIMUM_SPEED_MULTIPLIER) # Reports the accepted syntax and range.
                return # Leaves the current speed unchanged.
            var multiplier: float = float(arguments[2]) # Converts the validated argument into the requested speed.
            if multiplier < 0.0 or multiplier > DayNightCycle.MAXIMUM_SPEED_MULTIPLIER: # Rejects values outside the controller's supported range.
                _write_line("Time speed must be between 0 and %g." % DayNightCycle.MAXIMUM_SPEED_MULTIPLIER) # Reports the valid range.
                return # Leaves the current speed unchanged.
            cycle.set_speed_multiplier(multiplier) # Applies the new cycle multiplier immediately.
            _write_line("Day/night speed set to %.3fx." % cycle.get_speed_multiplier()) # Confirms the applied value.
            _write_time_status(cycle) # Reports the resulting effective day duration.
        "set": # Moves the clock directly to a requested hour.
            if arguments.size() != 3 or not arguments[2].is_valid_float(): # Requires exactly one numeric hour.
                _write_line("Usage: time set <0-24>") # Reports the accepted direct-time syntax.
                return # Leaves the current clock unchanged.
            var requested_hour: float = float(arguments[2]) # Converts the validated argument into hours.
            if requested_hour < 0.0 or requested_hour > 24.0: # Restricts direct input to one intuitive day range.
                _write_line("Time must be between 0 and 24 hours.") # Reports the valid range.
                return # Leaves the current clock unchanged.
            cycle.set_time_of_day_hours(requested_hour) # Applies and renders the requested lighting condition immediately.
            _write_line("World time set to %s." % cycle.get_formatted_time()) # Confirms the normalized clock value.
        _: # Handles unsupported time subcommands.
            _write_line("Usage: time [speed <multiplier>|set <hour>]") # Reports the complete accepted time syntax.

func _write_time_status(cycle: DayNightCycle) -> void: # Reports the current world clock and real-time cycle duration.
    var speed: float = cycle.get_speed_multiplier() # Reads the exact active multiplier.
    if is_zero_approx(speed): # Detects a deliberately paused world clock.
        _write_line("World time %s | cycle paused (0x)." % cycle.get_formatted_time()) # Reports the paused state clearly.
        return # Stops because a paused day has no finite duration.
    var full_day_seconds: float = cycle.get_effective_full_day_seconds() # Calculates the real duration of one complete day at the current speed.
    var duration_text: String = "%.1f seconds" % full_day_seconds # Defaults fast cycles to a precise seconds display.
    if full_day_seconds >= 60.0: # Detects day durations that read more naturally in minutes.
        duration_text = "%.2f minutes" % (full_day_seconds / 60.0) # Converts the duration for readable console output.
    _write_line("World time %s | speed %.3fx | full day %s." % [cycle.get_formatted_time(), speed, duration_text]) # Reports all useful cycle status in one line.

func _resolve_day_night_cycle() -> DayNightCycle: # Finds the active world clock without hard-coding the game scene hierarchy.
    if is_instance_valid(_day_night_cycle): # Detects whether the cached cycle remains inside the current scene tree.
        return _day_night_cycle # Reuses the valid active cycle.
    var cycle_node: Node = get_tree().get_first_node_in_group(DayNightCycle.GROUP_NAME) # Finds the world controller through its stable group name.
    _day_night_cycle = cycle_node as DayNightCycle # Stores the strongly typed controller when the group contains the expected class.
    return _day_night_cycle # Returns the resolved cycle or null when unavailable.

func _navigate_history(direction: int) -> void: # Moves through submitted commands without relying on LineEdit signals.
    if _command_history.is_empty(): # Detects whether any prior command exists.
        return # Leaves the empty command field unchanged when history is unavailable.
    _history_index = clampi(_history_index + direction, 0, _command_history.size()) # Moves within valid history entries plus the final empty position.
    if _history_index == _command_history.size(): # Detects navigation beyond the newest saved command.
        _command_line.clear() # Restores an empty field for a new command.
        return # Stops after returning to the live input position.
    _command_line.text = _command_history[_history_index] # Loads the selected historical command into the input field.
    _command_line.caret_column = _command_line.text.length() # Places the caret at the end for immediate editing or resubmission.

func _is_console_toggle_key(key_event: InputEventKey) -> bool: # Recognizes the grave or tilde key across physical and shifted reports.
    if key_event.physical_keycode == KEY_QUOTELEFT: # Prefers the physical key position used by the requested tilde binding.
        return true # Reports a console toggle regardless of active keyboard modifiers.
    if key_event.keycode == KEY_QUOTELEFT: # Handles layouts that report the logical grave key directly.
        return true # Reports a console toggle from the logical key value.
    return key_event.unicode == TOGGLE_UNICODE_GRAVE or key_event.unicode == TOGGLE_UNICODE_TILDE # Handles text-producing grave and tilde events defensively.

func _write_line(message: String) -> void: # Appends one literal line to the scrolling console output.
    _output.append_text(message + "\n") # Adds the message and advances to a fresh output line.
