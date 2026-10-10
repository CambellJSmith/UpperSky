extends CanvasLayer # Coordinate talking with existing game interaction ownership.
class_name DialogueInteraction # Resolve NPC targets and drive a separate editor-authored conversation menu.

signal encounter_resolved(npc: Villager, accepted: bool) # Notify the director after the player resolves a spontaneous encounter.

const TALK_DISTANCE: float = 3.0 # Keep conversations within ordinary interaction reach.
const TARGET_INTERVAL: float = 0.12 # Bound prompt raycasts independently of rendering speed.
@onready var _player: FirstPersonPlayer = $"../DynamicEntities/Player" # Resolve the existing gameplay input owner.
@onready var _terrain: InfiniteTerrain = $"../World/Terrain" # Resolve the actual procedural geography.
@onready var _menu: DialogueMenu = $Menu # Resolve the composed menu scene.
@onready var _prompt: Label = $Prompt # Resolve the authored interaction prompt.
var _encounter_accepted: bool = false # Preserve a completed friendly exchange until the player dismisses its confirmation.
var _encounter_definition: Dictionary = {} # Retain the current unsolicited event decision until resolution.
var _speaker: Villager # Retain the current live conversation target.
var _target: Villager # Cache the prompt target between bounded raycasts.
var _elapsed: float = 0.0 # Track the next prompt refresh.
var _context: Dictionary = {} # Retain one factual world snapshot per conversation.
var _turns: Dictionary[String, int] = {} # Rotate alternatives separately for each topic.
var _cycle: DayNightCycle # Read the clock without repeatedly searching groups.

func _ready() -> void: # Connect presentation to conversation state once.
    _cycle = get_tree().get_first_node_in_group(DayNightCycle.GROUP_NAME) as DayNightCycle # Resolve the optional world clock.
    _menu.topic_selected.connect(_speak) # Handle player-authored topic choices.
    _menu.encounter_selected.connect(_resolve_encounter) # Handle explicit consent through one authoritative state transition.
    _menu.close_requested.connect(close_dialogue) # Centralize conversation cleanup.
    _prompt.hide() # Hide interaction hints until a valid target is found.

func _process(delta: float) -> void: # Monitor live conversations and throttle closed-menu targeting.
    if not _context.is_empty(): # Validate the active actor even while the menu owns input.
        _prompt.hide() # Avoid overlapping hints during conversation.
        if not _speaker_valid(): # Handle death, fighting, unloads and moving out of reach.
            close_dialogue() # Restore gameplay and release the NPC immediately.
        return # Avoid geography queries and target raycasts while conversing.
    if not _gameplay_active(): # Respect inventory, loading and other modal interfaces.
        _prompt.hide() # Remove stale conversation hints.
        _target = null # Avoid retaining an outdated target.
        return # Leave current input ownership untouched.
    _elapsed += delta # Accumulate time for bounded target refresh.
    if _elapsed < TARGET_INTERVAL: # Skip repeated physics queries between refreshes.
        return # Preserve the current hint until its next refresh.
    _elapsed = 0.0 # Restart the bounded target interval.
    _target = _ray_target() # Read the closest unobstructed interaction target.
    _prompt.visible = is_instance_valid(_target) # Show the hint only for an eligible actor.

func _unhandled_input(event: InputEvent) -> void: # Open dialogue only when earlier gameplay handlers did not consume interaction.
    if event is InputEventKey and event.echo: # Ignore held-key repetition.
        return # Require a new interaction press.
    if event.is_action_pressed("Interact") and _gameplay_active(): # Reuse the game's mapped keyboard and controller interaction.
        var npc: Villager = _ray_target() # Revalidate immediately rather than trusting the prompt cache.
        if npc != null and open_dialogue(npc): # Reserve the eligible speaker before opening the menu.
            get_viewport().set_input_as_handled() # Prevent talking and another interaction from sharing a press.

func _input(event: InputEvent) -> void: # Handle conversation-only controls before gameplay input dispatch.
    if _context.is_empty() or (event is InputEventKey and event.echo): # Ignore input outside an active conversation or from repetition.
        return # Leave ordinary gameplay input routing unchanged.
    if event.is_action_pressed("ui_cancel") or event.is_action_pressed("Button_B") or event.is_action_pressed("Interact") or event.is_action_pressed("Inventory"): # Support the mapped conversation exit controls.
        close_dialogue() # Release input and speaker ownership together.
        get_viewport().set_input_as_handled() # Prevent the closing press from reopening another menu.
    elif event.is_action_pressed("Button_A"): # Support the project's controller confirmation action.
        var focus: Control = get_viewport().gui_get_focus_owner() # Resolve the currently highlighted topic.
        if focus is Button and _menu.is_ancestor_of(focus): # Restrict confirmation to this conversation's controls.
            (focus as Button).pressed.emit() # Activate the focused authored option.
            get_viewport().set_input_as_handled() # Prevent the same press from triggering a jump.
    elif event.is_action_pressed("StickLeft_North") or event.is_action_pressed("StickLeft_South"): # Support the project's mapped controller navigation.
        var focus: Control = get_viewport().gui_get_focus_owner() # Resolve the current conversation control.
        if focus != null and _menu.is_ancestor_of(focus): # Keep focus movement inside the active menu.
            var next: Control = focus.find_prev_valid_focus() if event.is_action_pressed("StickLeft_North") else focus.find_next_valid_focus() # Follow authored control order.
            if next != null: # Require an available focusable control.
                next.grab_focus() # Move the highlighted conversation choice.
            get_viewport().set_input_as_handled() # Keep navigation from reaching player movement.

func open_dialogue(npc: Villager) -> bool: # Open a conversation only during active gameplay and within reach.
    if not _context.is_empty() or not _gameplay_active() or not is_instance_valid(npc) or _player.global_position.distance_to(npc.global_position) > TALK_DISTANCE + 1.0: # Reject occupied menus and invalid remote actors.
        return false # Leave input ownership unchanged.
    if not npc.begin_dialogue(self): # Require the actor to accept exclusive conversation ownership.
        return false # Respect dead, hostile and otherwise unavailable speakers.
    _speaker = npc # Retain the accepted speaker for lifecycle checks.
    _context = DialogueContext.build(npc, _terrain, _cycle) # Resolve factual substitutions once rather than per frame.
    _turns.clear() # Restart topic variation for the new exchange.
    _player.set_gameplay_input_enabled(false) # Give the conversation exclusive player input.
    _menu.present((npc.get_relationship_species() + " " + npc.role.trim_prefix("radiant_").replace("_", " ")).capitalize(), _line("greeting")) # Present the actual speaker and contextual opening line.
    _prompt.hide() # Remove the interaction hint immediately.
    return true # Confirm successful menu ownership.

func close_dialogue() -> void: # Restore gameplay after every conversation exit path.
    if _speaker == null and _context.is_empty(): # Avoid claiming input when this menu was never open.
        return # Preserve another interface's ownership.
    var event_speaker: Villager = _speaker if is_instance_valid(_speaker) else null # Preserve a valid actor for the event completion signal.
    var was_encounter: bool = not _encounter_definition.is_empty() # Treat every ordinary close as peaceful refusal.
    var event_accepted: bool = _encounter_accepted # Preserve completed friendly consent when its confirmation closes.
    _encounter_accepted = false # Reset completion state before callbacks can open another conversation.
    _encounter_definition.clear() # Prevent duplicate consent resolution or reentrant callbacks.
    if is_instance_valid(_speaker): # Release a surviving actor's conversation reservation.
        _speaker.end_dialogue(self) # Resume ordinary wandering without resetting its route.
    _speaker = null # Drop the actor reference after release.
    _context.clear() # Release the conversation's factual snapshot.
    _menu.dismiss() # Hide the menu and its focus controls.
    if is_instance_valid(_player): # Restore controls only while the player still exists.
        _player.set_gameplay_input_enabled(true) # Return mouse capture and gameplay input.
    if was_encounter: # Notify event ownership after ordinary conversation cleanup completes.
        encounter_resolved.emit(event_speaker, event_accepted) # Distinguish a pending refusal from an already completed friendly exchange.

func _speak(topic: String) -> void: # Respond to a selected authored player phrase.
    if not _speaker_valid(): # Revalidate after an actor dies or unloads between frames.
        close_dialogue() # Release ownership instead of displaying a stale response.
        return # Stop the invalid conversation.
    if DialoguePhrases.TOPICS.has(topic): # Accept only authored topics.
        _menu.show_response(_line(topic)) # Expand and display the next contextual phrase.

func _line(topic: String) -> String: # Rotate topic alternatives using a stable per-speaker starting point.
    var turn: int = _turns.get(topic, 0) # Read this topic's current variation count.
    _turns[topic] = turn + 1 # Advance without affecting other topics.
    return DialoguePhrases.response(topic, _context, posmod(hash(str(_speaker.get_social_record().get("npc_id", _speaker.name)) + topic), 100000) + turn) # Vary speakers and repeated questions predictably.

func _speaker_valid() -> bool: # Guard every live actor access against streaming and death.
    return is_instance_valid(_speaker) and _speaker.can_talk() and _player.is_physics_processing() and not _player.get_health_state().is_dead() and _player.global_position.distance_to(_speaker.global_position) <= 4.5 # Close when either participant becomes unavailable.

func _gameplay_active() -> bool: # Respect existing input ownership and loading state.
    return is_instance_valid(_player) and _player.is_physics_processing() and not _player.get_health_state().is_dead() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED # Allow targeting only during live gameplay.

func _ray_target() -> Villager: # Use the first collision hit so walls and other interactables occlude speakers.
    var camera: Camera3D = _player.get_view_camera() # Resolve the player's actual view.
    var start: Vector3 = camera.global_position # Start the interaction ray at the camera.
    var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, start - camera.global_basis.z * TALK_DISTANCE) # Limit conversation targeting to ordinary reach.
    query.collide_with_areas = true # Respect bedrolls, doors and other interaction areas as occluders.
    query.exclude = [_player.get_rid()] # Ignore the player's own body.
    var hit: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(query) # Read one bounded physics query.
    if hit.is_empty(): # Reject empty view directions.
        return null # Leave the prompt hidden.
    var node: Node = hit.collider as Node # Resolve the closest hit's composed actor owner.
    while node != null: # Support nested model colliders without scene-name assumptions.
        if node is Villager: # Identify an actual NPC root.
            var npc: Villager = node as Villager # Access the actor's public dialogue eligibility.
            return npc if npc.can_talk() else null # Reject corpses, hostile actors and non-human species.
        node = node.get_parent() # Follow composition to the actor root.
    return null # Reject scenery and other interactables.

func _exit_tree() -> void: # Release speaker ownership when the scene or interface is removed.
    if is_instance_valid(_speaker): # Avoid accessing an already unloaded NPC.
        _speaker.end_dialogue(self) # Prevent a surviving actor from remaining in conversation idle.
    if not _context.is_empty() and is_instance_valid(_player) and _player.is_inside_tree(): # Restore controls if only the dialogue interface is removed.
        _player.set_gameplay_input_enabled(true) # Release this interface's input ownership during teardown.

func can_start_encounter() -> bool: # Expose modal readiness without revealing controller internals to the director.
    return _context.is_empty() and _gameplay_active() # Wait for live gameplay and exclusive conversation availability.

func open_encounter(npc: Villager, kind: String) -> bool: # Start an unsolicited conversation only after the actor arrives.
    if not is_instance_valid(npc) or not can_start_encounter(): # Respect actor lifetime and current input ownership before preparing goods.
        return false # Avoid changing stock while another menu owns gameplay.
    var quote: Dictionary = RadiantOfferService.prepare(npc, kind) # Retain one stock-backed quote for the actor's lifetime.
    if quote.is_empty() or not open_dialogue(npc): # Reuse ordinary reach, health, species and input ownership checks.
        return false # Leave the current gameplay or menu undisturbed.
    _encounter_definition = RadiantOfferService.render(quote, _context) # Expand exact item terms and real world facts once per conversation.
    _encounter_accepted = false # Start with an explicitly pending player decision.
    _menu.present_encounter(_encounter_definition) # Offer authored event-specific acceptance and refusal controls.
    return true # Confirm that the actor has started its radiant conversation.

func _resolve_encounter(accepted: bool) -> void: # Apply consent exactly once before releasing the conversation.
    if _encounter_definition.is_empty() or _encounter_accepted: # Reject stale buttons after a friendly exchange has completed.
        return # Avoid duplicate gifts, purchases, payments or hostility.
    if not _speaker_valid(): # Revalidate combat, death, range and streaming at the moment of selection.
        close_dialogue() # Treat an invalid pending conversation as cancellation.
        return # Do not mutate unavailable actors or player inventory.
    if not accepted: # Preserve all goods and affection when the player refuses.
        close_dialogue() # Route refusal through ordinary conversation cleanup and event scheduling.
        return # Leave the stored quote unused while the actor departs.
    var npc: Villager = _speaker # Preserve the accepted actor across menu cleanup.
    var inventory: PlayerInventory = _player.get_node("PlayerInventory") as PlayerInventory # Resolve the authoritative player-owned inventory.
    var outcome: Dictionary = RadiantOfferService.accept(npc, inventory) # Settle the stored quote with full stock, payment and weight validation.
    if not outcome.success: # Keep a failed exchange pending without charging or granting anything.
        _menu.show_response(outcome.message) # Explain missing payment, stock or carrying capacity in the actual menu.
        return # Allow a peaceful refusal or a later valid retry.
    if outcome.get("hostile", false): # Resume accepted battle challenges immediately.
        _encounter_definition.clear() # Suppress the ordinary-close refusal callback during explicit battle resolution.
        close_dialogue() # Restore gameplay before the hostile actor's next combat update.
        encounter_resolved.emit(npc, true) # Report the accepted battle once to the director.
        return # Avoid holding an already hostile actor behind a confirmation screen.
    _encounter_accepted = true # Keep a successful friendly transaction immune to repeated button presses.
    _menu.present_encounter_result(str(_encounter_definition.get("success", outcome.message))) # Show the authored result or factual local information before goodbye.
