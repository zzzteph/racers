class_name RulesCard
extends CanvasLayer
## SPEC 130: THE RULES OF WHATEVER YOU ARE PLAYING, A PAGE AT A TIME.
##
## The arena's pause menu had a Rules button and the race's did not ("all pause menus should be the
## same"), because the arena happened to own a briefing card and the race did not. The rules of a race
## were only ever on the How to play screen, which you cannot reach from inside one.
##
## This is that card, built from a list of [heading, body] rows -- so a race can hand it the racing
## rules and anything else can hand it its own. It turns pages rather than scrolling, for the same
## reason the briefing does: this is read once, deliberately, and a page you turn is read where a wall
## of text is skipped.
##
## Escape closes it, and so does the button. It pauses nothing by itself -- whoever opens it is already
## paused -- and it emits `closed` so the pause menu can come back.

signal closed

const PANEL := Rect2(160, 96, 960, 528)
const TEXT_X := 196.0
const HEAD_W := 260.0
const BODY_W := 640.0
const ROW_H := 48.0
const PER_PAGE := 6
const PAGE_BUTTON := Vector2(56.0, 44.0)

var _root: Control = null
var _rows: Array = []
var _pages: int = 1
var _page: int = 0
var _page_label: Label = null
var _title: Label = null


func _init() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)


## Fills the card with `rows` ([heading, body] each) under `title`, and shows it.
func open(title: String, rows: Array) -> void:
	for child in _root.get_children():
		child.queue_free()
	_rows.clear()
	_page = 0
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.04, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var panel := UiTheme.panel("RulesPanel")
	panel.position = PANEL.position
	panel.size = PANEL.size
	_root.add_child(panel)
	_title = UiTheme.label("RulesTitle", title, UiTheme.TITLE, UiTheme.ACCENT)
	_title.position = PANEL.position + Vector2(36, 22)
	_title.size = Vector2(PANEL.size.x - 72, 44)
	_root.add_child(_title)
	for i in rows.size():
		var row: Array = rows[i]
		var y := PANEL.position.y + 92.0 + ROW_H * float(i % PER_PAGE)
		var head := UiTheme.label("RuleHead%d" % i, String(row[0]), UiTheme.BODY, UiTheme.TEXT)
		head.position = Vector2(TEXT_X, y)
		head.size = Vector2(HEAD_W, 26)
		_root.add_child(head)
		var body := UiTheme.label("RuleBody%d" % i, String(row[1]), UiTheme.CAPTION, UiTheme.MUTED)
		body.position = Vector2(TEXT_X, y + 24.0)
		body.size = Vector2(BODY_W, 24)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_root.add_child(body)
		_rows.append([head, body])
	_pages = maxi(1, int(ceil(float(rows.size()) / float(PER_PAGE))))
	var foot := PANEL.end.y - 76.0
	var done := UiTheme.button("RulesClose", "BACK")
	done.position = Vector2(TEXT_X, foot)
	done.size = Vector2(220.0, PAGE_BUTTON.y)
	done.focus_mode = Control.FOCUS_ALL
	done.pressed.connect(close)
	_root.add_child(done)
	if _pages > 1:
		var prev := UiTheme.button("RulesPrev", "<")
		prev.position = Vector2(TEXT_X + 260.0, foot)
		prev.size = PAGE_BUTTON
		prev.focus_mode = Control.FOCUS_NONE
		prev.pressed.connect(func() -> void: _show_page(_page - 1))
		_root.add_child(prev)
		_page_label = UiTheme.label("RulesPage", "", UiTheme.BODY, UiTheme.MUTED)
		_page_label.position = Vector2(TEXT_X + 260.0 + PAGE_BUTTON.x, foot)
		_page_label.size = Vector2(88.0, PAGE_BUTTON.y)
		_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_root.add_child(_page_label)
		var next := UiTheme.button("RulesNext", ">")
		next.position = Vector2(TEXT_X + 348.0 + PAGE_BUTTON.x, foot)
		next.size = PAGE_BUTTON
		next.focus_mode = Control.FOCUS_NONE
		next.pressed.connect(func() -> void: _show_page(_page + 1))
		_root.add_child(next)
	_show_page(0)
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	done.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func page() -> int:
	return _page


func pages() -> int:
	return _pages


func _show_page(n: int) -> void:
	_page = posmod(n, maxi(_pages, 1))
	for i in _rows.size():
		var on: bool = int(i / PER_PAGE) == _page
		((_rows[i] as Array)[0] as Control).visible = on
		((_rows[i] as Array)[1] as Control).visible = on
	if _page_label != null:
		_page_label.text = "%d / %d" % [_page + 1, _pages]


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
