@tool
extends Resource
class_name HouseRecipe

## A saved recipe produces the same house in the editor and at runtime.
enum Layout { RANDOM, COTTAGE, LONGHALL, L_SHAPED, CROSS, JETTIED, TOWER }
enum WallStyle { RANDOM, STONE, BRICK, WOOD, TIMBER_FRAME }
enum RoofStyle { RANDOM, SLATE, THATCH }

@export var seed_value: int = 1:
    set(value):
        seed_value = value
        emit_changed()
@export var layout: Layout = Layout.RANDOM:
    set(value):
        layout = value
        emit_changed()
@export var wall_style: WallStyle = WallStyle.RANDOM:
    set(value):
        wall_style = value
        emit_changed()
@export var roof_style: RoofStyle = RoofStyle.RANDOM:
    set(value):
        roof_style = value
        emit_changed()
## Zero lets the seed choose the dimension or floor count.
@export_range(0.0, 14.0, .25) var width: float = 0.0:
    set(value):
        width = value
        emit_changed()
@export_range(0.0, 18.0, .25) var depth: float = 0.0:
    set(value):
        depth = value
        emit_changed()
@export_range(0, 3, 1) var floors: int = 0:
    set(value):
        floors = value
        emit_changed()
## Extend stone footings down into gently uneven terrain without burying the door.
@export_range(0.0, 4.0, .05) var foundation_extension: float = 0.0:
    set(value):
        foundation_extension = value
        emit_changed()
@export var include_chimney: bool = true:
    set(value):
        include_chimney = value
        emit_changed()
@export var include_porch: bool = true:
    set(value):
        include_porch = value
        emit_changed()

func resolve() -> Dictionary:
    var rng = RandomNumberGenerator.new()
    rng.seed = seed_value
    var shape: int = rng.randi_range(1, 6) if layout == Layout.RANDOM else layout
    var walls: int = rng.randi_range(1, 4) if wall_style == WallStyle.RANDOM else wall_style
    var roof: int = rng.randi_range(1, 2) if roof_style == RoofStyle.RANDOM else roof_style
    var w: float = rng.randf_range(5.2, 9.0)
    var d: float = rng.randf_range(6.0, 10.0)
    var levels: int = rng.randi_range(1, 2)
    match shape:
        Layout.COTTAGE:
            w = rng.randf_range(4.5, 6.8)
            d = rng.randf_range(5.0, 8.0)
            levels = 1
        Layout.LONGHALL:
            w = rng.randf_range(6.0, 8.0)
            d = rng.randf_range(11.0, 16.0)
            levels = 1
        Layout.L_SHAPED, Layout.CROSS:
            levels = 2
        Layout.JETTIED:
            levels = rng.randi_range(2, 3)
        Layout.TOWER:
            w = rng.randf_range(4.8, 6.5)
            d = w * rng.randf_range(.92, 1.08)
            levels = 3
    w = clampf(width, 4.0, 14.0) if width > 0 else w
    d = clampf(depth, 4.0, 18.0) if depth > 0 else d
    levels = clampi(floors, 1, 3) if floors > 0 else levels
    return {
        "seed": seed_value, "layout": shape, "wall": walls, "roof": roof,
        "width": w, "depth": d, "floors": levels,
        "floor_height": rng.randf_range(2.55, 2.95),
        "roof_rise": w * rng.randf_range(.38, .55),
        "hipped": shape == Layout.TOWER or (shape == Layout.COTTAGE and rng.randf() < .40),
        "foundation_extension": clampf(foundation_extension,0.0,4.0),
        "chimney": include_chimney, "porch": include_porch and rng.randf() < .7,
        "palette": rng.randi_range(0, 3),
    }
