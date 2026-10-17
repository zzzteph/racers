class_name FinishScreen
extends CanvasLayer
## End-of-race results overlay.

signal race_again_requested
signal menu_requested
## SPEC 112: the feedback card, from the results.
signal feedback_requested

const NEW_RECORD_COLOR := Color(1.0, 0.85, 0.2)

const MIN_PANEL_SIZE := Vector2(480, 240)

var _root: Control
var _panel: PanelContainer
var _title_label: Label
var _total_label: Label
var _laps_label: Label
var _best_label: Label
var _record_label: Label
var _medal_label: Label
var _reward_label: Label
## SPEC 124: "FINISHED ON THREE WHEELS" -- recognition for what the car went through, never a payout.
var _survival_label: Label = null
var _place_label: Label
var _points_label: Label
var _standings_label: Label
var _race_again_button: Button


func _init() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


## Online, the server scores the race after everyone is home (`Net.points_awarded`); the line goes under
## the place whenever it arrives -- before or after the card -- and never for a race nobody scores
## (offline, or a LAN host), where the signal simply never comes.
func _ready() -> void:
	var net := get_node_or_null("/root/Net")
	if net != null and net.has_signal("points_awarded"):
		net.points_awarded.connect(set_points)
		_apply_last_award()


func _apply_last_award() -> void:
	var net := get_node_or_null("/root/Net")
	if net == null or not ("last_award" in net):
		return
	var a: Dictionary = net.last_award
	if not a.is_empty():
		set_points(int(a["points"]), int(a["total"]), int(a["rank"]))


## "+7 pts  -  leaderboard #12 (58 pts)": what this race earned on the server's leaderboard.
func set_points(points: int, total: int, rank: int) -> void:
	_points_label.text = "+%d pts  -  leaderboard #%d (%d pts)" % [points, rank, total]
	_points_label.visible = true
	_fit_panel()


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	# SPEC 62: the panel is centred by a CenterContainer, not by offsets computed from its own minimum
	# size. Setting offsets against a Container's min size fights the layout -- the results panel ended up
	# 865 px tall for 404 px of content, with the heading off the top of the screen.
	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(centre)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	# Opaque background: the default PanelContainer style is translucent, which let the in-race HUD info
	# panel (infield on the circle track) show through the results and render both texts unreadable.
	_panel.add_theme_stylebox_override("panel", _make_opaque_panel_style())
	_panel.custom_minimum_size = MIN_PANEL_SIZE
	centre.add_child(_panel)
	var panel := _panel

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	_title_label = _make_label(box, "FinishedLabel", UiTheme.HEADING)
	_place_label = _make_label(box, "PlaceLabel", UiTheme.TITLE)
	_place_label.visible = false
	_points_label = _make_label(box, "PointsLabel", UiTheme.BODY)
	_points_label.add_theme_color_override("font_color", NEW_RECORD_COLOR)
	_points_label.visible = false
	_standings_label = _make_label(box, "StandingsLabel", UiTheme.BODY)
	_standings_label.visible = false
	_title_label.text = "Finished!"
	_total_label = _make_label(box, "TotalLabel", UiTheme.HEADING)
	_laps_label = _make_label(box, "LapsLabel", UiTheme.BODY)
	_best_label = _make_label(box, "BestLabel", UiTheme.BODY)
	_medal_label = _make_label(box, "MedalLabel", UiTheme.BODY)
	_medal_label.visible = false
	_reward_label = _make_label(box, "RewardLabel", UiTheme.BODY)
	_reward_label.visible = false
	_survival_label = _make_label(box, "SurvivalLabel", UiTheme.CAPTION)
	_survival_label.visible = false
	_survival_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.94))
	_record_label = _make_label(box, "RecordLabel", UiTheme.CAPTION)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)

	_race_again_button = _make_button(buttons, "RaceAgainButton", "Race again")
	_race_again_button.pressed.connect(func() -> void: race_again_requested.emit())
	var menu := _make_button(buttons, "MenuButton", "Tracks")
	menu.pressed.connect(func() -> void: menu_requested.emit())
	# SPEC 112: "how was that?" -- narrower than the two that matter, the same height.
	var feedback := _make_button(buttons, "FeedbackButton", "Feedback")
	feedback.custom_minimum_size = Vector2(200, 64)
	feedback.pressed.connect(func() -> void: feedback_requested.emit())


## Fully opaque dialog background (shared look for the finish screen and the pause menu), so nothing that
## is drawn underneath (HUD labels, road, countdown text) bleeds through the dialog text.
static func _make_opaque_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.14)
	sb.border_color = Color(0.45, 0.47, 0.52)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(4)
	return sb


func _make_label(parent: Control, node_name: String, font_size: int) -> Label:
	var l := Label.new()
	l.name = node_name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", UiTheme.snap_size(font_size))   # SPEC 62
	parent.add_child(l)
	return l


func _make_button(parent: Control, node_name: String, text: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(280, 64)       # SPEC 97: a thumb's worth
	b.add_theme_font_size_override("font_size", UiTheme.HEADING)  # SPEC 62
	UiTheme.style_button(b)
	parent.add_child(b)
	return b


## "1st of 5" -- shown above the times when there were rivals; hidden for a solo race.
func set_place(place: int, field: int) -> void:
	if field <= 1 or place <= 0:
		_place_label.visible = false
		return
	var suffix := "th"
	if place % 100 < 11 or place % 100 > 13:
		suffix = {1: "st", 2: "nd", 3: "rd"}.get(place % 10, "th")
	_place_label.text = "%d%s of %d%s" % [place, suffix, field, "  -  WINNER!" if place == 1 else ""]
	_place_label.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.2) if place == 1 else Color(0.9, 0.92, 0.95))
	_place_label.visible = true


## The finishing order, one line per driver ("1. Ann - Red Formula"). Hidden for a solo race.
func set_standings(lines: PackedStringArray) -> void:
	_standings_label.text = "\n".join(lines)
	_standings_label.visible = lines.size() > 1


func show_results(track_name: String, total_time: float, lap_times: Array, best_lap: float,
		new_best_lap: bool, new_best_total: bool, record_lap: float, record_total: float) -> void:

	_title_label.text = "Finished!  -  %s" % track_name if track_name != "" else "Finished!"

	_total_label.text = "Total  %s%s" % [GameState.format_time(total_time),
			"   NEW RECORD!" if new_best_total else ""]
	_total_label.remove_theme_color_override("font_color")
	if new_best_total:
		_total_label.add_theme_color_override("font_color", NEW_RECORD_COLOR)

	# SPEC 62: every lap on one wrapped line instead of one row each -- a ten-lap race used to be ten
	# rows of the same shape, which is a table nobody reads on a results screen ("*" marks the best).
	var lines: PackedStringArray = []
	for i in lap_times.size():
		var t := float(lap_times[i])
		var mark := "*" if is_finite(best_lap) and is_equal_approx(t, best_lap) else ""
		lines.append("%s%s" % [GameState.format_time(t), mark])
	# One line, wrapped inside a fixed width: without the width an autowrapped label asks the panel for
	# a minimum size of the whole string and the panel grows off the screen.
	_laps_label.text = ("Laps   " + "   ".join(lines)) if not lines.is_empty() else ""
	_laps_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_laps_label.custom_minimum_size = Vector2(MIN_PANEL_SIZE.x - 44.0, 0.0)

	_best_label.text = "Best lap  %s%s" % [GameState.format_time(best_lap),
			"   NEW RECORD!" if new_best_lap else ""]
	_best_label.remove_theme_color_override("font_color")
	if new_best_lap:
		_best_label.add_theme_color_override("font_color", NEW_RECORD_COLOR)

	# "NEW RECORD!" is shown only on the improved lines above; this line just lists the stored records.
	_record_label.text = "Track records:  lap %s   total %s" % [
			GameState.format_time(record_lap), GameState.format_time(record_total)]

	_points_label.visible = false
	_apply_last_award()
	_fit_panel()
	visible = true
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_inside_tree():
		_race_again_button.grab_focus()


## The medal this race's best lap won (SPEC 39), and what the next one needs. `medal` 0 = none.
func set_medal(medal: int, text: String) -> void:
	_medal_label.text = text
	_medal_label.visible = text != ""
	_medal_label.add_theme_color_override("font_color", Medals.medal_color(medal) if medal > 0 else Color(0.85, 0.85, 0.85))
	_fit_panel()


## What the race paid and opened (SPEC 56): "+300 coins   FIGURE 8 UNLOCKED".
func set_reward(text: String) -> void:
	_reward_label.text = text
	_reward_label.visible = text != ""
	_reward_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_fit_panel()


## SPEC 124: WHAT THE CAR WENT THROUGH, as a line of recognition on the card. Deliberately NOT a payout:
## anything that pays for damage is a thing to farm, and the first player who works out that they earn
## more by driving into walls has stopped racing. This says what happened and nothing else, which is
## what makes it safe to award for something the player did not necessarily choose.
func set_survival(text: String) -> void:
	if _survival_label == null:
		return
	_survival_label.text = text
	_survival_label.visible = text != ""
	_fit_panel()


func get_survival_text() -> String:
	return _survival_label.text if _survival_label != null and _survival_label.visible else ""


func get_reward_text() -> String:
	return _reward_label.text if _reward_label.visible else ""


func get_medal_text() -> String:
	return _medal_label.text if _medal_label.visible else ""


## Sizes the dialog to its content (centred), so the buttons sit at the bottom of the panel instead of
## leaving a large empty area under them.
## The panel is as big as its contents, never smaller than MIN_PANEL_SIZE, and the CenterContainer puts
## it in the middle. Kept as a function because every setter calls it after changing a line.
func _fit_panel() -> void:
	_panel.custom_minimum_size = MIN_PANEL_SIZE


func hide_screen() -> void:
	visible = false
	_root.visible = false


## After a network race the two buttons go somewhere else, and SPEC 125 makes them say where: "Lobby"
## and "Leave" were the names of the code paths, not of the places. One goes BACK TO THE ROOM -- the
## same people, the same chat -- and the other leaves multiplayer altogether.
func set_online(on: bool) -> void:
	_race_again_button.text = "Back to room" if on else "Race again"
	var menu := find_child("MenuButton", true, false) as Button
	if menu != null:
		menu.text = "Leave multiplayer" if on else "Tracks"
