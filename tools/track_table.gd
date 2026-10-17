extends SceneTree
## EVERY CIRCUIT'S NUMBERS, in one table (SPEC 117): how long it is, how many corners it has, how tight
## the tightest one is, how big a world it needs and how much of the lap is spent at full throttle.
##   godot --headless --path . --script res://tools/track_table.gd
##
## Written to answer "which of these are the same track twice?" -- the question that cut the list from
## twelve circuits to five. Two tracks with the same length, the same corner count and the same minimum
## radius are the same drive whatever their scenery says.
func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.settings_path = "user://tool_settings.cfg"
	print("")
	print("%-14s %-22s %7s %6s %9s %10s %9s  %-18s %s" % ["id", "name", "metres", "turns",
			"tightest", "straight", "world", "shape", "biggest empty patch"])
	for id in TrackRegistry.ids():
		var sid := String(id)
		var stats := TrackRegistry.get_stats(sid)
		var pts := TrackData.get_centerline(sid)
		print("%-14s %-22s %7.0f %6d %9.0f %10.0f %9s  %-18s %s" % [sid, TrackRegistry.get_display_name(sid),
				float(stats.get("length_m", 0.0)), int(stats.get("corners", 0)),
				float(stats.get("min_radius", 0.0)), float(stats.get("longest_straight", 0.0)),
				"%dx%d" % [TrackRegistry.get_world_size(sid).x, TrackRegistry.get_world_size(sid).y],
				"%s %s" % [_shape(pts), _fills(pts, TrackRegistry.get_world_size(sid))],
			_hole(pts, TrackRegistry.get_world_size(sid), TrackRegistry.get_width(sid))])
	quit(0)


## A one-word shape: how round the line is (its area against the area of a circle with the same
## perimeter). 1.0 is a circle; a long thin track is near 0.
func _shape(pts: PackedVector2Array) -> String:
	if pts.size() < 8:
		return "-"
	var area := 0.0
	var per := 0.0
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		area += a.cross(b) * 0.5
		per += a.distance_to(b)
	area = absf(area)
	var round_ness := 4.0 * PI * area / maxf(per * per, 1.0)
	if round_ness > 0.55:
		return "round"
	if round_ness > 0.3:
		return "square"
	return "long"


## How much of the WORLD the circuit actually uses: the centreline's bounding box against the world
## rectangle, per axis. "94x52" is a track that fills the width and wastes half the height.
func _fills(pts: PackedVector2Array, world: Vector2) -> String:
	if pts.is_empty():
		return "-"
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return "%.0fx%.0f%%" % [100.0 * (hi.x - lo.x) / maxf(world.x, 1.0),
			100.0 * (hi.y - lo.y) / maxf(world.y, 1.0)]


## SPEC 121: THE BIGGEST PIECE OF THE WORLD THE ROAD NEVER GOES NEAR -- the question "it has half the
## screen not occupied" actually asks. The bounding box above says nothing about a hole in the MIDDLE of
## a circuit, which is exactly what the Switchback and the Serpent had.
##
## The world is cut into `GRID` squares; a square is "road" if any centreline sample is within half a
## road width plus a square's diagonal of its centre. The answer is the largest axis-aligned rectangle of
## empty squares, as a percentage of the world and in world px -- a number that can be driven down and
## then held by a test, rather than argued about from a screenshot.
const GRID := 40


func _hole(pts: PackedVector2Array, world: Vector2, width: float) -> String:
	if pts.is_empty() or world.x < 1.0 or world.y < 1.0:
		return "-"
	var cols := GRID
	var rows := maxi(int(round(float(GRID) * world.y / world.x)), 4)
	var cw := world.x / float(cols)
	var ch := world.y / float(rows)
	var reach := width * 0.5 + sqrt(cw * cw + ch * ch) * 0.5
	var free := []
	for r in rows:
		var row := []
		for c in cols:
			row.append(true)
		free.append(row)
	# Every sample paints the squares its road covers. A sample every SAMPLE_SPACING px is far finer
	# than a square, so stamping a disc of `reach` around each one leaves no gaps along the road.
	var span_c := int(ceil(reach / cw))
	var span_r := int(ceil(reach / ch))
	for p in pts:
		var pc := int(p.x / cw)
		var pr := int(p.y / ch)
		for r in range(maxi(pr - span_r, 0), mini(pr + span_r + 1, rows)):
			for c in range(maxi(pc - span_c, 0), mini(pc + span_c + 1, cols)):
				var mid := Vector2((float(c) + 0.5) * cw, (float(r) + 0.5) * ch)
				if mid.distance_to(p) <= reach:
					free[r][c] = false
	# Largest all-empty rectangle: the standard histogram sweep, one row at a time.
	var heights := []
	for c in cols:
		heights.append(0)
	var best := 0
	var best_w := 0
	var best_h := 0
	for r in rows:
		for c in cols:
			heights[c] = (int(heights[c]) + 1) if bool(free[r][c]) else 0
		for c in cols:
			var h: int = int(heights[c])
			if h == 0:
				continue
			var wcells := 0
			for k in range(c, cols):
				if int(heights[k]) < h:
					break
				wcells += 1
			if h * wcells > best:
				best = h * wcells
				best_w = wcells
				best_h = h
	var share := 100.0 * float(best) / float(cols * rows)
	return "%.0f%%  %.0fx%.0f px" % [share, float(best_w) * cw, float(best_h) * ch]
