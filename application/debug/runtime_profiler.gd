extends Node
class_name RuntimeProfiler
const MAX_FRAMES: int = 60000
const MAX_SAMPLES: int = 1800
const MAX_MARKERS: int = 256
const MONITORS = {
	"fps":Performance.TIME_FPS,"engine_process_ms":Performance.TIME_PROCESS,"engine_physics_ms":Performance.TIME_PHYSICS_PROCESS,
	"static_memory_bytes":Performance.MEMORY_STATIC,"nodes":Performance.OBJECT_NODE_COUNT,"objects":Performance.OBJECT_COUNT,"resources":Performance.OBJECT_RESOURCE_COUNT,"orphan_nodes":Performance.OBJECT_ORPHAN_NODE_COUNT,
	"render_objects":Performance.RENDER_TOTAL_OBJECTS_IN_FRAME,"render_primitives":Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME,"draw_calls":Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME,
	"video_memory_bytes":Performance.RENDER_VIDEO_MEM_USED,"texture_memory_bytes":Performance.RENDER_TEXTURE_MEM_USED,"buffer_memory_bytes":Performance.RENDER_BUFFER_MEM_USED,
	"physics_active_objects":Performance.PHYSICS_3D_ACTIVE_OBJECTS,"physics_collision_pairs":Performance.PHYSICS_3D_COLLISION_PAIRS,"physics_islands":Performance.PHYSICS_3D_ISLAND_COUNT
}
static var recording: bool = false
static var instance: RuntimeProfiler
static var _stack: Array[Dictionary] = []
static var _next_scope_id: int = 0
static var _capture_first_scope_id: int = 0
static var _totals: Dictionary = {}
static var _frame_spans: Dictionary = {}
var _frames: Array[float] = []
var _samples: Array[Dictionary] = []
var _markers: Array[Dictionary] = []
var _worst: Array[Dictionary] = []
var _started: int = 0
var _last_tick: int = 0
var _stopped: int = 0
var _sample_at: float = 0
var _environment: Dictionary = {}
var _recorder_us: int = 0
var _stop_reason: String = ""
var last_export_path: String = ""
func _ready():
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000000 # Flush after gameplay process callbacks.
	set_process(false)
func _exit_tree():
	if instance == self:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),false)
		recording = false
		instance = null
		_stack.clear()
static func begin(label: String) -> int:
	# Worker jobs use the scheduler's separate elapsed-time counters. Their
	# shared sampler wrappers must never mutate the main-thread scope stack.
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not recording: return -1
	var token := _next_scope_id
	_next_scope_id += 1
	_stack.append({"token":token,"label":label,"start":Time.get_ticks_usec(),"children":0})
	return token
static func end(index: int):
	if index < 0 or OS.get_thread_caller_id() != OS.get_main_thread_id() or not recording: return
	# A stop/start inside a callback invalidates its old token. Never close
	# a new capture's scope with a recycled stack index from the old capture.
	if index < _capture_first_scope_id: return
	assert(not _stack.is_empty() and index == _stack[-1].token,"Profiler scopes must finish in stack order")
	var span = _stack.pop_back()
	var duration: int = Time.get_ticks_usec()-span.start
	var self_us: int = maxi(0,duration-span.children)
	if not _stack.is_empty(): _stack[-1].children += duration
	if not _totals.has(span.label): _totals[span.label] = {"calls":0,"inclusive_us":0,"self_us":0,"max_us":0}
	var total: Dictionary = _totals[span.label]
	total.calls += 1
	total.inclusive_us += duration
	total.self_us += self_us
	total.max_us = maxi(total.max_us,duration)
	if not _frame_spans.has(span.label): _frame_spans[span.label] = {"inclusive_ms":0.0,"self_ms":0.0,"calls":0}
	var frame: Dictionary = _frame_spans[span.label]
	frame.inclusive_ms += duration/1000.0
	frame.self_ms += self_us/1000.0
	frame.calls += 1
func start() -> String:
	if recording: return "Already recording. Use profile stop or profile export first."
	_frames.clear()
	_samples.clear()
	_markers.clear()
	_worst.clear()
	_totals.clear()
	_frame_spans.clear()
	_stack.clear()
	_capture_first_scope_id = _next_scope_id
	_recorder_us = 0
	_stop_reason = ""
	last_export_path = ""
	_started = Time.get_ticks_usec()
	_last_tick = _started
	_stopped = 0
	_sample_at = 0
	_environment = {
		"engine":Engine.get_version_info(),"os":OS.get_name(),"cpu":OS.get_processor_name(),"cpu_threads":OS.get_processor_count(),
		"gpu":RenderingServer.get_video_adapter_name(),"gpu_vendor":RenderingServer.get_video_adapter_vendor(),"renderer":RenderingServer.get_current_rendering_method(),"display_driver":DisplayServer.get_name(),
		"viewport_size":[get_viewport().get_visible_rect().size.x,get_viewport().get_visible_rect().size.y],"render_target_size":[get_viewport().get_texture().get_size().x,get_viewport().get_texture().get_size().y],"world_seed":TerrainHeightSampler.WORLD_SEED,"max_fps":Engine.max_fps,"physics_ticks_per_second":Engine.physics_ticks_per_second,"vsync_mode":DisplayServer.window_get_vsync_mode(),"time_scale":Engine.time_scale
	}
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	recording = true
	set_process(true)
	return "Profiler recording. Close the console and play; then use profile export."
func stop(reason: String = "user") -> String:
	if not recording: return "Profiler is stopped. %d frames retained."%_frames.size()
	recording = false
	_stopped = Time.get_ticks_usec()
	_stop_reason = reason
	set_process(false)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),false)
	_stack.clear()
	return "Profiler stopped: %d frames over %.1f seconds. Use profile export to save."%[_frames.size(),(_stopped-_started)/1000000.0]
func status() -> String:
	var elapsed = (Time.get_ticks_usec()-_started)/1000000.0 if recording else (_stopped-_started)/1000000.0
	return "%s · %d frames · %.1f seconds · %d markers%s"%["Recording" if recording else "Stopped",_frames.size(),maxf(0,elapsed),_markers.size()," · "+_stop_reason if not _stop_reason.is_empty() else ""]
func mark(label: String) -> String:
	if not recording: return "Start recording with profile start before adding markers."
	if label.strip_edges().is_empty(): return "Usage: profile mark <what you are doing>"
	if _markers.size() >= MAX_MARKERS: return "Marker limit reached."
	_markers.append({"elapsed_s":(Time.get_ticks_usec()-_started)/1000000.0,"frame":_frames.size(),"label":label.left(240),"context":_context()})
	return "Marked: "+label.left(240)
func _process(_delta):
	if not recording: return
	var begin_us = Time.get_ticks_usec()
	var ms = (begin_us-_last_tick)/1000.0
	_last_tick = begin_us
	var elapsed = (begin_us-_started)/1000000.0
	_frames.append(ms)
	if elapsed >= _sample_at:
		var sample: Dictionary = {"elapsed_s":elapsed,"frame":_frames.size()-1,"context":_context(),"system_totals_us":_totals.duplicate(true)}
		for label in MONITORS:
			var value = Performance.get_monitor(MONITORS[label])
			sample[label] = value*1000 if label in ["engine_process_ms","engine_physics_ms"] else value
		var viewport = get_viewport().get_viewport_rid()
		var cpu = RenderingServer.viewport_get_measured_render_time_cpu(viewport)
		var gpu = RenderingServer.viewport_get_measured_render_time_gpu(viewport)
		sample["render_cpu_ms"] = cpu if cpu > 0 else null
		sample["render_gpu_ms"] = gpu if gpu > 0 else null
		_samples.append(sample)
		_sample_at = elapsed+.5
	if _worst.size() < 40 or ms > _worst[-1].wall_ms:
		_worst.append({"frame":_frames.size()-1,"elapsed_s":elapsed,"wall_ms":ms,"systems":_frame_spans.duplicate(true),"context":_context()})
		_worst.sort_custom(func(a,b): return a.wall_ms > b.wall_ms)
		if _worst.size() > 40: _worst.pop_back()
	_frame_spans.clear()
	_recorder_us += Time.get_ticks_usec()-begin_us
	if _frames.size() >= MAX_FRAMES or _samples.size() >= MAX_SAMPLES:
		stop("capture limit reached; export retained data")
func _context() -> Dictionary:
	var game = get_parent()
	var player = game.get_node_or_null("DynamicEntities/Player") as FirstPersonPlayer
	var terrain = game.get_node_or_null("World/Terrain") as InfiniteTerrain
	var world = game.get_node_or_null("World") as Node3D
	var context: Dictionary = {"overworld":world != null and world.visible,"console_open":Input.mouse_mode != Input.MOUSE_MODE_CAPTURED}
	if player != null:
		var pos = terrain.local_to_world_position(player.global_position) if terrain != null and context.overworld else player.global_position
		context["player_position"] = [pos.x,pos.y,pos.z]
		context["fly_mode"] = player.is_fly_mode_enabled()
	var streams = {
		"terrain":["World/Terrain","_chunks","_pending_chunks","_pending_chunk_index"],"paths":["World/Paths","_chunks","_pending",""],
		"settlements":["World/Settlements","_towns","_pending",""],"homes":["World/Settlements","_homes","",""],"decorations":["WorldDecorations","_chunks","_pending_chunks","_pending_chunk_index"],
		"flora":["GroundFlora","_chunks","_pending_chunks","_pending_index"],"grass":["DenseGroundCover","_tiles","",""],
		"camps":["EnemyCamps","_cells","_pending",""],"biome_features":["World/BiomeFeatures","_chunks","_pending",""],"wayshrines":["World/Wayshrines","_cells","_pending",""]
	}
	var counts: Dictionary = {}
	for label in streams:
		var spec = streams[label]
		var node = game.get_node_or_null(spec[0])
		if node == null: continue
		var loaded = node.get(spec[1])
		var live = 0
		if loaded is Dictionary:
			for value in loaded.values():
				if value != null: live += 1
		elif loaded != null: live = loaded.size()
		var entry: Dictionary = {"loaded":live,"entries":loaded.size() if loaded != null else null,"enabled":node.can_process() and node.is_processing()}
		if not spec[2].is_empty():
			var pending = node.get(spec[2])
			var index = node.get(spec[3]) if not spec[3].is_empty() else 0
			entry["pending"] = maxi(0,pending.size()-int(index)) if pending != null else null
		counts[label] = entry
	var npcs = get_tree().get_nodes_in_group("npc")
	var active = 0
	var fighting = 0
	for npc in npcs:
		if npc.can_process() and npc.is_physics_processing():
			active += 1
			if npc.has_method("is_in_combat") and npc.is_in_combat(): fighting += 1
	context["npcs"] = {"loaded":npcs.size(),"active":active,"in_combat":fighting}
	var scheduler = GenerationScheduler.instance
	if scheduler != null:
		context["generation"] = {"workers":scheduler._workers.size(),"waiting_slices":scheduler._waiters.size(),"completed_jobs":scheduler.completed_jobs,"worker_task_total_ms":scheduler.worker_total_us/1000.0,"worker_task_max_ms":scheduler.worker_max_us/1000.0,"stale_jobs":scheduler.stale_jobs,"budget_ms":GenerationScheduler.FRAME_BUDGET_US/1000.0,"longest_slice_ms":scheduler.longest_slice_us/1000.0}
	context["streams"] = counts
	return context
func report() -> Dictionary:
	var sorted = _frames.duplicate()
	sorted.sort()
	var total: float = 0
	var spikes: Dictionary = {"over_16_67_ms":0,"over_33_33_ms":0,"over_50_ms":0,"over_100_ms":0}
	for ms in _frames:
		total += ms
		if ms > 16.67: spikes.over_16_67_ms += 1
		if ms > 33.33: spikes.over_33_33_ms += 1
		if ms > 50: spikes.over_50_ms += 1
		if ms > 100: spikes.over_100_ms += 1
	var systems: Array[Dictionary] = []
	for label in _totals:
		var entry: Dictionary = _totals[label]
		systems.append({"name":label,"calls":entry.calls,"inclusive_ms":entry.inclusive_us/1000.0,"self_ms":entry.self_us/1000.0,"maximum_call_ms":entry.max_us/1000.0,"average_call_ms":entry.inclusive_us/1000.0/entry.calls})
	systems.sort_custom(func(a,b): return a.self_ms > b.self_ms)
	return {"format":"UpperSky performance capture","schema_version":1,"created_utc":Time.get_datetime_string_from_system(true),"environment":_environment,
		"summary":{"frames":_frames.size(),"wall_duration_s":((_stopped if _stopped > 0 else Time.get_ticks_usec())-_started)/1000000.0,"average_frame_ms":total/maxi(1,_frames.size()),"average_fps":1000*_frames.size()/total if total > 0 else 0,"p50_ms":percentile(sorted,.50),"p95_ms":percentile(sorted,.95),"p99_ms":percentile(sorted,.99),"worst_frame_ms":sorted[-1] if not sorted.is_empty() else 0,"spikes":spikes,"recorder_callback_ms":_recorder_us/1000.0,"stop_reason":_stop_reason},
		"systems":systems,"slowest_frames":_worst,"samples":_samples,"markers":_markers,"frame_times_ms":_frames,
		"notes":["World generation uses background terrain workers plus cooperative main-thread slices. Worker task durations in generation context overlap frames and other workers; do not add them to CPU frame timings.","Wall frame times include rendering, waits, vsync and profiler overhead; CPU scope measurements are not GPU times.","System scopes measure main-thread callbacks only. Inclusive times overlap when nested. Self times exclude instrumented children; uninstrumented work remains in its parent. Worker durations are reported separately in generation context.","Frame scopes cover callbacks between recorder flushes. GPU/render timings are asynchronous backend measurements and null when unavailable.","Engine counters/context sampled every 0.5 seconds. Position is absolute overworld or local dungeon space. console_open also means another cursor menu may be open.","Only explicitly instrumented systems are timed. This is not a complete per-function or allocation profiler."]}
static func percentile(values: Array, fraction: float) -> float:
	return 0 if values.is_empty() else values[mini(values.size()-1,int(ceil(fraction*values.size()))-1)]
func export_report() -> String:
	if _started == 0: return "No recording yet. Use profile start first."
	if recording: stop()
	var folder = "user://performance_reports"
	var error = DirAccess.make_dir_recursive_absolute(folder)
	if error != OK: return "Could not create report folder: "+error_string(error)
	var timestamp = Time.get_datetime_string_from_system(true).replace(":","-")
	var path = folder+"/upper-sky-profile-"+timestamp+"-"+str(Time.get_ticks_msec())+".json"
	var file = FileAccess.open(path,FileAccess.WRITE)
	if file == null: return "Could not write report: "+error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(report(),"\t"))
	file.flush()
	if file.get_error() != OK: return "Report write failed: "+error_string(file.get_error())
	file.close()
	last_export_path = ProjectSettings.globalize_path(path)
	return "Profiler report saved: "+last_export_path+"\nSend that JSON file for analysis. Use profile folder to open its folder."
