extends Node
class_name GenerationScheduler
# Scene-tree work cooperates under one shared budget; workers return plain arrays.
signal frame_started
const FRAME_BUDGET_US = 3000
const WORKER_LIMIT = 2
static var instance: GenerationScheduler
class Ticket extends RefCounted:
	signal resumed
	var sequence = 0
	var priority = 2
	var owner: Node

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
		if not WorkerThreadPool.is_task_completed(job.id): continue
		WorkerThreadPool.wait_for_task_completion(job.id)
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
	waiters.sort_custom(func(a,b): return a.priority < b.priority if a.priority != b.priority else a.sequence < b.sequence)
	for ticket in waiters:
		if Time.get_ticks_usec() >= _deadline or (is_instance_valid(ticket.owner) and not ticket.owner.can_process()):
			_waiters.append(ticket)
			continue
		active_priority = ticket.priority
		active_owner = ticket.owner
		ticket.resumed.emit()
	active_priority = 2
	active_owner = null
	frame_started.emit()
	longest_slice_us = maxi(longest_slice_us,Time.get_ticks_usec()-_frame_begin)
	if RuntimeProfiler.recording: RuntimeProfiler.end(token)

func checkpoint(owner: Node = null) -> bool:
	if owner == null: owner = active_owner
	while not _closing and (Time.get_ticks_usec() >= _deadline or (owner != null and is_instance_valid(owner) and not owner.can_process())):
		var ticket = Ticket.new()
		ticket.sequence = _ticket_sequence
		_ticket_sequence += 1
		ticket.priority = active_priority
		ticket.owner = owner
		_waiters.append(ticket)
		await ticket.resumed
	return not _closing and (owner == null or is_instance_valid(owner))

func has_worker_room() -> bool: return not _closing and _workers.size() < WORKER_LIMIT

func submit(owner: Node, generate: Callable, apply: Callable) -> bool:
	if not has_worker_room(): return false
	var box = [null]
	var id = WorkerThreadPool.add_task(func():
		var started = Time.get_ticks_usec()
		var data = generate.call()
		box[0] = {"data":data,"duration_us":Time.get_ticks_usec()-started}
	,false,"World generation")
	if id < 0: return false
	_workers.append({"id":id,"owner":owner,"generator":generate.get_object(),"apply":apply,"box":box})
	return true

func _exit_tree():
	_closing = true
	if instance == self: instance = null
	for ticket in _waiters.duplicate(): ticket.resumed.emit()
	_waiters.clear()
	frame_started.emit()
	for job in _workers: WorkerThreadPool.wait_for_task_completion(job.id)
	_workers.clear()
