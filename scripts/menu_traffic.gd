class_name MenuTraffic
extends Node2D
## The title screen's traffic: a handful of cars (random types and colours) racing left to right across
## the title band at different speeds, wrapping round, and every now and then one kicks its tail out into
## a short, tidy drift with a puff of tyre smoke. Pure decoration: the cars are never simulated -- their
## pose is set directly and they draw themselves (3D models where 3D can be rendered).
##
## They drive like traffic, not ghosts: a car that catches a slower one in its lane moves over to the
## other lane if there is room there, and otherwise lifts and follows at a safe gap; and no two cars are
## ever allowed to overlap, whatever the drifts do.

const CAR_COUNT := 5
const LANES := [104.0, 158.0]
const SPEED_MIN := 170.0
const SPEED_MAX := 430.0
const DRIFT_CHANCE := 0.12        # per second, per car
const DRIFT_TIME := 1.3           # s from kick-out to straight again
const DRIFT_ANGLE := 0.55         # rad of body angle at the peak
const MARGIN := 70.0              # px off-screen a car wraps at
const LOOK_AHEAD := 90.0          # px: a slower car this close ahead in the lane is "in the way"
const FOLLOW_GAP := 56.0          # px kept behind a car that cannot be passed
const LANE_CLEAR := 80.0          # px of free lane needed (ahead and behind) to move over
const LANE_CHANGE_RATE := 2.2     # 1/s: how quickly a car slides into its new lane
const MIN_GAP := 44.0             # px between two cars' centres, never less
const Y_MIN := 80.0
const Y_MAX := 182.0

var _cars: Array = []             # [{car, speed, cruise, lane, drift_t, drift_dir}]
var _puffs: Array = []            # [{pos, vel, life, max}]
var _rng := RandomNumberGenerator.new()
var _width: float = 1280.0


func _ready() -> void:
	_rng.randomize()
	for i in CAR_COUNT:
		var c := preload("res://scenes/car.tscn").instantiate() as Car
		c.auto_process = false
		c.use_mouse = false
		c.rope_visible = false
		add_child(c)
		var entry := {"car": c, "speed": 0.0, "cruise": 0.0, "lane": 0, "drift_t": -1.0, "drift_dir": 1.0}
		_cars.append(entry)
		# Spread the starting cars out so none begins on top of another.
		_respawn(entry, -MARGIN + float(i) * (_width + MARGIN * 2.0) / float(CAR_COUNT))


func _respawn(e: Dictionary, x: float) -> void:
	var c: Car = e["car"]
	var ids := CarRegistry.ids()
	CarRegistry.apply(c, ids[_rng.randi_range(0, ids.size() - 1)], _rng.randi_range(0, CarRegistry.PALETTE_SIZE - 1))
	e["cruise"] = _rng.randf_range(SPEED_MIN, SPEED_MAX)
	e["speed"] = e["cruise"]
	e["drift_t"] = -1.0
	# Enter in whichever lane has room at that spot; failing both, a bit further back.
	var lane := _rng.randi_range(0, LANES.size() - 1)
	for attempt in 6:
		if _lane_clear(lane, x, e):
			break
		lane = 1 - lane
		if _lane_clear(lane, x, e):
			break
		x -= 90.0
	e["lane"] = lane
	c.position = Vector2(x, float(LANES[lane]))
	c.heading = 0.0
	c.rotation = 0.0
	c.queue_redraw()


## Is lane `lane` free of other cars within LANE_CLEAR of x (ahead and behind)?
func _lane_clear(lane: int, x: float, me: Dictionary) -> bool:
	for o in _cars:
		if o == me:
			continue
		var oc: Car = o["car"]
		if int(o["lane"]) == lane and absf(oc.position.x - x) < LANE_CLEAR:
			return false
	return true


## The nearest car ahead of `e` in its lane (or {}), and its distance.
func _car_ahead(e: Dictionary) -> Array:
	var c: Car = e["car"]
	var best := {}
	var best_d := INF
	for o in _cars:
		if o == e or int(o["lane"]) != int(e["lane"]):
			continue
		var d: float = (o["car"] as Car).position.x - c.position.x
		if d > 0.0 and d < best_d:
			best_d = d
			best = o
	return [best, best_d]


func _process(delta: float) -> void:
	for e in _cars:
		_drive(e, delta)
	for e in _cars:
		var c: Car = e["car"]
		if c.position.x > _width + MARGIN:
			_respawn(e, -MARGIN - _rng.randf_range(0.0, 200.0))
	# Last, so neither a drift, a lane change nor a car wrapping round can leave two cars overlapping.
	_separate()
	for i in range(_puffs.size() - 1, -1, -1):
		var p: Dictionary = _puffs[i]
		p["life"] = float(p["life"]) - delta
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		if float(p["life"]) <= 0.0:
			_puffs.remove_at(i)
	queue_redraw()


func _drive(e: Dictionary, delta: float) -> void:
	var c: Car = e["car"]
	var want: float = e["cruise"]
	# Traffic: overtake in the other lane if it is free, otherwise follow.
	var ahead := _car_ahead(e)
	var other: Dictionary = ahead[0]
	var gap: float = ahead[1]
	if not other.is_empty() and gap < LOOK_AHEAD and float(other["speed"]) < want:
		var free_lane := 1 - int(e["lane"])
		if _lane_clear(free_lane, c.position.x, e) and float(e["drift_t"]) < 0.0:
			e["lane"] = free_lane
		else:
			var follow := float(other["speed"]) * clampf((gap - FOLLOW_GAP) / (LOOK_AHEAD - FOLLOW_GAP), 0.0, 1.2)
			want = minf(want, follow)
	e["speed"] = lerpf(float(e["speed"]), want, 1.0 - exp(-4.0 * delta))
	var speed: float = e["speed"]

	var angle := 0.0
	var lateral := 0.0
	if float(e["drift_t"]) >= 0.0:
		var t: float = e["drift_t"] + delta
		e["drift_t"] = t
		var f := sin(clampf(t / DRIFT_TIME, 0.0, 1.0) * PI)      # 0 -> 1 -> 0
		angle = float(e["drift_dir"]) * DRIFT_ANGLE * f
		lateral = -float(e["drift_dir"]) * 40.0 * f * cos(t * 4.0)
		speed *= 1.0 - 0.18 * f
		if _rng.randf() < 0.6:
			_puff(c.position - Vector2.from_angle(angle) * 16.0)
		if t >= DRIFT_TIME:
			e["drift_t"] = -1.0
	elif _rng.randf() < DRIFT_CHANCE * delta:
		e["drift_t"] = 0.0
		e["drift_dir"] = 1.0 if _rng.randf() < 0.5 else -1.0

	# Slide toward the lane's line; a lane change leans the nose into it.
	var lane_y := float(LANES[int(e["lane"])])
	var dy := (lane_y - c.position.y) * (1.0 - exp(-LANE_CHANGE_RATE * delta))
	if float(e["drift_t"]) < 0.0:
		angle += clampf(dy / maxf(speed * delta, 0.001), -0.35, 0.35)
	c.position.x += speed * delta
	c.position.y = clampf(c.position.y + dy + lateral * delta, Y_MIN, Y_MAX)
	c.heading = angle
	c.rotation = angle
	c.queue_redraw()


## The hard rule: no two cars closer than MIN_GAP. The one behind is pushed back and slowed to the other's
## speed, so a drift or a lane change can never put one car through another.
## Pushing one car back can push it into the car behind it, so the pass repeats (front to back) until
## nothing overlaps.
func _separate() -> void:
	for _pass in 6:
		var moved := false
		for i in _cars.size():
			for j in range(i + 1, _cars.size()):
				var a: Dictionary = _cars[i]
				var b: Dictionary = _cars[j]
				var ca: Car = a["car"]
				var cb: Car = b["car"]
				var d := cb.position - ca.position
				if d.length() >= MIN_GAP - 0.01 or absf(d.y) >= 30.0:
					continue
				var behind: Dictionary = a if ca.position.x < cb.position.x else b
				var front: Dictionary = b if behind == a else a
				var cbh: Car = behind["car"]
				var cf: Car = front["car"]
				var need := sqrt(maxf(MIN_GAP * MIN_GAP - (cf.position.y - cbh.position.y) ** 2, 0.0))
				cbh.position.x = minf(cbh.position.x, cf.position.x - need)
				behind["speed"] = minf(float(behind["speed"]), float(front["speed"]))
				moved = true
		if not moved:
			break


func _puff(pos: Vector2) -> void:
	if _puffs.size() > 80:
		return
	var life := _rng.randf_range(0.5, 0.9)
	_puffs.append({"pos": pos + Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-4, 4)),
			"vel": Vector2(_rng.randf_range(-30, 10), _rng.randf_range(-25, -5)), "life": life, "max": life})


func _draw() -> void:
	for p in _puffs:
		var k := float(p["life"]) / float(p["max"])
		draw_circle(p["pos"], 3.0 + 9.0 * (1.0 - k), Color(0.9, 0.9, 0.92, 0.35 * k))


func get_car_count() -> int:
	return _cars.size()


## The closest two cars have been this frame (for tests): centre distance of the nearest pair that is in
## the same band (|dy| < 30).
func get_min_gap() -> float:
	var best := INF
	for i in _cars.size():
		for j in range(i + 1, _cars.size()):
			var d: Vector2 = (_cars[j]["car"] as Car).position - (_cars[i]["car"] as Car).position
			if absf(d.y) < 30.0:
				best = minf(best, d.length())
	return best
