extends Node3D

@export var npc_scene: PackedScene
@export var npcs_per_player := 30
@export var worker_count := 4
@export var movement_radius := 1.25
@export var movement_speed := 1.5
@export var npc_spacing := 1.8

var _workers: Array[Thread] = []
var _job_semaphore := Semaphore.new()
var _job_mutex := Mutex.new()
var _state_mutex := Mutex.new()
var _jobs: Array[Dictionary] = []
var _states: Array[Dictionary] = []
var _npcs: Array[Node3D] = []
var _origins: Array[Vector3] = []
var _running := false
var _queued_jobs := 0
var _finished_jobs := 0
var _elapsed_time := 0.0


func _ready():
	if npc_scene == null:
		npc_scene = preload("res://scenes/npc/threaded_npc.tscn")

	_start_workers()
	set_player_count(_get_current_player_count())


func _process(delta):
	_elapsed_time += delta
	_apply_finished_states()
	_queue_frame_jobs()


func _exit_tree():
	_stop_workers()


func set_player_count(player_count: int):
	var npc_count: int = int(max(1, player_count)) * npcs_per_player
	_rebuild_npcs(npc_count)


func _get_current_player_count() -> int:
	if "--debug_solo" in OS.get_cmdline_args():
		return 1

	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_peers().size() + 1

	return 1


func _start_workers():
	_running = true
	var count: int = int(max(1, worker_count))

	for i in range(count):
		var worker := Thread.new()
		_workers.append(worker)
		worker.start(_worker_loop)


func _stop_workers():
	_job_mutex.lock()
	_running = false
	_job_mutex.unlock()

	for worker in _workers:
		_job_semaphore.post()

	for worker in _workers:
		if worker.is_started():
			worker.wait_to_finish()

	_workers.clear()


func _rebuild_npcs(npc_count: int):
	_wait_for_pending_jobs()

	for npc in _npcs:
		npc.queue_free()

	_npcs.clear()
	_origins.clear()
	_states.clear()

	for i in range(npc_count):
		var npc := npc_scene.instantiate() as Node3D
		var origin := _calculate_origin(i)

		npc.name = "ThreadedNPC_%02d" % i
		npc.position = origin
		add_child(npc)

		_npcs.append(npc)
		_origins.append(origin)
		_states.append({
			"position": origin,
			"rotation_y": 0.0,
		})


func _calculate_origin(index: int) -> Vector3:
	var columns: int = int(max(1, int(ceil(sqrt(float(npcs_per_player))))))
	var player_index: int = int(index / npcs_per_player)
	var local_index: int = index % npcs_per_player
	var x: float = float(local_index % columns) * npc_spacing
	var z: float = float(int(local_index / columns)) * npc_spacing
	var player_offset: Vector3 = Vector3(float(player_index) * npc_spacing * float(columns + 2), 0.0, 0.0)

	return Vector3(-6.0 + x, 1.0, -6.0 + z) + player_offset


func _queue_frame_jobs():
	if _has_pending_jobs() or _npcs.is_empty():
		return

	var jobs: Array[Dictionary] = []

	for i in range(_npcs.size()):
		jobs.append({
			"index": i,
			"origin": _origins[i],
			"time": _elapsed_time,
			"phase": float(i) * 0.37,
			"movement_radius": movement_radius,
			"movement_speed": movement_speed,
		})

	_job_mutex.lock()
	_jobs.append_array(jobs)
	_queued_jobs = jobs.size()
	_finished_jobs = 0
	_job_mutex.unlock()

	for i in range(jobs.size()):
		_job_semaphore.post()


func _has_pending_jobs() -> bool:
	_job_mutex.lock()
	var pending: bool = _queued_jobs > 0 and _finished_jobs < _queued_jobs
	_job_mutex.unlock()
	return pending


func _apply_finished_states():
	if _npcs.is_empty():
		return

	_state_mutex.lock()
	var states: Array = _states.duplicate(true)
	_state_mutex.unlock()

	for i in range(int(min(_npcs.size(), states.size()))):
		_npcs[i].apply_simulation_state(states[i]["position"], states[i]["rotation_y"])


func _wait_for_pending_jobs():
	while _has_pending_jobs():
		OS.delay_msec(1)


func _worker_loop():
	while true:
		_job_semaphore.wait()

		_job_mutex.lock()
		if not _running and _jobs.is_empty():
			_job_mutex.unlock()
			break

		if _jobs.is_empty():
			_job_mutex.unlock()
			continue

		var job: Dictionary = _jobs.pop_back()
		_job_mutex.unlock()

		var state: Dictionary = _simulate_npc(job)

		_state_mutex.lock()
		_states[int(job["index"])] = state
		_state_mutex.unlock()

		_job_mutex.lock()
		_finished_jobs += 1
		_job_mutex.unlock()


func _simulate_npc(job: Dictionary) -> Dictionary:
	var time := float(job["time"])
	var phase := float(job["phase"])
	var origin: Vector3 = job["origin"]
	var radius := float(job["movement_radius"])
	var speed := float(job["movement_speed"])
	var angle: float = time * speed + phase
	var next_position: Vector3 = origin + Vector3(
		cos(angle) * radius,
		0.0,
		sin(angle) * radius
	)

	return {
		"position": next_position,
		"rotation_y": -angle,
	}
