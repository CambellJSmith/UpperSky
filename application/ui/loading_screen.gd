extends CanvasLayer
class_name LoadingScreen

@onready var _panel: ColorRect = $Panel
@onready var _label: Label = $Panel/Label

func _ready() -> void:
    layer = 200
    _panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    _label.offset_left = -300
    _label.offset_right = 300
    _label.offset_top = -24
    _label.offset_bottom = 24
    _panel.visible = false

func begin(message: String = "Loading world…") -> void:
    _label.text = message
    _panel.visible = true
    await get_tree().process_frame

func finish() -> void:
    _panel.visible = false

func set_message(message: String) -> void:
    _label.text = message
