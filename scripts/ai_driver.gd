class_name AIDriver
extends RefCounted
## The brain of one AI rival. It drives a normal [Car] through exactly the same input the player has --
## a rope target -- so it obeys the same physics, grip, over-pull, damage and rollovers.
##
## Each frame it:
##   1. tracks its own progress along the centerline (the Track's progress tracker belongs to the player);
##   2. follows a RACING LINE (inside at the apex, outside on entry and exit), as much of it as its
##      difficulty allows (easy drives the centerline);
##   3. reads the SPEED PROFILE: the fastest speed each point of that line can be taken at for this car
##      (sqrt(grip * radius)), with braking points worked backwards from every corner (easy leaves a big
##      margin, hard very little);
##   4. sets the rope length for that speed, pointed at a point a little way down the line;
##   5. handles traffic: a CLEAN rival steers round a car in its way and lifts if it cannot pass; an
##      AGGRESSIVE one looks for a car ALONGSIDE it that has the track edge on its far side and leans on
##      it to push it off -- but never rams a car from straight behind (that would only wreck itself) and
##      never when it would go off the road doing it.
##   6. drives it like a PERSON with a mouse (SPEC 40): the rope target is a HAND -- it reacts a moment
##      late and can only move so fast -- and it uses the rope the way players do: thrown long on the
##      straights (into the tension zone, charging and firing boosts), snapped short to brake, FLICKED
##      to the inside at a corner entry to throw the car into a drift, and, for the weaker drivers,
##      sometimes braking too late and running wide.
##
## The three levels are three different drivers, not three grip percentages:
##   easy    slow hand, brakes early, never drifts, never boosts, makes mistakes
##   medium  quicker hand, takes most of the line, drifts some corners, boosts, the odd mistake
##   hard    fast hand, the full line at the limit, drifts most corners, boosts on every straight
## Deterministic: the randomness (wander phase, which corners to drift, which to get wrong) is seeded.

const SPACING_GUESS := 16.0
const PROGRESS_WINDOW := 10
## SPEC 131: the easy and medium brake margins came down (0.45 -> 0.26, 0.60 -> 0.46) when a rope
## pointing down the road stopped being allowed to brake the car. A careful driver brakes EARLY, and
## "early" is measured against braking it can actually get; against the old figure the easy AI was
## arriving at every corner too fast and running wide half a second at a time. Hard is untouched --
## a racer brakes late on purpose, and it is the one that still has to find straights to boost on.
## Per difficulty: share of the racing line used, share of the tire grip planned for, share of the brake
## planned for, lateral wander (share of the half-width), a straight-line speed factor, and the hand:
## `react` s late, `hand` px/s at most, `drift` = chance of flicking into a drift at a corner, `mistake`
## = chance of braking too late for one, `zone` = uses the tension zone and the boost.
const LEVELS := {
	"easy": {"line": 0.3, "grip": 0.55, "brake": 0.26, "wander": 0.16, "top": 0.86,
			"react": 0.22, "hand": 1100.0, "drift": 0.0, "mistake": 0.08, "zone": false},
	"medium": {"line": 0.75, "grip": 0.70, "brake": 0.46, "wander": 0.05, "top": 0.95,
			"react": 0.12, "hand": 1900.0, "drift": 0.25, "mistake": 0.05, "zone": true},
	"hard": {"line": 1.0, "grip": 0.80, "brake": 0.72, "wander": 0.0, "top": 1.0,
			"react": 0.06, "hand": 3200.0, "drift": 0.5, "mistake": 0.03, "zone": true},
}
## PERSONALITIES (SPEC 42): what a driver TRIES to do -- the level is how well it does it. Every rival
## gets one at random.
##   risk / brake  share of the planned grip / brakes it asks for (over 1 = overdriving)
##   bang          how on/off its throttle is (1 = the cursor is either flung out or stabbed back)
##   drift         x the level's chance of drifting a corner;  mistake: x the level's mistake chance
##   kinds         the mistakes it makes: late (brakes too late), early (turns in too soon), exit (too
##                 greedy on the way out), flick (over-flicks a drift into a half-spin)
##   jitter        px of hand tremor;  lapse: attention lapses per second;  zeta: hand damping (< 1
##                 overshoots)
##   anger         how fast being passed / wrecking / leaving the road winds it up (mood)
##   push          leans on cars alongside (1 = always, > 0 = when angry);  attack / defend: race craft
##   boost         eager (the moment it can), pass (to overtake, or a long straight), straight
##   yank          how hard it yanks the car back from off the road;  panic: spooked by a car alongside
##   show          flicks the tail out on the straights;  overpull: flings the rope past the zone
##   top           (optional) share of the top speed it dares on a straight -- a rookie lifts
##   nerve / crack SPEC 143: seconds with a car on its tail before it is fully PRESSURED, and how many
##                 times its mistake chance is multiplied at full pressure -- a rookie cracks, a pro does not
##   big           SPEC 145: the share of its mistakes that are BIG ONES -- thrown into the corner flat out
##                 with the rope flung to the inside, which is a roll or a wall if the physics says so, and
##                 then a wreck (an INCIDENT: the race throws a caution). A pro never has one.
const PERSONALITIES := {
	"pro": {"risk": 1.0, "brake": 1.0, "bang": 0.15, "drift": 0.3, "mistake": 0.4, "kinds": ["late", "early"],
			"jitter": 2.0, "lapse": 0.02, "zeta": 0.9, "anger": 0.3, "push": 0.0, "attack": 1.0,
			"defend": 1.0, "boost": "pass", "yank": 0.3, "panic": 0.0, "show": 0.0, "overpull": 0.0,
			"nerve": 12.0, "crack": 0.8, "big": 0.0},
	"hothead": {"risk": 1.08, "brake": 1.12, "bang": 0.75, "drift": 1.0, "mistake": 1.0,
			"kinds": ["late", "exit", "flick", "late"], "jitter": 3.0, "lapse": 0.02, "zeta": 0.65,
			"anger": 1.2, "push": 0.3, "attack": 1.3, "defend": 0.6, "boost": "eager", "yank": 0.8,
			"panic": 0.0, "show": 0.0, "overpull": 1.0, "nerve": 5.0, "crack": 2.5, "big": 0.25},
	"drifter": {"risk": 1.0, "brake": 1.0, "bang": 0.55, "drift": 1.7, "mistake": 0.7, "kinds": ["flick", "exit"],
			"jitter": 2.5, "lapse": 0.02, "zeta": 0.7, "anger": 0.6, "push": 0.0, "attack": 0.8,
			"defend": 0.3, "boost": "straight", "yank": 0.6, "panic": 0.0, "show": 0.3, "overpull": 0.1,
			"nerve": 7.0, "crack": 2.5, "big": 0.12},
	"bully": {"risk": 1.03, "brake": 1.05, "bang": 0.55, "drift": 0.7, "mistake": 0.8,
			"kinds": ["late", "early", "exit"], "jitter": 2.0, "lapse": 0.02, "zeta": 0.75, "anger": 1.0,
			"push": 1.0, "attack": 1.3, "defend": 1.5, "boost": "pass", "yank": 0.8, "panic": 0.0,
			"show": 0.0, "overpull": 0.3, "nerve": 8.0, "crack": 1.6, "big": 0.1},
	"rookie": {"risk": 0.8, "brake": 0.7, "top": 0.92, "bang": 0.25, "drift": 0.2, "mistake": 1.6,
			"kinds": ["early", "late", "exit"], "jitter": 6.0, "lapse": 0.08, "zeta": 0.6, "anger": 0.6,
			"push": 0.0, "attack": 0.3, "defend": 0.0, "boost": "straight", "yank": 0.25, "panic": 0.5,
			"show": 0.0, "overpull": 0.5, "nerve": 3.0, "crack": 5.0, "big": 0.15},
}
## SPEC 143: what each one DOES, in a line, told to the player on the grid ("see exactly what you are
## up against"). Every line is a mechanic above, not a flavour: a rookie's nerve is 3 s, a bully's
## push is 1, a pro's crack is 1.5.
const PERSONALITY_TELLS := {
	"pro": "clean and quick, hard to rattle -- it has to be out-driven",
	"hothead": "fast and angry -- over-drives its corners, worse the more you lean on it",
	"drifter": "sideways into every corner, slow out of them -- pass it on the exits",
	"bully": "leans on you at the road edge and blocks the inside -- give it room",
	"rookie": "nervous -- sit on its tail for a few seconds and it cracks",
	"wildcard": "changes its mind every twenty seconds -- expect anything",
}
const PERSONALITY_NAMES := {"pro": "Pro", "hothead": "Hothead", "drifter": "Drifter", "bully": "Bully",
		"rookie": "Rookie", "wildcard": "Wildcard"}
## Every personality a rival can be dealt ("wildcard" switches between the moods below every 12-22 s).
const ALL_PERSONALITIES := ["pro", "hothead", "drifter", "bully", "rookie", "wildcard"]
const WILDCARD_MOODS := ["hothead", "pro", "drifter", "rookie"]
## The old style names still found in saved settings / lobbies.
const ALIASES := {"clean": "pro", "aggressive": "bully"}
const HAND_STIFFNESS := 60.0      # the hand spring's natural frequency is hand px/s / this (rad/s)
const LAPSE_TIME := 0.3
const MOOD_OVERDRIVE := 0.05      # share of extra speed asked of every corner at full mood
const MOOD_DECAY := 0.04          # per second
const MOOD_DECAY_LEADING := 0.1
const EXIT_TIME := 0.6            # s a greedy exit keeps the throttle pinned and runs wide
const OVERPULL_RATE := 0.05       # per second flat out (x personality x level)
const OVERPULL_TIME := 0.6
const OVERFLICK := 1.9            # an over-flick swings this much further than a drift flick
const SHOW_ANGLE := 0.3
const SHOW_TIME := 0.16
const PANIC_TIME := 0.35
## What a player is told about each level (the track screen).
const LEVEL_TEXT := {
	"easy": "Easy: a careful driver -- brakes early, never drifts or boosts, and runs wide now and then.",
	"medium": "Medium: a decent driver -- most of the racing line, drifts some corners, uses the boost.",
	"hard": "Hard: a racer -- late on the brakes, drifts into most corners, boosts on every straight.",
}
## How readily a driver throws each car sideways: a Sport or a Rally car is made to be drifted, a Formula
## is not (it grips, and a slide only costs it time).
const DRIFT_HABIT := {"sport": 1.0, "rally": 1.0, "kart": 0.6, "gt": 0.25, "f1": 0.15}
const FLICK_TIME := 0.22          # s the cursor is flicked to the inside to throw the car into a drift
const FLICK_ANGLE := 0.55         # rad the flick swings the rope toward the inside of the corner
const DRIFT_ENTRY_SPEED := 0.93   # a corner taken sideways is entered this much slower
const DRIFT_TURN_IN := 8          # points before the apex where the flick goes in
const MISTAKE_OVERSPEED := 1.22   # a braking mistake arrives this much too fast
const HAND_HISTORY := 32          # frames of aim the reaction delay can look back over
const EDGE_MARGIN := 20.0         # px the line keeps from the road edge (car half-width + a little)
const LOOKAHEAD_MIN := 44.0
const LOOKAHEAD_GAIN := 0.30      # s of travel the steering point sits ahead
const TRAFFIC_AHEAD := 95.0       # px ahead a car counts as "in the way"
const TRAFFIC_SIDE := 26.0        # px either side of our path
const AGGRO_RANGE := 60.0         # px: an aggressor only leans on cars this close
const STUCK_SPEED := 18.0
const STUCK_TIME := 1.4
const TAIL_PX := 75.0             # SPEC 143: a car this close behind, roughly in line, is pressure
const TAIL_SIDE := 36.0
const PRESSURE_RELIEF := 3.0      # s of clear air that lets full pressure off
const MISTAKE_CAP := 0.45         # a corner is never more likely wrong than this, whoever is behind
## SPEC 145: a BIG ONE. The flick goes in BIG_FLICK times a drift flick (an over-flick is 1.9) and for
## BIG_FLICK_TIME of a normal one, with the car arriving BIG_OVERSPEED too fast -- a car thrown
## sideways at 400 px/s across the edge of the road trips (SPEC 110's rollover) or finds something
## solid. For BIG_WINDOW s after the flick the driver is "in a big one": a roll or a hard hit in that
## window is the incident. If it only ran wide, it was a near miss, and nothing comes of it.
const BIG_FLICK := 2.2
const BIG_FLICK_TIME := 1.7
const BIG_OVERSPEED := 1.5
const BIG_WINDOW := 2.5

var car: Car = null
var track: Track = null
var difficulty: String = "medium"
var profile: String = "clean"
var progress: int = 0
var lap_tracker: LapTracker = null
var name: String = "Rival"

var _line: PackedVector2Array = PackedVector2Array()
var _offset: PackedFloat32Array = PackedFloat32Array()
var _normal: PackedVector2Array = PackedVector2Array()
var _speed: PackedFloat32Array = PackedFloat32Array()
var _corner: PackedFloat32Array = PackedFloat32Array()   # px/s the grip allows at each point (no top-speed cap)
var _distance: float = 0.0
var _time: float = 0.0
var _phase: float = 0.0
var _stuck: float = 0.0
var _side_shift: float = 0.0       # px, current traffic offset (smoothed)
var _aggro_target: Car = null
# The hand (SPEC 40).
var _rng := RandomNumberGenerator.new()
var _hand: Vector2 = Vector2.ZERO           # the cursor, relative to the car
var _hand_ready: bool = false
var _history: Array = []                    # [time, aim relative to the car]
var _apexes: PackedInt32Array = PackedInt32Array()   # slowest point of every corner
var _apex_turn: PackedFloat32Array = PackedFloat32Array()   # +1 right-hander, -1 left
var _decided_apex: int = -1
var _flick_left: float = 0.0
var _flick_dir: float = 0.0
var _mistake_apex: int = -1
var _drift_apex: int = -1
var _drifts: int = 0
var _mistakes: int = 0
# Personality and mood (SPEC 42).
var _persona: String = "pro"                # the personality driving right now (a wildcard changes it)
var _plan_risk: float = 1.0                 # the risk the line was planned with
var _mood: float = 0.0                      # 0 calm .. 1 wound up
var _place: int = 0
var _wild_left: float = 0.0
var _hand_vel: Vector2 = Vector2.ZERO
var _lapse_left: float = 0.0
var _lapse_seen: Vector2 = Vector2.ZERO
var _lapses: int = 0
var _flick_angle: float = FLICK_ANGLE
var _flick_time: float = FLICK_TIME
var _mistake_kind: String = ""
var _mistake_turn: float = 1.0
var _exit_turn: float = 1.0
var _exit_left: float = 0.0
var _overpull_left: float = 0.0
var _show_timer: float = 1.0
var _attacking: bool = false
## SPEC 143: PRESSURE. A car sitting on this driver's tail (within TAIL_PX behind, roughly in line) winds
## it up over the personality's `nerve` seconds; clear air lets it off over PRESSURE_RELIEF. Measured
## before this existed: a rival on another's tail did nothing to it -- 0 mistakes in 31 tail-seconds on
## the Circle, the lead held for 150.0 of 150 s -- so the field finished in grid order, every race.
var _pressure: float = 0.0
var _pressed: bool = false
var _cracks: int = 0                        # mistakes made at more than half pressure
var _big_left: float = 0.0                  # SPEC 145: s left of the big-one window
var _big_ones: int = 0
## SPEC 145: under a CAUTION the driver holds `caution_cap`, follows, and races nobody -- no attack, no
## defence, no leaning, no boost, no mistakes. The race sets both.
var caution: bool = false
var caution_cap: float = INF
## Probes only: every mistake roll is a big one (tools/probe_big_one.gd measures what becomes of them).
var force_big: bool = false
var _corners: int = 0                       # corners decided (the mistake / drift roll), for the probes
var _panic_left: float = 0.0
var _panic_brake: bool = false
var _panic_side: float = 1.0
var _panic_cool: float = 0.0


func setup(c: Car, t: Track, level: String, style: String, seed_value: int) -> void:
	car = c
	track = t
	difficulty = level if LEVELS.has(level) else "medium"
	profile = resolve_personality(style)
	_persona = profile if profile != "wildcard" else "pro"
	_plan_risk = float(PERSONALITIES[_persona]["risk"])
	_phase = float(seed_value % 997) * 0.731
	_rng.seed = seed_value * 7919 + 101
	_build_line()
	_find_corners()


# ---------------------------------------------------------------- progress (own copy of Track's logic)

func reset_progress(index: int) -> void:
	var n := track.get_point_count()
	progress = posmod(index, n) if n > 0 else 0
	_distance = 0.0
	_hand_ready = false
	_hand_vel = Vector2.ZERO
	_lapse_left = 0.0
	_exit_left = 0.0
	_overpull_left = 0.0
	_panic_left = 0.0
	_history.clear()
	_flick_left = 0.0
	_mistake_apex = -1
	_drift_apex = -1
	_pressure = 0.0
	_pressed = false
	_big_left = 0.0
	_mistake_kind = ""


## Windowed nearest-segment search around the last index, so the figure-8 crossing never swaps branches.
func update_progress(pos: Vector2) -> int:
	var n := track.get_point_count()
	if n < 2:
		return 0
	var best_d := INF
	var best_i := progress
	for off in range(-PROGRESS_WINDOW, PROGRESS_WINDOW + 1):
		var i := posmod(progress + off, n)
		var a := track.centerline[i]
		var b := track.centerline[(i + 1) % n]
		var q := Geometry2D.get_closest_point_to_segment(pos, a, b)
		var d := pos.distance_to(q)
		if d < best_d:
			best_d = d
			best_i = i if q.distance_to(a) <= q.distance_to(b) else (i + 1) % n
	if best_d > track.track_width * 1.5:
		# Lost (a big slide across the infield): re-attach anywhere, but only forward-ish of where we were.
		var g_best := INF
		for i in n:
			var d2 := track.centerline[i].distance_to(pos)
			var ahead := posmod(i - progress, n)
			if d2 < g_best and ahead < n / 3:
				g_best = d2
				best_i = i
				best_d = d2
	progress = best_i
	_distance = best_d
	return progress


func is_on_track() -> bool:
	return _distance <= track.track_width * 0.5


func make_on_track_provider() -> Callable:
	return func(pos: Vector2) -> bool:
		update_progress(pos)
		return is_on_track()


# ---------------------------------------------------------------- the racing line and speed profile

func _build_line() -> void:
	var n := track.get_point_count()
	var cl := track.centerline
	var lv: Dictionary = LEVELS[difficulty]
	_normal.resize(n)
	var curv := PackedFloat32Array()
	curv.resize(n)
	for i in n:
		var t := (cl[(i + 1) % n] - cl[posmod(i - 1, n)]).normalized()
		_normal[i] = Vector2(-t.y, t.x)                  # the car's RIGHT
		var d1 := cl[i] - cl[posmod(i - 3, n)]
		var d2 := cl[(i + 3) % n] - cl[i]
		var arc := maxf((d1.length() + d2.length()) * 0.5, 1.0)
		curv[i] = d1.angle_to(d2) / arc                  # > 0: right-hander
	# The racing line: a minimum-curvature path found as an elastic band. Every point is pulled toward
	# the midpoint of its neighbours (which straightens the band) but may only slide sideways, and only
	# as far as the road allows -- so it ends up wide on entry, on the apex, wide on exit, exactly where
	# the geometry says the corner is fastest. Easy uses none of it, hard all of it.
	var lim := maxf(track.track_width * 0.5 - EDGE_MARGIN, 0.0) * float(lv["line"])
	_offset = PackedFloat32Array()
	_offset.resize(n)
	var pts := cl.duplicate()
	if lim > 0.5:
		for it in 260:
			var span := 3 if it < 180 else 1
			for i in n:
				var mid := (pts[posmod(i - span, n)] + pts[(i + span) % n]) * 0.5
				_offset[i] = clampf(_offset[i] + (mid - pts[i]).dot(_normal[i]) * 0.6, -lim, lim)
				pts[i] = cl[i] + _normal[i] * _offset[i]
	_line.resize(n)
	for i in n:
		_line[i] = cl[i] + _normal[i] * _offset[i]
	# Speed profile along the line: the corner limit, then braking worked backwards (twice round, so the
	# wrap from the last point to the first is braked for too).
	var pp: Dictionary = PERSONALITIES[_persona]
	var grip := car.tire_peak_accel * car.high_speed_peak_factor * float(lv["grip"]) * float(pp["risk"])
	# SPEC 130: ... AND THE ROPE ONLY GETS `rope_ease` OF THE BRAKES. A driver slows down by shortening
	# the rope, which points the cursor straight down the road -- exactly the case that is no longer
	# allowed to brake hard. Planning with the car's full `brake_deceleration` therefore had every AI
	# arriving at every corner far too fast: measured on the Serpent, the Grand Tourer spent 21.8 s of
	# a lap off the road. A driver plans for the braking it can actually get -- HALF WAY between the
	# eased figure and the full one, because a driver brakes for a corner with the rope swung out to the
	# side leading the car round, and the easing fades out with that angle. Planning for the eased figure
	# flat is the opposite mistake: at `rope_ease` 0.22 it plans to brake four and a half times too early,
	# never finds a straight it is allowed to be fast on, and stops using its boost at all.
	var brake := car.brake_deceleration * Car.MASS_REF / maxf(car.mass, 0.05) * float(lv["brake"]) \
			* float(pp["brake"]) * lerpf(clampf(car.rope_ease, 0.0, 1.0), 1.0, 0.30)
	var vmax := minf(car.max_speed * float(lv["top"]) * (1.0 + catch_up), speed_cap)
	_speed.resize(n)
	_corner.resize(n)
	for i in n:
		var a := _line[posmod(i - 2, n)]
		var b := _line[i]
		var c := _line[(i + 2) % n]
		var r := _circumradius(a, b, c)
		_corner[i] = sqrt(grip * r)
		_speed[i] = clampf(_corner[i], 70.0, vmax)
	for pass_i in 2:
		for k in range(n - 1, -1, -1):
			var i := k
			var j := (k + 1) % n
			var ds := _line[i].distance_to(_line[j])
			_speed[i] = minf(_speed[i], sqrt(_speed[j] * _speed[j] + 2.0 * brake * ds))


## The corners: every local minimum of the speed profile that is a real slow-down (below 88 % of the
## straight-line speed), with the way it turns.
func _find_corners() -> void:
	var n := _speed.size()
	_apexes = PackedInt32Array()
	_apex_turn = PackedFloat32Array()
	if n < 8:
		return
	var vmax := 0.0
	for v in _speed:
		vmax = maxf(vmax, v)
	for i in n:
		var v := _speed[i]
		if v > vmax * 0.88:
			continue
		var is_min := true
		for k in range(1, 6):
			if _speed[posmod(i - k, n)] < v or _speed[(i + k) % n] <= v:
				is_min = false
				break
		if is_min:
			var a := _line[posmod(i - 3, n)]
			var b := _line[i]
			var c := _line[(i + 3) % n]
			_apexes.append(i)
			_apex_turn.append(signf((b - a).cross(c - b)) if absf((b - a).cross(c - b)) > 0.001 else 1.0)


## The next corner apex ahead (within `window` points), as an index into `_apexes`, or -1.
func _next_apex(window: int) -> int:
	var n := track.get_point_count()
	var best := -1
	var best_ahead := window + 1
	for k in _apexes.size():
		var ahead := posmod(_apexes[k] - progress, n)
		if ahead < best_ahead:
			best_ahead = ahead
			best = k
	return best


func get_drift_count() -> int:
	return _drifts


func get_mistake_count() -> int:
	return _mistakes


static func level_text(level: String) -> String:
	return String(LEVEL_TEXT.get(level, ""))


static func _smooth(v: PackedFloat32Array, half: int) -> PackedFloat32Array:
	var n := v.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var s := 0.0
		var w := 0.0
		for k in range(-half, half + 1):
			var wk := 1.0 - absf(float(k)) / float(half + 1)
			s += v[posmod(i + k, n)] * wk
			w += wk
		out[i] = s / w
	return out


static func _circumradius(a: Vector2, b: Vector2, c: Vector2) -> float:
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ca := c.distance_to(a)
	var area2 := absf((b - a).cross(c - a))
	if area2 < 0.001:
		return 100000.0
	return ab * bc * ca / (2.0 * area2)


func get_line() -> PackedVector2Array:
	return _line


func get_planned_speed(index: int) -> float:
	return _speed[posmod(index, _speed.size())]


# ---------------------------------------------------------------- driving

## The rope target for this frame. `others` = every other car on the track (the player included).
## The ideal target (where this driver WANTS the cursor) goes through the HAND: seen a moment late (and
## not at all during a lapse of attention), then a cursor on a spring -- it can only move so fast, it
## overshoots and settles (more for a jumpy driver), and it is never perfectly still.
func compute_target(delta: float, others: Array) -> Vector2:
	_time += delta
	_big_left = maxf(_big_left - delta, 0.0)
	# A snapped rope: the hand goes straight back to the car to tie it on again (SPEC 46).
	if car.rope_snap_enabled and car.is_rope_snapped():
		_hand = Vector2.ZERO
		_hand_vel = Vector2.ZERO
		return car.position
	_update_persona(delta)
	var ideal := _ideal_target(delta, others) - car.position
	var lv: Dictionary = LEVELS[difficulty]
	var p := _p()
	_history.append([_time, ideal])
	while _history.size() > HAND_HISTORY:
		_history.pop_front()
	# What the driver sees now is what happened `react` s ago: the newest aim at least that old. Walked
	# from the newest entry back, so the answer is a few steps away instead of most of the history.
	var seen: Vector2 = ideal
	var cutoff := _time - float(lv["react"])
	for k in range(_history.size() - 1, -1, -1):
		var h: Array = _history[k]
		if float(h[0]) <= cutoff:
			seen = h[1]
			break
	# A lapse of attention: for a moment the hand stays where it was.
	if _lapse_left > 0.0:
		_lapse_left -= delta
		seen = _lapse_seen
	elif _rng.randf() < float(p["lapse"]) * delta * (1.0 + _mood + _pressure):
		_lapse_left = LAPSE_TIME
		_lapse_seen = _hand
		_lapses += 1
	if not _hand_ready:
		_hand = seen
		_hand_vel = Vector2.ZERO
		_hand_ready = true
	# The hand is a spring: stiffer for a better driver, and underdamped (it overshoots, then settles)
	# for a jumpy one. A braking stab is the easiest move a hand makes, so shortening goes twice as fast.
	var w := float(lv["hand"]) / HAND_STIFFNESS
	var zeta := float(p["zeta"])
	var acc := (seen - _hand) * w * w - _hand_vel * (2.0 * zeta * w)
	_hand_vel += acc * delta
	var top := float(lv["hand"]) * (2.0 if seen.length() < _hand.length() else 1.0)
	_hand_vel = _hand_vel.limit_length(top)
	_hand += _hand_vel * delta
	# Never perfectly still: a small tremor, worse when the driver is wound up.
	var j := float(p["jitter"]) * (1.0 + _mood)
	var tremor := Vector2(sin(_time * 7.3 + _phase) + 0.5 * sin(_time * 13.1 + _phase * 2.0),
			cos(_time * 6.1 + _phase * 1.7) + 0.5 * sin(_time * 11.7 + _phase)) * j * 0.5
	return car.position + _hand + tremor


## SPEC 110: the race's honest catch-up -- extra pace for a rival behind the player (0 = none), and a
## ceiling under the player's own top speed so it can never simply drive past.
var catch_up: float = 0.0
var speed_cap: float = INF


## Where this driver wants the cursor this frame (before the hand).
func _ideal_target(delta: float, others: Array) -> Vector2:
	var n := track.get_point_count()
	var pos := car.position
	var speed := car.get_speed()
	var lv: Dictionary = LEVELS[difficulty]
	var p := _p()
	var hw := track.track_width * 0.5

	# Stuck against something: aim straight down the track to get going again.
	if speed < STUCK_SPEED:
		_stuck += delta
	else:
		_stuck = 0.0
	if not is_on_track():
		_raise_mood(0.12 * delta)

	# The hand is late, so the driver reads the road that much further ahead.
	var look_px := maxf(LOOKAHEAD_MIN, speed * (LOOKAHEAD_GAIN + float(lv["react"])))
	var look_i := (progress + int(ceil(look_px / SPACING_GUESS))) % n
	var desired := INF
	var react_pts := int(ceil(speed * float(lv["react"]) / SPACING_GUESS))
	for k in 4 + react_pts:
		desired = minf(desired, _speed[(progress + k) % n])
	# Temper: a wound-up driver asks more of every corner than it planned (a wildcard in a hothead mood
	# drives on a pro's plan, so its risk comes in here too).
	desired *= sqrt(float(p["risk"]) / _plan_risk) * (1.0 + MOOD_OVERDRIVE * _mood * float(p["anger"]))
	# Cold rubber, or a tyre down to the rim (SPEC 49): the driver feels the grip it actually has and asks
	# that much less of every corner (cornering speed goes with the square root of grip).
	desired *= sqrt(car.grip_condition())

	# Corners: at the start of the braking for one, decide -- once per corner -- whether to get it wrong,
	# or to throw the car into a drift.
	var ai := _next_apex(28)
	if ai >= 0 and _apexes[ai] != _decided_apex and desired < speed - 30.0 and speed > 220.0 and is_on_track() \
			and not caution:
		_decided_apex = _apexes[ai]
		_corners += 1
		var m_chance := 1.0 if force_big else mistake_chance()
		var d_chance := float(lv["drift"]) * float(p["drift"]) * float(DRIFT_HABIT.get(car.car_id, 0.6))
		if _rng.randf() < m_chance:
			_start_mistake(ai)
		elif _rng.randf() < d_chance:
			_drift_apex = _apexes[ai]
			_flick_dir = _apex_turn[ai]
			_flick_angle = FLICK_ANGLE
	# A drifted corner: brake a touch more (the slide carries the car wide), and flick at the turn-in.
	if _drift_apex >= 0:
		var to_apex := posmod(_drift_apex - progress, n)
		if to_apex > n / 2:
			_drift_apex = -1
		else:
			desired *= DRIFT_ENTRY_SPEED
			if to_apex <= DRIFT_TURN_IN and _flick_left <= 0.0:
				_flick_time = FLICK_TIME * (1.4 if _mistake_kind == "flick" else (BIG_FLICK_TIME if _mistake_kind == "crash" else 1.0))
				_flick_left = _flick_time
				_drifts += 1
				_drift_apex = -1
				if _mistake_kind == "crash":
					_big_left = BIG_WINDOW                # SPEC 145: whatever happens now is the incident

	var aim := _line[look_i]
	var lateral_extra := 0.0
	# The mistakes (SPEC 42): late on the brakes, in too early, too greedy on the exit.
	if _mistake_apex >= 0:
		var to_m := posmod(_mistake_apex - progress, n)
		if to_m > n / 2:
			if _mistake_kind == "exit":
				_exit_left = EXIT_TIME
			_mistake_apex = -1
			_mistake_kind = ""
		elif _mistake_kind == "late":
			desired *= MISTAKE_OVERSPEED
		elif _mistake_kind == "crash":
			desired *= BIG_OVERSPEED                      # SPEC 145: no braking at all
		elif _mistake_kind == "early":
			lateral_extra += _mistake_turn * hw * 0.55         # cuts to the inside too soon
	if _exit_left > 0.0:
		_exit_left -= delta
		desired = maxf(desired, speed * 1.2)
		lateral_extra -= _exit_turn * hw * 0.45                # runs out wide onto the kerb and beyond

	# Off the road: back to the centerline a short way ahead -- gently, or (a hothead) yanked at full rope.
	if not is_on_track():
		aim = track.centerline[(progress + 3) % n]
		desired = lerpf(140.0, car.max_speed, float(p["yank"]))

	# Easy drivers wander a little across the road; traffic, attack and defence shift the line.
	var wander := sin(_time * 0.55 + _phase) * hw * float(lv["wander"])
	var shift_goal := wander + _traffic_shift(others, hw) + _race_craft(others, hw, ai, delta)
	if _panic_left > 0.0:
		shift_goal += _panic_side * hw * 0.8
	_side_shift = lerpf(_side_shift, shift_goal, 1.0 - exp(-4.0 * delta))
	# The line stays on the road; only a mistake takes the cursor past its edge.
	var lateral := clampf(_offset[look_i] + _side_shift, -(hw - 12.0), hw - 12.0) - _offset[look_i] + lateral_extra
	aim += _normal[look_i] * lateral

	# A clean driver lifts behind a car it cannot get past; an attacking one pushes on.
	desired = minf(desired, _follow_speed(others))
	if _attacking:
		desired *= 1.0 + 0.04 * float(p["attack"])
	if caution:
		desired = minf(desired, caution_cap)            # SPEC 145: the pace behind the yellow flag
	if _stuck > STUCK_TIME:
		aim = pos + (track.centerline[(progress + 4) % n] - track.centerline[progress]).normalized() * 80.0
		desired = 160.0

	# The rope's tension zone (SPEC 39): flat out, the rope goes a little past its full-throttle length.
	var dare := float(p.get("top", 1.0))
	var cap := car.max_speed * 0.985 * dare
	var vmax := minf(car.max_speed * float(lv["top"]) * dare * (1.0 + catch_up), speed_cap)
	if caution:
		vmax = minf(vmax, caution_cap)
		cap = minf(cap, caution_cap)
	desired = minf(desired, vmax)
	var flat_out := desired >= vmax * 0.99 or desired - speed > 80.0
	if car.boost_enabled and bool(lv["zone"]) and flat_out and _stuck <= STUCK_TIME and is_on_track() and not caution:
		cap = car.max_speed * (1.0 + car.rope_band * 0.5) * dare
		desired = cap
		_maybe_boost(p)
	# The over-pull mistake: on a straight the rope is flung far past the zone -- the car is dragged.
	if _overpull_left > 0.0:
		_overpull_left -= delta
		cap = car.max_speed * (1.0 + car.rope_band + 0.35)
		desired = cap
	elif flat_out and float(p["overpull"]) > 0.0 and _rng.randf() < OVERPULL_RATE * float(p["overpull"]) \
			* float(lv["mistake"]) * 4.0 * delta and is_on_track() and not caution:
		_overpull_left = OVERPULL_TIME
		_mistakes += 1
	# Show-off: a drifter flicks the tail out on the straights, just because.
	if float(p["show"]) > 0.0 and flat_out and _flick_left <= 0.0 and speed > 250.0 and is_on_track() \
			and (ai < 0 or posmod(_apexes[ai] - progress, n) > 16) and not caution:
		_show_timer -= delta
		if _show_timer <= 0.0:
			_show_timer = _rng.randf_range(1.2, 2.6) / float(p["show"])
			_flick_dir = -_flick_dir if _flick_dir != 0.0 else 1.0
			_flick_angle = SHOW_ANGLE
			_flick_time = SHOW_TIME
			_flick_left = SHOW_TIME

	# On / off: a person mostly flings the cursor out or stabs it back in; they do not meter the throttle.
	var rope_speed := clampf(desired, 0.0, cap)
	var bang := float(p["bang"])
	var gap := desired - speed
	if gap > 35.0:
		rope_speed = lerpf(rope_speed, cap, bang)
	elif gap < -45.0:
		rope_speed = lerpf(rope_speed, 0.0, bang)
	if _panic_left > 0.0:
		_panic_left -= delta
		if _panic_brake:
			rope_speed = 0.0

	var dir := aim - pos
	if dir.length_squared() < 1.0:
		dir = Vector2.from_angle(car.heading)
	# The flick: for a moment the cursor swings to the inside of the corner and the rope stays long, so
	# the car is yanked sideways at speed and steps out into a drift (the car's own drift model holds it).
	if _flick_left > 0.0:
		_flick_left -= delta
		var f := sin(clampf(_flick_left / maxf(_flick_time, 0.01), 0.0, 1.0) * PI)
		var ang := _flick_angle * (OVERFLICK if _mistake_kind == "flick" else (BIG_FLICK if _mistake_kind == "crash" else 1.0))
		dir = dir.rotated(_flick_dir * ang * f)
	var rope := car.slack_radius + rope_speed / maxf(car.speed_per_px, 0.01)
	return pos + dir.normalized() * rope


## The chance of getting the next corner wrong: the level's, times the personality's, wound up by the
## mood and (SPEC 143) multiplied by 1 + `crack` at full pressure, never past MISTAKE_CAP a corner. A
## rookie on hard: 4.8 % a corner alone, 22-43 % with a car on its tail (the mood decides). A pro: 1.2 %
## and 2-4 %. The first cut of this (crack 8, no cap) had a pressured rookie wrong at 47 corners of 52.
func mistake_chance() -> float:
	var lv: Dictionary = LEVELS[difficulty]
	var p := _p()
	return minf(float(lv["mistake"]) * float(p["mistake"]) * (1.0 + _mood)
			* (1.0 + float(p["crack"]) * _pressure), MISTAKE_CAP)


## A mistake at the corner `ai` (an index into `_apexes`), of a kind this driver tends to make.
func _start_mistake(ai: int) -> void:
	var kinds: Array = _p()["kinds"]
	if _pressure > 0.5:
		_cracks += 1
	_mistake_kind = String(kinds[_rng.randi_range(0, kinds.size() - 1)])
	if force_big or _rng.randf() < float(_p().get("big", 0.0)):
		_mistake_kind = "crash"                   # SPEC 145: a big one
		_big_ones += 1
	_mistake_apex = _apexes[ai]
	_mistake_turn = _apex_turn[ai]
	_exit_turn = _apex_turn[ai]
	_mistakes += 1
	if _mistake_kind == "flick" or _mistake_kind == "crash":
		# An over-flick: the drift goes in much too hard -- a half-spin. A big one is the OPPOSITE: the
		# hands cross and the rope is snatched to the OUTSIDE of the corner at the turn-in, flat out, so
		# the car darts for the edge sideways. (Flung to the inside, measured, it only turned in tighter
		# -- the drift model held it, and 40 big ones in a row never left the road.)
		_drift_apex = _apexes[ai]
		_flick_dir = _apex_turn[ai] if _mistake_kind == "flick" else -_apex_turn[ai]
		_flick_angle = FLICK_ANGLE


## When to fire a full boost: a Hothead the moment it can (not mid-corner), a Pro or a Bully to pass or on
## a long straight, everyone else on a long straight.
func _maybe_boost(p: Dictionary) -> void:
	if not car.is_boost_ready():
		return
	var policy := String(p["boost"])
	var fire := _straight_ahead(car.max_speed * 0.6, car.max_speed * (1.0 + car.boost_speed * 0.5))
	if policy == "eager":
		fire = fire or _straight_ahead(car.max_speed * 0.2, car.get_speed() * 1.05)
	elif policy == "pass":
		fire = fire or (_attacking and _straight_ahead(car.max_speed * 0.3, car.get_speed() * 1.1))
	if fire:
		car.fire_boost()


## Attack and defence (SPEC 42). Closing on a car ahead: go for it (push on, a different line, boost to
## pass). A car close behind: cover the inside of the next corner. A rookie panics when a car appears
## right alongside -- a stab of the brakes or a swerve away.
func _race_craft(others: Array, hw: float, ai: int, delta: float) -> float:
	var p := _p()
	var fwd := Vector2.from_angle(car.heading)
	var right := Vector2(-fwd.y, fwd.x)
	_attacking = false
	var shift := 0.0
	if caution:
		_pressed = false                                  # SPEC 145: nobody races under the yellow
		_pressure = maxf(_pressure - delta / PRESSURE_RELIEF, 0.0)
		return 0.0
	_panic_cool = maxf(_panic_cool - delta, 0.0)
	var attack := float(p["attack"])
	var defend := float(p["defend"])
	var panic := float(p["panic"])
	_pressed = false
	for o in others:
		var other := o as Car
		if other == null or other == car or not other.visible:
			continue
		var rel := other.position - car.position
		var ahead := rel.dot(fwd)
		var side := rel.dot(right)
		if ahead > 20.0 and ahead < 110.0 and absf(side) < 40.0 and attack > 0.0:
			_attacking = true
			# Pull out of its wake to the side with more room.
			shift += -signf(side if absf(side) > 2.0 else 1.0) * hw * 0.25 * minf(attack, 1.5)
		elif ahead < -15.0 and ahead > -TAIL_PX and absf(side) < TAIL_SIDE:
			_pressed = true                                   # SPEC 143: somebody is on the tail
			if defend > 0.0 and ai >= 0:
				# Cover the inside of the next corner -- harder the longer it has been there.
				shift += _apex_turn[ai] * hw * 0.3 * defend * (1.0 + _pressure)
		if panic > 0.0 and absf(ahead) < 26.0 and absf(side) < 40.0 and _panic_cool <= 0.0:
			_panic_cool = 2.5
			if _rng.randf() < panic * 0.6:
				_panic_left = PANIC_TIME
				_panic_brake = _rng.randf() < 0.5
				_panic_side = -signf(side)
				_raise_mood(0.15)
	# SPEC 143: the pressure winds up on the tail and lets off in clear air; it also winds up the mood,
	# which is the hothead's way of cracking (it over-drives rather than brakes too late).
	if _pressed:
		_pressure = minf(_pressure + delta / maxf(float(p["nerve"]), 0.1), 1.0)
		_raise_mood(0.06 * delta)
	else:
		_pressure = maxf(_pressure - delta / PRESSURE_RELIEF, 0.0)
	return clampf(shift, -hw * 0.6, hw * 0.6)


# ---------------------------------------------------------------- personality and mood (SPEC 42)

func _p() -> Dictionary:
	return PERSONALITIES[_persona]


## The wildcard changes mood every so often.
func _update_persona(delta: float) -> void:
	_mood = maxf(_mood - (MOOD_DECAY_LEADING if _place == 1 else MOOD_DECAY) * delta, 0.0)
	if profile != "wildcard":
		return
	_wild_left -= delta
	if _wild_left <= 0.0:
		_wild_left = _rng.randf_range(12.0, 22.0)
		_persona = String(WILDCARD_MOODS[_rng.randi_range(0, WILDCARD_MOODS.size() - 1)])


func _raise_mood(amount: float) -> void:
	_mood = clampf(_mood + amount * float(_p()["anger"]), 0.0, 1.0)


## The race tells the driver where it is running; dropping a place winds it up.
func notify_place(place: int) -> void:
	if _place > 0 and place > _place:
		_raise_mood(0.25 * float(place - _place))
	_place = place


## The race tells the driver it just wrecked.
func notify_wreck() -> void:
	_raise_mood(0.45)


func get_mood() -> float:
	return _mood


func get_personality() -> String:
	return profile


## The personality it is driving with right now (a wildcard's current mood).
func get_current_personality() -> String:
	return _persona


func get_lapse_count() -> int:
	return _lapses


## SPEC 143: how wound up it is by the car on its tail, 0..1.
func get_pressure() -> float:
	return _pressure


func is_pressed() -> bool:
	return _pressed


## Mistakes made under pressure (more than half).
func get_crack_count() -> int:
	return _cracks


func get_corner_count() -> int:
	return _corners


## SPEC 145: true for BIG_WINDOW s after a big one's flick -- a roll or a hard hit now is the incident.
func is_in_big_one() -> bool:
	return _big_left > 0.0


func get_big_one_count() -> int:
	return _big_ones


static func personality_tell(style: String) -> String:
	return String(PERSONALITY_TELLS.get(resolve_personality(style), ""))


static func personality_name(style: String) -> String:
	return String(PERSONALITY_NAMES.get(resolve_personality(style), "Pro"))


## A personality id from anything stored (the old "clean" / "aggressive" styles map onto Pro / Bully).
static func resolve_personality(style: String) -> String:
	var s := String(ALIASES.get(style, style))
	return s if PERSONALITIES.has(s) or s == "wildcard" else "pro"


## True if the grip allows at least `min_speed` (no braking for anything) for the next `px` of the line.
func _straight_ahead(px: float, min_speed: float) -> bool:
	var n := _line.size()
	if n == 0:
		return false
	var run := 0.0
	var i := progress
	var guard := 0
	while run < px and guard < n:
		var j := (i + 1) % n
		if _corner[i] < min_speed:
			return false
		run += _line[i].distance_to(_line[j])
		i = j
		guard += 1
	return true


## Lateral shift (px, + = toward our right) for traffic this frame.
func _traffic_shift(others: Array, hw: float) -> float:
	var fwd := Vector2.from_angle(car.heading)
	var right := Vector2(-fwd.y, fwd.x)
	var shift := 0.0
	_aggro_target = null
	var best_aggro := INF
	var push := 0.0 if caution else float(_p()["push"])
	for o in others:
		var other := o as Car
		if other == null or other == car or not other.visible or other.is_rolling():
			continue
		var rel := other.position - car.position
		var ahead := rel.dot(fwd)
		var side := rel.dot(right)
		if (push >= 0.5 or (push > 0.0 and _mood > 0.5)) and absf(ahead) < 34.0 and absf(side) < AGGRO_RANGE \
				and absf(side) > 8.0 and _worth_pushing(other, side, hw):
			var d := rel.length()
			if d < best_aggro:
				best_aggro = d
				_aggro_target = other
		elif ahead > 0.0 and ahead < TRAFFIC_AHEAD and absf(side) < TRAFFIC_SIDE:
			# In the way: pass on the side with more road.
			var my_off := _offset[progress] + _side_shift
			var go_right := my_off < 0.0 if absf(my_off) > 6.0 else side < 0.0
			shift += (1.0 if go_right else -1.0) * (TRAFFIC_SIDE + 12.0 - absf(side))
	if _aggro_target != null:
		# Lean into it: aim just past where it is sideways, so the contact pushes it outward.
		var s := (_aggro_target.position - car.position).dot(right)
		return clampf(s + signf(s) * 14.0, -hw, hw)
	return clampf(shift, -hw * 0.9, hw * 0.9)


## Only worth a shove when the target has the road edge on its FAR side (so a push puts it on the grass)
## and we are not about to brake hard for a corner ourselves (a shove there just spins both cars).
func _worth_pushing(other: Car, side: float, hw: float) -> bool:
	var n := track.get_point_count()
	var their_i := track.get_nearest_index(other.position)
	var their_off := (other.position - track.centerline[their_i]).dot(_normal[their_i])
	var toward_edge := signf(side) == signf(their_off) and absf(their_off) > hw * 0.25
	var braking_soon := _speed[(progress + 6) % n] < car.get_speed() * 0.8
	return toward_edge and not braking_soon


## Speed cap from a car directly ahead that we are about to run into (clean drivers only; an
## aggressive one is happy to tap it).
func _follow_speed(others: Array) -> float:
	var fwd := Vector2.from_angle(car.heading)
	var right := Vector2(-fwd.y, fwd.x)
	var tap := (float(_p()["push"]) >= 0.5 or _attacking) and not caution
	var cap := INF
	for o in others:
		var other := o as Car
		if other == null or other == car or not other.visible:
			continue
		var rel := other.position - car.position
		var ahead := rel.dot(fwd)
		var side := absf(rel.dot(right))
		if ahead > 0.0 and ahead < 48.0 and side < 18.0:
			var their := other.velocity.dot(fwd)
			cap = minf(cap, their * (1.05 if tap else 0.92))
	return cap


func get_aggro_target() -> Car:
	return _aggro_target
