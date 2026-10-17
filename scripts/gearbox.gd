class_name Gearbox
extends RefCounted
## Simple automatic gearbox: gear, engine rpm, shift events (SPEC 18.3).
##
## Pure logic: no scene tree, no [Car] reference, no clock. It is fed road speed, throttle and a hold
## flag once per physics frame and owns nothing else, so it is trivially testable and bit-deterministic.
##
## The model is a real one, not a label: each gear is a ratio expressed as the road speed at which it
## reaches [constant REDLINE_RPM], rpm is computed from road speed through that ratio, and the shifts
## use both rpm hysteresis ([constant SHIFT_UP_RPM] / [constant SHIFT_DOWN_RPM]) and a directional dwell
## ([constant SHIFT_LOCK_TIME] against a reversal, [constant SHIFT_CHAIN_TIME] to keep walking the same
## way) so the gear can never flutter at a threshold and still keeps up with a hard launch.
##
## It does NOT modulate torque (SPEC decision 29.5): [member Car.acceleration] is untouched and the rope
## feel is exactly what it was. This is a real gearbox driven by the car, not a gearbox driving the car.

## Emitted once per gear change, including the drops to [constant NEUTRAL] / [constant REVERSE].
signal gear_changed(from_gear: int, to_gear: int)
## Edge-triggered: fired when the rpm crosses [constant REDLINE_RPM] upward. Re-armed only after the
## rpm falls below `REDLINE_RPM - REDLINE_REARM`, so a car sitting on the limiter fires once.
signal redline(rpm: float)

const REVERSE := -1
const NEUTRAL := 0
const TOP_GEAR := 6

## Road speed (px/s) at which each gear reaches [constant REDLINE_RPM]. Index 0 is gear 1.
##
## RETUNED (fixer round 1, decision 30.1). The first table spread six gears over 0..`Car.max_speed`
## (580 px/s) and put the last two entirely above the speed the game is actually played at: measured over
## one careful lap of each of the eight tracks the box reached **gear 4 and no higher**, and the rev bar
## never crossed the redline on ANY track even under maximum attack, because gear 6 topped out exactly at
## `max_speed` and tyre slip keeps `velocity.dot(heading)` a few px/s under it — so the "redline zone that
## lights up" was unreachable art.
##
## The ratios now span the band the game lives in (150-350 px/s is three gears with two shift points in
## it) and gear 6 tops out at 460 px/s, BELOW `max_speed`: a car that gets a long straight genuinely runs
## into the limiter and the red zone lights. This is an instrument-only change — [Gearbox] does not touch
## torque (decision 29.5) — so lap times are bit-identical.
## Gear 1 is 95, not 80: with SHIFT_DOWN_RPM at 4200 the hysteresis only survives while a gear's top
## speed is under ~1.53x the one below it, and 135/80 = 1.69 put gear 1's upshift point and gear 2's
## downshift point on the same 76 px/s. The ratios above gear 1 are all 1.33-1.44.
const GEAR_TOP_SPEED := [95.0, 135.0, 195.0, 260.0, 345.0, 460.0]

const IDLE_RPM := 900.0
## Lowered 7200 -> 6800 with the ratios above, so the red zone is 3 of the rev bar's 24 segments
## (`REDLINE_RPM / MAX_RPM` = 0.872) instead of the single, permanently unlit segment it used to be.
const REDLINE_RPM := 6800.0
const MAX_RPM := 7800.0
## Just under the redline: an ordinary upshift does not sit on the limiter, but gear 6 (which cannot
## upshift) runs past it on a long straight, which is the only place the red zone is meant to light.
const SHIFT_UP_RPM := 6500.0
## RAISED 3100 -> 4200 with the ratios above (decision 30.1). At 3100 the downshift speeds were so far
## below the upshift speeds that the box latched in whatever gear it had reached: gear 6 held all the way
## down to 171 px/s, so a careful lap sat in top the whole way round and the readout was as static as it
## was before, only one number higher. At 4200 gear 6 gives way at 257 px/s and gear 5 at 193, which puts
## two or three real shift points inside the 150-350 px/s band a careful lap lives in.
const SHIFT_DOWN_RPM := 4200.0
## s of dwell before a shift in the OPPOSITE direction to the last one -- i.e. before the only thing
## that can flutter. It bounds the up-down-up rate at 4/s no matter what the input does.
const SHIFT_LOCK_TIME := 0.25
## s of dwell before another shift in the SAME direction (a launch walking up the box). It has to be
## shorter than the reversal lock: this car goes 0 -> max_speed in 1.12 s and its five upshift speeds
## are 0.155-0.18 s apart, so a flat 0.25 s dwell would leave the engine sitting on the limiter in
## third all the way down the first straight. Flutter needs a reversal, so shortening this costs
## nothing: the 0.25 s guarantee still covers every direction change.
const SHIFT_CHAIN_TIME := 0.10
## s the dashboard flashes the new gear.
const SHIFT_FLASH_TIME := 0.18
## px/s below which a coasting car with no throttle sits in N (and below whose negative it is in R).
const NEUTRAL_SPEED := 12.0
## rpm below REDLINE_RPM the `redline` signal re-arms.
const REDLINE_REARM := 200.0
## Throttle demand that counts as "the driver is asking for drive" when picking a gear out of N/R.
const ENGAGE_THROTTLE := 0.05

## Current gear: [constant REVERSE], [constant NEUTRAL], or 1..[constant TOP_GEAR].
var gear: int = NEUTRAL
## Engine speed in rpm, always inside `[IDLE_RPM, MAX_RPM]`.
var rpm: float = IDLE_RPM

var _since_shift: float = 999.0
var _last_dir: int = 0
var _flash_left: float = 0.0
var _flash_dir: int = 0
var _redline_armed: bool = true


## One physics frame. `forward_speed` is the car's speed ALONG ITS HEADING in px/s (signed: negative
## after a barrier bounce), `throttle` is 0..1, `held` is true while the car is locked, mid-rollover or
## the race has not started.
func update(delta: float, forward_speed: float, throttle: float, held: bool) -> void:
	delta = maxf(delta, 0.0)
	if not is_finite(forward_speed):
		forward_speed = 0.0
	if not is_finite(throttle):
		throttle = 0.0
	throttle = clampf(throttle, 0.0, 1.0)

	_since_shift = minf(_since_shift + delta, 999.0)
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		if _flash_left == 0.0:
			_flash_dir = 0

	# Held: clutch out. Neutral, idle, no dwell -- the first frame after the release may shift.
	if held:
		_since_shift = 999.0
		_last_dir = 0
		_set_gear(NEUTRAL)
		# Snapped, not filtered: a held car must be frozen (SPEC test 29 models pause as `Car.lock()`
		# and asserts the gear and rpm do not change while it is held).
		rpm = IDLE_RPM
		_update_redline()
		return

	# The gear the box wants this frame. Changes are always +-1, so no gear can ever be skipped; a
	# change that REVERSES the last one waits SHIFT_LOCK_TIME (that is the only thing that can flutter),
	# one that continues it waits SHIFT_CHAIN_TIME.
	var want := gear
	if forward_speed < -NEUTRAL_SPEED:
		want = REVERSE
	elif absf(forward_speed) < NEUTRAL_SPEED and throttle < ENGAGE_THROTTLE:
		want = NEUTRAL
	elif gear <= NEUTRAL:
		want = 1
	else:
		var r := rpm_for(gear, forward_speed)
		if r >= SHIFT_UP_RPM and gear < TOP_GEAR:
			want = gear + 1
		elif r <= SHIFT_DOWN_RPM and gear > 1:
			want = gear - 1

	if want != gear:
		var dir := 1 if want > gear else -1
		var dwell := SHIFT_CHAIN_TIME if dir == _last_dir else SHIFT_LOCK_TIME
		if _since_shift >= dwell:
			_set_gear(want)

	rpm = rpm_for(gear, forward_speed)
	_update_redline()


## Engine rpm gear `g` would read at road speed `speed` (px/s). N idles; R uses gear 1's ratio on the
## magnitude of the speed. Always clamped to `[IDLE_RPM, MAX_RPM]`, for any input.
func rpm_for(g: int, speed: float) -> float:
	if g == NEUTRAL:
		return IDLE_RPM
	if not is_finite(speed):
		return IDLE_RPM
	var idx := 0 if g == REVERSE else clampi(g, 1, TOP_GEAR) - 1
	var top: float = GEAR_TOP_SPEED[idx]
	if top <= 0.0:
		return IDLE_RPM
	return clampf(IDLE_RPM + (absf(speed) / top) * (REDLINE_RPM - IDLE_RPM), IDLE_RPM, MAX_RPM)


## Road speed (px/s) at which gear `g` reaches `target_rpm` -- the arithmetic behind the shift table of
## SPEC 18.3, exposed so the tests can assert the shift points instead of hunting for them.
func speed_for_rpm(g: int, target_rpm: float) -> float:
	if g == NEUTRAL:
		return 0.0
	var idx := 0 if g == REVERSE else clampi(g, 1, TOP_GEAR) - 1
	var top: float = GEAR_TOP_SPEED[idx]
	return clampf((target_rpm - IDLE_RPM) / (REDLINE_RPM - IDLE_RPM), 0.0, 1.0) * top


## Road speed (px/s) at which gear `g` upshifts (g < TOP_GEAR), for the tests and the README table.
func upshift_speed(g: int) -> float:
	return speed_for_rpm(g, SHIFT_UP_RPM)


## Road speed (px/s) at which gear `g` downshifts to `g - 1` (g > 1).
func downshift_speed(g: int) -> float:
	return speed_for_rpm(g, SHIFT_DOWN_RPM)


## rpm as a 0..1 fraction of [constant MAX_RPM] -- the rev bar's fill.
func get_rpm_fraction() -> float:
	return clampf(rpm / MAX_RPM, 0.0, 1.0)


## Where the red zone starts on that bar: `REDLINE_RPM / MAX_RPM` == 0.923.
func get_redline_fraction() -> float:
	return REDLINE_RPM / MAX_RPM


func is_redlining() -> bool:
	return rpm >= REDLINE_RPM


## "R", "N" or "1".."6".
func gear_text() -> String:
	if gear == REVERSE:
		return "R"
	if gear == NEUTRAL:
		return "N"
	return str(gear)


## 1 -> 0 over [constant SHIFT_FLASH_TIME] after a gear change; 0 when no shift is fresh.
func get_shift_flash() -> float:
	return clampf(_flash_left / SHIFT_FLASH_TIME, 0.0, 1.0)


## +1 up, -1 down, 0 none. Valid while [method get_shift_flash] is above zero.
func get_shift_direction() -> int:
	return _flash_dir if _flash_left > 0.0 else 0


## s left before a shift REVERSING the last one is allowed (0 == a reversal is allowed this frame).
## This is the anti-flutter dwell; a further shift the same way needs only [constant SHIFT_CHAIN_TIME].
func get_shift_lock() -> float:
	return maxf(SHIFT_LOCK_TIME - _since_shift, 0.0)


## s since the last gear change.
func get_time_since_shift() -> float:
	return _since_shift


func reset() -> void:
	gear = NEUTRAL
	rpm = IDLE_RPM
	_since_shift = 999.0
	_last_dir = 0
	_flash_left = 0.0
	_flash_dir = 0
	_redline_armed = true


func _set_gear(g: int) -> void:
	if g == gear:
		return
	var from := gear
	gear = g
	_since_shift = 0.0
	_last_dir = 1 if g > from else -1
	_flash_dir = _last_dir
	_flash_left = SHIFT_FLASH_TIME
	gear_changed.emit(from, g)


func _update_redline() -> void:
	if rpm >= REDLINE_RPM:
		if _redline_armed:
			_redline_armed = false
			redline.emit(rpm)
	elif rpm < REDLINE_RPM - REDLINE_REARM:
		_redline_armed = true
