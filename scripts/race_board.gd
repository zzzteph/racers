class_name RaceBoard
extends Node2D
## The running order (SPEC 55) as a TIMING TOWER (SPEC 108): every car on its own line, top to bottom,
## best first -- its place, its colour as a chip, the car's name, and the lap it is on -- with your own
## line picked out. It is what every racing game shows (F1, Forza, Gran Turismo, Wreckfest, Circuit
## Superstars): an order is a column, and a column reads at a glance.
##
## It sits in the tower column left of the world (`Hud.TOWER_W`), which the race leaves clear of
## the road (`Hud.WORLD_AREA`), so it never covers anything. SPEC 107's chips in a row were
## "very hard to understand"; SPEC 63's column in the corner sat on the track.
##
## Names are the CAR, not the colour: the chip is the colour, so "Blue Kart - Wildcard" reads "Kart"
## with a blue chip -- the way the cars on the road read.
##
## Lives in the HUD's CanvasLayer (screen coordinates) and is a pure consumer: Race pushes the order in,
## this only paints it.

const RECT := Rect2(8.0, 84.0, 184.0, 26.0)        # grows downward with the field
const ROW_H := 26.0
const HEADER_H := 18.0
const PAD := 6.0
const BG_COLOR := Color(0.05, 0.06, 0.07, 0.72)
const EDGE_COLOR := Color(1, 1, 1, 0.16)
const YOU_COLOR := Color(1.0, 0.82, 0.25, 0.18)
const TEXT_COLOR := Color(0.92, 0.94, 0.96)
const DIM_COLOR := Color(0.72, 0.76, 0.80)
const HEADER_COLOR := Color(0.70, 0.75, 0.80)
const FONT_SIZE := 15
const HEADER_FONT_SIZE := 11
const CHIP := Vector2(10.0, 13.0)
## SPEC 111: the top five and you ("the leaderboard should be limited -- top 5"); the rest of the field
## is on the results card.
const MAX_ROWS := 5

## What the board is a board OF: the running order.
var header: String = "ORDER"
var _rows: Array = []          # [{place, name, color, lap, laps, you, finished, out}]
var _signature: String = ""
var _models: Array = []        # the cars' names, so a colour word in front of one can be dropped


func _ready() -> void:
	z_index = 50
	for id in CarRegistry.ids():
		_models.append(CarRegistry.get_display_name(String(id)))


## The running order, best first. Only redraws when something actually reads differently.
func set_rows(rows: Array) -> void:
	var sig := ""
	for r in rows:
		sig += "%s|%d|%d|%d|%s;" % [String(r.get("name", "")),
				int(r.get("lap", 0)), int(r.get("down", 0)),
				1 if bool(r.get("finished", false)) else 0, "1" if bool(r.get("out", false)) else "0"]
	if sig == _signature:
		return
	_signature = sig
	_rows = rows
	queue_redraw()


func get_row_count() -> int:
	return _rows.size()


## How tall the tower is drawn.
func get_height() -> float:
	return HEADER_H + ROW_H * float(mini(_rows.size(), MAX_ROWS)) + PAD


## The lines that are shown: the first MAX_ROWS -- and you in the last slot if you are further down.
func shown_rows() -> Array:
	if _rows.size() <= MAX_ROWS:
		return _rows
	var out: Array = _rows.slice(0, MAX_ROWS)
	for r in _rows:
		if bool(r.get("you", false)) and not out.has(r):
			out[MAX_ROWS - 1] = r
	return out


func _draw() -> void:
	if _rows.is_empty():
		return
	var shown := shown_rows()
	var box := Rect2(RECT.position, Vector2(RECT.size.x, HEADER_H + ROW_H * float(shown.size()) + PAD))
	draw_rect(box, BG_COLOR)
	draw_rect(box, EDGE_COLOR, false, 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, box.position + Vector2(PAD, 13.0), header,
			HORIZONTAL_ALIGNMENT_LEFT, -1, HEADER_FONT_SIZE, HEADER_COLOR)
	for i in shown.size():
		var r: Dictionary = shown[i]
		var y := box.position.y + HEADER_H + ROW_H * float(i)
		var row := Rect2(box.position.x + 2.0, y, box.size.x - 4.0, ROW_H - 2.0)
		if bool(r.get("you", false)):
			draw_rect(row, YOU_COLOR)
		var base := Vector2(box.position.x + PAD, y + 18.0)
		var dim := bool(r.get("out", false))
		var col: Color = DIM_COLOR if dim else TEXT_COLOR
		draw_string(font, base, "%d" % int(r.get("place", i + 1)),
				HORIZONTAL_ALIGNMENT_LEFT, 16, FONT_SIZE, col)
		# The car's own colour, so a glance matches the car you can see on the road.
		var chip: Color = r.get("color", Color.WHITE)
		draw_rect(Rect2(Vector2(base.x + 18.0, y + 6.0), CHIP), Color(chip.r, chip.g, chip.b, 0.9))
		var tail := _lap_text(r)
		var tail_w := font.get_string_size(tail, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var name_w := box.size.x - PAD * 2.0 - 34.0 - tail_w - 8.0
		draw_string(font, base + Vector2(34.0, 0.0), _fit(font, short_name(String(r.get("name", ""))), name_w),
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)
		draw_string(font, Vector2(box.end.x - PAD - tail_w, base.y), tail,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)


## The car's name for the tower: the persona goes ("Blue Kart - Wildcard" is the AI's, the tower is not
## the place), and so does a colour word in front of a car's name -- the chip is the colour.
func short_name(name: String) -> String:
	return plain_name(name, _models)


## The same, for anyone without a board (SPEC 143: the field card): `models` are the cars' display
## names, looked up when not given.
static func plain_name(name: String, models: Array = []) -> String:
	if models.is_empty():
		for id in CarRegistry.ids():
			models.append(CarRegistry.get_display_name(String(id)))
	var t := name
	if t.contains(" - "):
		t = t.substr(0, t.find(" - "))
	var words := t.split(" ", false)
	if words.size() >= 2:
		var rest := " ".join(words.slice(1))
		if models.has(rest):
			return rest
	return t


## `text`, trimmed with an ellipsis to fit `width` px at FONT_SIZE.
func _fit(font: Font, text: String, width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x <= width:
		return text
	var t := text
	while t.length() > 1 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x > width:
		t = t.left(t.length() - 1)
	return t.strip_edges() + "…"


## What is left for this car: how it finished, or how many laps it has been lapped by.
## SPEC 111: "L1 / L2 looks incorrect" -- a lap number next to every name read as a mistake (the leader
## on L2, you on L1, ten metres apart). A timing tower says nothing for a car on the leader's lap and
## "-1 LAP" for one that has actually been lapped (`down`, counted by the race from the running order).
func _lap_text(r: Dictionary) -> String:
	if bool(r.get("finished", false)):
		return "DONE"
	if bool(r.get("out", false)):
		return "OUT"
	var down := int(r.get("down", 0))
	if down <= 0:
		return ""
	return "-%d LAP%s" % [down, "" if down == 1 else "S"]


## SPEC 111: the box the tower occupies on screen, for the overlap audit (custom-drawn, so `UiAudit`
## cannot see its text; this hands it the panel instead).
func audit_rect() -> Rect2:
	if _rows.is_empty() or not visible:
		return Rect2()
	return Rect2(RECT.position, Vector2(RECT.size.x, get_height()))


func audit_text() -> String:
	return "timing tower"
