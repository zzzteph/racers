class_name Track
extends Node2D
## Race track: procedural drawing, geometry queries, checkpoints, branch-aware car progress and the
## figure-8 bridge. All logic works right after setup() even when the node is not in the scene tree.

const BRIDGE_DECK_Z := 10
## Checkpoint gates are drawn here, above SkidMarks.GROUND_Z (2) and below the car (5) and the deck (10).
const GATES_Z := 4
const PROGRESS_WINDOW := 10          # centerline points searched either side of the last index
const START_BACKOFF := 40.0          # px behind the start line where the car spawns

const GRASS_COLOR := Color(0.23, 0.48, 0.2)
const EDGE_COLOR := Color(0.95, 0.95, 0.95)
## SPEC 124: the repair lane's paint.
const ASPHALT_COLOR := Color(0.3, 0.3, 0.32)
const DASH_COLOR := Color(0.85, 0.8, 0.45, 0.55)
const EDGE_BAND := 4.0               # white edge band per side (total band width = width + 8)
const GATE_COLOR := Color(1.0, 1.0, 1.0, 0.22)
const SAND_COLOR := Color(0.86, 0.76, 0.50)
const SAND_DOT_COLOR := Color(0.72, 0.62, 0.38)
## Sand traps: on the outside of every corner tighter than SAND_CORNER_RADIUS, SAND_DEPTH px deep at the
## apex, tapering to nothing SAND_HALF_SPAN centerline points either side. Trimmed wherever they would
## reach another part of the road or the barrier.
const SAND_CORNER_RADIUS := 320.0
const SAND_DEPTH := 64.0
const SAND_HALF_SPAN := 8
const SAND_ROAD_GAP := 10.0          # px of grass kept between a trap and any other part of the road
const GATE_PENDING_COLOR := Color(1.0, 0.85, 0.2, 0.85)
const BARRIER_MARGIN := 22.0         # matches Car.screen_margin: where the car's position is clamped
const BARRIER_COLOR := Color(0.24, 0.24, 0.26)
## TYRE WALLS (SPEC 49). The barrier is lined with tyres wherever the road runs within
## `TYRE_WALL_NEAR` px of it -- which is exactly where cars actually hit it. A tyre wall absorbs the blow
## and grabs the car; bare concrete hurts, and lets it bounce back onto the road.
const TYRE_WALL_NEAR := 170.0
const TYRE_WALL_R := 5.0
const TYRE_WALL_STEP := 12.0
const TYRE_WALL_COLOR := Color(0.09, 0.09, 0.1)
const TYRE_WALL_RIM := Color(0.28, 0.28, 0.31)
const BARRIER_KERB_A := Color(0.85, 0.2, 0.15)
const BARRIER_KERB_B := Color(0.92, 0.92, 0.92)
const BRIDGE_DECK_FACTOR := 2.5      # deck length = factor * track width
const UPPER_ZONE_MARGIN := 30.0
const CHECKPOINT_BRIDGE_MARGIN := 40.0
## Windowed distance (in track widths) above which the global recovery search also runs: 0.45 * 110 = 50 px
## is about the road edge, so a car that took the *other* branch's exit at the figure-8 crossing is
## re-attached to the branch it is really on at once, instead of being reported off track (and drawn on the
## wrong side of the deck) for ~3 s while its believed distance crawls up to the old 2-width threshold.
const RECOVERY_FACTOR := 0.45
## Direction-of-travel tie-break for that search, in track widths: a candidate segment whose tangent does
## not match the car's motion is scored this much worse, so the two branches never swap at the crossing.
const RECOVERY_MARGIN := 0.75
## Checkpoint counts and road widths are the registry's (SPEC 14.4); Track reads them per id.

var track_id: String = ""
var centerline: PackedVector2Array
var track_width: float = TrackData.TRACK_WIDTH
## The world this track lives in (SPEC 52): one screen for the classic tracks, bigger for the rest.
## Everything the track draws -- the ground, the barrier, the kerbs, the tyre walls -- uses this, and
## Race takes the car's bounds, the camera limits and the minimap from it.
var world_size: Vector2 = TrackData.SCREEN_SIZE

var _arc: PackedFloat32Array = PackedFloat32Array()   # cumulative arc length at each point, _arc[0] = 0
var _total_length: float = 0.0
var _checkpoint_indices: PackedInt32Array = PackedInt32Array()
var _checkpoint_positions: PackedVector2Array = PackedVector2Array()
var _next_checkpoint: int = 1

var _has_bridge: bool = false
var _bridge_center: Vector2 = Vector2.ZERO
var _lower_arc: float = 0.0          # arc position of the crossing on the lower branch
var _upper_arc: float = 0.0          # arc position of the crossing on the upper (bridge) branch
var _deck_half_length: float = 0.0
var _lower_zone_half: float = 0.0
var _bridge_deck: BridgeDeck = null
var _gate_layer: Node2D = null
## The drawn deck's centreline, cached once in `setup()`: `is_point_on_deck()` runs per skid-mark segment
## and must not rebuild it (nor allocate) on the hot path.
var _deck_points: PackedVector2Array = PackedVector2Array()

## Sand traps as quads (4 points each), built in setup(); `_sand_bounds` is one Rect2 per trap.
var _sand_quads: Array[PackedVector2Array] = []
var _sand_trap_of_quad: PackedInt32Array = PackedInt32Array()
var _sand_bounds: Array[Rect2] = []

## Where the barrier is lined with tyres, sampled every TYRE_WALL_STEP px along each side and computed
## ONCE in setup(). It used to be a live `distance_to_centerline()` per sample, which is a full scan of
## the centerline -- ~300 of them per redraw of the barrier, and one per frame per car scraping a wall.
var _wall_top: PackedByteArray = PackedByteArray()
var _wall_bottom: PackedByteArray = PackedByteArray()
var _wall_left: PackedByteArray = PackedByteArray()
var _wall_right: PackedByteArray = PackedByteArray()

## SPEC 54: the whole ground -- grass, barrier, kerbs, tyre walls, sand, road, dashes, start line --
## baked into one mesh at setup, because none of it moves during a race. It was ~2280 draw calls a frame
## (a quad per centerline segment, a dot per grain of sand, two circles per tyre in the walls); it is one.
var _ground: ArrayMesh = null

var _progress_index: int = 0
var _car_distance: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
var _has_last_pos: bool = false


func setup(id: String) -> void:
	track_id = TrackRegistry.resolve(id)
	centerline = TrackData.get_centerline(track_id)
	track_width = TrackRegistry.get_width(track_id)
	world_size = TrackRegistry.get_world_size(track_id)
	links = TrackRegistry.get_links(track_id)     # SPEC 124: paved road off the centreline
	_compute_arc()
	_setup_bridge()
	_deck_points = get_bridge_deck_points()
	_setup_checkpoints()
	_setup_bridge_deck_node()
	_setup_gate_layer()
	_setup_sand()
	_setup_tyre_walls()
	_bake_ground()
	reset_progress(0)
	queue_redraw()


# ------------------------------------------------------------------ geometry (branch-agnostic)

func get_point_count() -> int:
	return centerline.size()


func get_total_length() -> float:
	return _total_length


## SPEC 130: THE BOX THE ROAD ACTUALLY OCCUPIES, in world coordinates. A track's `world_size` is the
## room the CAMERA has to move in, which on the bigger circuits is a good deal larger than the circuit:
## the old Switchback declared 2400 x 2000 and its road stopped well short of the east wall, so a preview that
## fitted the declared world drew a quarter of itself as empty grass ("the right part of the map preview
## is empty"). Anything framing the circuit wants this instead.
func road_bounds() -> Rect2:
	if centerline.is_empty():
		return Rect2(Vector2.ZERO, world_size)
	var box := Rect2(centerline[0], Vector2.ZERO)
	for p in centerline:
		box = box.expand(p)
	for r in links:
		box = box.merge(r as Rect2)
	# The asphalt is `track_width` wide about the centreline, and a little air round it reads better
	# than a circuit jammed against the edge of its own picture.
	return box.grow(track_width * 0.5 + 40.0)


func get_start_position() -> Vector2:
	if centerline.size() < 2:
		return Vector2.ZERO
	var fwd := (centerline[1] - centerline[0]).normalized()
	return centerline[0] - fwd * START_BACKOFF


func get_start_heading() -> float:
	if centerline.size() < 2:
		return 0.0
	return (centerline[1] - centerline[0]).angle()


func distance_to_centerline(pos: Vector2) -> float:
	var n := centerline.size()
	if n == 0:
		return INF
	var best := INF
	for i in n:
		var d := _segment_distance(i, pos)
		if d < best:
			best = d
	return best


func is_on_track(pos: Vector2) -> bool:
	if distance_to_centerline(pos) <= track_width * 0.5:
		return true
	# SPEC 124: a paved link is road, even though it is nowhere near the centreline. Without this the
	# route a breakable opens is grass, and grass is capped at `Car.off_track_max_speed` -- so the
	# "shortcut" would take nine seconds to cover what the road does in two.
	for r in links:
		if (r as Rect2).has_point(pos):
			return true
	return false


## SPEC 124: the paved links on this circuit, in world space. Set by `setup()` from the registry; the
## scenery reads them so it does not plant a tree in the middle of one.
var links: Array = []


func get_nearest_index(pos: Vector2) -> int:
	var best := INF
	var best_i := 0
	for i in centerline.size():
		var d := centerline[i].distance_squared_to(pos)
		if d < best:
			best = d
			best_i = i
	return best_i


# ------------------------------------------------------------------ checkpoints

func get_checkpoint_positions() -> PackedVector2Array:
	return _checkpoint_positions


func get_checkpoint_indices() -> PackedInt32Array:
	return _checkpoint_indices


## Generous enough that an ordinary corner cut still clips the gate (the checkpoint rule is there to stop
## infield shortcuts, not to punish a wide line); acceptance is additionally bounded by
## `LapTracker.INDEX_WINDOW` along the car's own branch.
func get_checkpoint_radius() -> float:
	return track_width * 1.2


## The checkpoint the car must reach next (highlighted in `_draw`). Set by the race from the LapTracker.
func set_next_checkpoint(index: int) -> void:
	if index == _next_checkpoint:
		return
	_next_checkpoint = index
	# The gates moved into the "GateLayer" child (decision 20.9), and nothing in `Track._draw` reads
	# `_next_checkpoint` any more, so redrawing the Track itself here re-ran ~550 draw commands (grass,
	# barrier, ~150 kerb ticks, two ~150-quad strips, dashes, start line) ~36 times a race for a
	# byte-identical result.
	if _gate_layer != null and is_instance_valid(_gate_layer):
		_gate_layer.queue_redraw()


func get_next_checkpoint() -> int:
	return _next_checkpoint


# ------------------------------------------------------------------ branch-aware progress

func reset_progress(index: int = 0) -> void:
	var n := centerline.size()
	_progress_index = posmod(index, n) if n > 0 else 0
	_car_distance = 0.0
	_has_last_pos = false


func update_car_progress(pos: Vector2) -> int:
	var n := centerline.size()
	if n < 2:
		return 0
	# Direction of travel since the last update: used to pick the right branch at the figure-8 crossing.
	var move_dir := Vector2.ZERO
	if _has_last_pos:
		var step := pos - _last_pos
		if step.length_squared() > 0.25:
			move_dir = step.normalized()
	_last_pos = pos
	_has_last_pos = true

	var best_d := INF
	var best_i := _progress_index
	for off in range(-PROGRESS_WINDOW, PROGRESS_WINDOW + 1):
		var i := posmod(_progress_index + off, n)
		var res := _segment_nearest(i, pos)
		if res.x < best_d:
			best_d = res.x
			best_i = i if res.y <= 0.5 else (i + 1) % n
	if best_d > track_width * RECOVERY_FACTOR:
		# The car is clearly off its own branch (crawled across the infield, or took the other branch's
		# exit at the crossing): global recovery search, scored so that a segment running against the
		# car's direction of travel is not preferred over the branch it is actually driving along.
		var g_i := -1
		var g_d := INF
		var g_score := INF
		for i in n:
			var res := _segment_nearest(i, pos)
			var score := res.x
			if move_dir != Vector2.ZERO:
				var tangent := (centerline[(i + 1) % n] - centerline[i]).normalized()
				score += (1.0 - maxf(tangent.dot(move_dir), 0.0)) * track_width * RECOVERY_MARGIN
			if score < g_score:
				g_score = score
				g_d = res.x
				g_i = i if res.y <= 0.5 else (i + 1) % n
		if g_i >= 0 and g_d < best_d:
			best_d = g_d
			best_i = g_i
	_progress_index = best_i
	_car_distance = best_d
	return _progress_index


func get_progress_index() -> int:
	return _progress_index


func get_car_distance_to_centerline() -> float:
	return _car_distance


func is_car_on_track() -> bool:
	if get_car_distance_to_centerline() <= track_width * 0.5:
		return true
	# SPEC 124: and the paved links. This is the test the CARS actually use -- `make_on_track_provider`
	# is built on it -- so a link that only `is_on_track()` knew about drove like grass, at 58 px/s,
	# which is how the first measured version of a link came out three seconds SLOWER
	# than the road it was supposed to cut out.
	for r in links:
		if (r as Rect2).has_point(_last_pos):
			return true
	return false


func make_on_track_provider() -> Callable:
	return func(pos: Vector2) -> bool:
		update_car_progress(pos)
		return is_car_on_track()


# ------------------------------------------------------------------ bridge (figure 8)

func has_bridge() -> bool:
	return _has_bridge


func get_bridge_center() -> Vector2:
	return _bridge_center if _has_bridge else Vector2.ZERO


func is_index_on_upper_branch_zone(index: int) -> bool:
	if not _has_bridge or centerline.is_empty():
		return false
	var s := _arc[posmod(index, centerline.size())]
	return _cyclic_arc_distance(s, _upper_arc) <= _deck_half_length + UPPER_ZONE_MARGIN


## True only over the *drawn* deck (no layering margin): drives the car's raised look so it does not pop
## to bridge scale a car length before the deck starts.
func is_index_on_deck(index: int) -> bool:
	if not _has_bridge or centerline.is_empty():
		return false
	var s := _arc[posmod(index, centerline.size())]
	return _cyclic_arc_distance(s, _upper_arc) <= _deck_half_length


func is_car_on_deck() -> bool:
	return has_bridge() and is_index_on_deck(get_progress_index())


## True when `pos` is inside the DRAWN deck footprint: within half a track width of the deck centreline and
## inside its arc span. Unlike [method is_index_on_deck] this bounds the point sideways as well, which is
## what a consumer placing something on the deck (a skid mark, a particle) needs — the along-arc test alone
## puts a wheel sliding 59 px wide of the centreline on the deck layer, over its rail and off its edge.
## Side-effect free: it touches no progress state and is safe to call from a Callable.
func is_point_on_deck(pos: Vector2) -> bool:
	if not _has_bridge:
		return false
	var deck := _deck_points
	if deck.size() < 2:
		return false
	var half := track_width * 0.5
	var best := INF
	for i in deck.size() - 1:
		var a := deck[i]
		var b := deck[i + 1]
		var ab := b - a
		var len2 := ab.length_squared()
		var t := 0.0 if len2 <= 0.000001 else clampf((pos - a).dot(ab) / len2, 0.0, 1.0)
		best = minf(best, pos.distance_to(a + ab * t))
		if best <= half:
			return true
	return best <= half


func is_index_on_lower_branch_zone(index: int) -> bool:
	if not _has_bridge or centerline.is_empty():
		return false
	var s := _arc[posmod(index, centerline.size())]
	return _cyclic_arc_distance(s, _lower_arc) <= _lower_zone_half


func is_car_on_bridge_layer() -> bool:
	return has_bridge() and is_index_on_upper_branch_zone(get_progress_index())


func is_car_under_bridge() -> bool:
	return has_bridge() and is_index_on_lower_branch_zone(get_progress_index())


func get_bridge_deck() -> Node2D:
	return _bridge_deck


## Extra helper: arc length position of a centerline index.
func get_arc_at_index(index: int) -> float:
	if centerline.is_empty():
		return 0.0
	return _arc[posmod(index, centerline.size())]


## Extra helper: the upper-branch deck section (global points), empty when there is no bridge.
func get_bridge_deck_points() -> PackedVector2Array:
	if not _has_bridge:
		return PackedVector2Array()
	var pts := PackedVector2Array()
	var count: int = maxi(2, ceili(_deck_half_length * 2.0 / 8.0) + 1)
	for k in count:
		var s := _upper_arc - _deck_half_length + _deck_half_length * 2.0 * float(k) / float(count - 1)
		pts.append(_point_at_arc(s))
	return pts


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if _ground != null:
		draw_mesh(_ground, null)
		return
	# No bake (a track with no centerline, or one built before setup): the ground is still the ground.
	draw_rect(Rect2(Vector2.ZERO, world_size), GRASS_COLOR)


## Bakes the ground into `_ground` (SPEC 54). Everything here is exactly what `_draw` used to paint, in
## the same order: grass, barrier and kerbs, tyre walls, sand, the white edging, the asphalt, the centre
## dashes and the start line.
func _bake_ground() -> void:
	_ground = null
	var m := MeshPaint.new()
	m.add_rect(Rect2(Vector2.ZERO, world_size), GRASS_COLOR)
	if centerline.size() < 3:
		_ground = m.build()
		return
	_bake_barrier(m)
	_bake_sand(m)
	var hw := track_width * 0.5
	# All white bands first, then all asphalt, so the lower road stays continuous at the figure-8 crossing.
	var normals := compute_normals(centerline, true)
	m.add_strip(centerline, normals, true, hw + EDGE_BAND, EDGE_COLOR)
	# SPEC 124: the links, drawn as road, under the centreline's own strip so the joins are covered by it.
	for r in links:
		m.add_rect((r as Rect2).grow(EDGE_BAND), EDGE_COLOR)
	for r in links:
		m.add_rect((r as Rect2).grow(-1.0), ASPHALT_COLOR)
	m.add_strip(centerline, normals, true, hw - 1.0, ASPHALT_COLOR)
	_bake_centre_dashes(m)
	_bake_start_line(m)
	_ground = m.build()



## Trackside barrier drawn exactly where the car's position is clamped, so a car that overcooks a corner
## visibly stops against a wall instead of against nothing.
func _bake_barrier(paint: MeshPaint) -> void:
	var s := world_size
	var m := BARRIER_MARGIN
	var bands: Array[Rect2] = [
		Rect2(0, 0, s.x, m), Rect2(0, s.y - m, s.x, m),
		Rect2(0, m, m, s.y - m * 2.0), Rect2(s.x - m, m, m, s.y - m * 2.0),
	]
	for b in bands:
		paint.add_rect(b, BARRIER_COLOR)
	# Red/white kerb ticks along the inner face of the barrier.
	var tick := 26.0
	var kerb := 6.0
	var i := 0
	var x := 0.0
	while x < s.x:
		var c := BARRIER_KERB_A if i % 2 == 0 else BARRIER_KERB_B
		var w := minf(tick, s.x - x)
		paint.add_rect(Rect2(x, m - kerb, w, kerb), c)
		paint.add_rect(Rect2(x, s.y - m, w, kerb), c)
		x += tick
		i += 1
	i = 0
	var y := m
	while y < s.y - m:
		var c := BARRIER_KERB_A if i % 2 == 0 else BARRIER_KERB_B
		var h := minf(tick, s.y - m - y)
		paint.add_rect(Rect2(m - kerb, y, kerb, h), c)
		paint.add_rect(Rect2(s.x - m, y, kerb, h), c)
		y += tick
		i += 1
	_bake_tyre_walls(paint)


## Tyres stacked against the inner face of the barrier where the road runs close to it (SPEC 49).
func _bake_tyre_walls(paint: MeshPaint) -> void:
	var s := world_size
	var m := BARRIER_MARGIN
	var inset := TYRE_WALL_R * 0.55
	var x := TYRE_WALL_STEP * 0.5
	while x < s.x:
		if is_tyre_wall(Vector2(x, m)):
			_bake_wall_tyre(paint, Vector2(x, m - inset))
		if is_tyre_wall(Vector2(x, s.y - m)):
			_bake_wall_tyre(paint, Vector2(x, s.y - m + inset))
		x += TYRE_WALL_STEP
	var y := m + TYRE_WALL_STEP * 0.5
	while y < s.y - m:
		if is_tyre_wall(Vector2(m, y)):
			_bake_wall_tyre(paint, Vector2(m - inset, y))
		if is_tyre_wall(Vector2(s.x - m, y)):
			_bake_wall_tyre(paint, Vector2(s.x - m + inset, y))
		y += TYRE_WALL_STEP


func _bake_wall_tyre(paint: MeshPaint, at: Vector2) -> void:
	paint.add_circle(at, TYRE_WALL_R, TYRE_WALL_COLOR, 8)
	paint.add_circle(at, TYRE_WALL_R * 0.42, TYRE_WALL_RIM, 6)


## Samples each side of the barrier once and records where the road runs close to it (SPEC 49).
func _setup_tyre_walls() -> void:
	var s := world_size
	var m := BARRIER_MARGIN
	_wall_top = PackedByteArray()
	_wall_bottom = PackedByteArray()
	_wall_left = PackedByteArray()
	_wall_right = PackedByteArray()
	var nx := int(ceil(s.x / TYRE_WALL_STEP))
	for i in nx:
		var x := (float(i) + 0.5) * TYRE_WALL_STEP
		_wall_top.append(1 if distance_to_centerline(Vector2(x, m)) < TYRE_WALL_NEAR else 0)
		_wall_bottom.append(1 if distance_to_centerline(Vector2(x, s.y - m)) < TYRE_WALL_NEAR else 0)
	var ny := int(ceil(s.y / TYRE_WALL_STEP))
	for i in ny:
		var y := (float(i) + 0.5) * TYRE_WALL_STEP
		_wall_left.append(1 if distance_to_centerline(Vector2(m, y)) < TYRE_WALL_NEAR else 0)
		_wall_right.append(1 if distance_to_centerline(Vector2(s.x - m, y)) < TYRE_WALL_NEAR else 0)


## The baked ground (SPEC 54), or null before setup. One mesh: the whole track in one draw call.
func get_ground_mesh() -> ArrayMesh:
	return _ground


## True where the barrier is lined with tyres (SPEC 49), i.e. where the road passes close to the wall.
## `pos` is taken to the nearest side of the barrier -- it is asked at the moment a car is clamped there.
func is_tyre_wall(pos: Vector2) -> bool:
	if _wall_top.is_empty():
		return false
	var s := world_size
	var d_left := pos.x
	var d_right := s.x - pos.x
	var d_top := pos.y
	var d_bottom := s.y - pos.y
	var nearest := minf(minf(d_left, d_right), minf(d_top, d_bottom))
	if is_equal_approx(nearest, d_top):
		return _wall_top[clampi(int(pos.x / TYRE_WALL_STEP), 0, _wall_top.size() - 1)] == 1
	if is_equal_approx(nearest, d_bottom):
		return _wall_bottom[clampi(int(pos.x / TYRE_WALL_STEP), 0, _wall_bottom.size() - 1)] == 1
	if is_equal_approx(nearest, d_left):
		return _wall_left[clampi(int(pos.y / TYRE_WALL_STEP), 0, _wall_left.size() - 1)] == 1
	return _wall_right[clampi(int(pos.y / TYRE_WALL_STEP), 0, _wall_right.size() - 1)] == 1


## Faint gates across the road at every checkpoint, with the pending one highlighted, so the ordered
## checkpoint rule (a lap only counts when all of them are passed) is visible instead of invisible.
##
## Drawn into the separate `"Gates"` child at [constant GATES_Z], **above the skid marks**: the gates are
## UI-in-world, not paint, and the highlighted one is the only thing telling the player which checkpoint is
## outstanding. At the track's own z = 0 a few laps of rubber (alpha up to 0.75 at SkidMarks.GROUND_Z = 2)
## progressively darkened it away.
func draw_checkpoint_gates(target: CanvasItem) -> void:
	var n := centerline.size()
	if n < 3:
		return
	var hw := track_width * 0.5 - 2.0
	for k in _checkpoint_indices.size():
		var pending := k == _next_checkpoint
		if k == 0 and not pending:
			continue  # checkpoint 0 is the checkered start/finish strip
		var idx: int = _checkpoint_indices[k]
		var p: Vector2 = centerline[idx]
		var dir: Vector2 = (centerline[(idx + 1) % n] - centerline[posmod(idx - 1, n)]).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		target.draw_line(p + nrm * hw, p - nrm * hw, GATE_PENDING_COLOR if pending else GATE_COLOR,
				5.0 if pending else 3.0)
		if pending:
			# Chevrons at both gate posts, pointing the way through.
			for side in [1.0, -1.0]:
				var post: Vector2 = p + nrm * (hw * side)
				target.draw_line(post, post - nrm * (14.0 * side) + dir * 14.0, GATE_PENDING_COLOR, 4.0)


## Canvas item for the checkpoint gates, kept above the ground marks (see [method draw_checkpoint_gates]).
class GateLayer:
	extends Node2D

	var track: Node2D = null

	func _draw() -> void:
		if track != null and is_instance_valid(track):
			track.draw_checkpoint_gates(self)


func _setup_gate_layer() -> void:
	if _gate_layer == null or not is_instance_valid(_gate_layer):
		var found := get_node_or_null("Gates")
		if found is Node2D:
			_gate_layer = found
		else:
			var layer := GateLayer.new()
			layer.name = "Gates"
			layer.track = self
			_gate_layer = layer
			add_child(layer)
	_gate_layer.z_as_relative = false
	_gate_layer.z_index = GATES_Z
	_gate_layer.queue_redraw()


## The "Gates" child that draws the checkpoint gates (for tests / wiring checks).
func get_gate_layer() -> Node2D:
	return _gate_layer


func _bake_centre_dashes(paint: MeshPaint) -> void:
	var n := centerline.size()
	for i in range(0, n, 2):
		var a := centerline[i]
		var b := centerline[(i + 1) % n]
		paint.add_line(a, a.lerp(b, 0.6), 2.0, DASH_COLOR)


func _bake_start_line(paint: MeshPaint) -> void:
	var n := centerline.size()
	var p := centerline[0]
	var fwd := (centerline[1] - centerline[n - 1]).normalized()
	var angle := fwd.angle()
	var cols := 11
	var rows := 2
	var cell := track_width / float(cols)
	# Baked into world space (a mesh has no draw_set_transform), so each cell is rotated by hand.
	for r in rows:
		for c in cols:
			var color := Color.WHITE if (r + c) % 2 == 0 else Color(0.08, 0.08, 0.08)
			var x := -cell * rows * 0.5 + cell * r
			var y := -track_width * 0.5 + cell * c
			var a := p + Vector2(x, y).rotated(angle)
			var b := p + Vector2(x + cell, y).rotated(angle)
			var c2 := p + Vector2(x + cell, y + cell).rotated(angle)
			var d := p + Vector2(x, y + cell).rotated(angle)
			paint.add_quad(a, b, c2, d, color)


## Per-point unit normals (left-hand, rotated +90 deg) using averaged neighbour directions.
static func compute_normals(points: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var n := points.size()
	var normals := PackedVector2Array()
	normals.resize(n)
	for i in n:
		var prev: Vector2
		var next: Vector2
		if closed:
			prev = points[posmod(i - 1, n)]
			next = points[(i + 1) % n]
		else:
			prev = points[maxi(i - 1, 0)]
			next = points[mini(i + 1, n - 1)]
		var dir := (next - prev).normalized()
		normals[i] = Vector2(-dir.y, dir.x)
	return normals


## Draws a thick strip along a polyline as convex quads (no joint gaps).
static func draw_strip(canvas: CanvasItem, points: PackedVector2Array, closed: bool, half_width: float,
		color: Color, offset: Vector2 = Vector2.ZERO) -> void:
	var n := points.size()
	if n < 2:
		return
	var normals := compute_normals(points, closed)
	var seg_count := n if closed else n - 1
	var colors := PackedColorArray([color])
	for i in seg_count:
		var j := (i + 1) % n
		var quad := PackedVector2Array([
			points[i] + normals[i] * half_width + offset,
			points[j] + normals[j] * half_width + offset,
			points[j] - normals[j] * half_width + offset,
			points[i] - normals[i] * half_width + offset,
		])
		canvas.draw_polygon(quad, colors)


# ------------------------------------------------------------------ internals

func _compute_arc() -> void:
	var n := centerline.size()
	_arc = PackedFloat32Array()
	_arc.resize(n)
	var s := 0.0
	for i in n:
		_arc[i] = s
		s += centerline[i].distance_to(centerline[(i + 1) % n])
	_total_length = s


func _segment_distance(i: int, pos: Vector2) -> float:
	return _segment_nearest(i, pos).x


## Returns Vector2(distance, u) for segment i -> i+1 (cyclic), u = projection parameter 0..1.
func _segment_nearest(i: int, pos: Vector2) -> Vector2:
	var n := centerline.size()
	var a := centerline[i]
	var b := centerline[(i + 1) % n]
	var ab := b - a
	var len_sq := ab.length_squared()
	var u := 0.0
	if len_sq > 0.0:
		u = clampf((pos - a).dot(ab) / len_sq, 0.0, 1.0)
	return Vector2(pos.distance_to(a + ab * u), u)


func _cyclic_arc_distance(a: float, b: float) -> float:
	if _total_length <= 0.0:
		return absf(a - b)
	var d := fposmod(a - b, _total_length)
	return minf(d, _total_length - d)


func _point_at_arc(s: float) -> Vector2:
	var n := centerline.size()
	if n == 0:
		return Vector2.ZERO
	s = fposmod(s, _total_length)
	var i := _index_at_arc(s)
	var seg_len := centerline[i].distance_to(centerline[(i + 1) % n])
	var u := 0.0
	if seg_len > 0.0:
		u = clampf((s - _arc[i]) / seg_len, 0.0, 1.0)
	return centerline[i].lerp(centerline[(i + 1) % n], u)


## Index of the segment containing arc position s (binary search).
func _index_at_arc(s: float) -> int:
	var lo := 0
	var hi := centerline.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if _arc[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	return lo


func _nearest_index_at_arc(s: float) -> int:
	var n := centerline.size()
	s = fposmod(s, _total_length)
	var i := _index_at_arc(s)
	var j := (i + 1) % n
	var s_next := _arc[j] if j != 0 else _total_length
	return i if (s - _arc[i]) <= (s_next - s) else j


func _setup_bridge() -> void:
	_has_bridge = false
	_bridge_center = Vector2.ZERO
	_lower_arc = 0.0
	_upper_arc = 0.0
	_deck_half_length = 0.0
	_lower_zone_half = 0.0
	if not TrackData.has_bridge(track_id):
		return
	var n := centerline.size()
	for i in n:
		var a1 := centerline[i]
		var a2 := centerline[(i + 1) % n]
		for j in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue  # adjacent through the wrap
			var b1 := centerline[j]
			var b2 := centerline[(j + 1) % n]
			var hit: Variant = Geometry2D.segment_intersects_segment(a1, a2, b1, b2)
			if hit == null:
				continue
			var p: Vector2 = hit
			_has_bridge = true
			_bridge_center = p
			# Branch traversed first (lower indices) = lower road; second = upper bridge branch.
			_lower_arc = _arc[i] + a1.distance_to(p)
			_upper_arc = _arc[j] + b1.distance_to(p)
			_deck_half_length = track_width * BRIDGE_DECK_FACTOR * 0.5
			var sin_angle := absf((a2 - a1).normalized().cross((b2 - b1).normalized()))
			_lower_zone_half = (track_width * 0.5 + BridgeDeck.WALL_OUTSET + UPPER_ZONE_MARGIN) \
					/ maxf(sin_angle, 0.3)
			return


func _setup_checkpoints() -> void:
	_checkpoint_indices = PackedInt32Array()
	_checkpoint_positions = PackedVector2Array()
	var n := centerline.size()
	if n == 0:
		return
	var count: int = TrackRegistry.get_checkpoint_count(track_id)
	var spacing := _total_length / float(count)
	var used := {}
	for k in count:
		var s := spacing * float(k)
		if k > 0 and _has_bridge:
			s = _shift_out_of_bridge_zone(s)
		var idx := 0 if k == 0 else _nearest_index_at_arc(s)
		if used.has(idx):
			continue
		used[idx] = true
		_checkpoint_indices.append(idx)
		_checkpoint_positions.append(centerline[idx])


func _shift_out_of_bridge_zone(s: float) -> float:
	var zone := _deck_half_length + CHECKPOINT_BRIDGE_MARGIN
	for center in [_lower_arc, _upper_arc]:
		var c: float = center
		var d := fposmod(s - c, _total_length)   # distance ahead of the crossing
		if d <= zone:
			return fposmod(c + zone + 1.0, _total_length)
		if _total_length - d <= zone:
			return fposmod(c - zone - 1.0, _total_length)
	return s


func _setup_bridge_deck_node() -> void:
	if _has_bridge:
		if _bridge_deck == null or not is_instance_valid(_bridge_deck):
			_bridge_deck = BridgeDeck.new()
			_bridge_deck.name = "BridgeDeck"
			add_child(_bridge_deck)
		_bridge_deck.z_index = BRIDGE_DECK_Z
		_bridge_deck.set_deck(get_bridge_deck_points(), track_width)
	elif _bridge_deck != null:
		if is_instance_valid(_bridge_deck):
			remove_child(_bridge_deck)
			_bridge_deck.free()
		_bridge_deck = null


# ------------------------------------------------------------------ sand traps

## "sand" when `pos` is inside a sand trap, else "grass". Only meaningful off the road (the car asks only
## then); side-effect free.
func get_surface_at(pos: Vector2) -> String:
	return "sand" if is_point_in_sand(pos) else "grass"


func is_point_in_sand(pos: Vector2) -> bool:
	for t in _sand_bounds.size():
		if not _sand_bounds[t].has_point(pos):
			continue
		for q in _sand_quads.size():
			if _sand_trap_of_quad[q] == t and Geometry2D.is_point_in_polygon(pos, _sand_quads[q]):
				return true
	return false


func get_sand_trap_count() -> int:
	return _sand_bounds.size()


## Car hook: the surface under the car while it is off the road.
func make_surface_provider() -> Callable:
	return func(pos: Vector2) -> String: return get_surface_at(pos)


func _setup_sand() -> void:
	_sand_quads.clear()
	_sand_trap_of_quad = PackedInt32Array()
	_sand_bounds.clear()
	var n := centerline.size()
	if n < 24:
		return
	# Signed curvature radius per point from the heading change over +-3 points (> 0 = right-hander).
	var rad := PackedFloat32Array()
	rad.resize(n)
	var turn := PackedFloat32Array()
	turn.resize(n)
	for i in n:
		var a := centerline[posmod(i - 3, n)]
		var b := centerline[i]
		var c := centerline[(i + 3) % n]
		var d1 := b - a
		var d2 := c - b
		var ang := d1.angle_to(d2)
		var arc := (d1.length() + d2.length()) * 0.5
		turn[i] = ang
		rad[i] = arc / maxf(absf(ang), 0.0001)
	# Corner runs: consecutive points under the radius; one trap at each run's tightest point.
	var in_corner := func(i: int) -> bool: return rad[i] < SAND_CORNER_RADIUS
	var start := -1
	for i in n:
		if not in_corner.call(i):
			start = i
			break
	if start < 0:
		return          # all corner (a circle): no straight to anchor on
	var apexes: Array[int] = []
	var k := 0
	while k < n:
		var i := (start + k) % n
		if in_corner.call(i):
			var best := i
			var j := k
			while j < n and in_corner.call((start + j) % n):
				var idx := (start + j) % n
				if rad[idx] < rad[best]:
					best = idx
				j += 1
			apexes.append(best)
			k = j
		else:
			k += 1
	var hw := track_width * 0.5
	var inner_off := hw + EDGE_BAND + 2.0
	for apex in apexes:
		# Skip the figure-8 crossing: sand under a bridge would be nonsense.
		if _has_bridge and (is_index_on_upper_branch_zone(apex) or is_index_on_lower_branch_zone(apex)):
			continue
		var outside := -signf(turn[apex])       # outside of a right-hander is to the LEFT
		var inner := PackedVector2Array()
		var outer := PackedVector2Array()
		var valid: Array[bool] = []
		var max_depth := 0.0
		for o in range(-SAND_HALF_SPAN, SAND_HALF_SPAN + 1):
			var i := posmod(apex + o, n)
			var dir := (centerline[(i + 1) % n] - centerline[posmod(i - 1, n)]).normalized()
			var nrm := Vector2(-dir.y, dir.x) * outside
			var taper := sin(PI * float(o + SAND_HALF_SPAN + 1) / float(2 * SAND_HALF_SPAN + 2))
			var depth := SAND_DEPTH * taper
			var p_in := centerline[i] + nrm * inner_off
			# Shrink until the outer edge is clear of every other part of the road and of the barrier.
			while depth > 0.0:
				var p_out := p_in + nrm * depth
				if _sand_point_ok(p_out, hw, SAND_ROAD_GAP) and _sand_point_ok(p_in + nrm * depth * 0.5, hw, SAND_ROAD_GAP):
					break
				depth -= 6.0
			depth = maxf(depth, 0.0)
			var ok := _sand_point_ok(p_in, hw, 1.0)
			valid.append(ok)
			if ok:
				max_depth = maxf(max_depth, depth)
			inner.append(p_in)
			outer.append(p_in + nrm * (depth if ok else 0.0))
		if max_depth < 24.0:
			continue
		# Quads only between two valid samples: a trap is cut wherever its inner edge would leave the
		# grass (another road, or the barrier), never stretched across it.
		var trap := _sand_bounds.size()
		var box := Rect2()
		var any := false
		for q in inner.size() - 1:
			if not (valid[q] and valid[q + 1]):
				continue
			var quad := PackedVector2Array([inner[q], inner[q + 1], outer[q + 1], outer[q]])
			_sand_quads.append(quad)
			_sand_trap_of_quad.append(trap)
			for pt in quad:
				box = Rect2(pt, Vector2.ZERO) if not any else box.expand(pt)
				any = true
		if any:
			_sand_bounds.append(box.grow(1.0))


## A sand point must sit off every part of the road (plus the white band and a gap) and inside the barrier.
func _sand_point_ok(p: Vector2, hw: float, gap: float) -> bool:
	var m := BARRIER_MARGIN + 4.0
	if p.x < m or p.y < m or p.x > world_size.x - m or p.y > world_size.y - m:
		return false
	return distance_to_centerline(p) >= hw + EDGE_BAND + gap


func _bake_sand(paint: MeshPaint) -> void:
	for q in _sand_quads:
		paint.add_quad(q[0], q[1], q[2], q[3], SAND_COLOR)
	# A few darker grains per quad, at fixed positions, so the sand reads as sand.
	for qi in _sand_quads.size():
		var q: PackedVector2Array = _sand_quads[qi]
		for g in 3:
			var u := fposmod(float(qi * 7 + g * 3) * 0.37, 1.0)
			var v := fposmod(float(qi * 5 + g * 11) * 0.23, 1.0)
			var p := q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), v)
			paint.add_circle(p, 1.6, SAND_DOT_COLOR, 6)
