class_name TrackData
extends RefCounted
## Procedural track centerlines. Pure data, no scene tree needed.
## Centerlines are closed loops (last point is NOT a duplicate of the first), resampled to ~uniform
## arc-length spacing, index 0 = start/finish, direction of travel = increasing index.

## Default road width. Per-track widths live in TrackRegistry (SPEC 14.2); this is the fallback for an
## id the registry does not know.
const TRACK_WIDTH := 110.0
const SCREEN_SIZE := Vector2(1280, 720)
const SAMPLE_SPACING := 16.0  # target arc-length spacing between centerline points

const CENTER := Vector2(640, 360)
const CIRCLE_RADII := Vector2(520, 265)
const FIGURE8_A := 530.0   # x half extent
const FIGURE8_B := 540.0   # y extent is +-B/2
const DENSE_SAMPLES := 4000


## Minimum point count a generator must produce before its result is trusted (SPEC 14.4).
const MIN_GENERATED_POINTS := 16

## id -> built centerline. EVERY track, including the two built-ins: `circle()` and `figure8()` each
## sample DENSE_SAMPLES = 4000 points and then resample, which measured 1311 us and 1528 us against 3 us
## for a cached generator track -- they were the two most expensive centerlines in the game to rebuild,
## and the select screen rebuilt them on every hover of their row (decision 30.12).
static var _generated: Dictionary = {}
## ids whose generator failed once; re-warning every frame would flood the log.
static var _generator_failed: Dictionary = {}


static func get_centerline(track_id: String) -> PackedVector2Array:
	if track_id == "figure8" or track_id == "circle":
		if not _generated.has(track_id):
			_generated[track_id] = figure8() if track_id == "figure8" else circle()
		return _generated[track_id]
	# SPEC 78: a track you drew yourself is its own line -- no generator script involved.
	if TrackRegistry.is_user(track_id):
		if not _generated.has(track_id):
			var drawn := TrackRegistry.user_centerline(track_id)
			_generated[track_id] = drawn if drawn.size() >= MIN_GENERATED_POINTS else circle()
		return _generated[track_id]
	var pts := _from_generator(track_id)
	return pts if pts.size() >= MIN_GENERATED_POINTS else circle()


## Builds a registry track from `res://scripts/tracks/<id>.gd`. The load is a guarded runtime `load()`,
## never a `preload`: a registry entry whose generator file is missing or broken degrades to the circle
## track with one warning instead of making the whole project fail to parse (SPEC decision 29.2).
static func _from_generator(track_id: String) -> PackedVector2Array:
	if _generated.has(track_id):
		return _generated[track_id]
	var path := TrackRegistry.get_generator_path(track_id)
	if path.is_empty():
		# Not a registry track at all (or one of the two built-ins). Callers already resolve unknown
		# ids through TrackRegistry.resolve(); falling back silently is the documented behaviour and
		# is what test_track_id_fallback pins.
		return PackedVector2Array()
	if not ResourceLoader.exists(path):
		_warn_once(track_id, "TrackData: generator '%s' is missing - using circle" % path)
		return PackedVector2Array()
	var script: Script = load(path) as Script
	if script == null or not script.has_method("build"):
		_warn_once(track_id, "TrackData: generator '%s' has no build() - using circle" % path)
		return PackedVector2Array()
	var pts: PackedVector2Array = script.call("build")
	if pts.size() < MIN_GENERATED_POINTS:
		_warn_once(track_id, "TrackData: generator '%s' returned %d points - using circle"
				% [path, pts.size()])
		return PackedVector2Array()
	pts = _rotate_start(track_id, pts)
	_generated[track_id] = pts
	return pts


## SPEC 131: WHERE THE LAP STARTS ON A CIRCUIT THAT IS ALREADY DRAWN. A generator produces a closed loop
## and index 0 is wherever its author happened to begin writing it -- which is also where the grid goes,
## and therefore which way every car faces at the lights.
##
## On the old Switchback that was the bottom straight, driven EAST to WEST: five cars lined up pointing off
## the left of the screen, perfectly correctly, on a 2400 x 2000 world where you cannot see enough of the
## circuit to work out that this is deliberate. Reported as "the machines are looking the other
## direction" -- and then the car spins round at the green light as it takes up the cursor, because a
## hand does not naturally sit to the left of a car.
##
## `start_at` rotates the array so the lap begins somewhere else on the SAME road. Nothing about the
## shape of the circuit changes: not a point moves, the corners are the corners, and the lap is the same
## length. Only the start line moves, which is a thing circuits do.
static func _rotate_start(track_id: String, pts: PackedVector2Array) -> PackedVector2Array:
	var at := TrackRegistry.get_start_at(track_id)
	if at <= 0.0 or pts.size() < 3:
		return pts
	var shift := posmod(int(round(at * float(pts.size()))), pts.size())
	if shift == 0:
		return pts
	var out := PackedVector2Array()
	for i in pts.size():
		out.append(pts[(i + shift) % pts.size()])
	return out


static func _warn_once(track_id: String, message: String) -> void:
	if _generator_failed.has(track_id):
		return
	_generator_failed[track_id] = true
	push_warning(message)


## Test hook: drop the built centerlines so an edited generator is picked up.
static func clear_cache() -> void:
	_generated.clear()
	_generator_failed.clear()


## Ellipse centred on screen. Starts at the bottom middle (a straight-ish section) and travels right-to-left
## along the bottom (clockwise on screen).
static func circle() -> PackedVector2Array:
	var dense := PackedVector2Array()
	dense.resize(DENSE_SAMPLES)
	for k in DENSE_SAMPLES:
		var th := PI * 0.5 + TAU * float(k) / float(DENSE_SAMPLES)
		dense[k] = CENTER + Vector2(CIRCLE_RADII.x * cos(th), CIRCLE_RADII.y * sin(th))
	return resample_closed(dense, SAMPLE_SPACING)


## Lemniscate of Gerono: x = cx + a*sin(t), y = cy + b*sin(t)*cos(t).
## Starts at the right tip (t = PI/2, far from the central crossing) moving up. The crossing is reached
## first at t = PI (lower branch) and again at t = 2*PI (upper / bridge branch).
static func figure8() -> PackedVector2Array:
	var dense := PackedVector2Array()
	dense.resize(DENSE_SAMPLES)
	for k in DENSE_SAMPLES:
		var t := PI * 0.5 + TAU * float(k) / float(DENSE_SAMPLES)
		dense[k] = CENTER + Vector2(FIGURE8_A * sin(t), FIGURE8_B * sin(t) * cos(t))
	return resample_closed(dense, SAMPLE_SPACING)


static func has_bridge(track_id: String) -> bool:
	return TrackRegistry.has_bridge(track_id)


## Resamples a closed polyline to evenly spaced points (spacing adjusted so the loop divides evenly).
## The first output point equals the first input point.
static func resample_closed(points: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var n_in := points.size()
	if n_in < 2 or spacing <= 0.0:
		return points.duplicate()
	var total := 0.0
	for i in n_in:
		total += points[i].distance_to(points[(i + 1) % n_in])
	if total <= 0.0:
		return points.duplicate()
	var count: int = maxi(3, roundi(total / spacing))
	var step := total / float(count)
	var out := PackedVector2Array()
	out.resize(count)
	var seg := 0
	var seg_start := 0.0
	var seg_len := points[0].distance_to(points[1 % n_in])
	for k in count:
		var s := step * float(k)
		while s > seg_start + seg_len and seg < n_in - 1:
			seg_start += seg_len
			seg += 1
			seg_len = points[seg].distance_to(points[(seg + 1) % n_in])
		var u := 0.0
		if seg_len > 0.0:
			u = clampf((s - seg_start) / seg_len, 0.0, 1.0)
		out[k] = points[seg].lerp(points[(seg + 1) % n_in], u)
	return out
