extends SceneTree
## Renders the pictures the How to play screen shows (SPEC 63): a car on the rope, the race order and the
## minimap, and the garage. Saved to art/help/*.png and shipped with the game.
##   godot --path . --script res://tools/make_help_art.gd

const OUT := "res://art/help"


func _init() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var gs: Node = root.get_node_or_null("GameState")
	gs.settings_path = "user://tool_settings.cfg"
	gs.profile = Profile.new()
	gs.profile.path = "user://tool_profile.cfg"
	gs.profile.coins = 4000
	gs.profile.buy_part("sport", "slicks")
	gs.settings["unlock_all"] = true
	gs.set_opponent_count(3)
	gs.selected_track = "figure8"
	var race: Node = load("res://scenes/race.tscn").instantiate()
	root.add_child(race)
	while race.phase == 0:
		await process_frame
	race.car.use_mouse = false
	var t: Node = race.track
	# The race pauses when the window loses focus, and a tool's window never has it -- so the race is
	# stepped by hand here, exactly as the other shooting tools do.
	for i in 220:
		var idx: int = t.get_progress_index()
		race.car.target_point = t.centerline[(idx + 9) % t.get_point_count()]
		if race.pause_menu.is_open():
			race.resume_race()
		race._physics_process(1.0 / 60.0)
		await process_frame
	var frame: Image = root.get_viewport().get_texture().get_image()
	# The car and its rope: cropped around where the car actually is on screen, not where it usually is.
	var at: Vector2 = race.world_to_screen(race.car.position)
	var cursor: Vector2 = race.world_to_screen(race.car.get_rope_target())
	var mid := (at + cursor) * 0.5
	var box := Rect2i(int(clampf(mid.x - 280.0, 0.0, 720.0)), int(clampf(mid.y - 160.0, 0.0, 400.0)), 560, 320)
	_save(frame.get_region(box), "rope.png")
	# The race order and the minimap, along the top.
	_save(frame.get_region(Rect2i(0, 0, 1280, 240)), "hud.png")
	race.free()
	await process_frame
	var garage: Node = load("res://scenes/car_select.tscn").instantiate()
	root.add_child(garage)
	for i in 30:
		await process_frame
	var shot: Image = root.get_viewport().get_texture().get_image()
	_save(shot.get_region(Rect2i(920, 120, 360, 540)), "garage.png")
	garage.free()
	print("wrote the help pictures")
	quit()


func _save(img: Image, name: String) -> void:
	img.save_png("%s/%s" % [OUT, name])
	print("  ", name, " ", img.get_size())
