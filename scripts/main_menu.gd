extends Control
## Main menu: title and buttons over the key art (records live on the track select screen). Built in code.

const BG_COLOR := Color(0.13, 0.32, 0.14)
const TITLE_COLOR := Color(1.0, 0.92, 0.3)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


## SPEC 112: the feedback card, opened from the corner button.
var feedback_card: FeedbackCard = null
## SPEC 113: the release notes, opened from the other corner -- and once by themselves for a new build.
var whats_new_card: WhatsNewCard = null
var _menu_controls: Array = []


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# The key art (tools/render_art.gd), dimmed so the menu reads over it.
	BackgroundArt.add(self, "res://art/menu_bg.png", 0.55)

	# Decorative asphalt stripe behind the title.
	var stripe := ColorRect.new()
	stripe.name = "Stripe"
	stripe.color = Color(0.13, 0.13, 0.15, 0.82)
	stripe.set_anchors_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_top = 70.0
	stripe.offset_bottom = 190.0
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stripe)

	# Cars racing across the title band, behind the title.
	var traffic := MenuTraffic.new()
	traffic.name = "Traffic"
	add_child(traffic)

	var title := Label.new()
	title.name = "Title"
	title.text = "Rope Racers"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 8)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 70.0
	title.offset_bottom = 190.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var buttons := VBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 14)
	buttons.set_anchors_preset(Control.PRESET_CENTER)
	buttons.offset_left = -150.0
	buttons.offset_right = 150.0
	buttons.offset_top = -100.0
	buttons.offset_bottom = 190.0
	add_child(buttons)

	# SPEC 16.1: the title menu's only track entry point. The per-track buttons it replaces are gone
	# (decision 29.8) — eight tracks do not fit on a menu, which is what the select screen is for.
	var race_btn := _make_button("RaceButton", "Race")
	race_btn.pressed.connect(_on_race_pressed)
	buttons.add_child(race_btn)

	# SPEC 140: THE ARENA AND DELIVERY ARE GONE; MULTIPLAYER IS NOT. Racing against other people is
	# racing, so it stays -- what it lost is the ability to host a stunt match, because the arena it
	# would play is gone (see `Lobby`).
	var mp_btn := _make_button("MultiplayerButton", "Multiplayer")
	mp_btn.pressed.connect(func() -> void: GameState.go_to_lobby())
	buttons.add_child(mp_btn)

	# SPEC 74: How to play belongs on the way IN, next to Race -- it is the first thing a new player
	# needs and the last place anyone would look for it is inside Settings.
	var help_btn := _make_button("HelpButton", "How to play")
	help_btn.pressed.connect(func() -> void: GameState.go_to_help())
	buttons.add_child(help_btn)

	var settings_btn := _make_button("SettingsButton", "Settings")
	settings_btn.pressed.connect(func() -> void: GameState.go_to_settings())
	buttons.add_child(settings_btn)

	var quit_btn := _make_button("QuitButton", "Quit")
	quit_btn.pressed.connect(_on_quit_pressed)
	# SPEC 97: a phone has no Quit -- and it was the easiest button on the screen to hit.
	quit_btn.visible = not (OS.has_feature("mobile") or OS.has_feature("web"))
	buttons.add_child(quit_btn)

	# SPEC 72: which build this is, quietly, bottom right. Nobody looks at it until something is wrong
	# -- and then it is the first thing to ask for. SPEC 115: the line above it says what the build
	# brought, because a number alone answers no question a player has.
	var build := Label.new()
	build.name = "BuildLabel"
	build.text = Version.line()
	build.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	build.add_theme_font_size_override("font_size", UiTheme.CAPTION)
	build.add_theme_color_override("font_color", UiTheme.MUTED)
	build.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	build.offset_top = -34.0
	build.offset_bottom = -10.0
	build.offset_right = -16.0
	build.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(build)

	# SPEC 112: feedback, bottom left, out of the way of the menu column -- a muted button, since it
	# is for the day something is wrong or an idea arrives, not for every visit.
	var fb := Button.new()
	fb.name = "FeedbackButton"
	fb.text = "Feedback"
	fb.custom_minimum_size = Vector2(200, 48)
	fb.add_theme_font_size_override("font_size", UiTheme.BODY)
	UiTheme.style_button(fb, UiTheme.MUTED)
	fb.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	fb.offset_left = 16.0
	fb.offset_top = -64.0
	fb.offset_right = 216.0
	fb.offset_bottom = -16.0
	fb.pressed.connect(func() -> void: feedback_card.open("the title menu", GameState.get_player_name()))
	add_child(fb)
	feedback_card = FeedbackCard.new()
	feedback_card.name = "FeedbackCard"
	add_child(feedback_card)
	feedback_card.retry_queue()          # what could not be sent last time goes now, once per run

	# SPEC 113: what's new, bottom right above the build number.
	var wn := Button.new()
	wn.name = "WhatsNewButton"
	wn.text = "What's new"
	wn.custom_minimum_size = Vector2(200, 48)
	wn.add_theme_font_size_override("font_size", UiTheme.BODY)
	UiTheme.style_button(wn, UiTheme.MUTED)
	wn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	wn.offset_left = -216.0
	wn.offset_top = -92.0
	wn.offset_right = -16.0
	wn.offset_bottom = -44.0
	wn.pressed.connect(open_whats_new)
	add_child(wn)

	# SPEC 130: the one-line summary of this build's notes USED to sit above that button. It was the
	# newest release's headlines, cut to fit, and it is gone: the title screen is a door to a race, and
	# a changelog on it is the game talking about itself. The button is still there for anybody who
	# wants the notes, and the build number underneath still says which build this is.

	whats_new_card = WhatsNewCard.new()
	whats_new_card.name = "WhatsNewCard"
	add_child(whats_new_card)
	# The big title too: a card is the screen.
	_menu_controls = [buttons, fb, wn, build, get_node_or_null("Title")]
	feedback_card.closed.connect(func() -> void: _set_menu_shown(true))
	whats_new_card.closed.connect(func() -> void: _set_menu_shown(true))
	fb.pressed.connect(func() -> void: _set_menu_shown(false))
	# Once for every new build: the notes open by themselves, and the build is remembered as seen.
	if String(GameState.settings.get("seen_version", "")) != Version.number():
		GameState.set_setting("seen_version", Version.number())
		open_whats_new.call_deferred()
	else:
		race_btn.grab_focus.call_deferred()


## SPEC 113: the release notes over the menu; the menu's own controls step aside while a card is up
## (nothing to click through, nothing for the audit to see twice).
func open_whats_new() -> void:
	_set_menu_shown(false)
	whats_new_card.open()


func _set_menu_shown(on: bool) -> void:
	for c in _menu_controls:
		if c != null and is_instance_valid(c):
			(c as CanvasItem).visible = on
	var quit := find_child("QuitButton", true, false) as Button
	if on and quit != null:
		quit.visible = not (OS.has_feature("mobile") or OS.has_feature("web"))



func _make_button(node_name: String, text: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(300, 52)
	b.add_theme_font_size_override("font_size", UiTheme.TITLE)    # SPEC 62: menu buttons ARE the menu
	UiTheme.style_button(b)
	return b


## Esc always means "back / out": in the main menu there is nowhere further back, so it quits.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		GameState.quit_game()


## Race: first the car (and colour, and the rivals), then the track.
func _on_race_pressed() -> void:
	GameState.go_to_car_select()


func _on_quit_pressed() -> void:
	GameState.quit_game()
