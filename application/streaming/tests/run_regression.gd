extends SceneTree # Load regression dependencies in the same order as the game.

func _initialize() -> void: # Select one regression from the command-line arguments.
    var arguments: PackedStringArray = OS.get_cmdline_user_args() # Read the requested project-relative test path.
    if arguments.size() != 1: # Require one unambiguous regression script.
        push_error("Pass One Regression Script After --") # Explain the expected invocation.
        quit(1) # Reject an incomplete test command.
        return # Stop before loading game resources.
    load("res://application/game/game.tscn") # Warm resource dependencies through the production scene to avoid existing standalone equipment preload cycles.
    var regression: Script = load("res://" + arguments[0]) # Load the selected regression after its dependencies are ready.
    if regression == null: # Reject missing or invalid regression scripts.
        quit(1) # Report a failed test setup.
        return # Preserve the running tree until shutdown.
    set_script(regression) # Let the regression own this SceneTree and its fixtures.
    call("_initialize") # Start the selected regression through its normal entry point.
