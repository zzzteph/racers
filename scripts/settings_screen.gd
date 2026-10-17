extends Control
## Settings (from the title menu): the driver's name, full screen / windowed, music and effects
## volume, and an FPS counter. Every change is applied and saved at once (GameState.set_setting), so
## there is no Apply button to forget. Esc or Back returns to the title menu.

const BG_COLOR := Color(0.13, 0.32, 0.14)
const TITLE_COLOR := Color(1.0, 0.92, 0.3)
## SPEC 62 / 74: the box is its rows and nothing else -- four rows of 40 px, 16 px between them, 32 px of
## padding top and bottom: 4*40 + 3*16 + 64 = 272. (How to play left for the main menu in SPEC 74, and the
## box that used to hold six rows was left standing around 208 px of settings.) Sat in the middle of the
## screen, between the title above it and the hint under it.
## SPEC 126: 340 tall, not 272 -- "Reduce shake and flashing" is a fifth row, and the panel has to
## grow for it or the last row lands on the footnote underneath.
const PANEL := Rect2(320, 196, 640, 340)
const ROW_H := 44.0          # SPEC 97: every control a thumb's height
const ROW_GAP := 16.0

var _name_edit: LineEdit = null
var _fullscreen: Button = null
var _fps: Button
var _close_camera: Button
var _low_graphics: Button
var _unlock_all: Button = null
var _music: HSlider = null
var _sfx: HSlider
## SPEC 126: reduce shake and flashing.
var _calm: Button = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		go_back()


func go_back() -> void:
	# A name typed but not confirmed with Enter still counts.
	if _name_edit != null:
		GameState.set_setting("player_name", _name_edit.text)
	GameState.go_to_menu()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	BackgroundArt.add(self, "res://art/bg_wreck.png")
	var stripe := ColorRect.new()
	stripe.color = Color(0.13, 0.13, 0.15, 0.85)
	_place(stripe, Rect2(0, 0, 1280, 68))
	add_child(stripe)
	var title := Label.new()
	title.name = "Title"
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", UiTheme.TITLE)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 6)
	_place(title, Rect2(24, 16, 500, 40))
	add_child(title)

	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.72)      # readable over the background art
	_place(panel, PANEL)
	add_child(panel)

	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", int(ROW_GAP))
	_place(grid, PANEL.grow(-32))
	add_child(grid)

	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_name_edit.text = GameState.get_player_name()
	_name_edit.max_length = GameState.MAX_NAME_LENGTH
	_name_edit.custom_minimum_size = Vector2(304, ROW_H)
	_name_edit.add_theme_font_size_override("font_size", UiTheme.BODY)
	_name_edit.text_submitted.connect(func(t: String) -> void: GameState.set_setting("player_name", t))
	_name_edit.focus_exited.connect(func() -> void: GameState.set_setting("player_name", _name_edit.text))
	_row(grid, "Your name", _name_edit)

	_fullscreen = _check("FullscreenCheck", bool(GameState.get_setting("fullscreen")), "fullscreen")
	_row(grid, "Full screen", _fullscreen)
	_music = _slider("MusicSlider", float(GameState.get_setting("music_volume")), "music_volume")
	_row(grid, "Music volume", _music)
	_sfx = _slider("SfxSlider", float(GameState.get_setting("sfx_volume")), "sfx_volume")
	_row(grid, "Effects volume", _sfx)
	# SPEC 126: less shake, no flashing, no rising announcement -- and every warning still shown.
	_calm = _check("CalmCheck", bool(GameState.get_setting("calm_effects")), "calm_effects")
	_calm.tooltip_text = ("Turns the camera shake and the flashing down. Nothing you need to see is "
			+ "removed -- the warnings, the chips and the status line are unchanged.")
	_row(grid, "Reduce shake and flashing", _calm)
	# SPEC 63: Show FPS, Practice, Low graphics and Close camera are gone -- three of them explained
	# nothing to a player and the fourth is what the mouse wheel does now. SPEC 74: How to play is on the
	# main menu, so what is left here really is only settings.

	var hint := Label.new()
	# SPEC 122: M has not toggled the music since SPEC 118 removed the handler; the sliders are the only
	# controls there are, and the screen now says only what is true.
	hint.text = "Everything here is saved as you change it.   Esc goes back."
	hint.add_theme_font_size_override("font_size", UiTheme.CAPTION)
	hint.add_theme_color_override("font_color", UiTheme.MUTED)
	# Under the panel, not inside it: it is a footnote, not a setting.
	_place(hint, Rect2(PANEL.position.x, PANEL.end.y + 12, 600, 24))
	add_child(hint)

	var back := Button.new()
	back.name = "BackButton"
	back.text = "Back"
	back.add_theme_font_size_override("font_size", 22)
	_place(back, Rect2(UiTheme.MARGIN, 720.0 - UiTheme.BUTTON_H - UiTheme.MARGIN, 200, UiTheme.BUTTON_H))
	back.pressed.connect(go_back)
	add_child(back)


func _row(grid: GridContainer, caption: String, control: Control) -> void:
	var l := Label.new()
	l.text = caption
	l.add_theme_font_size_override("font_size", UiTheme.BODY)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.custom_minimum_size = Vector2(232, ROW_H)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(l)
	grid.add_child(control)


## SPEC 97: a toggle is a proper button that says On / Off -- the default CheckButton drew as an eight
## pixel dot, invisible and untappable on a phone.
func _check(node_name: String, value: bool, key: String) -> Button:
	var c := Button.new()
	c.name = node_name
	c.toggle_mode = true
	c.button_pressed = value
	c.text = "On" if value else "Off"
	c.focus_mode = Control.FOCUS_NONE
	c.custom_minimum_size = Vector2(304, maxf(ROW_H, 44.0))
	c.add_theme_font_size_override("font_size", UiTheme.BODY)
	UiTheme.style_button(c)
	c.toggled.connect(func(on: bool) -> void:
		c.text = "On" if on else "Off"
		GameState.set_setting(key, on))
	return c


func _slider(node_name: String, value: float, key: String) -> HSlider:
	var s := HSlider.new()
	s.name = node_name
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(304, ROW_H)
	s.value_changed.connect(func(v: float) -> void: GameState.set_setting(key, v))
	return s


func _place(c: Control, r: Rect2) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.end.x
	c.offset_bottom = r.end.y
