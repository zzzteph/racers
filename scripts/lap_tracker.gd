class_name LapTracker
extends RefCounted
## Pure lap / checkpoint / timing logic. No scene tree needed.

signal checkpoint_passed(checkpoint: int)
signal lap_completed(lap: int, lap_time: float)          # lap = 1-based number of the lap just completed
signal race_finished(total_time: float, lap_times: Array) # Array of float, length == total_laps
## The car came back over the start/finish line with checkpoints still outstanding, so the lap did not
## count. `missing_checkpoint` is the one it still has to reach.
signal lap_voided(missing_checkpoint: int)

## TRACK LIMITS (SPEC 49): this lap has spent longer than `limits_time` off the road, so its TIME will not
## count as a record. The lap itself, the race and the result are untouched -- only the record is.
signal lap_limits_lost()

const INDEX_WINDOW := 8

var total_laps: int = 3
var current_lap: int = 1            # 1-based lap in progress (stays == total_laps after finish)
var next_checkpoint: int = 1
var lap_times: Array[float] = []
var current_lap_time: float = 0.0
var total_time: float = 0.0
var best_lap_time: float = INF      # best lap of this race (laps that lost track limits excluded)
## SPEC 49 -- track limits. Off by default, so every existing test times laps exactly as before.
var limits_enabled: bool = false
var limits_time: float = 1.5        # s off the road in one lap before its time stops counting
var voided_laps: Array[bool] = []   # index-aligned with `lap_times`: true = no record from this lap
var running: bool = false
var finished: bool = false

var _positions: PackedVector2Array = PackedVector2Array()
var _indices: PackedInt32Array = PackedInt32Array()
var _point_count: int = 0
var _radius: float = 0.0
var _has_start_line: bool = false
var _start_origin: Vector2 = Vector2.ZERO
var _start_forward: Vector2 = Vector2.RIGHT
## True once the car has left the start/finish area this lap; a return to the line while checkpoints are
## still outstanding then means "lap not counted" (emitted once per pass, see `lap_voided`).
var _left_start: bool = false
var _lap_off_time: float = 0.0
var _lap_over_limits: bool = false


func setup(checkpoint_positions: PackedVector2Array, checkpoint_indices: PackedInt32Array,
		point_count: int, radius: float, laps: int = 3) -> void:
	_positions = checkpoint_positions.duplicate()
	_indices = checkpoint_indices.duplicate()
	_point_count = point_count
	_radius = radius
	total_laps = maxi(1, laps)
	reset()


## Optional: the drawn start/finish line (point on it + direction of travel). When set, checkpoint 0 (lap
## complete) additionally requires the car to be at or past the line (signed projection onto `forward` >= 0),
## so laps count when the car crosses the checkered strip, not when it enters the checkpoint radius.
func set_start_line(origin: Vector2, forward: Vector2) -> void:
	if forward.length_squared() <= 0.0:
		_has_start_line = false
		return
	_has_start_line = true
	_start_origin = origin
	_start_forward = forward.normalized()


func reset() -> void:
	current_lap = 1
	next_checkpoint = 1 if _positions.size() > 1 else 0
	lap_times = []
	current_lap_time = 0.0
	total_time = 0.0
	best_lap_time = INF
	running = false
	finished = false
	_left_start = false
	voided_laps = []
	_lap_off_time = 0.0
	_lap_over_limits = false


func start() -> void:
	if finished:
		return
	running = true


func stop() -> void:
	running = false


func update_race(delta: float, car_pos: Vector2, progress_index: int = -1, off_track: bool = false) -> void:
	if not running or finished:
		return
	current_lap_time += delta
	total_time += delta
	if limits_enabled and off_track:
		_lap_off_time += delta
		if not _lap_over_limits and _lap_off_time > limits_time:
			_lap_over_limits = true
			lap_limits_lost.emit()
	var count := _positions.size()
	if count == 0 or next_checkpoint < 0 or next_checkpoint >= count:
		return
	_check_voided_lap(car_pos, count)
	if car_pos.distance_to(_positions[next_checkpoint]) > _radius:
		return
	if progress_index >= 0 and next_checkpoint < _indices.size():
		if _cyclic_index_distance(progress_index, _indices[next_checkpoint]) > INDEX_WINDOW:
			return
	if next_checkpoint != 0:
		var passed := next_checkpoint
		next_checkpoint = (next_checkpoint + 1) % count
		checkpoint_passed.emit(passed)
		return
	# Checkpoint 0 reached after all others: lap complete once the car is on/over the start line.
	if _has_start_line and (car_pos - _start_origin).dot(_start_forward) < 0.0:
		return
	var lap_time := current_lap_time
	lap_times.append(lap_time)
	voided_laps.append(_lap_over_limits)
	if lap_time < best_lap_time and not _lap_over_limits:
		best_lap_time = lap_time
	_lap_off_time = 0.0
	_lap_over_limits = false
	var lap_number := lap_times.size()
	lap_completed.emit(lap_number, lap_time)
	if lap_number >= total_laps:
		finished = true
		running = false
		current_lap = total_laps
		race_finished.emit(total_time, Array(lap_times))
	else:
		current_lap += 1
		current_lap_time = 0.0
		next_checkpoint = 1 if count > 1 else 0
	_left_start = false


## Emits `lap_voided` once when the car crosses the start/finish line again with checkpoints outstanding,
## which is the only symptom the player would otherwise get of a lap that will not count.
func _check_voided_lap(car_pos: Vector2, count: int) -> void:
	if count <= 1:
		return
	var d := car_pos.distance_to(_positions[0])
	if d > _radius * 2.0:
		_left_start = true
		return
	if not _left_start or next_checkpoint == 0:
		return
	if d > _radius:
		return
	if _has_start_line and (car_pos - _start_origin).dot(_start_forward) < 0.0:
		return
	_left_start = false
	lap_voided.emit(next_checkpoint)


func get_laps_completed() -> int:
	return lap_times.size()


func is_finished() -> bool:
	return finished


func get_checkpoint_count() -> int:
	return _positions.size()


func _cyclic_index_distance(a: int, b: int) -> int:
	if _point_count <= 0:
		return absi(a - b)
	var d := posmod(a - b, _point_count)
	return mini(d, _point_count - d)
