extends CharacterBody3D # Provides collision-aware movement for the first-person player.
class_name FirstPersonPlayer # Makes the player type available to typed gameplay code.

const WALK_SPEED: float = 5.0 # Defines the player's normal movement speed.
const SPRINT_SPEED: float = 8.0 # Defines the player's sprint movement speed.
const GROUND_ACCELERATION: float = 28.0 # Controls how quickly grounded movement reaches its target speed.
const AIR_ACCELERATION: float = 8.0 # Controls limited directional adjustment while airborne.
const JUMP_VELOCITY: float = 7.0 # Defines the upward velocity applied when jumping.
const MOUSE_LOOK_SENSITIVITY: float = 0.0025 # Converts mouse motion into camera rotation.
const CONTROLLER_LOOK_SPEED: float = 2.6 # Converts right-stick input into camera rotation.
const MINIMUM_PITCH: float = deg_to_rad(-89.0) # Prevents the camera from rotating beyond straight down.
const MAXIMUM_PITCH: float = deg_to_rad(89.0) # Prevents the camera from rotating beyond straight up.

@onready var _collision_shape: CollisionShape3D = $CollisionShape3D # Stores the capsule node used for movement and spawn placement queries.
@onready var _head: Node3D = $Head # Stores the pivot used for vertical camera rotation.

var _gravity: float = 0.0 # Stores the project gravity used by player movement.
var _pitch: float = 0.0 # Tracks the current vertical viewing angle.

func _ready() -> void: # Initializes the player when it enters the active scene tree.
    _gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity")) # Reads gravity once instead of querying project settings every physics frame.
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # Captures the mouse for immediate first-person camera control.

func get_collision_shape() -> Shape3D: # Exposes the player capsule resource for collision-safe external placement queries.
    return _collision_shape.shape # Returns the same shape used by CharacterBody3D movement collision.

func get_collision_local_transform() -> Transform3D: # Exposes the capsule offset relative to the player root for accurate shape queries.
    return _collision_shape.transform # Returns the authored collision-node transform without leaking mutable node ownership.

func _unhandled_input(event: InputEvent) -> void: # Handles camera input after interface controls have had an opportunity to consume it.
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: # Limits mouse-look processing to captured mouse motion.
        var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion # Converts the generic event into its strongly typed mouse-motion form.
        _rotate_view(mouse_motion.relative * MOUSE_LOOK_SENSITIVITY) # Applies the mouse movement to the player's view.
        get_viewport().set_input_as_handled() # Prevents the handled mouse event from reaching unrelated nodes.
        return # Stops processing after consuming the mouse-look event.
    if event.is_action_pressed("Button_Start"): # Uses the shared start action to toggle mouse capture.
        _toggle_mouse_capture() # Switches between captured and visible mouse modes.
        get_viewport().set_input_as_handled() # Prevents the capture-toggle input from reaching unrelated nodes.

func _physics_process(delta: float) -> void: # Advances movement using the fixed physics timestep.
    _apply_controller_look(delta) # Applies right-stick camera movement independently from mouse events.
    _apply_vertical_movement(delta) # Applies gravity and jump input to the vertical velocity.
    _apply_horizontal_movement(delta) # Accelerates horizontal velocity toward the requested movement direction.
    move_and_slide() # Moves the character while resolving floor, wall, and ceiling collisions.

func _apply_controller_look(delta: float) -> void: # Converts right-stick input into frame-rate-independent view rotation.
    var look_input: Vector2 = Input.get_vector("StickRight_West", "StickRight_East", "StickRight_North", "StickRight_South") # Reads the normalized right-stick direction.
    if look_input.is_zero_approx(): # Avoids unnecessary transform changes when the stick is centred.
        return # Leaves the current view unchanged when there is no controller-look input.
    _rotate_view(look_input * CONTROLLER_LOOK_SPEED * delta) # Applies controller look using elapsed frame time.

func _apply_vertical_movement(delta: float) -> void: # Updates jumping and gravity without affecting horizontal movement.
    if is_on_floor(): # Checks whether the body is currently supported by a floor.
        if velocity.y < 0.0: # Detects residual downward velocity after landing.
            velocity.y = 0.0 # Clears downward velocity to keep floor contact stable.
        if Input.is_action_just_pressed("Button_A"): # Uses the shared primary action for jumping while grounded.
            velocity.y = JUMP_VELOCITY # Applies the jump impulse to the vertical velocity.
        return # Skips gravity while grounded for stable movement.
    velocity.y -= _gravity * delta # Applies gravity while the player is airborne.

func _apply_horizontal_movement(delta: float) -> void: # Updates movement along the ground plane.
    var movement_input: Vector2 = Input.get_vector("StickLeft_West", "StickLeft_East", "StickLeft_North", "StickLeft_South") # Reads normalized keyboard or left-stick movement.
    var local_direction: Vector3 = Vector3(movement_input.x, 0.0, movement_input.y) # Converts two-dimensional input into local three-dimensional movement.
    var world_direction: Vector3 = global_transform.basis * local_direction # Rotates local movement so forward follows the player's yaw.
    world_direction.y = 0.0 # Removes any vertical component introduced by future transform changes.
    world_direction = world_direction.normalized() # Keeps diagonal movement at the same speed as cardinal movement.
    var movement_speed: float = WALK_SPEED # Selects normal walking as the default movement speed.
    if Input.is_action_pressed("StickLeft_Click"): # Checks whether the sprint action is being held.
        movement_speed = SPRINT_SPEED # Uses the faster sprint speed while the action remains pressed.
    var target_velocity: Vector3 = world_direction * movement_speed # Calculates the requested horizontal velocity.
    var acceleration: float = GROUND_ACCELERATION if is_on_floor() else AIR_ACCELERATION # Uses responsive ground movement and restricted air control.
    velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta) # Smoothly approaches the requested horizontal velocity on the x axis.
    velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta) # Smoothly approaches the requested horizontal velocity on the z axis.

func _rotate_view(rotation_input: Vector2) -> void: # Applies yaw to the body and pitch to the camera pivot.
    rotate_y(-rotation_input.x) # Rotates the player's movement frame horizontally.
    _pitch = clampf(_pitch - rotation_input.y, MINIMUM_PITCH, MAXIMUM_PITCH) # Updates and clamps the vertical viewing angle.
    _head.rotation.x = _pitch # Applies pitch only to the head so the collision body remains upright.

func _toggle_mouse_capture() -> void: # Switches mouse ownership between gameplay and interface use.
    if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: # Detects whether gameplay currently owns the mouse.
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # Releases the mouse for menus and desktop interaction.
        return # Stops after releasing the mouse.
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # Recaptures the mouse for first-person camera control.
