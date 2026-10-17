extends SceneTree
## SPEC 144: are the bought effects visible in a race? Every effect owned and worn in a tool profile, a
## race started through the menu (the player's path), the car driven flat out for a few seconds, and
## the frame shot. Prints what the race's CarEffects believes it is wearing.
##   godot --path . --script res://tools/shoot_effects.gd

func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	gs.settings_path = "user://tool_settings.cfg"
	gs.records_path = "user://tool_records.cfg"
	gs.profile = Profile.new()
	gs.profile.path = "user://tool_profile.cfg"
	gs.profile.coins = 100000
	for e in Profile.EFFECTS:
		gs.profile.buy_effect(e)
	gs.set_opponent_count(0)
	print("profile worn: %s" % str(gs.profile.equipped))
	change_scene_to_file("res://scenes/main_menu.tscn")
	for k in 30:
		await _frame()
	gs.start_race("circle")
	var race: Node = null
	while true:
		await _frame()
		race = current_scene
		if race != null and "phase" in race and race.get("car") != null:
			break
	print("race wears: %s  (tint %s)" % [str(race.car_effects.cosmetics), str(race.car_effects.cosmetic_tint)])
	race.car.use_mouse = false
	var t = race.track
	var n: int = t.get_point_count()
	var guard := 0
	while guard < 900 and (int(race.phase) != 1 or guard < 400):
		var i: int = t.get_nearest_index(race.car.position)
		race.car.target_point = t.centerline[(i + 7) % n]
		await _frame()
		guard += 1
	var img: Image = root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://build/spike")
	var at: Vector2 = race.car.get_global_transform_with_canvas().origin
	var box := Rect2i(int(at.x) - 160, int(at.y) - 100, 320, 200).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(box)
	crop.resize(box.size.x * 3, box.size.y * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png("res://build/spike/effects_race.png")
	print("speed %.0f, on track %s, puffs alive %d  -> build/spike/effects_race.png (3x crop round the car)" % [
			race.car.get_speed(), not race.car.is_off_track(), race.car_effects._puff_count])
	quit()


func _frame() -> void:
	await process_frame
	if paused:
		paused = false
		var s := current_scene
		if s != null and s.get("pause_menu") != null and s.pause_menu.is_open():
			s.pause_menu.close()
