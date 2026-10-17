extends SceneTree
## Every screen, audited for text that does not fit and text that collides (SPEC 97, `UiAudit`).
##   godot --path . --script res://tools/check_overlaps.gd
## Exit code 1 when anything is wrong. Windowed: the layouts need a frame or two.
## SPEC 111: the race's screens too (countdown, racing with everything on, wrecked, paused, finished),
## and the timing tower and the minimap count as boxes ("UI elements overlap the leaderboard and the map").
##
## SPEC 122: EVERY SELECTION, not just the one a screen opens on. A default-state pass audited the Sport
## and the Circle and nothing else, so two car descriptions that did not fit their labels, a track whose
## description sat on its reward line and three help lines over their boxes all went unreported for as
## long as they existed. The sweep below opens each screen once and then steps it through every car,
## every track and every help page, auditing each.

const SCREENS := [
	["main menu", "res://scenes/main_menu.tscn"],
	["garage", "res://scenes/garage.tscn"],
	["settings", "res://scenes/settings.tscn"],
	["lobby", "res://scenes/lobby.tscn"],
]


func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	gs.settings_path = "user://tool_settings.cfg"
	gs.profile = Profile.new()
	gs.profile.path = "user://tool_profile.cfg"
	gs.profile.coins = 900
	var total := 0
	for pair in SCREENS:
		var node: Node = load(String(pair[1])).instantiate()
		root.add_child(node)
		for i in 6:
			await process_frame
		total += _report(String(pair[0]), node)
		node.free()
		await process_frame
	total += await _sweep_selections(gs)
	total += await _audit_race(gs)
	print("")
	print("%d problem%s" % [total, "" if total == 1 else "s"])
	quit(1 if total > 0 else 0)


## SPEC 122: the screens whose content CHANGES with what is highlighted -- every car, every track, every
## help page. One instance each,
## stepped through its states, because building a scene is much slower than changing its selection.
func _sweep_selections(gs: Node) -> int:
	var total := 0

	var cars: Node = load("res://scenes/car_select.tscn").instantiate()
	root.add_child(cars)
	for i in 6:
		await process_frame
	for i in CarRegistry.ids().size():
		cars.select_car(i)
		for k in 3:
			await process_frame
		total += _report("car select: %s" % CarRegistry.get_display_name(String(CarRegistry.ids()[i])), cars)
	cars.free()
	await process_frame

	var tracks: Node = load("res://scenes/track_select.tscn").instantiate()
	root.add_child(tracks)
	for i in 6:
		await process_frame
	for i in TrackRegistry.ids().size():
		tracks.select_track(i)
		for k in 4:
			await process_frame
		total += _report("track select: %s" % TrackRegistry.get_display_name(String(TrackRegistry.ids()[i])), tracks)
	# SPEC 122: a solo run is a TIME TRIAL and says different things; audit that too.
	gs.set_opponent_count(0)
	tracks.select_track(0)
	for k in 4:
		await process_frame
	total += _report("track select: time trial", tracks)
	gs.set_opponent_count(3)
	tracks.free()
	await process_frame

	var help: Node = load("res://scenes/help.tscn").instantiate()
	root.add_child(help)
	for i in 6:
		await process_frame
	for i in help.page_count():
		help.show_page(i)
		for k in 3:
			await process_frame
		total += _report("help: page %d" % (i + 1), help)
	help.free()
	await process_frame

	return total


## SPEC 111: a race with a full field on the Serpent (the tower at its tallest, the minimap on), at
## every point a player sees: the countdown, mid-race with every message up, wrecked, paused, finished.
func _audit_race(gs: Node) -> int:
	var total := 0
	gs.selected_track = "serpent"
	gs.set_opponent_count(7)
	var race: Node = load("res://scenes/race.tscn").instantiate()
	root.add_child(race)
	for i in 6:
		await process_frame
	race._update_standings()
	await process_frame
	total += _report("race countdown", race)
	race.car.use_mouse = false
	for i in 4 * 60:
		race.car.target_point = race.car.position + Vector2.from_angle(race.car.heading) * 260.0
		race._physics_process(1.0 / 60.0)
		if i % 6 == 0:
			await process_frame
	race.hud.flash_message("WRONG WAY  -  turn around", Color(1.0, 0.36, 0.25), 2)
	race.hud.set_hint("Bring the cursor to your car")
	race.hud.set_off_track(true)
	race.hud.set_touch_controls(true)
	race.hud.set_gap("+12 m")
	await process_frame
	total += _report("race racing", race)
	race.hud.set_touch_controls(false)
	race.car.damage_enabled = true
	race._on_car_wrecked()
	race._physics_process(1.0 / 60.0)
	await process_frame
	total += _report("race wrecked", race)
	race._wreck_left = 0.0
	race._respawn()
	race.pause_race()
	await process_frame
	total += _report("race paused", race)
	race.resume_race()
	race.finish_race(184.2, [61.4, 61.4, 61.4])
	for i in 3:
		await process_frame
	total += _report("race finished", race)
	race.free()
	await process_frame
	return total


func _report(screen: String, node: Node) -> int:
	var problems := UiAudit.audit(node)
	print("--- %s: %d" % [screen, problems.size()])
	for line in UiAudit.lines(problems):
		print("    " + line)
	return problems.size()
