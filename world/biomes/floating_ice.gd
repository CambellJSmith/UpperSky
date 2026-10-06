extends AnimatableBody3D
class_name FloatingIce

var _surface_height: float = 0.0
var _phase: float = 0.0
var _elapsed: float = 0.0

func initialize(surface_height: float, phase: float) -> void:
    _surface_height = surface_height
    _phase = phase
    position.y = surface_height

func _physics_process(delta: float) -> void:
    _elapsed += delta
    position.y = _surface_height + sin(_elapsed * 0.6 + _phase) * 0.12
