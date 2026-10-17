class_name FieldCard
extends Node2D
## THE FIELD (SPEC 143): who you are racing, told on the grid. One line per rival -- its colour as a
## chip, the car, the personality it was dealt, and what that personality DOES in a dozen words -- so
## that a player "sees exactly what will be" before the lights go out, instead of finding out at the
## first corner that the red car is a Bully. Shown through the countdown and for a few seconds after GO,
## then it fades; the timing tower (RaceBoard) does not carry the personalities, and is not meant to.
##
## Lives in the HUD's CanvasLayer (screen coordinates) and is a pure consumer: Race pushes the rows in.

## Centred in the band under the dashboard, above the countdown number (Hud.COUNTDOWN_RECT starts at
## 230): the flash and hint slots live there, and both are idle on the grid -- the HUD hides this card
## the moment a flash needs the space. Under the number it covered the cars on the grid, which is the
## one thing a card about the cars on the grid must not do. The height grows with the field: five
## rivals (a full room) end at 268, still clear of the number.
const RECT := Rect2(200.0, 90.0, 856.0, 24.0)   # ends at 1056: clear of the minimap (1064)
const ROW_H := 30.0
const HEADER_H := 20.0
const PAD := 8.0
const BG_COLOR := Color(0.05, 0.06, 0.07, 0.78)
const EDGE_COLOR := Color(1, 1, 1, 0.16)
const TEXT_COLOR := Color(0.92, 0.94, 0.96)
const TELL_COLOR := Color(0.80, 0.83, 0.86)
const HEADER_COLOR := Color(0.70, 0.75, 0.80)
const FONT_SIZE := 17
const TELL_FONT_SIZE := 15
const HEADER_FONT_SIZE := 11
const CHIP := Vector2(11.0, 14.0)
const NAME_W := 170.0
const PERSONA_W := 92.0
const MAX_ROWS := 6

var _rows: Array = []          # [{name, color, persona, tell}]
var _alpha: float = 1.0


func _ready() -> void:
	z_index = 50


func set_rows(rows: Array) -> void:
	_rows = rows.slice(0, MAX_ROWS)
	queue_redraw()


func get_rows() -> Array:
	return _rows


## The card fades out after GO; 0 hides it.
func set_alpha(a: float) -> void:
	a = clampf(a, 0.0, 1.0)
	var show := a > 0.0
	if is_equal_approx(a, _alpha) and show == visible:
		return
	_alpha = a
	visible = show
	queue_redraw()


## Where it is on the screen, as drawn (for the layout checks).
func get_rect() -> Rect2:
	return Rect2(RECT.position, Vector2(RECT.size.x, HEADER_H + ROW_H * float(_rows.size()) + PAD))


func _draw() -> void:
	if _rows.is_empty() or _alpha <= 0.0:
		return
	var box := get_rect()
	draw_rect(box, Color(BG_COLOR, BG_COLOR.a * _alpha))
	draw_rect(box, Color(EDGE_COLOR, EDGE_COLOR.a * _alpha), false, 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, box.position + Vector2(PAD, 14.0), "THE FIELD",
			HORIZONTAL_ALIGNMENT_LEFT, -1, HEADER_FONT_SIZE, Color(HEADER_COLOR, _alpha))
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var y := box.position.y + HEADER_H + ROW_H * float(i)
		var base := Vector2(box.position.x + PAD, y + 20.0)
		var chip: Color = r.get("color", Color.WHITE)
		draw_rect(Rect2(Vector2(base.x, y + 7.0), CHIP), Color(chip.r, chip.g, chip.b, 0.9 * _alpha))
		draw_string(font, base + Vector2(18.0, 0.0), _fit(font, String(r.get("name", "")), NAME_W, FONT_SIZE),
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(TEXT_COLOR, _alpha))
		var persona := String(r.get("persona", ""))
		var x := base.x + 18.0 + NAME_W + 8.0
		if not persona.is_empty():
			draw_string(font, Vector2(x, base.y), persona.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1,
					TELL_FONT_SIZE, Color(chip.lightened(0.35), _alpha))
		x += PERSONA_W
		draw_string(font, Vector2(x, base.y), _fit(font, String(r.get("tell", "")), box.end.x - PAD - x, TELL_FONT_SIZE),
				HORIZONTAL_ALIGNMENT_LEFT, -1, TELL_FONT_SIZE, Color(TELL_COLOR, _alpha))


## `text`, trimmed with an ellipsis to fit `width` px at `size`.
static func _fit(font: Font, text: String, width: float, size: int) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
		return text
	var t := text
	while t.length() > 1 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		t = t.left(t.length() - 1)
	return t.strip_edges() + "…"
