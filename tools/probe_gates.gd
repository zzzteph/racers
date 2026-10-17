extends SceneTree
## SPEC 124: WHERE A SHORTCUT MAY GO. A breakable wall is only worth having if the route behind it is a
## LEGAL lap -- every checkpoint still passed -- so this prints each circuit's gates, in order, with the
## radius a car has to come inside. A cut that bypasses one of these voids the lap it was taken on.
##   godot --headless --path . --script res://tools/probe_gates.gd [-- --track=serpent]   (default: all)


func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.settings_path = "user://tool_settings.cfg"
	var want := "all"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--track"):
			want = String(a).split("=")[-1]
	for id in TrackRegistry.ids():
		var sid := String(id)
		if want != "all" and sid != want:
			continue
		var t := Track.new()
		t.setup(sid)
		root.add_child(t)
		print("")
		print("%s -- %d gates, radius %.0f px, world %s" % [sid, t.get_checkpoint_positions().size(),
				t.get_checkpoint_radius(), t.world_size])
		var idx := t.get_checkpoint_indices()
		var pos := t.get_checkpoint_positions()
		for i in pos.size():
			print("  gate %2d  index %4d   at %6.0f, %6.0f" % [i, int(idx[i]), pos[i].x, pos[i].y])
		t.free()
	quit(0)
