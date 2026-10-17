extends Control
## Car select -- the first step of a race: the car and its colour. NEXT goes on to the track select
## screen, where the rivals are set up.
##
## Layout (1280x720): the car list on the left; a big turning 3D model of the highlighted car in the
## middle with its five colours under it; its four characteristics as large values and bars on the
## right. Keyboard: Up/Down car, Left/Right colour, Enter next, Esc back to the title menu.

const BG_COLOR := Color(0.13, 0.32, 0.14)
const TITLE_COLOR := Color(1.0, 0.92, 0.3)
const STRIPE_COLOR := Color(0.13, 0.13, 0.15, 0.85)
const PANEL_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const DIM_COLOR := Color(0.86, 0.88, 0.86)
const SUB_COLOR := Color(0.78, 0.82, 0.78)
const CAPTION_COLOR := Color(1.0, 0.92, 0.3)
const OUTLINE_SIZE := 4

const LIST_RECT := Rect2(24, 80, 296, 568)
const ROW_SIZE := Vector2(280, 72)
const STAGE_RECT := Rect2(336, 80, 920, 568)
const MODEL_RECT := Rect2(352, 160, 560, 288)
## Under the model (SPEC 39): what the car is good and weak at, its rope, and the tracks it is best on.
## SPEC 62: the four trait lines are still filled in (and still readable through `get_traits_text()`),
## but only the first is shown. Three paragraphs of prose on a menu is three paragraphs nobody reads.
const TRAITS_RECT := Rect2(352, 456, 560, 24)
const TRAIT_CAPTIONS := ["GOOD AT", "WEAK AT", "ROPE", "BEST ON"]
const TRAITS_SHOWN := 1
const SWATCH_Y := 512.0
const STATS_RECT := Rect2(944, 160, 296, 184)
## SPEC 61 -- the garage. One row per slot: what is fitted, and what it costs to change. Clicking a row
## moves to the next part in that slot, buying it the first time. Under the rows, what the fitted part is
## good and bad at -- because no part here is simply better than another.
const PRICE_COLOR := Color(1.0, 0.85, 0.3)
const TURN_SPEED := 0.55          # rad/s of the turntable

## Bar scales for the four characteristics (the widest car fills the bar).
const SPEED_SCALE_KMH := 140.0
const WEIGHT_SCALE_KG := 1800.0

var _ids: PackedStringArray = PackedStringArray()
## The car this screen opened with (SPEC 73): what Back falls back to after looking at a locked one.
var _entry_car: String = ""
var _rows: Array[Control] = []
var _model: CarModel3D = null
var _angle: float = 0.6
var _name_label: Label = null
var _desc_label: Label = null
var _trait_labels: Array = []
var _color_label: Label = null
var _swatches: Array[Button] = []
var _stats: Control = null
var _garage: Control = null
var _coins_label: Label = null
var _buy_button: Button = null
var _price_sign: Label = null
var _price_note: Label = null
var _garage_button: Button = null
var _next_button: Button = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# SPEC 63: cheapest first, so the list reads as the order you will buy them in (the starter is free
	# and therefore first).
	_ids = CarRegistry.ids()
	var by_price: Array = []
	for id in _ids:
		by_price.append(id)
	by_price.sort_custom(func(a: String, b: String) -> bool:
		return CarRegistry.get_price(a) < CarRegistry.get_price(b))
	_ids = PackedStringArray(by_price)
	_entry_car = GameState.owned_car()
	_build_ui()
	_refresh()


func _process(delta: float) -> void:
	_angle = fmod(_angle + delta * TURN_SPEED, TAU)
	if _model != null:
		_model.pose(_angle, 0.0, 0.0, 0.0, 0.0, PackedFloat32Array([0, 0, 0, 0]), delta * 80.0, 0.0)


# ---------------------------------------------------------------- public API (tests use these too)

func select_car(index: int) -> void:
	GameState.select_car(_ids[posmod(index, _ids.size())])
	_refresh()
	Audio.rev(GameState.selected_car)
	_tell_room()


func select_color(index: int) -> void:
	GameState.select_color(index)
	_refresh()
	_tell_room()


## Picking the car from a multiplayer room (SPEC 45): the room sees the choice at once, and Back / Done
## go back to the room instead of on to the track screen.
func _from_room() -> bool:
	return Net.is_online()


func _tell_room() -> void:
	if _from_room():
		Net.update_my_player()


## The list's own order (SPEC 63: cheapest first), for anything that walks the rows.
func get_car_ids() -> PackedStringArray:
	return _ids


func get_selected_car() -> String:
	return GameState.selected_car


## SPEC 122: what the primary button says, worked out from the same cases `go_next()` branches on,
## so the two can never disagree again.
func _next_label() -> String:
	if _from_room():
		return "BACK TO ROOM  >"
	return "NEXT:  TRACK  >"        # SPEC 140: a track is the only next


func go_next() -> void:
	# SPEC 71: you race what you own. A locked car can be looked at and bought, not driven.
	if not GameState.profile.is_car_unlocked(GameState.selected_car):
		Audio.beep(false)
		return
	if _from_room():
		GameState.go_to_lobby()
		return
	GameState.go_to_track_select()


func go_back() -> void:
	# SPEC 73: Back always goes back -- but not with a car that was never bought. Whatever was being
	# looked at is dropped for the car this screen opened with (itself owned, or the starter).
	if not GameState.profile.is_car_unlocked(GameState.selected_car):
		GameState.select_car(GameState.owned_car(_entry_car))
		_tell_room()
	if _from_room():
		GameState.go_to_lobby()
		return
	GameState.go_to_menu()


func _unhandled_input(event: InputEvent) -> void:
	# The LIST's order, not the registry's: the rows are sorted by price (SPEC 63), so the arrow keys
	# have to walk the same order the eye does.
	var i := _ids.find(GameState.selected_car)
	if event.is_action_pressed("ui_down"):
		get_viewport().set_input_as_handled()
		select_car(i + 1)
	elif event.is_action_pressed("ui_up"):
		get_viewport().set_input_as_handled()
		select_car(i - 1)
	elif event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		select_color(GameState.selected_color + 1)
	elif event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		select_color(GameState.selected_color - 1)
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		go_next()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		go_back()


# ---------------------------------------------------------------- refresh

func _refresh() -> void:
	var id := GameState.selected_car
	var ci := GameState.selected_color
	var pal: Array = CarRegistry.get_palette(id)
	_name_label.text = CarRegistry.get_display_name(id)
	_name_label.add_theme_color_override("font_color", (pal[ci]["body"] as Color).lightened(0.3))
	_desc_label.text = CarRegistry.get_description(id)
	var best := PackedStringArray()
	for t in Medals.best_tracks(id):
		best.append(TrackRegistry.get_short_name(t))
	var traits := [CarRegistry.get_good(id), CarRegistry.get_weak(id), CarRegistry.get_rope_text(id), ", ".join(best)]
	for k in _trait_labels.size():
		(_trait_labels[k] as Label).text = String(traits[k])
	_color_label.text = String(pal[ci]["name"])
	for k in _swatches.size():
		# A locked colour is shown dimmed with its price on it: clicking buys it (SPEC 56).
		# A colour you have not bought is dimmed here; it is bought in the garage (SPEC 64).
		var owned: bool = GameState.profile.is_color_unlocked(id, k)
		_style_swatch(_swatches[k], pal[k]["body"] if owned else (pal[k]["body"] as Color).darkened(0.55),
				k == ci)
		_swatches[k].disabled = not owned
		_swatches[k].tooltip_text = String(pal[k]["name"]) if owned else "Buy this colour in the garage"
	for r in _rows:
		r.queue_redraw()
	if _model != null:
		# SPEC 70: a car you have not bought is shown in primer grey, whatever its colours are.
		var owned := GameState.profile.is_car_unlocked(id)
		var body: Color = pal[ci]["body"]
		var stripe: Color = pal[ci]["stripe"]
		if not owned:
			var g := (body.r + body.g + body.b) / 3.0 * 0.55 + 0.12
			body = Color(g, g, g * 1.05)
			stripe = Color(g * 1.4, g * 1.4, g * 1.4)
		_model.build(CarRegistry.get_style(id), body, stripe)
		# SPEC 130: the parts you have FITTED, on the car you are choosing. This screen only ever
		# applied the wheel SCALE, so a set of wheels bought and fitted in the garage showed up there
		# and nowhere else -- you picked the car and the old ones were still on it. `set_look` is what
		# the garage uses and what puts the rest of it on too: rubber, ride height, cage, scoop.
		var fitted: Dictionary = GameState.profile.fitted(id)
		_model.set_look(fitted)
		_model.set_wheel_scale(Parts.wheel_scale(fitted))
	_stats.queue_redraw()
	_refresh_garage(id)


# ---------------------------------------------------------------- construction

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	BackgroundArt.add(self, "res://art/bg_garage.png")
	var stripe := ColorRect.new()
	stripe.color = STRIPE_COLOR
	_place(stripe, Rect2(0, 0, 1280, 68))
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stripe)
	var title := _label("Title", Rect2(24, 16, 500, 40), UiTheme.TITLE, TITLE_COLOR)
	title.text = "SELECT CAR"
	add_child(title)

	for r in [LIST_RECT, STAGE_RECT]:
		var p := ColorRect.new()
		p.color = PANEL_COLOR
		_place(p, r)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(p)

	# --- car list
	for i in _ids.size():
		var row := Control.new()
		row.name = "Car_%s" % _ids[i]
		_place(row, Rect2(LIST_RECT.position + Vector2(8, 8 + i * (ROW_SIZE.y + 6)), ROW_SIZE))
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.draw.connect(_draw_row.bind(row, i))
		row.gui_input.connect(_on_row_input.bind(i))
		add_child(row)
		_rows.append(row)

	# --- the stage: name, description, turning model, colours, characteristics
	_name_label = _label("CarName", Rect2(352, 80, 560, 48), UiTheme.TITLE, Color.WHITE)
	add_child(_name_label)
	# SPEC 122: WRAPPED, not clipped. The Kart's description wants 594 px and the Rally's 671 in a 560 px
	# box, so both were silently cut off mid-sentence on the screen that is meant to sell the car. Two
	# lines of room and word wrapping; the type size is the same as everywhere else.
	_desc_label = _label("CarDescription", Rect2(352, 132, 560, 52), UiTheme.BODY, UiTheme.MUTED)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_desc_label)
	var box := SubViewportContainer.new()
	box.name = "ModelBox"
	box.stretch = true
	_place(box, MODEL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_model = CarModel3D.new()
	_model.name = "Model"
	box.add_child(_model)
	_model.set_view(50.0, int(MODEL_RECT.size.y), 38.0)
	_model.size = Vector2i(int(MODEL_RECT.size.x), int(MODEL_RECT.size.y))

	for k in TRAIT_CAPTIONS.size():
		var y := TRAITS_RECT.position.y
		var cap := _label("TraitCaption%d" % k, Rect2(TRAITS_RECT.position.x, y, 80, 24),
				UiTheme.CAPTION, UiTheme.MUTED)
		cap.text = TRAIT_CAPTIONS[k]
		cap.visible = k < TRAITS_SHOWN
		add_child(cap)
		var l := _label("Trait%d" % k, Rect2(TRAITS_RECT.position.x + 80, y, TRAITS_RECT.size.x - 80 + 60, 24),
				UiTheme.CAPTION, UiTheme.TEXT)
		l.clip_text = true
		l.visible = k < TRAITS_SHOWN
		add_child(l)
		_trait_labels.append(l)

	for k in CarRegistry.PALETTE_SIZE:
		var b := Button.new()
		b.name = "Swatch%d" % k
		b.focus_mode = Control.FOCUS_NONE
		_place(b, Rect2(352 + k * 66, SWATCH_Y, 56, 48))
		b.pressed.connect(select_color.bind(k))
		add_child(b)
		_swatches.append(b)
	_color_label = _label("ColorName", Rect2(700, SWATCH_Y, 210, 48), UiTheme.BODY, UiTheme.TEXT)
	add_child(_color_label)
	var colour_caption := _label("ColourCaption", Rect2(352, SWATCH_Y - 24, 200, 20),
			UiTheme.CAPTION, UiTheme.MUTED)
	colour_caption.text = "COLOUR"
	add_child(colour_caption)

	_stats = Control.new()
	_stats.name = "Characteristics"
	_place(_stats, STATS_RECT)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.draw.connect(_draw_stats)
	add_child(_stats)

	_coins_label = _label("CoinsLabel", Rect2(1016, 16, 240, 40), 24, PRICE_COLOR)
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_coins_label)

	_garage_button = _button("GarageButton", "GARAGE  >", Rect2(944, 400, 296, 56), UiTheme.HEADING)
	_garage_button.pressed.connect(_open_garage)
	add_child(_garage_button)

	_price_sign = _label("PriceSign", Rect2(352, 300, 560, 64), UiTheme.TITLE, UiTheme.ACCENT)
	_price_sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price_sign.visible = false
	add_child(_price_sign)
	_price_note = _label("PriceNote", Rect2(352, 364, 560, 28), UiTheme.BODY, UiTheme.MUTED)
	_price_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price_note.visible = false
	add_child(_price_note)

	_buy_button = _button("BuyCarButton", "BUY", Rect2(690, 660, 200, 48), 22)
	_buy_button.pressed.connect(buy_selected_car)
	_buy_button.visible = false
	add_child(_buy_button)

	var back := _button("BackButton", "Room" if _from_room() else "Menu",
			Rect2(UiTheme.MARGIN, 720.0 - UiTheme.BUTTON_H - UiTheme.MARGIN, 200, UiTheme.BUTTON_H), 22)
	back.pressed.connect(go_back)
	add_child(back)
	# SPEC 122: the label is derived from where `go_next()` actually goes.
	_next_button = _button("NextButton", _next_label(),
			Rect2(1016, 660, 240, 48), 22)
	_next_button.pressed.connect(go_next)
	add_child(_next_button)


func _draw_row(row: Control, i: int) -> void:
	var id := _ids[i]
	var selected := id == GameState.selected_car
	var rect := Rect2(Vector2.ZERO, row.size)
	# SPEC 63: a car you have not bought is grey -- its colour chip, its name and its numbers -- so the
	# list says at a glance what is yours and what is for sale.
	var owned := GameState.profile.is_car_unlocked(id)
	var body := CarRegistry.get_body_color(id, GameState.selected_color if selected else 0)
	if not owned:
		var grey := (body.r + body.g + body.b) / 3.0 * 0.7
		body = Color(grey, grey, grey)
	row.draw_rect(rect, Color(1, 1, 1, 0.16) if selected else Color(1, 1, 1, 0.04), true)
	if selected:
		row.draw_rect(rect, Color(1, 1, 1, 0.8), false, 2.0)
	row.draw_rect(Rect2(10, 12, 10, rect.size.y - 24), body, true)
	var font := row.get_theme_default_font()
	# SPEC 62: a name and one line under it. The ratings live in the panel on the right, once.
	row.draw_string_outline(font, Vector2(32, 32), CarRegistry.get_display_name(id), HORIZONTAL_ALIGNMENT_LEFT,
			-1, UiTheme.HEADING, 4, Color.BLACK)
	row.draw_string(font, Vector2(32, 32), CarRegistry.get_display_name(id), HORIZONTAL_ALIGNMENT_LEFT, -1,
			UiTheme.HEADING, Color.WHITE if owned else UiTheme.MUTED)
	var locked := not owned
	var under := "%d km/h  -  %d kg" % [CarRegistry.get_max_speed_kmh(id), CarRegistry.get_weight_kg(id)]
	if locked:
		under = "%d coins" % CarRegistry.get_price(id)
	row.draw_string(font, Vector2(32, 56), under, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.CAPTION,
			UiTheme.ACCENT if locked else UiTheme.MUTED)


func _draw_stats() -> void:
	var id := GameState.selected_car
	var font := _stats.get_theme_default_font()
	var accent := CarRegistry.get_body_color(id, GameState.selected_color).lightened(0.2)
	var susp := CarRegistry.get_suspension(id)
	var dyn := CarRegistry.get_dynamics(id)
	# SPEC 61: the numbers are what the car will actually race with, parts included.
	var fitted: Dictionary = GameState.profile.fitted(id)
	var kmh := int(round(float(CarRegistry.get_max_speed_kmh(id)) * Parts.scaled(fitted, "max_speed")))
	var kg := int(round(float(CarRegistry.get_weight_kg(id)) * Parts.scaled(fitted, "mass")))
	var items := [
		["MAX SPEED", "%d km/h" % kmh, float(kmh) / SPEED_SCALE_KMH],
		["WEIGHT", "%d kg" % kg, float(kg) / WEIGHT_SCALE_KG],
		["SUSPENSION", ["", "very soft", "soft", "medium", "stiff", "very stiff"][susp], float(susp) / 5.0],
		["DYNAMICS", ["", "lazy", "calm", "balanced", "sharp", "razor"][dyn], float(dyn) / 5.0],
	]
	var w := STATS_RECT.size.x
	# SPEC 62: caption, value and bar on ONE line each -- the same four rows, a third of the height.
	var step := STATS_RECT.size.y / float(items.size())
	for k in items.size():
		var y := float(k) * step
		_stats.draw_string(font, Vector2(0, y + 14), String(items[k][0]), HORIZONTAL_ALIGNMENT_LEFT, 150,
				UiTheme.CAPTION, UiTheme.MUTED)
		_stats.draw_string(font, Vector2(w - 150.0, y + 14), String(items[k][1]), HORIZONTAL_ALIGNMENT_RIGHT,
				150, UiTheme.BODY, UiTheme.TEXT)
		var bar := Rect2(0, y + 22, w, 6)
		_stats.draw_rect(bar, UiTheme.BAR_TRACK, true)
		_stats.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(float(items[k][2]), 0.0, 1.0),
				bar.size.y)), accent, true)


## The garage, for a car you own. A locked one has nothing to set up (SPEC 71).
func _open_garage() -> void:
	if not GameState.profile.is_car_unlocked(GameState.selected_car):
		Audio.beep(false)
		return
	GameState.go_to_garage()


## The coin count and the BUY button for a locked car. Everything else about a car -- its parts, its
## colours, its effects -- is set up in the garage now (SPEC 64).
func _refresh_garage(id: String) -> void:
	if _coins_label != null:
		_coins_label.text = "%d coins" % GameState.get_coins()
	if _buy_button == null:
		return
	var locked := not GameState.profile.is_car_unlocked(id)
	_buy_button.visible = locked
	if _next_button != null:
		_next_button.disabled = locked
		_next_button.tooltip_text = "" if not locked else "Buy this car before you race it"
	var price := GameState.profile.car_price(id)
	# SPEC 70: the price, big, across the car -- a locked car should say what it costs from the doorway.
	if _price_sign != null:
		_price_sign.visible = locked
		_price_sign.text = "%d COINS" % price
		_price_sign.add_theme_color_override("font_color",
				UiTheme.ACCENT if price <= GameState.get_coins() else UiTheme.WARN)
	if _price_note != null:
		_price_note.visible = locked
		_price_note.text = "Yours to buy" if price <= GameState.get_coins() 				else "%d more to go" % (price - GameState.get_coins())
	if locked:
		_buy_button.text = "BUY  %d" % price
		_buy_button.disabled = price > GameState.get_coins()
	# SPEC 71: there is nothing to set up on a car you do not own -- the garage is shut until you buy it.
	if _garage_button != null:
		_garage_button.disabled = locked
		_garage_button.text = "GARAGE  >" if not locked else "GARAGE  (locked)"
		_garage_button.tooltip_text = "Parts, colours, effects and ready-made setups for this car" 				if not locked else "Buy the car first"


## Buys the selected car, if it is locked and there are coins for it.
func buy_selected_car() -> bool:
	var id := GameState.selected_car
	if not GameState.profile.buy_car(id):
		return false
	GameState.save_profile()
	Audio.beep(true)
	_refresh()
	return true


func get_traits_text() -> String:
	var out := PackedStringArray()
	for l in _trait_labels:
		out.append((l as Label).text)
	return " | ".join(out)


func _on_row_input(event: InputEvent, i: int) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if mb.double_click and _ids[i] == GameState.selected_car:
			go_next()
		else:
			select_car(i)


func _style_swatch(b: Button, c: Color, selected: bool) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = c.lightened(0.12) if state == "hover" else c
		box.border_color = Color.WHITE if selected else Color(0, 0, 0, 0.6)
		box.set_border_width_all(4 if selected else 2)
		box.set_corner_radius_all(6)
		b.add_theme_stylebox_override(state, box)


func _label(node_name: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.name = node_name
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(l, rect)
	return l


func _button(node_name: String, text: String, rect: Rect2, font_size: int) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	_place(b, rect)
	return b


func _place(c: Control, r: Rect2) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.end.x
	c.offset_bottom = r.end.y
	c.custom_minimum_size = r.size
