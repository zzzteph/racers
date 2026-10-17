class_name PauseMenu
extends CanvasLayer
## Pause overlay (Esc). Runs while the tree is paused.

signal resume_requested
signal restart_requested
signal menu_requested
## The title menu (Esc from the pause menu's "Main menu" button).
signal main_menu_requested
## SPEC 91/130: the rules card, again, from the pause menu.
signal rules_requested
## SPEC 112: the feedback card.
signal feedback_requested

var _root: Control
var _resume_button: Button
## SPEC 122: kept, because online this card is not a pause and must not say it is.
var _title: Label = null


func _init() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -170.0
	panel.offset_right = 170.0
	panel.offset_top = -150.0
	panel.offset_bottom = 150.0
	# Opaque background: the default PanelContainer style is translucent, so the road and the big "GO" /
	# countdown text behind it showed through the menu labels.
	panel.add_theme_stylebox_override("panel", _make_opaque_panel_style())
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.name = "Title"
	title.text = "Paused"
	_title = title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UiTheme.TITLE)   # SPEC 62
	box.add_child(title)

	_resume_button = _make_button(box, "ResumeButton", "Resume")
	_resume_button.pressed.connect(func() -> void: resume_requested.emit())
	var restart := _make_button(box, "RestartButton", "Restart")
	restart.pressed.connect(func() -> void: restart_requested.emit())
	var rules := _make_button(box, "RulesButton", "Rules")
	rules.visible = false
	rules.pressed.connect(func() -> void: rules_requested.emit())
	var menu := _make_button(box, "MenuButton", "Tracks")
	var main := _make_button(box, "MainMenuButton", "Main menu")
	main.pressed.connect(func() -> void: main_menu_requested.emit())
	menu.pressed.connect(func() -> void: menu_requested.emit())
	# SPEC 112: the moment something goes wrong is the moment to say so.
	var feedback := _make_button(box, "FeedbackButton", "Feedback")
	feedback.pressed.connect(func() -> void: feedback_requested.emit())


## Fully opaque dialog background (same look as the finish screen).
static func _make_opaque_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.14)
	sb.border_color = Color(0.45, 0.47, 0.52)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(4)
	return sb


func _make_button(parent: Control, node_name: String, text: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(260, 52)
	b.add_theme_font_size_override("font_size", UiTheme.HEADING)     # SPEC 62
	UiTheme.style_button(b)
	parent.add_child(b)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()


func open() -> void:
	visible = true
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_inside_tree():
		_resume_button.grab_focus()


func close() -> void:
	visible = false
	_root.visible = false


func is_open() -> bool:
	return visible


## SPEC 91/130: the briefing (`RulesCard`) under Rules.
func set_rules(on: bool) -> void:
	var b := find_child("RulesButton", true, false) as Button
	if b != null:
		b.visible = on


## In a network race the game cannot pause for everyone: Restart and Tracks make no sense, and the menu
## says so.
## SPEC 122: online, the match does NOT stop for this menu -- the other cars are still driving and the
## clock is still running. Calling the card "Paused" told the player the opposite of what was happening.
func set_online(on: bool) -> void:
	if _title != null:
		_title.text = "Menu  -  the match continues" if on else "Paused"

	for n in ["RestartButton", "MenuButton"]:
		var b := find_child(n, true, false) as Button
		if b != null:
			b.visible = not on
	var main := find_child("MainMenuButton", true, false) as Button
	if main != null:
		main.text = "Leave race" if on else "Main menu"
