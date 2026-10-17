class_name Suspension
extends RefCounted
## Four-corner spring-damper (SPEC 7.4). FL, FR, RL, RR.
##
## Weight transfer sets a target compression per corner; a spring-damper chases it, and the resulting
## compressions are renormalized into per-wheel loads that **always sum to exactly 1.0**. Renormalizing is
## deliberate: it makes the car's *total* grip independent of suspension tuning (so no suspension tweak can
## break the difficulty pins) while still moving grip between the wheels. The grip genuinely lost in a
## corner comes from the tire's load sensitivity instead (TireModel.load_exponent).
##
## Deterministic, allocation-free after construction, and finite for any input.

const STATIC_LOAD := 0.25
const WHEELS := 4

# --- tuning (mirrored from Car's exports once per physics_step) ---
var rest: float = 6.0          # px of compression at static load
var max_travel: float = 14.0   # px, bump stop
var stiffness: float = 260.0   # 1/s^2 (~2.6 Hz)
var damping: float = 18.0      # 1/s (zeta ~0.56)

# --- state ---
var compression := PackedFloat32Array()
var comp_vel := PackedFloat32Array()
var load := PackedFloat32Array()
var tilt: float = 0.0    # (left load - right load), -1..1; + = loaded on the car's LEFT
var pitch: float = 0.0   # (front load - rear load), -1..1; + = nose down / braking
## The same two numbers computed from the loads **before** the two-wheels `lift` is applied. The lift is
## part of the consequence of being on two wheels, not evidence for it: judging the rollover state machine
## on the lifted split makes `TWO_WHEELS` self-sustaining (the lift alone pins the tilt at >= 0.85), so the
## state could never be driven out of. The machine reads these; the tire curve and the visuals read the
## lifted `tilt` / `pitch` / `load`.
var tilt_raw: float = 0.0
var pitch_raw: float = 0.0

# Scratch buffers, sized once: `step()` allocates nothing.
var _target := PackedFloat32Array()
var _raw := PackedFloat32Array()
var _bare := PackedFloat32Array()   # the same loads without the two-wheels lift


func _init() -> void:
	compression.resize(WHEELS)
	comp_vel.resize(WHEELS)
	load.resize(WHEELS)
	_target.resize(WHEELS)
	_raw.resize(WHEELS)
	_bare.resize(WHEELS)
	reset()


## Back to the static ride height with no motion and four equal loads.
func reset() -> void:
	for i in WHEELS:
		compression[i] = clampf(rest, 0.0, maxf(max_travel, 0.0))
		comp_vel[i] = 0.0
		load[i] = STATIC_LOAD
	tilt = 0.0
	pitch = 0.0
	tilt_raw = 0.0
	pitch_raw = 0.0


## A downward jolt: `strength` px/s added to every corner's compression rate. Because it is applied
## equally, it is visible in `compression` (the drawn suspension travel) but leaves the renormalized loads
## alone — a bump shakes the body without secretly changing the grip.
func bump(strength: float) -> void:
	if not is_finite(strength):
		return
	var s := clampf(strength, -400.0, 400.0)
	for i in WHEELS:
		comp_vel[i] += s


## One integration step. `p` = pitch transfer (-1..1, + = front loaded), `r` = roll transfer (-1..1,
## + = loaded on the car's LEFT). `lift` scales the load of a pair of wheels toward zero (two-wheels state);
## pass 1.0 for all four to disable it.
func step(dt: float, p: float, r: float, lift_left: float = 1.0, lift_right: float = 1.0) -> void:
	if not (dt > 0.0) or not is_finite(dt):
		return
	var pp := clampf(p, -1.0, 1.0)
	var rr := clampf(r, -1.0, 1.0)
	var top := maxf(max_travel, 0.001)
	var base := maxf(rest, 0.001)
	_target[0] = STATIC_LOAD * (1.0 + pp + rr)   # FL
	_target[1] = STATIC_LOAD * (1.0 + pp - rr)   # FR
	_target[2] = STATIC_LOAD * (1.0 - pp + rr)   # RL
	_target[3] = STATIC_LOAD * (1.0 - pp - rr)   # RR
	var raw_sum := 0.0
	var bare_sum := 0.0
	for i in WHEELS:
		var target_c := clampf(base * (_target[i] / STATIC_LOAD), 0.0, top)
		var accel := stiffness * (target_c - compression[i]) - damping * comp_vel[i]
		var v := comp_vel[i] + accel * dt
		var c := compression[i] + v * dt
		if c <= 0.0:
			c = 0.0
			v = 0.0
		elif c >= top:
			c = top
			v = 0.0
		comp_vel[i] = v
		compression[i] = c
		var side_lift := lift_left if (i == 0 or i == 2) else lift_right
		var bare := c / base * STATIC_LOAD
		var value := bare * maxf(side_lift, 0.0)
		_bare[i] = bare
		bare_sum += bare
		_raw[i] = value
		raw_sum += value
	if raw_sum <= 0.000001:
		for i in WHEELS:
			load[i] = STATIC_LOAD
	else:
		for i in WHEELS:
			load[i] = _raw[i] / raw_sum
	tilt = (load[0] + load[2]) - (load[1] + load[3])
	pitch = (load[0] + load[1]) - (load[2] + load[3])
	if bare_sum <= 0.000001:
		tilt_raw = 0.0
		pitch_raw = 0.0
	else:
		var inv := 1.0 / bare_sum
		tilt_raw = ((_bare[0] + _bare[2]) - (_bare[1] + _bare[3])) * inv
		pitch_raw = ((_bare[0] + _bare[1]) - (_bare[2] + _bare[3])) * inv


## Relax toward the static ride height (used while the car is locked or scripted through a rollover).
func settle(dt: float) -> void:
	step(dt, 0.0, 0.0)


## -1..1 lean of one corner, from how far that corner sits from its static ride height (for drawing).
func lean(index: int) -> float:
	if index < 0 or index >= WHEELS:
		return 0.0
	return clampf((compression[index] - rest) / maxf(rest, 0.001), -1.0, 1.0)
