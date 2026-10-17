extends SceneTree
## SPEC 136: a picture of the gear notches on the rope, at several rope lengths.
##
## Must run WINDOWED -- headless renders nothing, so no probe of a drawing can be trusted there (the same
## rule that let a field of cars sit facing backwards through three rounds of fixes, SPEC 134).
##
##   godot --path . --script res://tools/shot_rope_gears.gd
##
## Writes build/shots/rope-gear-<n>.png, one per rope length, cropped around the car.

const OUT := "res://build/shots"
const CROP := 520
## Fractions of the car's full-throttle rope to hold the cursor at.
const PULLS := [0.18, 0.45, 0.72, 1.0]


func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		printerr("no GameState")
		quit(1)
		return
	gs.settings_path = "user://tool_settings.cfg"
	# Records and the profile too, not just the settings: this tool spawns REAL races, which
	# submit lap times and pay coins. Every other tool in here isolates the settings alone, which is a
	# gap waiting to write somebody's actual save (cf. the rule about `set_setting`).
	gs.records_path = "user://tool_records.cfg"
	gs.profile = Profile.new()
	gs.profile.path = "user://tool_profile.cfg"
	gs.selected_track = "circle"
	gs.set_opponent_count(0)
	DirAccess.make_dir_recursive_absolute(OUT)
	var race: Node = load("res://scenes/race.tscn").instantiate()
	root.add_child(race)
	for k in 20:
		await process_frame
	if race.has_method("_begin_racing"):
		race._begin_racing()
	for k in 10:
		await process_frame
	var car: Car = race.car
	var full: float = car.slack_radius + car.max_speed / car.speed_per_px
	print("")
	print("%s: slack %.0f px, full throttle at %.0f px." % [car.car_id, car.slack_radius, full])
	print("gear tops (px from the car): %s" % [_radii(car)])
	print("")
	for i in PULLS.size():
		var pull: float = float(PULLS[i])
		# The car DRIVES, with the rope held at a fixed length, and the RACE drives it -- stepping the car
		# by hand does not work here, because the race's own `_physics_process` runs on every awaited
		# frame and re-points the rope at the real mouse. (Two rounds of identical-looking screenshots
		# before that was spotted.) `use_mouse` off makes `Race._player_target()` read `target_point`.
		car.use_mouse = false
		car.unlock()
		for k in 120:
			car.target_point = car.position + Vector2.from_angle(car.heading) * full * pull
			await process_frame
		var img: Image = root.get_texture().get_image()
		var at: Vector2 = _screen_pos(race, car)
		var box := Rect2i(int(at.x) - CROP / 2, int(at.y) - CROP / 2, CROP, CROP)
		box = box.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		if box.size.x > 8 and box.size.y > 8:
			img = img.get_region(box)
		var path := "%s/rope-gear-%d.png" % [OUT, i + 1]
		img.save_png(path)
		print("%3.0f %% of the rope (%3.0f px)  ->  %s" % [pull * 100.0, full * pull, path])
	print("")
	race.free()
	quit()


func _radii(car: Car) -> String:
	var out := PackedStringArray()
	for s in Gearbox.GEAR_TOP_SPEED:
		out.append("%.0f" % (car.slack_radius + float(s) / car.speed_per_px))
	return ", ".join(out)


func _screen_pos(race: Node, car: Car) -> Vector2:
	var cam: Camera2D = race.world_camera if "world_camera" in race else null
	if cam == null:
		return Vector2(root.size) * 0.5
	return (car.position - cam.get_screen_center_position()) * cam.zoom + Vector2(root.size) * 0.5
