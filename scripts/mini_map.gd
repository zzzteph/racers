class_name MiniMap
extends Node2D
## The track, small, in the corner (SPEC 50). Only the CLOSE CAMERA mode needs it: zoomed in on the car
## you can see the detail of the road but not where you are on it, so the whole circuit is drawn here with
## a dot per car -- yours white and a little bigger.
##
## Lives in the HUD's CanvasLayer, so it is in screen coordinates and the chase camera never moves it.
## Pure consumer: Race pushes the dots in every frame (`set_dots`), exactly like the rest of the HUD.

const RECT := Rect2(1064, 96, 204, 122)     # under the lap flash, clear of the pause button
const BG_COLOR := Color(0.05, 0.06, 0.07, 0.62)
const EDGE_COLOR := Color(1, 1, 1, 0.22)
const ROAD_COLOR := Color(0.72, 0.75, 0.78, 0.55)
const ROAD_WIDTH := 3.0
const DOT_R := 2.6
const PLAYER_DOT_R := 3.6
const PADDING := 10.0

var _line: PackedVector2Array = PackedVector2Array()     # the centerline, already in screen coordinates
var _dots: Array = []                                    # [{pos: Vector2 (world), color: Color, me: bool}]
var _scale: float = 1.0
var _origin: Vector2 = Vector2.ZERO
## SPEC 65: the lobby draws the chosen track with this, in a box of its own choosing.
var _box: Rect2 = RECT


func _ready() -> void:
	z_index = 50


## SPEC 111: the box the map occupies on screen, for the overlap audit (see RaceBoard.audit_rect).
func audit_rect() -> Rect2:
	return _box if visible and not _line.is_empty() else Rect2()


func audit_text() -> String:
	return "minimap"


## The track to draw, fitted into RECT once. `world` is the size of the world the track lives in.
## Where this map is drawn, in the parent's coordinates. Defaults to the in-race corner.
func set_box(box: Rect2) -> void:
	_box = box
	queue_redraw()


func setup(centerline: PackedVector2Array, world: Vector2) -> void:
	_line = PackedVector2Array()
	if world.x <= 0.0 or world.y <= 0.0:
		return
	var inner := _box.grow(-PADDING)
	_scale = minf(inner.size.x / world.x, inner.size.y / world.y)
	_origin = inner.position + (inner.size - world * _scale) * 0.5
	for p in centerline:
		_line.append(_origin + p * _scale)
	queue_redraw()


## Every car on the map this frame, in world coordinates.
func set_dots(dots: Array) -> void:
	_dots = dots
	queue_redraw()


func to_map(world_pos: Vector2) -> Vector2:
	return _origin + world_pos * _scale


func _draw() -> void:
	if _line.size() < 2:
		return
	draw_rect(_box, BG_COLOR)
	draw_rect(_box, EDGE_COLOR, false, 1.0)
	var closed := _line.duplicate()
	closed.append(_line[0])
	draw_polyline(closed, ROAD_COLOR, ROAD_WIDTH, true)
	for d in _dots:
		var me := bool(d.get("me", false))
		var at := to_map(d["pos"] as Vector2)
		if me:
			draw_circle(at, PLAYER_DOT_R + 1.4, Color(0, 0, 0, 0.65))
		draw_circle(at, PLAYER_DOT_R if me else DOT_R, d["color"] as Color)
