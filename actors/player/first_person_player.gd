extends CharacterBody3D
class_name FirstPersonPlayer

const WALK_SPEED: float = 7.5
const SPRINT_SPEED: float = 12.0
const GROUND_ACCELERATION: float = 38.0
const AIR_ACCELERATION: float = 11.0
const JUMP_VELOCITY: float = 7.0
const JUMP_STAMINA_COST: float = 12.0
const CLIMB_SPEED: float = 4.2
const CLIMB_LATERAL_SPEED: float = 3.8
const CLIMB_CONTACT_SPEED: float = 1.6
const CLIMB_STAMINA_DRAIN_PER_SECOND: float = 24.0
const CLIMB_ATTACH_INPUT_DOT: float = 0.12
const SWIM_SPEED: float = 6.5
const SWIM_SPRINT_SPEED: float = 10.5
const SWIM_VERTICAL_SPEED: float = 6.0
const SWIM_ACCELERATION: float = 16.0
const SWIM_BODY_SAMPLE_HEIGHT: float = 0.9
const SWIM_SURFACE_ROOT_DEPTH: float = 1.48
const SWIM_BUOYANCY_RESPONSE: float = 0.65
const SPRINT_STAMINA_DRAIN_PER_SECOND: float = 18.0
const SWIM_STAMINA_DRAIN_PER_SECOND: float = 10.0
const FAST_SWIM_STAMINA_DRAIN_PER_SECOND: float = 18.0
const STAMINA_REGENERATION_PER_SECOND: float = 16.0
const STAMINA_REGENERATION_DELAY: float = 1.25
const FLY_SPEED: float = 35.0
const FLY_SPRINT_SPEED: float = 120.0
const FLY_ACCELERATION: float = 70.0
const MOUSE_LOOK_SENSITIVITY: float = 0.0025
const CONTROLLER_LOOK_SPEED: float = 2.6
const MINIMUM_PITCH: float = deg_to_rad(-89.0)
const MAXIMUM_PITCH: float = deg_to_rad(89.0)

@onready var _vitals: PlayerVitals = $PlayerVitals
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D

var _terrain: InfiniteTerrain
var _gravity: float = 0.0
var _pitch: float = 0.0
var _gameplay_input_enabled: bool = true
var _fly_mode_enabled: bool = false
var _swimming_enabled: bool = false
var _climbing_enabled: bool = false
var _current_water_level: float = 0.0
var _stamina_exertion_this_frame: bool = false
var _stamina_regeneration_delay_remaining: float = 0.0
var _initial_collision_layer: int = 0
var _initial_collision_mask: int = 0
var _initial_motion_mode: int = CharacterBody3D.MOTION_MODE_GROUNDED

func _ready() -> void:
    _gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
    _initial_collision_layer = collision_layer
    _initial_collision_mask = collision_mask
    _initial_motion_mode = motion_mode
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func initialize_environment(terrain: InfiniteTerrain) -> void:
    _terrain = terrain

func get_collision_shape() -> Shape3D:
    return _collision_shape.shape

func get_collision_local_transform() -> Transform3D:
    return _collision_shape.transform

func get_view_camera() -> Camera3D:
    return _camera

func is_fly_mode_enabled() -> bool:
    return _fly_mode_enabled

func is_swimming() -> bool:
    return _swimming_enabled

func is_climbing() -> bool:
    return _climbing_enabled

func set_gameplay_input_enabled(enabled: bool) -> void:
    _gameplay_input_enabled = enabled
    if not _gameplay_input_enabled:
        _climbing_enabled = false
        velocity.x = 0.0
        velocity.z = 0.0
        if _fly_mode_enabled or _swimming_enabled:
            velocity.y = 0.0
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        return
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func set_fly_mode_enabled(enabled: bool) -> void:
    if enabled == _fly_mode_enabled:
        return
    _fly_mode_enabled = enabled
    _climbing_enabled = false
    velocity = Vector3.ZERO
    if _fly_mode_enabled:
        _set_swimming_enabled(false)
        collision_layer = 0
        collision_mask = 0
        motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
        return
    collision_layer = _initial_collision_layer
    collision_mask = _initial_collision_mask
    motion_mode = _initial_motion_mode

func _unhandled_input(event: InputEvent) -> void:
    if not _gameplay_input_enabled:
        return
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
        _rotate_view(mouse_motion.relative * MOUSE_LOOK_SENSITIVITY)
        get_viewport().set_input_as_handled()
        return
    if event.is_action_pressed("Button_Start"):
        _toggle_mouse_capture()
        get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
    _stamina_exertion_this_frame = false
    if _gameplay_input_enabled:
        _apply_controller_look(delta)
    _update_water_state()
    _update_climbing_state()

    if _fly_mode_enabled:
        _apply_fly_movement(delta)
    elif _swimming_enabled:
        _apply_swim_movement(delta)
    elif _climbing_enabled:
        if not _apply_climb_movement(delta):
            _climbing_enabled = false
            _apply_vertical_movement(delta)
            _apply_horizontal_movement(delta)
    else:
        _apply_vertical_movement(delta)
        _apply_horizontal_movement(delta)

    move_and_slide()
    _update_stamina_regeneration(delta)

func _update_water_state() -> void:
    if _terrain == null or _fly_mode_enabled:
        _set_swimming_enabled(false)
        return
    var player_world_position: Vector3 = _terrain.local_to_world_position(global_position)
    var horizontal_position: Vector2 = Vector2(player_world_position.x, player_world_position.z)
    var water_exists: bool = _terrain.has_water_at(horizontal_position)
    _current_water_level = _terrain.get_water_level_at(horizontal_position)
    var body_sample_height: float = player_world_position.y + SWIM_BODY_SAMPLE_HEIGHT
    _set_swimming_enabled(water_exists and body_sample_height < _current_water_level)

func _set_swimming_enabled(enabled: bool) -> void:
    if enabled == _swimming_enabled:
        return
    _swimming_enabled = enabled
    if _swimming_enabled:
        _climbing_enabled = false
    if _fly_mode_enabled:
        return
    motion_mode = CharacterBody3D.MOTION_MODE_FLOATING if _swimming_enabled else _initial_motion_mode
    if _swimming_enabled:
        velocity.y *= 0.35

func _update_climbing_state() -> void:
    if not _gameplay_input_enabled or _fly_mode_enabled or _swimming_enabled:
        _climbing_enabled = false
        return
    if not Input.is_action_pressed("Button_A") or not is_on_wall():
        _climbing_enabled = false
        return
    var wall_normal: Vector3 = get_wall_normal().normalized()
    if wall_normal.is_zero_approx():
        _climbing_enabled = false
        return
    if _climbing_enabled:
        return
    var movement_input: Vector2 = Input.get_vector("StickLeft_West", "StickLeft_East", "StickLeft_North", "StickLeft_South")
    if movement_input.is_zero_approx():
        return
    var local_direction: Vector3 = Vector3(movement_input.x, 0.0, movement_input.y)
    var world_direction: Vector3 = global_transform.basis * local_direction
    world_direction.y = 0.0
    if world_direction.is_zero_approx():
        return
    world_direction = world_direction.normalized()
    _climbing_enabled = world_direction.dot(-wall_normal) >= CLIMB_ATTACH_INPUT_DOT

func _apply_climb_movement(delta: float) -> bool:
    if not is_on_wall() or not Input.is_action_pressed("Button_A"):
        return false
    if not _consume_stamina(CLIMB_STAMINA_DRAIN_PER_SECOND, delta):
        return false

    var wall_normal: Vector3 = get_wall_normal().normalized()
    if wall_normal.is_zero_approx():
        return false
    var wall_up: Vector3 = Vector3.UP.slide(wall_normal)
    if wall_up.is_zero_approx():
        wall_up = Vector3.UP
    else:
        wall_up = wall_up.normalized()
    var wall_right: Vector3 = wall_up.cross(wall_normal).normalized()

    var movement_input: Vector2 = Input.get_vector("StickLeft_West", "StickLeft_East", "StickLeft_North", "StickLeft_South")
    var climb_velocity: Vector3 = wall_up * (-movement_input.y) * CLIMB_SPEED
    climb_velocity += wall_right * movement_input.x * CLIMB_LATERAL_SPEED
    climb_velocity += -wall_normal * CLIMB_CONTACT_SPEED
    velocity = climb_velocity
    return true

func _apply_controller_look(delta: float) -> void:
    var look_input: Vector2 = Input.get_vector("StickRight_West", "StickRight_East", "StickRight_North", "StickRight_South")
    if look_input.is_zero_approx():
        return
    _rotate_view(look_input * CONTROLLER_LOOK_SPEED * delta)

func _apply_vertical_movement(delta: float) -> void:
    if is_on_floor():
        if velocity.y < 0.0:
            velocity.y = 0.0
        if _gameplay_input_enabled and Input.is_action_just_pressed("Button_A") and _consume_stamina_amount(JUMP_STAMINA_COST):
            velocity.y = JUMP_VELOCITY
        return
    velocity.y -= _gravity * delta

func _apply_horizontal_movement(delta: float) -> void:
    var movement_input: Vector2 = Vector2.ZERO
    if _gameplay_input_enabled:
        movement_input = Input.get_vector("StickLeft_West", "StickLeft_East", "StickLeft_North", "StickLeft_South")
    var local_direction: Vector3 = Vector3(movement_input.x, 0.0, movement_input.y)
    var world_direction: Vector3 = global_transform.basis * local_direction
    world_direction.y = 0.0
    world_direction = world_direction.normalized()
    var movement_speed: float = WALK_SPEED
    var sprint_requested: bool = _gameplay_input_enabled and not movement_input.is_zero_approx() and Input.is_action_pressed("StickLeft_Click")
    if sprint_requested and _consume_stamina(SPRINT_STAMINA_DRAIN_PER_SECOND, delta):
        movement_speed = SPRINT_SPEED
    var target_velocity: Vector3 = world_direction * movement_speed
    var acceleration: float = GROUND_ACCELERATION if is_on_floor() else AIR_ACCELERATION
    velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
    velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

func _apply_swim_movement(delta: float) -> void:
    var movement_input: Vector2 = Vector2.ZERO
    var vertical_input: float = 0.0
    if _gameplay_input_enabled:
        movement_input = Input.get_vector("StickLeft_West", "StickLeft_East", "StickLeft_North", "StickLeft_South")
        if Input.is_action_pressed("Button_A"):
            vertical_input += 1.0
        if Input.is_action_pressed("Button_B"):
            vertical_input -= 1.0
    var player_directed_swimming: bool = not movement_input.is_zero_approx() or not is_zero_approx(vertical_input)
    var local_direction: Vector3 = Vector3(movement_input.x, 0.0, movement_input.y)
    var world_direction: Vector3 = global_transform.basis * local_direction
    world_direction.y = 0.0
    world_direction = world_direction.normalized()
    var movement_speed: float = SWIM_SPEED
    var fast_swim_requested: bool = player_directed_swimming and not movement_input.is_zero_approx() and Input.is_action_pressed("StickLeft_Click")
    var fast_swimming: bool = false
    if fast_swim_requested:
        fast_swimming = _consume_stamina(FAST_SWIM_STAMINA_DRAIN_PER_SECOND, delta)
    if fast_swimming:
        movement_speed = SWIM_SPRINT_SPEED
    elif player_directed_swimming:
        _consume_stamina(SWIM_STAMINA_DRAIN_PER_SECOND, delta)
    var target_velocity: Vector3 = world_direction * movement_speed
    if is_zero_approx(vertical_input):
        var player_world_position: Vector3 = _terrain.local_to_world_position(global_position)
        var preferred_root_height: float = _current_water_level - SWIM_SURFACE_ROOT_DEPTH
        vertical_input = clampf((preferred_root_height - player_world_position.y) * SWIM_BUOYANCY_RESPONSE, -1.0, 1.0)
    target_velocity.y = vertical_input * SWIM_VERTICAL_SPEED
    velocity = velocity.move_toward(target_velocity, SWIM_ACCELERATION * delta)

func _consume_stamina(drain_per_second: float, delta: float) -> bool:
    if drain_per_second <= 0.0 or delta <= 0.0:
        return false
    _stamina_exertion_this_frame = true
    _stamina_regeneration_delay_remaining = STAMINA_REGENERATION_DELAY
    if _vitals == null or not _vitals.has_stamina():
        return false
    return _vitals.consume_stamina(drain_per_second * delta) > 0.0

func _consume_stamina_amount(amount: float) -> bool:
    if amount <= 0.0 or _vitals == null:
        return false
    if _vitals.get_stamina() + 0.0001 < amount:
        return false
    _stamina_exertion_this_frame = true
    _stamina_regeneration_delay_remaining = STAMINA_REGENERATION_DELAY
    return _vitals.consume_stamina(amount) >= amount - 0.0001

func _update_stamina_regeneration(delta: float) -> void:
    if _vitals == null or delta <= 0.0:
        return
    if _stamina_exertion_this_frame:
        return
    if _stamina_regeneration_delay_remaining > 0.0:
        _stamina_regeneration_delay_remaining = maxf(_stamina_regeneration_delay_remaining - delta, 0.0)
        return
    _vitals.restore_stamina(STAMINA_REGENERATION_PER_SECOND * delta)

func _apply_fly_movement(delta: float) -> void:
    var movement_input: Vector2 = Vector2.ZERO
    var vertical_input: float = 0.0
    if _gameplay_input_enabled:
        movement_input = Input.get_vector("StickLeft_West", "StickLeft_East", "StickLeft_North", "StickLeft_South")
        if Input.is_action_pressed("Button_A"):
            vertical_input += 1.0
        if Input.is_action_pressed("Button_B"):
            vertical_input -= 1.0
    var local_direction: Vector3 = Vector3(movement_input.x, 0.0, movement_input.y)
    var world_direction: Vector3 = global_transform.basis * local_direction
    world_direction.y = vertical_input
    world_direction = world_direction.normalized()
    var movement_speed: float = FLY_SPEED
    if _gameplay_input_enabled and Input.is_action_pressed("StickLeft_Click"):
        movement_speed = FLY_SPRINT_SPEED
    var target_velocity: Vector3 = world_direction * movement_speed
    velocity = velocity.move_toward(target_velocity, FLY_ACCELERATION * delta)

func _rotate_view(rotation_input: Vector2) -> void:
    rotate_y(-rotation_input.x)
    _pitch = clampf(_pitch - rotation_input.y, MINIMUM_PITCH, MAXIMUM_PITCH)
    _head.rotation.x = _pitch

func _toggle_mouse_capture() -> void:
    if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        return
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
