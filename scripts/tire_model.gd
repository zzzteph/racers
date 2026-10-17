class_name TireModel
extends RefCounted
## One wheel's tire force, evaluated once per sub-step (SPEC 7.5).
##
## Simplified Magic Formula: `F_lat = -D * sin(C * atan(B * alpha))`. It rises linearly with slope `C`,
## peaks at `alpha_peak = 1.85 / B` and then falls away — that post-peak falloff is the breakaway that
## makes the car drift instead of merely understeering.
##
## Pure maths: no state that survives a call, no allocation, no randomness. Every division is guarded and
## every result is finite, including at zero speed, zero slip, zero load and `dt == 0`.
##
## **Reversed contact patches are deliberately treated as forward.** `alpha` uses `absf(v_fwd)`, so a wheel
## rolling backwards makes the same (damping) force it would make rolling forwards. A textbook tire would
## flip the sign there and become unstable; this model reaches genuinely reversed patches in a big drift
## (body slip angles past 90 deg are reachable), and the stable branch is what keeps the slide recoverable.
## Pinned by a degenerate-input test (SPEC 7.5).

const STATIC_LOAD := 0.25

# --- tuning (mirrored from Car's exports once per physics_step) ---
var peak_accel: float = 950.0          # px/s^2 total peak lateral force of all four wheels
var cornering_stiffness: float = 9000.0  # px/s^2 per rad, total at nominal load
var shape_c: float = 1.45              # falloff after the peak
var load_exponent: float = 0.85        # < 1 => load sensitivity (a doubly loaded tire is not twice as good)
var long_mu_ratio: float = 1.45        # longitudinal capacity relative to the lateral peak
var slip_epsilon: float = 30.0         # px/s, low-speed slip-angle guard
var slide_threshold: float = 0.90      # saturation at which the patch counts as sliding
var slide_min_speed: float = 35.0      # px/s of patch slide needed with it
## Fraction of the longitudinal capacity at which the contact patch starts to slip along the wheel. Below
## it the tire rolls (no mark, no smoke); above it the reported `slip_speed` grows toward a locked /
## spinning wheel. Without this the longitudinal axis produced NO patch slide at all, so hard braking and
## wheelspin — two of the four cases the user asked to see marks for — could never leave one.
var long_slip_start: float = 0.88
## How much of the forward speed a fully slipping patch reports as slide (a locked wheel would be 1.0;
## 0.45 keeps a brake lock-up comparable with a hard lateral scrub rather than dwarfing it).
var long_slip_weight: float = 0.45


## Solves one wheel and writes the six result fields into `out` (a reused Dictionary, never reallocated).
##   v_fwd/v_lat  contact-patch velocity in the *wheel's* frame (px/s)
##   load         normalized load of this wheel (the four sum to 1.0); STATIC_LOAD == nominal
##   mu           surface / speed / brake grip multiplier
##   long_demand  wanted longitudinal acceleration share for this wheel (px/s^2, signed)
##   dt           sub-step length, for the explicit-integration guard
##   speed_cap    max_speed, used only to bound the reported slip speed
func solve(out: Dictionary, v_fwd: float, v_lat: float, load: float, mu: float,
		long_demand: float, dt: float, speed_cap: float) -> void:
	var lf := pow(maxf(load, 0.0) / STATIC_LOAD, load_exponent)
	var m := maxf(mu, 0.0)
	var d := maxf(peak_accel, 0.0) * STATIC_LOAD * lf * m          # peak lateral force of this wheel
	var c := maxf(cornering_stiffness, 0.0) * STATIC_LOAD * lf * m  # cornering stiffness of this wheel
	var shape := maxf(shape_c, 0.1)
	var b := c / maxf(d * shape, 0.001)

	# Slip angle. `slip_epsilon` in the denominator is the whole low-speed singularity guard: at standstill
	# alpha stays small and the force goes to zero with v_lat, so a parked car neither spins nor jitters.
	var alpha := atan2(v_lat, maxf(absf(v_fwd), maxf(slip_epsilon, 0.001)))
	var f_lat := -d * sin(shape * atan(b * alpha))

	# Longitudinal first (friction circle with longitudinal priority): braking is the player's only way of
	# slowing down, so no amount of cornering may take it away.
	var p_long := maxf(d * maxf(long_mu_ratio, 0.01), 0.001)
	var f_long := clampf(long_demand, -p_long, p_long)
	var used_long := absf(f_long) / p_long
	var lat_budget := d * sqrt(maxf(0.0, 1.0 - used_long * used_long))
	f_lat = clampf(f_lat, -lat_budget, lat_budget)

	# Explicit-integration guard: four wheels may remove at most 90 % of the lateral velocity in one
	# sub-step, whatever `cornering_stiffness` is. No overshoot, no ringing, no NaN.
	var lat_cap := absf(v_lat) * 0.9 / maxf(dt, 0.000001) * STATIC_LOAD
	f_lat = clampf(f_lat, -lat_cap, lat_cap)

	var alpha_peak := 1.85 / maxf(b, 0.001)
	var lat_sat := absf(alpha) / maxf(alpha_peak, 0.02)
	var long_sat := absf(long_demand) / p_long
	# Longitudinal patch slide. The old `excess` term was `max(0, |demand| - P_long)`, which is structurally
	# zero whenever the longitudinal capacity is above the brake/drive demand — i.e. always — so braking and
	# wheelspin reported a slip speed of exactly 0. A real tire already slides before it locks: the slide
	# grows from `long_slip_start` of capacity and keeps growing past it when the demand is clipped.
	var long_slip := clampf((long_sat - long_slip_start) / maxf(1.0 - long_slip_start, 0.01), 0.0, 1.6)
	var slip_spd := absf(v_lat) \
			+ long_slip * long_slip_weight * clampf(absf(v_fwd), 0.0, maxf(speed_cap, 0.0))
	var sat := sqrt(lat_sat * lat_sat + long_sat * long_sat)

	out["slip_angle"] = alpha
	out["lat_force"] = f_lat
	out["long_force"] = f_long
	out["saturation"] = sat
	## Lateral-only saturation. `saturation` mixes in the brake/drive demand, so it is high whenever the
	## player is hard on the throttle even with the car dead straight; the drift release and the drift
	## detector must react to the rear tires *sliding sideways*, which is this number.
	out["lat_saturation"] = lat_sat
	out["long_saturation"] = long_sat
	out["slip_speed"] = slip_spd
	out["is_sliding"] = sat >= slide_threshold and slip_spd >= slide_min_speed


## Peak lateral force available to one wheel at this load / mu (px/s^2). Used by diagnostics and tests.
func peak_lateral(load: float, mu: float) -> float:
	var lf := pow(maxf(load, 0.0) / STATIC_LOAD, load_exponent)
	return maxf(peak_accel, 0.0) * STATIC_LOAD * lf * maxf(mu, 0.0)


## Slip angle (rad) at which this wheel makes its peak lateral force.
func peak_slip_angle() -> float:
	var shape := maxf(shape_c, 0.1)
	var b := maxf(cornering_stiffness, 0.0) / maxf(maxf(peak_accel, 0.001) * shape, 0.001)
	return 1.85 / maxf(b, 0.001)
