extends CanvasLayer
class_name WorldCompass

const RANGE := 1800.0
const BAR_WIDTH := 620.0
const BAR_HEIGHT := 58.0
const REFRESH_SECONDS := 0.5
@onready var _player: FirstPersonPlayer = $"../DynamicEntities/Player"
var _bar: CompassBar
var _elapsed := 0.0
var _points: Array[Dictionary] = []
var _discovered: Dictionary = {}

func _ready() -> void:
	layer = 88
	_bar = CompassBar.new()
	_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar.position = Vector2(0.0, 18.0)
	_bar.custom_minimum_size = Vector2(0.0, BAR_HEIGHT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)

func _process(delta: float) -> void:
	if not is_instance_valid(_player): return
	_elapsed += delta
	if _elapsed >= REFRESH_SECONDS:
		_elapsed = 0.0
		_refresh_points()
	_bar.heading = _player.rotation.y
	_bar.points = _points
	_bar.queue_redraw()

func _refresh_points() -> void:
	var cities: CityTravel = get_node_or_null("../CityTravel")
	if cities != null and cities.active != null:
		var local := cities.active.to_local(_player.global_position)
		var origin := Vector2(local.x,local.z)
		_points.clear()
		_points.append({"id":"city:castle","kind":"castle","icon":"♜","offset":Vector2(0,-66)-origin})
		_points.append({"id":"city:gate","kind":"gate","icon":"▣","offset":Vector2(0,112)-origin})
		_points.append({"id":"city:square","kind":"square","icon":"◇","offset":-origin})
		for child in cities.active.get_children():
			if child.has_meta("house_parameters"):
				_points.append({"id":str(child.name),"kind":"home","icon":"⌂","offset":Vector2(child.position.x,child.position.z)-origin})
		var homes := _points.slice(3)
		homes.sort_custom(func(a: Dictionary,b: Dictionary): return a.offset.length_squared()<b.offset.length_squared())
		_points.resize(3)
		for house in homes.slice(0,4): _points.append(house)
		return
	var terrain: InfiniteTerrain = get_node("../World/Terrain")
	var absolute := terrain.local_to_world_position(_player.global_position)
	var origin := Vector2(absolute.x, absolute.z)
	var next: Array[Dictionary] = []
	_collect_cells(get_node_or_null("../EnemyCamps"), "_cells", "camp", "⛺", origin, next)
	var settlements := get_node_or_null("../World/Settlements")
	_collect_cells(settlements, "_towns", "town", "⌂", origin, next)
	_collect_cells(settlements, "_homes", "home", "⌂", origin, next)
	var entrances := get_node_or_null("../DynamicEntities/DungeonEntrances")
	if is_instance_valid(entrances):
		for entrance in entrances.get_children():
			for door in entrance.get_children():
				if door is DungeonDoor:
					var world := terrain.local_to_world_position(door.global_position)
					_append_point("cave:%s" % door.get_path(), "cave", "▣", world, origin, next)
	_append_logical_points(origin, next)
	_points = next

func _append_logical_points(origin: Vector2, output: Array[Dictionary]) -> void:
	# Keep exploration guidance useful before the corresponding world chunks stream in.
	# These are deterministic candidate coordinates; streamed POIs replace them when found.
	var candidates := [
		{"id": "logical:camp:nw", "kind": "camp", "icon": "⛺", "offset": Vector2(-920, -560)},
		{"id": "logical:town:e", "kind": "town", "icon": "⌂", "offset": Vector2(1080, 180)},
		{"id": "logical:home:sw", "kind": "home", "icon": "⌂", "offset": Vector2(-760, 820)},
		{"id": "logical:cave:n", "kind": "cave", "icon": "▣", "offset": Vector2(120, -1280)},
		{"id": "logical:camp:se", "kind": "camp", "icon": "⛺", "offset": Vector2(980, 760)},
		{"id": "logical:town:w", "kind": "town", "icon": "⌂", "offset": Vector2(-1320, 80)}
	]
	for candidate in candidates:
		if output.size() >= 5: return
		if _discovered.has(candidate.id): continue
		var duplicate := false
		for existing in output:
			if existing.offset.distance_to(candidate.offset) < 140.0:
				duplicate = true
				break
		if not duplicate:
			output.append(candidate)

func _collect_cells(owner: Node, property_name: String, kind: String, icon: String, origin: Vector2, output: Array[Dictionary]) -> void:
	if not is_instance_valid(owner): return
	var cells: Dictionary = owner.get(property_name)
	if cells == null: return
	for cell in cells:
		var item = cells[cell]
		if not is_instance_valid(item): continue
		var world: Vector3 = item.get_meta("world_position", Vector3.ZERO)
		if world == Vector3.ZERO: continue
		var city: bool = kind == "town" and item.has_meta("definition") and CityGeometry.is_city(item.get_meta("definition"))
		_append_point("%s:%s" % [kind, cell], "city" if city else kind, "♜" if city else icon, world, origin, output)

func _append_point(id: String, kind: String, icon: String, world: Vector3, origin: Vector2, output: Array[Dictionary]) -> void:
	var offset := Vector2(world.x, world.z) - origin
	var distance := offset.length()
	if distance > RANGE: return
	if distance < 28.0:
		_discovered[id] = true
		return
	if _discovered.has(id): return
	output.append({"id": id, "kind": kind, "icon": icon, "offset": offset})

class CompassBar extends Control:
	var heading := 0.0
	var points: Array[Dictionary] = []
	func _draw() -> void:
		var centre := size.x * 0.5
		var rect := Rect2(centre - BAR_WIDTH * 0.5, 0.0, BAR_WIDTH, BAR_HEIGHT)
		draw_style_box(_box(Color(0.02, 0.025, 0.03, 0.82), 10), rect)
		var font := ThemeDB.fallback_font
		for i in range(-12, 13):
			var angle := float(i) * PI / 12.0
			var x := centre + angle / PI * BAR_WIDTH * 0.5
			draw_line(Vector2(x, 38), Vector2(x, 46 if i % 3 else 31), Color(0.8, 0.84, 0.78, 0.75), 1.0)
		var labels := ["N", "E", "S", "W"]
		for i in range(4):
			var relative := wrapf(float(i) * PI * 0.5 + heading, -PI, PI)
			var x := centre + relative / PI * BAR_WIDTH * 0.5
			if x > centre - BAR_WIDTH * 0.45 and x < centre + BAR_WIDTH * 0.45:
				draw_string(font, Vector2(x - 5, 22), labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.88, 0.55))
		for point in points:
			var offset: Vector2 = point.offset
			var angle := atan2(offset.x, -offset.y) + heading
			var relative := wrapf(angle, -PI, PI)
			var x := centre + relative / PI * BAR_WIDTH * 0.45
			if x < centre - BAR_WIDTH * 0.47 or x > centre + BAR_WIDTH * 0.47: continue
			draw_string(font, Vector2(x - 7, 48), point.icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.92, 0.82))

	func _box(color: Color, radius: int) -> StyleBoxFlat:
		var box := StyleBoxFlat.new()
		box.bg_color = color
		box.corner_radius_top_left = radius
		box.corner_radius_top_right = radius
		box.corner_radius_bottom_left = radius
		box.corner_radius_bottom_right = radius
		return box
