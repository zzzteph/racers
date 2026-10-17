class_name WhatsNewCard
extends CanvasLayer
## WHAT'S NEW (SPEC 113): the release notes, in the game. A card over the title menu with the newest
## sections of CHANGELOG.md in a scrolling text, and CLOSE. Opened from the corner button, and once by
## itself the first time a new build runs (the menu decides that; this only shows).

signal closed

## SPEC 128: the button the keyboard lands on when the card opens, and what had it before.
var _close: Button = null
var _focus_was: Control = null

const PANEL_RECT := Rect2(200, 40, 880, 640)
const PANEL_COLOR := Color(0.11, 0.12, 0.14)
const PANEL_EDGE := Color(0.45, 0.47, 0.52)
const DIM := Color(0, 0, 0, 0.6)
const TEXT_RECT := Rect2(30, 96, 820, 460)
const CLOSE_RECT := Rect2(290, 572, 300, 52)

var _root: Control
var _text: RichTextLabel
var _sub: Label


func _init() -> void:
	layer = 31
	_build()


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)
	var panel := Control.new()
	panel.name = "Panel"
	panel.position = PANEL_RECT.position
	panel.size = PANEL_RECT.size
	_root.add_child(panel)
	var back := ColorRect.new()
	back.name = "Back"
	back.color = PANEL_COLOR
	back.size = PANEL_RECT.size
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(back)
	var edge := ReferenceRect.new()
	edge.name = "Edge"
	edge.border_color = PANEL_EDGE
	edge.border_width = 2.0
	edge.editor_only = false
	edge.size = PANEL_RECT.size
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(edge)
	var title := Label.new()
	title.name = "Title"
	title.text = "WHAT'S NEW"
	title.position = Vector2(0, 16)
	title.size = Vector2(PANEL_RECT.size.x, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UiTheme.HEADING)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)
	_sub = Label.new()
	_sub.name = "Sub"
	_sub.position = Vector2(0, 58)
	_sub.size = Vector2(PANEL_RECT.size.x, 30)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", UiTheme.CAPTION)
	_sub.add_theme_color_override("font_color", UiTheme.MUTED)
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_sub)
	_text = RichTextLabel.new()
	_text.name = "Notes"
	_text.bbcode_enabled = true
	_text.scroll_active = true
	_text.selection_enabled = false
	_text.position = TEXT_RECT.position
	_text.size = TEXT_RECT.size
	_text.add_theme_font_size_override("normal_font_size", UiTheme.BODY)
	_text.add_theme_font_size_override("bold_font_size", UiTheme.BODY)
	_text.add_theme_font_size_override("mono_font_size", UiTheme.BODY)
	panel.add_child(_text)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "CLOSE"
	# SPEC 128: the card takes the keyboard when it opens (see `UiTheme.take_focus`) -- a full-screen
	# card that does not is a card the keyboard is not in.
	close_button.focus_mode = Control.FOCUS_ALL
	_close = close_button
	close_button.position = CLOSE_RECT.position
	close_button.size = CLOSE_RECT.size
	close_button.add_theme_font_size_override("font_size", UiTheme.HEADING)
	UiTheme.style_button(close_button)
	close_button.pressed.connect(close)
	panel.add_child(close_button)


## Fills the card with the notes (the newest `limit` versions) and shows it.
func open(limit: int = ReleaseNotes.DEFAULT_LIMIT) -> void:
	var list := ReleaseNotes.sections()
	if list.is_empty():
		_text.text = "The release notes did not ship with this build."
		_sub.text = Version.label()
	else:
		_text.text = ReleaseNotes.bbcode(list, limit)
		_sub.text = "This build is %s  -  %d release%s below, newest first" % [Version.label(),
				mini(list.size(), limit), "" if mini(list.size(), limit) == 1 else "s"]
	_text.scroll_to_line(0)
	_root.visible = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_focus_was = UiTheme.take_focus(_close)


func close() -> void:
	if not is_open():
		return
	_root.visible = false
	visible = false
	UiTheme.give_focus(_focus_was)
	_focus_was = null
	closed.emit()


func is_open() -> bool:
	return _root.visible


func get_text() -> String:
	return _text.get_parsed_text()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
