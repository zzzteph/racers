extends Control
## How to play (SPEC 63). It replaces three settings toggles that explained nothing and one that the
## mouse wheel now does: a player does not want a "close camera" checkbox, they want to know the wheel
## zooms -- and they want to be shown, not told, which is what the pictures are for.
##
## Text on the left, pictures of the real game on the right (`art/help/`, made by
## `tools/make_help_art.gd`). Every line is one idea; nothing here is a paragraph.

const BG_COLOR := Color(0.13, 0.32, 0.14)
## SPEC 116: taller and tighter than it was; the audit is what decides whether the lines fit.
const PANEL := Rect2(64, 56, 1152, 584)
const TEXT_X := 96.0
const TEXT_W := 560.0
## SPEC 131: HOW MUCH AIR THE WORDS GET. 26 px of line on 18 px of text is 1.44 -- technically legible
## and, in a solid column of it, a wall ("the font is too tight, it must be more spacious"). 34 is 1.9,
## which is what a page meant to be READ rather than scanned wants.
##
## The column SCROLLS to pay for it. Spacing this generous does not fit a fixed panel, and the
## alternative was cutting the words down until they fitted, which is how the page got tight in the
## first place.
const LINE_H := 34.0
const HEADING_H := 30.0
const SECTION_GAP := 22.0
const SHOT_X := 688.0
const SHOT_W := 496.0

var _page: int = 0
var _tabs: Array = []
var _page_root: Control = null

## SPEC 120: PAGES, because one screen cannot hold every subject. RACE is how to drive and what a race
## is; MACHINES is what the cars, their tyres and their parts actually do -- which the game had never
## explained anywhere. (The ARENA page went with the arena, SPEC 140.)
##
## SPEC 122: EVERY CLAIM ON THESE PAGES IS CHECKED AGAINST THE CODE THAT IMPLEMENTS IT. Four of them
## were not true. The RACE page promised a reverse, a control a race does not have. Colours are free
## (`Profile.is_color_unlocked` returns true for all of them), not bought. The Formula is neither the
## fastest (the Grand Tourer's 730 px/s beats its 650) nor the lightest (the Kart's 500 kg beats its
## 800). And the arena page got its own scoring wrong. `test_help_claims` in the suite now holds the
## checkable ones to the registry.
## Each page: [name, [[heading, [lines...]], ...], [[picture, caption], ...]].
const PAGES := [
	["RACE", [
		["THE ROPE", [
			"Your car follows the cursor, on a rope.",
			"Cursor far away = throttle; on the car = brakes.",
			"Let it go slack and the car coasts: it keeps its speed.",
		]],
		["THE BOOST", [
			"Hold the cursor just past full throttle to charge it,",
			"then click to fire. Drag too hard and the rope snaps --",
			"and pull harder still and the car leaves the ground.",
			"A drift charges it fastest; catching one tops it up.",
		]],
		["THE VIEW", [
			"The wheel zooms in and out -- two fingers on a phone.",
			"Zoomed out shows the whole track at once.",
		]],
		["THE RACE", [
			"Chevrons show the way; a missed gate costs you a detour.",
			"A wrecked engine limps -- ride it home, there is no reset.",
			"Off the road? Pull hard: the rope drags you back onto it.",
		]],
		["THE CAREER", [
			"Every track is open. Win for stars: 1 easy, 2 medium, 3 hard.",
			"Stars need rivals -- a solo run is a time trial.",
			"Coins buy cars, parts and effects. Colours are free.",
		]],
	], [
		["res://art/help/rope.png", "The rope, the cursor and the tension zone"],
		["res://art/help/hud.png", "The order top left, the map top right"],
	]],
	["MACHINES", [
		["FIVE CARS", [
			"Sport is the all-rounder. Formula has the grip and the brakes.",
			"Grand Tourer has the top speed and the weight to go with it.",
			"Rally is at home off the road; Kart is the lightest and darts.",
		]],
		["TYRES", [
			"Grip falls away past the peak: that is the slide you feel.",
			"A burst tyre costs speed and steers wide until you repair it.",
		]],
		["DAMAGE", [
			"Panels are armour. Under them: the engine (nose), tank (tail).",
			"Only a blown tank ends it. A dead engine limps -- ride it.",
			"In a race, F writes the car off once it is half broken: you",
			"restart repaired at the last checkpoint, and lose the time.",
		]],
		["PARTS", [
			"Engine, wheels, suspension, body, rope, charge -- the garage.",
			"Every part is a trade: none of them is simply better.",
			"The charge is what your car does when it is written off: a",
			"wreck goes off and hurts whatever is beside it, panels and",
			"all. Reach or bite -- you cannot buy both.",
		]],
	], [
		["res://art/help/rope.png", "Every car has its own rope and its own weight"],
	]],
]

## [file, caption]
const SHOTS := [
	["res://art/help/rope.png", "The rope, the cursor and the tension zone"],
	["res://art/help/hud.png", "The order top left, the map top right"],
]


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	BackgroundArt.add(self, "res://art/bg_grid.png")

	var stripe := ColorRect.new()
	stripe.color = Color(0.13, 0.13, 0.15, 0.85)
	_place(stripe, Rect2(0, 0, 1280, 68))
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stripe)
	var title := UiTheme.label("Title", "HOW TO PLAY", UiTheme.TITLE, Color(1.0, 0.92, 0.3))
	_place(title, Rect2(UiTheme.MARGIN * 1.5, 14, 420, 44))
	add_child(title)

	# SPEC 120: the page tabs, along the top stripe beside the title.
	var x := 460.0
	for i in PAGES.size():
		var tab := UiTheme.button("Tab%d" % i, String(PAGES[i][0]), UiTheme.BODY)
		_place(tab, Rect2(x, 10, 160, UiTheme.BUTTON_H))
		tab.pressed.connect(show_page.bind(i))
		add_child(tab)
		_tabs.append(tab)
		x += 160.0 + UiTheme.MARGIN

	var panel := ColorRect.new()
	panel.name = "Panel"
	panel.color = Color(0, 0, 0, 0.72)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(panel, PANEL)
	add_child(panel)
	_page_root = Control.new()
	_page_root.name = "Page"
	_page_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_page_root)

	var back := UiTheme.button("BackButton", "Back", UiTheme.HEADING)
	back.focus_mode = Control.FOCUS_NONE
	_place(back, Rect2(UiTheme.MARGIN, 720.0 - UiTheme.BUTTON_H - UiTheme.MARGIN, 200, UiTheme.BUTTON_H))
	back.pressed.connect(go_back)
	add_child(back)
	show_page(0)


## Swaps the page under the tabs. Everything on a page is built fresh, which is cheap (a dozen labels
## and two pictures) and means no page can leave anything of its own behind on another.
func show_page(index: int) -> void:
	_page = clampi(index, 0, PAGES.size() - 1)
	# Freed NOW, not at the end of the frame: a deferred free leaves both pages on the screen for a
	# frame, which is one frame of garbage and an overlap the audit rightly complains about.
	for c in _page_root.get_children():
		_page_root.remove_child(c)
		c.free()
	for i in _tabs.size():
		(_tabs[i] as Button).add_theme_color_override("font_color",
				UiTheme.ACCENT if i == _page else UiTheme.MUTED)
	var page: Array = PAGES[_page]
	# SPEC 131: the words live in a scrolling column now, so they can have room to breathe without the
	# page having to end where the panel does. Dragged with one finger, like everything else here.
	var scroll := ScrollContainer.new()
	scroll.name = "TextScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_place_in(_page_root, scroll, Rect2(TEXT_X, PANEL.position.y + 24.0, TEXT_W + 16.0,
			PANEL.size.y - 48.0))
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.name = "Lines"
	column.add_theme_constant_override("separation", 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	for i in (page[1] as Array).size():
		var section: Array = (page[1] as Array)[i]
		if i > 0:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(TEXT_W, SECTION_GAP)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			column.add_child(gap)
		var heading := UiTheme.label("Heading%d" % i, String(section[0]), UiTheme.CAPTION, UiTheme.ACCENT)
		heading.custom_minimum_size = Vector2(TEXT_W, HEADING_H)
		heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		column.add_child(heading)
		for line in (section[1] as Array):
			var l := UiTheme.label("Line", String(line), UiTheme.BODY, UiTheme.TEXT)
			l.custom_minimum_size = Vector2(TEXT_W, LINE_H)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			column.add_child(l)

	var sy := PANEL.position.y + 24.0
	var shots: Array = page[2]
	for i in shots.size():
		var shot: Array = shots[i]
		var tex: Texture2D = load(String(shot[0])) as Texture2D
		if tex == null:
			continue
		var h := SHOT_W * float(tex.get_height()) / float(tex.get_width())
		var pic := TextureRect.new()
		pic.name = "Shot%d" % i
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_place_in(_page_root, pic, Rect2(SHOT_X, sy, SHOT_W, h))
		sy += h + 8.0
		var cap := UiTheme.label("ShotCaption%d" % i, String(shot[1]), UiTheme.CAPTION, UiTheme.MUTED)
		_place_in(_page_root, cap, Rect2(SHOT_X, sy, SHOT_W, 20))
		sy += 28.0


func page() -> int:
	return _page


## SPEC 122: how many pages there are, so the audit can step through all of them rather than only the
## one the screen opens on.
func page_count() -> int:
	return PAGES.size()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		go_back()


## SPEC 74: reached from the main menu now, so that is where Back goes.
func go_back() -> void:
	GameState.go_to_menu()


## The same placement, into a page rather than into the screen.
func _place_in(parent: Control, control: Control, rect: Rect2) -> void:
	parent.add_child(control)
	_place(control, rect)


func _place(control: Control, rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y
