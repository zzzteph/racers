class_name GarageEffects
extends Node2D
## The bought effects, shown on the car in the garage (SPEC 67). A cosmetic you cannot see before you buy
## it is a cosmetic nobody buys: clicking "Flames" lights them on the preview immediately, whether or not
## it has been paid for yet.
##
## This is NOT the in-race `CarEffects` -- there is no car here, no physics and no particle pool. It is a
## small looping animation drawn in the model's box: flames and smoke behind the car, stars around it, a
## pool of light under it. Deterministic in `_t`, so it looks the same every time the screen opens.

const FLAME_COLORS := [Color(1.0, 0.85, 0.3), Color(1.0, 0.55, 0.12), Color(0.9, 0.2, 0.05)]
const SMOKE_COLOR := Color(0.85, 0.85, 0.88)
const STAR_COLOR := Color(1.0, 0.95, 0.6)

var _box: Rect2 = Rect2()
var _effects: PackedStringArray = PackedStringArray()
var _tint: Color = Color(0.4, 0.7, 1.0)
var _t: float = 0.0
## The car's heading on the turntable, so the flames stay behind it as it turns (SPEC 67).
var _heading: float = 0.0


func _ready() -> void:
	z_index = 60


func _process(delta: float) -> void:
	if _effects.is_empty():
		return
	_t += delta
	queue_redraw()


## Where the car is drawn: the effects are placed around the middle of this box.
func set_box(box: Rect2) -> void:
	_box = box
	queue_redraw()


## Which effects to show, and the car's colour (the underglow and the smoke take it).
func set_effects(effects: PackedStringArray, tint: Color) -> void:
	_effects = effects
	_tint = tint
	queue_redraw()


## Where the car is pointing on the turntable.
func set_heading(heading: float) -> void:
	_heading = heading


func get_effects() -> PackedStringArray:
	return _effects


func _draw() -> void:
	if _effects.is_empty() or _box.size.x <= 0.0:
		return
	var mid := _box.get_center()
	# Behind the car, wherever the turntable has it pointing.
	var back := -Vector2.from_angle(_heading)
	var tail := mid + back * 46.0
	if _effects.has("underglow"):
		for ring in 4:
			var r := 74.0 - 13.0 * float(ring)
			var pulse := 0.10 + 0.05 * sin(_t * 2.4 + float(ring))
			draw_circle(mid, r, Color(_tint.r, _tint.g, _tint.b, pulse))
	if _effects.has("flames"):
		for i in 7:
			var phase := fposmod(_t * 2.2 + float(i) * 0.31, 1.0)
			var at := tail + back * (phase * 40.0) + back.orthogonal() * sin(float(i) * 2.1 + _t * 5.0) * 7.0
			var r2 := (9.0 - phase * 6.0) * (0.8 + 0.3 * sin(_t * 9.0 + float(i)))
			draw_circle(at, maxf(r2, 1.0),
					Color(FLAME_COLORS[i % 3].r, FLAME_COLORS[i % 3].g, FLAME_COLORS[i % 3].b,
					0.85 * (1.0 - phase)))
	if _effects.has("smoke"):
		for i in 6:
			var phase2 := fposmod(_t * 1.1 + float(i) * 0.17, 1.0)
			var side := -1.0 if i % 2 == 0 else 1.0
			var at2 := tail + back.orthogonal() * (side * 26.0) + back * (phase2 * 52.0)
			draw_circle(at2, 4.0 + phase2 * 12.0,
					Color(_tint.r * 0.7 + 0.3, _tint.g * 0.7 + 0.3, _tint.b * 0.7 + 0.3,
					0.30 * (1.0 - phase2)))
	if _effects.has("stars"):
		for i in 9:
			var a := _t * 1.3 + float(i) * TAU / 9.0
			var wob := 68.0 + 10.0 * sin(_t * 2.0 + float(i) * 1.7)
			var at3 := mid + Vector2.from_angle(a) * wob
			var twinkle := 0.45 + 0.55 * absf(sin(_t * 4.0 + float(i)))
			var s := 2.0 + 2.0 * twinkle
			draw_line(at3 - Vector2(s, 0), at3 + Vector2(s, 0), Color(STAR_COLOR, twinkle), 1.6)
			draw_line(at3 - Vector2(0, s), at3 + Vector2(0, s), Color(STAR_COLOR, twinkle), 1.6)
