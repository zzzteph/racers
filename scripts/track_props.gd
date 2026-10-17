class_name TrackProps
extends Node2D
## Things at the side of the road that can be hit and broken (SPEC 41): traffic CONES along the road edge
## through every corner (on the apex and round the outside), and TYRE STACKS out on the run-off of the
## sharpest ones.
##
## A cone is light: a car knocks it flying (it tumbles, slides and ends up lying on the track, where it
## can be hit again), and a fast hit crushes it flat, with orange fragments. A tyre stack is heavy: a hit
## bursts it into loose tyres that roll away (each one a small obstacle of its own), costs the car real
## speed, a little damage and a nudge. Nothing is ever put back during a race; a restart builds a fresh set.
##
## Pure 2D and self-contained: Race calls `setup(track, seed)` once and `step(delta, cars)` every physics
## frame. Layout is deterministic per track (same seed, same cones -- online every client sees the same
## set; each simulates its own hits).

const Z := 3                        # over the skid marks (2), under the cars (5)

const KIND_CONE := 0
const KIND_TYRES := 1               # a tyre stack, standing
const KIND_TYRE := 2                # one loose tyre from a burst stack
const KIND_PART := 3                # a piece of a car (SPEC 45): its colour and size travel with it
const STANDING := 0
const KNOCKED := 1                  # flying / lying on its side
const CRUSHED := 2                  # flattened (cones), or burst (stacks)

## Per kind: contact radius, how much the object takes of the car's speed, damage to the car, the closing
## speed that crushes / bursts it, and how far it flies relative to the car (lighter flies further).
const SPEC := {
	KIND_CONE: {"r": 5.5, "loss": 0.02, "damage": 0.0, "crush": 330.0, "fly": 1.25, "kick": 0.0},
	KIND_TYRES: {"r": 9.0, "loss": 0.18, "damage": 4.0, "crush": 90.0, "fly": 0.35, "kick": 110.0},
	KIND_TYRE: {"r": 5.0, "loss": 0.05, "damage": 0.5, "crush": 99999.0, "fly": 0.9, "kick": 80.0},
	KIND_PART: {"r": 4.0, "loss": 0.015, "damage": 0.0, "crush": 99999.0, "fly": 1.0, "kick": 50.0},
}
## `kick` (SPEC 142): the sideways shove, px/s, the car takes from running over it -- see `Car.hit_object`.
const FRICTION := 3.2               # 1/s: loose objects slow down
const SPIN_DAMP := 2.5
const MAX_PROPS := 160
const MAX_PARTS := 320              # car debris kept on the track (the oldest goes first)
## SPEC 142: a wreck's debris lies there FOR A WHILE, not for the race. A piece, or a wheel that rolled
## off, is gone `_debris_life` s after it came off, fading over the last PART_FADE s of that: about three
## laps of the circuit it is on, held between PART_LIFE_MIN and PART_LIFE_MAX (a lap is 7 s on the
## Circle and 23 s on the Serpent, so one number cannot be "a few laps" on both). Long enough to be met
## on the next lap or two; short enough that lap one's wreck is not still a minefield on lap ten.
const PART_LIFE_MIN := 30.0
const PART_LIFE_MAX := 60.0
const PART_LIFE_LAPS := 3.0
const PART_LIFE_PACE := 420.0       # px/s, a racing lap's pace, for turning a length into a time
const PART_FADE := 4.0
## SPEC 46 -- the track remembers the race. OIL: a damaged car drips it; a slick cuts the grip of a wheel on
## it to OIL_GRIP and fades out over OIL_LIFE s. FIRE: a wreck leaves a burning patch for FIRE_LIFE s that
## does FIRE_DAMAGE per second to a car in it. SHARP DEBRIS: hitting a piece of a car punctures the tyre
## nearest it by PART_PUNCTURE.
const OIL_GRIP := 0.45
const OIL_LIFE := 20.0
const OIL_RADIUS := 6.0
const OIL_MAX_RADIUS := 12.0
const MAX_OIL := 160
const FIRE_LIFE := 4.0
const FIRE_RADIUS := 22.0
const FIRE_DAMAGE := 8.0
const PART_PUNCTURE := 0.5          # SPEC 142: two pieces under the same wheel burst it (was 0.3, four)
## THE ROPE SWEEPS NOTHING (SPEC 120; it used to, SPEC 49). These numbers are what it used to sweep
## with, kept for the record -- the rope is a line between the hand and the car, and things on the track
## are the CAR's business.
const ROPE_REACH := 13.0
const ROPE_FLICK := 210.0           # px/s given to something the rope sweeps
const ROPE_SNAG_BURST := 0.8        # s of snagging before the stack goes
const OIL_COLOR := Color(0.03, 0.03, 0.05, 0.62)
const CONE_SPACING := 3             # centerline points between cones along a corner edge
const CORNER_CURVATURE := 0.0042    # 1/px: a bend this tight gets cones (the circuits run 0.004-0.009)
const TYRE_SHARE := 0.9             # a tyre stack on the outside where a bend is within 10 % of the
                                    # track's tightest
const TYRE_GAP := 14                # centerline points between two tyre stacks

const CONE_COLOR := Color(1.0, 0.45, 0.08)
const CONE_STRIPE := Color(0.97, 0.97, 0.95)
const TYRE_COLOR := Color(0.09, 0.09, 0.1)
const TYRE_RIM := Color(0.35, 0.35, 0.38)
const SHADOW := Color(0, 0, 0, 0.28)

var _props: Array = []              # {kind, state, pos, vel, angle, spin, height, hvel}
var _rng := RandomNumberGenerator.new()
var _hits: int = 0
var _part_hits: int = 0             # ... of which were pieces of a car (SPEC 142 measures these)
var _debris_life: float = PART_LIFE_MAX  # SPEC 142: what a wreck's debris lives for on this track
var _oil: Array = []                # {pos, r, life}
var _fires: Array = []              # {pos, life}
var _t: float = 0.0
var _world: Vector2 = TrackData.SCREEN_SIZE     # SPEC 52: the world the props live in
var _solids: Array[Rect2] = []                  # SPEC 53: buildings a rolling tyre bounces off
## Held for as long as they are drawn (SPEC 54): `draw_mesh` records a reference, not a copy.
## Perf round: TWO meshes. The STATIC one holds everything at rest -- the standing cones and stacks, the
## crushed ones, the parts and tyres that have stopped, the oil -- and is rebuilt only when something
## joins or leaves it (a hit, a landing, a slick drying a shade). The DYNAMIC one holds what is moving
## and the fires, and is rebuilt on every redraw; it is a handful of shapes. It was ONE mesh of everything,
## rebuilt (2 ms) on every tick that any single tyre was still rolling.
var _static_paint := MeshPaint.new()
var _static_mesh := ArrayMesh.new()
var _static_has: bool = false
var _static_dirty: bool = true
var _dyn_paint := MeshPaint.new()
var _dyn_mesh := ArrayMesh.new()
var _dyn_has: bool = false
## A drying slick is re-baked at most this often; nobody can see oil getting 2 % lighter.
const OIL_FADE_EVERY := 0.25
var _oil_fade_accum: float = 0.0
## Raised by the tick, flushed once per drawn frame from `_process` (a `queue_redraw` from a tick paints
## in that tick's own flush: two or three rebuilds a frame when the frame is slow).
var _redraw_pending: bool = false


func _ready() -> void:
	z_index = Z
	z_as_relative = false


## Something needs drawing again; `still` says the STATIC mesh has to be rebuilt too.
func _touch(still: bool) -> void:
	if still:
		_static_dirty = true
	_redraw_pending = true


func _process(_delta: float) -> void:
	if _redraw_pending:
		_redraw_pending = false
		queue_redraw()


## Places the props for `track`. Cones on both edges of every bend (the apex and the outside), a tyre
## stack on the outside of the tight ones, never on the figure-8 bridge.
## `auto` false (SPEC 111: a drawn track that wants only the props its author placed) skips the
## cones-and-tyres pass and leaves the world ready for `add_authored`.
func setup(track: Track, seed_value: int = 1, auto: bool = true) -> void:
	_debris_life = clampf(track.get_total_length() * PART_LIFE_LAPS / PART_LIFE_PACE, PART_LIFE_MIN, PART_LIFE_MAX)
	_world = track.world_size            # SPEC 52: props live in the track's world, not always a screen
	_props.clear()
	_rng.seed = seed_value
	var n := track.get_point_count()
	if n < 8 or not auto:
		return
	var cl := track.centerline
	var hw := track.track_width * 0.5
	var curv := PackedFloat32Array()
	curv.resize(n)
	for i in n:
		var d1 := cl[i] - cl[posmod(i - 3, n)]
		var d2 := cl[(i + 3) % n] - cl[i]
		curv[i] = d1.angle_to(d2) / maxf((d1.length() + d2.length()) * 0.5, 1.0)
	var kmax := 0.0
	for v in curv:
		kmax = maxf(kmax, absf(v))
	var last_tyres := -100
	for i in range(0, n, CONE_SPACING):
		if _props.size() >= MAX_PROPS:
			break
		var k := curv[i]
		if absf(k) < CORNER_CURVATURE or (track.has_bridge() and _near_bridge(track, i)):
			continue
		var t := (cl[(i + 1) % n] - cl[posmod(i - 1, n)]).normalized()
		var right := Vector2(-t.y, t.x)
		var outside := -signf(k)          # a right-hander (k > 0) has its outside on the left
		# Cones right on the edge line, both sides.
		for side in [outside, -outside]:
			var cp: Vector2 = cl[i] + right * float(side) * (hw + 3.0)
			if _free(track, cp, hw + 1.0, 8.0):
				_add(KIND_CONE, cp)
		if absf(k) >= kmax * TYRE_SHARE and i - last_tyres >= TYRE_GAP:
			for dist in [26.0, 18.0]:
				var tp: Vector2 = cl[i] + right * outside * (hw + float(dist))
				if _free(track, tp, hw + 10.0, 14.0):
					_add(KIND_TYRES, tp)
					last_tyres = i
					break


## Off every part of the road (`clear` px from any centerline point) and `margin` px inside the barrier.
func _free(track: Track, p: Vector2, clear: float, margin: float) -> bool:
	var m := Track.BARRIER_MARGIN + margin
	var sz := _world
	if p.x < m or p.y < m or p.x > sz.x - m or p.y > sz.y - m:
		return false
	return track.distance_to_centerline(p) >= clear


func _near_bridge(track: Track, i: int) -> bool:
	var n := track.get_point_count()
	for k in range(-6, 7):
		if track.is_index_on_deck(posmod(i + k, n)):
			return true
	return false


func _add(kind: int, pos: Vector2) -> void:
	_props.append({"kind": kind, "state": STANDING, "pos": pos, "vel": Vector2.ZERO,
			"angle": _rng.randf_range(0.0, TAU), "spin": 0.0, "height": 0.0, "hvel": 0.0, "rest": true})


## A piece that came off a car: it tumbles along from where it came off and stays on the track (a car
## can knock it about again). The oldest piece goes once there are MAX_PARTS.
func add_debris(pos: Vector2, vel: Vector2, color: Color, size: Vector2) -> void:
	_make_room()
	_props.append({"kind": KIND_PART, "state": KNOCKED, "pos": pos, "vel": vel,
			"angle": _rng.randf_range(0.0, TAU), "spin": _rng.randf_range(-12.0, 12.0), "height": 0.0,
			"hvel": _rng.randf_range(30.0, 90.0), "color": color, "size": size, "rest": false,
			"life": _debris_life})
	_touch(true)


## SPEC 142: a wheel off a wrecked (or torn-apart) car. It is a loose tyre -- rubber, it rolls, it knocks
## the car that hits it and cuts nothing -- and like the rest of the wreck it lies there for a while.
## It counts against the DEBRIS budget (MAX_PARTS), not the scenery's: the Serpent's cones fill
## MAX_PROPS on their own, and a wreck there must still leave a wreck.
func add_loose_tyre(pos: Vector2, vel: Vector2) -> void:
	_make_room()
	_props.append({"kind": KIND_TYRE, "state": KNOCKED, "pos": pos, "vel": vel,
			"angle": _rng.randf_range(0.0, TAU), "spin": _rng.randf_range(-10.0, 10.0),
			"height": 0.0, "hvel": _rng.randf_range(30.0, 90.0), "rest": false, "life": _debris_life})
	_touch(true)


## Wreck debris -- anything with a life -- is capped at MAX_PARTS; the oldest piece goes to make room.
func _make_room() -> void:
	var n := 0
	var oldest := -1
	for i in _props.size():
		if _props[i].has("life"):
			n += 1
			if oldest < 0:
				oldest = i
	if n >= MAX_PARTS and oldest >= 0:
		_props.remove_at(oldest)


## SPEC 142: how long a piece of a wreck lies on this track.
func get_debris_life() -> float:
	return _debris_life


## A drop of oil where a damaged car passed. Drops close together pool into one bigger slick.
## `life` INF (SPEC 111: an oil drum an author placed) is a slick that never dries.
func add_oil(pos: Vector2, life: float = OIL_LIFE, radius: float = OIL_RADIUS) -> void:
	for o in _oil:
		if (o["pos"] as Vector2).distance_to(pos) < float(o["r"]) * 0.8:
			o["r"] = minf(float(o["r"]) + 1.0, OIL_MAX_RADIUS)
			o["life"] = maxf(float(o["life"]), OIL_LIFE)
			_touch(true)
			return
	if _oil.size() >= MAX_OIL:
		_oil.pop_front()
	_oil.append({"pos": pos + Vector2(_rng.randf_range(-2, 2), _rng.randf_range(-2, 2)), "r": radius,
			"life": life, "seed": _rng.randf_range(0.0, 100.0)})
	_touch(true)


## SPEC 111: the props an author placed on a drawn track -- {kind: "cone" | "tyres" | "oil", pos}.
## Wherever they put them (no clearance rule: a cone on the racing line is a choice). Returns how many
## were placed.
func add_authored(items: Array) -> int:
	var n := 0
	for it in items:
		var d: Dictionary = it
		var pos: Vector2 = d.get("pos", Vector2.ZERO)
		match String(d.get("kind", "")):
			"cone":
				if _props.size() < MAX_PROPS:
					_add(KIND_CONE, pos)
					n += 1
			"tyres":
				if _props.size() < MAX_PROPS:
					_add(KIND_TYRES, pos)
					n += 1
			"oil":
				add_oil(pos, INF, OIL_MAX_RADIUS)
				n += 1
	_touch(true)
	return n


## The buildings in this world (SPEC 53): loose things bounce off them instead of rolling through.
func set_solids(rects: Array[Rect2]) -> void:
	_solids = rects


## SPEC 120: THE ROPE TOUCHES NOTHING. Until now it swept the track (SPEC 49): anything loose within
## `ROPE_REACH` of the line was flicked aside, and a standing tyre stack snagged it and eventually
## burst. It was a nice idea and it played badly -- "the rope should not have effect on the objects".
## The rope is a line between your hand and your car, not a wire dragged through the scenery: cones you
## never touched went flying, stacks you had driven past exploded behind you, and the strain it added
## snapped the rope for something the car never hit.
##
## Kept as a function returning 0 so `Race._sweep_ropes` still has something to ask, and so the rule is
## written down where the sweeping used to be. The CAR still hits everything it drives into.
func sweep_rope(_from: Vector2, _to: Vector2, _delta: float) -> float:
	return 0.0


## A tyre stack coming apart: four loose tyres roll off and the stack is gone (SPEC 41 / 49).
func _burst_stack(p: Dictionary, spawned: Array, away: Vector2 = Vector2.ZERO, carry: Vector2 = Vector2.ZERO,
		closing: float = 120.0) -> void:
	p["state"] = CRUSHED
	p["vel"] = Vector2.ZERO
	var base := away if away.length() > 0.01 else Vector2.RIGHT
	for k in 4:
		if _props.size() + spawned.size() >= MAX_PROPS:
			break
		var dir := base.rotated(_rng.randf_range(-1.1, 1.1)) if away.length() > 0.01 \
				else Vector2.from_angle(_rng.randf_range(0.0, TAU))
		spawned.append({"kind": KIND_TYRE, "state": KNOCKED, "pos": (p["pos"] as Vector2) + dir * 5.0,
				"vel": carry * _rng.randf_range(0.3, 0.8) + dir * closing * _rng.randf_range(0.2, 0.5),
				"angle": _rng.randf_range(0.0, TAU), "spin": _rng.randf_range(-10.0, 10.0),
				"height": 0.0, "hvel": _rng.randf_range(20.0, 60.0), "rest": false})


## A tyre stack at `pos` (the layout places them itself; this is for tests).
func add_stack(pos: Vector2) -> void:
	_add(KIND_TYRES, pos)
	_touch(true)


## One prop, as data (position, velocity, state). A copy: the caller cannot move it by writing to it.
func get_prop(index: int) -> Dictionary:
	if index < 0 or index >= _props.size():
		return {}
	return (_props[index] as Dictionary).duplicate()


## Tyres knocked out of a tyre wall by a car hitting it (SPEC 49): they end up on the road and stay there.
func add_loose_tyres(pos: Vector2, away: Vector2, force: float, count: int = 2) -> void:
	for k in count:
		if _props.size() >= MAX_PROPS:
			return
		var dir := away.rotated(_rng.randf_range(-0.9, 0.9))
		_props.append({"kind": KIND_TYRE, "state": KNOCKED, "pos": pos + dir * 6.0,
				"vel": dir * clampf(force * 0.4, 40.0, 220.0),
				"angle": _rng.randf_range(0.0, TAU), "spin": _rng.randf_range(-10.0, 10.0),
				"height": 0.0, "hvel": _rng.randf_range(20.0, 70.0), "rest": false})
	_touch(true)


## A burning patch where a car exploded.
func add_fire(pos: Vector2) -> void:
	_fires.append({"pos": pos, "life": FIRE_LIFE})
	_touch(false)


## Grip factor at `pos` (1 = clean road, OIL_GRIP on a fresh slick, fading back to 1 as it dries).
func grip_at(pos: Vector2) -> float:
	for o in _oil:
		var r := float(o["r"])
		if absf(pos.x - (o["pos"] as Vector2).x) < r and (o["pos"] as Vector2).distance_to(pos) < r:
			return lerpf(1.0, OIL_GRIP, clampf(float(o["life"]) / (OIL_LIFE * 0.4), 0.0, 1.0))
	return 1.0


func get_oil_count() -> int:
	return _oil.size()


func get_fire_count() -> int:
	return _fires.size()


func _age_hazards(delta: float, cars: Array) -> void:
	_t += delta
	var fading := false
	# SPEC 142: wreck debris has a life. The last PART_FADE s of it are drawn fainter, at the oil's rate.
	for i in range(_props.size() - 1, -1, -1):
		var p: Dictionary = _props[i]
		if not p.has("life"):
			continue
		var life := float(p["life"]) - delta
		p["life"] = life
		if life <= 0.0:
			_props.remove_at(i)
			_touch(true)
		elif life < PART_FADE:
			fading = true
	for i in range(_oil.size() - 1, -1, -1):
		_oil[i]["life"] = float(_oil[i]["life"]) - delta
		if float(_oil[i]["life"]) <= 0.0:
			_oil.remove_at(i)
			_touch(true)
		elif float(_oil[i]["life"]) < OIL_LIFE * 0.5:
			fading = true                              # drying: its alpha is on the way down
	if fading:
		_oil_fade_accum += delta
		if _oil_fade_accum >= OIL_FADE_EVERY:
			_oil_fade_accum = 0.0
			_touch(true)
	for i in range(_fires.size() - 1, -1, -1):
		var f: Dictionary = _fires[i]
		f["life"] = float(f["life"]) - delta
		if float(f["life"]) <= 0.0:
			_fires.remove_at(i)
			_touch(false)
			continue
		for car in cars:
			var c := car as Car
			if c != null and c.visible and not c.is_locked() and c.position.distance_to(f["pos"]) < FIRE_RADIUS:
				c._add_damage(FIRE_DAMAGE * delta)
	if not _fires.is_empty():
		_touch(false)                                  # the flames flicker: every frame while they burn


## One physics frame: every car against every object, then the loose ones move. Returns the number of hits
## this frame (for tests / sound).
func step(delta: float, cars: Array) -> int:
	if delta <= 0.0:
		return 0
	var hits := 0
	var spawned: Array = []
	for car in cars:
		var c := car as Car
		if c == null or not c.visible or c.is_locked():
			continue
		var circles := c.get_contact_circles()
		for p in _props:
			var spec: Dictionary = SPEC[int(p["kind"])]
			if float(p["height"]) > 6.0 or int(p["state"]) == CRUSHED:
				continue                                 # in the air, or flattened / burst: driven over
			var r := float(spec["r"]) + Car.CONTACT_RADIUS
			var hit := false
			var at := Vector2.ZERO
			for cc in circles:
				if (p["pos"] as Vector2).distance_to(cc) < r:
					hit = true
					at = cc
					break
			if not hit:
				continue
			var rel: Vector2 = c.velocity - (p["vel"] as Vector2)
			var away := ((p["pos"] as Vector2) - at).normalized()
			if rel.dot(away) <= 20.0:
				# Touching but not closing (it is already being pushed along): just keep it clear.
				p["pos"] = at + away * (r + 0.5)
				continue
			hits += 1
			_hit(p, c, at, away, rel.length(), spawned)
	for sp in spawned:
		_props.append(sp)
	_move(delta)
	_age_hazards(delta, cars)
	_hits += hits
	if hits > 0:
		_touch(true)                 # a crushed cone or a burst stack changes shape where it stands
	return hits


func _hit(p: Dictionary, c: Car, at: Vector2, away: Vector2, closing: float, spawned: Array) -> void:
	var kind := int(p["kind"])
	var spec: Dictionary = SPEC[kind]
	var fly := float(spec["fly"])
	p["pos"] = at + away * (float(spec["r"]) + Car.CONTACT_RADIUS + 0.5)
	p["vel"] = c.velocity * fly + away * closing * 0.35 + away.orthogonal() * _rng.randf_range(-60.0, 60.0)
	p["spin"] = _rng.randf_range(-14.0, 14.0) * clampf(closing / 300.0, 0.3, 1.5)
	c.hit_object(at, float(spec["loss"]), float(spec["damage"]), float(spec["kick"]))
	if kind == KIND_PART:
		_part_hits += 1
		if c.tyres_enabled:
			c.puncture(at, PART_PUNCTURE)            # sharp edges
	if kind == KIND_TYRES:
		# The stack bursts: four loose tyres roll off, the stack is gone.
		_burst_stack(p, spawned, away, c.velocity, closing)
		return
	if kind == KIND_CONE:
		if closing >= float(spec["crush"]):
			p["state"] = CRUSHED
			p["vel"] = (p["vel"] as Vector2) * 0.5
		else:
			p["state"] = KNOCKED
			p["hvel"] = clampf(closing * 0.25, 30.0, 110.0)     # thrown up a little


func _move(delta: float) -> void:
	var damp := exp(-FRICTION * delta)
	var sdamp := exp(-SPIN_DAMP * delta)
	var moving := false
	for p in _props:
		var v: Vector2 = p["vel"]
		if v.length_squared() < 1.0 and float(p["height"]) <= 0.0 and absf(float(p["spin"])) < 0.05:
			if not bool(p.get("rest", true)):
				p["rest"] = true                 # it has stopped: into the static mesh, where it lies
				_static_dirty = true
			continue
		if bool(p.get("rest", true)):
			p["rest"] = false                    # it has been set moving: out of the static mesh
			_static_dirty = true
		moving = true
		var np := (p["pos"] as Vector2) + v * delta
		# The trackside barrier stops loose debris (it bounces back a little).
		var m := Track.BARRIER_MARGIN + 3.0
		var sz := _world
		if np.x < m or np.x > sz.x - m:
			v.x = -v.x * 0.4
			np.x = clampf(np.x, m, sz.x - m)
		for rect in _solids:
			if not rect.has_point(np):
				continue
			# Out the shallowest way, with what is left of the speed reversed: a tyre rolling into a wall
			# does not roll through it (SPEC 53).
			var l := np.x - rect.position.x
			var r2 := rect.end.x - np.x
			var u := np.y - rect.position.y
			var d2 := rect.end.y - np.y
			var least := minf(minf(l, r2), minf(u, d2))
			if is_equal_approx(least, l):
				np.x = rect.position.x - 0.5
				v.x = -absf(v.x) * 0.4
			elif is_equal_approx(least, r2):
				np.x = rect.end.x + 0.5
				v.x = absf(v.x) * 0.4
			elif is_equal_approx(least, u):
				np.y = rect.position.y - 0.5
				v.y = -absf(v.y) * 0.4
			else:
				np.y = rect.end.y + 0.5
				v.y = absf(v.y) * 0.4
			break
		if np.y < m or np.y > sz.y - m:
			v.y = -v.y * 0.4
			np.y = clampf(np.y, m, sz.y - m)
		p["pos"] = np
		p["vel"] = v * damp
		p["angle"] = float(p["angle"]) + float(p["spin"]) * delta
		p["spin"] = float(p["spin"]) * sdamp
		var h := float(p["height"]) + float(p["hvel"]) * delta
		var hv := float(p["hvel"]) - 420.0 * delta
		if h <= 0.0:
			h = 0.0
			hv = 0.0
		p["height"] = h
		p["hvel"] = hv
	if moving:
		_touch(false)


# ---------------------------------------------------------------- drawing

## Everything on the ground, in two meshes (SPEC 54, perf round). A canvas item's `_draw` runs on a
## redraw, not every frame, so a frame in which nothing rolls and nothing burns costs nothing; a frame
## in which one tyre rolls costs that tyre, not the hundred cones it rolls past.
func _draw() -> void:
	if _static_dirty:
		_static_dirty = false
		var m := _static_paint
		m.reset()
		# Oil under everything, then whatever is standing or lying still.
		for o in _oil:
			_paint_oil(m, o)
		for p in _props:
			if bool(p.get("rest", true)):
				_paint_prop(m, p)
		_static_has = m.build_into(_static_mesh)
	var d := _dyn_paint
	d.reset()
	for f in _fires:
		var k := clampf(float(f["life"]) / FIRE_LIFE, 0.0, 1.0)
		var fp: Vector2 = f["pos"]
		d.add_circle(fp, FIRE_RADIUS * 0.9, Color(0.05, 0.04, 0.03, 0.45), 10)
		for j in 7:
			var ang := float(j) * 0.9 + _t * 3.0
			var r := (6.0 + 5.0 * sin(_t * 11.0 + float(j) * 1.7)) * (0.5 + 0.5 * k)
			var at := fp + Vector2.from_angle(ang) * FIRE_RADIUS * 0.45 * (0.4 + 0.6 * fposmod(float(j) * 0.37, 1.0))
			d.add_circle(at, r, Color(1.0, 0.5 + 0.3 * sin(float(j) + _t * 7.0), 0.1, 0.55 * k), 8)
	for p in _props:
		if not bool(p.get("rest", true)):
			_paint_prop(d, p)
	_dyn_has = d.build_into(_dyn_mesh)
	if _static_has:
		draw_mesh(_static_mesh, null)
	if _dyn_has:
		draw_mesh(_dyn_mesh, null)


func _paint_prop(m: MeshPaint, p: Dictionary) -> void:
	match int(p["kind"]):
		KIND_CONE:
			_paint_cone(m, p)
		KIND_TYRES:
			_paint_tyres(m, p)
		KIND_TYRE:
			_paint_tyre(m, p["pos"], float(p["height"]), 5.0, _fade_of(p))
		KIND_PART:
			_paint_part(m, p)


## A slick: an irregular splash (never a disc), a few droplets round it, a glossy highlight and a thin
## rainbow sheen -- it looks like oil on tarmac, and fades as it dries.
func _paint_oil(m: MeshPaint, o: Dictionary) -> void:
	var a := clampf(float(o["life"]) / (OIL_LIFE * 0.5), 0.0, 1.0)
	var at: Vector2 = o["pos"]
	var r := float(o["r"])
	var seed := float(o.get("seed", 0.0))
	var pts := PackedVector2Array()
	for k in 11:
		var ang := TAU * float(k) / 11.0
		var wob := 0.72 + 0.28 * sin(seed + float(k) * 2.3) + 0.12 * sin(seed * 1.7 + float(k) * 5.1)
		pts.append(at + Vector2.from_angle(ang) * r * wob * Vector2(1.25, 0.85))
	m.add_polygon(pts, Color(OIL_COLOR.r, OIL_COLOR.g, OIL_COLOR.b, OIL_COLOR.a * a))
	for k in 3:
		var d := Vector2.from_angle(seed + float(k) * 2.1) * r * (1.25 + 0.2 * float(k))
		m.add_circle(at + d, r * (0.18 - 0.04 * float(k)),
				Color(OIL_COLOR.r, OIL_COLOR.g, OIL_COLOR.b, OIL_COLOR.a * a * 0.9), 7)
	# The sheen: a soft highlight and a thin rainbow ring.
	m.add_circle(at + Vector2(-r * 0.3, -r * 0.25), r * 0.28, Color(0.75, 0.8, 0.95, 0.16 * a), 7)
	m.add_ring(at, r * 0.55, 1.2, Color(0.55, 0.3, 0.8, 0.35 * a), 9)
	m.add_ring(at, r * 0.45, 1.0, Color(0.2, 0.75, 0.6, 0.3 * a), 9)


func _paint_cone(m: MeshPaint, p: Dictionary) -> void:
	var pos: Vector2 = p["pos"]
	var h := float(p["height"])
	match int(p["state"]):
		STANDING:
			m.add_circle(pos + Vector2(1.8, 2.4), 6.2, SHADOW, 8)
			m.add_circle(pos, 5.6, CONE_COLOR.darkened(0.15), 8)       # the base
			m.add_circle(pos, 4.0, CONE_COLOR, 8)
			m.add_ring(pos, 2.7, 1.5, CONE_STRIPE, 8)                  # the reflective band
			m.add_circle(pos, 1.1, CONE_COLOR.lightened(0.3), 6)       # the tip
		KNOCKED:
			# On its side: a triangle from base to tip, lifted while it flies.
			var a := float(p["angle"])
			var up := Vector2(0, -h)
			m.add_circle(pos + Vector2(1.5, 2.0), 4.0, SHADOW, 7)
			var tip := pos + up + Vector2.from_angle(a) * 10.0
			var b1 := pos + up + Vector2.from_angle(a + PI * 0.5) * 4.4
			var b2 := pos + up + Vector2.from_angle(a - PI * 0.5) * 4.4
			m.add_triangle(tip, b1, b2, CONE_COLOR)
			m.add_line(b1.lerp(tip, 0.45), b2.lerp(tip, 0.45), 1.2, CONE_STRIPE)
			m.add_line(b1, b2, 2.0, CONE_COLOR.darkened(0.3))
		CRUSHED:
			# Flattened, with a couple of fragments.
			var a2 := float(p["angle"])
			var pts := PackedVector2Array()
			for k in 7:
				var ang := a2 + TAU * float(k) / 7.0
				pts.append(pos + Vector2.from_angle(ang) * (4.5 + 2.0 * sin(float(k) * 2.3)))
			m.add_polygon(pts, CONE_COLOR.darkened(0.25))
			m.add_line(pos + Vector2.from_angle(a2) * 2.0, pos + Vector2.from_angle(a2) * 5.5, 1.0, CONE_STRIPE)
			m.add_circle(pos + Vector2.from_angle(a2 + 2.0) * 8.0, 1.2, CONE_COLOR, 6)
			m.add_circle(pos + Vector2.from_angle(a2 - 2.4) * 9.0, 1.0, CONE_COLOR, 6)


func _paint_tyres(m: MeshPaint, p: Dictionary) -> void:
	var pos: Vector2 = p["pos"]
	if int(p["state"]) == STANDING:
		m.add_circle(pos + Vector2(2.0, 3.0), 10.0, SHADOW, 9)
		# A stack of three seen from above: offset rings.
		for k in 3:
			var o := Vector2.from_angle(float(p["angle"]) + float(k) * 2.1) * 3.0
			_paint_tyre(m, pos + o, 0.0, 6.0)
	else:
		# Burst: a black scuff where it stood.
		m.add_circle(pos, 8.0, Color(0, 0, 0, 0.22), 9)


func _paint_part(m: MeshPaint, p: Dictionary) -> void:
	var pos: Vector2 = p["pos"]
	var h := float(p["height"])
	var sz: Vector2 = p.get("size", Vector2(6, 4))
	var col: Color = p.get("color", Color(0.2, 0.2, 0.22))
	var a := float(p["angle"])
	var fade := _fade_of(p)
	m.add_rotated_rect(pos + Vector2(1.5, 2.0), sz, a, Color(SHADOW, SHADOW.a * fade))
	m.add_rotated_rect(pos + Vector2(0, -h), sz, a, Color(col.darkened(0.15), fade))
	m.add_rotated_rect_outline(pos + Vector2(0, -h), sz, a, Color(col.darkened(0.55), fade), 1.0)


## 1 for something that stays; on the way to 0 over the last PART_FADE s of a piece that does not.
func _fade_of(p: Dictionary) -> float:
	if not p.has("life"):
		return 1.0
	return clampf(float(p["life"]) / PART_FADE, 0.0, 1.0)


func _paint_tyre(m: MeshPaint, pos: Vector2, h: float, r: float, fade: float = 1.0) -> void:
	var at := pos + Vector2(0, -h)
	if h > 0.5:
		m.add_circle(pos + Vector2(1.5, 2.0), r, Color(SHADOW, SHADOW.a * fade), 8)
	m.add_circle(at, r, Color(TYRE_COLOR, fade), 9)
	m.add_ring(at, r * 0.55, 1.4, Color(TYRE_RIM, fade), 8)


# ---------------------------------------------------------------- queries (tests)

func get_prop_count(kind: int = -1) -> int:
	if kind < 0:
		return _props.size()
	var n := 0
	for p in _props:
		if int(p["kind"]) == kind:
			n += 1
	return n


func count_state(kind: int, state: int) -> int:
	var n := 0
	for p in _props:
		if int(p["kind"]) == kind and int(p["state"]) == state:
			n += 1
	return n


func get_props() -> Array:
	return _props


func get_hit_count() -> int:
	return _hits


func get_part_hit_count() -> int:
	return _part_hits
