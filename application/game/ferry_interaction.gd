extends CanvasLayer
class_name FerryInteraction
var player: FirstPersonPlayer
var prompt: Label

func initialize(character: FirstPersonPlayer): player = character
func _ready():
    layer = 12
    prompt = Label.new()
    prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    prompt.add_theme_font_size_override("font_size",20)
    prompt.add_theme_color_override("font_shadow_color",Color.BLACK)
    prompt.add_theme_constant_override("shadow_offset_x",2)
    prompt.add_theme_constant_override("shadow_offset_y",2)
    prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(prompt)
    prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
    prompt.offset_left = -280
    prompt.offset_right = 280
    prompt.offset_top = -135
    prompt.offset_bottom = -105
    prompt.hide()

func _process(_delta: float):
    prompt.hide()
    if player==null or not player.is_physics_processing() or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED: return
    if player.water_transport!=null:
        prompt.text = "Crossing to the opposite dock…"
        prompt.show()
        return
    var target := _target()
    if target.is_empty(): return
    prompt.text = "[E / X] Board boat"
    prompt.show()

func _unhandled_input(event: InputEvent):
    if player==null or player.water_transport!=null or not player.is_physics_processing() or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED: return
    if event is InputEventKey and event.echo: return
    if not event.is_action_pressed("Interact"): return
    var target := _target()
    if target.is_empty(): return
    if target.ferry.request(player,target.side): get_viewport().set_input_as_handled()

func _target() -> Dictionary:
    var camera := player.get_view_camera()
    var start := camera.global_position
    var query := PhysicsRayQueryParameters3D.create(start,start-camera.global_basis.z*5,1 | (1<<17))
    query.collide_with_areas = true
    query.hit_from_inside = true
    query.exclude = [player.get_rid()]
    var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty() or not hit.collider.has_meta("ferry"): return {}
    return {"ferry":hit.collider.get_meta("ferry"),"side":hit.collider.get_meta("side")}
