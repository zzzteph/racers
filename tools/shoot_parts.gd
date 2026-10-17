extends SceneTree
## One picture per part (SPEC 67): the garage, with each part in turn fitted to the car, so the 3D
## models can be looked at.  godot --path . --script res://tools/shoot_parts.gd
func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	gs.settings_path = "user://tool_settings.cfg"
	gs.profile = Profile.new()
	gs.profile.path = "user://tool_profile.cfg"
	gs.profile.coins = 99999
	gs.selected_car = "sport"
	var g: Node = load("res://scenes/garage.tscn").instantiate()
	root.add_child(g)
	for i in 20:
		await process_frame
	var shots := {"engine": ["turbo", "torque", "light_engine"], "wheels": ["slicks", "gravel", "hard"],
			"suspension": ["stiff", "soft"], "body": ["cage", "stripped"],
			"rope": ["short_rope", "long_rope"], "effects": ["flames", "stars", "underglow", "smoke"]}
	var sheet := Image.create(400 * 4, 224 * 4, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.08, 0.09, 0.11))
	var n := 0
	for tab in shots.keys():
		g.select_tab(String(tab))
		var rows: Array = g.rows_for(String(tab))
		for want in shots[tab]:
			for i in rows.size():
				if String((rows[i] as Dictionary)["id"]) == String(want):
					g.select_row(i)
					if String(tab) != "effects":
						g.take_action()
			for k in 12:
				await process_frame
			var frame: Image = root.get_viewport().get_texture().get_image()
			if n == 0:
				frame.save_png("build/shots/parts_frame.png")
				print("frame ", frame.get_size(), " format ", frame.get_format())
			frame.convert(Image.FORMAT_RGBA8)
			var img: Image = frame.get_region(Rect2i(832, 104, 400, 224))
			sheet.blit_rect(img, Rect2i(0, 0, 400, 224), Vector2i((n % 4) * 400, int(n / 4) * 224))
			n += 1
	DirAccess.make_dir_recursive_absolute("build/shots")
	sheet.save_png("build/shots/parts.png")
	print("wrote build/shots/parts.png with ", n, " parts")
	quit()
