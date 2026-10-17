@tool
class_name MapTrack
extends Node2D
## A HAND-DRAWN CIRCUIT (SPEC 78, SPEC 111). A track is one line -- the middle of the road -- so that is
## what this is: a `Path2D` you draw with the curve tool, plus how wide the road is and how many laps.
## SPEC 111 adds what stands beside it: `MapBlock` children are buildings (solid; the rope bends round
## them), `MapProp` children are cones, tyre stacks and oil drums (an oil drum is a permanent slick).
##
## Making one (docs/MAPPING.md, part 2, is the long version):
##   1. Duplicate `scenes/tracks/_template.tscn` (a file whose name starts with "_" is a template and
##      is never listed), rename it `<name>.tscn` -- or Scene > New Scene > Other Node > MapTrack.
##   2. Select the Path2D child and draw the centreline. CLOSE THE LOOP -- put the last point on the
##      first one. The first point is the start line; the curve's direction is the way the race runs.
##   3. Set `display_name`, `track_width`, `laps` and `accent` on the root. Drop MapBlock and MapProp
##      nodes where you want them. Turn `auto_props` off if you want only the props you placed.
##   4. `godot --headless --path . --script res://tools/check_map.gd -- --track <name>` measures it and
##      says whether it can be driven; the root node's warning triangle says the same in the editor.
## It then appears in the track list under "Yours".
##
## The one thing worth understanding before drawing: a corner's difficulty is its RADIUS against the road
## WIDTH, and a corner of `turn` degrees at radius R eats `R * tan(turn/2)` of straight at each end. Draw
## a hairpin too close to the corner before it and there is no room left for either.

## Below this the corner is tighter than a car can take at any useful speed, and the track is refused.
const MIN_RADIUS := 70.0
## How finely the curve is sampled into the centreline the game drives on.
const SAMPLE_SPACING := 16.0
## Space kept around the circuit when working out how big the world is.
const MARGIN := 140.0
## A building must keep this much grass between itself and the edge of the road.
const BLOCK_CLEAR := 12.0
## The road must keep this far from the world's top-left corner (the world starts at 0,0).
const EDGE_CLEAR := 60.0
## The MapProp kinds a circuit knows what to do with, and what the race calls them.
const PROP_KINDS := {
	MapProp.Kind.CONE: "cone",
	MapProp.Kind.TYRES: "tyres",
	MapProp.Kind.OIL_DRUM: "oil",
}

@export var display_name: String = "My Circuit"
## How wide the road is. 100-130 is the range the tracks that ship use.
@export_range(60.0, 220.0, 1.0) var track_width: float = 118.0:
	set(v):
		track_width = v
		queue_redraw()
@export_range(1, 20, 1) var laps: int = 3
## The colour this track is shown in on the menus.
@export var accent: Color = Color(0.45, 0.8, 1.0)
## Buildings and scenery along it, as the town tracks have (placed for you; your MapBlocks are added).
@export var town_scenery: bool = false
## Cones and tyre stacks at the corners, placed for you (SPEC 41). Off: only the props you placed.
@export var auto_props: bool = true


func _ready() -> void:
	if Engine.is_editor_hint() and get_path_node() == null:
		# A track scene with no line in it is no use, so make the line.
		var p := Path2D.new()
		p.name = "Path2D"
		p.curve = Curve2D.new()
		add_child(p)
		p.owner = self
	queue_redraw()


func get_path_node() -> Path2D:
	for c in get_children():
		if c is Path2D:
			return c as Path2D
	return null


## The centreline the game drives on: the curve, sampled evenly, in world coordinates.
func get_centerline() -> PackedVector2Array:
	var out := PackedVector2Array()
	var p := get_path_node()
	if p == null or p.curve == null or p.curve.point_count < 3:
		return out
	var baked := p.curve.get_baked_points()
	if baked.size() < 3:
		return out
	var offset := p.global_position
	# Even spacing: the whole game (progress, checkpoints, the AI's line) assumes samples are evenly
	# spaced, and a hand-drawn curve is anything but.
	var pts := PackedVector2Array()
	var carry := 0.0
	var prev: Vector2 = baked[0] + offset
	pts.append(prev)
	for i in range(1, baked.size()):
		var cur: Vector2 = baked[i] + offset
		var seg := prev.distance_to(cur)
		while carry + seg >= SAMPLE_SPACING:
			var t := (SAMPLE_SPACING - carry) / maxf(seg, 0.0001)
			prev = prev.lerp(cur, t)
			pts.append(prev)
			seg = prev.distance_to(cur)
			carry = 0.0
		carry += seg
		prev = cur
	# A closed loop: drop the last sample if it lands on top of the first.
	if pts.size() > 2 and pts[0].distance_to(pts[pts.size() - 1]) < SAMPLE_SPACING * 0.6:
		pts.remove_at(pts.size() - 1)
	return pts


## How big a world this circuit needs: the far edge of the line, plus room for the road and the run-off
## (the world starts at 0,0, so a line drawn away from the corner simply makes a bigger world).
func get_world_size() -> Vector2:
	var pts := get_centerline()
	if pts.is_empty():
		return Vector2(1280, 720)
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	for b in get_blocks():
		box = box.merge(b)
	var pad := track_width * 0.5 + MARGIN
	return (box.end + Vector2(pad, pad)).max(Vector2(1280, 720))


# ---------------------------------------------------------------- what stands beside the road (SPEC 111)

## Every MapBlock in the scene, as the rectangles the cars and the rope meet.
func get_blocks() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for n in _all(MapBlock):
		out.append((n as MapBlock).get_rect())
	return out


## Every MapBlock as the town draws them: {rect, color, lift, name}.
func get_block_items() -> Array:
	var out: Array = []
	for n in _all(MapBlock):
		var b := n as MapBlock
		out.append({"rect": b.get_rect(), "color": b.color, "lift": b.height, "name": String(b.name)})
	return out


## Every MapProp the race knows what to do with: {kind: "cone" | "tyres" | "oil", pos, name}.
func get_props() -> Array:
	var out: Array = []
	for n in _all(MapProp):
		var p := n as MapProp
		if PROP_KINDS.has(p.kind):
			out.append({"kind": String(PROP_KINDS[p.kind]), "pos": p.global_position, "name": String(p.name)})
	return out


## Everything the race reads off the scene, in one dictionary (cached by the registry).
func get_items() -> Dictionary:
	return {"blocks": get_block_items(), "props": get_props(), "auto_props": auto_props}


func _all(type: Variant) -> Array:
	var out: Array = []
	_collect(self, type, out)
	return out


func _collect(node: Node, type: Variant, out: Array) -> void:
	for c in node.get_children():
		if is_instance_of(c, type):
			out.append(c)
		_collect(c, type, out)


## The tightest corner on the circuit, in pixels of radius (INF when it is all straight). Measured from
## three consecutive samples: the radius of the circle through them.
func tightest_radius() -> float:
	var pts := get_centerline()
	var n := pts.size()
	if n < 5:
		return INF
	var best := INF
	for i in n:
		var a: Vector2 = pts[(i - 2 + n) % n]
		var b: Vector2 = pts[i]
		var c: Vector2 = pts[(i + 2) % n]
		var ab := a.distance_to(b)
		var bc := b.distance_to(c)
		var ca := c.distance_to(a)
		var area := absf((b - a).cross(c - a)) * 0.5
		if area < 0.01:
			continue
		best = minf(best, ab * bc * ca / (4.0 * area))
	return best


## Everything wrong with the circuit. Empty = drivable.
func validate() -> PackedStringArray:
	var out := PackedStringArray()
	var pts := get_centerline()
	# The tightest corner first: a circuit so small it samples to a handful of points is TIGHT, not
	# unfinished, and being told "draw a full lap" when the lap is drawn helps nobody.
	var tight := tightest_radius()
	if tight < MIN_RADIUS:
		out.append("The tightest corner has a radius of %.0f px -- under %.0f no car can take it."
				% [tight, MIN_RADIUS])
	if pts.size() < 24:
		out.append("The line has %d points: draw a full lap with the Path2D's curve tool." % pts.size())
		return out
	var p := get_path_node()
	var closed := pts[0].distance_to(pts[pts.size() - 1]) < track_width
	if p != null and p.curve != null:
		var first: Vector2 = p.curve.get_point_position(0)
		var last: Vector2 = p.curve.get_point_position(p.curve.point_count - 1)
		closed = closed or first.distance_to(last) < track_width
	if not closed:
		out.append("The loop does not close: the last point of the curve must meet the first.")
	if _crosses_itself(pts):
		out.append("The line crosses itself. A crossing needs a bridge, which a hand-drawn track has no way to say.")
	# The world starts at (0,0): a road drawn past the top or left edge has no run-off there.
	var edge := track_width * 0.5 + EDGE_CLEAR
	var min_x := INF
	var min_y := INF
	for q in pts:
		min_x = minf(min_x, q.x)
		min_y = minf(min_y, q.y)
	if min_x < edge or min_y < edge:
		out.append("The road runs too close to the top-left corner of the world (x %.0f, y %.0f): move the whole line so it stays %.0f px from x=0 and y=0."
				% [min_x, min_y, edge])
	# SPEC 111: a building on the road is a wall across the race.
	var clear := track_width * 0.5 + BLOCK_CLEAR
	for it in get_block_items():
		var r: Rect2 = it["rect"]
		if _rect_near_line(pts, r, clear):
			out.append("Building '%s' sits on the road: keep it %.0f px off the tarmac." % [String(it["name"]), BLOCK_CLEAR])
	return out


## Advice, not refusals.
func notes() -> PackedStringArray:
	var out := PackedStringArray()
	var pts := get_centerline()
	if pts.size() < 24:
		return out
	var length := 0.0
	for i in pts.size():
		length += pts[i].distance_to(pts[(i + 1) % pts.size()])
	if length < 2200.0:
		out.append("A lap is only %.0f px: short laps mean a lot of laps, so consider fewer." % length)
	var tight := tightest_radius()
	if tight < track_width:
		out.append("The tightest corner (%.0f px) is tighter than the road is wide -- that is a hairpin."
				% tight)
	var box := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		box = box.expand(q)
	if box.position.x > 700.0 or box.position.y > 500.0:
		out.append("The line starts %.0f px right and %.0f px down from the corner: that is all empty world. Move it toward (0,0)."
				% [box.position.x, box.position.y])
	# SPEC 111: what a circuit does with the things you placed.
	for n in _all(MapProp):
		var mp := n as MapProp
		if not PROP_KINDS.has(mp.kind):
			out.append("'%s' is a %s: on a circuit only CONE, TYRES and OIL_DRUM stand, so it is ignored."
					% [String(mp.name), String(MapProp.Kind.keys()[mp.kind])])
	var hw := track_width * 0.5
	for it in get_props():
		if _distance_to_line(pts, it["pos"]) < hw:
			out.append("'%s' stands on the road itself." % String(it["name"]))
	return out


## Does the centreline cross itself? Segment against segment, skipping neighbours.
static func _crosses_itself(pts: PackedVector2Array) -> bool:
	var n := pts.size()
	for i in n:
		var a1: Vector2 = pts[i]
		var a2: Vector2 = pts[(i + 1) % n]
		for j in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue
			var b1: Vector2 = pts[j]
			var b2: Vector2 = pts[(j + 1) % n]
			if Geometry2D.segment_intersects_segment(a1, a2, b1, b2) != null:
				return true
	return false


## Distance from `p` to the closed polyline.
static func _distance_to_line(pts: PackedVector2Array, p: Vector2) -> float:
	var n := pts.size()
	var best := INF
	for i in n:
		var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % n])
		best = minf(best, q.distance_to(p))
	return best


## True when any corner, edge midpoint or the centre of `r` is within `clear` of the line -- the outline,
## not only the centre, so a building's corner cannot poke onto the road.
static func _rect_near_line(pts: PackedVector2Array, r: Rect2, clear: float) -> bool:
	var probes := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y),
			r.get_center(), Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y),
			Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y)]
	for q in probes:
		if _distance_to_line(pts, q) < clear:
			return true
	return false


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var pts := get_centerline()
	if pts.size() < 3:
		return
	# The road, as it will actually be: the width is the whole difficulty of a corner, so draw it.
	var road := PackedVector2Array(pts)
	road.append(pts[0])
	draw_polyline(road, Color(0.16, 0.16, 0.18, 0.85), track_width, true)
	draw_polyline(road, Color(1, 1, 1, 0.25), 2.0, true)
	# The start line, and the way the race runs: a chevron every ~600 px along the curve's direction
	# (SPEC 111: "the starting direction is not clear" is true in the editor too).
	var n := pts.size()
	var fwd := (pts[1] - pts[0]).normalized()
	var side := Vector2(-fwd.y, fwd.x) * track_width * 0.5
	draw_line(pts[0] - side, pts[0] + side, Color(1, 1, 1, 0.9), 4.0)
	draw_circle(pts[0], 10.0, Color(0.45, 1.0, 0.55))
	var every := maxi(int(600.0 / SAMPLE_SPACING), 4)
	for i in range(every / 2, n, every):
		var d := (pts[(i + 2) % n] - pts[posmod(i - 2, n)]).normalized()
		var w := Vector2(-d.y, d.x)
		var tip := pts[i] + d * 14.0
		draw_polyline(PackedVector2Array([tip - d * 24.0 - w * 14.0, tip, tip - d * 24.0 + w * 14.0]),
				Color(1.0, 0.92, 0.35, 0.9), 5.0, true)


func _get_configuration_warnings() -> PackedStringArray:
	var out := validate()
	for n in notes():
		out.append(n)
	return out
