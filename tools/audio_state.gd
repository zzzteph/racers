extends SceneTree
## SPEC 139: what does the audio layer think it is doing?
##
## "There is no sound in the web version." A browser probe established that the page's AudioContext is
## running, Godot's output nodes are connected to the destination, and the level is flat zero for three
## minutes -- so the question moved inside the engine: is the game even ASKING for sound?
##
## This prints the audio layer's own state on a real (windowed) run: whether it is live, how much of the
## render plan is left, which sounds exist, whether the music player is playing, and what the buses are
## set to. Run it on the desktop build as the control, because the same code runs on both.
##
##   godot --path . --script res://tools/audio_state.gd
## (Must be WINDOWED: a headless run sets `_silent` and renders nothing by design.)

const WAIT := 40.0


func _init() -> void:
	await process_frame
	var a: Node = root.get_node_or_null("Audio")
	if a == null:
		printerr("no Audio autoload")
		quit(1)
		return
	print("")
	print("driver=%s  mix_rate=%d  output_latency=%s" % [AudioServer.get_driver_name(),
			AudioServer.get_mix_rate(), ProjectSettings.get_setting("audio/driver/output_latency")])
	var t := 0.0
	var last := -1
	while t < WAIT:
		await process_frame
		t += 1.0 / 60.0
		var left: int = (a.get("_jobs") as Array).size()
		if left != last:
			last = left
			print("%5.1fs  jobs left %3d   rendered %2d" % [t, left, (a.get("_wav") as Dictionary).size()])
	var wav: Dictionary = a.get("_wav")
	var player: AudioStreamPlayer = a.get("_music_player")
	print("")
	print("live            = %s" % a.get("_live"))
	print("silent          = %s" % a.get("_silent"))
	print("music_enabled   = %s" % a.get("music_enabled"))
	print("music_volume    = %.2f   sfx_volume = %.2f" % [a.get("music_volume"), a.get("sfx_volume")])
	print("rendered sounds = %d  %s" % [wav.size(), str(wav.keys()).substr(0, 300)])
	print("music_race wav  = %s" % ("present" if wav.has("music_race") else "MISSING"))
	if player != null:
		print("music player    : playing=%s stream=%s volume_db=%.1f bus=%s"
				% [player.playing, player.stream, player.volume_db, player.bus])
	for name in ["Master", "Music", "Sfx"]:
		var i := AudioServer.get_bus_index(name)
		if i < 0:
			print("bus %-7s    : MISSING" % name)
		else:
			print("bus %-7s    : volume_db=%.1f mute=%s effects=%d"
					% [name, AudioServer.get_bus_volume_db(i), AudioServer.is_bus_mute(i),
					AudioServer.get_bus_effect_count(i)])
	print("")
	quit()
