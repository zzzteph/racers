extends Control
## Track select (SPEC 16). A scrollable list of every registry track on the left, a live preview of
## the highlighted one on the right, rendered by the real Track drawing code inside a SubViewport.
##
## The screen owns ONE selection index (decision 29.12): hover, click, the keyboard and the RACE
## button all funnel through select_track(), so mouse and keyboard can never disagree. Rows are
## plain Controls, not Buttons, and the two real Buttons take no focus.

const BG_COLOR := Color(0.13, 0.32, 0.14)        # == MainMenu.BG_COLOR
const TITLE_COLOR := Color(1.0, 0.92, 0.3)       # == MainMenu.TITLE_COLOR
const STRIPE_COLOR := Color(0.13, 0.13, 0.15, 0.85)
const PANEL_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const HEADING_COLOR := Color(1.0, 0.92, 0.3)
const SUB_COLOR := Color(0.78, 0.82, 0.78)
const LOCATION_COLOR := Color(0.8, 0.85, 0.8)
const DIM_COLOR := Color(0.86, 0.88, 0.86)
const HOVER_COLOR := Color(1.0, 1.0, 1.0, 0.07)
const OUTLINE_SIZE := 4

## SPEC 120: 76 tall, not 62. A row carries four things now -- the name, the location, two times and
## the medal-and-stars -- and at 62 the last two had nowhere to go but on top of each other. With five
## circuits on the list (SPEC 117) there is room to spare.
const ROW_SIZE := Vector2(356, 76)
const ROW_HIGHLIGHT_ALPHA := 0.30
const ROW_BAR_WIDTH := 3.0
const HEADING_HEIGHT := 30.0

const PREVIEW_RECT := Rect2(440, 100, 800, 450)
const PREVIEW_SCALE := 0.625                     # 800/1280 == 450/720
const DOUBLE_CLICK_TIME := 0.35


## The track list, and the race setup (rivals and their difficulty) underneath it.
const LIST_RECT := Rect2(24, 84, 380, 456)
const SETUP_RECT := Rect2(24, 548, 380, 100)

## Row order, flattened over the categories — the index this screen is built around.
var _ids: PackedStringArray = PackedStringArray()
var _rows: Array[Control] = []
var _selected: int = 0
var _hovered: int = -1
var _last_click_index: int = -1
var _last_click_time: float = -1000.0

var _scroll: ScrollContainer = null
var _rows_box: VBoxContainer = null
var _sub_viewport: SubViewport = null
var _preview_track: Track = null
var _preview_car: Car = null
var _name_label: Label = null
var _location_label: Label = null
var _stats_label: Label = null
var _description_label: Label = null
## The medal box over the preview (SPEC 39): the three medal times for the selected car on this track,
## which are won, and the cars that are fastest here.
const MEDAL_BOX_RECT := Rect2(452, 110, 300, 56)
## Under the preview's bottom edge: what the chosen AI level means.
const LEVEL_STRIP_RECT := Rect2(452, 502, 776, 32)
var _level_strip: ColorRect = null
var _level_text: Label = null
var _medal_box: Control = null
var _medal_caption: Label = null
var _medal_labels: Array = []
var _pace_label: Label = null
var _medal_earned: int = 0
var _race_button: Button = null
var _lock_label: Label = null
var _coins_label: Label = null
var _back_button: Button = null

var _laps_button: Button = null     # SPEC 110
var _rival_count_label: Label = null
var _level_buttons: Dictionary = {}

## Frames left in which the preview re-renders: the car's 3D model draws into its own viewport, whose
## texture is only ready a frame or two after the model is built or re-posed.
var _preview_frames: int = 0



func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_collect_ids()
	_build_ui()
	select_track(_index_of(GameState.selected_track))
	_refresh_car()
	# `select_track()` asks the ScrollContainer to scroll the highlighted row into view, but at _ready()
	# time the container has not laid out yet (its v_scroll max is still 0) and the call is a silent
	# no-op. Coming back from a Yas Marina race therefore landed on the select screen with the list at
	# the top and the highlighted row half-clipped off the bottom. Re-issued once the first layout pass
	# has run, which is exactly what `sort_children` reports (decision 30.10).
	_rows_box.sort_children.connect(_scroll_selection_into_view)
	_scroll_selection_into_view.call_deferred()


## Puts the highlighted row inside the visible window. Cheap and idempotent, so it is safe to run on
## every layout pass; it also snaps back to the very top when row 0 is selected, because
## `ensure_control_visible` sees row 0 as already visible and would leave the category heading above it
## clipped.
func _scroll_selection_into_view() -> void:
	if _scroll == null or _selected < 0 or _selected >= _rows.size():
		return
	if _selected == 0:
		_scroll.scroll_vertical = 0
		return
	_scroll.ensure_control_visible(_rows[_selected])


func _collect_ids() -> void:
	_ids = PackedStringArray()
	for category in TrackRegistry.categories():
		for id in TrackRegistry.ids_in(category):
			_ids.append(id)


func _index_of(id: String) -> int:
	for i in _ids.size():
		if _ids[i] == id:
			return i
	return 0


# ------------------------------------------------------------------ public API (SPEC 16.6)

func get_selected_index() -> int:
	return _selected


func get_selected_id() -> String:
	if _ids.is_empty():
		return TrackRegistry.DEFAULT_ID
	return _ids[clampi(_selected, 0, _ids.size() - 1)]


## The one way the selection ever moves. Wraps at both ends; repaints only the two affected rows;
## rebuilds the preview and every readout; re-arms the SubViewport for a single render.
func select_track(index: int) -> void:
	if _ids.is_empty():
		return
	var n := _ids.size()
	var next := ((index % n) + n) % n
	var previous := _selected
	_selected = next
	if previous >= 0 and previous < _rows.size():
		_rows[previous].queue_redraw()
	if next < _rows.size():
		_rows[next].queue_redraw()
		_scroll_selection_into_view()
	_refresh_details()
	_rebuild_preview()


## Starts the highlighted track. GameState.start_race() is what writes selected_track (SPEC 16.6 /
## test 15): moving the highlight alone must never change the stored selection.
func start_selected() -> void:
	GameState.start_race(get_selected_id())


## Back goes to the car screen (the step before this one); the title menu is one more Esc away.
func go_back() -> void:
	GameState.go_to_car_select()


## The preview shows the car the player picked, in the colour they picked.
func _refresh_car() -> void:
	if _preview_car != null:
		CarRegistry.apply(_preview_car, GameState.selected_car, GameState.selected_color)
		if _sub_viewport != null:
			_request_preview()
	# The medals and the pace line are per car, so they follow the car too.
	_refresh_details()


# ------------------------------------------------------------------ input (SPEC 16.6)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		get_viewport().set_input_as_handled()
		select_track(_selected + 1)
	elif event.is_action_pressed("ui_up"):
		get_viewport().set_input_as_handled()
		select_track(_selected - 1)
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		start_selected()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		go_back()


## Hover HIGHLIGHTS; click and the keyboard SELECT (the user asked for those as two things). Hover used
## to call `select_track()`, which made `_hovered` always equal `_selected` -- the hover tint was dead
## code -- and, because `select_track()` scrolls the list, a keyboard move could slide a different row
## under a parked cursor, fire `mouse_entered` and drag the selection back (decision 30.11).
func _on_row_entered(index: int) -> void:
	var previous := _hovered
	_hovered = index
	if previous >= 0 and previous < _rows.size():
		_rows[previous].queue_redraw()
	if index >= 0 and index < _rows.size():
		_rows[index].queue_redraw()


func _on_row_exited(index: int) -> void:
	if _hovered == index:
		_hovered = -1
		if index < _rows.size():
			_rows[index].queue_redraw()


func _on_row_gui_input(event: InputEvent, index: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	accept_event()
	var now := float(Time.get_ticks_msec()) / 1000.0
	var repeat: bool = index == _last_click_index and (now - _last_click_time) <= DOUBLE_CLICK_TIME
	_last_click_index = index
	_last_click_time = now
	if index != _selected:
		select_track(index)
		return
	if mb.double_click or repeat:
		start_selected()


# ------------------------------------------------------------------ the preview (SPEC 16.5)

func _rebuild_preview() -> void:
	if _preview_track == null:
		return
	var id := get_selected_id()
	_preview_track.setup(id)
	_preview_track.set_next_checkpoint(1)
	# SPEC 52: the preview fits whatever world the track lives in, not always one screen.
	# SPEC 130: ... and it fits the ROAD, not the world. `world_size` is the room the camera has, which
	# on a big circuit can be far larger than the road -- the old Switchback left a quarter of its
	# preview as empty grass. Framing `road_bounds()` and centring it fills the picture
	# with the thing the picture is of, on every track, and makes the small circuits bigger too.
	var scaled := _preview_track.get_parent() as Node2D
	if scaled != null:
		var box := _preview_track.road_bounds()
		var fit := minf(PREVIEW_RECT.size.x / maxf(box.size.x, 1.0),
				PREVIEW_RECT.size.y / maxf(box.size.y, 1.0))
		scaled.scale = Vector2(fit, fit)
		scaled.position = PREVIEW_RECT.size * 0.5 - box.get_center() * fit
	if _preview_car != null:
		_preview_car.reset_to(_preview_track.get_start_position(), _preview_track.get_start_heading())
	if _sub_viewport != null:
		_request_preview()


func _refresh_details() -> void:
	var id := get_selected_id()
	var accent := TrackRegistry.get_accent(id)
	var stats := TrackRegistry.get_stats(id)
	_name_label.text = TrackRegistry.get_display_name(id)
	_name_label.add_theme_color_override("font_color", accent)
	_location_label.text = TrackRegistry.get_location(id)
	_description_label.text = TrackRegistry.get_description(id)
	_stats_label.text = "%d m\n%d corners\n%d laps" % [                # SPEC 110: the laps you will race
		int(round(float(stats.get("length_m", 0.0)))),
		int(stats.get("corners", 0)),
		GameState.get_laps(id),
	]
	# SPEC 117: nothing is locked, so the line under the stats says what there is to WIN here instead:
	# the stars this track already carries, and what the difficulty you have selected would put on it.
	if _race_button != null:
		_race_button.disabled = false
		_race_button.text = "RACE"
	if _lock_label != null:
		# SPEC 122: WITH NO RIVALS THERE IS NOTHING TO WIN. `Profile.finish_race()` returns early on
		# `rivals <= 0` -- no coins, no star, no record of a win -- and this line went on advertising a
		# star for a race that cannot award one. A solo run is a time trial, and it says so.
		# SPEC 130: the WARNING stays and the scorekeeping goes. "Not won yet -- a win on HARD is worth 4"
		# was the screen reciting its own bookkeeping at somebody who is trying to pick a track; the
		# stars are already drawn on the row. A run with no rivals awards nothing, which is the one
		# thing here a player cannot see for themselves and would be annoyed to find out afterwards.
		if GameState.opponent_count <= 0:
			_lock_label.text = ("TIME TRIAL  -  no rivals, so no coins and no star. The lap clock and "
					+ "the medals still count.")
			_lock_label.visible = true
		else:
			_lock_label.text = ""
			_lock_label.visible = false
	if _coins_label != null:
		_coins_label.text = "%d coins" % GameState.get_coins()
	_refresh_medals(id)
	_race_button.add_theme_color_override("font_color", Color(1, 1, 1))
	_style_accent_button(_race_button, accent)
	_refresh_row_times()


## The list rows show the stored records too, so a record set this session is visible without a
## reload. Cheap: eight short strings.
func _refresh_row_times() -> void:
	for i in _rows.size():
		var id := _ids[i]
		var times := _rows[i].get_node_or_null("Times") as Label
		if times != null:
			times.text = "lap %s\nrace %s" % [
				GameState.format_time(GameState.get_best_lap(id)),
				GameState.format_time(GameState.get_best_total(id)),
			]


# ------------------------------------------------------------------ construction (SPEC 16.3)

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	BackgroundArt.add(self, "res://art/bg_tracks.png")

	var stripe := ColorRect.new()
	stripe.name = "HeaderStripe"
	stripe.color = STRIPE_COLOR
	_place(stripe, Rect2(0, 0, 1280, 68))
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stripe)

	var title := _make_label("Title", Rect2(24, 16, 500, 40), UiTheme.TITLE, TITLE_COLOR)
	title.text = "SELECT TRACK"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 6)
	add_child(title)


	var list_panel := ColorRect.new()
	list_panel.name = "ListPanel"
	list_panel.color = PANEL_COLOR
	_place(list_panel, LIST_RECT)
	list_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(list_panel)

	var preview_panel := ColorRect.new()
	preview_panel.name = "PreviewPanel"
	preview_panel.color = PANEL_COLOR
	_place(preview_panel, Rect2(424, 84, 832, 564))
	preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview_panel)

	_build_list()
	_build_preview()
	_build_medal_box()
	_build_footer()
	_build_setup()


func _build_list() -> void:
	_scroll = ScrollContainer.new()
	_scroll.name = "ListScroll"
	_place(_scroll, LIST_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)
	_style_scrollbar(_scroll.get_v_scroll_bar())

	_rows_box = VBoxContainer.new()
	_rows_box.name = "Rows"
	_rows_box.add_theme_constant_override("separation", 4)
	_rows_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_scroll.add_child(_rows_box)

	var index := 0
	var grouped := TrackRegistry.categories().size() > 1
	for category in TrackRegistry.categories():
		if not grouped:
			# One list: no heading at all.
			for id in TrackRegistry.ids_in(category):
				_rows_box.add_child(_make_row(id, index))
				index += 1
			continue
		var heading := Label.new()
		heading.name = "Heading_%s" % category
		heading.text = category.to_upper()
		heading.custom_minimum_size = Vector2(ROW_SIZE.x, HEADING_HEIGHT)
		heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		heading.add_theme_font_size_override("font_size", 18)
		heading.add_theme_color_override("font_color", HEADING_COLOR)
		heading.add_theme_color_override("font_outline_color", Color.BLACK)
		heading.add_theme_constant_override("outline_size", OUTLINE_SIZE)
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heading.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		# 10 px left pad without a wrapper node, so the heading stays a direct child of Rows.
		var pad := StyleBoxEmpty.new()
		pad.content_margin_left = 10.0
		heading.add_theme_stylebox_override("normal", pad)
		_rows_box.add_child(heading)

		for id in TrackRegistry.ids_in(category):
			_rows_box.add_child(_make_row(id, index))
			index += 1


func _make_row(id: String, index: int) -> Control:
	var row := Control.new()
	row.name = "Row_%s" % id
	row.custom_minimum_size = ROW_SIZE
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var badge := ColorRect.new()
	badge.name = "Badge"
	badge.color = TrackRegistry.get_accent(id)
	_place(badge, Rect2(10, 8, 8, 46))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badge)

	var name_label := _make_label("Name", Rect2(28, 6, 212, 28), UiTheme.HEADING, Color.WHITE)
	name_label.text = TrackRegistry.get_short_name(id)
	name_label.clip_text = true
	row.add_child(name_label)

	# SPEC 120: 196 wide. The bottom right of the row belongs to the medal and the stars now, and the
	# location used to run straight under them.
	var sub := _make_label("Sub", Rect2(28, 38, 196, 20), UiTheme.CAPTION, UiTheme.MUTED)
	sub.text = TrackRegistry.get_location(id)
	sub.clip_text = true
	row.add_child(sub)

	# SPEC 120: the two times sit in the TOP right of the row, clear of the medal and stars below them
	# ("medals overlap with the timings"): both used to be drawn at y 20, straight over this block.
	var times := _make_label("Times", Rect2(196, 4, 150, 44), UiTheme.CAPTION, UiTheme.MUTED)
	times.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	times.text = "lap %s\nrace %s" % [
		GameState.format_time(GameState.get_best_lap(id)),
		GameState.format_time(GameState.get_best_total(id)),
	]
	row.add_child(times)

	row.draw.connect(_draw_row.bind(row, index))
	row.mouse_entered.connect(_on_row_entered.bind(index))
	row.mouse_exited.connect(_on_row_exited.bind(index))
	row.gui_input.connect(_on_row_gui_input.bind(index))
	_rows.append(row)
	return row


func _draw_row(row: Control, index: int) -> void:
	var accent := TrackRegistry.get_accent(_ids[index]) if index < _ids.size() else Color.WHITE
	var rect := Rect2(Vector2.ZERO, row.size)
	if index == _selected:
		var fill := accent
		fill.a = ROW_HIGHLIGHT_ALPHA
		row.draw_rect(rect, fill, true)
		row.draw_rect(Rect2(0, 0, ROW_BAR_WIDTH, row.size.y), accent, true)
	elif index == _hovered:
		row.draw_rect(rect, HOVER_COLOR, true)
	# SPEC 117/120: STARS -- one for a win on easy, two on medium, three on hard -- along the BOTTOM
	# right of the row, under the times rather than across them, and big enough to see: they were 4.6 px
	# at 16 % alpha when empty, which read as nothing at all ("stars are barely visible").
	if index < _ids.size():
		var stars := GameState.track_stars(_ids[index])
		for k in 3:
			var at := Vector2(292.0 + 16.0 * float(k), 60.0)
			if k < stars:
				_draw_star(row, at, 7.0, Color(1.0, 0.86, 0.35, 1.0))
				_draw_star(row, at, 3.2, Color(1.0, 0.97, 0.80, 1.0))
			else:
				_draw_star(row, at, 7.0, Color(0.80, 0.83, 0.88, 0.38))
	# The medal the selected car has won here, as a disc beside the stars on the same line.
	if index < _ids.size():
		var m := Medals.medal_for(_ids[index], GameState.selected_car, GameState.get_best_lap(_ids[index]))
		if m > Medals.NONE:
			row.draw_circle(Vector2(264, 60), 7.0, Medals.medal_color(m))
			row.draw_arc(Vector2(264, 60), 7.0, 0.0, TAU, 16, Color(0, 0, 0, 0.6), 1.5, true)


func _build_medal_box() -> void:
	_medal_box = Control.new()
	_medal_box.name = "MedalBox"
	_place(_medal_box, MEDAL_BOX_RECT)
	_medal_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_medal_box.draw.connect(_draw_medal_box)
	add_child(_medal_box)
	var o := MEDAL_BOX_RECT.position
	_medal_caption = _make_label("MedalCaption", Rect2(o + Vector2(12, 4), Vector2(280, 20)),
			UiTheme.CAPTION, UiTheme.MUTED)
	add_child(_medal_caption)
	_medal_labels.clear()
	for i in 3:
		var l := _make_label("Medal%d" % i, Rect2(o + Vector2(32 + i * 94, 24), Vector2(70, 24)),
				UiTheme.BODY, UiTheme.TEXT)
		add_child(l)
		_medal_labels.append(l)
	# SPEC 62: the "fastest car here" line was a third row of small print over the track; the car screen
	# already says which tracks a car is best on.
	_pace_label = _make_label("PaceLabel", Rect2(o + Vector2(12, 54), Vector2(280, 22)),
			UiTheme.CAPTION, UiTheme.MUTED)
	_pace_label.visible = false
	_pace_label.clip_text = true
	add_child(_pace_label)


func _draw_medal_box() -> void:
	_medal_box.draw_rect(Rect2(Vector2.ZERO, _medal_box.size), Color(0, 0, 0, 0.62), true)
	for i in 3:
		var m: int = [Medals.GOLD, Medals.SILVER, Medals.BRONZE][i]
		var won := _medal_earned >= m
		var col := Medals.medal_color(m)
		if not won:
			col.a = 0.35
		var c := Vector2(18 + i * 94, 38)
		_medal_box.draw_circle(c, 7.0, col)
		if won:
			_medal_box.draw_arc(c, 9.5, 0.0, TAU, 20, col, 1.5, true)


func _refresh_medals(id: String) -> void:
	if _medal_box == null:
		return
	var car := GameState.selected_car
	_medal_earned = Medals.medal_for(id, car, GameState.get_best_lap(id))
	_medal_caption.text = "MEDALS  -  %s%s" % [CarRegistry.get_display_name(car),
			"   (%s won)" % Medals.medal_name(_medal_earned) if _medal_earned > Medals.NONE else ""]
	for i in 3:
		var m: int = [Medals.GOLD, Medals.SILVER, Medals.BRONZE][i]
		var l: Label = _medal_labels[i]
		l.text = GameState.format_time(Medals.target(id, car, m))
		l.add_theme_color_override("font_color", Color.WHITE if _medal_earned >= m else Color(1, 1, 1, 0.55))
	var names := PackedStringArray()
	for c in Medals.cars_by_pace(id).slice(0, 2):
		names.append(CarRegistry.get_display_name(c))
	_pace_label.text = "Fastest here: %s" % ", ".join(names)
	_medal_box.queue_redraw()


func get_medal_text() -> String:
	if _medal_caption == null:
		return ""
	var times := PackedStringArray()
	for l in _medal_labels:
		times.append((l as Label).text)
	return "%s | %s | %s" % [_medal_caption.text, " ".join(times), _pace_label.text]


func _build_preview() -> void:
	var box := SubViewportContainer.new()
	box.name = "PreviewBox"
	box.stretch = true
	_place(box, PREVIEW_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_sub_viewport = SubViewport.new()
	_sub_viewport.name = "SubViewport"
	_sub_viewport.size = Vector2i(int(PREVIEW_RECT.size.x), int(PREVIEW_RECT.size.y))
	_sub_viewport.transparent_bg = false
	_sub_viewport.disable_3d = true
	_sub_viewport.gui_disable_input = true
	_request_preview()
	box.add_child(_sub_viewport)

	# Track draws a full 1280x720 world (grass + barrier band); scaling the whole world keeps every
	# drawing routine in its real coordinates and the SubViewport clips it exactly (decision 29.11).
	var scaled := Node2D.new()
	scaled.name = "Scaled"
	scaled.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	_sub_viewport.add_child(scaled)

	_preview_track = Track.new()
	_preview_track.name = "Track"
	scaled.add_child(_preview_track)

	_preview_car = preload("res://scenes/car.tscn").instantiate() as Car
	_preview_car.name = "Car"
	_preview_car.auto_process = false          # scenery: it is never stepped
	_preview_car.rope_visible = false
	scaled.add_child(_preview_car)


## Footer geometry. SPEC 16.3's table put Description 800 px wide under a 180 px stats block and
## CircuitName/Location 32 px apart; measured, both pairs overlap (a 24 px Label is 34 px tall, and
## 440+800 runs straight through the stats column at x 1060). The block below keeps every SPEC
## element, column and reading order and only opens the gaps — see the note appended to SPEC 19.5.
func _build_footer() -> void:
	_name_label = _make_label("CircuitName", Rect2(440, 552, 600, 32), UiTheme.HEADING, Color.WHITE)
	add_child(_name_label)

	# SPEC 62: the location is on the row in the list; repeating it here is a line nobody reads twice.
	_location_label = _make_label("CircuitLocation", Rect2(440, 592, 600, 24), UiTheme.CAPTION, LOCATION_COLOR)
	_location_label.visible = false
	add_child(_location_label)

	_stats_label = _make_label("StatsLabel", Rect2(1060, 544, 180, 100), UiTheme.BODY, UiTheme.TEXT)
	_stats_label.add_theme_constant_override("line_spacing", -2)
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_stats_label)

	# 600 wide: it stops at x 1040, clear of the stats column.
	# SPEC 97: two lines when a description needs them -- it used to run past its box.
	# SPEC 122: and the REWARD line underneath has its own row now. The description wraps to two lines
	# on the longer circuits and the reward line was pinned at y 620, straight across the second one
	# (measured on the Serpent: 383 x 20 px of shared pixels). The bottom of this screen is a stack --
	# description, then reward, then complexity, then records -- and nothing in it is pinned over
	# anything else.
	_description_label = _make_label("Description", Rect2(440, 586, 680, 52), UiTheme.BODY, UiTheme.MUTED)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_description_label)

	# SPEC 130: TRACK COMPLEXITY and the best-lap/best-race line used to sit along this bar. Neither is
	# a reason to pick one circuit over another at the moment of picking: the complexity pips rate
	# something the preview already shows, and your own records are the finish screen's business. What
	# is left on this screen is the map, the name, the medals and what you are about to drive.

	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.text = "Back"
	_back_button.focus_mode = Control.FOCUS_NONE     # Enter belongs to the list, always
	_back_button.add_theme_font_size_override("font_size", 22)
	_place(_back_button, Rect2(UiTheme.MARGIN, 720.0 - UiTheme.BUTTON_H - UiTheme.MARGIN, 200, UiTheme.BUTTON_H))
	_back_button.pressed.connect(go_back)
	add_child(_back_button)

	# SPEC 122: its own row under the description, and narrow enough to clear the RACE button at x 1016.
	_lock_label = _make_label("LockLabel", Rect2(440, 640, 560, 22), UiTheme.CAPTION, UiTheme.WARN)
	_lock_label.visible = false
	add_child(_lock_label)
	_coins_label = _make_label("CoinsLabel", Rect2(1000, 16, 256, 40), UiTheme.HEADING, UiTheme.ACCENT)
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_coins_label)

	_race_button = Button.new()
	_race_button.name = "RaceButton"
	_race_button.text = "RACE"
	_race_button.focus_mode = Control.FOCUS_NONE
	_race_button.add_theme_font_size_override("font_size", 26)
	_race_button.add_theme_color_override("font_outline_color", Color.BLACK)
	_race_button.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	_place(_race_button, Rect2(1016, 660, 240, 48))
	_race_button.pressed.connect(start_selected)
	add_child(_race_button)



# ------------------------------------------------------------------ small helpers

## RIVALS [-] n [+]  and  DIFFICULTY [Easy] [Medium] [Hard]. That is the whole race setup: cars and
## colours and driving styles are random (GameState.resolve_opponents).
func _build_setup() -> void:
	var panel := ColorRect.new()
	panel.name = "SetupPanel"
	panel.color = PANEL_COLOR
	_place(panel, SETUP_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	# SPEC 110: sprint or endurance, one button: "4 LAPS" / "10 LAPS".
	# SPEC 130: x 170 put it straight across the Back button, which runs from x 16 to x 216 -- 46 px of
	# shared pixels on the one row of this screen that has two controls on it. It starts clear of Back
	# now and stops short of the preview panel's edge at x 424.
	_laps_button = _setup_button("LapsButton", "", Rect2(232, 660, 190, 48))
	_laps_button.pressed.connect(func() -> void:
		GameState.set_endurance(not GameState.is_endurance())
		_refresh_setup()
		_refresh_details())
	var cap := _make_label("RivalsCaption", Rect2(38, 552, 130, 44), UiTheme.CAPTION, UiTheme.MUTED)
	cap.text = "RIVALS"
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(cap)
	var less := _setup_button("RivalsLess", "-", Rect2(206, 552, 48, 44))
	less.pressed.connect(func() -> void: set_rival_count(GameState.opponent_count - 1))
	_rival_count_label = _make_label("RivalCount", Rect2(254, 552, 92, 44), UiTheme.HEADING, UiTheme.TEXT)
	_rival_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rival_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_rival_count_label)
	var more := _setup_button("RivalsMore", "+", Rect2(346, 552, 48, 44))
	more.pressed.connect(func() -> void: set_rival_count(GameState.opponent_count + 1))

	var cap2 := _make_label("LevelCaption", Rect2(38, 600, 130, 44), UiTheme.CAPTION, UiTheme.MUTED)
	cap2.text = "RIVAL SKILL"
	cap2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(cap2)
	var x := 160.0
	for lv in GameState.DIFFICULTIES:
		var b := _setup_button("Level_%s" % lv, String(lv).capitalize(), Rect2(x, 600, 76, 44))
		b.toggle_mode = true
		b.pressed.connect(set_rival_difficulty.bind(String(lv)))
		b.tooltip_text = AIDriver.level_text(String(lv))
		_level_buttons[lv] = b
		x += 78.0
	# What the chosen level means, along the bottom of the preview (SPEC 40).
	_level_strip = ColorRect.new()
	_level_strip.name = "LevelStrip"
	_level_strip.color = Color(0, 0, 0, 0.62)
	_place(_level_strip, LEVEL_STRIP_RECT)
	_level_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_level_strip)
	_level_text = _make_label("LevelText", LEVEL_STRIP_RECT.grow_individual(-12, 0, -12, 0),
			UiTheme.CAPTION, UiTheme.TEXT)
	_level_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_text.clip_text = true
	add_child(_level_text)
	_refresh_setup()


func _setup_button(node_name: String, text: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	_place(b, rect)
	add_child(b)
	return b


func set_rival_count(n: int) -> void:
	GameState.set_opponent_count(n)
	_refresh_setup()


func set_rival_difficulty(level: String) -> void:
	GameState.set_rival_difficulty(level)
	_refresh_setup()


func _refresh_setup() -> void:
	var n := GameState.opponent_count
	_rival_count_label.text = "%d" % n if n > 0 else "none"
	if _laps_button != null and _selected < _ids.size():
		# SPEC 122: "4 LAPS" did not say that pressing it changes the format, nor what the other one is.
		var id2 := String(_ids[_selected])
		var laps := GameState.get_laps(id2)
		_laps_button.text = "%s  %d LAPS" % ["ENDURANCE" if GameState.is_endurance() else "SPRINT", laps]
		_laps_button.tooltip_text = "Sprint or endurance -- press to swap."
	var current := GameState.get_rival_difficulty()
	for lv in _level_buttons.keys():
		var b: Button = _level_buttons[lv]
		b.set_pressed_no_signal(lv == current)
		b.disabled = n == 0
	if _level_text != null:
		_level_strip.visible = n > 0
		_level_text.visible = n > 0
		# SPEC 62: one line. The personalities explain themselves on the road, and the second line was
		# a paragraph sitting on top of the track.
		_level_text.text = "%d rival%s -- %s" % [n, "" if n == 1 else "s", AIDriver.level_text(current)]


func get_level_text() -> String:
	return _level_text.text if _level_text != null and _level_text.visible else ""


func _make_label(node_name: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(label, rect)
	return label


## Absolute placement in the 1280x720 design space (SPEC decision 11: everything built in code).
func _place(control: Control, rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.position.x + rect.size.x
	control.offset_bottom = rect.position.y + rect.size.y
	control.custom_minimum_size = rect.size


func _style_accent_button(button: Button, accent: Color) -> void:
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		var tint := accent
		match state:
			"hover":
				tint = accent.lightened(0.18)
			"pressed":
				tint = accent.darkened(0.25)
		box.bg_color = Color(tint.r, tint.g, tint.b, 0.92)
		box.border_color = Color(1, 1, 1, 0.55)
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		button.add_theme_stylebox_override(state, box)


## The default scrollbar is dark grey on a dark panel and reads as nothing. SPEC 16.7 wants the bar to
## be the cue that the list continues past eight tracks, so it gets an explicit light grabber.
func _style_scrollbar(bar: VScrollBar) -> void:
	if bar == null:
		return
	bar.custom_minimum_size = Vector2(10, 0)
	var track_box := StyleBoxFlat.new()
	track_box.bg_color = Color(1, 1, 1, 0.08)
	track_box.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("scroll", track_box)
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var grab := StyleBoxFlat.new()
		grab.bg_color = Color(1, 1, 1, 0.45 if state == "grabber" else 0.70)
		grab.set_corner_radius_all(5)
		bar.add_theme_stylebox_override(state, grab)


func _request_preview() -> void:
	_preview_frames = 4
	if _sub_viewport != null:
		_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _process(_delta: float) -> void:
	if _preview_frames > 0 and _sub_viewport != null:
		_preview_frames -= 1
		_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## SPEC 117: one star, `r` across, drawn as a ten-point polygon (a five-pointed star is the one shape
## every player already reads as "you have done this").
static func _draw_star(canvas: CanvasItem, at: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + TAU * float(i) / 10.0
		var rad := r if i % 2 == 0 else r * 0.45
		pts.append(at + Vector2(cos(a), sin(a)) * rad)
	canvas.draw_colored_polygon(pts, color)
