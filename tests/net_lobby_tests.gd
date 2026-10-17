extends RefCounted
## Multiplayer lobby round (tester feedback): the room chat, the name row, the START countdown, the
## sender-clock NetPuppet, the standing rooms, the leaderboard, and the room flow. Driven in-process
## (`Net` as a host, or as a dedicated server with pretend peers -- no sockets), the way run_tests.gd
## drives its net tests. Wired from run_tests.gd with a runtime `load(...).run(self)` (a preload would
## compile FinishScreen -- and its GameState autoload reference -- before the autoloads exist).
##
## `t` is the runner: it has `check(name, ok, detail)`.

const DT := 1.0 / 60.0


static func run(t) -> void:
	test_puppet_jitter(t)
	test_chat(t)
	test_countdown(t)
	test_name_change(t)
	test_standing_rooms_and_room_flow(t)
	test_leaderboard(t)
	test_lobby_layouts(t)


static func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


static func _net() -> Node:
	return _root().get_node_or_null("Net")


static func _gs() -> Node:
	return _root().get_node_or_null("GameState")


static func _lobby() -> Node:
	var lob: Node = load("res://scenes/lobby.tscn").instantiate()
	_root().add_child(lob)
	return lob


## SPEC 128: A PACKET BUILT BY THE PRODUCER, not typed out here. This used to be a hand-written array of
## eighteen fields plus a stamp, and when `Car.get_net_state()` grew a nineteenth (the body's component
## damage) the literal did not -- so every puppet test went on exercising a packet shape the game had
## stopped sending, and the real one, whose stamp had moved, was tested by nothing. The puppet spent a
## release reading the damage bits as the sender's clock.
##
## A real car, posed and then serialised the way `Net.send_car_state()` serialises it. Now the fixture
## cannot drift away from the thing it is testing: if the schema changes again, this changes with it.
static func _packet(x: float, v: float, stamp_ms: int) -> Array:
	var c := Car.new()
	c.use_mouse = false
	c.bounds = Rect2(-100000, -100000, 200000, 200000)
	c.reset_to(Vector2(x, 0.0), 0.0)
	c.velocity = Vector2(v, 0.0)
	var out: Array = c.get_net_state(0, 1)
	out.append(stamp_ms)                 # exactly what `Net.send_car_state` appends, at the same index
	c.free()
	return out


# ---------------------------------------------------------------- 4. the puppet

## A 30 Hz stream with +-40 ms of arrival jitter, a 150 ms hole and a burst of packets held up 150 ms,
## sampled at 60 Hz: the drawn x never steps back and never jumps more than two frames of motion, the car
## stays a bounded distance behind where it really is, and the late burst is seen as late (the delay grows).
static func test_puppet_jitter(t) -> void:
	var hz := 30.0
	var v := 300.0
	var lat := 0.06
	var jit := 0.04
	var base := 1000.0            # s: the sender's clock is not the receiver's
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var packets: Array = []       # [arrival, state], in arrival order
	var last_arrival := -INF
	var dropped := 0
	for k in 120:
		var s := float(k) / hz
		if s >= 1.0 and s < 1.15:
			continue              # the hole: 150 ms of packets lost
		var arrival := s + lat + rng.randf_range(-jit, jit)
		if s >= 2.0 and s < 2.15:
			arrival = s + lat + 0.15      # a burst held up by the network: late, in order
		if arrival < last_arrival:
			dropped += 1          # an ordered channel drops a packet that was overtaken
			continue
		last_arrival = arrival
		packets.append([arrival, _packet(v * s, v, int(round((s + base) * 1000.0)))])
	var p := NetPuppet.new()
	var next := 0
	var xs := PackedFloat64Array()
	var worst_behind := 0.0
	var least_behind := INF
	var now := 0.3
	while now <= 3.9:
		while next < packets.size() and float(packets[next][0]) <= now:
			p.push(packets[next][1], now)         # pushed when its frame sees it, as the race does
			next += 1
		var smp := p.sample(now)
		if not smp.is_empty():
			var x := (smp[0] as Vector2).x
			xs.append(x)
			worst_behind = maxf(worst_behind, v * now - x)
			least_behind = minf(least_behind, v * now - x)
		now += DT
	var min_step := INF
	var max_step := -INF
	var backwards := 0
	for i in range(1, xs.size()):
		var step := xs[i] - xs[i - 1]
		min_step = minf(min_step, step)
		max_step = maxf(max_step, step)
		if step < -0.01:
			backwards += 1
	var frame := v * DT
	t.check("net puppet: a jittered 30 Hz stream (+-40 ms, a 150 ms hole, a late burst) draws a car that never steps back and never jumps more than two frames",
			xs.size() > 150 and backwards == 0 and max_step <= 2.0 * frame + 0.01 and min_step >= -0.01
			and least_behind >= 0.0 and worst_behind <= v * 0.45 and p.late_packets >= 1
			and p.delay() > NetPuppet.DELAY_MIN,
			"%d samples, step %.2f .. %.2f px (a frame is %.1f), behind %.0f .. %.0f px, %d late packets, delay %.0f ms, %d overtaken"
			% [xs.size(), min_step, max_step, frame, least_behind, worst_behind, p.late_packets,
			p.delay() * 1000.0, dropped])
	# A packet without the sender's clock (an older sender) is timed by its arrival, as before.
	var old := NetPuppet.new()
	for k in 4:
		var st: Array = _packet(float(k) * 10.0, 300.0, 0)
		st.resize(18)
		old.push(st, float(k) * 0.05)
	var mid: Array = old.sample(0.1 + 0.075)
	t.check("net puppet: an unstamped packet stream still interpolates on its arrival times, 0.1 s behind",
			absf((mid[0] as Vector2).x - 15.0) < 0.6 and is_equal_approx(old.delay(), NetPuppet.INTERP_DELAY),
			"x %.1f" % (mid[0] as Vector2).x)


# ---------------------------------------------------------------- 1. chat

static func test_chat(t) -> void:
	var net := _net()
	var gs := _gs()
	if net == null or gs == null:
		t.check("net chat: the Net autoload exists", false)
		return
	var err: int = net.host(47791)
	var got: Array = []
	var on_line := func(n: String, tx: String) -> void: got.append([n, tx])
	net.chat_received.connect(on_line)
	var first: Array = net._chat_internal(1, "  hello [b]room[/b]  ")
	var second: Array = net._chat_internal(1, "too soon")            # within 0.5 s: dropped
	net._chat_last.clear()
	var long: Array = net._chat_internal(1, "x".repeat(300))
	net._chat_last.clear()
	var blank: Array = net._chat_internal(1, "   \t ")
	net._chat_last.clear()
	net.send_chat("via the api")
	var me := String(gs.get_player_name())
	var lines: Array = net.chat_lines.duplicate()
	t.check("net chat: a line goes to the room and comes back tagged with the sender's name and colour; one per half second, trimmed to 120 printable characters, brackets out",
			err == OK and first == [1] and second.is_empty() and long == [1] and blank.is_empty()
			and got.size() == 3 and got[0][0] == me and got[0][1] == "hello broom/b"
			and String(got[1][1]).length() == net.CHAT_MAX and got[2][1] == "via the api"
			and lines.size() == 3 and lines[0]["color"] is Color and String(lines[0]["name"]) == me,
			"first %s, second %s, got %d lines: %s" % [first, second, got.size(), str(got).left(120)])
	# The client keeps the last 50 lines, and forgets them when it changes room.
	for i in 60:
		net._chat_line_local("Ann", "line %d" % i, "sport", 1)
	var kept: int = net.chat_lines.size()
	var oldest: String = String(net.chat_lines[0]["text"])
	# The lobby: a log, a line to type (44 px), SEND (44 px); Enter or SEND sends and clears the line.
	var lob := _lobby()
	var edit := lob.find_child("ChatEdit", true, false) as LineEdit
	var send := lob.find_child("ChatSendButton", true, false) as Button
	var log := lob.find_child("ChatLog", true, false) as RichTextLabel
	net._chat_last.clear()
	edit.text = "yo room"
	lob._send_chat()
	var shown: bool = log != null and log.get_parsed_text().contains("yo room") and edit.text == ""
	t.check("net chat: the client keeps the last 50 lines; the room has a log, a 44 px line and a SEND button, and a sent line shows in the log",
			kept == net.CHAT_KEEP and oldest == "line 10" and edit != null and edit.size.y >= 44.0
			and edit.max_length == net.CHAT_MAX and send != null and send.size.y >= 44.0 and shown
			and String(net.chat_lines[net.chat_lines.size() - 1]["text"]) == "yo room",
			"kept %d (oldest '%s'), shown %s" % [kept, oldest, shown])
	lob.free()
	# The relay is room-scoped: a line from room A reaches room A's players, none of room B's.
	net.mode = net.Mode.DEDICATED
	var a: int = net._create_room_internal("A", 101)
	net._join_room_internal(101, a, "", true)
	net._join_room_internal(102, a, "", true)
	var b: int = net._create_room_internal("B", 103)
	net._join_room_internal(103, b, "", true)
	net._chat_last.clear()
	var to: Array = net._chat_internal(101, "only us")
	var nobody: Array = net._chat_internal(999, "not in a room")
	net.chat_received.disconnect(on_line)
	net.leave()
	t.check("net chat: the server relays a line to the sender's room only",
			to == [101, 102] and nobody.is_empty() and net.chat_lines.is_empty(),
			"went to %s" % [to])


# ---------------------------------------------------------------- 3. the countdown

static func test_countdown(t) -> void:
	var net := _net()
	if net == null:
		return
	var err: int = net.host(47793)
	var lob := _lobby()
	var start := lob.find_child("StartButton", true, false) as Button
	var big := lob.find_child("CountdownLabel", true, false) as Label
	var track := lob.find_child("TrackButton", true, false) as Button
	var before: bool = not big.visible and start.text == "START RACE" and not start.disabled
	var started: bool = net._start_countdown(1)
	var left: float = net.countdown_left()
	var again: bool = net._start_countdown(1)
	lob._refresh()
	var counting: bool = String(net.lobby.get("state", "")) == "countdown" and big.visible and big.text == "5" \
			and start.text == "CANCEL" and not start.disabled and track.disabled
	var refused: String = net._join_room_internal(555, net.room_id)
	var listed := ""
	for r in net._rooms_view():
		listed = String(r["state"])
	var not_leader: bool = net._cancel_countdown(999)
	var cancelled: bool = net._cancel_countdown(1)
	lob._refresh()
	var back: bool = String(net.lobby.get("state", "")) == "lobby" and net.countdown_left() < 0.0 \
			and not big.visible and start.text == "START RACE"
	t.check("net countdown: START puts the room in a 5 s countdown everyone sees (5, CANCEL for the leader, setup frozen, no joining), and CANCEL takes it back",
			err == OK and before and started and left > 4.5 and left <= 5.001 and not again and counting
			and refused.contains("about to start") and listed == "countdown" and not not_leader and cancelled and back,
			# SPEC 141: every condition the check reads, not five of its eleven. It failed twice with all
			# five printed ones reading correct. SPEC 142: with all eleven printed it failed AGAIN, every one
			# reading correct -- `left` was 5.00. `countdown_end` is now + 5.0 and `countdown_left` is
			# countdown_end - now in the same millisecond: 5.0 give or take one double rounding, and the
			# check demanded `<= 5.0`. Not the port; a float compared for equality by accident.
			"host err %d, before %s, started %s, left %.2f, again %s, counting %s, refused '%s', listed %s, not-leader %s, cancelled %s, back %s"
			% [err, before, started, left, again, counting, refused, listed, not_leader, cancelled, back])
	lob.free()
	# The server starts the race when the time is up -- not before.
	net.mode = net.Mode.DEDICATED
	var rid: int = net._create_room_internal("Cd", 101)
	net._join_room_internal(101, rid, "", true)
	net._apply_setup(101, {"rivals": 0, "laps": 1})
	net._start_countdown(101)
	net._rooms[rid]["start_at"] = Time.get_ticks_msec() + 100000
	net._tick_countdowns(Time.get_ticks_msec())
	var early: bool = String(net._rooms[rid]["state"]) == "countdown"
	net._rooms[rid]["start_at"] = Time.get_ticks_msec() - 1
	net._tick_countdowns(Time.get_ticks_msec())
	var raced: bool = String(net._rooms[rid]["state"]) == "racing" and net._rooms[rid]["race"] != null
	net.leave()
	t.check("net countdown: the server starts the room's race when the countdown reaches zero, not before",
			early and raced, "early %s, raced %s" % [early, raced])


# ---------------------------------------------------------------- 2. the name row

static func test_name_change(t) -> void:
	var net := _net()
	var gs := _gs()
	if net == null or gs == null:
		return
	var old = gs.settings.get("player_name", "Player")
	var err: int = net.host(47795)
	var lob := _lobby()
	var edit := lob.find_child("MyNameEdit", true, false) as LineEdit
	var was: String = edit.text if edit != null else ""
	gs.settings["player_name"] = "Zed"            # what _save_room_name does, minus the settings file
	net.update_my_player()
	lob._refresh()
	var players := lob.find_child("Players", true, false) as RichTextLabel
	var seen: bool = String(net.players[1]["name"]) == "Zed" and edit.text == "Zed" \
			and players.get_parsed_text().contains("Zed")
	gs.settings["player_name"] = old
	net.update_my_player()
	net.leave()
	t.check("net name: YOUR NAME is a 44 px line in the room; a new name reaches the room's list at once",
			err == OK and edit != null and edit.size.y >= 44.0 and was == String(old)
			and edit.max_length == gs.MAX_NAME_LENGTH and seen,
			"was '%s', seen %s" % [was, seen])
	lob.free()


# ---------------------------------------------------------------- 6. standing rooms, 5. the room flow

static func test_standing_rooms_and_room_flow(t) -> void:
	var net := _net()
	if net == null:
		return
	var err: int = net.host(47797)
	net.mode = net.Mode.DEDICATED
	net._leave_room_internal(1)                   # the host's own room: a dedicated server has none
	net._create_standing_rooms()
	var listed: Array = []
	for r in net._rooms_view():
		listed.append([String(r["name"]), int(r["max"])])
	# SPEC 140: the two stunt rooms are gone with the arena. Three standing races are left, and what
	# the test is really about -- a standing room is fixed in size, stays public, and is made new when
	# it empties -- is unchanged.
	var want := [["Race 3", 3], ["Race 5", 5], ["Race 6", 6]]
	var first: int = int(net._rooms.keys()[0])
	# A player in "Race 3" leads it but cannot make it something else; when it empties it is made new.
	net._join_room_internal(101, first, "", false)
	var led: bool = int(net._rooms[first]["leader"]) == 101
	net._apply_setup(101, {"max": 2, "public": false, "password": "pw", "track": "singapore"})
	var pinned: bool = int(net._rooms[first]["max"]) == 3 \
			and bool(net._rooms[first]["public"]) and String(net._rooms[first]["password"]) == "" \
			and String(net._rooms[first]["setup"]["track"]) == "singapore"
	(net._rooms[first]["wins"] as Dictionary)["Ann"] = 3
	net._leave_room_internal(101)
	var renewed: bool = net._rooms.has(first) and (net._rooms[first]["players"] as Array).is_empty() \
			and String(net._rooms[first]["state"]) == "lobby" and int(net._rooms[first]["leader"]) == 0 \
			and (net._rooms[first]["wins"] as Dictionary).is_empty() \
			and String(net._rooms[first]["setup"]["track"]) != "singapore" \
			and net.is_standing_room(first)
	t.check("net rooms: a dedicated server has three standing races, first in the list in order (Race 3, Race 5, Race 6), fixed in size, made new when they empty",
			err == OK and listed.size() == 3 and listed == want and led and pinned and renewed,
			"listed %s, led %s, pinned %s, renewed %s" % [listed, led, pinned, renewed])
	# Player-made rooms live beside them, and every CREATE is a new room: two creates by one player are
	# two rooms (the first closes behind it), two players' creates are two rooms.
	var mine: int = net._create_room_internal("Mine", 201)
	net._join_room_internal(201, mine, "", true)
	var mine2: int = net._create_room_internal("Mine again", 201)
	net._join_room_internal(201, mine2, "", true)
	var other: int = net._create_room_internal("Other", 202)
	net._join_room_internal(202, other, "", true)
	var names: Array = []
	for r in net._rooms_view():
		names.append(String(r["name"]))
	var separate: bool = mine2 != mine and other != mine2 and not net._rooms.has(mine) \
			and int(net._peer_room[201]) == mine2 and int(net._peer_room[202]) == other \
			and names == ["Race 3", "Race 5", "Race 6", "Mine again", "Other"]
	# Quick join never lands in a private, locked or busy room; a standing room counts.
	var quick: int = net.quick_join_target()
	net.leave()
	t.check("net rooms: player-made rooms sit after the standing ones; every CREATE makes its own room; quick join still finds a room",
			separate and quick > 0, "rooms %s, quick %d" % [names, quick])


# ---------------------------------------------------------------- 7. the leaderboard

static func test_leaderboard(t) -> void:
	var net := _net()
	var gs := _gs()
	if net == null or gs == null:
		return
	var path := "user://test_leaderboard.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	net.leaderboard_path = path
	var err: int = net.host(47799)
	net.mode = net.Mode.DEDICATED
	var table: Array = []
	for place in range(1, 8):
		table.append(net.place_points(place))
	net.award("Ann", 1)
	net.award("Bob", 2)
	net.award("Ann", 3)
	net.award("  [x]Zed  ", 9)
	var rows: Array = net.leaderboard_rows()
	var ranked: bool = rows.size() == 3 and String(rows[0]["name"]) == "Ann" and int(rows[0]["points"]) == 15 \
			and int(rows[0]["races"]) == 2 and int(rows[0]["wins"]) == 1 and String(rows[1]["name"]) == "Bob" \
			and int(rows[1]["points"]) == 7 and String(rows[2]["name"]) == "xZed" and int(rows[2]["points"]) == 1 \
			and net.leaderboard_rank("Bob") == 2 and net.leaderboard_rank("Nobody") == 0
	var saved: bool = net.save_leaderboard()
	net._board.clear()
	net.load_leaderboard()
	var loaded: Array = net.leaderboard_rows(2)
	var reloaded: bool = loaded.size() == 2 and String(loaded[0]["name"]) == "Ann" and int(loaded[0]["points"]) == 15 \
			and int(loaded[0]["wins"]) == 1 and String(loaded[1]["name"]) == "Bob"
	t.check("net leaderboard: 10-7-5-3-2 then 1 a place, kept by name (trimmed, 16 chars, no brackets), saved to a ConfigFile and loaded back in order",
			err == OK and table == [10, 7, 5, 3, 2, 1, 1] and net.place_points(0) == 0 and ranked and saved and reloaded,
			"table %s, ranked %s, saved %s, reloaded %s" % [table, ranked, saved, reloaded])
	# A finished race: every human in the results by its place (the AI hold places), nothing for a
	# player who left before the flag; the arena's winner takes first place.
	var rid: int = net._create_room_internal("Scored", 101)
	for p in [101, 102]:
		net._join_room_internal(p, rid, "", true)
	var r: Dictionary = net._rooms[rid]
	r["state"] = "racing"
	r["race_setup"] = {"entries": [
		{"key": 0, "kind": "human", "peer": 101, "name": "Ann"},
		{"key": 1, "kind": "human", "peer": 102, "name": "Bob"},
		{"key": 2, "kind": "ai", "peer": 0, "name": "Bot"},
		{"key": 3, "kind": "human", "peer": 103, "name": "Cy"}]}
	r["results"] = [{"key": 2, "time": 60.0}, {"key": 0, "time": 61.0}, {"key": 1, "time": 62.0}]
	net._award_race(rid)
	var after: Array = net.leaderboard_rows()
	var scored: bool = after.size() == 3 and int(net._board["Ann"]["points"]) == 22 and int(net._board["Ann"]["races"]) == 3 \
			and int(net._board["Bob"]["points"]) == 12 and not net._board.has("Cy")
	# SPEC 140: the second half of this used to score a stunt match's winner. There are no stunt
	# matches, so what is left is the race scoring -- which is the part that mattered anyway.
	t.check("net leaderboard: a finished race scores its humans by place (AI hold places, a leaver gets nothing)",
			scored, "Ann %s, Bob %s, Cy on the board %s" % [
			net._board.get("Ann"), net._board.get("Bob"), net._board.has("Cy")])
	net.leave()
	net.leaderboard_path = net.LEADERBOARD_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# The client: the award signal and the rows; the finish screen's line under the place, in either order.
	var awards: Array = []
	var on_award := func(pts: int, total: int, rank: int) -> void: awards.append([pts, total, rank])
	net.points_awarded.connect(on_award)
	var fs: FinishScreen = FinishScreen.new()
	_root().add_child(fs)
	fs.set_online(true)
	net._points_awarded(7, 58, 12)
	var line := fs.find_child("PointsLabel", true, false) as Label
	var by_signal: bool = line != null and line.visible and line.text == "+7 pts  -  leaderboard #12 (58 pts)"
	fs.show_results("Circle", 60.0, [20.0, 20.0, 20.0], 20.0, false, false, 20.0, 60.0)
	var kept: bool = line.visible
	net.last_award = {}
	fs.show_results("Circle", 60.0, [20.0, 20.0, 20.0], 20.0, false, false, 20.0, 60.0)
	var gone: bool = not line.visible
	net.points_awarded.disconnect(on_award)
	fs.free()
	var got_rows: Array = []
	var on_rows := func() -> void: got_rows.append(net.leaderboard.size())
	net.leaderboard_changed.connect(on_rows)
	net._leaderboard([{"name": "Ann", "points": 22, "races": 3, "wins": 1}])
	net.leaderboard_changed.disconnect(on_rows)
	t.check("net leaderboard: the client hears its award and the rows; the finish screen shows '+7 pts  -  leaderboard #12 (58 pts)' under the place, before or after the card, and never without an award",
			awards == [[7, 58, 12]] and by_signal and kept and gone and got_rows == [1]
			and int(net.leaderboard[0]["points"]) == 22,
			"awards %s, by signal %s, kept %s, gone %s, rows %s" % [awards, by_signal, kept, gone, got_rows])
	net.leaderboard = []
	net.last_award = {}


# ---------------------------------------------------------------- the screens

## SPEC 120: the room view -- PLAYERS and the leaderboard on the left, the CHAT on the right, the race
## setup in one wide panel below -- and the room browser, which no longer carries the leaderboard at
## all. No text overlaps or clipping anywhere, every control at least 44 px tall.
static func test_lobby_layouts(t) -> void:
	var net := _net()
	var gs := _gs()
	if net == null or gs == null:
		return
	var err: int = net.host(47801)
	net._chat_line_local("Ann", "see you on the grid", "sport", 1)
	var lob := _lobby()
	lob._refresh()
	var room_box := lob.find_child("RoomBox", true, false) as Control
	var room_problems: Array = UiAudit.audit(lob)
	var short := _short_controls(room_box)
	var pieces: bool = lob.find_child("MyNameEdit", true, false) != null and lob.find_child("ChatEdit", true, false) != null \
			and lob.find_child("ChatSendButton", true, false) != null and lob.find_child("StartButton", true, false) != null
	# SPEC 120: the leaderboard is IN the room, and there is no AI to configure in one.
	var board_here: bool = lob.find_child("Board", true, false) != null
	var no_ai: bool = lob.find_child("RivalsLess", true, false) == null \
			and lob.find_child("RivalsMore", true, false) == null \
			and lob.find_child("Level_hard", true, false) == null
	t.check("lobby: the room -- players and the leaderboard left, chat right, the setup below, and no AI to set -- has no overlaps and every control is 44 px or taller",
			err == OK and room_box != null and room_box.visible and pieces and board_here and no_ai \
			and room_problems.is_empty() and short.is_empty(),
			"; ".join(UiAudit.lines(room_problems)) + (" short: %s" % [short] if not short.is_empty() else ""))
	net.leave()
	# The browser, as a client of a dedicated server sees it: standing rooms and a player's room, a
	# leaderboard with 16-character names, CREATE ROOM in plain sight.
	net.mode = net.Mode.CLIENT
	net.server_kind = "dedicated"
	net.room_id = -1
	net.rooms_list = [
		{"id": 1, "name": "Race 6", "players": 2, "max": 6, "track": "Pit Lane", "state": "lobby", "locked": false},
		{"id": 3, "name": "Race 3", "players": 3, "max": 3, "track": "Circle", "state": "racing", "locked": false},
		{"id": 5, "name": "Race 6", "players": 4, "max": 6, "track": "Figure 8", "state": "countdown", "locked": false},
		{"id": 6, "name": "Stephan's evening race", "players": 1, "max": 6, "track": "Bahrain", "state": "lobby", "locked": true}]
	var rows: Array = []
	for i in 12:
		rows.append({"name": "Racer_Number_%02d" % i if i != 3 else String(gs.get_player_name()), "points": 1000 - i * 37,
				"races": 20, "wins": 3})
	net.leaderboard = rows
	lob._refresh()
	var browser := lob.find_child("BrowserBox", true, false) as Control
	var create := lob.find_child("CreateRoomButton", true, false) as Button
	# SPEC 120: no leaderboard on this screen any more -- it belongs to the room.
	var no_board: bool = lob.find_child("Board_4", true, false) == null
	var starting := lob.find_child("Join_5", true, false) as Button
	var browser_problems: Array = UiAudit.audit(lob)
	var short2 := _short_controls(browser)
	t.check("lobby: the room browser -- the rooms (a starting one says so) and CREATE ROOM, and no leaderboard -- no overlaps, every control 44 px or taller",
			browser != null and browser.visible and create != null and create.is_visible_in_tree() and create.text == "CREATE ROOM"
			and no_board and starting != null and starting.disabled and starting.text == "Starting"
			and browser_problems.is_empty() and short2.is_empty(),
			"; ".join(UiAudit.lines(browser_problems)) + (" short: %s" % [short2] if not short2.is_empty() else ""))
	lob.free()
	net.leave()


## Visible buttons and text fields under `box` that are shorter than 44 px, by name.
static func _short_controls(box: Control) -> Array:
	var out: Array = []
	if box == null:
		return out
	for c in box.find_children("*", "Button", true, false) + box.find_children("*", "LineEdit", true, false):
		var ctl := c as Control
		if ctl.is_visible_in_tree() and ctl.size.y < 44.0:
			out.append("%s (%.0f)" % [ctl.name, ctl.size.y])
	return out
