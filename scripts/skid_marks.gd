class_name SkidMarks
extends Node2D
## Persistent per-wheel ground marks (rubber on asphalt, dirt scuffs on grass).
##
## Pure consumer of [method Car.get_wheel_states] (SPEC 9.B): it never writes to the car and nothing it
## does can change the simulation. [Race] drives it with an explicit [method sample] call once per physics
## frame, after [code]car.physics_step()[/code] (SPEC decision 13), so hand-stepped tests see exactly what
## the running game sees.
##
## Storage is a fixed-size ring buffer of parallel packed arrays — no per-segment object, no allocation in
## [method sample] once [method set_car] has sized the buffers. Marks laid on the figure-8 bridge deck go to
## the [code]"OnBridge"[/code] child so they are drawn on the deck instead of underneath it.

const GROUND_Z := 2      # between Track (0) and the car under the bridge (5)
const BRIDGE_Z := 15     # between the bridge deck (10) and the car on the bridge (20)

const LAYER_GROUND := 0
const LAYER_BRIDGE := 1

const KIND_ASPHALT := 0
const KIND_GRASS := 1

const WHEEL_COUNT := 4

## Look (SPEC 9.B). Asphalt marks are near-black and translucent; grass marks are wider, lighter brown
## dirt streaks that fade faster.
const ASPHALT_COLOR := Color(0.05, 0.05, 0.06)
const GRASS_COLOR := Color(0.42, 0.33, 0.20)
const GRASS_WIDTH_FACTOR := 1.5
const GRASS_ALPHA_FACTOR := 0.6
const GRASS_FADE_FACTOR := 0.6
const WIDTH_MIN := 1.6
const WIDTH_MAX := 5.0
const MAX_ALPHA := 0.75
const BASE_ALPHA := 0.18
const ALPHA_GAIN := 0.55
## px/s of patch slide that counts as a "full" slide for width/alpha.
const SLIP_REFERENCE := 220.0
## A streak longer than this is assumed to be a discontinuity (teleport / reset), not a skid: the streak is
## restarted instead of drawing a line across the screen. A wheel covers ~10 px per frame at max speed.
const MAX_STREAK_JUMP := 120.0
## s a streak survives after its wheel stops qualifying. Dropping it on the first non-qualifying frame made
## a slide that flickers over the threshold lay nothing at all.
const STREAK_GRACE := 0.1
## `Car.get_roll_height()` above which the wheels are in the air and cannot be laying anything down.
const AIRBORNE_HEIGHT := 0.15

## Hard cap on stored segments. The oldest slot is recycled when the buffer is full, so the player always
## sees their most recent drift (SPEC decision 14).
@export var max_segments: int = 1600
## px a wheel must travel before a new segment is laid.
@export var min_segment_length: float = 6.0
## s until an asphalt segment is invisible (grass fades in `fade_time * GRASS_FADE_FACTOR`).
@export var fade_time: float = 10.0
## s between fade redraws — marks only redraw when they change or this has elapsed.
@export var redraw_interval: float = 0.1
## Hard cap on segments added per frame (one per wheel).
@export var max_new_per_frame: int = 4
## `load_ratio` a wheel needs to leave a mark ("heavy load on the tires"). Kept at 0.35: the rear axle under
## hard braking is the pair that locks and it runs at 0.44, so a threshold high enough to reject a "normally
## loaded" wheel (~1.15) would delete exactly the brake marks the brief asks for. What this gate cannot do
## is separate a working tire from a sliding one — that is `mark_min_lat_sat` / `mark_min_long_sat` below.
@export var mark_min_load: float = 0.35
## px/s of patch slide a wheel needs to leave a mark.
@export var mark_min_slip: float = 45.0
## Fraction of `mark_min_slip` demanded on grass. A car flagged off track is capped at `off_track_max_speed`
## (58 px/s) by Car's crawl, so at the full threshold a wheel had to be sliding almost dead sideways at the
## crawl speed to qualify: two 120 s reckless runs ended with 0 and 21 dirt segments. The brief's "marks on
## grass = lighter dirt marks instead" needs a threshold scaled to the speed the surface allows.
@export var grass_slip_factor: float = 0.40
## The tire's own verdict, and the half of the gate that separates "heavy load" from "heavy load AND
## SLIPPING". A wheel marks when it is past `mark_min_lat_sat` of its peak slip angle (cornering hard /
## drifting) or its longitudinal demand is CLIPPED by its capacity (`mark_min_long_sat` >= 1.0: a genuine
## lock-up or wheelspin). Measured with the shipped tuning: a clean lap at the 96-192 px lines lays 0
## segments (its wheels peak at 0.30-0.40 of lateral saturation and 0.94 of longitudinal), a committed
## 224 px line lays them through the corners, a provoked slide lays them under all four wheels, and standing
## on the brakes from 580 px/s lays them under the locking rear pair.
## This replaces a load+slip-only gate that fired on 98 % of the wheel-frames the tire model reported as
## GRIPPING: a clean lap laid 9049 px of streak on a 2531 px track (357 % of the lap in black), which is
## neither what the user asked for nor what CarEffects smoked on the same lap.
@export var mark_min_lat_sat: float = 0.45
@export var mark_min_long_sat: float = 1.00

var car: Car

# --- ring buffer (parallel packed arrays, sized once in set_car()/clear()) ---
var _seg_a := PackedVector2Array()
var _seg_b := PackedVector2Array()
var _seg_width := PackedFloat32Array()
var _seg_alpha := PackedFloat32Array()
var _seg_born := PackedFloat32Array()
var _seg_kind := PackedByteArray()
var _seg_layer := PackedByteArray()
var _capacity: int = 0
## The mesh each layer is drawing (SPEC 54), held for as long as it is on screen: `draw_mesh` records a
## reference to it, so a mesh built as a local in `_draw` is freed before it is ever painted.
## Perf round: TWO meshes per layer. The BAKE holds every live segment and is rebuilt at the
## `redraw_interval` cadence (the fade step); the FRESH mesh holds only the segments laid since the bake
## and is the one rebuilt on the ticks that add a segment -- a few dozen quads instead of the whole
## buffer (1600-3200 segments, 0.6-1 ms a rebuild) every time a wheel lays six pixels of rubber.
var _layer_mesh: Array[ArrayMesh] = [null, null]
var _layer_paint: Array[MeshPaint] = [null, null]
var _layer_has := PackedByteArray([0, 0])
var _fresh_mesh: Array[ArrayMesh] = [null, null]
var _fresh_paint: Array[MeshPaint] = [null, null]
var _fresh_has := PackedByteArray([0, 0])
var _pushed: int = 0                            # segments pushed since clear(), never wraps
var _baked_at := PackedInt32Array([-1, -1])     # `_pushed` when each layer's bake was made
var _bake_due := PackedByteArray([1, 1])
## More fresh segments than this and the bake is simply redone.
const FRESH_MAX := 200
## Raised by `sample()` (a physics tick), flushed once per drawn frame from `_process`: a `queue_redraw`
## from a tick paints in that tick's own flush, two or three times a frame when the frame is slow.
var _redraw_pending: bool = false
var _head: int = 0          # next slot to write
var _count: int = 0         # occupied slots (tail .. head-1)
var _dropped: int = 0       # segments recycled since the last clear()
## Occupied slots per layer, so a layer with nothing on it costs one comparison instead of a full sweep.
var _layer_count := PackedInt32Array([0, 0])

# --- per-wheel streak state ---
var _last_point := PackedVector2Array()
var _has_last := PackedByteArray()
var _prev_pos := PackedVector2Array()   # last frame's contact patch, qualifying or not
var _has_prev := PackedByteArray()
var _streak_left := PackedFloat32Array()  # s of grace left on a streak whose wheel stopped qualifying
var _bridge_last_count: int = 0

var _time: float = 0.0              # local clock, advanced only by sample(delta) — deterministic
var _redraw_accum: float = 0.0
var _bridge_layer: Node2D = null
var _has_deck_query: bool = false
## Optional `func(pos: Vector2) -> bool`: is this POINT inside the drawn bridge deck? Supplied by [Race]
## from [method Track.is_point_on_deck]. Without it the car-level arc test is used, as before.
var _deck_probe: Callable = Callable()


## Drawing node for marks laid on the bridge deck. Kept as a child so the deck marks can sit at a
## different z_index than the ground marks while sharing one buffer.
class BridgeMarkLayer:
	extends Node2D

	var marks: Node2D = null

	func _draw() -> void:
		if marks != null and is_instance_valid(marks):
			marks.draw_layer_into(self, 1)


func _ready() -> void:
	z_as_relative = false
	z_index = GROUND_Z


## Binds the car whose wheels lay the marks and builds the "OnBridge" child. Sizes the ring buffer once.
func set_car(c: Car) -> void:
	car = c
	# Resolved once: `sample()` runs every physics frame and has_method() is not free.
	_has_deck_query = c != null and c.has_method("is_on_bridge_deck")
	_ensure_capacity()
	_reset_streaks()
	if _bridge_layer == null or not is_instance_valid(_bridge_layer):
		var found := get_node_or_null("OnBridge")
		if found is Node2D:
			_bridge_layer = found
		else:
			var layer := BridgeMarkLayer.new()
			layer.name = "OnBridge"
			layer.marks = self
			_bridge_layer = layer
			add_child(layer)
	_bridge_layer.z_as_relative = false
	_bridge_layer.z_index = BRIDGE_Z
	z_as_relative = false
	z_index = GROUND_Z
	_request_redraw()


## One sampling step. Called explicitly by [Race] once per physics frame, after `car.physics_step()`.
## Lays at most one segment per wheel: a wheel marks when it is sliding, heavily loaded and has travelled
## at least [member min_segment_length] since its last point.
func sample(delta: float) -> void:
	if delta > 0.0:
		_time += delta
		_redraw_accum += delta
	if car == null or not is_instance_valid(car):
		_maybe_fade_redraw()
		return
	if _capacity <= 0:
		_ensure_capacity()
	# Keeps the drawn window free of dead slots even while marking continuously (`_maybe_fade_redraw`,
	# the only other caller, never runs on a frame that added a segment).
	_prune_tail()
	var states: Array = car.get_wheel_states()
	if states.is_empty():
		_maybe_fade_redraw()
		return
	if car.get_roll_height() > AIRBORNE_HEIGHT:
		# Mid barrel roll the car is drawn up to 26 px away from its own shadow; `Car` keeps solving the
		# tires (the geometry is still wanted) but nothing is touching the ground, so nothing is laid and
		# every streak is dropped so it restarts cleanly on landing.
		_reset_streaks()
		_maybe_fade_redraw()
		return
	# Cheap early-out only: `car.is_on_bridge_deck()` is an along-arc test on the car's progress index and
	# says nothing about how far sideways a wheel is, so each segment is classified individually below.
	var deck_possible := _has_deck_query and car.is_on_bridge_deck()
	var added := 0
	var budget := max_new_per_frame
	for i in mini(states.size(), WHEEL_COUNT):
		var w: Dictionary = states[i]
		if w.is_empty():
			continue
		var idx: int = w.get("index", i)
		if idx < 0 or idx >= WHEEL_COUNT:
			idx = i
		var pos: Vector2 = w.get("position", Vector2.ZERO)
		var pos_ok := _is_finite(pos)
		var prev_known := _has_prev[idx] != 0
		var prev: Vector2 = _prev_pos[idx]
		if pos_ok:
			_prev_pos[idx] = pos
			_has_prev[idx] = 1
		else:
			_has_prev[idx] = 0
		var load_ratio := float(w.get("load_ratio", 0.0))
		var slip_speed := float(w.get("slip_speed", 0.0))
		var surface := String(w.get("surface", "asphalt"))
		var on_grass := surface == "grass"
		var slip_gate := mark_min_slip * (grass_slip_factor if on_grass else 1.0)
		var saturated := float(w.get("lat_saturation", 0.0)) >= mark_min_lat_sat \
				or float(w.get("long_saturation", 0.0)) >= mark_min_long_sat
		if not (pos_ok and saturated and load_ratio >= mark_min_load and slip_speed >= slip_gate):
			# Hold the streak for a moment instead of dropping it at once, so a slide that flickers over
			# and under the threshold still draws one continuous line.
			if _has_last[idx] != 0:
				_streak_left[idx] = _streak_left[idx] - maxf(delta, 0.0)
				if _streak_left[idx] <= 0.0:
					_has_last[idx] = 0
			continue
		_streak_left[idx] = STREAK_GRACE
		if _has_last[idx] == 0:
			# Seed the streak from where this wheel was LAST frame, so a single qualifying frame already
			# lays a segment. Requiring two consecutive qualifying frames silently discarded every brief
			# slip: measured 59 and 232 qualifying wheel-frames on two laps, and 0 segments from either.
			if not prev_known:
				_last_point[idx] = pos
				_has_last[idx] = 1
				continue
			_last_point[idx] = prev
			_has_last[idx] = 1
		var from: Vector2 = _last_point[idx]
		var dist := from.distance_to(pos)
		if dist > MAX_STREAK_JUMP:
			# Discontinuity (reset/teleport): restart the streak instead of drawing across the screen.
			_last_point[idx] = pos
			continue
		if dist < min_segment_length:
			continue
		if added >= budget:
			continue
		var kind := KIND_GRASS if on_grass else KIND_ASPHALT
		_push_segment(from, pos, load_ratio, slip_speed, kind, deck_possible)
		_last_point[idx] = pos
		added += 1
	if added > 0:
		_request_redraw()            # the new segments join the fresh mesh
	# The fade cadence runs on regardless of what was added: it is what re-bakes the whole buffer. (It
	# used to restart on every added segment, which made continuous marking a full rebuild per tick.)
	_maybe_fade_redraw()


## Empties the buffer and the per-wheel streaks (called on restart).
func clear() -> void:
	_ensure_capacity()
	_head = 0
	_count = 0
	_dropped = 0
	_layer_count[LAYER_GROUND] = 0
	_layer_count[LAYER_BRIDGE] = 0
	_pushed = 0
	_baked_at[LAYER_GROUND] = -1
	_baked_at[LAYER_BRIDGE] = -1
	_time = 0.0
	_redraw_accum = 0.0
	_reset_streaks()
	_request_redraw()


## Live (not yet faded out) segments.
func get_segment_count() -> int:
	_prune_tail()
	var live := 0
	for k in _count:
		var idx := _slot(k)
		if _time - _seg_born[idx] < _fade_for(_seg_kind[idx]):
			live += 1
	return live


## Segments recycled since the last [method clear] — proves the cap recycles instead of growing.
func get_dropped_count() -> int:
	return _dropped


func get_last_point(wheel_index: int) -> Vector2:
	if wheel_index < 0 or wheel_index >= _last_point.size():
		return Vector2.ZERO
	return _last_point[wheel_index]


func has_last_point(wheel_index: int) -> bool:
	if wheel_index < 0 or wheel_index >= _has_last.size():
		return false
	return _has_last[wheel_index] != 0


## The "OnBridge" child that draws deck marks (for tests / wiring checks).
func get_bridge_layer() -> Node2D:
	return _bridge_layer


## Segments currently stored on the given layer (LAYER_GROUND / LAYER_BRIDGE), faded ones excluded.
func get_layer_segment_count(layer: int) -> int:
	_prune_tail()
	var live := 0
	for k in _count:
		var idx := _slot(k)
		if _seg_layer[idx] != layer:
			continue
		if _time - _seg_born[idx] < _fade_for(_seg_kind[idx]):
			live += 1
	return live


## Debug/test accessor: a copy of one live segment's data, oldest first. Empty dictionary when out of range.
func get_segment_info(order_index: int) -> Dictionary:
	if order_index < 0 or order_index >= _count:
		return {}
	var idx := _slot(order_index)
	return {
		"a": _seg_a[idx],
		"b": _seg_b[idx],
		"width": _seg_width[idx],
		"alpha": _seg_alpha[idx],
		"age": _time - _seg_born[idx],
		"fade": _fade_for(_seg_kind[idx]),
		"kind": int(_seg_kind[idx]),
		"layer": int(_seg_layer[idx]),
		"color": GRASS_COLOR if int(_seg_kind[idx]) == KIND_GRASS else ASPHALT_COLOR,
	}


func _draw() -> void:
	draw_layer_into(self, LAYER_GROUND)


## Draws every live segment of `layer` into `target`. Public because the "OnBridge" child calls it back.
## Hot path: the occupied window is walked as one or two contiguous index ranges (no modulo, no function
## call per segment), and a layer holding nothing costs a single comparison.
func draw_layer_into(target: CanvasItem, layer: int) -> void:
	if _count <= 0 or layer < 0 or layer >= _layer_count.size():
		return
	if _layer_count[layer] <= 0:
		return
	if _layer_paint[layer] == null:
		_layer_paint[layer] = MeshPaint.new()
		_layer_mesh[layer] = ArrayMesh.new()
		_fresh_paint[layer] = MeshPaint.new()
		_fresh_mesh[layer] = ArrayMesh.new()
	var fresh := _pushed - _baked_at[layer]
	if _bake_due[layer] != 0 or _baked_at[layer] < 0 or fresh > FRESH_MAX:
		# SPEC 54: every live segment of this layer in ONE mesh. It was a `draw_line` per segment, and a
		# car sliding across the grass lays them down as fast as it can move.
		_bake_due[layer] = 0
		var tail := (_head - _count + _capacity) % _capacity
		var first_end := mini(tail + _count, _capacity)
		var paint := _layer_paint[layer]
		paint.reset()
		paint.reserve(_layer_count[layer] * 2)        # two triangles per segment, one allocation
		_paint_range(paint, layer, tail, first_end)
		var wrapped := _count - (first_end - tail)
		if wrapped > 0:
			_paint_range(paint, layer, 0, wrapped)
		_layer_has[layer] = 1 if paint.build_into(_layer_mesh[layer]) else 0
		_baked_at[layer] = _pushed
		_fresh_has[layer] = 0
	else:
		# Only what was laid since the bake: the newest `fresh` slots before the head.
		var fp := _fresh_paint[layer]
		fp.reset()
		var n := mini(fresh, _count)
		if n > 0:
			var start := (_head - n + _capacity) % _capacity
			var first := mini(n, _capacity - start)
			_paint_range(fp, layer, start, start + first)
			if n > first:
				_paint_range(fp, layer, 0, n - first)
		_fresh_has[layer] = 1 if fp.build_into(_fresh_mesh[layer]) else 0
	if _layer_has[layer] != 0:
		target.draw_mesh(_layer_mesh[layer], null)
	if _fresh_has[layer] != 0:
		target.draw_mesh(_fresh_mesh[layer], null)


func _paint_range(paint: MeshPaint, layer: int, from_idx: int, to_idx: int) -> void:
	var fade_asphalt := maxf(fade_time, 0.0001)
	var fade_grass := maxf(fade_time * GRASS_FADE_FACTOR, 0.0001)
	var inv_asphalt := 1.0 / fade_asphalt
	var inv_grass := 1.0 / fade_grass
	var now := _time
	var col := ASPHALT_COLOR
	for idx in range(from_idx, to_idx):
		if _seg_layer[idx] != layer:
			continue
		var age := now - _seg_born[idx]
		var f := 0.0
		if _seg_kind[idx] == KIND_GRASS:
			f = 1.0 - age * inv_grass
			col = GRASS_COLOR
		else:
			f = 1.0 - age * inv_asphalt
			col = ASPHALT_COLOR
		if f <= 0.0:
			continue
		var a := _seg_alpha[idx] * f
		if a <= 0.004:
			continue
		col.a = a
		paint.add_line(_seg_a[idx], _seg_b[idx], _seg_width[idx], col)


# --- internals -------------------------------------------------------------------------------------

## `deck_possible` is the car-level early-out; the layer is decided from the SEGMENT's own midpoint.
## The car's deck query is an along-arc test, so with it alone a drift on the bridge painted skid lines at
## BRIDGE_Z straight over the deck's edge band, its rail and its posts and on across the grass beyond it
## (wheels reach 59 px of lateral offset in a real slide against a 55 px half-width), and a segment that
## straddles a deck end landed on the wrong side of it (measured 10 ground segments swallowed by the deck
## and 3 deck segments painted over the lower road on one figure-8 run).
func _push_segment(from: Vector2, to: Vector2, load_ratio: float, slip_speed: float,
		kind: int, deck_possible: bool) -> void:
	if _capacity <= 0:
		return
	var layer := LAYER_GROUND
	if deck_possible and _point_on_deck((from + to) * 0.5):
		layer = LAYER_BRIDGE
		# The deck is concrete: a wheel whose body flag says "off track" is still on the deck here.
		kind = KIND_ASPHALT
	var load_f := clampf(load_ratio * 0.5, 0.0, 1.0)
	var slip_f := clampf(slip_speed / SLIP_REFERENCE, 0.0, 1.0)
	var intensity := load_f * slip_f
	var width := lerpf(WIDTH_MIN, WIDTH_MAX, load_f) * clampf(slip_speed / SLIP_REFERENCE, 0.35, 1.0)
	var alpha := clampf(BASE_ALPHA + ALPHA_GAIN * intensity, 0.0, MAX_ALPHA)
	if kind == KIND_GRASS:
		width *= GRASS_WIDTH_FACTOR
		alpha *= GRASS_ALPHA_FACTOR
	var idx := _head
	if _count >= _capacity:
		# The slot being overwritten is the oldest one: retire it first.
		_layer_count[_seg_layer[idx]] -= 1
		_dropped += 1
	else:
		_count += 1
	_seg_a[idx] = from
	_seg_b[idx] = to
	_seg_width[idx] = width
	_seg_alpha[idx] = alpha
	_seg_born[idx] = _time
	_seg_kind[idx] = kind
	_seg_layer[idx] = layer
	_layer_count[layer] += 1
	_head = (idx + 1) % _capacity
	_pushed += 1


## Index of the k-th oldest occupied slot.
func _slot(k: int) -> int:
	return (_head - _count + k + _capacity * 2) % _capacity


func _fade_for(kind: int) -> float:
	if kind == KIND_GRASS:
		return maxf(fade_time * GRASS_FADE_FACTOR, 0.0001)
	return maxf(fade_time, 0.0001)


## Releases fully faded slots from the oldest end so the occupied window stays tight.
func _prune_tail() -> void:
	while _count > 0:
		var idx := _slot(0)
		if _time - _seg_born[idx] >= _fade_for(_seg_kind[idx]):
			_layer_count[_seg_layer[idx]] -= 1
			_count -= 1
		else:
			break


func _ensure_capacity() -> void:
	var want := maxi(max_segments, 1)
	if _capacity == want and _seg_a.size() == want:
		return
	_capacity = want
	_seg_a.resize(want)
	_seg_b.resize(want)
	_seg_width.resize(want)
	_seg_alpha.resize(want)
	_seg_born.resize(want)
	_seg_kind.resize(want)
	_seg_layer.resize(want)
	_head = 0
	_count = 0
	_dropped = 0
	_layer_count[LAYER_GROUND] = 0
	_layer_count[LAYER_BRIDGE] = 0
	_pushed = 0
	_baked_at[LAYER_GROUND] = -1
	_baked_at[LAYER_BRIDGE] = -1


func _reset_streaks() -> void:
	if _last_point.size() != WHEEL_COUNT:
		_last_point.resize(WHEEL_COUNT)
	if _has_last.size() != WHEEL_COUNT:
		_has_last.resize(WHEEL_COUNT)
	if _prev_pos.size() != WHEEL_COUNT:
		_prev_pos.resize(WHEEL_COUNT)
	if _has_prev.size() != WHEEL_COUNT:
		_has_prev.resize(WHEEL_COUNT)
	if _streak_left.size() != WHEEL_COUNT:
		_streak_left.resize(WHEEL_COUNT)
	for i in WHEEL_COUNT:
		_last_point[i] = Vector2.ZERO
		_has_last[i] = 0
		_prev_pos[i] = Vector2.ZERO
		_has_prev[i] = 0
		_streak_left[i] = 0.0


## The fade step: every `redraw_interval`, the whole buffer is re-baked at its current alphas.
func _maybe_fade_redraw() -> void:
	if _count <= 0:
		return
	if _redraw_accum >= redraw_interval:
		_redraw_accum = 0.0
		_prune_tail()
		_bake_due[LAYER_GROUND] = 1
		_bake_due[LAYER_BRIDGE] = 1
		_request_redraw()


func _request_redraw() -> void:
	_redraw_pending = true


## One `queue_redraw` per drawn frame, however many ticks asked for it.
func _process(_delta: float) -> void:
	if not _redraw_pending:
		return
	_redraw_pending = false
	queue_redraw()
	if _bridge_layer != null and is_instance_valid(_bridge_layer):
		# On the circle there is never a deck mark, so the second canvas item never needs touching — except
		# on the one frame after its last mark retires, which is what `_bridge_last_count` catches.
		var n := _layer_count[LAYER_BRIDGE]
		if n > 0 or _bridge_last_count > 0:
			_bridge_layer.queue_redraw()
		_bridge_last_count = n


func _is_finite(v: Vector2) -> bool:
	return is_finite(v.x) and is_finite(v.y)


## Side-effect-free point-in-deck test. Falls back to "yes" (the old car-level behaviour) when no probe has
## been supplied, so a hand-built SkidMarks without a Track behaves exactly as it did.
func _point_on_deck(p: Vector2) -> bool:
	if not _deck_probe.is_valid():
		return true
	return bool(_deck_probe.call(p))


## Binds the point-in-deck query (see [member _deck_probe]). Pass an empty Callable to clear it.
func set_deck_probe(probe: Callable) -> void:
	_deck_probe = probe
