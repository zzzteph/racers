extends SceneTree
## Screenshot tool: drives a real race for a few seconds and writes PNGs of the running game, so a view
## change (the close camera, SPEC 50) can be looked at instead of guessed at.
##
##   godot --path . --script res://tools/shoot_race.gd -- --track miami --close 1 --shots 3 --out build/shots
##
## Options: --track <id>, --close 0|1 (the close camera), --rivals <n>, --seconds <s before the first
## shot>, --gap <s between shots>, --shots <n>, --out <dir>.

const DT := 1.0 / 60.0

var _track := "figure8"
var _close := true
var _rivals := 3
var _seconds := 6.0
var _gap := 2.0
var _shots := 2
var _out := "build/shots"


func _init() -> void:
	_parse_args()
	await process_frame            # the tree (and the autoloads) exist from here on
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		printerr("GameState autoload missing")
		quit(1)
		return
	# A tool must not leave anything in the player's settings.cfg, and several GameState calls save the
	# whole dictionary -- so the save target is pointed at a throwaway file first.
	gs.settings_path = "user://tool_settings.cfg"
	gs.settings["close_camera"] = _close
	gs.set_opponent_count(_rivals)
	gs.selected_track = _track
	var scene: PackedScene = load("res://scenes/race.tscn")
	var race: Node = scene.instantiate()
	root.add_child(race)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out) if _out.begins_with("res://") else _out)
	await process_frame
	# Let the countdown run out, then drive: the player's car follows the racing line of a rival's AI is
	# not available here, so it simply keeps the cursor ahead of itself -- enough to move and to be seen.
	var frames := int(_seconds / DT)
	var gap_frames := int(_gap / DT)
	for shot in _shots:
		var n := frames if shot == 0 else gap_frames
		for i in n:
			if race.pause_menu != null and race.pause_menu.is_open():
				race.resume_race()          # a tool's window never has focus, and the race pauses on that
			if race.has_method("_physics_process"):
				race.car.target_point = race.track.centerline[
						(race.track.get_progress_index() + 8) % race.track.get_point_count()]
				race.car.use_mouse = false
				race._physics_process(DT)
			await process_frame
		await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var path := "%s/race_%s_%s_%d.png" % [_out, _track, "close" if _close else "far", shot]
		img.save_png(path)
		print("wrote ", path)
	quit()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := String(args[i])
		var v := String(args[i + 1]) if i + 1 < args.size() else ""
		match a:
			"--track": _track = v
			"--close": _close = v != "0"
			"--rivals": _rivals = int(v)
			"--seconds": _seconds = float(v)
			"--gap": _gap = float(v)
			"--shots": _shots = int(v)
			"--out": _out = v
		i += 2
