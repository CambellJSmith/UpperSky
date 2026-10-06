extends CanvasLayer
class_name BedrollInteraction

const INTERACTION_DISTANCE: float = 3.0
const REST_COOLDOWN_SECONDS: float = 0.75

@onready var _player: FirstPersonPlayer = $"../DynamicEntities/Player"
var _camera: Camera3D
var _cycle: DayNightCycle
var _prompt: Label
var _cooldown: float = 0.0
var _message_remaining: float = 0.0

func _ready() -> void:
    layer = 12
    _camera = _player.get_view_camera()
    _cycle = get_tree().get_first_node_in_group(DayNightCycle.GROUP_NAME) as DayNightCycle
    _prompt = Label.new()
    _prompt.name = "RestPrompt"
    _prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _prompt.add_theme_font_size_override("font_size", 20)
    _prompt.add_theme_color_override("font_shadow_color", Color.BLACK)
    _prompt.add_theme_constant_override("shadow_offset_x", 2)
    _prompt.add_theme_constant_override("shadow_offset_y", 2)
    add_child(_prompt)
    _prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
    _prompt.offset_left = -260.0
    _prompt.offset_right = 260.0
    _prompt.offset_top = -105.0
    _prompt.offset_bottom = -65.0
    _prompt.hide()

func _process(delta: float) -> void:
    _cooldown = maxf(0.0, _cooldown - delta)
    _message_remaining = maxf(0.0, _message_remaining - delta)
    if not _gameplay_active():
        _prompt.hide()
        return
    if _message_remaining > 0.0:
        _prompt.show()
        return
    var bedroll: CampBedroll = _target_bedroll()
    _prompt.visible = bedroll != null and _cycle != null
    if _prompt.visible:
        _prompt.text = "[E / X] Rest for 8 hours"

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and (event as InputEventKey).echo:
        return
    if not event.is_action_pressed("Interact") or not _gameplay_active():
        return
    var bedroll: CampBedroll = _target_bedroll()
    if bedroll == null:
        return
    # Consume repeated presses on a bedroll so they cannot trigger another interaction.
    get_viewport().set_input_as_handled()
    if _cooldown > 0.0 or not bedroll.rest(_cycle):
        return
    _cooldown = REST_COOLDOWN_SECONDS
    _message_remaining = 2.0
    _prompt.text = "Rested 8 hours · %s" % _cycle.get_formatted_time()
    _prompt.show()

func _gameplay_active() -> bool:
    return _camera != null and _player.is_physics_processing() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func _target_bedroll() -> CampBedroll:
    if _camera == null:
        return null
    var start: Vector3 = _camera.global_position
    var end: Vector3 = start - _camera.global_transform.basis.z * INTERACTION_DISTANCE
    # Solid terrain/tent walls and doors occlude bedrolls instead of allowing use through them.
    var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, end)
    query.collision_mask = 1 | CampBedroll.INTERACTION_COLLISION_LAYER | DungeonDoor.INTERACTION_COLLISION_LAYER | Wayshrine.INTERACTION_COLLISION_LAYER
    query.collide_with_areas = true
    query.collide_with_bodies = true
    query.exclude = [_player.get_rid()]
    var hit: Dictionary = _camera.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty() or not hit["collider"] is CampBedroll:
        return null
    var bedroll: CampBedroll = hit["collider"] as CampBedroll
    if not bedroll.is_visible_in_tree() or not bedroll.can_process():
        return null
    return bedroll
