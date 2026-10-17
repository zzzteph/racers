class_name GuideArrow
extends Node2D
## WHICH WAY (SPEC 111). Three chevrons on the road, pulsing, that say where to go: ahead of the car along
## the track through the countdown and the first seconds of a race ("the starting direction is not
## clear"); turned round when the car is driving against the track ("not clear how to get back on track
## after a wrong way"); pointing at the road when the car has been on the grass for a while.
##
## World space, under the HUD: it is drawn on the tarmac, where the eye already is. The chevrons are
## baked once per KIND; the pulse and the creep are `modulate` and `position`, never a redraw (SPEC 109).

enum Kind { START, WRONG_WAY, TO_ROAD, CHECKPOINT }

const COLORS := {
	Kind.START: Color(1.0, 0.92, 0.35),
	Kind.WRONG_WAY: Color(1.0, 0.36, 0.25),
	Kind.TO_ROAD: Color(1.0, 0.72, 0.30),
	Kind.CHECKPOINT: Color(1.0, 0.5, 0.2),
}
## "Show with a BIG arrow where they need to go": the corrections are half as big again as the start arrow.
const SCALES := {
	Kind.START: 1.0,
	Kind.WRONG_WAY: 1.5,
	Kind.TO_ROAD: 1.25,
	Kind.CHECKPOINT: 1.5,
}
const CHEVRONS := 3
const STEP := 24.0          # px between chevrons, along the arrow
const HALF_H := 16.0        # half the height of a chevron
const DEPTH := 12.0         # how far the point sits ahead of the tails
const LINE_W := 6.0
const OUTLINE_W := 10.0
const PULSE_HZ := 1.6
const CREEP_PX := 10.0      # the chevrons creep forward and reset: motion says "this way"

var kind: int = Kind.START
var _age: float = 0.0
var _anchor: Vector2 = Vector2.ZERO


func _ready() -> void:
	z_index = 45
	visible = false


## Shows the arrow at `at`, pointing `angle` radians, in the colour of `what`.
func show_at(at: Vector2, angle: float, what: int) -> void:
	_anchor = at
	rotation = angle
	if what != kind:
		kind = what
		scale = Vector2.ONE * float(SCALES.get(kind, 1.0))
		queue_redraw()
	if not visible:
		_age = 0.0
		visible = true
	position = _anchor + Vector2.from_angle(angle) * _creep()


func hide_guide() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_age += delta
	var pulse := 0.62 + 0.38 * (0.5 + 0.5 * sin(_age * TAU * PULSE_HZ))
	modulate = Color(1.0, 1.0, 1.0, pulse)
	position = _anchor + Vector2.from_angle(rotation) * _creep()


func _creep() -> float:
	return fmod(_age * 28.0, CREEP_PX * 2.0) - CREEP_PX


func _draw() -> void:
	var c: Color = COLORS.get(kind, Color.WHITE)
	var outline := Color(0.05, 0.05, 0.06, 0.75)
	for i in CHEVRONS:
		var x := (float(i) - float(CHEVRONS - 1) * 0.5) * STEP
		var pts := PackedVector2Array([Vector2(x - DEPTH, -HALF_H), Vector2(x, 0.0), Vector2(x + DEPTH * 0.0 - DEPTH, HALF_H)])
		pts[1] = Vector2(x + DEPTH * 0.5, 0.0)
		pts[0] = Vector2(x - DEPTH * 0.5, -HALF_H)
		pts[2] = Vector2(x - DEPTH * 0.5, HALF_H)
		draw_polyline(pts, outline, OUTLINE_W, true)
		var fade := 0.55 + 0.45 * float(i) / float(maxi(CHEVRONS - 1, 1))
		draw_polyline(pts, Color(c.r, c.g, c.b, fade), LINE_W, true)
