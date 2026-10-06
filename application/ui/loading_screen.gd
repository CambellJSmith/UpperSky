extends CanvasLayer
class_name LoadingScreen

@onready var _panel: ColorRect = $Panel
@onready var _label: Label = $Panel/Label

func _ready() -> void:
    layer = 200
    _panel.visible = false

func begin(message: String = "Loading world…") -> void:
    _label.text = message
    _panel.visible = true
    await get_tree().process_frame

func finish() -> void:
    _panel.visible = false
