extends Control
## THE GARAGE (SPEC 64): where a car is set up. Parts, colours, effects and ready-made profiles, each in
## its own tab, with the car on the right and -- the point of the screen -- what the thing under the
## cursor would DO to it, before any coins are spent.
##
## It is a screen of its own because the car screen was doing two jobs at once: choosing which car to
## drive and rebuilding it. Choosing happens there; rebuilding happens here.
##
## Reading the panel on the right: the four bars are the car as it is now, and the brighter overlay is
## what the highlighted part would make of it. Under them, what that part is good and bad at -- because
## nothing in the catalogue is simply better than what it replaces.

const BG_COLOR := Color(0.10, 0.12, 0.16)
const TABS_RECT := Rect2(24, 80, 232, 568)
const LIST_RECT := Rect2(272, 80, 520, 568)
const CAR_RECT := Rect2(808, 80, 448, 568)
const MODEL_RECT := Rect2(832, 104, 400, 224)
const TAB_H := 56.0
const ROW_H := 64.0
const BAR_W := 400.0

## The tabs, in order: the five part slots, then the two cosmetics, then the profiles.
const TABS := ["engine", "wheels", "suspension", "body", "rope", "charge", "colour", "effects", "profiles"]

var _tab: String = "engine"
var _highlight: int = 0
var _model: CarModel3D = null
var _angle: float = 0.6
var _tab_rows: Array[Control] = []
var _rows: Array[Control] = []
var _title: Label = null
var _coins: Label = null
var _detail: Control = null
## SPEC 130: what the highlighted part does, under the bars, in a box that scrolls rather than spilling
## over the BUY button.
var _notes: RichTextLabel = null
var _action: Button = null
var _fx: GarageEffects = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# SPEC 71: the garage is for a car you own. Reached with a locked one selected (a stale scene, a
	# room that chose it for you), it goes straight back rather than selling parts for a car you have not
	# got.
	if not GameState.profile.is_car_unlocked(GameState.selected_car):
		go_back.call_deferred()
		return
	_build()
	_refresh()


func _process(delta: float) -> void:
	_angle = fmod(_angle + delta * 0.55, TAU)
	if _model != null:
		_model.pose(_angle, 0.0, 0.0, 0.0, 0.0, PackedFloat32Array([0, 0, 0, 0]), 0.0, 0.0)
	if _fx != null:
		_fx.set_heading(_angle)


# ---------------------------------------------------------------- what is in the current tab

## Every row of the current tab: [{id, name, price, owned, fitted, good, bad}].
func rows_for(tab: String) -> Array:
	var car_id := GameState.selected_car
	var p: Profile = GameState.profile
	var out: Array = []
	match tab:
		"colour":
			var pal: Array = CarRegistry.get_palette(car_id)
			for i in pal.size():
				# SPEC 111: every colour is free; the row is a picker, not a shop.
				out.append({"id": str(i), "name": String(pal[i]["name"]), "price": 0,
						"owned": p.is_color_unlocked(car_id, i), "fitted": GameState.selected_color == i,
						"good": "A colour. It changes nothing but the car.", "bad": "",
						"color": pal[i]["body"]})
		"effects":
			for name in Profile.EFFECTS:
				var e := String(name)
				out.append({"id": e, "name": e.capitalize(), "price": Profile.EFFECT_PRICE,
						"owned": p.has_effect(e), "fitted": p.is_equipped(e),
						"good": _effect_blurb(e), "bad": "", "color": Color(0.5, 0.6, 0.7)})
		"profiles":
			for prof in Parts.PROFILES:
				var d: Dictionary = prof
				var missing := _profile_cost(String(d["id"]))
				out.append({"id": String(d["id"]), "name": String(d["name"]), "price": missing,
						"owned": missing <= 0, "fitted": _profile_fitted(String(d["id"])),
						"good": String(d["blurb"]), "bad": "", "color": UiTheme.ACCENT})
		_:
			for part in Parts.in_slot(tab):
				var d2: Dictionary = part
				var id := String(d2["id"])
				out.append({"id": id, "name": String(d2["name"]), "price": Parts.price(id),
						"owned": p.owns_part(car_id, id), "fitted": p.fitted_part(car_id, tab) == id,
						"good": String(d2.get("good", "")), "bad": String(d2.get("bad", "")),
						"color": Color(0.6, 0.65, 0.7)})
	return out


static func _effect_blurb(name: String) -> String:
	match name:
		"flames": return "A burner out of the exhaust under power."
		"stars": return "A sparkle trail behind the car."
		"underglow": return "A pool of your colour under the car."
		_: return "Tyre smoke in your colour."


## What the parts of a profile you do NOT own would cost, 0 when you own them all.
func _profile_cost(profile_id: String) -> int:
	var total := 0
	for slot in Parts.SLOTS:
		var part := String(Parts.profile_parts(profile_id)[slot])
		if not GameState.profile.owns_part(GameState.selected_car, part):
			total += Parts.price(part)
	return total


func _profile_fitted(profile_id: String) -> bool:
	var want := Parts.profile_parts(profile_id)
	for slot in Parts.SLOTS:
		if GameState.profile.fitted_part(GameState.selected_car, String(slot)) != String(want[slot]):
			return false
	return true


# ---------------------------------------------------------------- doing it

## Fits (or buys) whatever is highlighted. Returns true when something changed.
func take_action() -> bool:
	var list := rows_for(_tab)
	if _highlight < 0 or _highlight >= list.size():
		return false
	var row: Dictionary = list[_highlight]
	var p: Profile = GameState.profile
	var car_id := GameState.selected_car
	var did := false
	match _tab:
		"colour":
			var index := int(String(row["id"]))
			did = p.is_color_unlocked(car_id, index) or p.buy_color(car_id, index)
			if did:
				GameState.select_color(index)
		"effects":
			var name := String(row["id"])
			if p.has_effect(name):
				p.toggle_equip(name)
				did = true
			else:
				did = p.buy_effect(name)
		"profiles":
			did = _fit_profile(String(row["id"]))
		_:
			var part := String(row["id"])
			did = p.fit_part(car_id, part) if p.owns_part(car_id, part) else p.buy_part(car_id, part)
	if did:
		GameState.save_profile()
		Audio.beep(true)
		_refresh()
	else:
		Audio.beep(false)
	return did


## Fits every part of a profile, buying what is missing when there are coins for all of it.
func _fit_profile(profile_id: String) -> bool:
	var want := Parts.profile_parts(profile_id)
	var cost := _profile_cost(profile_id)
	if cost > GameState.get_coins():
		return false
	for slot in Parts.SLOTS:
		var part := String(want[String(slot)])
		if not GameState.profile.owns_part(GameState.selected_car, part):
			GameState.profile.buy_part(GameState.selected_car, part)
		GameState.profile.fit_part(GameState.selected_car, part)
	return true


func select_row(index: int) -> void:
	var list := rows_for(_tab)
	if list.is_empty():
		return
	_highlight = posmod(index, list.size())
	_refresh()


func select_tab(tab: String) -> void:
	if not TABS.has(tab):
		return
	_tab = tab
	_highlight = 0
	_refresh()


func get_tab() -> String:
	return _tab


func go_back() -> void:
	GameState.go_to_car_select()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		go_back()
	elif event.is_action_pressed("ui_down"):
		get_viewport().set_input_as_handled()
		select_row(_highlight + 1)
	elif event.is_action_pressed("ui_up"):
		get_viewport().set_input_as_handled()
		select_row(_highlight - 1)
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		take_action()


# ---------------------------------------------------------------- drawing

func _refresh() -> void:
	var car_id := GameState.selected_car
	_title.text = "GARAGE  -  %s" % CarRegistry.get_display_name(car_id)
	_coins.text = "%d coins" % GameState.get_coins()
	var list := rows_for(_tab)
	_highlight = clampi(_highlight, 0, maxi(list.size() - 1, 0))
	for i in _rows.size():
		_rows[i].visible = i < list.size()
		_rows[i].queue_redraw()
	for t in _tab_rows:
		t.queue_redraw()
	if _model != null:
		var pal: Array = CarRegistry.get_palette(car_id)
		var ci: int = GameState.selected_color
		if _tab == "colour" and _highlight < pal.size():
			ci = _highlight                                  # the colour under the cursor, on the car
		_model.build(CarRegistry.get_style(car_id), pal[ci]["body"], pal[ci]["stripe"])
		# SPEC 67: the car shown is the car as the highlighted row would leave it.
		_model.set_look(_preview_fitted())
	if _fx != null:
		_fx.set_effects(_preview_effects(), CarRegistry.get_body_color(car_id, GameState.selected_color))
	_detail.queue_redraw()
	_refresh_notes(list)
	_refresh_action(list)


## SPEC 130: the good and the bad of the highlighted row, in the scrolling box under the bars. The
## warning is red, the way it was when it was drawn -- a downside in the same colour as the upside is a
## downside nobody reads.
func _refresh_notes(list: Array) -> void:
	if _notes == null:
		return
	var text := ""
	if _highlight < list.size():
		var item: Dictionary = list[_highlight]
		text = String(item.get("good", ""))
		var bad := String(item.get("bad", ""))
		if bad != "":
			text += ("\n" if text != "" else "") + "[color=#%s]%s[/color]" % [UiTheme.WARN.to_html(false), bad]
	if _notes.text != text:
		_notes.text = text
		_notes.get_parent().set_deferred("scroll_vertical", 0)


## The effects the preview should wear: what is equipped, plus the one under the cursor (SPEC 67), so
## a click on "Flames" shows flames before it is bought.
func _preview_effects() -> PackedStringArray:
	var worn := PackedStringArray(GameState.profile.equipped)
	if _tab == "effects":
		var list := rows_for("effects")
		if _highlight >= 0 and _highlight < list.size():
			var name := String((list[_highlight] as Dictionary)["id"])
			if not worn.has(name):
				worn.append(name)
	return worn


## The parts the car would have with the highlighted row fitted -- what the bars preview.
func _preview_fitted() -> Dictionary:
	var fitted: Dictionary = GameState.profile.fitted(GameState.selected_car).duplicate()
	var list := rows_for(_tab)
	if _highlight < 0 or _highlight >= list.size():
		return fitted
	var row: Dictionary = list[_highlight]
	if Parts.SLOTS.has(_tab):
		fitted[_tab] = String(row["id"])
	elif _tab == "profiles":
		fitted = Parts.profile_parts(String(row["id"]))
	return fitted


func _refresh_action(list: Array) -> void:
	if _action == null:
		return
	if list.is_empty():
		_action.visible = false
		return
	var row: Dictionary = list[_highlight]
	_action.visible = true
	var price := int(row["price"])
	if bool(row["fitted"]) and _tab != "effects":
		_action.text = "FITTED"
		_action.disabled = true
	elif bool(row["owned"]):
		_action.text = "TAKE OFF" if _tab == "effects" and bool(row["fitted"]) else "FIT"
		_action.disabled = false
	else:
		_action.text = "BUY  %d" % price
		_action.disabled = price > GameState.get_coins()


func _draw_tab(row: Control, index: int) -> void:
	var tab := String(TABS[index])
	var rect := Rect2(Vector2.ZERO, row.size)
	row.draw_rect(rect, UiTheme.ROW_SELECTED if tab == _tab else Color(1, 1, 1, 0.04), true)
	if tab == _tab:
		row.draw_rect(Rect2(0, 0, 3, rect.size.y), UiTheme.ACCENT, true)
	var font := row.get_theme_default_font()
	row.draw_string(font, Vector2(20, 36), tab.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.BODY,
			UiTheme.TEXT if tab == _tab else UiTheme.MUTED)


func _draw_row(row: Control, index: int) -> void:
	var list := rows_for(_tab)
	if index >= list.size():
		return
	var item: Dictionary = list[index]
	var rect := Rect2(Vector2.ZERO, row.size)
	row.draw_rect(rect, UiTheme.ROW_SELECTED if index == _highlight else Color(1, 1, 1, 0.04), true)
	var font := row.get_theme_default_font()
	var owned := bool(item["owned"])
	row.draw_rect(Rect2(12, 16, 8, rect.size.y - 32), item.get("color", Color.WHITE) as Color, true)
	row.draw_string(font, Vector2(34, 30), String(item["name"]), HORIZONTAL_ALIGNMENT_LEFT, 300,
			UiTheme.BODY, UiTheme.TEXT if owned else UiTheme.MUTED)
	var right := ""
	var colour := UiTheme.MUTED
	if bool(item["fitted"]):
		right = "FITTED"
		colour = UiTheme.ACCENT
	elif owned:
		right = "OWNED"
	else:
		right = "%d" % int(item["price"])
		colour = UiTheme.ACCENT if int(item["price"]) <= GameState.get_coins() else UiTheme.WARN
	row.draw_string(font, Vector2(rect.size.x - 140.0, 30), right, HORIZONTAL_ALIGNMENT_RIGHT, 128,
			UiTheme.CAPTION, colour)
	row.draw_string(font, Vector2(34, 52), String(item.get("good", "")), HORIZONTAL_ALIGNMENT_LEFT,
			int(rect.size.x - 56.0), UiTheme.CAPTION, UiTheme.MUTED)


## The car as it is, and what the highlighted row would make of it (SPEC 64).
func _draw_detail() -> void:
	var font := _detail.get_theme_default_font()
	var car_id := GameState.selected_car
	var now: Dictionary = GameState.profile.fitted(car_id)
	var soon := _preview_fitted()
	var rows := [
		["TOP SPEED", "max_speed", float(CarRegistry.get_max_speed_kmh(car_id)), 150.0, false],
		["DRIVE", "acceleration", 1.0, 1.35, false],
		["GRIP", "tire_peak_accel", 1.0, 1.35, false],
		["WEIGHT", "mass", float(CarRegistry.get_weight_kg(car_id)), 2000.0, true],
	]
	var y := 0.0
	for r in rows:
		var caption := String(r[0])
		var field := String(r[1])
		var base := float(r[2])
		var scale_to := float(r[3])
		var lower_is_better := bool(r[4])
		var a := base * Parts.scaled(now, field)
		var b := base * Parts.scaled(soon, field)
		_detail.draw_string(font, Vector2(0, y + 14), caption, HORIZONTAL_ALIGNMENT_LEFT, 200,
				UiTheme.CAPTION, UiTheme.MUTED)
		var text := "%d km/h" % int(round(b)) if field == "max_speed" else \
				("%d kg" % int(round(b)) if field == "mass" else "%d %%" % int(round(b * 100.0)))
		var changed := not is_equal_approx(a, b)
		var better := (b < a) if lower_is_better else (b > a)
		var colour: Color = UiTheme.TEXT
		if changed:
			colour = Color(0.55, 0.9, 0.55) if better else UiTheme.WARN
		_detail.draw_string(font, Vector2(BAR_W - 150.0, y + 14), text, HORIZONTAL_ALIGNMENT_RIGHT, 150,
				UiTheme.BODY, colour)
		var bar := Rect2(0, y + 22, BAR_W, 8)
		_detail.draw_rect(bar, UiTheme.BAR_TRACK, true)
		_detail.draw_rect(Rect2(bar.position, Vector2(BAR_W * clampf(a / scale_to, 0.0, 1.0), 8.0)),
				Color(0.55, 0.62, 0.70), true)
		if changed:
			_detail.draw_rect(Rect2(bar.position, Vector2(BAR_W * clampf(b / scale_to, 0.0, 1.0), 8.0)),
					Color(colour.r, colour.g, colour.b, 0.55), true)
		y += 46.0
	# SPEC 130: what the part DOES used to be drawn here, under the bars, as two multiline strings
	# clipped to two lines each. A part with anything to say ran past the bottom of the panel and over
	# the BUY button underneath it -- and clipping it instead would have hidden the reason to buy the
	# thing. It is a scrolling label now (`_notes`), so any length of text fits and none of it is lost.


# ---------------------------------------------------------------- construction

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	BackgroundArt.add(self, "res://art/bg_garage.png")
	var stripe := ColorRect.new()
	stripe.color = Color(0.13, 0.13, 0.15, 0.85)
	_place(stripe, Rect2(0, 0, 1280, 68))
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stripe)
	_title = UiTheme.label("Title", "GARAGE", UiTheme.TITLE, Color(1.0, 0.92, 0.3))
	_place(_title, Rect2(24, 14, 700, 44))
	add_child(_title)
	_coins = UiTheme.label("CoinsLabel", "", UiTheme.HEADING, UiTheme.ACCENT)
	_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(_coins, Rect2(960, 16, 296, 40))
	add_child(_coins)

	for r in [TABS_RECT, LIST_RECT, CAR_RECT]:
		var panel := UiTheme.panel("Panel")
		_place(panel, r)
		add_child(panel)

	for i in TABS.size():
		var tab := Control.new()
		tab.name = "Tab_%s" % TABS[i]
		_place(tab, Rect2(TABS_RECT.position + Vector2(8, 8 + i * (TAB_H + 4)), Vector2(216, TAB_H)))
		tab.mouse_filter = Control.MOUSE_FILTER_STOP
		tab.draw.connect(_draw_tab.bind(tab, i))
		tab.gui_input.connect(_on_tab_input.bind(i))
		add_child(tab)
		_tab_rows.append(tab)

	# Enough rows for the longest tab (the five colours, four effects, four profiles, four parts).
	for i in 6:
		var row := Control.new()
		row.name = "Row%d" % i
		_place(row, Rect2(LIST_RECT.position + Vector2(8, 8 + i * (ROW_H + 4)), Vector2(504, ROW_H)))
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.draw.connect(_draw_row.bind(row, i))
		row.gui_input.connect(_on_row_input.bind(i))
		add_child(row)
		_rows.append(row)

	var box := SubViewportContainer.new()
	box.name = "ModelBox"
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(box, MODEL_RECT)
	add_child(box)
	_model = CarModel3D.new()
	_model.name = "Model"
	_model.priority = true
	box.add_child(_model)
	_model.set_view(52.0, int(MODEL_RECT.size.y), 34.0)

	# SPEC 67: the bought effects, drawn over the car in the preview.
	_fx = GarageEffects.new()
	_fx.name = "EffectPreview"
	_fx.set_box(MODEL_RECT)
	add_child(_fx)

	_detail = Control.new()
	_detail.name = "Detail"
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Just the four bars now: 4 x 46 px. The words below them have their own box.
	_place(_detail, Rect2(832, 344, BAR_W, 188))
	_detail.draw.connect(_draw_detail)
	add_child(_detail)

	# SPEC 130: what the highlighted part does, in a box that SCROLLS. Dragged with one finger like
	# everything else in the game -- there is no second pointer and never will be.
	var notes := ScrollContainer.new()
	notes.name = "Notes"
	notes.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	notes.follow_focus = true
	_place(notes, Rect2(832, 536, BAR_W, 56))
	add_child(notes)
	_notes = RichTextLabel.new()
	_notes.name = "NotesText"
	_notes.bbcode_enabled = true
	_notes.fit_content = true
	_notes.scroll_active = false
	_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notes.custom_minimum_size = Vector2(BAR_W, 0)
	_notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notes.add_theme_font_size_override("normal_font_size", UiTheme.CAPTION)
	_notes.add_theme_font_size_override("bold_font_size", UiTheme.CAPTION)
	notes.add_child(_notes)

	_action = Button.new()
	_action.name = "ActionButton"
	_action.text = "FIT"
	_action.focus_mode = Control.FOCUS_NONE
	_action.add_theme_font_size_override("font_size", UiTheme.HEADING)
	UiTheme.style_button(_action)
	_place(_action, Rect2(832, 600, 400, 48))
	_action.pressed.connect(take_action)
	add_child(_action)

	var back := Button.new()
	back.name = "BackButton"
	back.text = "Back"
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", UiTheme.HEADING)
	UiTheme.style_button(back)
	_place(back, Rect2(UiTheme.MARGIN, 720.0 - UiTheme.BUTTON_H - UiTheme.MARGIN, 200, UiTheme.BUTTON_H))
	back.pressed.connect(go_back)
	add_child(back)


func _on_tab_input(event: InputEvent, index: int) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		select_tab(String(TABS[index]))


func _on_row_input(event: InputEvent, index: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if index == _highlight:
		take_action()                      # a second click on the highlighted row fits or buys it
	else:
		select_row(index)


func _place(control: Control, rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y
