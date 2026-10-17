class_name FeedbackCard
extends CanvasLayer
## THE FEEDBACK CARD (SPEC 112): a rating, three toggles (Bug / Suggestion / General), a few words, SEND.
## Opened from the title menu, the pause menu and the results card; posts to the Google Form
## (`Feedback`) without leaving the game. Every control is a thumb's worth (44 px or more), one pointer
## does everything, Esc closes.
##
## Nothing here names an autoload: whoever opens the card passes the player's name and where they are.

signal sent(body: String)
signal closed

## SPEC 128: what had the keyboard before this card took it, so closing gives it back.
var _focus_was: Control = null

const PANEL_RECT := Rect2(240, 56, 800, 608)
const PANEL_COLOR := Color(0.11, 0.12, 0.14)
const PANEL_EDGE := Color(0.45, 0.47, 0.52)
const DIM := Color(0, 0, 0, 0.55)
const STAR_SIZE := Vector2(64, 56)
const TYPE_SIZE := Vector2(200, 48)
const DETAILS_RECT := Rect2(60, 262, 680, 150)
const SEND_RECT := Rect2(110, 490, 300, 56)
const CLOSE_RECT := Rect2(430, 490, 300, 56)
const STATUS_RECT := Rect2(40, 556, 720, 40)
const INFO_RECT := Rect2(60, 420, 680, 60)
const CHOSEN := Color(1.0, 0.84, 0.30)

## Tests: build the body, say "sent", post nothing.
var dry_run: bool = false
var last_body: String = ""

var _root: Control
var _panel: Control
var _stars: Array = []
var _types: Dictionary = {}
var _details: TextEdit
## SPEC 125: how many characters are left before the box starts eating them.
var _counter: Label = null
var _info: Label
var _status: Label
var _send_button: Button
var _http: HTTPRequest = null
var _rating: int = 0
var _type: String = Feedback.DEFAULT_TYPE
var _where: String = ""
var _name: String = ""
var _last_sent_at: float = -1.0e9
var _pending: String = ""
var _queue_left: Array = []


func _init() -> void:
	layer = 30
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
	_panel = Control.new()
	_panel.name = "Panel"
	_panel.position = PANEL_RECT.position
	_panel.size = PANEL_RECT.size
	_root.add_child(_panel)
	var back := ColorRect.new()
	back.name = "Back"
	back.color = PANEL_COLOR
	back.size = PANEL_RECT.size
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(back)
	var edge := ReferenceRect.new()
	edge.name = "Edge"
	edge.border_color = PANEL_EDGE
	edge.border_width = 2.0
	edge.editor_only = false
	edge.size = PANEL_RECT.size
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(edge)

	var title := _label("Title", "FEEDBACK", Rect2(0, 16, 800, 40), UiTheme.HEADING)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var lead := _label("Lead", "A bug, an idea, or a word -- it lands with the maker as you send it.",
			Rect2(0, 58, 800, 30), UiTheme.BODY)
	lead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lead.add_theme_color_override("font_color", UiTheme.MUTED)

	# The rating: five buttons, 1 to 5, the chosen one and everything under it lit.
	_label("RatingCaption", "Rating   1 = bad, 5 = great", Rect2(60, 100, 680, 26), UiTheme.CAPTION) \
			.add_theme_color_override("font_color", UiTheme.MUTED)
	for i in 5:
		var b := Button.new()
		b.name = "Star%d" % (i + 1)
		b.text = str(i + 1)
		b.toggle_mode = false
		b.focus_mode = Control.FOCUS_NONE
		b.position = Vector2(210.0 + 76.0 * float(i), 128.0)
		b.size = STAR_SIZE
		b.add_theme_font_size_override("font_size", UiTheme.HEADING)
		UiTheme.style_button(b)
		b.pressed.connect(set_rating.bind(i + 1))
		_panel.add_child(b)
		_stars.append(b)

	# The kind: three toggles.
	var x := 100.0
	for t in Feedback.TYPES:
		var kind := String(t)
		var b := Button.new()
		b.name = "Type%s" % kind
		b.text = kind
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.position = Vector2(x, 198.0)
		b.size = TYPE_SIZE
		b.add_theme_font_size_override("font_size", UiTheme.BODY)
		UiTheme.style_button(b)
		b.pressed.connect(set_type.bind(kind))
		_panel.add_child(b)
		_types[kind] = b
		x += TYPE_SIZE.x + 10.0

	_details = TextEdit.new()
	_details.name = "Details"
	_details.position = DETAILS_RECT.position
	_details.size = DETAILS_RECT.size
	_details.placeholder_text = "What happened, or what would make it better?"
	_details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_details.add_theme_font_size_override("font_size", UiTheme.BODY)
	_details.text_changed.connect(_on_details_changed)
	_panel.add_child(_details)
	# SPEC 125: how much room is left, beside the box it belongs to.
	_counter = _label("Counter", "", Rect2(DETAILS_RECT.end.x - 96.0, DETAILS_RECT.position.y - 22.0,
			96.0, 20.0), UiTheme.CAPTION)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_info = _label("Info", "", INFO_RECT, UiTheme.CAPTION)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_color_override("font_color", UiTheme.MUTED)

	_send_button = Button.new()
	_send_button.name = "SendButton"
	_send_button.text = "SEND"
	_send_button.focus_mode = Control.FOCUS_NONE
	_send_button.position = SEND_RECT.position
	_send_button.size = SEND_RECT.size
	_send_button.add_theme_font_size_override("font_size", UiTheme.HEADING)
	UiTheme.style_button(_send_button)
	_send_button.pressed.connect(func() -> void: send())
	_panel.add_child(_send_button)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "CLOSE"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.position = CLOSE_RECT.position
	close_button.size = CLOSE_RECT.size
	close_button.add_theme_font_size_override("font_size", UiTheme.HEADING)
	UiTheme.style_button(close_button, UiTheme.MUTED)
	close_button.pressed.connect(close)
	_panel.add_child(close_button)

	_status = _label("Status", "", STATUS_RECT, UiTheme.BODY)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", CHOSEN)
	_status.visible = false
	_refresh()


func _label(node_name: String, text: String, r: Rect2, font_size: int) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.position = r.position
	l.size = r.size
	l.add_theme_font_size_override("font_size", UiTheme.snap_size(font_size))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(l)
	return l


# ---------------------------------------------------------------- open / close

## `where` is what the player was doing ("Serpent, lap 2 of 3"); `name` their own name.
func open(where: String, name: String) -> void:
	_where = where
	_name = name
	_status.visible = false
	_status.text = ""
	_info.text = "Sent with version %s, your name (%s) and where you are: %s." % [Version.number(),
			name if name != "" else "no name", where if where != "" else "the game"]
	_root.visible = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	# SPEC 128: the keyboard goes to the box the player came here to type in, and everything on the card
	# is a Tab away in reading order -- stars, kind, the box, SEND, CLOSE.
	_focus_was = UiTheme.take_focus(_details)
	var chain: Array = []
	chain.append_array(_stars)
	for t in Feedback.TYPES:
		chain.append(_types.get(String(t)))
	chain.append(_details)
	chain.append(_send_button)
	chain.append(_panel.get_node_or_null("CloseButton"))
	UiTheme.focus_chain(chain)


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


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


# ---------------------------------------------------------------- the fields

func set_rating(n: int) -> void:
	_rating = clampi(n, 0, 5)
	_refresh()


func set_type(kind: String) -> void:
	_type = kind if Feedback.TYPES.has(kind) else Feedback.DEFAULT_TYPE
	_refresh()


func set_details(text: String) -> void:
	_details.text = text
	_on_details_changed()


func get_rating() -> int:
	return _rating


func get_type() -> String:
	return _type


func get_details() -> String:
	return _details.text


func get_where() -> String:
	return _where


func get_status_text() -> String:
	return _status.text if _status.visible else ""


## SPEC 125: the limit is VISIBLE before it bites. Text past `MAX_DETAILS` was silently cut off as it
## was typed, so a long report lost its ending and nothing on the screen had said there was a ceiling.
func _on_details_changed() -> void:
	if _details.text.length() > Feedback.MAX_DETAILS:
		_details.text = _details.text.left(Feedback.MAX_DETAILS)
		_details.set_caret_column(_details.get_line(_details.get_caret_line()).length())
	_refresh_counter()


func _refresh_counter() -> void:
	if _counter == null:
		return
	var used := _details.text.length()
	var left := Feedback.MAX_DETAILS - used
	_counter.text = "%d left" % left
	_counter.add_theme_color_override("font_color",
			UiTheme.WARN if left <= 60 else Color(0.62, 0.66, 0.72))


func _refresh() -> void:
	for i in _stars.size():
		var b: Button = _stars[i]
		b.modulate = Color(1, 1, 1, 1.0) if i < _rating else Color(1, 1, 1, 0.45)
	for kind in _types.keys():
		var chosen := String(kind) == _type
		var b: Button = _types[kind]
		b.button_pressed = chosen
		b.modulate = Color(1, 1, 1, 1.0) if chosen else Color(1, 1, 1, 0.55)   # the pressed look alone is too quiet


func build_body() -> String:
	return Feedback.build_body(_rating, _type, _details.text, _name, _where)


# ---------------------------------------------------------------- sending

## True when the submission went (or was queued for the next launch); false when there is nothing to
## send yet or the last one was seconds ago.
func send() -> bool:
	if _rating <= 0 and Feedback.clean(_details.text, Feedback.MAX_DETAILS) == "":
		_say("Pick a rating or write a few words first.")
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_sent_at < Feedback.MIN_INTERVAL:
		_say("Sent a moment ago -- give it half a minute.")
		return false
	var body := build_body()
	last_body = body
	_last_sent_at = now
	if dry_run:
		_after_sent(body)
		return true
	_post(body, false)
	return true


func _post(body: String, from_queue: bool) -> void:
	if _http == null:
		_http = HTTPRequest.new()
		_http.name = "Post"
		_http.timeout = 15.0
		add_child(_http)
		_http.request_completed.connect(_on_completed)
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		if not from_queue:
			Feedback.queue_add(body)
			_say("Sending is busy -- kept, it goes with the next launch.")
		return
	_pending = body
	var err := _http.request(Feedback.FORM_URL, Feedback.HEADERS, HTTPClient.METHOD_POST, body)
	if err != OK:
		_pending = ""
		if not from_queue:
			Feedback.queue_add(body)
		_say("Could not send (error %d) -- kept, it goes with the next launch." % err)
		return
	if Feedback.is_fire_and_forget():
		# The browser hides Google's reply to a cross-site post; the post itself goes.
		_send_button.disabled = false
		_after_sent(body)
	else:
		_send_button.disabled = true
		_say("Sending ...")


func _on_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var body := _pending
	_pending = ""
	_send_button.disabled = false
	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 400
	if Feedback.is_fire_and_forget():
		ok = true
	if ok:
		if body != "":
			_after_sent(body)
		_next_queued()
		return
	if body != "" and not Feedback.is_fire_and_forget():
		Feedback.queue_add(body)
	# SPEC 125: the recovery in plain words first, the numbers afterwards for anybody who wants them.
	_say("Could not reach the form -- saved, and it goes with the next launch.  (result %d, HTTP %d)"
			% [result, code])
	_queue_left.clear()


## SPEC 125: SUBMITTED IS NOT THE SAME AS DELIVERED. The web build's send is fire-and-forget -- the
## browser will not let the game read the response -- and it reported "Sent -- thank you!" regardless of
## what happened at the other end. The card now says only what it actually knows.
func _after_sent(body: String) -> void:
	_say("Sent -- thank you!" if not Feedback.is_fire_and_forget()
			else "Submitted -- the browser will not tell us whether it arrived. Thank you!")
	_details.text = ""
	_rating = 0
	_refresh()
	sent.emit(body)


func _say(text: String) -> void:
	_status.text = text
	_status.visible = text != ""


# ---------------------------------------------------------------- the queue (once per run)

## Sends what failed last time, one at a time. Nothing on the web build (see Feedback.QUEUE_PATH).
func retry_queue() -> int:
	if Feedback.retried_this_run or Feedback.is_fire_and_forget():
		return 0
	Feedback.retried_this_run = true
	_queue_left = Feedback.queue_load()
	var n := _queue_left.size()
	if n > 0:
		Feedback.queue_save([])          # what fails again is re-queued by _on_completed
		_next_queued()
	return n


func _next_queued() -> void:
	if _queue_left.is_empty() or dry_run:
		return
	var body := String(_queue_left.pop_front())
	_post(body, true)
