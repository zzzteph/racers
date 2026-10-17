class_name RopeLine
extends Node2D
## Visual "rope" from the car to its rope target (the cursor). Drawn in global coordinates (top_level).
##
## Always a straight line (SPEC 45). Every car's rope has its own thickness (`Car.rope_draw_width`); the
## colour reads the pull: grey and slack, warming to white as it tightens, GOLD with a glow while the cursor
## sits in the tension zone (the boost is charging), and RED once it drags the car. Near full length, two
## short ticks round the car mark where the zone starts and ends, so the sweet spot can be aimed at.

const SLACK_COLOR := Color(0.6, 0.6, 0.6)
const TAUT_COLOR := Color(0.95, 0.9, 0.8)
const ZONE_COLOR := Color(1.0, 0.78, 0.2)
const DRAG_COLOR := Color(0.95, 0.12, 0.08)
const TICK_HALF_LENGTH := 14.0    # px of arc either side of the rope's direction

var car: Car  # set by Car._ready

var _last_from: Vector2 = Vector2.ZERO
var _last_to: Vector2 = Vector2.ZERO
var _last_tension: float = -1.0
var _was_drawing: bool = false


func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = 100
	global_position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE


## Only dirties the canvas item when something it draws has actually changed. The FINISHED phase hides the
## rope and can sit on screen indefinitely, so an unconditional `queue_redraw()` re-dirtied an item that
## draws nothing 60 times a second; a held cursor during the countdown / resume hold did the same.
func _process(_delta: float) -> void:
	if car == null or not is_instance_valid(car) or not car.rope_visible:
		if _was_drawing:
			_was_drawing = false
			queue_redraw()
		return
	var from: Vector2 = car.rope_draw_anchor()
	var to := car.get_rope_target()
	var tension := car.get_rope_tension() + (2.0 if car.is_in_tension_zone() else 0.0) 			+ (4.0 if car.get_overpull() > 0.0 else 0.0) + (8.0 if car.rope_snap_enabled and car.is_rope_snapped() else 0.0)
	if _was_drawing and from == _last_from and to == _last_to and is_equal_approx(tension, _last_tension) \
			and car.get_overpull() <= 0.0:
		return
	_last_from = from
	_last_to = to
	_last_tension = tension
	_was_drawing = true
	queue_redraw()


func _draw() -> void:
	if car == null or not is_instance_valid(car) or not car.rope_visible:
		return
	var from: Vector2 = car.rope_draw_anchor()
	var to := car.get_rope_target()
	if car.rope_snap_enabled and car.is_rope_snapped():
		_draw_snapped(from, to)
		return
	var tension := car.get_rope_tension()
	var zone := car.is_in_tension_zone()
	var drag := car.get_overpull()
	var tinted := car.rope_tint.a > 0.0
	var color := SLACK_COLOR.lerp(TAUT_COLOR, tension)
	if tinted:
		# A rival's rope: its car's colour, fainter while slack.
		color = car.rope_tint.darkened(0.35).lerp(car.rope_tint.lightened(0.25), tension)
		color.a = lerpf(0.55, 0.9, tension)
	if zone:
		color = ZONE_COLOR
	if drag > 0.0:
		color = DRAG_COLOR
	# SPEC 110: the drift charge shows on the rope -- blue, orange, purple, the mini-turbo's tiers.
	var tier := car.boost_tier()
	if tier > 0 and not car.is_boosting():
		color = color.lerp(Car.TIER_COLORS[tier], 0.75)
	var width := lerpf(1.5, 4.0, tension) * maxf(car.rope_draw_width, 0.2) * (0.7 if tinted else 1.0)
	var d := from.distance_to(to)
	if d > 1.0:
		var pts := _rope_points(from, to, tension, drag)
		if zone:
			draw_polyline(pts, Color(ZONE_COLOR.r, ZONE_COLOR.g, ZONE_COLOR.b, 0.28), width + 5.0, true)
		draw_polyline(pts, color, width, true)
	if d > 1.0 or not tinted:
		draw_arc(to, 6.0 if tinted else 8.0, 0.0, TAU, 24, color, 2.0, true)
	# SPEC 136: the gear as PIPS round the cursor. The bands along the rope give the spatial sense, but
	# the rope is 2 px wide and six divisions along it is a finer scale than the eye can take at a
	# glance (measured: two rounds of screenshots). The cursor is where the eye already is -- it is the
	# thing being aimed -- and a pip meter there is a fixed size however long the rope is.
	if not tinted and d > car.slack_radius:
		_draw_gear_pips(from, to, d, color)
		_draw_gear_mark(from, to, d, color)
	if not tinted:
		_draw_zone_ticks(from, to, d)


## A snapped rope (SPEC 46): a frayed stub hanging off the car and a faint ring where the cursor is -- bring
## it back to the car to tie the rope on again.
func _draw_snapped(from: Vector2, to: Vector2) -> void:
	var dir := (to - from).normalized() if from.distance_to(to) > 1.0 else Vector2.RIGHT
	var stub := from + dir * 12.0
	draw_line(from, stub, DRAG_COLOR, 2.0, true)
	for k in 3:
		draw_line(stub, stub + dir.rotated(-0.6 + 0.6 * float(k)) * 5.0, DRAG_COLOR, 1.2, true)
	draw_arc(to, 8.0, 0.0, TAU, 24, Color(DRAG_COLOR.r, DRAG_COLOR.g, DRAG_COLOR.b, 0.45), 2.0, true)


## The rope as it lies: a straight line from the car to the cursor.
func _rope_points(from: Vector2, to: Vector2, _tension: float, _drag: float) -> PackedVector2Array:
	return PackedVector2Array([from, to])


## SPEC 136: THE GEARS, WHERE THE EYE IS. "I do not want the rope shorter -- but to have some idea about
## the speed."
##
## The rope's length has always BEEN the speed demand, and there has never been anything to read it
## against: 130 px out of a possible 180 looks exactly like 130 out of 400, so the only way to know what
## you were asking for was to already know the car by heart. The game's answer to "how fast" is already
## written and already tuned -- [Gearbox], a real six-speed with ratios, shift points and hysteresis --
## but it lives on the dashboard at the bottom of the screen, which nobody looks at while driving, and it
## reads the car's ACTUAL speed rather than the rope's demand.
##
## So the ladder is drawn twice, in the two places the eye actually is: as PIPS behind the cursor, which
## is the thing being aimed, and as ONE mark on the rope at the gear boundary just passed, which is what
## you aim BACK to when easing down a gear. Nothing about the physics changed.
##
## **What was tried and thrown away**: banding the whole rope, one band per gear, alternating bright and
## dim. It was measured by screenshot twice, strengthened once, and it never read -- the rope is 2 to 4 px
## wide, and six divisions along a thin line is a finer scale than the eye takes at a glance. The pips
## work because they are a FIXED SIZE however long the rope is. If a future round wants the ladder on the
## rope itself, the lesson is that the rope cannot carry a six-point scale; three zones might.
const GEAR_TICK_PX := 13.0        # px of arc either side of the rope, at the boundary just passed


## The one mark on the rope: a short arc across it at the top of the gear being asked for. The pips say
## WHICH gear; this says where on the rope it ends, which is the part you can steer by.
func _draw_gear_mark(from: Vector2, to: Vector2, d: float, color: Color) -> void:
	if car.speed_per_px <= 0.0:
		return
	var edge := 0.0
	for s in Gearbox.GEAR_TOP_SPEED:
		var r: float = car.slack_radius + float(s) / car.speed_per_px
		if r >= d:
			break
		edge = r
	if edge <= 0.0:
		return
	var a := (to - from).angle()
	var half := GEAR_TICK_PX / maxf(edge, 1.0)
	draw_arc(from, edge, a - half, a + half, 6, Color(color.r, color.g, color.b, 0.7), 2.0, true)


## Two short arcs round the car at the zone's inner and outer radius, in the rope's direction -- shown
## once the rope is out near its full length.
func _draw_zone_ticks(from: Vector2, to: Vector2, d: float) -> void:
	if not car.boost_enabled or not car.overpull_enabled:
		return
	var r := car.get_zone_radii()
	if d < r.x * 0.8:
		return
	var a := (to - from).angle()
	var alpha := clampf((d - r.x * 0.8) / (r.x * 0.2), 0.0, 1.0) * 0.8
	var col := Color(ZONE_COLOR.r, ZONE_COLOR.g, ZONE_COLOR.b, alpha)
	for radius in [r.x, r.y]:
		var half: float = TICK_HALF_LENGTH / maxf(radius, 1.0)
		draw_arc(from, radius, a - half, a + half, 6, col, 2.0, true)


## A short arc of pips just outside the cursor ring, lit up to the gear the rope is asking for, laid
## across the rope rather than along it so they never sit on the line.
const PIP_R := 15.0
const PIP_SPREAD := 1.9           # rad of arc the pips are spread over
const PIP_SIZE := 2.1


func _draw_gear_pips(from: Vector2, to: Vector2, d: float, color: Color) -> void:
	if car.speed_per_px <= 0.0:
		return
	var n: int = Gearbox.GEAR_TOP_SPEED.size()
	var lit := 0
	for s in Gearbox.GEAR_TOP_SPEED:
		if d >= car.slack_radius + float(s) / car.speed_per_px:
			lit += 1
	# Centred on the direction back toward the car, so the meter sits behind the cursor and the rope
	# runs between the pips and the car rather than through them.
	var base := (from - to).angle()
	for i in n:
		var f := (float(i) / float(n - 1) - 0.5) * PIP_SPREAD
		var at: Vector2 = to + Vector2.from_angle(base + f) * PIP_R
		var on := i < lit
		draw_circle(at, PIP_SIZE if on else PIP_SIZE * 0.8,
				Color(color.r, color.g, color.b, 0.95 if on else 0.34))
