extends SceneTree
## Posts one feedback entry to the Google Form from the command line (SPEC 112): to check that the form
## still takes what the game sends after the form is edited, or to file a note without the game.
##   godot --headless --path . --script res://tools/send_feedback.gd -- --rating 5 --type General
##       --details "Test from the build machine" --name "Steph" [--where "the command line"]
## Exit code 0 when Google answered 2xx/3xx.


func _init() -> void:
	await process_frame
	var opts := {"rating": "0", "type": Feedback.DEFAULT_TYPE, "details": "", "name": "", "where": "the command line"}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i + 1 < args.size():
		var key := String(args[i])
		if key.begins_with("--") and opts.has(key.substr(2)):
			opts[key.substr(2)] = String(args[i + 1])
			i += 2
		else:
			i += 1
	var body := Feedback.build_body(int(opts["rating"]), String(opts["type"]), String(opts["details"]),
			String(opts["name"]), String(opts["where"]))
	print("posting to %s" % Feedback.FORM_URL)
	for k in Feedback.parse_body(body).keys():
		print("  %s = %s" % [k, String(Feedback.parse_body(body)[k]).replace("\n", " / ")])
	var http := HTTPRequest.new()
	http.timeout = 20.0
	root.add_child(http)
	var err := http.request(Feedback.FORM_URL, Feedback.HEADERS, HTTPClient.METHOD_POST, body)
	if err != OK:
		print("request refused (error %d)" % err)
		quit(1)
		return
	var res: Array = await http.request_completed
	var ok := int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) >= 200 and int(res[1]) < 400
	print("%s -- HTTP %d (result %d)" % ["sent" if ok else "FAILED", int(res[1]), int(res[0])])
	quit(0 if ok else 1)
