class_name Hud
extends CanvasLayer
## In-race overlays. The permanent race information -- track, lap, times, best lap / record, position,
## the off-track warning and the drift readout -- lives in the race bar ([Dashboard]) at the bottom of the
## screen, in the same place on every track; [Hud] keeps it and forwards it there (`set_bar`).
##
## What Hud still draws itself are the three TRANSIENT overlays, each in one fixed place over the world:
## the big countdown / "Ready" / "WRECKED!" in the middle, the lap flash and messages at the top, and the
## "bring the cursor to your car" hint just under them.

## The on-screen pause button (the game needs nothing but the mouse -- or a finger).
signal pause_pressed()
## SPEC 135: write the car off on purpose. The F key emits this, and so does the chip itself -- the game
## is played with one pointer, so every control has to be reachable without a keyboard.
signal self_destruct_pressed()
## SPEC 63: the pause is top RIGHT (the race order board has the top left). SPEC 135: self-destruct is
## the F key AND a chip in the same corner -- SPEC 63's objection was to a button sitting next to the
## cursor you steer with, which is a button you press by accident; up here it is nowhere near it.
## SPEC 97: a thumb-sized pause.
## SPEC 107/108: THE DASHBOARD. "The top left is part of the screen and overlaps with the track." The
## HUD keeps two regions the world never enters: a STRIP across the top (BAR_H) and a TOWER column
## down the left (TOWER_W); the race fits its picture into what is left (`WORLD_AREA`,
## `world_shift`). SPEC 108, after SPEC 107's row of chips was "very hard to understand": what racing
## games do. The strip is INSTRUMENTS -- a small caption over a big value, like a dashboard: POSITION,
## LAP, LAP TIME, BEST LAP and GAP -- with the status words (OFF TRACK, SHIELD 5s) beside them and the
## pause at the end. The tower is the running order as a TIMING TOWER (`RaceBoard`), the column every
## racing game uses.
const BAR_H := 72.0
const BAR_RECT := Rect2(0, 0, 1280, 72)
const BAR_COLOR := Color(0.05, 0.06, 0.07, 0.94)
const BAR_EDGE := Color(1, 1, 1, 0.16)
const TOWER_W := 200.0
## The world's screen: right of the tower, under the strip.
const WORLD_AREA := Rect2(200, 72, 1080, 648)
const PAUSE_RECT := Rect2(1208, 8, 64, 56)
## SPEC 135: the self-destruct chip, top right, right-aligned under the minimap (which ends at y 218)
## and well clear of the pause button in the strip above it. It is on screen for the whole race rather
## than only when it is usable, because its job is to TEACH the key -- a control nobody knows about is
## not a control. It is dim and unclickable until the car has earned it.
const SCRAP_RECT := Rect2(1064, 226, 204, 34)
const SCRAP_READY_COLOR := Color(1.0, 0.52, 0.26)
const SCRAP_DIM_COLOR := Color(0.72, 0.75, 0.78, 0.55)
## The instruments: [caption, x, width, value size]. Captions on one line, values under them.
const CAPTION_Y := 22.0
const VALUE_Y := 56.0
const CAPTION_SIZE := 12
const CAPTION_COLOR := Color(0.62, 0.66, 0.72)
const VALUE_COLOR := Color(0.94, 0.95, 0.97)
const RACE_BLOCKS := [["POSITION", 16.0, 108.0, 26], ["LAP", 136.0, 96.0, 26],
		["LAP TIME", 244.0, 128.0, 24], ["BEST LAP", 384.0, 128.0, 24], ["GAP", 524.0, 110.0, 24]]
## SPEC 135: THE SCRAP NOTICE IS BACK, as ONE thing rather than the five it had grown into by SPEC 128
## (a corner button, a key, a status line teaching the key, a notice, and a countdown on the notice).
## It is the chip at SCRAP_RECT and nothing else: it names the key, it says when the key would work, and
## it is itself the button for anyone without a keyboard. A car that is merely WEDGED is still not its
## job -- `Race` lifts one of those back onto the road by itself, with no explosion and no reward.
## The status words on the strip, after the instruments (SPEC 69) -- OFF TRACK, SHIELD 5s, STREAK x2.
const STATUS_LINE_RECT := Rect2(650, 30, 340, 34)
const FLASH_TIME := 2.0
const WARN_COLOR := Color(1.0, 0.55, 0.15)
## Drift readout colour at full intensity (white at zero), quantised into DRIFT_COLOR_STEPS.
const DRIFT_COLOR := Color(1.0, 0.55, 0.15)
const DRIFT_COLOR_STEPS := 8
## The fixed overlay rects (1280x720 base). The world is drawn above the bar (y < 636).
const COUNTDOWN_RECT := Rect2(0, 230, 1280, 180)
## SPEC 97: 640 wide, wrapping -- a long "X SPOILED Y - 12 points" used to run over the board
## on the left and the clock on the right.
const FLASH_RECT := Rect2(320, 84, 640, 60)     # SPEC 107: under the dashboard
const HINT_RECT := Rect2(240, 164, 800, 64)     # SPEC 97: under the flash even when it wraps to two lines
## While the player's car is wrecked: "WRECKED!" in the countdown slot, the respawn countdown under it, and
## a red wash over the world (not the race bar).
## SPEC 111: 436, not 404 -- at 140 px "WRECKED!" reaches y 422, and the line sat 18 px into it.
const WRECK_SUB_RECT := Rect2(0, 436, 1280, 48)
const WRECK_TINT_RECT := Rect2(0, 0, 1280, 636)
const WRECK_COLOR := Color(1.0, 0.36, 0.2)
const COUNTDOWN_COLOR := Color(1.0, 0.92, 0.3)

var _countdown_label: Label
var _flash_label: Label
var _hint_label: Label
var _wreck_label: Label
var _map: MiniMap = null
var _board: RaceBoard = null
var _field_card: FieldCard = null  # SPEC 143
var _touch: bool = false
var _scrap_button: Button = null       # SPEC 135: the self-destruct chip, top right
var _scrap_ready: bool = false
var _scrap_text: String = ""
var _base_status: String = ""          # what the mode put on the status line
var _base_color: Color = Color.WHITE
var _status_line: Label = null
var _wreck_tint: ColorRect
var _bar: Dashboard = null
var _bar_panel: Node2D = null          # SPEC 107: the strip's edge and the race information on it
var _race_info_shown: bool = false
var _gap_text: String = ""             # SPEC 110: metres to the car ahead (or the lead)
var _flash_priority: int = 0
var _wreck_showing: bool = false

var _track_name: String = ""
var _record_lap: float = INF
var _position_text: String = ""
var _place: int = 0
var _field: int = 0
var _lap_text: String = "Lap 1/3"
var _off_track: bool = false
var _drift_text: String = ""
var _drift_color: Color = DRIFT_COLOR
var _drift_color_step: int = -1
var _drift_shown: Color = Color.WHITE
var _flash_left: float = 0.0
var _flash_age: float = 0.0
var _flash_panel: Node2D = null
var _info := [1, 3, 0.0, 0.0, INF]


func _init() -> void:
	layer = 10
	_build()


func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# SPEC 107: the dashboard's ground, under everything else on the HUD.
	var bar := ColorRect.new()
	bar.name = "Dashboard"
	bar.position = BAR_RECT.position
	bar.size = BAR_RECT.size
	bar.color = BAR_COLOR
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	_wreck_tint = ColorRect.new()
	_wreck_tint.name = "WreckTint"
	# SPEC 84: the WHOLE window. It was a fixed 1280x720 rectangle, so on any window that is not exactly
	# that -- which is most of them, and all of full screen -- the red stopped partway across and the
	# rest of the screen stayed normal. Anchored full-rect it follows the viewport wherever it goes.
	_wreck_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wreck_tint.offset_left = 0.0
	_wreck_tint.offset_top = 0.0
	_wreck_tint.offset_right = 0.0
	_wreck_tint.offset_bottom = 0.0
	_wreck_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wreck_tint.color = Color(0.6, 0.05, 0.0, 0.0)
	_wreck_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wreck_tint.visible = false
	root.add_child(_wreck_tint)
	_countdown_label = _make_label(root, "CountdownLabel", COUNTDOWN_RECT, 140)
	_countdown_label.add_theme_color_override("font_color", COUNTDOWN_COLOR)
	_countdown_label.add_theme_constant_override("outline_size", 14)
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.visible = false
	var pause := Button.new()
	pause.name = "PauseButton"
	pause.text = "II"
	pause.focus_mode = Control.FOCUS_NONE
	pause.add_theme_font_size_override("font_size", 22)
	pause.position = PAUSE_RECT.position
	pause.size = PAUSE_RECT.size
	pause.tooltip_text = "Pause"
	pause.pressed.connect(func() -> void: pause_pressed.emit())
	root.add_child(pause)
	# SPEC 135: the self-destruct chip. A Button rather than a Label because the key it advertises has
	# to be pressable by the one pointer the game is played with (there is no keyboard on a phone), and
	# up here in the corner it is nowhere near the cursor the car is steered by -- which was SPEC 63's
	# objection to the old button that sat next to the pause.
	_scrap_button = Button.new()
	_scrap_button.name = "SelfDestructButton"
	_scrap_button.text = "F  SELF-DESTRUCT"
	_scrap_button.focus_mode = Control.FOCUS_NONE
	_scrap_button.add_theme_font_size_override("font_size", 16)
	_scrap_button.position = SCRAP_RECT.position
	_scrap_button.size = SCRAP_RECT.size
	_scrap_button.tooltip_text = "Write the car off and restart from the last checkpoint"
	_scrap_button.visible = false
	_scrap_button.pressed.connect(func() -> void: self_destruct_pressed.emit())
	root.add_child(_scrap_button)
	# SPEC 111: the touch screen's F.
	_touch = DisplayServer.is_touchscreen_available()
	# The panel is a sibling drawn UNDER the label (SPEC 63).
	_flash_panel = Node2D.new()
	_flash_panel.name = "FlashPanel"
	_flash_panel.draw.connect(_draw_flash_panel)
	root.add_child(_flash_panel)
	_status_line = _make_label(root, "StatusLine", STATUS_LINE_RECT, UiTheme.BODY)
	_status_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status_line.visible = false
	_flash_label = _make_label(root, "FlashLabel", FLASH_RECT, UiTheme.HEADING)
	_flash_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_flash_label.visible = false
	_hint_label = _make_label(root, "HintLabel", HINT_RECT, 20)
	_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.75))
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.visible = false
	_wreck_label = _make_label(root, "WreckLabel", WRECK_SUB_RECT, 32)
	_wreck_label.add_theme_color_override("font_color", Color.WHITE)
	_wreck_label.add_theme_constant_override("outline_size", 8)
	_wreck_label.visible = false
	_bar_panel = Node2D.new()
	_bar_panel.name = "BarPanel"
	_bar_panel.draw.connect(_draw_bar_panel)
	root.add_child(_bar_panel)


## Perf round: the setters below are called every physics tick with mostly the SAME values, and each
## used to redraw the strip (nine `draw_string`s) or re-shape a label regardless. Now a value that has
## not changed costs a comparison, and the strip is redrawn at most once per drawn frame, from
## `_process`, whatever the number of ticks that asked.
var _bar_dirty: bool = false
var _status_color: Color = Color(0, 0, 0, -1.0)
var _position_set: bool = false        # `set_race_position` has been called at least once


func set_board_visible(on: bool) -> void:
	if _board != null:
		_board.visible = on


static func _clock_text(seconds: float) -> String:
	if not is_finite(seconds) or seconds < 0.0:
		return "-:--.---"
	return "%d:%06.3f" % [int(seconds / 60.0), fmod(seconds, 60.0)]


## SPEC 108: the dashboard's edge and its INSTRUMENTS: a caption over a value, each in its own place.
func _draw_bar_panel() -> void:
	_bar_panel.draw_line(Vector2(0.0, BAR_RECT.size.y - 0.5), Vector2(BAR_RECT.size.x, BAR_RECT.size.y - 0.5), BAR_EDGE, 1.0)
	var font := ThemeDB.fallback_font
	var blocks: Array = []
	var values: Array = []
	if _race_info_shown:
		blocks = RACE_BLOCKS
		values = [
			("%d/%d" % [_place, _field]) if _place > 0 and _field > 1 else "\u2014",
			"%d/%d" % [int(_info[0]), int(_info[1])],
			_clock_text(float(_info[2])),
			_clock_text(float(_info[4])) if is_finite(float(_info[4])) else "\u2014",
			_gap_text if _gap_text != "" else "\u2014",
		]
	for i in blocks.size():
		var b: Array = blocks[i]
		var x := float(b[1])
		_bar_panel.draw_string(font, Vector2(x, CAPTION_Y), String(b[0]), HORIZONTAL_ALIGNMENT_LEFT, int(b[2]),
				CAPTION_SIZE, CAPTION_COLOR)
		_bar_panel.draw_string(font, Vector2(x, VALUE_Y), String(values[i]), HORIZONTAL_ALIGNMENT_LEFT, int(b[2]),
				int(b[3]), VALUE_COLOR)


func _make_label(parent: Control, node_name: String, r: Rect2, font_size: int) -> Label:
	var l := Label.new()
	l.name = node_name
	l.position = r.position
	l.size = r.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	parent.add_child(l)
	return l


func _process(delta: float) -> void:
	if _bar_dirty and _bar_panel != null:
		_bar_dirty = false
		_bar_panel.queue_redraw()
	if _flash_left > 0.0:
		_flash_left -= delta
		_flash_age += delta
		if _flash_panel != null:
			_flash_panel.queue_redraw()
		# Grows in over the first eighth of a second and fades with the last (SPEC 63).
		var grow := clampf(_flash_age * 8.0, 0.0, 1.0)
		var fade := clampf(_flash_left / 0.4, 0.0, 1.0)
		_flash_label.modulate = Color(1, 1, 1, minf(grow, fade))
		_flash_label.scale = Vector2.ONE * lerpf(0.86, 1.0, grow)
		_flash_label.pivot_offset = _flash_label.size * 0.5
		if _flash_left <= 0.0:
			_flash_label.visible = false
			if _flash_panel != null:
				_flash_panel.queue_redraw()


## SPEC 135: the self-destruct chip. Called every frame of a race. `ready` is whether pressing it would
## do anything now; `cooldown_left` and `damage` against `needs` are the two reasons it might not, and
## the chip says WHICH -- "SCRAP IN 12 s" is a wait, a dim chip with no number is "your car is fine".
func set_self_destruct(ready: bool, cooldown_left: float, damage: float, needs: float) -> void:
	_scrap_ready = ready
	if ready:
		_scrap_text = "F  SELF-DESTRUCT"
	elif cooldown_left > 0.0:
		_scrap_text = "SCRAP IN %d s" % ceili(cooldown_left)
	else:
		_scrap_text = "F  SELF-DESTRUCT"
	if _scrap_button == null:
		return
	_scrap_button.visible = true
	_scrap_button.text = _scrap_text
	_scrap_button.disabled = not ready
	_scrap_button.modulate = Color.WHITE if ready else Color(1, 1, 1, 0.75)
	_scrap_button.add_theme_color_override("font_color",
			SCRAP_READY_COLOR if ready else SCRAP_DIM_COLOR)
	_scrap_button.add_theme_color_override("font_disabled_color", SCRAP_DIM_COLOR)


## Off the screen entirely -- before the lights, after the flag, and in any mode that has no such key.
func hide_self_destruct() -> void:
	_scrap_ready = false
	_scrap_text = ""
	if _scrap_button != null:
		_scrap_button.visible = false


func get_self_destruct_text() -> String:
	return _scrap_text


func is_self_destruct_ready() -> bool:
	return _scrap_ready


## The race bar the permanent information goes to. Everything set before is pushed at once.
## SPEC 111: tests and the phone.
func set_touch_controls(on: bool) -> void:
	_touch = on
	_apply_status_line()


func set_status_line(text: String, color: Color) -> void:
	_base_status = text
	_base_color = color
	_apply_status_line()


## What the status line shows: the mode's words, and nothing when it has none.
func _apply_status_line() -> void:
	if _status_line == null:
		return
	var text := _base_status
	var color := _base_color
	# SPEC 97: not while WRECKED! is up -- the two share the band under the doll.
	var shown := text != "" and not _wreck_showing
	if text == _status_line.text and color == _status_color and shown == _status_line.visible:
		return
	_status_line.text = text
	if color != _status_color:
		# A theme override re-shapes the label whether or not the colour changed: only when it has.
		_status_color = color
		_status_line.add_theme_color_override("font_color", color)
	_status_line.visible = shown


func get_status_line() -> String:
	return _status_line.text if _status_line != null and _status_line.visible else ""


## The running order in the corner (SPEC 55). Built once, on the first update.
## What the board calls itself. Set before the first update.
var board_header: String = "ORDER"


func update_board(rows: Array) -> void:
	if _board == null:
		_board = RaceBoard.new()
		_board.name = "RaceBoard"
		(get_node("Root") as Control).add_child(_board)
	_board.header = board_header
	_board.set_rows(rows)


func has_board() -> bool:
	return _board != null


## SPEC 143: THE FIELD -- who you are racing, on the grid. `rows`: [{name, color, persona, tell}].
func show_field(rows: Array) -> void:
	if rows.is_empty():
		hide_field()
		return
	if _field_card == null:
		_field_card = FieldCard.new()
		_field_card.name = "FieldCard"
		(get_node("Root") as Control).add_child(_field_card)
	_field_card.set_rows(rows)
	_field_card.set_alpha(1.0)


func set_field_alpha(a: float) -> void:
	if _field_card != null:
		_field_card.set_alpha(a)


func hide_field() -> void:
	if _field_card != null:
		_field_card.set_alpha(0.0)


## The rows on the card right now, [] when it is hidden (for the tests).
func get_field_rows() -> Array:
	return _field_card.get_rows() if _field_card != null and _field_card.visible else []


func get_field_rect() -> Rect2:
	return _field_card.get_rect() if _field_card != null else Rect2()


func setup_minimap(centerline: PackedVector2Array, world: Vector2) -> void:
	if _map == null:
		_map = MiniMap.new()
		_map.name = "MiniMap"
		(get_node("Root") as Control).add_child(_map)
	_map.setup(centerline, world)


func update_minimap(dots: Array) -> void:
	if _map != null:
		_map.set_dots(dots)


func has_minimap() -> bool:
	return _map != null and _map.visible


## The minimap is only shown while the view rides with the car (SPEC 63).
func set_minimap_visible(on: bool) -> void:
	if _map != null:
		_map.visible = on


func set_bar(bar: Dashboard) -> void:
	_bar = bar
	if _bar == null:
		return
	_bar.set_track(_track_name)
	_bar.set_accent(_drift_color)
	_push_info()
	_bar.set_place(_place, _field)
	_push_status()


## Fixed overlay rects, for the tests: {"countdown", "flash", "hint"}.
func get_layout_rects() -> Dictionary:
	return {"countdown": COUNTDOWN_RECT, "flash": FLASH_RECT, "hint": HINT_RECT}


func get_countdown_rect() -> Rect2:
	return COUNTDOWN_RECT


## SPEC 110: the GAP instrument. "" shows a dash.
func set_gap(text: String) -> void:
	if text == _gap_text:
		return
	_gap_text = text
	if _bar_panel != null:
		_bar_panel.queue_redraw()


func get_gap_text() -> String:
	return _gap_text


## SPEC 108: how far (in world units, at zoom `z`) a camera looks past the point it centres, so that
## point lands in the middle of WORLD_AREA rather than of the screen.
static func world_shift(z: float) -> Vector2:
	var c := WORLD_AREA.get_center()
	return Vector2(-(c.x - 640.0) / maxf(z, 0.001), -(c.y - 360.0) / maxf(z, 0.001))


## SPEC 108: the camera limits that let the world reach the edges of WORLD_AREA -- the tower's and the
## strip's worth of world beyond the top-left corner.
static func limit_left(z: float) -> int:
	return -int(ceil(WORLD_AREA.position.x / maxf(z, 0.001))) - 1


static func limit_top(z: float) -> int:
	return -int(ceil(WORLD_AREA.position.y / maxf(z, 0.001))) - 1


# ---------------------------------------------------------------- race information (-> the bar)

func set_track_name(track_name: String) -> void:
	_track_name = track_name
	if _bar != null:
		_bar.set_track(track_name)


func set_record_lap(record_lap: float) -> void:
	_record_lap = record_lap
	_push_info()


## The one saturated colour of the race screen: the track accent (the bar and the drift readout).
func set_accent(color: Color) -> void:
	_drift_color = color
	_drift_color_step = -1
	if _bar != null:
		_bar.set_accent(color)


## Race position ("P2/5"); 0 hides it (a solo race).
func set_race_position(place: int, field: int) -> void:
	if _position_set and place == _place and field == _field:
		return
	_position_set = true
	_place = place
	_field = field
	_position_text = "   P%d/%d" % [place, field] if place > 0 and field > 1 else ""
	if _bar != null:
		_bar.set_place(place, field)
	_bar_dirty = true


func get_race_position_text() -> String:
	return _position_text


func update_race_info(lap: int, total_laps: int, current_lap_time: float, total_time: float,
		best_lap_time: float) -> void:
	_info = [lap, total_laps, current_lap_time, total_time, best_lap_time]
	_lap_text = "Lap %d/%d%s" % [lap, total_laps, _position_text]
	_race_info_shown = true                       # SPEC 107: it is on the dashboard from here on
	_push_info()
	_bar_dirty = true                             # the lap time moves every tick; drawn once a frame


func get_lap_text() -> String:
	return _lap_text


func _push_info() -> void:
	if _bar != null:
		_bar.set_race_info(int(_info[0]), int(_info[1]), float(_info[2]), float(_info[3]), float(_info[4]),
				_record_lap)


## SPEC 145: the yellow flag. The bar says CAUTION over everything else while it is up.
func set_caution(on: bool) -> void:
	if _bar != null:
		_bar.set_caution(on)
	_push_status()


func is_caution() -> bool:
	return _bar != null and _bar.is_caution()


func set_off_track(is_off: bool) -> void:
	if is_off == _off_track:
		return
	_off_track = is_off
	_push_status()


func is_off_track_visible() -> bool:
	return _off_track


## Drift readout (in the bar's status column): "DRIFT 1.4 s | 3.2 s", white -> accent with `intensity`.
func set_drift(active: bool, intensity: float, drift_seconds: float, banked_seconds: float = 0.0) -> void:
	var text := ""
	if active:
		text = "DRIFT  %.1f s" % maxf(drift_seconds, 0.0)
		if banked_seconds > 0.05:
			text += "  | %.1f s" % banked_seconds
		var step := clampi(int(round(clampf(intensity, 0.0, 1.0) * DRIFT_COLOR_STEPS)), 0, DRIFT_COLOR_STEPS)
		if step != _drift_color_step:
			_drift_color_step = step
			_drift_shown = Color.WHITE.lerp(_drift_color, float(step) / float(DRIFT_COLOR_STEPS))
	if text != _drift_text:
		_drift_text = text
		_push_status()


## Text of the drift readout, "" while there is no drift (for tests).
func get_drift_text() -> String:
	return _drift_text


func _push_status() -> void:
	if _bar == null:
		return
	_bar.set_status(_off_track, _drift_text, _drift_shown)
	# SPEC 69: the bar works out what matters (off track, a flat tyre, cold rubber, a broken part, the
	# boost); with the bar itself gone, the HUD shows that one line top left.
	set_status_line(_bar.get_status_text(), _bar.get_status_color())


# ---------------------------------------------------------------- overlays

func show_countdown(text: String) -> void:
	_countdown_label.text = text
	_countdown_label.visible = true


func hide_countdown() -> void:
	_countdown_label.visible = false


## The player's car is a burning wreck: "WRECKED!" (in red), "Respawn in 1.4 s" under it, and a red wash
## over the world that fades as the respawn nears. Called every frame of the wait.
func show_wreck(respawn_in: float, wait: float) -> void:
	_wreck_showing = true
	_status_line.visible = false
	_countdown_label.text = "WRECKED!"
	_countdown_label.add_theme_color_override("font_color", WRECK_COLOR)
	_countdown_label.visible = true
	_wreck_label.text = "Respawn in %.1f s" % maxf(respawn_in, 0.0)
	_wreck_label.visible = true
	_wreck_tint.color.a = 0.28 * clampf(respawn_in / maxf(wait, 0.01), 0.0, 1.0) + 0.06
	_wreck_tint.visible = true


func hide_wreck() -> void:
	_wreck_showing = false
	_status_line.visible = _status_line.text != ""
	_countdown_label.add_theme_color_override("font_color", COUNTDOWN_COLOR)
	_wreck_label.visible = false
	_wreck_tint.visible = false


func get_wreck_text() -> String:
	return _wreck_label.text if _wreck_label.visible else ""


func flash_lap(lap: int, lap_time: float) -> void:
	_flash_label.remove_theme_color_override("font_color")
	_flash_label.text = "Lap %d: %s" % [lap, _clock_text(lap_time)]     # no autoload: the suite loads Hud bare
	_flash_label.visible = true
	_flash_left = FLASH_TIME
	_flash_age = 0.0


## Brief attention message in the flash slot (e.g. "Lap not counted - checkpoint missed").
## SPEC 63: a message over the track is unreadable without something behind it. The flash now has its
## own panel, sized to the text, and it grows in and fades out instead of appearing and vanishing.
func _draw_flash_panel() -> void:
	if _flash_label == null or not _flash_label.visible or _flash_panel == null:
		return
	var font := _flash_label.get_theme_font("font")
	var size := font.get_string_size(_flash_label.text, HORIZONTAL_ALIGNMENT_CENTER, -1,
			_flash_label.get_theme_font_size("font_size"))
	var grow := clampf(_flash_age * 8.0, 0.0, 1.0)
	var fade := clampf(_flash_left / 0.4, 0.0, 1.0)
	var w := (minf(size.x, FLASH_RECT.size.x - 48.0) + 48.0) * lerpf(0.82, 1.0, grow)
	var h := float(maxi(_flash_label.get_line_count(), 1)) * _flash_label.get_line_height() + 20.0
	var at := Vector2(FLASH_RECT.get_center().x - w * 0.5, FLASH_RECT.position.y + 2.0)
	var alpha := 0.72 * minf(grow, fade)
	_flash_panel.draw_rect(Rect2(at, Vector2(w, h)), Color(0.04, 0.05, 0.06, alpha), true)
	_flash_panel.draw_rect(Rect2(at, Vector2(w, h)), Color(1, 1, 1, 0.14 * minf(grow, fade)), false, 1.0)


func flash_message(text: String, color: Color = WARN_COLOR, priority: int = 1) -> void:
	hide_field()                               # SPEC 143: the card gives the band up to the news
	# SPEC 97: a louder message is not replaced by a quieter one while it is still up.
	if _flash_left > 0.4 and priority < _flash_priority:
		return
	_flash_priority = priority
	_flash_label.add_theme_color_override("font_color", color)
	_flash_label.text = text
	_flash_label.visible = true
	_flash_left = FLASH_TIME
	_flash_age = 0.0


## Hides the lap flash immediately (pause / resume hold).
func clear_flash() -> void:
	_flash_label.visible = false
	_flash_left = 0.0


func get_flash_text() -> String:
	return _flash_label.text if _flash_label.visible else ""


## Short guidance text (e.g. "Bring the cursor to your car"); empty string hides it.
func set_hint(text: String) -> void:
	_hint_label.text = text
	_hint_label.visible = not text.is_empty()


## What the hint slot is saying -- for whoever is driving it, and for the tests.
func get_hint() -> String:
	return _hint_label.text if _hint_label != null and _hint_label.visible else ""
