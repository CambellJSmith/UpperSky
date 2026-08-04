extends CharacterBody3D # Provides collision-aware walking, water swimming, and optional collision-free developer flight.
class_name FirstPersonPlayer # Makes the player type available to typed gameplay and developer-console code.

const WALK_SPEED: float = 7.5 # Defines the player's faster normal movement speed across the monumental terrain.
const SPRINT_SPEED: float = 12.0 # Defines the player's faster sprint movement speed.
const GROUND_ACCELERATION: float = 38.0 # Keeps faster grounded movement responsive when starting, stopping, or changing direction.
const AIR_ACCELERATION: float = 11.0 # Preserves proportionate directional adjustment while airborne at the higher travel speed.
const JUMP_VELOCITY: float = 7.0 # Defines the upward velocity applied when jumping.
const SWIM_SPEED: float = 6.5 # Defines faster ordinary horizontal movement while the body is immersed.
const SWIM_SPRINT_SPEED: float = 10.5 # Defines faster swimming while the sprint input is held.
const SWIM_VERTICAL_SPEED: float = 6.0 # Defines faster explicit ascent and descent while swimming.
const SWIM_ACCELERATION: float = 16.0 # Keeps faster swimming responsive while retaining noticeable water resistance.
const SWIM_BODY_SAMPLE_HEIGHT: float = 0.9 # Tests immersion at the capsule centre rather than at the player's feet.
const SWIM_SURFACE_ROOT_DEPTH: float = 1.48 # Buoys the player toward a root height that leaves the camera close to the surface.
const SWIM_BUOYANCY_RESPONSE: float = 0.65 # Converts displacement from the preferred floating depth into vertical swim input.
const FLY_SPEED: float = 35.0 # Provides useful traversal speed across the monumental terrain while fly mode is active.
const FLY_SPRINT_SPEED: float = 120.0 # Provides accelerated developer traversal while the ordinary sprint input is held.
const FLY_ACCELERATION: float = 70.0 # Controls how quickly collision-free movement reaches its requested velocity.
const MOUSE_LOOK_SENSITIVITY: float = 0.0025 # Converts mouse motion into camera rotation.
const CONTROLLER_LOOK_SPEED: float = 2.6 # Converts right-stick input into camera rotation.
const MINIMUM_PITCH: float = deg_to_rad(-89.0) # Prevents the camera from rotating beyond straight down.
const MAXIMUM_PITCH: float = deg_to_rad(89.0) # Prevents the camera from rotating beyond straight up.

@onready var _collision_shape: CollisionShape3D = $CollisionShape3D # Stores the capsule node used for movement and spawn placement queries.
@onready var _head: Node3D = $Head # Stores the pivot used for vertical camera rotation.
@onready var _camera: Camera3D = $Head/Camera3D # Stores the rendered camera used by underwater view testing.

var _terrain: InfiniteTerrain # Supplies authoritative water occupancy, level, and floating-origin conversion for swimming.
var _gravity: float = 0.0 # Stores the project gravity used by ordinary player movement.
var _pitch: float = 0.0 # Tracks the current vertical viewing angle.
var _gameplay_input_enabled: bool = true # Prevents movement and look input while the developer console owns the keyboard.
var _fly_mode_enabled: bool = false # Tracks whether gravity and collision-free flight are active.
var _swimming_enabled: bool = false # Tracks whether the body centre currently occupies a real generated water volume.
var _current_water_level: float = 0.0 # Stores the active local water surface used for buoyancy and vertical movement.
var _initial_collision_layer: int = 0 # Retains the authored collision layer for restoration after fly mode.
var _initial_collision_mask: int = 0 # Retains the authored collision mask for restoration after fly mode.
var _initial_motion_mode: int = CharacterBody3D.MOTION_MODE_GROUNDED # Retains the authored grounded motion mode for restoration after swimming or flight.

func _ready() -> void: # Initializes the player when it enters the active scene tree.
    _gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity")) # Reads gravity once instead of querying project settings every physics frame.
    _initial_collision_layer = collision_layer # Stores the authored player collision layer before any developer command can change it.
    _initial_collision_mask = collision_mask # Stores the authored player collision mask before any developer command can change it.
    _initial_motion_mode = motion_mode # Stores the authored grounded motion mode before entering swimming or collision-free flight.
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # Captures the mouse for immediate first-person camera control.

func initialize_environment(terrain: InfiniteTerrain) -> void: # Connects movement to the authoritative procedural terrain and water system.
    _terrain = terrain # Stores the terrain controller without signals or global state.

func get_collision_shape() -> Shape3D: # Exposes the player capsule resource for collision-safe external placement queries.
    return _collision_shape.shape # Returns the same shape used by CharacterBody3D movement collision.

func get_collision_local_transform() -> Transform3D: # Exposes the capsule offset relative to the player root for accurate shape queries.
    return _collision_shape.transform # Returns the authored collision-node transform without leaking mutable node ownership.

func get_view_camera() -> Camera3D: # Exposes the exact first-person camera to view-dependent environmental effects.
    return _camera # Returns the active rendered camera owned by the player.

func set_gameplay_input_enabled(enabled: bool) -> void: # Transfers movement and look ownership between gameplay and the developer console.
    _gameplay_input_enabled = enabled # Stores whether player controls should currently respond to input.
    if not _gameplay_input_enabled: # Detects console ownership or another temporary input lock.
        velocity.x = 0.0 # Stops retained horizontal movement along the x axis immediately.
        velocity.z = 0.0 # Stops retained horizontal movement along the z axis immediately.
        if _fly_mode_enabled or _swimming_enabled: # Checks whether gravity-free or buoyant movement is currently active.
            velocity.y = 0.0 # Stops retained vertical movement while commands are being entered.
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # Releases the mouse for interface interaction.
        return # Stops after applying the input lock.
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # Recaptures the mouse when gameplay control resumes.

func set_fly_mode_enabled(enabled: bool) -> void: # Enables or disables collision-free gravity-free developer traversal.
    if enabled == _fly_mode_enabled: # Detects whether the requested state is already active.
        return # Avoids resetting movement or collision properties unnecessarily.
    _fly_mode_enabled = enabled # Stores the newly requested fly-mode state.
    velocity = Vector3.ZERO # Removes falling, jumping, swimming, or flight momentum during the mode transition.
    if _fly_mode_enabled: # Checks whether collision-free flight must now be activated.
        _set_swimming_enabled(false) # Prevents water physics from competing with explicit developer flight.
        collision_layer = 0 # Prevents the flying player from acting as a collidable object for other bodies.
        collision_mask = 0 # Prevents move_and_slide from colliding with terrain or world geometry.
        motion_mode = CharacterBody3D.MOTION_MODE_FLOATING # Removes grounded floor semantics while flying in three dimensions.
        return # Stops after enabling every fly-mode property.
    collision_layer = _initial_collision_layer # Restores the authored player collision layer.
    collision_mask = _initial_collision_mask # Restores the authored player collision mask.
    motion_mode = _initial_motion_mode # Restores ordinary grounded motion until water state is refreshed on the next physics step.

func is_fly_mode_enabled() -> bool: # Reports the current developer flight state to console commands and future diagnostics.
    return _fly_mode_enabled # Returns whether collision-free movement is currently active.

func is_swimming() -> bool: # Reports whether ordinary movement has currently transitioned into water physics.
    return _swimming_enabled # Returns the authoritative body-immersion state.

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

func _physics_process(delta: float) -> void: # Advances walking, swimming, or fly movement using the fixed physics timestep.
    if _gameplay_input_enabled: # Checks whether look input should currently control the view.
        _apply_controller_look(delta) # Applies right-stick camera movement independently from mouse events.
    _update_water_state() # Resolves body immersion from the same terrain and water fields used by rendered geometry.
    if _fly_mode_enabled: # Selects collision-free three-dimensional movement when requested by the console.
        _apply_fly_movement(delta) # Applies horizontal, vertical, and accelerated developer flight.
    elif _swimming_enabled: # Selects buoyant collision-aware movement while the body occupies real water.
        _apply_swim_movement(delta) # Applies water drag, horizontal swimming, ascent, descent, and surface buoyancy.
    else: # Uses ordinary gravity and floor movement outside water and fly mode.
        _apply_vertical_movement(delta) # Applies gravity and jump input to the vertical velocity.
        _apply_horizontal_movement(delta) # Accelerates horizontal velocity toward the requested movement direction.
    move_and_slide() # Moves using terrain collision during walking and swimming, or no collision during fly mode.

func _update_water_state() -> void: # Determines whether the player's body centre is inside an actual generated water volume.
    if _terrain == null or _fly_mode_enabled: # Waits for environment initialization and lets fly mode take priority over water.
        _set_swimming_enabled(false) # Restores ordinary state whenever water cannot control movement.
        return # Skips unavailable or overridden water sampling.
    var player_world_position: Vector3 = _terrain.local_to_world_position(global_position) # Converts the near-origin player transform into stable procedural-world coordinates.
    var horizontal_position: Vector2 = Vector2(player_world_position.x, player_world_position.z) # Extracts the coordinate used by terrain and water samplers.
    var water_exists: bool = _terrain.has_water_at(horizontal_position) # Verifies that clipped water geometry exists at this location.
    _current_water_level = _terrain.get_water_level_at(horizontal_position) # Stores the exact local flat water level for buoyancy.
    var body_sample_height: float = player_world_position.y + SWIM_BODY_SAMPLE_HEIGHT # Tests immersion at the capsule centre rather than at its feet.
    _set_swimming_enabled(water_exists and body_sample_height < _current_water_level) # Enables swimming only after the body centre crosses below a real water surface.

func _set_swimming_enabled(enabled: bool) -> void: # Applies or removes the movement-mode changes required by swimming.
    if enabled == _swimming_enabled: # Detects whether immersion state is unchanged.
        return # Avoids resetting motion mode every physics frame.
    _swimming_enabled = enabled # Stores the newly resolved water state.
    if _fly_mode_enabled: # Checks whether developer flight still owns motion semantics.
        return # Leaves floating fly mode untouched while it is active.
    motion_mode = CharacterBody3D.MOTION_MODE_FLOATING if _swimming_enabled else _initial_motion_mode # Uses collision-aware floating movement in water and grounded movement on land.
    if _swimming_enabled: # Detects the moment the player first enters water.
        velocity.y *= 0.35 # Dampens a hard fall into water without eliminating all entry momentum.

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

func _apply_swim_movement(delta: float) -> void: # Updates collision-aware movement, water drag, and buoyancy inside a real water volume.
    var movement_input: Vector2 = Vector2.ZERO # Defaults to no horizontal swim input while gameplay controls are unavailable.
    var vertical_input: float = 0.0 # Defaults to neutral buoyant movement before explicit ascent or descent input.
    if _gameplay_input_enabled: # Checks whether the player currently owns swim controls.
        movement_input = Input.get_vector("StickLeft_West", "StickLeft_East", "StickLeft_North", "StickLeft_South") # Reuses ordinary movement controls for horizontal swimming.
        if Input.is_action_pressed("Button_A"): # Uses Space or the primary controller button for ascent.
            vertical_input += 1.0 # Requests upward swimming.
        if Input.is_action_pressed("Button_B"): # Uses Control or the secondary controller button for descent.
            vertical_input -= 1.0 # Requests downward swimming.
    var local_direction: Vector3 = Vector3(movement_input.x, 0.0, movement_input.y) # Converts horizontal swim input into the player's local yaw frame.
    var world_direction: Vector3 = global_transform.basis * local_direction # Rotates swimming so forward follows the player's facing direction.
    world_direction.y = 0.0 # Keeps horizontal swimming independent from camera pitch and terrain slope.
    world_direction = world_direction.normalized() # Keeps diagonal horizontal swimming at a consistent speed.
    var movement_speed: float = SWIM_SPEED # Selects ordinary swimming speed by default.
    if _gameplay_input_enabled and Input.is_action_pressed("StickLeft_Click"): # Reuses the sprint action for faster swimming.
        movement_speed = SWIM_SPRINT_SPEED # Applies the stronger swim pace while sprint remains held.
    var target_velocity: Vector3 = world_direction * movement_speed # Calculates the requested horizontal water velocity.
    if is_zero_approx(vertical_input): # Detects whether buoyancy should control vertical movement instead of direct input.
        var player_world_position: Vector3 = _terrain.local_to_world_position(global_position) # Reads the stable root elevation for surface floating.
        var preferred_root_height: float = _current_water_level - SWIM_SURFACE_ROOT_DEPTH # Targets a depth that leaves the camera near the surface.
        vertical_input = clampf((preferred_root_height - player_world_position.y) * SWIM_BUOYANCY_RESPONSE, -1.0, 1.0) # Converts displacement into gentle upward or downward buoyancy.
    target_velocity.y = vertical_input * SWIM_VERTICAL_SPEED # Applies explicit vertical swimming or automatic surface buoyancy.
    velocity = velocity.move_toward(target_velocity, SWIM_ACCELERATION * delta) # Uses water resistance to approach the requested three-dimensional movement smoothly.

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
