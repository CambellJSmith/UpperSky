extends Node
class_name GenerationScheduler
# Scene-tree work cooperates under one shared budget; workers return plain arrays.
signal frame_started
const FRAME_BUDGET_US = 3000
const WORKER_LIMIT = 2
const PRIORITY_AGING_MS = 120
static var instance: GenerationScheduler
class Ticket extends RefCounted:
	signal resumed
	var sequence = 0
	var priority = 2
	var owner: Node
	var queued_at_ms = 0

var active_owner: Node
var active_priority = 2
var _ticket_sequence = 0
var _waiters: Array = []
var _deadline = 0
var _closing = false
var _workers: Array[Dictionary] = []
var worker_total_us = 0
var worker_max_us = 0
var completed_jobs = 0
var stale_jobs = 0
var longest_slice_us = 0
var _frame_begin = 0
var _operation_frame: int = -1 # Separate costly engine calls across rendered frames.
var operation_max_us: int = 0 # Expose the worst indivisible engine operation.
var operation_overruns: int = 0 # Count operations that exceed the entire cooperative budget.

func _ready():
	instance = self
	process_priority = -10000
	_deadline = Time.get_ticks_usec()+FRAME_BUDGET_US

func _process(_delta):
	# Scene teardown can invalidate WorkerThreadPool IDs before the final
	# scheduler tick. Never poll the pool after shutdown has begun.
	if _closing:
		return
	var token = RuntimeProfiler.begin("generation.main_thread_slices") if RuntimeProfiler.recording else -1
	_frame_begin = Time.get_ticks_usec()
	_deadline = _frame_begin+FRAME_BUDGET_US
	for job in _workers.duplicate():
		if int(job.id) < 0:
			_workers.erase(job)
			stale_jobs += 1
			continue
		# Joining consumes the pool ID. Retain the result, not a live task ID,
		# while its owner is paused during travel or waiting for a frame budget.
		if not job.get("joined",false):
			if not WorkerThreadPool.is_task_completed(job.id): continue
			WorkerThreadPool.wait_for_task_completion(job.id)
			job["joined"] = true
		if not is_instance_valid(job.owner):
			_workers.erase(job)
			stale_jobs += 1
			continue
		if not job.owner.can_process() or Time.get_ticks_usec() >= _deadline: continue
		_workers.erase(job)
		worker_total_us += job.box[0].duration_us
		worker_max_us = maxi(worker_max_us,job.box[0].duration_us)
		job.apply.call(job.box[0].data)
		completed_jobs += 1
	var waiters = _waiters
	_waiters = []
	var now_ms := Time.get_ticks_msec()
	# Long regional jobs must not starve terrain/decorations queued at a lower
	# priority. Waiting raises urgency; a resumed job's next ticket starts fresh.
	waiters.sort_custom(func(a,b):
		var urgency_a: int = a.priority-int((now_ms-a.queued_at_ms)/PRIORITY_AGING_MS)
		var urgency_b: int = b.priority-int((now_ms-b.queued_at_ms)/PRIORITY_AGING_MS)
		return urgency_a < urgency_b if urgency_a != urgency_b else a.sequence < b.sequence
	)
	for ticket in waiters:
		if typeof(ticket.owner) == TYPE_OBJECT and not is_instance_valid(ticket.owner):
			# Let checkpoint return false to unwind work owned by a removed node.
			ticket.resumed.emit()
			continue
		if Time.get_ticks_usec() >= _deadline or (is_instance_valid(ticket.owner) and not ticket.owner.can_process()):
			_waiters.append(ticket)
			continue
		active_priority = ticket.priority
		active_owner = ticket.owner if is_instance_valid(ticket.owner) else null
		ticket.resumed.emit()
	active_priority = 2
	active_owner = null
	frame_started.emit()
	longest_slice_us = maxi(longest_slice_us,Time.get_ticks_usec()-_frame_begin)
	if RuntimeProfiler.recording: RuntimeProfiler.end(token)

func checkpoint(owner: Node = null) -> bool:
	if owner == null: owner = active_owner
	var had_owner := is_instance_valid(owner)
	while not _closing and (Time.get_ticks_usec() >= _deadline or (owner != null and is_instance_valid(owner) and not owner.can_process())):
		var ticket = Ticket.new()
		ticket.sequence = _ticket_sequence
		ticket.queued_at_ms = Time.get_ticks_msec()
		_ticket_sequence += 1
		ticket.priority = active_priority
		ticket.owner = owner
		_waiters.append(ticket)
		await ticket.resumed
	return not _closing and (not had_owner or is_instance_valid(owner))

func operation_checkpoint(owner: Node = null) -> bool: # Admit one costly engine operation per frame across cooperative owners.
	if owner == null: owner = active_owner # Retain existing ownership conventions.
	var had_owner: bool = is_instance_valid(owner) # Detect teardown while waiting for the next frame.
	while not _closing: # Unwind staged installation when the scheduler shuts down.
		if not await checkpoint(owner): return false # Preserve pause, priority and deadline checks.
		if had_owner and not is_instance_valid(owner): return false # Reject removed scene owners.
		var frame: int = Engine.get_process_frames() # Share admission between worker applies and resumed generators.
		if _operation_frame != frame: # Prevent expensive stages from accumulating in one frame.
			_operation_frame = frame # Reserve this frame's engine operation before returning.
			return true # Allow the caller to execute one indivisible operation.
		await frame_started # Resume through the scheduler rather than spinning on the deadline.
	return false # Reject work during teardown.

func record_operation(started_us: int) -> void: # Measure indivisible work separately from coroutine slices.
	var duration: int = Time.get_ticks_usec() - started_us # Include engine work performed after admission.
	operation_max_us = maxi(operation_max_us, duration) # Preserve the largest observed operation.
	if duration > FRAME_BUDGET_US: operation_overruns += 1 # Surface the remaining soft-budget limitation.

func has_worker_room(background: bool = false) -> bool:
	if _closing or _workers.size() >= WORKER_LIMIT: return false
	if background:
		for job in _workers:
			if job.get("background",false): return false
	return true

func submit(owner: Node, generate: Callable, apply: Callable, background: bool = false) -> bool:
	if not has_worker_room(background): return false
	var box = [null]
	var id = WorkerThreadPool.add_task(func():
		var started = Time.get_ticks_usec()
		var data = generate.call()
		box[0] = {"data":data,"duration_us":Time.get_ticks_usec()-started}
	,false,"World generation")
	if id < 0: return false
	_workers.append({"id":id,"owner":owner,"generator":generate.get_object(),"apply":apply,"box":box,"background":background})
	return true

func _exit_tree():
	_closing = true
	# tree_exiting is emitted after this callback. Cancel private samplers now,
	# before joining them, rather than waiting on a signal that cannot fire yet.
	for job in _workers:
		var generator = job.get("generator")
		if is_instance_valid(generator) and generator.has_method("cancel"): generator.cancel()
	for ticket in _waiters.duplicate(): ticket.resumed.emit()
	_waiters.clear()
	frame_started.emit()
	for job in _workers:
		if not job.get("joined",false): WorkerThreadPool.wait_for_task_completion(job.id)
	_workers.clear()
	if instance == self: instance = null
