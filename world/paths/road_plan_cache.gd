extends RefCounted
class_name RoadPlanCache

const VERSION := 4
const LIMIT := 512
var directory: String
var writes := 0

func _init(seamless: bool):
    directory = "user://world_roads/v%d_%d_%s/"%[VERSION,TerrainHeightSampler.WORLD_SEED,"seamless" if seamless else "tiered"]

func read(link: Dictionary):
    var path: String = directory+String(link.key).sha256_text()+".road"
    if not FileAccess.file_exists(path): return null
    var file := FileAccess.open(path,FileAccess.READ)
    if file == null: return null
    var packet = file.get_var(false)
    if not packet is Dictionary or packet.get("start") != link.start or packet.get("end") != link.end or not packet.get("road") is Dictionary: return null
    var road: Dictionary = packet.road
    if road.is_empty(): return road
    if road.get("key") != link.key or not road.get("points") is Array or road.points.size()<2 or not road.get("bridges") is Array: return null
    if road.get("kind") not in ["arterial","connection"] or not road.get("from") is Vector2 or not road.get("to") is Vector2: return null
    if not road.get("bounds") is Rect2 or not road.get("core") is float or not road.get("edge") is float: return null
    if road.core <= 0 or road.core > 8 or road.edge <= road.core or road.edge > 10: return null
    for point in road.points:
        if not point is Vector2 or not point.is_finite(): return null
    if road.points[0] != link.start or road.points[-1] != link.end: return null
    for bridge in road.bridges:
        if not bridge is Dictionary or not bridge.get("a") is Vector2 or not bridge.get("b") is Vector2 or not bridge.get("height") is float or not bridge.get("width") is float or not bridge.get("key") is String: return null
        if not bridge.a.is_finite() or not bridge.b.is_finite() or bridge.a.distance_to(bridge.b)<.1 or not is_finite(bridge.height) or bridge.width <= 0 or bridge.width>16: return null
        for field in ["height_a","height_b"]:
            if not bridge.get(field) is float or not is_finite(bridge[field]): return null
    return road

func write(link: Dictionary, road: Dictionary):
    if DirAccess.make_dir_recursive_absolute(directory) != OK: return
    var path: String = directory+String(link.key).sha256_text()+".road"
    var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
    if file == null: return
    file.store_var({"start":link.start,"end":link.end,"road":road},false)
    file.close()
    DirAccess.rename_absolute(path+".tmp",path)
    writes += 1
    if writes%32 != 0: return
    var folder := DirAccess.open(directory)
    if folder == null: return
    var files: Array[String] = []
    for name in folder.get_files():
        if name.ends_with(".road"): files.append(name)
    if files.size() <= LIMIT: return
    var times := {}
    for name in files: times[name] = FileAccess.get_modified_time(directory+name)
    files.sort_custom(func(a,b): return times[a] < times[b])
    for i in range(files.size()-LIMIT): DirAccess.remove_absolute(directory+files[i])
