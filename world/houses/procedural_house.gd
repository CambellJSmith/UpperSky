@tool
extends Node3D
class_name ProceduralHouse

## Drop this node/scene into a level and assign a recipe; all geometry is native 3D.
@export var recipe: HouseRecipe:
    set(value):
        if recipe != null and recipe.changed.is_connected(_queue_rebuild):
            recipe.changed.disconnect(_queue_rebuild)
        recipe = value
        if recipe != null:
            recipe.changed.connect(_queue_rebuild)
        _queue_rebuild()
@export var generate_collision: bool = true:
    set(value):
        generate_collision = value
        _queue_rebuild()
@export var regenerate: bool = false:
    set(value):
        if value:
            _queue_rebuild()
var _queued: bool = false
var generated: Node3D

func _ready() -> void:
    rebuild()

func _queue_rebuild() -> void:
    if not is_inside_tree() or _queued:
        return
    _queued = true
    rebuild.call_deferred()

func rebuild() -> void:
    _queued = false
    if not is_inside_tree():
        return
    if is_instance_valid(generated):
        remove_child(generated)
        generated.queue_free()
    var active_recipe = recipe if recipe != null else HouseRecipe.new()
    generated = HouseGeometry.new().build(active_recipe, generate_collision)
    add_child(generated)
    set_meta("house_parameters", generated.get_meta("house_parameters"))
    # Generated children are not serialized; the small recipe is the source of truth.
