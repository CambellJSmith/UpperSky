extends CharacterBody3D # Provides collision-aware ordinary movement and optional collision-free developer flight.
class_name FirstPersonPlayer # Makes the player type available to typed gameplay and developer-console code.

const WALK_SPEED: float = 5.0 # Defines the player's normal movement speed.
const SPRINT_SPEED: float = 8.0 # Defines the player's sprint movement speed.
const GROUND_ACCELERATION: float = 28.0 # Controls how quickly grounded movement reaches its target speed.
const AIR_ACCELERATION: float = 8.0 # Controls limited directional adjustment while airborne.
const JUMP_VELOCITY: float = 7.0 # Defines the upward velocity applied when jumping.
const FLY_SPEED: float = 35.0 # Provides useful traversal speed across the monumental terrain while fly mode is active.
const FLY_SPRINT_SPEED: float = 120.0 # Provides accelerated developer traversal while the ordinary sprint input is held.
const FLY_ACCELERATION: float = 70.0 # Controls how quickly collision-free movement reaches its requested velocity.
const MOUSE_LOOK_SENSITIVITY: float = 0.0025 # Converts mouse motion into camera rotation.
const CONTROLLER_LOOK_SPEED: float = 2.6 # Converts right-stick input into camera rotation.
const MINIMUM_PITCH: float = deg_to_rad(-89.0) # Prevents the camera from rotating beyond straight down.
const MAXIMUM_PITCH: float = deg_to_rad(89.0) # Prevents the camera from rotating beyond straight up.

@onready var _collision_shape: CollisionShape3D = $CollisionShape3D # Stores the capsule node used for movement and spawn placement queries.
@onready var _head: Node3D = $Head # Stores the pivot used for vertical camera rotation.

var _gravity: float = 0.0 # Stores the project gravity used by ordinary player movement.
var _pitch: float = 0.0 # Tracks the current vertical viewing angle.
var _gameplay_input_enabled: bool = true # Prevents movement and look input while the developer console owns the keyboard.
var _fly_mode_enabled: bool = false # Tracks whether gravity and collision-free flight are active.
var _initial_collision_layer: int = 0 # Retains the authored collision layer for restoration after fly mode.
var _initial_collision_mask: int = 0 # Retains the authored collision mask for restoration after fly mode.
var _initial_motion_mode: int = CharacterBody3D.MOTION_MODE_GROUNDED # Retains the authored grounded motion mode for restoration after flight.

func _ready() -> void: # Initializes the player when it enters the active scene tree.
    _gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity")) # Reads gravity once instead of querying project settings every physics frame.
    _initial_collision_layer = collision_layer # Stores the authored player collision layer before any developer command can change it.
    _initial_collision_mask = collision_mask # Stores the authored player collision mask before any developer command can change it.
    _initial_motion_mode = motion_mode # Stores the authored grounded motion mode before entering collision-free flight.
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # Captures the mouse for immediate first-person camera control.

func get_collision_shape() -> Shape3D: # Exposes the player capsule resource for collision-safe external placement queries.
    return _collision_shape.shape # Returns the same shape used by CharacterBody3D movement collision.

func get_collision_local_transform() -> Transform3D: # Exposes the capsule offset relative to the player root for accurate shape queries.
    return _collision_shape.transform # Returns the authored collision-node transform without leaking mutable node ownership.

func set_gameplay_input_enabled(enabled: bool) -> void: # Transfers movement and look ownership between gameplay and the developer console.
    _gameplay_input_enabled = enabled # Stores whether player controls should currently respond to input.
    if not _gameplay_input_enabled: # Detects console ownership or another temporary input lock.
        velocity.x = 0.0 # Stops retained horizontal movement along the x axis immediately.
        velocity.z = 0.0 # Stops retained horizontal movement along the z axis immediately.
        if _fly_mode_enabled: # Checks whether gravity-free movement is currently active.
            velocity.y = 0.0 # Stops retained vertical flight while commands are being entered.
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # Releases the mouse for interface interaction.
        return # Stops after applying the input lock.
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # Recaptures the mouse when gameplay control resumes.

func set_fly_mode_enabled(enabled: bool) -> void: # Enables or disables collision-free gravity-free developer traversal.
    if enabled == _fly_mode_enabled: # Detects whether the requested state is already active.
        return # Avoids resetting movement or collision properties unnecessarily.
    _fly_mode_enabled = enabled # Stores the newly requested fly-mode state.
    velocity = Vector3.ZERO # Removes ordinary falling, jumping, or flight momentum during the mode transition.
    if _fly_mode_enabled: # Checks whether collision-free flight must now be activated.
        collision_layer = 0 # Prevents the flying player from acting as a collidable object for other bodies.
        collision_mask = 0 # Prevents move_and_slide from colliding with terrain or world geometry.
        motion_mode = CharacterBody3D.MOTION_MODE_FLOATING # Removes grounded floor semantics while flying in three dimensions.
        return # Stops after enabling every fly-mode property.
    collision_layer = _initial_collision_layer # Restores the authored player collision layer.
    collision_mask = _initial_collision_mask # Restores the authored player collision mask.
    motion_mode = _initial_motion_mode # Restores ordinary grounded floor and slope behaviour.

func is_fly_mode_enabled() -> bool: # Reports the current developer flight state to console commands and future diagnostics.
    return _fly_mode_enabled # Returns whether collision-free movement is currently active.

func _unhandled_input(event: InputEvent) -> void: # Handles camera input after interface controls have had an opportunity to consume it.
    if not _gameplay_input_enabled: # Detects whether the developer console currently owns input.
        return # Prevents camera movement and capture changes while entering commands.
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: # Limits mouse-look processing to captured mouse motion.
        var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion # Converts the generic event into its strongly typed mouse-motion form.
        _rotate_view(mouse_motion.relative * MOUSE_LOOK_SENSITIVITY) # Applies the mouse movement to the player's view.
        get_viewport().set_input_as_handled() # Prevents the handled mouse event from reaching unrelated nodes.
        return # Stops processing after consuming the mouse-look event.
    if event.is_action_pressed("Button_Start"): # Uses the shared start action to toggle mouse capture.
        _toggle_mouse_capture() # Switches between captured and visible mouse modes.
        get_viewport().set_input_as_handled() # Prevents the capture-toggle input from reaching unrelated nodes.

func _physics_process(delta: float) -> void: # Advances ordinary or fly movement using the fixed physics timestep.
    if _gameplay_input_enabled: # Checks whether look input should currently control the view.
        _apply_controller_look(delta) # Applies right-stick camera movement independently from mouse events.
    if _fly_mode_enabled: # Selects collision-free three-dimensional movement when requested by the console.
        _apply_fly_movement(delta) # Applies horizontal, vertical, and accelerated developer flight.
    else: # Uses ordinary gravity and floor movement outside fly mode.
        _apply_vertical_movement(delta) # Applies gravity and jump input to the vertical velocity.
        _apply_horizontal_movement(delta) # Accelerates horizontal velocity toward the requested movement direction.
    move_and_slide() # Moves using the current collision mask, which is disabled only during fly mode.

func _apply_controller_look(delta: float) -> void: # Converts right-stick input into frame-rate-independent view rotation.
    var look_input: Vector2 = Input.get_vector("StickRight_West", "StickRight_East", "StickRight_North", "StickRight_South") # Reads the normalized right-stick direction.
    if look_input.is_zero_approx(): # Avoids unnecessary transform changes when the stick is centred.
        return # Leaves the current view unchanged when there is no controller-look input.
    _rotate_view(look_input * CONTROLLER_LOOK_SPEED * delta) # Applies controller look using elapsed frame time.

func _apply_vertical_movement(delta: float) -> void: # Updates jumping and gravity without affecting horizontal movement.
    if is_on_floor(): # Checks whether the body is currently supported by a floor.
        if velocity.y < 0.0: # Detects residual downward velocity after landing.
            velocity.y = 0.0 # Clears downward velocity to keep floor contact stable.
        if _gameplay_input_enabled and Input.is_action_just_pressed("Button_A"): # Uses the shared primary action for jumping only when gameplay owns input.
            velocity.y = JUMP_VELOCITY # Applies the jump impulse to the vertical velocity.
        return # Skips gravity while grounded for stable movement.
    velocity.y -= _gravity * delta # Applies gravity while the player is airborne, including while the console is open.

func _apply_horizontal_movement(delta: float) -> void: # Updates movement along the ground plane.
    var movement_input: Vector2 = Vector2.ZERO # Defaults to no requested movement while gameplay input is unavailable.
    if _gameplay_input_enabled: # Checks whether keyboard or controller movement should be read.
        movement_input = Input.get_vector("StickLeft_West", "StickLeft_East", "StickLeft_North", "StickLeft_South") # Reads normalized keyboard or left-stick movement.
    var local_direction: Vector3 = Vector3(movement_input.x, 0.0, movement_input.y) # Converts two-dimensional input into local three-dimensional movement.
    var world_direction: Vector3 = global_transform.basis * local_direction # Rotates local movement so forward follows the player's yaw.
    world_direction.y = 0.0 # Removes any vertical component introduced by future transform changes.
    world_direction = world_direction.normalized() # Keeps diagonal movement at the same speed as cardinal movement.
    var movement_speed: float = WALK_SPEED # Selects normal walking as the default movement speed.
    if _gameplay_input_enabled and Input.is_action_pressed("StickLeft_Click"): # Checks whether the sprint action is being held during gameplay input.
        movement_speed = SPRINT_SPEED # Uses the faster sprint speed while the action remains pressed.
    var target_velocity: Vector3 = world_direction * movement_speed # Calculates the requested horizontal velocity.
    var acceleration: float = GROUND_ACCELERATION if is_on_floor() else AIR_ACCELERATION # Uses responsive ground movement and restricted air control.
    velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta) # Smoothly approaches the requested horizontal velocity on the x axis.
    velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta) # Smoothly approaches the requested horizontal velocity on the z axis.

func _apply_fly_movement(delta: float) -> void: # Updates collision-free horizontal and vertical developer flight.
    var movement_input: Vector2 = Vector2.ZERO # Defaults to no horizontal flight while the console owns input.
    var vertical_input: float = 0.0 # Defaults to no ascent or descent.
    if _gameplay_input_enabled: # Checks whether flight controls should currently respond.
        movement_input = Input.get_vector("StickLeft_West", "StickLeft_East", "StickLeft_North", "StickLeft_South") # Reuses the ordinary movement controls for horizontal flight.
        if Input.is_action_pressed("Button_A"): # Uses Space or the primary controller button for ascent.
            vertical_input += 1.0 # Requests upward world-space flight.
        if Input.is_action_pressed("Button_B"): # Uses Control or the secondary controller button for descent.
            vertical_input -= 1.0 # Requests downward world-space flight.
    var local_direction: Vector3 = Vector3(movement_input.x, 0.0, movement_input.y) # Converts horizontal input into the player's local yaw frame.
    var world_direction: Vector3 = global_transform.basis * local_direction # Rotates horizontal flight so forward follows the player's view yaw.
    world_direction.y = vertical_input # Adds explicit world-space ascent or descent independent from camera pitch.
    world_direction = world_direction.normalized() # Keeps combined diagonal and vertical flight at a consistent speed.
    var movement_speed: float = FLY_SPEED # Selects normal developer flight speed by default.
    if _gameplay_input_enabled and Input.is_action_pressed("StickLeft_Click"): # Reuses the existing sprint input for rapid traversal.
        movement_speed = FLY_SPRINT_SPEED # Uses high-speed flight while sprint remains held.
    var target_velocity: Vector3 = world_direction * movement_speed # Calculates the complete requested three-dimensional velocity.
    velocity = velocity.move_toward(target_velocity, FLY_ACCELERATION * delta) # Smoothly approaches the requested flight direction without gravity.

func _rotate_view(rotation_input: Vector2) -> void: # Applies yaw to the body and pitch to the camera pivot.
    rotate_y(-rotation_input.x) # Rotates the player's movement frame horizontally.
    _pitch = clampf(_pitch - rotation_input.y, MINIMUM_PITCH, MAXIMUM_PITCH) # Updates and clamps the vertical viewing angle.
    _head.rotation.x = _pitch # Applies pitch only to the head so the collision body remains upright.

func _toggle_mouse_capture() -> void: # Switches mouse ownership between gameplay and interface use.
    if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: # Detects whether gameplay currently owns the mouse.
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # Releases the mouse for menus and desktop interaction.
        return # Stops after releasing the mouse.
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # Recaptures the mouse for first-person camera control.
