extends Node
## Multiplayer (autoload "Net"). Direct-IP over WebSockets -- the one transport every build can speak,
## the browser (web) build included.
##
##   * HOST GAME: this machine is the server AND plays. It has one room -- its own -- and everyone who
##     joins goes straight into it.
##   * DEDICATED SERVER (`--headless -- --server [--port 7777]`, Windows or Linux): holds any number of
##     named ROOMS. A player who connects sees the room list, creates a room with a name or joins one;
##     a room that is already racing cannot be joined. Every room races on its own, at the same time --
##     the server runs one race node per racing room (it simulates that room's AI and keeps its results).
##
## Authority per car: every human's car is simulated on that human's own machine (the rope feels as it
## does in single player, whatever the ping); the AI of a room by the server. Owners send their car's
## state ~30 times a second; the server relays it to the rest of the ROOM, who draw it as a smoothly
## interpolated NetPuppet. Wrecks and finishes go reliably; the server keeps the finishing order.
##
## Every machine keeps a mirror of ITS room (`players`, `lobby`) for the UI; a dedicated server is not in
## a room, so its own mirrors stay empty.
##
## SPEC 43 -- rooms and connections, Among-Us style:
##   * a room is PUBLIC (in the room list) or PRIVATE (only by its 6-letter CODE), may have a PASSWORD,
##     has a player limit (2-6) the leader sets, and the leader can kick; QUICK JOIN drops you into the
##     busiest open public room (or makes one);
##   * the client and server check their PROTOCOL version on connect ("server is 1.6, you have 1.5");
##   * the client measures its PING; if the connection drops it RECONNECTS for 30 s and the server gives
##     it its seat back (same room, by a per-install token);
##   * a dedicated server can announce itself to the server directory (a Cloudflare Worker) every 30 s;
##     the client reads that list for its "Servers" tab. OFFICIAL_URL is the default server.
##
## The room's lobby has a CHAT (`send_chat` -> `_chat` -> the server relays `_chat_line` to the ROOM, one
## line per half second per player, 120 characters, tagged with the sender's car colour) and START is a
## COUNTDOWN: the leader's START puts the room in state "countdown" with `start_at` 5 s ahead, every
## client shows 5-4-3-2-1 from the view's `countdown` seconds, the leader can CANCEL, and the server
## starts the race (`start_race`) when the time is up. Car states carry the SENDER's clock as a trailing
## element, so a NetPuppet interpolates on the sender's timeline (see net_puppet.gd).

## SPEC 125: the server refused a room -- a wrong password, a full room, one that has gone.
signal room_refused(reason: String)
signal lobby_changed()
signal rooms_changed()
signal status_changed(text: String)
signal disconnected(reason: String)
## A chat line for my room arrived (it is also the last entry of `chat_lines`).
signal chat_received(name: String, text: String)
## The server scored my race: `points` for this one, `total` now, `rank` on its leaderboard.
signal points_awarded(points: int, total: int, rank: int)
## The server's leaderboard rows arrived (`leaderboard`).
signal leaderboard_changed()

enum Mode { OFFLINE, HOST, CLIENT, DEDICATED }

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 6                 # per room
const MAX_ROOMS := 32
const SEND_EVERY := 2                  # physics frames between state packets (60 Hz / 2 = 30 Hz)
const LAPS_CHOICES := [3, 5, 10]
const RACE_SCENE := preload("res://scenes/race.tscn")
const RESULTS_TIME := 6.0              # s a dedicated room shows its results before going back to its lobby
## The official server and the server directory (SPEC 43). The game server sits behind Caddy (TLS) on /ws.
const OFFICIAL_URL := "wss://rope.thenakedcat.games/ws"
const OFFICIAL_NAME := "rope.thenakedcat.games"
const DIRECTORY_URL := "https://rope.thenakedcat.games/api/servers"
## Bump when the wire format changes: a client and a server with different protocols refuse each other.
## SPEC 93: 3 -- rooms carry a mode (race / arena) and the arena's own traffic (`_arena_up` /
## `_arena_down`); a 2 client would join a room it cannot play.
## 4 -- the lobby chat (`_chat` / `_chat_line`), the start countdown (`_request_cancel`, room state
## "countdown") and sender-stamped car states. Godot numbers RPCs by their sorted names, so a build
## with other RPC methods cannot even be refused politely: it must not connect at all.
## SPEC 114: 5 -- the stunt arena. The score rows carry two more fields (the pot and the trick count),
## the "coin" and "coins" messages are gone and a "bonuses" one takes the latter's place, and the
## WRECKER arrives with "points" rather than "coins". A 4 client in a 5 room would draw nobody's pot,
## see coins that no longer exist and disagree about the score.
## SPEC 128: 6, not 5. The car-state packet grew a field (the body's component damage) and the position
## of the timestamp after it moved with it, so a 0.12.6 client and a 0.12.7 one read each other's
## packets differently. Two builds that disagree about the wire format must not be allowed to meet.
## SPEC 140: 8 -- the arena's RPCs went, which renumbered the rest.
## 9 -- the Switchback is gone. A room's track is an id both ends must know: an older build could pick
## it, and a newer one would quietly fall back to another circuit and race a different track.
const PROTOCOL := 9
const CHAT_EVERY := 0.5                # s between chat lines from one player
const CHAT_MAX := 120                  # characters per line
const CHAT_KEEP := 50                  # lines a client keeps
const COUNTDOWN := 5.0                 # s from the leader's START to the race
## The STANDING rooms a dedicated server always has (made at start, emptied -- never closed -- when the
## last player leaves), first in the room list in this order. Player-made rooms live beside them.
const STANDING_ROOMS := [
	{"name": "Race 3", "max": 3},
	{"name": "Race 5", "max": 5},
	{"name": "Race 6", "max": 6},
]
## The server-wide LEADERBOARD: points per finishing place in an online race (1st .. 5th; 1 from 6th
## on; nothing for leaving before the flag), kept by player NAME in `leaderboard_path` on the server.
const POINTS := [10, 7, 5, 3, 2]
const LEADERBOARD_PATH := "user://leaderboard.cfg"
const LEADERBOARD_ROWS := 100          # rows a client is sent
const CODE_LENGTH := 6
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # no 0/O, 1/I
const MIN_ROOM_PLAYERS := 2
const PING_EVERY := 2.0
const REJOIN_WINDOW := 30.0            # s a dropped player keeps its seat / keeps trying to reconnect
const RECONNECT_EVERY := 3.0
const HEARTBEAT_EVERY := 30.0
const MAX_PEERS := 96                  # a dedicated server's player limit (all rooms together)
const STATUS_EVERY := 10.0             # s between rewrites of the status file

signal servers_changed()

var mode: int = Mode.OFFLINE
var status: String = ""
## "host" or "dedicated": what the server we are connected to is (clients learn it in _welcome).
var server_kind: String = ""
## My room: its players (peer id -> {"name", "car", "color"}) and its setup + name + leader + state.
var players: Dictionary = {}
var lobby: Dictionary = {"track": "circle", "laps": 10, "rivals": 0, "level": "medium", "leader": 1, "name": ""}
var room_id: int = -1
## The room list (a dedicated server's browser): [{"id", "name", "players", "max", "track", "state"}].
var rooms_list: Array = []
## The race my room is running: {"track", "laps", "entries": [...], "seed", "room"} (see start_race).
var race_setup: Dictionary = {}
## My own race scene while a race is on.
var race: Node = null
## My room's chat, oldest first: [{"name", "text", "color": Color}] -- the last CHAT_KEEP lines.
var chat_lines: Array = []
## When my room's countdown reaches zero, on this machine's clock (s; -1 = no countdown).
var countdown_end: float = -1.0
## The server's leaderboard as last sent: [{"name", "points", "races", "wins"}], best first.
var leaderboard: Array = []
## What the server scored my last race: {"points", "total", "rank"} ({} until it does).
var last_award: Dictionary = {}
## Command-line test bots.
var bot: bool = false
var bot_wait_players: int = 2
var bot_room: String = "Bots"

# --- server state ---
var _rooms: Dictionary = {}            # room id -> room
var _peer_room: Dictionary = {}        # peer id -> room id
var _profiles: Dictionary = {}         # peer id -> {"name", "car", "color"}
var _next_room: int = 1
var _cli_setup: Dictionary = {}        # --track / --laps / --rivals for new rooms
var _chat_last: Dictionary = {}        # peer id -> ms of its last chat line (the rate limit)
var _board: Dictionary = {}            # the leaderboard: name -> {"points", "races", "wins"}
var leaderboard_path: String = LEADERBOARD_PATH
var _peer: WebSocketMultiplayerPeer = null

# --- SPEC 43 ---
## Round trip to the server, ms (-1 = not measured yet).
var ping_ms: int = -1
## What the server we joined told us about itself: {"name", "motd", "protocol", "version"}.
var server_info: Dictionary = {}
## The server directory's list: [{"name", "url", "players", "rooms", "max", "version", "motd"}].
var servers_list: Array = []
var servers_status: String = ""
## The address we connected to, for reconnecting.
var last_address: String = ""
var reconnecting: bool = false
## SPEC 125: why the last attempt to join a room was refused ("" = nothing has been). Read by the lobby
## so the message lands beside the control that caused it.
var last_room_error: String = ""
var _reconnect_left: float = 0.0
var _reconnect_timer: float = 0.0
var _leaving: bool = false             # an intentional leave: no reconnect
var _ping_timer: float = 0.0
# Dedicated server configuration (command line or RR_* environment variables).
var server_name: String = "Rope Racers server"
var server_motd: String = ""
var public_url: String = ""
var register_url: String = ""
var register_key: String = ""
var max_rooms: int = MAX_ROOMS
var max_peers: int = MAX_PEERS
var _seats: Dictionary = {}            # token -> {"until", "room": snapshot of the room}
var _peer_token: Dictionary = {}       # peer id -> token
var _heartbeat_timer: float = 5.0
## A JSON file the server keeps up to date with its own entry for the server list (SPEC 43b): nginx
## serves it as /api/servers, so one Docker box needs no directory service at all.
var status_file: String = ""
var _status_timer: float = 1.0
var _heartbeat: HTTPRequest = null
var _directory: HTTPRequest = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)
	_parse_command_line.call_deferred()


# ---------------------------------------------------------------- command line

func _parse_command_line() -> void:
	var args := OS.get_cmdline_user_args()
	var port := DEFAULT_PORT
	var want_server := false
	var want_host := false
	var join_ip := ""
	var i := 0
	while i < args.size():
		var nxt := args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--server":
				want_server = true
			"--host":
				want_host = true
			"--join":
				join_ip = nxt
				i += 1
			"--port":
				port = int(nxt)
				i += 1
			"--bot":
				bot = true
			"--players":
				bot_wait_players = int(nxt)
				i += 1
			"--room":
				bot_room = nxt
				i += 1
			"--track":
				_cli_setup["track"] = TrackRegistry.resolve(nxt)
				i += 1
			"--laps":
				_cli_setup["laps"] = clampi(int(nxt), 1, 20)
				i += 1
			"--rivals":
				_cli_setup["rivals"] = clampi(int(nxt), 0, GameState.MAX_OPPONENTS)
				i += 1
			"--name":
				GameState.settings["player_name"] = GameState.sanitize_name(nxt)
				server_name = _clean_room_name(nxt)
				i += 1
			"--motd":
				server_motd = nxt.substr(0, 120)
				i += 1
			"--public-url":
				public_url = nxt
				i += 1
			"--register-url":
				register_url = nxt
				i += 1
			"--register-key":
				register_key = nxt
				i += 1
			"--max-rooms":
				max_rooms = clampi(int(nxt), 1, 256)
				i += 1
			"--max-players":
				max_peers = clampi(int(nxt), 2, 1000)
				i += 1
			"--status-file":
				status_file = nxt
				i += 1
		i += 1
	# The same settings from the environment (Docker): RR_NAME, RR_MOTD, RR_PORT, RR_PUBLIC_URL,
	# RR_REGISTER_URL, RR_REGISTER_KEY, RR_MAX_ROOMS, RR_MAX_PLAYERS. The command line wins.
	if OS.get_environment("RR_SERVER") == "1":
		want_server = true
	if OS.get_environment("RR_PORT") != "" and not args.has("--port"):
		port = int(OS.get_environment("RR_PORT"))
	if OS.get_environment("RR_NAME") != "" and not args.has("--name"):
		server_name = _clean_room_name(OS.get_environment("RR_NAME"))
	if OS.get_environment("RR_MOTD") != "" and not args.has("--motd"):
		server_motd = OS.get_environment("RR_MOTD").substr(0, 120)
	if OS.get_environment("RR_PUBLIC_URL") != "" and public_url == "":
		public_url = OS.get_environment("RR_PUBLIC_URL")
	if OS.get_environment("RR_REGISTER_URL") != "" and register_url == "":
		register_url = OS.get_environment("RR_REGISTER_URL")
	if OS.get_environment("RR_REGISTER_KEY") != "" and register_key == "":
		register_key = OS.get_environment("RR_REGISTER_KEY")
	if OS.get_environment("RR_MAX_ROOMS") != "" and not args.has("--max-rooms"):
		max_rooms = clampi(int(OS.get_environment("RR_MAX_ROOMS")), 1, 256)
	if OS.get_environment("RR_STATUS_FILE") != "" and status_file == "":
		status_file = OS.get_environment("RR_STATUS_FILE")
	if OS.get_environment("RR_MAX_PLAYERS") != "" and not args.has("--max-players"):
		max_peers = clampi(int(OS.get_environment("RR_MAX_PLAYERS")), 2, 1000)
	if want_server:
		start_dedicated(port)
	elif want_host:
		host(port)
		GameState.go_to_lobby()
	elif join_ip != "":
		join(join_ip, port)
		GameState.go_to_lobby()


# ---------------------------------------------------------------- connection

func is_online() -> bool:
	return mode != Mode.OFFLINE


## SPEC 122: the socket is open but the handshake is not finished -- `mode` goes to CLIENT the moment
## `join()` is called, so `is_online()` is already true while there is still nothing to show. The lobby
## puts its CONNECTING card up on this rather than leaving the screen blank.
func is_connecting() -> bool:
	return mode == Mode.CLIENT and (_peer == null
			or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED)


func is_server() -> bool:
	return mode == Mode.HOST or mode == Mode.DEDICATED


func local_id() -> int:
	return multiplayer.get_unique_id() if is_online() and multiplayer.multiplayer_peer != null else 1


func is_leader() -> bool:
	return is_online() and room_id >= 0 and int(lobby.get("leader", -1)) == local_id()


func in_room() -> bool:
	return room_id >= 0


func host(port: int = DEFAULT_PORT) -> int:
	leave()
	_peer = WebSocketMultiplayerPeer.new()
	var err := _peer.create_server(port)
	if err != OK:
		_set_status("Could not host on port %d (error %d) -- is it already in use?" % [port, err])
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	mode = Mode.HOST
	server_kind = "host"
	_profiles[1] = _my_player_info()
	var id := _create_room_internal("%s's game" % GameState.get_player_name(), 1)
	_join_room_internal(1, id)
	_set_status("Hosting on port %d. Friends join with your IP address." % port)
	return OK


func start_dedicated(port: int = DEFAULT_PORT) -> int:
	leave()
	_leaving = false
	_peer = WebSocketMultiplayerPeer.new()
	var err := _peer.create_server(port)
	if err != OK:
		print("Rope Racers dedicated server: could not listen on port %d (error %d)" % [port, err])
		get_tree().quit(1)
		return err
	multiplayer.multiplayer_peer = _peer
	mode = Mode.DEDICATED
	server_kind = "dedicated"
	load_leaderboard()
	_create_standing_rooms()
	_set_status("Dedicated server on port %d" % port)
	print("Rope Racers dedicated server \"%s\" (%s, protocol %d) listening on port %d" % [
			server_name, Version.label(), PROTOCOL, port])
	if register_url != "":
		print("  announcing itself to %s as %s" % [register_url, public_url if public_url != "" else "(no --public-url!)"])
	GameState.go_to_lobby()
	return OK


func join(ip: String, port: int = DEFAULT_PORT) -> int:
	var keep_reconnect := reconnecting
	leave()
	reconnecting = keep_reconnect
	_leaving = false
	_peer = WebSocketMultiplayerPeer.new()
	var address := server_address(ip, port)
	last_address = address
	var err := _peer.create_client(address)
	if err != OK:
		_set_status("Could not connect to %s (error %d)" % [address, err])
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	mode = Mode.CLIENT
	ping_ms = -1
	if not reconnecting:
		_set_status("Connecting to %s ..." % display_address(address))
	lobby_changed.emit()
	return OK


## Connects to the official server.
func join_official() -> int:
	return join(OFFICIAL_URL)


## "host", "host:port", "ws://..." or "wss://..." -> a WebSocket URL.
static func server_address(ip: String, port: int = DEFAULT_PORT) -> String:
	var a := ip.strip_edges()
	if a.begins_with("ws://") or a.begins_with("wss://"):
		return a
	if a.contains(":") and not a.contains("]"):
		return "ws://%s" % a
	return "ws://%s:%d" % [a, port]


## A URL for people: "rope.thenakedcat.games" for the official server, else host:port.
static func display_address(url: String) -> String:
	if url == OFFICIAL_URL:
		return OFFICIAL_NAME
	return url.replace("wss://", "").replace("ws://", "").trim_suffix("/ws")


func leave() -> void:
	_leaving = true
	reconnecting = false
	for r in _rooms.values():
		_free_room_race(r)
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE
	server_kind = ""
	players.clear()
	room_id = -1
	rooms_list.clear()
	race_setup = {}
	race = null
	chat_lines.clear()
	countdown_end = -1.0
	leaderboard.clear()
	last_award = {}
	_rooms.clear()
	_peer_room.clear()
	_profiles.clear()
	_peer_token.clear()
	_seats.clear()
	_chat_last.clear()
	_board.clear()
	_next_room = 1
	ping_ms = -1
	server_info = {}
	lobby_changed.emit()
	rooms_changed.emit()


## SPEC 73: what the room is told I drive. `owned_car` is the guard: a player browsing the car screen
## from a room moves `selected_car` around freely, and none of that reaches the others unless it is bought.
func _my_player_info() -> Dictionary:
	var car := GameState.owned_car()
	return {"name": GameState.get_player_name(), "car": car,
			"color": GameState.selected_color if car == GameState.selected_car else 0}


## A token that stays the same for this installation: how a server knows a reconnecting player.
func _my_token() -> String:
	var t := String(GameState.settings.get("player_token", ""))
	if t.length() < 16:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		t = ""
		for k in 24:
			t += "0123456789abcdef"[rng.randi_range(0, 15)]
		GameState.settings["player_token"] = t
		# A command-line bot (--bot --name X) must never write its name into the player's settings.
		if not bot and not OS.get_cmdline_user_args().has("--name"):
			GameState.save_settings()
	return t


func _set_status(t: String) -> void:
	status = t
	status_changed.emit(t)
	_log(t)


## Progress lines for bots and the dedicated server (their only UI is the console).
func _log(t: String) -> void:
	if bot or mode == Mode.DEDICATED:
		print("[net %s] %s" % [["offline", "host", "client", "server"][mode], t])


func _on_connected() -> void:
	_set_status("Connected." if not reconnecting else "Reconnected.")
	reconnecting = false
	var me := _my_player_info()
	_register.rpc_id(1, me["name"], me["car"], me["color"], PROTOCOL, _my_token())


func _on_connection_failed() -> void:
	if reconnecting:
		_drop_peer_only()
		return
	var where := display_address(last_address)
	leave()
	var msg := "Could not reach %s -- the server may be offline, or the address is wrong." % where
	_set_status(msg)
	disconnected.emit(msg)


func _on_server_gone() -> void:
	var was_racing := race != null
	if not _leaving and last_address != "" and server_kind == "dedicated":
		# Dropped, not closed: keep trying for REJOIN_WINDOW s; the server keeps our seat.
		_drop_peer_only()
		reconnecting = true
		_reconnect_left = REJOIN_WINDOW
		_reconnect_timer = 0.5
		_set_status("Connection lost -- reconnecting ...")
		if was_racing:
			GameState.go_to_lobby()
		lobby_changed.emit()
		return
	leave()
	_set_status("The server closed the connection.")
	disconnected.emit("The server closed the connection.")
	if was_racing:
		GameState.go_to_lobby()


## Forget the socket but keep who we were connected to (for reconnecting).
func _drop_peer_only() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE
	players.clear()
	room_id = -1
	race = null
	countdown_end = -1.0
	ping_ms = -1


func _process(delta: float) -> void:
	if is_server():
		_tick_countdowns(Time.get_ticks_msec())
	if reconnecting and mode == Mode.OFFLINE:
		_reconnect_left -= delta
		_reconnect_timer -= delta
		if _reconnect_left <= 0.0:
			reconnecting = false
			last_address = ""
			_set_status("Could not reconnect -- the server is gone.")
			disconnected.emit("Could not reconnect -- the server is gone.")
		elif _reconnect_timer <= 0.0:
			_reconnect_timer = RECONNECT_EVERY
			_set_status("Connection lost -- reconnecting (%d s) ..." % int(ceil(_reconnect_left)))
			join(last_address)
	if mode == Mode.CLIENT and multiplayer.multiplayer_peer != null \
			and _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_ping_timer = PING_EVERY
			_ping.rpc_id(1, Time.get_ticks_msec())
	if mode == Mode.DEDICATED:
		var now := Time.get_ticks_msec() / 1000.0
		for t in _seats.keys():
			if float(_seats[t]["until"]) < now:
				_seats.erase(t)
		if status_file != "":
			_status_timer -= delta
			if _status_timer <= 0.0:
				_status_timer = STATUS_EVERY
				write_status_file()
		if register_url != "" and register_key != "":
			_heartbeat_timer -= delta
			if _heartbeat_timer <= 0.0:
				_heartbeat_timer = HEARTBEAT_EVERY
				_send_heartbeat()


func _on_peer_disconnected(id: int) -> void:
	if not is_server():
		return
	# Keep the seat for a player who may reconnect: its room as it was (SPEC 43).
	if mode == Mode.DEDICATED and _peer_token.has(id) and _peer_room.has(id):
		var rid := int(_peer_room[id])
		if _rooms.has(rid):
			var r: Dictionary = _rooms[rid]
			_seats[String(_peer_token[id])] = {"until": Time.get_ticks_msec() / 1000.0 + REJOIN_WINDOW,
					"room": {"id": rid, "name": r["name"], "code": r["code"], "public": r["public"],
					"password": r["password"], "max": r["max"], "setup": (r["setup"] as Dictionary).duplicate()}}
	_leave_room_internal(id)
	_profiles.erase(id)
	_peer_token.erase(id)
	_chat_last.erase(id)
	_broadcast_rooms()


# ---------------------------------------------------------------- server: rooms

func _create_room_internal(name: String, leader: int, public: bool = true, password: String = "",
		max_players: int = MAX_PLAYERS, code: String = "") -> int:
	var id := _next_room
	_next_room += 1
	var clean := _clean_room_name(name)
	if clean == "":
		clean = "Room %d" % id
	var setup := _default_setup()
	if code == "" or _room_by_code(code) >= 0:
		code = _new_code()
	# SPEC 65: `wins` is the room's own scoreboard -- how many races each player (by name) has won
	# since the room was made. It is part of the lobby state, so every client sees the same table.
	# `state`: "lobby" -> "countdown" (the leader pressed START; `start_at` is the server's clock, ms, when
	# the race starts) -> "racing" -> "lobby".
	_rooms[id] = {"id": id, "name": clean, "leader": leader, "players": [], "setup": setup, "wins": {},
			"state": "lobby", "start_at": 0, "race_setup": {}, "loaded": {}, "results": [], "over_sent": false,
			"counting": false, "race": null, "public": public, "password": _clean_password(password),
			"max": clampi(max_players, MIN_ROOM_PLAYERS, MAX_PLAYERS), "code": code, "standing": false}
	_log("room %d \"%s\" [%s] created (%s%s)" % [id, clean, code, "public" if public else "private",
			", password" if password != "" else ""])
	return id


## A new room's race, with the command line's --track / --laps / --rivals on top.
func _default_setup() -> Dictionary:
	var setup := {"track": "circle", "laps": 10, "rivals": 2, "level": "medium"}
	setup.merge(_cli_setup, true)
	return setup


## Dedicated server: the STANDING_ROOMS, in their order (the first room ids, so the list keeps it).
func _create_standing_rooms() -> void:
	for s in STANDING_ROOMS:
		var id := _create_room_internal(String(s["name"]), 0, true, "", int(s["max"]))
		var r: Dictionary = _rooms[id]
		r["standing"] = true


## A standing room is never closed: when its last player leaves it is made new again -- its race
## setup, scoreboard and leader reset; its name and size are what they always were.
func _reset_standing_room(r: Dictionary) -> void:
	_free_room_race(r)
	r["setup"] = _default_setup()
	r["players"] = []
	r["leader"] = 0
	r["state"] = "lobby"
	r["start_at"] = 0
	r["race_setup"] = {}
	r["loaded"] = {}
	r["results"] = []
	r["over_sent"] = false
	r["counting"] = false
	r["wins"] = {}
	r["public"] = true
	r["password"] = ""


## Is room `id` one of the standing rooms?
func is_standing_room(id: int) -> bool:
	return _rooms.has(id) and bool(_rooms[id].get("standing", false))


## A fresh room code no room is using: 6 characters, no look-alikes.
func _new_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	while true:
		var c := ""
		for k in CODE_LENGTH:
			c += CODE_CHARS[rng.randi_range(0, CODE_CHARS.length() - 1)]
		if _room_by_code(c) < 0:
			return c
	return ""


func _room_by_code(code: String) -> int:
	var want := code.strip_edges().to_upper()
	for id in _rooms.keys():
		if String(_rooms[id]["code"]) == want:
			return int(id)
	return -1


static func _clean_password(pw: String) -> String:
	return pw.strip_edges().substr(0, 24)


## Printable, trimmed, at most 28 characters (room names are longer than player names).
static func _clean_room_name(n: String) -> String:
	var out := ""
	for ch in n.strip_edges():
		if ch.unicode_at(0) >= 32 and ch != "[" and ch != "]":
			out += ch
	return out.substr(0, 28).strip_edges()


## `password` must match a locked room's; `by_code` is how a private room is reached (it is not listed).
func _join_room_internal(peer: int, id: int, password: String = "", by_code: bool = true) -> String:
	if not _rooms.has(id):
		return "That room no longer exists."
	var r: Dictionary = _rooms[id]
	if not bool(r.get("public", true)) and not by_code:
		return "That room is private -- you need its code."
	if String(r.get("password", "")) != "" and _clean_password(password) != String(r["password"]):
		return "Wrong password for that room." if password != "" else "That room needs a password."
	if String(r["state"]) == "racing":
		return "That room is racing -- wait for the race to end."
	if String(r["state"]) == "countdown":
		return "That room is about to start its race -- wait for it to end."
	if (r["players"] as Array).size() >= int(r.get("max", MAX_PLAYERS)):
		return "That room is full."
	_leave_room_internal(peer)
	(r["players"] as Array).append(peer)
	_peer_room[peer] = id
	if int(r["leader"]) <= 0 or not (r["players"] as Array).has(int(r["leader"])):
		r["leader"] = peer
	_log("peer %d joined room %d (%d players)" % [peer, id, (r["players"] as Array).size()])
	_sync_room(id)
	_broadcast_rooms()
	if bot and (r["players"] as Array).size() >= bot_wait_players:
		start_race(id)
	return ""


func _leave_room_internal(peer: int) -> void:
	if not _peer_room.has(peer):
		return
	var id := int(_peer_room[peer])
	_peer_room.erase(peer)
	if not _rooms.has(id):
		return
	var r: Dictionary = _rooms[id]
	(r["players"] as Array).erase(peer)
	(r["loaded"] as Dictionary).erase(peer)
	if String(r["state"]) == "racing":
		var node := _race_node(id)
		if node != null:
			node.net_peer_left(peer)
		for p in r["players"]:
			if int(p) != local_id():
				if _sendable(int(p)):
					_net_peer_left.rpc_id(int(p), peer)
		_check_race_over(id)
	if (r["players"] as Array).is_empty():
		if bool(r.get("standing", false)):
			_reset_standing_room(r)
			_log("room %d \"%s\" emptied -- made new" % [id, String(r["name"])])
		else:
			_free_room_race(r)
			_rooms.erase(id)
			_log("room %d closed (empty)" % id)
	else:
		if int(r["leader"]) == peer:
			r["leader"] = int((r["players"] as Array)[0])
		_sync_room(id)
	_broadcast_rooms()


func _free_room_race(r: Dictionary) -> void:
	if mode != Mode.DEDICATED:
		r["race"] = null
		return
	var node = r.get("race")
	if node != null and is_instance_valid(node):
		node.queue_free()
	r["race"] = null


func _room_view(id: int) -> Dictionary:
	var r: Dictionary = _rooms[id]
	var ps := {}
	for p in r["players"]:
		ps[int(p)] = _profiles.get(int(p), {"name": "Player", "car": "sport", "color": 0})
	var l: Dictionary = (r["setup"] as Dictionary).duplicate()
	l["leader"] = int(r["leader"])
	l["name"] = String(r["name"])
	l["state"] = String(r["state"])
	l["code"] = String(r.get("code", ""))
	l["public"] = bool(r.get("public", true))
	l["locked"] = String(r.get("password", "")) != ""
	l["max"] = int(r.get("max", MAX_PLAYERS))
	l["standing"] = bool(r.get("standing", false))   # its size and openness are fixed
	l["wins"] = (r.get("wins", {}) as Dictionary).duplicate()   # SPEC 65: the room's scoreboard
	# The countdown as seconds LEFT (every machine has its own clock; the server's start_at means nothing
	# to a client): a client counts down from what it is told, and the server starts the race at zero.
	l["countdown"] = maxf((int(r.get("start_at", 0)) - Time.get_ticks_msec()) / 1000.0, 0.0) \
			if String(r["state"]) == "countdown" else 0.0
	return {"id": id, "players": ps, "lobby": l}


## Sends room `id` to everyone in it (and updates the host's own mirror).
func _sync_room(id: int) -> void:
	if not _rooms.has(id):
		return
	var view := _room_view(id)
	for p in _rooms[id]["players"]:
		if int(p) == local_id() and mode == Mode.HOST:
			_apply_room_view(view)
		else:
			if _sendable(int(p)):
				_room_state.rpc_id(int(p), view)


func _rooms_view() -> Array:
	var out: Array = []
	var ids := _rooms.keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = _rooms[id]
		if not bool(r.get("public", true)):
			continue                               # private rooms are reached by their code only
		var st: Dictionary = r["setup"]
		var where := TrackRegistry.get_short_name(String(st["track"]))
		out.append({"id": int(id), "name": String(r["name"]), "players": (r["players"] as Array).size(),
				"max": int(r.get("max", MAX_PLAYERS)), "track": where,
				"state": String(r["state"]), "locked": String(r.get("password", "")) != ""})
	return out


func _broadcast_rooms() -> void:
	if mode != Mode.DEDICATED:
		return
	var view := _rooms_view()
	rooms_list = view
	rooms_changed.emit()
	for p in multiplayer.get_peers():
		if _is_open(p):
			_room_list.rpc_id(p, view)


## SPEC 128: is this seat somebody the server can actually send to? A seat is a NUMBER in a room's
## player list; a peer is a socket. They come apart whenever somebody drops -- their seat is held for
## `REJOIN_WINDOW` while their socket is already gone -- and `rpc_id` to a peer that is not connected is
## an engine error, not a delivery. Every broadcast loop asks this first now.
##
## It is also what made the suite's network fixtures print fifty-seven "Attempt to call RPC with unknown
## peer ID" errors: they seat fabricated players that were never connected, which is exactly the state a
## dropped player leaves behind, so the guard the fixtures needed is the guard production needed.
func _sendable(peer: int) -> bool:
	return peer != local_id() and _is_open(peer)


## A peer whose connection is still open (one that is closing, or already gone, must not be sent to).
func _is_open(peer: int) -> bool:
	if _peer == null or multiplayer.multiplayer_peer == null or not multiplayer.get_peers().has(peer):
		return false
	var ws := _peer.get_peer(peer)
	return ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN


# ---------------------------------------------------------------- client <-> server: lobby

@rpc("any_peer", "reliable")
func _register(name: String, car: String, color: int, protocol: int = 0, token: String = "") -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var refuse := register_refusal(protocol, _profiles.size())
	if refuse != "":
		_log("refused peer %d: %s" % [id, refuse])
		_refused.rpc_id(id, refuse)
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if _peer != null:
				_peer.disconnect_peer(id))
		return
	_profiles[id] = {"name": GameState.sanitize_name(name), "car": CarRegistry.resolve(car),
			"color": clampi(color, 0, CarRegistry.PALETTE_SIZE - 1)}
	_peer_token[id] = token.substr(0, 40)
	_log("player %d connected as %s" % [id, _profiles[id]["name"]])
	_welcome.rpc_id(id, server_kind, {"name": server_name if mode == Mode.DEDICATED else "%s's game" %
			GameState.get_player_name(), "motd": server_motd, "protocol": PROTOCOL,
			"version": Version.number()})
	if mode == Mode.HOST:
		var room: int = int(_rooms.keys()[0]) if not _rooms.is_empty() else -1
		var err := _join_room_internal(id, room)
		if err != "":
			_room_error.rpc_id(id, err)
		return
	_leaderboard.rpc_id(id, leaderboard_rows(LEADERBOARD_ROWS))
	# Back within REJOIN_WINDOW s of dropping out: the same room (recreated if it emptied meanwhile).
	var seat_room := _reseat(id, token)
	if seat_room >= 0:
		_room_error.rpc_id(id, "Welcome back -- you are in your room again.")
		return
	_room_list.rpc_id(id, _rooms_view())


## Why a player may not connect ("" = welcome): an old / new game version, or a full server.
func register_refusal(protocol: int, connected: int) -> String:
	if protocol != PROTOCOL:
		return "This server runs a different version of the game (protocol %d, yours is %d) -- update the game." % [
				PROTOCOL, protocol]
	if mode == Mode.DEDICATED and connected >= max_peers:
		return "The server is full (%d players) -- try again in a moment." % max_peers
	return ""


## Puts a reconnecting player back in its room; returns the room id, or -1.
func _reseat(peer: int, token: String) -> int:
	if token == "" or not _seats.has(token):
		return -1
	var seat: Dictionary = _seats[token]
	_seats.erase(token)
	if float(seat["until"]) < Time.get_ticks_msec() / 1000.0:
		return -1
	var snap: Dictionary = seat["room"]
	var id := int(snap["id"])
	if not _rooms.has(id) or String(_rooms[id]["code"]) != String(snap["code"]):
		if _rooms.size() >= max_rooms:
			return -1
		id = _create_room_internal(String(snap["name"]), peer, bool(snap["public"]), String(snap["password"]),
				int(snap["max"]), String(snap["code"]))
		_rooms[id]["setup"] = (snap["setup"] as Dictionary).duplicate()
	if _join_room_internal(peer, id, String(snap["password"]), true) != "":
		return -1
	return id


@rpc("authority", "reliable")
func _welcome(kind: String, info: Dictionary = {}) -> void:
	server_kind = kind
	server_info = info
	_log("the server is a %s server" % kind)
	lobby_changed.emit()


@rpc("authority", "reliable")
func _refused(msg: String) -> void:
	last_address = ""
	reconnecting = false
	_leaving = true
	_set_status(msg)
	disconnected.emit(msg)


@rpc("any_peer", "unreliable")
func _ping(t: int) -> void:
	if is_server():
		_pong.rpc_id(multiplayer.get_remote_sender_id(), t)


@rpc("authority", "unreliable")
func _pong(t: int) -> void:
	ping_ms = maxi(Time.get_ticks_msec() - t, 0)
	lobby_changed.emit()


@rpc("authority", "reliable")
func _room_list(list: Array) -> void:
	rooms_list = list
	rooms_changed.emit()
	if bot and room_id < 0 and server_kind == "dedicated":
		for r in list:
			if String(r["name"]) == bot_room and String(r["state"]) == "lobby":
				join_room(int(r["id"]))
				return
		create_room(bot_room)


@rpc("authority", "reliable")
func _room_state(view: Dictionary) -> void:
	_apply_room_view(view)


func _apply_room_view(view: Dictionary) -> void:
	if int(view["id"]) != room_id:
		chat_lines.clear()                 # another room: its chat is not this one's
	room_id = int(view["id"])
	players = view["players"]
	lobby = view["lobby"]
	if String(lobby.get("state", "lobby")) == "countdown":
		countdown_end = Time.get_ticks_msec() / 1000.0 + float(lobby.get("countdown", 0.0))
	else:
		countdown_end = -1.0
	lobby_changed.emit()


## Seconds until my room's race starts: -1 when no countdown is on.
func countdown_left() -> float:
	if room_id < 0 or countdown_end < 0.0 or String(lobby.get("state", "lobby")) != "countdown":
		return -1.0
	return maxf(countdown_end - Time.get_ticks_msec() / 1000.0, 0.0)


@rpc("authority", "reliable")
func _room_error(msg: String) -> void:
	_set_status(msg)
	# SPEC 125: a room refusal is news for the dialog that caused it, not only for the status strip at
	# the bottom of the screen. The lobby keeps its password popup open on this and says so inside it.
	last_room_error = msg
	room_refused.emit(msg)
	lobby_changed.emit()


## Creates a room (on a dedicated server) and goes in: public (listed) or private (code only), with an
## optional password and a player limit.
func create_room(name: String, public: bool = true, password: String = "", max_players: int = MAX_PLAYERS) -> void:
	if mode == Mode.CLIENT:
		_create_room.rpc_id(1, name, public, password, max_players)


@rpc("any_peer", "reliable")
func _create_room(name: String, public: bool = true, password: String = "", max_players: int = MAX_PLAYERS) -> void:
	if mode != Mode.DEDICATED:
		return
	var id := multiplayer.get_remote_sender_id()
	if _rooms.size() >= max_rooms:
		_room_error.rpc_id(id, "The server has no space for another room -- join one instead.")
		return
	_join_room_internal(id, _create_room_internal(name, id, public, password, max_players), password, true)


## Joins a listed room (a locked one needs `password`).
func join_room(id: int, password: String = "") -> void:
	if mode == Mode.CLIENT:
		_join_room.rpc_id(1, id, password)


@rpc("any_peer", "reliable")
func _join_room(id: int, password: String = "") -> void:
	if mode != Mode.DEDICATED:
		return
	var peer := multiplayer.get_remote_sender_id()
	var err := _join_room_internal(peer, id, password, false)
	if err != "":
		_room_error.rpc_id(peer, err)


## Joins a room by its code -- public or private.
func join_code(code: String, password: String = "") -> void:
	if mode == Mode.CLIENT:
		_join_code.rpc_id(1, code, password)


@rpc("any_peer", "reliable")
func _join_code(code: String, password: String = "") -> void:
	if mode != Mode.DEDICATED:
		return
	var peer := multiplayer.get_remote_sender_id()
	var id := _room_by_code(code)
	var err := "No room has the code %s." % code.strip_edges().to_upper() if id < 0 \
			else _join_room_internal(peer, id, password, true)
	if err != "":
		_room_error.rpc_id(peer, err)


## Quick join: the busiest public room without a password that still has space, or a new one.
func quick_join() -> void:
	if mode == Mode.CLIENT:
		_quick_join.rpc_id(1)


@rpc("any_peer", "reliable")
func _quick_join() -> void:
	if mode != Mode.DEDICATED:
		return
	var peer := multiplayer.get_remote_sender_id()
	var id := quick_join_target()
	if id < 0:
		if _rooms.size() >= max_rooms:
			_room_error.rpc_id(peer, "Every room is busy and the server has no space for another.")
			return
		var nm := "%s's room" % String(_profiles.get(peer, {"name": "Player"})["name"])
		id = _create_room_internal(nm, peer)
	var err := _join_room_internal(peer, id, "", false)
	if err != "":
		_room_error.rpc_id(peer, err)


## Server: the room quick join would put a player in (-1 = none fits).
func quick_join_target() -> int:
	var best := -1
	var best_n := -1
	for id in _rooms.keys():
		var r: Dictionary = _rooms[id]
		var n := (r["players"] as Array).size()
		if bool(r["public"]) and String(r["password"]) == "" and String(r["state"]) == "lobby" \
				and n < int(r["max"]) and n > best_n:
			best = int(id)
			best_n = n
	return best


## The leader removes a player from the room (back to the room list).
func kick(peer: int) -> void:
	if is_server():
		_kick_internal(local_id(), peer)
	else:
		_kick.rpc_id(1, peer)


@rpc("any_peer", "reliable")
func _kick(peer: int) -> void:
	if is_server():
		_kick_internal(multiplayer.get_remote_sender_id(), peer)


func _kick_internal(from: int, peer: int) -> bool:
	if from == peer or not _peer_room.has(from) or not _peer_room.has(peer):
		return false
	var id := int(_peer_room[from])
	if int(_peer_room[peer]) != id or int(_rooms[id]["leader"]) != from or String(_rooms[id]["state"]) != "lobby":
		return false
	_leave_room_internal(peer)
	if mode == Mode.DEDICATED and _is_open(peer):
		_room_error.rpc_id(peer, "The leader removed you from the room.")
		_room_list.rpc_id(peer, _rooms_view())
	elif mode == Mode.HOST and _peer != null:
		_refused.rpc_id(peer, "The host removed you from the game.")
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if _peer != null:
				_peer.disconnect_peer(peer))
	_log("peer %d kicked from room %d" % [peer, id])
	return true


## Back to the room list (dedicated server), or out of the game (anywhere else).
func leave_room() -> void:
	if mode == Mode.CLIENT and server_kind == "dedicated" and room_id >= 0:
		_leave_room.rpc_id(1)
		room_id = -1
		players.clear()
		chat_lines.clear()
		countdown_end = -1.0
		lobby_changed.emit()
	else:
		leave()


@rpc("any_peer", "reliable")
func _leave_room() -> void:
	if mode == Mode.DEDICATED:
		var peer := multiplayer.get_remote_sender_id()
		_leave_room_internal(peer)
		_room_list.rpc_id(peer, _rooms_view())


## This player's car / colour / name changed.
func update_my_player() -> void:
	if not is_online():
		return
	var me := _my_player_info()
	if is_server():
		_profiles[local_id()] = me
		if _peer_room.has(local_id()):
			_sync_room(int(_peer_room[local_id()]))
	else:
		_update_profile.rpc_id(1, me["name"], me["car"], me["color"])


@rpc("any_peer", "reliable")
func _update_profile(name: String, car: String, color: int) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	_profiles[id] = {"name": GameState.sanitize_name(name), "car": CarRegistry.resolve(car),
			"color": clampi(color, 0, CarRegistry.PALETTE_SIZE - 1)}
	if _peer_room.has(id):
		_sync_room(int(_peer_room[id]))


# ---------------------------------------------------------------- lobby chat

## A line from me to everyone in my room (the server relays it back to me too, in order).
func send_chat(text: String) -> void:
	if not is_online() or room_id < 0:
		return
	if is_server():
		_chat_internal(local_id(), text)
	else:
		_chat.rpc_id(1, text)


@rpc("any_peer", "reliable")
func _chat(text: String) -> void:
	if is_server():
		_chat_internal(multiplayer.get_remote_sender_id(), text)


## Server: peer `from`'s line goes to every player of ITS room -- trimmed to CHAT_MAX printable
## characters, at most one line per CHAT_EVERY s per peer, tagged with the sender's name and car colour.
## Returns the peers it went to ([] when the line was dropped).
func _chat_internal(from: int, text: String) -> Array:
	if not _peer_room.has(from):
		return []
	var line := clean_chat(text)
	if line == "":
		return []
	var now := Time.get_ticks_msec()
	if now - int(_chat_last.get(from, -1000000)) < int(CHAT_EVERY * 1000.0):
		return []
	_chat_last[from] = now
	var id := int(_peer_room[from])
	var info: Dictionary = _profiles.get(from, {"name": "Player", "car": "sport", "color": 0})
	_log("room %d  %s: %s" % [id, String(info["name"]), line])
	var sent: Array = []
	for p in _rooms[id]["players"]:
		if int(p) == local_id() and mode == Mode.HOST:
			_chat_line_local(String(info["name"]), line, String(info["car"]), int(info["color"]))
		else:
			if _sendable(int(p)):
				_chat_line.rpc_id(int(p), String(info["name"]), line, String(info["car"]), int(info["color"]))
		sent.append(int(p))
	return sent


@rpc("authority", "reliable")
func _chat_line(name: String, text: String, car: String, color: int) -> void:
	_chat_line_local(name, text, car, color)


func _chat_line_local(name: String, text: String, car: String, color: int) -> void:
	chat_lines.append({"name": name, "text": text, "color": CarRegistry.get_body_color(CarRegistry.resolve(car), color)})
	while chat_lines.size() > CHAT_KEEP:
		chat_lines.remove_at(0)
	chat_received.emit(name, text)


## Printable, trimmed, no bbcode brackets, at most CHAT_MAX characters.
static func clean_chat(text: String) -> String:
	var out := ""
	for ch in text.strip_edges():
		if ch.unicode_at(0) >= 32 and ch != "[" and ch != "]":
			out += ch
	return out.substr(0, CHAT_MAX).strip_edges()


# ---------------------------------------------------------------- the race setup and START

## The leader changes the room's race: any of "track", "laps", "rivals", "level".
func request_setup(changes: Dictionary) -> void:
	if is_server():
		_apply_setup(local_id(), changes)
	else:
		_request_setup.rpc_id(1, changes)


@rpc("any_peer", "reliable")
func _request_setup(changes: Dictionary) -> void:
	if is_server():
		_apply_setup(multiplayer.get_remote_sender_id(), changes)


func _apply_setup(from: int, changes: Dictionary) -> void:
	if not _peer_room.has(from):
		return
	var id := int(_peer_room[from])
	var r: Dictionary = _rooms[id]
	if from != int(r["leader"]) or String(r["state"]) != "lobby":
		return
	var st: Dictionary = r["setup"]
	if changes.has("track"):
		st["track"] = TrackRegistry.resolve(String(changes["track"]))
	if changes.has("laps"):
		st["laps"] = clampi(int(changes["laps"]), 1, 20)
	if changes.has("rivals"):
		st["rivals"] = clampi(int(changes["rivals"]), 0, GameState.MAX_OPPONENTS)
	if changes.has("level") and GameState.DIFFICULTIES.has(String(changes["level"])):
		st["level"] = String(changes["level"])
	# SPEC 140: a room is a RACE. The mode and the arena it used to carry are gone; a standing room is
	# still its size, and stays public and open.
	var standing := bool(r.get("standing", false))
	# The room itself (SPEC 43): public / private, password, player limit (never below who is in it).
	if changes.has("public") and mode == Mode.DEDICATED and not standing:
		r["public"] = bool(changes["public"])
	if changes.has("password") and mode == Mode.DEDICATED and not standing:
		r["password"] = _clean_password(String(changes["password"]))
	if changes.has("max") and not standing:
		r["max"] = clampi(int(changes["max"]), maxi(MIN_ROOM_PLAYERS, (r["players"] as Array).size()), MAX_PLAYERS)
	_sync_room(id)
	_broadcast_rooms()


## The leader presses START: the room counts down COUNTDOWN s, then the server starts the race.
func request_start() -> void:
	if is_server():
		_start_countdown(local_id())
	else:
		_request_start.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_start() -> void:
	if is_server():
		_start_countdown(multiplayer.get_remote_sender_id())


## The leader presses CANCEL during the countdown: back to the lobby, nothing starts.
func cancel_start() -> void:
	if is_server():
		_cancel_countdown(local_id())
	else:
		_request_cancel.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_cancel() -> void:
	if is_server():
		_cancel_countdown(multiplayer.get_remote_sender_id())


## Server: `from` (the leader, in the lobby) starts its room's countdown. True when it did.
func _start_countdown(from: int) -> bool:
	if not _peer_room.has(from):
		return false
	var id := int(_peer_room[from])
	var r: Dictionary = _rooms[id]
	if int(r["leader"]) != from or String(r["state"]) != "lobby" or (r["players"] as Array).is_empty():
		return false
	r["state"] = "countdown"
	r["start_at"] = Time.get_ticks_msec() + int(round(COUNTDOWN * 1000.0))
	_log("room %d counts down (%d s)" % [id, int(COUNTDOWN)])
	_sync_room(id)
	_broadcast_rooms()
	return true


## Server: `from` (the leader) stops its room's countdown. True when it did.
func _cancel_countdown(from: int) -> bool:
	if not _peer_room.has(from):
		return false
	var id := int(_peer_room[from])
	var r: Dictionary = _rooms[id]
	if int(r["leader"]) != from or String(r["state"]) != "countdown":
		return false
	r["state"] = "lobby"
	r["start_at"] = 0
	_log("room %d: the countdown was cancelled" % id)
	_sync_room(id)
	_broadcast_rooms()
	return true


## Server, every frame: a room whose countdown is over starts its race.
func _tick_countdowns(now_ms: int) -> void:
	for id in _rooms.keys():
		var r: Dictionary = _rooms[id]
		if String(r["state"]) == "countdown" and now_ms >= int(r.get("start_at", 0)):
			start_race(int(id))


# ---------------------------------------------------------------- race start

## Server: builds room `id`'s line-up (its players, then AI rivals), shuffles the grid, starts the race.
## From the lobby directly (bots, tests) or at the end of the countdown.
func start_race(id: int) -> void:
	if not is_server() or not _rooms.has(id):
		return
	var r: Dictionary = _rooms[id]
	if not (String(r["state"]) in ["lobby", "countdown"]) or (r["players"] as Array).is_empty():
		return
	var st: Dictionary = r["setup"]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var entries: Array = []
	var taken := {}
	for p in r["players"]:
		var info: Dictionary = _profiles.get(int(p), {"name": "Player", "car": "sport", "color": 0})
		entries.append({"key": entries.size(), "kind": "human", "peer": int(p), "name": String(info["name"]),
				"car": String(info["car"]), "color": int(info["color"]), "level": "", "profile": ""})
		taken["%s/%d" % [info["car"], info["color"]]] = true
	var dealt: Array = []
	for i in int(st["rivals"]):
		var car := CarRegistry.ids()[rng.randi_range(0, CarRegistry.ids().size() - 1)]
		var color := rng.randi_range(0, CarRegistry.PALETTE_SIZE - 1)
		var guard := 0
		while taken.has("%s/%d" % [car, color]) and guard < 20:
			car = CarRegistry.ids()[rng.randi_range(0, CarRegistry.ids().size() - 1)]
			color = rng.randi_range(0, CarRegistry.PALETTE_SIZE - 1)
			guard += 1
		taken["%s/%d" % [car, color]] = true
		entries.append({"key": entries.size(), "kind": "ai", "peer": 0, "name": "%s %s" % [
				CarRegistry.get_palette(car)[color]["name"], CarRegistry.get_display_name(car)],
				"car": car, "color": color, "level": String(st["level"]),
				"profile": GameState.pick_profile("random", rng, dealt)})
		dealt.append(String(entries[entries.size() - 1]["profile"]))
	var slots := range(entries.size())
	for k in range(slots.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var t = slots[k]
		slots[k] = slots[j]
		slots[j] = t
	for k in entries.size():
		entries[k]["slot"] = slots[k]
	var setup := {"track": String(st["track"]), "laps": int(st["laps"]), "entries": entries,
			"seed": rng.randi(), "room": id}
	r["race_setup"] = setup
	r["state"] = "racing"
	r["walls"] = 0                                   # SPEC 128: every route starts closed
	r["start_at"] = 0
	r["loaded"] = {}
	r["results"] = []
	r["over_sent"] = false
	r["counting"] = false
	_log("room %d starts a %d-lap race on %s with %d cars" % [id, setup["laps"], setup["track"], entries.size()])
	_sync_room(id)
	_broadcast_rooms()
	for p in r["players"]:
		if int(p) == local_id() and mode == Mode.HOST:
			_start_race_local(setup)
		else:
			if _sendable(int(p)):
				_start_race.rpc_id(int(p), setup)
	if mode == Mode.DEDICATED:
		# The server runs this room's race itself: its AI, and its results.
		var node := RACE_SCENE.instantiate()
		node.name = "RoomRace%d" % id
		node.set("net_setup", setup)
		node.set("net_room", id)
		r["race"] = node
		add_child(node)


@rpc("authority", "reliable")
func _start_race(setup: Dictionary) -> void:
	_start_race_local(setup)


func _start_race_local(setup: Dictionary) -> void:
	race_setup = setup
	last_award = {}
	GameState.selected_track = String(setup["track"])
	GameState.go_to_race_scene()


## A race node registers itself (the local player's scene, or a dedicated room's).
func register_race(node: Node, room: int) -> void:
	if mode == Mode.DEDICATED:
		if _rooms.has(room):
			_rooms[room]["race"] = node
	else:
		race = node


func unregister_race(node: Node) -> void:
	if race == node:
		race = null


func _race_node(room: int) -> Node:
	if mode == Mode.DEDICATED:
		if _rooms.has(room):
			var n = _rooms[room]["race"]
			return n if n != null and is_instance_valid(n) else null
		return null
	return race if room == room_id else null


## A race scene is built. When every player of the room (and, on a dedicated server, the server's own
## copy) is, the countdown starts for all of them together.
func race_ready(_node: Node, room: int) -> void:
	if is_server():
		_mark_loaded(room, 0 if mode == Mode.DEDICATED else local_id())
	else:
		_client_loaded.rpc_id(1)


@rpc("any_peer", "reliable")
func _client_loaded() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if is_server() and _peer_room.has(sender):
		_mark_loaded(int(_peer_room[sender]), sender)


func _mark_loaded(room: int, who: int) -> void:
	if not _rooms.has(room):
		return
	var r: Dictionary = _rooms[room]
	var loaded: Dictionary = r["loaded"]
	loaded[who] = true
	if bool(r["counting"]):
		return
	for p in r["players"]:
		if not loaded.has(int(p)):
			return
	if mode == Mode.DEDICATED and not loaded.has(0):
		return
	r["counting"] = true
	_log("room %d: everyone is ready -- countdown" % room)
	for p in r["players"]:
		if int(p) == local_id() and mode == Mode.HOST:
			_begin_countdown_local(room)
		else:
			if _sendable(int(p)):
				_begin_countdown.rpc_id(int(p))
	if mode == Mode.DEDICATED:
		_begin_countdown_local(room)


@rpc("authority", "reliable")
func _begin_countdown() -> void:
	_begin_countdown_local(room_id)


func _begin_countdown_local(room: int) -> void:
	var node := _race_node(room)
	if node != null:
		node.net_begin_countdown()


# ---------------------------------------------------------------- in-race traffic

## The state of car `key` of room `room` (its owner calls this). The sender's clock (ms) goes on the end
## of the car's 18 fields: the receiving NetPuppet interpolates on the sender's timeline, so the
## network's jitter does not become the car's (`Car.apply_net_state` ignores the extra element).
func send_car_state(key: int, state: Array, room: int) -> void:
	if not is_online():
		return
	var stamped := state.duplicate()
	stamped.append(Time.get_ticks_msec())
	if is_server():
		_relay_state(room, local_id(), key, stamped)
	else:
		_car_state.rpc_id(1, key, stamped)


@rpc("any_peer", "unreliable_ordered")
func _car_state(key: int, state: Array) -> void:
	if not is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _peer_room.has(sender):
		return
	var room := int(_peer_room[sender])
	if not _owns(room, sender, key):
		return
	var node := _race_node(room)
	if node != null:
		node.net_car_state(key, state)
	_relay_state(room, sender, key, state)


func _relay_state(room: int, from: int, key: int, state: Array) -> void:
	if not _rooms.has(room):
		return
	for p in _rooms[room]["players"]:
		if int(p) != from and not (int(p) == local_id() and mode == Mode.HOST):
			if _sendable(int(p)):
				_car_state_relay.rpc_id(int(p), key, state)


@rpc("authority", "unreliable_ordered")
func _car_state_relay(key: int, state: Array) -> void:
	if race != null:
		race.net_car_state(key, state)


## "wreck", "finish" (data = total time): the car's owner calls this; everyone in the room hears it.
## SPEC 128: WHO DID IT AND WHAT IT WAS ARE TWO DIFFERENT NUMBERS. Every event used to carry one `key`,
## which the server then checked as a CAR the sender owns -- right for "I wrecked" and "I finished", and
## wrong for "I went through wall 3", where the key is a wall. A wall index only passed that check when it
## happened to equal a car key the sender owned, so online, breakable walls (SPEC 124) opened on the
## machine of whoever drove through and NOWHERE else: everybody kept racing into a wall that was not
## there any more, and the one who broke it was driving a route nobody else could see.
##
## `who` is the car making the claim. When it is left out, the key IS the car, which is what the older
## events mean; when it is given, the key is the event's own subject and the ownership check is on `who`.
func send_event(kind: String, key: int, data: float, room: int, who: int = -1) -> void:
	if not is_online():
		return
	if is_server():
		_server_event(room, local_id(), kind, key, data, who)
	else:
		_event_up.rpc_id(1, kind, key, data, who)


@rpc("any_peer", "reliable")
func _event_up(kind: String, key: int, data: float, who: int = -1) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if is_server() and _peer_room.has(sender):
		_server_event(int(_peer_room[sender]), sender, kind, key, data, who)


func _server_event(room: int, sender: int, kind: String, key: int, data: float,
		who: int = -1) -> void:
	if not _rooms.has(room) or not _owns(room, sender, who if who >= 0 else key):
		return
	var r: Dictionary = _rooms[room]
	# SPEC 128: the room's own record of the routes that have been opened in it. The clients each hear
	# the event once and keep their own copy; this is the authority's, and it is what a race node created
	# after the fact (a dedicated server's) and `open_walls()` read.
	if kind == "wall" and key >= 0 and key < 32:
		r["walls"] = int(r.get("walls", 0)) | (1 << key)
	if kind == "finish":
		for res in r["results"]:
			if int(res["key"]) == key:
				return
		(r["results"] as Array).append({"key": key, "time": data})
	_log("room %d: %s car %d %.2f" % [room, kind, key, data])
	for p in r["players"]:
		if not (int(p) == local_id() and mode == Mode.HOST):
			if _sendable(int(p)):
				_event_down.rpc_id(int(p), kind, key, data)
	var node := _race_node(room)
	if node != null:
		node.net_event(kind, key, data)
	if kind == "finish":
		_check_race_over(room)


func _check_race_over(room: int) -> void:
	if not _rooms.has(room):
		return
	var r: Dictionary = _rooms[room]
	if bool(r["over_sent"]) or String(r["state"]) != "racing":
		return
	var done := {}
	for res in r["results"]:
		done[int(res["key"])] = true
	for e in (r["race_setup"] as Dictionary).get("entries", []):
		if String(e["kind"]) == "human" and (r["players"] as Array).has(int(e["peer"])) and not done.has(int(e["key"])):
			return
	r["over_sent"] = true
	var results: Array = r["results"]
	# SPEC 65: the room's own scoreboard. The first finisher's NAME takes the win, so it survives a
	# reconnect (a peer id does not) and reads the same for everyone in the room.
	if not results.is_empty():
		var winner := int((results[0] as Dictionary)["key"])
		for e in (r["race_setup"] as Dictionary).get("entries", []):
			if int(e["key"]) == winner:
				var who := String(e["name"])
				var wins: Dictionary = r.get("wins", {})
				wins[who] = int(wins.get(who, 0)) + 1
				r["wins"] = wins
				break
	_log("room %d: race over" % room)
	for p in r["players"]:
		if not (int(p) == local_id() and mode == Mode.HOST):
			if _sendable(int(p)):
				_race_over.rpc_id(int(p), results)
	var node := _race_node(room)
	if node != null:
		node.net_race_over(results)
	if mode == Mode.DEDICATED:
		_award_race(room)
		get_tree().create_timer(RESULTS_TIME).timeout.connect(func() -> void: return_to_lobby(room))


@rpc("authority", "reliable")
func _event_down(kind: String, key: int, data: float) -> void:
	if race != null:
		race.net_event(kind, key, data)


@rpc("authority", "reliable")
func _race_over(results: Array) -> void:
	if race != null:
		race.net_race_over(results)


@rpc("authority", "reliable")
func _net_peer_left(id: int) -> void:
	if race != null:
		race.net_peer_left(id)


# ---------------------------------------------------------------- back to the lobby

func return_to_lobby(room: int) -> void:
	if is_server() and _rooms.has(room):
		var r: Dictionary = _rooms[room]
		if String(r["state"]) == "lobby":
			return
		r["state"] = "lobby"
		r["race_setup"] = {}
		_free_room_race(r)
		for p in r["players"]:
			if int(p) == local_id() and mode == Mode.HOST:
				_to_lobby_local()
			else:
				if _sendable(int(p)):
					_to_lobby.rpc_id(int(p))
		_sync_room(room)
		_broadcast_rooms()
	else:
		_to_lobby_local()


@rpc("authority", "reliable")
func _to_lobby() -> void:
	_to_lobby_local()


func _to_lobby_local() -> void:
	race = null
	race_setup = {}
	GameState.go_to_lobby()


## Does peer `sender` own car `key` in room `room`? Humans own their car; the server owns the AI.
func _owns(room: int, sender: int, key: int) -> bool:
	if not _rooms.has(room):
		return false
	for e in (_rooms[room]["race_setup"] as Dictionary).get("entries", []):
		if int(e["key"]) == key:
			if String(e["kind"]) == "ai":
				return sender == local_id() and is_server()
			return int(e["peer"]) == sender
	return false


## SPEC 128: the routes already open in `room`, as a bitmask of wall indices. The server's own answer,
## for anything that has to catch up with a race in progress.
func open_walls(room: int) -> int:
	return int(_rooms[room].get("walls", 0)) if _rooms.has(room) else 0


## This machine's entry in a race line-up (-1: not driving in it -- a dedicated server).
func my_entry_key(setup: Dictionary) -> int:
	if mode == Mode.DEDICATED:
		return -1
	for e in setup.get("entries", []):
		if String(e["kind"]) == "human" and int(e["peer"]) == local_id():
			return int(e["key"])
	return -1


# ---------------------------------------------------------------- the leaderboard

## Points for finishing `place`-th (1-based): 10, 7, 5, 3, 2, then 1.
static func place_points(place: int) -> int:
	if place < 1:
		return 0
	return int(POINTS[place - 1]) if place <= POINTS.size() else 1


## Server: `name` finished `place`-th -- its row after the award. Names are self-declared strings, so
## two players with one name share a row (that is the key the owner asked for).
func award(name: String, place: int) -> Dictionary:
	var who := GameState.sanitize_name(name)
	var row: Dictionary = _board.get(who, {"points": 0, "races": 0, "wins": 0})
	row["points"] = int(row["points"]) + place_points(place)
	row["races"] = int(row["races"]) + 1
	if place == 1:
		row["wins"] = int(row["wins"]) + 1
	_board[who] = row
	return row


## The board, best first (points, then wins, then races, then the name): [{"name", "points", "races",
## "wins"}], at most `limit` rows (0 = all).
func leaderboard_rows(limit: int = 0) -> Array:
	var rows: Array = []
	for who in _board.keys():
		var row: Dictionary = _board[who]
		rows.append({"name": String(who), "points": int(row["points"]), "races": int(row["races"]),
				"wins": int(row["wins"])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["points"]) != int(b["points"]):
			return int(a["points"]) > int(b["points"])
		if int(a["wins"]) != int(b["wins"]):
			return int(a["wins"]) > int(b["wins"])
		if int(a["races"]) != int(b["races"]):
			return int(a["races"]) < int(b["races"])
		return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0)
	if limit > 0 and rows.size() > limit:
		rows.resize(limit)
	return rows


## Server: `name`'s rank on the board (1 = best; 0 = not on it).
func leaderboard_rank(name: String) -> int:
	var rows := leaderboard_rows()
	for i in rows.size():
		if String(rows[i]["name"]) == name:
			return i + 1
	return 0


## Server: the board from `leaderboard_path` (missing or broken rows are skipped).
func load_leaderboard() -> void:
	_board.clear()
	var cfg := ConfigFile.new()
	if cfg.load(leaderboard_path) != OK:
		return
	if not cfg.has_section("players"):
		return
	for who in cfg.get_section_keys("players"):
		var v = cfg.get_value("players", who, {})
		if v is Dictionary:
			_board[GameState.sanitize_name(String(who))] = {"points": maxi(int(v.get("points", 0)), 0),
					"races": maxi(int(v.get("races", 0)), 0), "wins": maxi(int(v.get("wins", 0)), 0)}


func save_leaderboard() -> bool:
	var cfg := ConfigFile.new()
	for who in _board.keys():
		cfg.set_value("players", String(who), (_board[who] as Dictionary).duplicate())
	var err := cfg.save(leaderboard_path)
	if err != OK:
		print("[net server] cannot save the leaderboard to %s (error %d)" % [leaderboard_path, err])
	return err == OK


## Server: score room `room`'s finished race -- every human in the results by its place (the AI hold
## places too: beating them counts), a player who left before the flag nothing -- tell each one what it
## earned, save, and send everyone the new board.
func _award_race(room: int) -> void:
	if mode != Mode.DEDICATED or not _rooms.has(room):
		return
	var r: Dictionary = _rooms[room]
	var by_key := {}
	for e in (r["race_setup"] as Dictionary).get("entries", []):
		by_key[int(e["key"])] = e
	var place := 0
	var awarded := 0
	for res in r["results"]:
		place += 1
		var e: Dictionary = by_key.get(int(res["key"]), {})
		if e.is_empty() or String(e["kind"]) != "human":
			continue
		awarded += 1
		_award_peer(String(e["name"]), int(e["peer"]), place, room)
	if awarded > 0:
		_finish_awards(room)


func _award_peer(name: String, peer: int, place: int, room: int) -> void:
	var row := award(name, place)
	var pts := place_points(place)
	_log("room %d: %s finished %d. -- +%d points (%d)" % [room, name, place, pts, int(row["points"])])
	if peer != local_id() and _is_open(peer):
		_points_awarded.rpc_id(peer, pts, int(row["points"]), leaderboard_rank(GameState.sanitize_name(name)))


func _finish_awards(_room: int) -> void:
	save_leaderboard()
	var rows := leaderboard_rows(LEADERBOARD_ROWS)
	for p in multiplayer.get_peers():
		if _is_open(p):
			_leaderboard.rpc_id(p, rows)


@rpc("authority", "reliable")
func _points_awarded(points: int, total: int, rank: int) -> void:
	last_award = {"points": points, "total": total, "rank": rank}
	points_awarded.emit(points, total, rank)


@rpc("authority", "reliable")
func _leaderboard(rows: Array) -> void:
	leaderboard = rows
	leaderboard_changed.emit()


## The server's rooms (for tests and the console): room id -> {"name", "players", "state"}.
# ---------------------------------------------------------------- server directory (SPEC 43)

## Dedicated server: tell the directory (a Cloudflare Worker) we are up, how busy, and where.
func _send_heartbeat() -> void:
	if _heartbeat == null:
		_heartbeat = HTTPRequest.new()
		_heartbeat.name = "Heartbeat"
		_heartbeat.timeout = 10.0
		add_child(_heartbeat)
		_heartbeat.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
			if result != HTTPRequest.RESULT_SUCCESS or code >= 300:
				print("[net server] directory heartbeat failed (result %d, HTTP %d)" % [result, code]))
	if _heartbeat.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var body := JSON.stringify(heartbeat_body())
	_heartbeat.request(register_url, ["Content-Type: application/json", "Authorization: Bearer %s" % register_key],
			HTTPClient.METHOD_POST, body)


func heartbeat_body() -> Dictionary:
	var rooms_public := 0
	for r in _rooms.values():
		if bool(r["public"]):
			rooms_public += 1
	return {"name": server_name, "url": public_url, "players": _profiles.size(), "max": max_peers,
			"rooms": rooms_public, "protocol": PROTOCOL, "version": Version.number(), "motd": server_motd}


## Writes this server's entry as a one-server list ({"servers": [...]}, the directory's own format) to
## `status_file` -- via a temporary file and a rename, so nginx never serves half a file.
func write_status_file(path: String = "") -> bool:
	var target := path if path != "" else status_file
	if target == "":
		return false
	var entry := heartbeat_body()
	entry["updated"] = int(Time.get_unix_time_from_system())
	var tmp := target + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		print("[net server] cannot write the status file %s (error %d)" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify({"servers": [entry] if public_url != "" else []}))
	f.close()
	return DirAccess.rename_absolute(tmp, target) == OK


## Client: fetch the server list from the directory (servers_changed when it arrives).
func fetch_servers() -> void:
	if _directory == null:
		_directory = HTTPRequest.new()
		_directory.name = "Directory"
		_directory.timeout = 10.0
		add_child(_directory)
		_directory.request_completed.connect(_on_directory)
	if _directory.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	servers_status = "Loading the server list ..."
	servers_changed.emit()
	var err := _directory.request(DIRECTORY_URL)
	if err != OK:
		servers_status = "Could not ask for the server list (error %d)." % err
		servers_changed.emit()


func _on_directory(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		servers_list = []
		servers_status = "The server list is not available right now (result %d, HTTP %d)." % [result, code]
		servers_changed.emit()
		return
	servers_list = parse_server_list(body.get_string_from_utf8())
	servers_status = "%d server%s online." % [servers_list.size(), "" if servers_list.size() == 1 else "s"] \
			if not servers_list.is_empty() else "No servers are online right now."
	servers_changed.emit()


## The directory's JSON -> [{"name", "url", "players", "max", "rooms", "protocol", "motd"}], newest format
## tolerated: unknown fields ignored, broken entries dropped, same-protocol servers first.
static func parse_server_list(text: String) -> Array:
	var data = JSON.parse_string(text)
	var arr: Array = []
	if data is Dictionary and (data as Dictionary).has("servers"):
		data = data["servers"]
	if not (data is Array):
		return arr
	for e in data:
		if not (e is Dictionary) or not (e as Dictionary).has("url"):
			continue
		var url := String(e["url"])
		if not (url.begins_with("ws://") or url.begins_with("wss://")):
			continue
		arr.append({"name": _clean_room_name(String(e.get("name", url))), "url": url,
				"players": int(e.get("players", 0)), "max": int(e.get("max", 0)), "rooms": int(e.get("rooms", 0)),
				"protocol": int(e.get("protocol", 0)), "version": String(e.get("version", "")).substr(0, 16),
				"motd": String(e.get("motd", "")).substr(0, 120)})
	arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var am := int(a["protocol"]) == PROTOCOL
		var bm := int(b["protocol"]) == PROTOCOL
		if am != bm:
			return am
		return int(a["players"]) > int(b["players"]))
	return arr


func get_server_rooms() -> Dictionary:
	var out := {}
	for id in _rooms.keys():
		out[id] = {"name": _rooms[id]["name"], "players": (_rooms[id]["players"] as Array).duplicate(),
				"state": _rooms[id]["state"]}
	return out
