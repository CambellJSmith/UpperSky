extends RefCounted
class_name WayshrineRegistry
# Discovery survives streaming and is serialized by SaveSystem.
static var activated: Dictionary = {}
static func activate(definition: Dictionary) -> bool:
    if definition.is_empty() or activated.has(definition.id): return false
    activated[definition.id] = definition.duplicate(true)
    return true
static func is_activated(id: Vector2i) -> bool: return activated.has(id)
static func destinations(source: Vector2i) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    if not is_activated(source): return result
    for id in activated:
        if id != source: result.append(activated[id])
    result.sort_custom(func(a,b): return a.title < b.title)
    return result
