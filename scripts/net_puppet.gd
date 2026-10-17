class_name NetPuppet
extends RefCounted
## Smooths a remote car (one this machine does not simulate) between the state packets its owner sends
## ~30 times a second (Net.SEND_EVERY).
##
## A packet carries the SENDER's clock as its last element (Net.send_car_state appends it), so the
## timeline the puppet interpolates on is the sender's: network jitter changes when a packet ARRIVES,
## never where the car IS. The receiver's clock is mapped onto the sender's by a slowly-adapting minimum
## of (arrival - sent); the car is drawn DELAY behind the newest moment it can be sure of (about three
## send intervals, more for a while after a packet turned up late); and the pose it draws eases toward
## the interpolated one with a short time constant, so a packet boundary never shows as a kink. The
## delay and the clock offset are applied through a slewed lag, so the drawn timeline never runs
## backwards (a late packet slows the car for a moment instead of jerking it back). If the packets stop
## it coasts on the last velocity for a moment, then holds.
##
## A packet without the stamp (an older sender) is timed by its arrival, INTERP_DELAY behind, as before.

const INTERP_DELAY := 0.1          # s behind the newest packet, for unstamped packets
const MAX_EXTRAPOLATE := 0.25      # s of coasting when packets stop
const BUFFER := 24                 # packets kept: 0.8 s at 30 Hz, more than DELAY_MAX plus the offset
## SPEC 128: the sender's `Time.get_ticks_msec()`, appended by `Net.send_car_state()` AFTER the car's
## own fields. Derived from `Car.NET_FIELDS` rather than written out, because the last time it was
## written out the car grew a field and this did not: the puppet spent a release reading the body's
## damage bits as the clock.
const STAMP_INDEX := Car.NET_FIELDS
const DELAY_MIN := 0.12            # s behind the sender's clock: ~3.6 packets at 30 Hz
const DELAY_MAX := 0.5
const DELAY_MARGIN := 0.02         # s on top of a late packet's lateness when the delay grows
const DELAY_DECAY := 0.01          # s of delay given back per second while packets are on time
const OFFSET_CREEP := 0.02         # how fast the clock offset drifts up toward a slower packet
const LAG_SLEW := 0.25             # s per s the applied lag may change: time runs at 0.75x - 1.25x
const SMOOTH_TAU := 0.04           # s: the drawn pose eases toward the interpolated one
const SNAP_DISTANCE := 160.0       # px: farther than this is a respawn -- jump, do not glide

var _times: PackedFloat64Array = PackedFloat64Array()   # the sender's clock when stamped, else arrival
var _states: Array = []
var _stamped := false
var _offset := 0.0                 # receiver clock - sender clock (s), tracked at its minimum
var _has_offset := false
var _delay := DELAY_MIN
var _lag := 0.0                    # the offset + delay in use, slewed toward the wanted one
var _lag_set := false
var _last_now := 0.0
var _last_t := -INF                # the timeline moment last drawn (a packet older than it was late)
var _out_pos := Vector2.ZERO
var _out_head := 0.0
var _out_set := false
## Packets that arrived after the moment they describe had been drawn (for tests and the overlay).
var late_packets: int = 0


## SPEC 128: the sender's clock on the newest packet, in seconds (0 when none has carried one). Public
## so a test can prove that what the producer stamped is what the consumer read -- the defect this
## exists to catch was that the two disagreed about WHERE in the packet the stamp was, and every number
## downstream of it looked plausible.
func newest_sent() -> float:
	return _times[_times.size() - 1] if _stamped and not _times.is_empty() else 0.0


func push(state: Array, now: float) -> void:
	var t := now
	if state.size() > STAMP_INDEX and (state[STAMP_INDEX] is float or state[STAMP_INDEX] is int):
		var sent := float(state[STAMP_INDEX]) / 1000.0
		var off := now - sent
		if not _has_offset or off < _offset:
			_offset = off                 # a faster packet: the clocks are at most this far apart
			_has_offset = true
		else:
			_offset += (off - _offset) * OFFSET_CREEP
		_stamped = true
		t = sent
		if _lag_set and t <= _last_t:
			# It was needed already: draw far enough behind that it would have been on time (the lag
			# slews there, forward only). A burst of late packets asks for its worst one, not their sum.
			late_packets += 1
			var needed := (_lag - _offset) + (_last_t - t) + DELAY_MARGIN
			_delay = clampf(maxf(_delay, needed), DELAY_MIN, DELAY_MAX)
	if not _times.is_empty() and t < _times[_times.size() - 1]:
		return                            # older than what we have: the newer packet is the truth
	_times.append(t)
	_states.append(state)
	while _states.size() > BUFFER:
		_times.remove_at(0)
		_states.remove_at(0)


func has_state() -> bool:
	return not _states.is_empty()


func latest() -> Array:
	return _states[_states.size() - 1] if not _states.is_empty() else []


## How far behind the sender's clock the car is drawn (s), for the overlay.
func delay() -> float:
	return _delay if _stamped else INTERP_DELAY


## [pos: Vector2, heading: float, state: Array] for time `now`, or [] before the first packet. Call it
## once per frame with the receiver's clock: the smoothing and the lag slew step forward by the time
## since the last call.
func sample(now: float) -> Array:
	var n := _states.size()
	if n == 0:
		return []
	var dt := 0.0
	var want := (_offset + _delay) if _stamped else INTERP_DELAY
	if not _lag_set:
		_lag = want
		_lag_set = true
	else:
		dt = maxf(now - _last_now, 0.0)
		if _stamped:
			_delay = maxf(_delay - DELAY_DECAY * dt, DELAY_MIN)
			want = _offset + _delay
		_lag = move_toward(_lag, want, LAG_SLEW * dt)
	_last_now = now
	var t := now - _lag
	_last_t = t
	var target := _at(t)
	var pos: Vector2 = target[0]
	var head: float = target[1]
	if not _out_set or pos.distance_squared_to(_out_pos) > SNAP_DISTANCE * SNAP_DISTANCE:
		_out_pos = pos
		_out_head = wrapf(head, -PI, PI)
		_out_set = true
	elif dt > 0.0:
		var k := 1.0 - exp(-dt / SMOOTH_TAU)
		_out_pos = _out_pos.lerp(pos, k)
		_out_head = wrapf(_out_head + wrapf(head - _out_head, -PI, PI) * k, -PI, PI)
	return [_out_pos, _out_head, target[2]]


## The pose on the timeline at `t`: between the two packets around it, the first packet before any, a
## coast on the last velocity (at most MAX_EXTRAPOLATE) past the newest.
func _at(t: float) -> Array:
	var n := _states.size()
	for i in range(n - 1, 0, -1):
		if _times[i - 1] <= t and t <= _times[i]:
			var a: Array = _states[i - 1]
			var b: Array = _states[i]
			var span := maxf(_times[i] - _times[i - 1], 0.0001)
			var f := clampf((t - _times[i - 1]) / span, 0.0, 1.0)
			var pa := Vector2(float(a[0]), float(a[1]))
			var pb := Vector2(float(b[0]), float(b[1]))
			var ha := float(a[2])
			var hb := float(b[2])
			return [pa.lerp(pb, f), ha + wrapf(hb - ha, -PI, PI) * f, b]
	if t < _times[0]:
		var first: Array = _states[0]
		return [Vector2(float(first[0]), float(first[1])), float(first[2]), first]
	var last: Array = _states[n - 1]
	var pos := Vector2(float(last[0]), float(last[1]))
	var ahead := clampf(t - _times[n - 1], 0.0, MAX_EXTRAPOLATE)
	return [pos + Vector2(float(last[3]), float(last[4])) * ahead, float(last[2]) + float(last[5]) * ahead, last]
