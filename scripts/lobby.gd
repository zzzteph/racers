extends Control
## Multiplayer (SPEC 43). Not connected -- four tabs:
##   ONLINE   the official server (rope.thenakedcat.games): one button
##   SERVERS  the server directory's list (a Cloudflare Worker), Join any of them
##   DIRECT   any server by address (host:port or a ws:// / wss:// URL)
##   HOST     be the server yourself (a LAN / port-forwarded game; not in the web build)
## with YOU on the right: your name. (The car and colour are chosen in the room -- CHOOSE CAR opens the car screen.)
## Connected to a dedicated server, not in a room -- the ROOM LIST: public rooms (a lock marks a password;
## the five standing rooms first), QUICK JOIN, the server's LEADERBOARD (rank, name, points; you
## highlighted), CREATE ROOM (name, public / private, password, player limit) and JOIN BY CODE.
## In a room -- the players (the leader can kick), the room's code and whether it is private, the CHAT
## (a log and a line to type), your car (CHOOSE CAR: the full car screen, back to the room when done),
## YOUR NAME (changed on the spot), and the race setup the leader chooses and starts: START runs a
## 5-4-3-2-1 countdown, big in the middle, that the leader can CANCEL. Everything shown comes from Net.

const BG_COLOR := Color(0.13, 0.32, 0.14)
const TITLE_COLOR := Color(1.0, 0.92, 0.3)
## SPEC 62: dark enough to read over the background art, and one type scale with the other screens.
const PANEL_COLOR := Color(0.0, 0.0, 0.0, 0.72)
const CAPTION_COLOR := Color(1.0, 0.92, 0.3)
const SUB_COLOR := Color(0.8, 0.84, 0.8)
const TABS := ["online", "servers", "direct", "host"]
const TAB_NAMES := {"online": "ONLINE", "servers": "SERVERS", "direct": "DIRECT", "host": "HOST LAN"}

var _tab: String = "online"
var _tab_buttons: Dictionary = {}
var _tab_boxes: Dictionary = {}
var _connect_box: Control = null
## SPEC 122: the card that is up while the connection is being made or remade -- see `_build_working`.
var _working_box: Control = null
var _working_title: Label = null
var _working_note: Label = null
var _working_cancel: Button = null
var _room_box: Control = null
var _browser_box: Control = null
var _rooms_box: VBoxContainer = null
var _servers_box: VBoxContainer = null
var _servers_status: Label = null
var _room_name_edit: LineEdit = null
var _room_pw_edit: LineEdit = null
var _room_public: bool = true
var _room_max: int = 6
var _public_button: Button = null
var _max_button: Button = null
var _code_edit: LineEdit = null
var _code_pw_edit: LineEdit = null
var _pw_popup: Control = null
var _pw_popup_edit: LineEdit = null
## SPEC 125: the password dialog's own title, note and button -- it reports its own failures now.
var _pw_title: Label = null
var _pw_note: Label = null
var _pw_join: Button = null
var _pw_room: int = -1
var _room_title: Label = null

var _shown_map_track: String = ""
var _room_code: Label = null
var _room_public_button: Button = null
var _room_max_button: Button = null
var _back_button: Button = null
var _name_edit: LineEdit = null
var _ip_edit: LineEdit = null
var _port_edit: LineEdit = null
var _host_port_edit: LineEdit = null
var _status: Label = null
var _conn_label: Label = null
var _players_label: RichTextLabel = null
var _car_button: Button = null
var _color_button: Button = null
var _track_button: Button = null
var _laps_button: Button = null
## SPEC 120: a room has no AI. The rivals count and their skill were the two settings here that were
## not about the people in the room; a multiplayer race is between the players in it, and the server
## keeps its `rivals` at zero for the same reason.
var _start_button: Button = null
var _setup_note: Label = null
## SPEC 122: "THE RACE" over the setup panel.
var _setup_caption: Label = null
var _setup_controls: Array[Control] = []
var _chat_log: RichTextLabel = null
var _chat_edit: LineEdit = null
var _my_name_edit: LineEdit = null
var _countdown_label: Label = null
var _countdown_box: Control = null          # SPEC 113: the card the number sits on
var _shown_count: int = -1
var _board_box: VBoxContainer = null
var _board_status: Label = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	Net.lobby_changed.connect(_refresh)
	Net.room_refused.connect(_on_room_refused)   # SPEC 125: inside the dialog that asked
	Net.rooms_changed.connect(_refresh)
	Net.servers_changed.connect(_refresh_servers)
	Net.status_changed.connect(func(t: String) -> void: _status.text = t)
	Net.disconnected.connect(_on_disconnected)
	Net.chat_received.connect(func(_n: String, _t: String) -> void: _refresh_chat())
	Net.leaderboard_changed.connect(_refresh_board)
	_status.text = Net.status
	_select_tab(String(GameState.settings.get("mp_tab", "online")))
	_refresh()


func _process(_delta: float) -> void:
	_tick_countdown()


## The room's countdown, big in the middle: 5, 4, 3, 2, 1 with a beep on each, from what the server
## said is left (`Net.countdown_left`); gone at zero (the race arrives) or when the leader cancels.
func _tick_countdown() -> void:
	var left := Net.countdown_left()
	var n := int(ceil(left - 0.001)) if left > 0.0 else 0
	if n <= 0:
		if _countdown_label.visible:
			_countdown_label.visible = false
			_countdown_box.visible = false
		_shown_count = -1
		return
	if n != _shown_count:
		_shown_count = n
		_countdown_label.text = str(n)
		_countdown_label.visible = true
		_countdown_box.visible = true
		_countdown_box.move_to_front()          # over whatever a refresh added after it
		Audio.beep(false)


func _on_disconnected(reason: String) -> void:
	_status.text = reason
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _pw_popup != null and _pw_popup.visible:
			_pw_popup.visible = false
			return
		leave()


func leave() -> void:
	if Net.mode == Net.Mode.DEDICATED:
		return
	if Net.mode == Net.Mode.CLIENT and Net.server_kind == "dedicated" and Net.in_room():
		Net.leave_room()          # back to the room list
		_refresh()
		return
	if Net.is_online() or Net.reconnecting:
		Net.leave()
		_status.text = "Disconnected."
		_refresh()
		return
	GameState.go_to_menu()


# ---------------------------------------------------------------- actions

func _save_name() -> void:
	GameState.set_setting("player_name", _name_edit.text)
	_name_edit.text = GameState.get_player_name()


func _play_official() -> void:
	_save_name()
	Net.join_official()
	_refresh()


func _join() -> void:
	_save_name()
	GameState.set_setting("mp_address", _ip_edit.text.strip_edges())
	Net.join(_ip_edit.text, _port())
	_refresh()


func _join_listed(url: String) -> void:
	_save_name()
	Net.join(url)
	_refresh()


func _host() -> void:
	_save_name()
	Net.host(_host_port())
	_refresh()


func _port() -> int:
	var p := int(_port_edit.text)
	return p if p > 0 and p < 65536 else Net.DEFAULT_PORT


func _host_port() -> int:
	var p := int(_host_port_edit.text)
	return p if p > 0 and p < 65536 else Net.DEFAULT_PORT


func _create_room() -> void:
	var n := _room_name_edit.text.strip_edges()
	Net.create_room(n if n != "" else "%s's room" % GameState.get_player_name(), _room_public,
			_room_pw_edit.text, _room_max)


## The chat line goes to the room (the server echoes it back to everyone, me included).
func _send_chat() -> void:
	var t := _chat_edit.text.strip_edges()
	if t == "":
		return
	Net.send_chat(t)
	_chat_edit.text = ""


## YOUR NAME, changed in the room: saved, and the room told at once.
func _save_room_name() -> void:
	var want := GameState.sanitize_name(_my_name_edit.text)
	if want != GameState.get_player_name():
		GameState.set_setting("player_name", want)
		Net.update_my_player()
	_my_name_edit.text = GameState.get_player_name()


## START RACE, or CANCEL during the countdown.
func _start_or_cancel() -> void:
	if Net.countdown_left() >= 0.0:
		Net.cancel_start()
	else:
		Net.request_start()


func _join_by_code() -> void:
	var c := _code_edit.text.strip_edges().to_upper()
	if c.length() < 4:
		_status.text = "Type the room's code (6 letters)."
		return
	Net.join_code(c, _code_pw_edit.text)


func _join_listed_room(id: int, locked: bool) -> void:
	if locked:
		_pw_room = id
		_pw_popup_edit.text = ""
		_pw_note.text = ""
		_pw_join.disabled = false
		_pw_title.text = "PASSWORD FOR  %s" % _room_name(id).to_upper()
		_pw_popup.visible = true
		_pw_popup_edit.grab_focus()
		return
	Net.join_room(id)


## SPEC 125: the name of a listed room, so a dialog about it can say which one it is about.
func _room_name(id: int) -> String:
	for r in Net.rooms_list:
		if int((r as Dictionary)["id"]) == id:
			return String((r as Dictionary)["name"])
	return "that room"


## SPEC 125: submitted, and WAITING. The dialog stays up in a Joining state; `_on_room_refused` puts a
## refusal inside it and `_refresh` closes it once we are actually in a room.
func _join_with_password() -> void:
	if _pw_popup_edit.text.strip_edges() == "":
		_pw_note.text = "Type the password first."
		return
	_pw_note.text = ""
	_pw_join.disabled = true
	_pw_join.text = "Joining ..."
	Net.join_room(_pw_room, _pw_popup_edit.text)


## The server said no. The dialog keeps the room, the typing and the focus.
func _on_room_refused(reason: String) -> void:
	if _pw_popup == null or not _pw_popup.visible:
		return
	_pw_join.disabled = false
	_pw_join.text = "Join"
	_pw_note.text = reason
	_pw_popup_edit.grab_focus()
	_pw_popup_edit.select_all()


func _close_password() -> void:
	if _pw_popup == null:
		return
	_pw_popup.visible = false
	_pw_join.disabled = false
	_pw_join.text = "Join"
	_pw_note.text = ""
	# SPEC 125: focus goes back where it came from -- the Join button of the room that was being joined.
	var back := find_child("Join_%d" % _pw_room, true, false) as Button
	if back != null and back.is_visible_in_tree() and not back.disabled:
		back.grab_focus()


## The full car screen (cars, stats, colours); Back / Done return here, still connected.
func _choose_car() -> void:
	GameState.go_to_car_select()


## SPEC 73: the room's quick car switch walks OWNED cars only -- the full screen (CHOOSE CAR) is where
## a locked one can be looked at and bought.
func _cycle_car() -> void:
	var ids := CarRegistry.ids()
	var at := CarRegistry.index_of(GameState.owned_car())
	for step in ids.size():
		var id := String(ids[(at + 1 + step) % ids.size()])
		if GameState.profile.is_car_unlocked(id):
			GameState.select_car(id)
			break
	Net.update_my_player()
	_refresh()


func _cycle_color() -> void:
	GameState.select_color(GameState.selected_color + 1)
	Net.update_my_player()
	_refresh()


## SPEC 120: whatever a room was set to before, a room has no AI in it now.
func _no_rivals() -> void:
	if int(Net.lobby.get("rivals", 0)) != 0 and Net.is_leader():
		Net.request_setup({"rivals": 0})


func _cycle_track() -> void:
	var ids := TrackRegistry.ids()
	var i := Array(ids).find(String(Net.lobby.get("track", "circle")))
	Net.request_setup({"track": ids[(i + 1) % ids.size()]})


func _cycle_laps() -> void:
	var choices: Array = Net.LAPS_CHOICES
	var i := choices.find(int(Net.lobby.get("laps", 10)))
	Net.request_setup({"laps": choices[(i + 1) % choices.size()]})


func _select_tab(t: String) -> void:
	if not TABS.has(t):
		t = "online"
	_tab = t
	GameState.settings["mp_tab"] = t
	for k in _tab_boxes.keys():
		(_tab_boxes[k] as Control).visible = k == t
		(_tab_buttons[k] as Button).set_pressed_no_signal(k == t)
	if t == "servers" and Net.servers_list.is_empty():
		Net.fetch_servers()


func get_tab() -> String:
	return _tab


## SPEC 128: THE ORDER THE KEYBOARD WALKS THE LOBBY -- everything on it that can be typed in or pressed,
## in READING ORDER: down the screen, and left to right within a band. The screen changes shape
## underneath this (connected, browsing, in a room, which tab is up), so it is rebuilt after every
## refresh rather than wired once, and it only ever includes controls that are actually on screen: a
## chain that points at something the refresh just hid is a Tab that goes nowhere.
##
## SPEC 129: it used to walk only the visible TAB's buttons, which left the room and the browser -- most
## of the screen, most of the time -- off the path entirely.
func _order_focus() -> void:
	var live: Array = []
	for node in find_children("*", "Button", true, false):
		var b := node as Button
		if b != null and b.is_visible_in_tree() and not b.disabled:
			live.append(b)
	for node in find_children("*", "LineEdit", true, false):
		var e := node as LineEdit
		if e != null and e.is_visible_in_tree() and not e.editable == false:
			live.append(e)
	# Down the screen in 40 px bands, then across: the order a player reads it in, not the order the
	# code happened to build it in.
	live.sort_custom(func(a, b) -> bool:
		var pa: Vector2 = (a as Control).global_position
		var pb: Vector2 = (b as Control).global_position
		var band := int(pa.y / 40.0) - int(pb.y / 40.0)
		return pa.x < pb.x if band == 0 else band < 0)
	UiTheme.focus_chain(live)


# ---------------------------------------------------------------- refresh

func _refresh() -> void:
	# SPEC 128: the keyboard order is rebuilt after every refresh, deferred so it sees the visibility
	# this pass is about to set. `_refresh` has several early exits and the order has to survive all of
	# them -- a Tab chain pointing at a control the refresh just hid is a Tab that goes nowhere.
	_order_focus.call_deferred()
	var connected := Net.is_online() and (Net.is_server() or not Net.players.is_empty())
	var browsing := Net.mode == Net.Mode.CLIENT and Net.server_kind == "dedicated" and not Net.in_room()
	_connect_box.visible = not Net.is_online() and not Net.reconnecting
	_browser_box.visible = browsing
	_room_box.visible = Net.is_online() and not browsing and (Net.in_room() or Net.mode == Net.Mode.DEDICATED)
	# SPEC 125: we got in -- the password dialog has nothing left to ask about.
	if _pw_popup != null and _pw_popup.visible and Net.in_room():
		_close_password()
	if Net.mode == Net.Mode.CLIENT and Net.server_kind == "dedicated" and Net.in_room():
		_back_button.text = "Leave room"
	elif Net.is_online() or Net.reconnecting:
		_back_button.text = "Disconnect"
	else:
		_back_button.text = "Menu"
	# SPEC 122: the card that explains an otherwise bare screen -- and it only goes up when the screen
	# WOULD be bare. A half-open connection that is already showing a room browser or a room has nothing
	# to explain, and a card over the top of either is just something in the way.
	if _working_box != null:
		_working_box.visible = (Net.reconnecting or Net.is_connecting()) \
				and not _browser_box.visible and not _room_box.visible and not _connect_box.visible
		if _working_box.visible:
			_refresh_working()
	_refresh_connection_label()
	_refresh_me()
	if browsing:
		_refresh_rooms()
		_refresh_board()
		return
	if not Net.is_online() or not _room_box.visible:
		return
	_refresh_room()
	_refresh_chat()


func _refresh_connection_label() -> void:
	if Net.reconnecting:
		_conn_label.text = "reconnecting ..."
	elif Net.mode == Net.Mode.CLIENT:
		var nm := String(Net.server_info.get("name", Net.display_address(Net.last_address)))
		_conn_label.text = "%s   %s" % [nm, "%d ms" % Net.ping_ms if Net.ping_ms >= 0 else "..."]
	elif Net.mode == Net.Mode.HOST:
		_conn_label.text = "hosting"
	else:
		_conn_label.text = ""


func _refresh_me() -> void:
	var pal: Array = CarRegistry.get_palette(GameState.selected_car)
	_car_button.text = "%s  -  %s" % [CarRegistry.get_display_name(GameState.selected_car),
			String(pal[GameState.selected_color]["name"])]
	_style_swatch(_car_button, pal[GameState.selected_color]["body"])
	if _my_name_edit != null and not _my_name_edit.has_focus():
		_my_name_edit.text = GameState.get_player_name()


## The room browser: one row per public room, with Join (a lock and a password prompt for locked ones).
func _refresh_rooms() -> void:
	for c in _rooms_box.get_children():
		c.queue_free()
	# SPEC 72: the protocol decides whether we may play at all; the version only says who is behind.
	var behind := Version.update_hint(String(Net.server_info.get("version", "")))
	if behind != "":
		var u := _label("UpdateHint", Rect2(0, 0, 600, 32), 16, UiTheme.WARN)
		u.text = behind
		# SPEC 122: wrapped, not 600 px of demand inside the list's window.
		u.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		u.custom_minimum_size = Vector2(0, 32)
		u.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rooms_box.add_child(u)
	var motd := String(Net.server_info.get("motd", ""))
	if motd != "":
		var m := _label("Motd", Rect2(0, 0, 600, 32), 16, TITLE_COLOR)
		m.text = motd
		m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		m.custom_minimum_size = Vector2(0, 32)
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rooms_box.add_child(m)
	if Net.rooms_list.is_empty():
		var none := _label("NoRooms", Rect2(0, 0, 488, 40), 18, SUB_COLOR)
		none.text = "No public rooms yet -- make one on the right, or QUICK JOIN."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size = Vector2(0, 40)
		none.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rooms_box.add_child(none)
		return
	for r in Net.rooms_list:
		var row := HBoxContainer.new()
		# SPEC 122: no fixed width -- the row is as wide as the window, and the NAME is what gives way.
		row.custom_minimum_size = Vector2(0, 52)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12)
		var state := String(r["state"])
		var busy := state != "lobby"                 # racing, or counting down to it
		var full := int(r["players"]) >= int(r["max"])
		var locked := bool(r.get("locked", false))
		# Two lines: the name, then the facts -- a phone-width row, nothing clipped.
		var info := VBoxContainer.new()
		info.custom_minimum_size = Vector2(160, 52)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		var name_l := Label.new()
		name_l.text = String(r["name"])
		name_l.add_theme_font_size_override("font_size", UiTheme.BODY)     # SPEC 62
		name_l.custom_minimum_size = Vector2(160, 26)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		info.add_child(name_l)
		# SPEC 122: what the room plays first (SPEC 140: every room is a race), then the map, then how
		# full it is.
		var facts := PackedStringArray(["Race", String(r["track"]),
				"%d/%d" % [int(r["players"]), int(r["max"])]])
		if locked:
			facts.append("password")
		if busy:
			facts.append("racing" if state == "racing" else "starting")
		var facts_l := Label.new()
		facts_l.text = "  -  ".join(facts)
		facts_l.add_theme_font_size_override("font_size", UiTheme.CAPTION)
		facts_l.add_theme_color_override("font_color", SUB_COLOR)
		facts_l.custom_minimum_size = Vector2(160, 24)
		facts_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		facts_l.clip_text = true
		info.add_child(facts_l)
		row.add_child(info)
		var b := Button.new()
		b.name = "Join_%d" % int(r["id"])
		b.text = ("Racing" if state == "racing" else "Starting") if busy else ("Full" if full else "Join")
		b.disabled = busy or full
		b.focus_mode = Control.FOCUS_ALL          # SPEC 128: a room you cannot Tab to is one you cannot join
		b.custom_minimum_size = Vector2(110, 44)
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(_join_listed_room.bind(int(r["id"]), locked))
		row.add_child(b)
		_rooms_box.add_child(row)


## The server's leaderboard: rank, name, points -- me highlighted. Rebuilt when the server sends rows.
func _refresh_board() -> void:
	if _board_box == null or _room_box == null or not _room_box.visible:
		return
	for c in _board_box.get_children():
		c.queue_free()
	var me := GameState.get_player_name()
	var mine := 0
	for i in Net.leaderboard.size():
		if String(Net.leaderboard[i]["name"]) == me:
			mine = i + 1
			break
	if Net.leaderboard.is_empty():
		_board_status.text = "No race scored yet."
	else:
		_board_status.text = "You are #%d" % mine if mine > 0 else "Finish a race to get on it"
	for i in Net.leaderboard.size():
		var r: Dictionary = Net.leaderboard[i]
		var row := HBoxContainer.new()
		row.name = "Board_%d" % (i + 1)
		row.custom_minimum_size = Vector2(0, 32)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		var yours := String(r["name"]) == me
		var who := Label.new()
		who.text = "%d.  %s" % [i + 1, String(r["name"])]
		who.add_theme_font_size_override("font_size", UiTheme.CAPTION)
		who.add_theme_color_override("font_color", TITLE_COLOR if yours else Color.WHITE)
		who.custom_minimum_size = Vector2(120, 32)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		who.clip_text = true
		row.add_child(who)
		var pts := Label.new()
		pts.text = "%d" % int(r["points"])
		pts.add_theme_font_size_override("font_size", UiTheme.CAPTION)
		pts.add_theme_color_override("font_color", TITLE_COLOR if yours else Color.WHITE)
		pts.custom_minimum_size = Vector2(48, 32)
		pts.size_flags_horizontal = Control.SIZE_SHRINK_END
		pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pts.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pts.tooltip_text = "%d races, %d wins" % [int(r["races"]), int(r["wins"])]
		row.add_child(pts)
		_board_box.add_child(row)


## The room's chat log: the last lines, the sender in its car's colour, following the newest.
func _refresh_chat() -> void:
	if _chat_log == null:
		return
	var lines := PackedStringArray()
	for l in Net.chat_lines:
		# SPEC 125: the car's colour is a SWATCH, not the text. A name drawn in a car colour is a name
		# drawn in whatever the player picked -- navy on near-black, or a yellow that vanishes -- and a
		# name nobody can read is worse than a name with no colour at all.
		var col: Color = l["color"]
		lines.append("[color=#%s]#[/color] [color=#dfe4ea]%s:[/color]  %s"
				% [_readable(col).to_html(false), _bb_escape(String(l["name"])),
				_bb_escape(String(l["text"]))])
	_chat_log.text = "\n".join(lines)


## SPEC 125: the same hue, lifted until it can be seen against the chat's dark panel. Only the swatch
## uses it; the name itself is always the same readable grey.
static func _readable(c: Color) -> Color:
	var out := c
	var lift := 0
	while out.get_luminance() < 0.42 and lift < 8:
		out = out.lightened(0.18)
		lift += 1
	return out


static func _bb_escape(s: String) -> String:
	return s.replace("[", "[lb]").replace("]", "[rb]")


## The SERVERS tab: the directory's list.
func _refresh_servers() -> void:
	if _servers_box == null:
		return
	_servers_status.text = Net.servers_status
	for c in _servers_box.get_children():
		c.queue_free()
	for s in Net.servers_list:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(780, 44)
		row.add_theme_constant_override("separation", 12)
		var same := int(s["protocol"]) == Net.PROTOCOL
		var info := Label.new()
		info.text = "%s   -   %d players   -   %d rooms%s" % [String(s["name"]), int(s["players"]), int(s["rooms"]),
				"" if same else "   (other game version)"]
		info.add_theme_font_size_override("font_size", UiTheme.BODY)     # SPEC 62
		info.custom_minimum_size = Vector2(640, 40)
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info.clip_text = true
		info.tooltip_text = String(s["motd"])
		row.add_child(info)
		var b := Button.new()
		b.text = "Join"
		b.disabled = not same
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(110, 44)
		b.pressed.connect(_join_listed.bind(String(s["url"])))
		row.add_child(b)
		_servers_box.add_child(row)


func _refresh_room() -> void:
	var connected := Net.is_online() and (Net.is_server() or not Net.players.is_empty())
	_no_rivals()              # SPEC 120: a room has no AI in it
	_refresh_board()          # SPEC 120: the leaderboard lives in the room now
	_room_title.text = String(Net.lobby.get("name", ""))
	var code := String(Net.lobby.get("code", ""))
	var dedicated := Net.server_kind == "dedicated" or Net.mode == Net.Mode.DEDICATED
	var public := bool(Net.lobby.get("public", true))
	_room_code.text = ("CODE  %s   %s%s" % [code, "public" if public else "PRIVATE",
			"  +  password" if bool(Net.lobby.get("locked", false)) else ""]) if dedicated and code != "" else ""
	# Players (the leader gets a kick link next to everyone else).
	var lead := Net.is_leader()
	var lines := PackedStringArray()
	var ids := Net.players.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = Net.players[id]
		var col: Color = CarRegistry.get_body_color(String(p["car"]), int(p["color"]))
		var tags := ""
		if int(id) == int(Net.lobby.get("leader", -1)):
			tags += "  [color=#ffd84a](leader)[/color]"
		if int(id) == Net.local_id():
			tags += "  [color=#a8ffa8](you)[/color]"
		elif lead and String(Net.lobby.get("state", "lobby")) == "lobby":
			tags += "  [url=kick:%d][color=#ff8a7a][kick][/color][/url]" % int(id)
		lines.append("[color=#%s]■[/color]  %s  -  %s%s" % [col.to_html(false), String(p["name"]),
				CarRegistry.get_display_name(String(p["car"])), tags])
	if lines.is_empty():
		lines.append("Waiting for the server ..." if not connected else "Nobody here yet.")
	_players_label.text = "\n".join(lines)
	# SPEC 65: the room's scoreboard -- who has won what here, best first, so a room has a story.
	var wins: Dictionary = Net.lobby.get("wins", {})
	if not wins.is_empty():
		var names := wins.keys()
		names.sort_custom(func(a: Variant, b: Variant) -> bool: return int(wins[a]) > int(wins[b]))
		var board := PackedStringArray(["", "[color=#ffd84a]WINS HERE[/color]"])
		for n in names:
			board.append("%s  -  %d" % [String(n), int(wins[n])])
		lines.append_array(board)
		_players_label.text = "\n".join(lines)
	# SPEC 121: no map in the room. A thumbnail of a circuit told nobody anything they could act on, and
	# it was one more box in a screen that was already too full.
	# The setup. SPEC 140: a room is a RACE. The mode toggle is gone, so there is no branch here any
	# more -- a track and a lap count, which is the whole of it.
	_track_button.text = "Track:  %s" % TrackRegistry.get_short_name(String(Net.lobby.get("track", "circle")))
	_laps_button.text = "Laps:  %d" % int(Net.lobby.get("laps", 10))
	_laps_button.visible = true

	_room_public_button.visible = dedicated
	_room_public_button.text = "Room:  %s" % ("public" if public else "private")
	_room_max_button.text = "Players:  up to %d" % int(Net.lobby.get("max", Net.MAX_PLAYERS))
	# The countdown: the setup is frozen, START is CANCEL for the leader and "STARTING" for the rest.
	var counting := String(Net.lobby.get("state", "lobby")) == "countdown"
	for c in _setup_controls:
		if c is Button:
			(c as Button).disabled = not lead or counting
	# A standing room ("Race 3" ...) is its size, always public and open.
	var standing := bool(Net.lobby.get("standing", false))
	if standing:
		for c in [_room_max_button, _room_public_button]:
			if c != null:
				(c as Button).disabled = true
	if counting:
		_start_button.text = "CANCEL" if lead else "STARTING ..."
		_start_button.disabled = not lead
	else:
		_start_button.text = "START RACE"
	if _setup_caption != null:
		_setup_caption.text = "THE RACE"
		_start_button.disabled = not lead or Net.players.is_empty()
	if counting:
		# SPEC 125: a bare number does not say what it is counting down TO. A guest who joined a moment
		# ago has no idea what is starting, or where.
		_setup_note.text = "Starting:  %s" % _setup_summary()
	elif lead:
		_setup_note.text = "You choose the race." \
				+ ("  This room is always here: its size is fixed." if standing else "")
	else:
		# SPEC 125: a guest sees a panel of greyed-out controls and no explanation, which reads as
		# broken rather than as somebody else's job. Say whose job it is, and what is set.
		var leader_name := _leader_name()
		_setup_note.text = "%s chooses and starts it.   %s" % [leader_name, _setup_summary()]
	_tick_countdown()


## SPEC 125: who leads this room, by name.
## SPEC 129: this had never once returned a name. `Net.players` is keyed BY peer id -- iterating it
## walks the ids, so `var d: Dictionary = p` was assigning an int to a Dictionary and throwing, several
## times a second, every time a room view arrived; and the profiles it was searching carry no "id" field
## to match on anyway. Found by `tools/two_clients.sh` on its first run: it needs a second real player
## in a room to happen at all, which is precisely what the suite has never had.
func _leader_name() -> String:
	var who: Dictionary = Net.players.get(int(Net.lobby.get("leader", -1)), {})
	return String(who.get("name", "The leader")) if not who.is_empty() else "The leader"


## SPEC 125: what is actually set, in one line -- the same facts a guest cannot read off disabled
## buttons. Shown to guests, and in the countdown card, so what is about to happen is never a surprise.
func _setup_summary() -> String:
	var setup: Dictionary = Net.lobby.get("setup", {})
	var bits := PackedStringArray()
	bits.append("Race")
	var where := String(setup.get("track", ""))
	if where != "":
		bits.append(where)
	if int(setup.get("laps", 0)) > 0:
		bits.append("%d laps" % int(setup["laps"]))
	bits.append("%d/%d players" % [Net.players.size(), int(Net.lobby.get("max", Net.MAX_PLAYERS))])
	return "  -  ".join(bits)


func _on_player_meta(meta: Variant) -> void:
	var m := String(meta)
	if m.begins_with("kick:"):
		Net.kick(int(m.substr(5)))


# ---------------------------------------------------------------- construction

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	BackgroundArt.add(self, "res://art/bg_grid.png")
	var stripe := ColorRect.new()
	stripe.color = Color(0.13, 0.13, 0.15, 0.85)
	_place(stripe, Rect2(0, 0, 1280, 68))
	add_child(stripe)
	var title := _label("Title", Rect2(24, 8, 600, 52), 34, TITLE_COLOR)
	title.text = "MULTIPLAYER"
	title.add_theme_constant_override("outline_size", 6)
	add_child(title)
	_conn_label = _label("Connection", Rect2(640, 14, 616, 40), 18, Color.WHITE)
	_conn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_conn_label)
	# SPEC 120: under everything. The room's setup panel reaches y 696, and this line used to run
	# straight through it.
	_status = _label("Status", Rect2(24, 700, 1232, 20), 16, Color.WHITE)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)
	var back := _button("BackButton", "Menu",
			Rect2(UiTheme.MARGIN, 720.0 - UiTheme.BUTTON_H - UiTheme.MARGIN, 200, UiTheme.BUTTON_H), 22)
	back.pressed.connect(leave)
	add_child(back)
	_back_button = back
	_build_connect()
	_build_browser()
	_build_room()
	_build_working()
	_build_password_popup()


## SPEC 122: SOMETHING TO LOOK AT WHILE IT CONNECTS. Reconnecting hid all three panels -- the connect
## form, the room browser and the room -- because each of them is shown on a condition that a half-open
## connection fails. What was left was an empty screen with one small grey line at the very bottom, at
## the one moment a player most needs to be told what is happening and given a way out.
##
## This card fills that hole: where we are going, what is being attempted, and CANCEL. It is also the
## right place for a connection that has FAILED, which used to be announced only in that bottom strip.
func _build_working() -> void:
	_working_box = Control.new()
	_working_box.name = "WorkingBox"
	_working_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_working_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_working_box)
	_panel(_working_box, Rect2(340, 220, 600, 260))
	_working_title = _label("WorkingTitle", Rect2(372, 250, 536, 44), 30, TITLE_COLOR)
	_working_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_working_box.add_child(_working_title)
	_working_note = _label("WorkingNote", Rect2(372, 306, 536, 96), 18, SUB_COLOR)
	_working_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_working_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_working_box.add_child(_working_note)
	_working_cancel = _button("WorkingCancel", "CANCEL", Rect2(490, 410, 300, 52), 22)
	_working_cancel.pressed.connect(func() -> void: Net.leave())
	_working_box.add_child(_working_cancel)
	_working_box.visible = false


## What that card says. `_refresh` decides whether it is up at all.
func _refresh_working() -> void:
	var where := String(Net.server_info.get("name", Net.display_address(Net.last_address)))
	if where.strip_edges() == "":
		where = "the server"
	if Net.reconnecting:
		_working_title.text = "RECONNECTING"
		var room := String(Net.lobby.get("name", ""))
		_working_note.text = ("Lost the connection to %s. Trying to get back in%s.  Your place is held "
				+ "while this is going on -- CANCEL to stop trying and go back to the menu.") \
				% [where, " to %s" % room if room != "" else ""]
	else:
		_working_title.text = "CONNECTING"
		_working_note.text = ("Opening a connection to %s.  This takes a moment; CANCEL to stop.") % where


func _build_connect() -> void:
	_connect_box = Control.new()
	_connect_box.name = "ConnectBox"
	_connect_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_connect_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_connect_box)
	# Tabs.
	var x := 24.0
	for t in TABS:
		var b := _button("Tab_%s" % t, String(TAB_NAMES[t]), Rect2(x, 84, 206, 44), 18)
		b.toggle_mode = true
		b.pressed.connect(_select_tab.bind(String(t)))
		_connect_box.add_child(b)
		_tab_buttons[t] = b
		x += 210.0
	# YOU, on the right, for every tab.
	_panel(_connect_box, Rect2(880, 84, 376, 504))
	_connect_box.add_child(_caption("YOU", Rect2(896, 92, 200, 36)))
	_connect_box.add_child(_label("NameCaption", Rect2(896, 136, 340, 28), 16, SUB_COLOR))
	(_connect_box.get_child(_connect_box.get_child_count() - 1) as Label).text = "Your name (everyone sees it)"
	_name_edit = _edit("NameEdit", GameState.get_player_name(), Rect2(896, 166, 344, 44))
	_name_edit.max_length = 16
	_name_edit.text_submitted.connect(func(_t: String) -> void: _save_name())
	_name_edit.focus_exited.connect(_save_name)
	_connect_box.add_child(_name_edit)
	var me_help := _label("MeHelp", Rect2(896, 226, 344, 240), 15, SUB_COLOR)
	me_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	me_help.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	me_help.text = ("Connect first, then pick your car and colour in the room -- everyone there sees what "
			+ "you drive.")
	_connect_box.add_child(me_help)

	var area := Rect2(24, 140, 840, 448)
	# ONLINE: the official server.
	var online := _tab_box("online", area)
	online.add_child(_caption("THE OFFICIAL SERVER", Rect2(40, 152, 500, 36)))
	var addr := _label("OfficialAddress", Rect2(40, 192, 800, 32), 20, Color.WHITE)
	addr.text = Net.OFFICIAL_NAME
	online.add_child(addr)
	var play := _button("PlayOnlineButton", "PLAY ONLINE", Rect2(40, 240, 808, 84), 34)
	play.pressed.connect(_play_official)
	online.add_child(play)
	var ohelp := _label("OnlineHelp", Rect2(40, 340, 808, 230), 16, SUB_COLOR)
	ohelp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ohelp.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# SPEC 122: no AI. SPEC 120 took the rivals count and their skill out of a room -- a multiplayer
	# match is between the people in it -- and this paragraph was still promising them.
	ohelp.text = ("Join the room list: QUICK JOIN drops you into a match that is about to start, or make "
			+ "your own room -- public (anyone can see it) or private (friends join with its 6-letter "
			+ "code), with a password if you like. Whoever makes a room leads it: the track, "
			+ "the laps, how many can join, and START. A room is played between its players; there are no "
			+ "AI rivals in one.")
	online.add_child(ohelp)
	# SERVERS: the directory.
	var servers := _tab_box("servers", area)
	servers.add_child(_caption("SERVERS", Rect2(40, 152, 300, 36)))
	var refresh := _button("RefreshServers", "Refresh", Rect2(708, 148, 140, 44), 18)
	refresh.pressed.connect(func() -> void: Net.fetch_servers())
	servers.add_child(refresh)
	_servers_status = _label("ServersStatus", Rect2(40, 196, 808, 28), 16, SUB_COLOR)
	servers.add_child(_servers_status)
	var sscroll := ScrollContainer.new()
	_place(sscroll, Rect2(40, 230, 808, 346))
	servers.add_child(sscroll)
	_servers_box = VBoxContainer.new()
	_servers_box.name = "ServerRows"
	_servers_box.add_theme_constant_override("separation", 6)
	sscroll.add_child(_servers_box)
	# DIRECT: by address.
	var direct := _tab_box("direct", area)
	direct.add_child(_caption("SERVER ADDRESS", Rect2(40, 152, 400, 36)))
	_ip_edit = _edit("IpEdit", String(GameState.settings.get("mp_address", "127.0.0.1")), Rect2(40, 196, 560, 48))
	_ip_edit.text_submitted.connect(func(_t: String) -> void: _join())
	direct.add_child(_ip_edit)
	_port_edit = _edit("PortEdit", str(Net.DEFAULT_PORT), Rect2(612, 196, 236, 48))
	direct.add_child(_port_edit)
	var join := _button("JoinButton", "Join", Rect2(40, 262, 808, 64), 26)
	join.pressed.connect(_join)
	direct.add_child(join)
	var dhelp := _label("DirectHelp", Rect2(40, 344, 808, 230), 16, SUB_COLOR)
	dhelp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dhelp.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	dhelp.text = ("An IP or name with a port (192.168.1.20 and 7777), or a full address: "
			+ "wss://rope.thenakedcat.games/ws. The web version needs a wss:// server (a secure one).")
	direct.add_child(dhelp)
	# HOST: be the server.
	var host_box := _tab_box("host", area)
	host_box.add_child(_caption("HOST A GAME", Rect2(40, 152, 400, 36)))
	host_box.add_child(_label("HostPortCaption", Rect2(40, 196, 200, 48), 18, SUB_COLOR))
	(host_box.get_child(host_box.get_child_count() - 1) as Label).text = "Port"
	_host_port_edit = _edit("HostPortEdit", str(Net.DEFAULT_PORT), Rect2(160, 196, 200, 48))
	host_box.add_child(_host_port_edit)
	var host := _button("HostButton", "Host game", Rect2(40, 262, 808, 64), 26)
	host.pressed.connect(_host)
	# A browser cannot listen for connections: the web build joins only.
	host.disabled = OS.has_feature("web")
	host_box.add_child(host)
	var hhelp := _label("HostHelp", Rect2(40, 344, 808, 230), 16, SUB_COLOR)
	hhelp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hhelp.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	hhelp.text = ("You play and your computer is the server: friends on your network use DIRECT with your "
			+ "IP address. Over the internet your port (TCP 7777) must be forwarded on the router, or use "
			+ "a virtual LAN (Tailscale, ZeroTier). For a server that is always on, see deploy/README.md.")
	host_box.add_child(hhelp)


func _tab_box(t: String, r: Rect2) -> Control:
	var box := Control.new()
	box.name = "Tab%sBox" % String(t).capitalize()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_connect_box.add_child(box)
	_panel(box, r)
	_tab_boxes[t] = box
	return box


## Three panels: ROOMS (the list, QUICK JOIN), the LEADERBOARD, and NEW ROOM + JOIN BY CODE -- so making
## a room of your own is always on screen next to the rooms that exist.
func _build_browser() -> void:
	_browser_box = Control.new()
	_browser_box.name = "BrowserBox"
	_browser_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_browser_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_browser_box)
	_panel(_browser_box, Rect2(24, 84, 808, 504))
	_browser_box.add_child(_caption("ROOMS", Rect2(40, 92, 200, 36)))
	var quick := _button("QuickJoinButton", "QUICK JOIN", Rect2(328, 88, 200, 44), 18)
	quick.pressed.connect(func() -> void: Net.quick_join())
	_browser_box.add_child(quick)
	# SPEC 122: THE LIST FILLS THE PANEL. The panel is 808 px wide and the window that showed the rooms
	# was 488, while every row demanded 776 -- so the JOIN button of every room sat off the right-hand
	# side of a window with 300 px of unused panel beside it. The window is the panel's inner width now,
	# sideways scrolling is switched OFF (which makes Godot size the rows to the window instead of the
	# other way round), and the rows are built to stretch.
	var scroll := ScrollContainer.new()
	_place(scroll, Rect2(40, 138, 776, 436))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_browser_box.add_child(scroll)
	_rooms_box = VBoxContainer.new()
	_rooms_box.name = "Rooms"
	_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_rooms_box)

	# SPEC 120: the leaderboard is NOT here any more -- "remove the leaderboard in the lobby selection;
	# leaderboard only for lobby". It is a thing about the people you are playing WITH, so it lives in
	# the room (`_build_room`), and this screen is for finding a room. The panel it used to fill now
	# belongs to the room list, which is what a player came here to read.
	_panel(_browser_box, Rect2(856, 84, 400, 504))
	_browser_box.add_child(_caption("NEW ROOM", Rect2(872, 92, 300, 36)))
	_room_name_edit = _edit("RoomNameEdit", "", Rect2(872, 134, 368, 44))
	_room_name_edit.placeholder_text = "Room name"
	_room_name_edit.max_length = 28
	_browser_box.add_child(_room_name_edit)
	_public_button = _button("PublicButton", "", Rect2(872, 186, 178, 44), 17)
	_public_button.pressed.connect(func() -> void:
		_room_public = not _room_public
		_refresh_new_room())
	_browser_box.add_child(_public_button)
	_max_button = _button("MaxButton", "", Rect2(1062, 186, 178, 44), 17)
	_max_button.pressed.connect(func() -> void:
		_room_max = Net.MIN_ROOM_PLAYERS + (_room_max - Net.MIN_ROOM_PLAYERS + 1) % (Net.MAX_PLAYERS - Net.MIN_ROOM_PLAYERS + 1)
		_refresh_new_room())
	_browser_box.add_child(_max_button)
	_room_pw_edit = _edit("RoomPasswordEdit", "", Rect2(872, 238, 368, 44))
	_room_pw_edit.placeholder_text = "Password (optional)"
	_room_pw_edit.secret = true
	_room_pw_edit.max_length = 24
	_browser_box.add_child(_room_pw_edit)
	var create := _button("CreateRoomButton", "CREATE ROOM", Rect2(872, 290, 368, 52), 22)
	create.pressed.connect(_create_room)
	_browser_box.add_child(create)
	_browser_box.add_child(_caption("JOIN BY CODE", Rect2(872, 366, 300, 36)))
	_code_edit = _edit("CodeEdit", "", Rect2(872, 408, 178, 44))
	_code_edit.placeholder_text = "ABC234"
	_code_edit.max_length = Net.CODE_LENGTH
	_code_edit.text_submitted.connect(func(_t: String) -> void: _join_by_code())
	_browser_box.add_child(_code_edit)
	_code_pw_edit = _edit("CodePasswordEdit", "", Rect2(1062, 408, 178, 44))
	_code_pw_edit.placeholder_text = "Password"
	_code_pw_edit.secret = true
	_browser_box.add_child(_code_pw_edit)
	var by_code := _button("JoinCodeButton", "JOIN BY CODE", Rect2(872, 460, 368, 52), 22)
	by_code.pressed.connect(_join_by_code)
	_browser_box.add_child(by_code)
	_refresh_new_room()


func _refresh_new_room() -> void:
	_public_button.text = "Public" if _room_public else "Private (code)"
	_max_button.text = "Up to %d players" % _room_max


## SPEC 121: THE ROOM, in three columns and a bench. PLAYERS on the left, the server's LEADERBOARD in
## the middle (between the players and the chat, where it reads as "these people, ranked"), the CHAT on
## the right, and the race setup in one wide panel underneath all three. No map: the track has a name,
## and the picture of it told nobody anything they could act on.
func _build_room() -> void:
	_room_box = Control.new()
	_room_box.name = "RoomBox"
	_room_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_room_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_room_box)

	# --- left: who is here
	_panel(_room_box, Rect2(24, 84, 380, 392))
	_room_box.add_child(_caption("PLAYERS", Rect2(40, 92, 200, 36)))
	_room_title = _label("RoomName", Rect2(200, 92, 188, 36), 18, Color.WHITE)
	_room_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_room_title.clip_text = true
	_room_box.add_child(_room_title)
	_room_code = _label("RoomCode", Rect2(40, 126, 348, 28), 17, TITLE_COLOR)
	_room_code.clip_text = true
	_room_box.add_child(_room_code)
	_players_label = RichTextLabel.new()
	_players_label.name = "Players"
	_players_label.bbcode_enabled = true
	_players_label.meta_underlined = false
	_players_label.add_theme_font_size_override("normal_font_size", UiTheme.BODY)
	_players_label.meta_clicked.connect(_on_player_meta)
	_place(_players_label, Rect2(40, 160, 348, 304))
	_room_box.add_child(_players_label)

	# --- middle: the same people, ranked
	_panel(_room_box, Rect2(420, 84, 380, 392))
	# SPEC 122: this is the SERVER's ranking, over everyone who has ever played on it; the players panel
	# beside it counts wins in THIS room. Two different populations, so two different words.
	_room_box.add_child(_caption("SERVER RANKING", Rect2(436, 92, 300, 36)))
	_board_status = _label("BoardStatus", Rect2(436, 126, 348, 24), 15, SUB_COLOR)
	_room_box.add_child(_board_status)
	# SPEC 122: same defect, same fix -- rows demanded 424 px in a 348 px window, so the POINTS column
	# (the only number on the board) was off the side of it.
	var bscroll := ScrollContainer.new()
	_place(bscroll, Rect2(436, 156, 348, 308))
	bscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_room_box.add_child(bscroll)
	_board_box = VBoxContainer.new()
	_board_box.name = "Board"
	_board_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_box.add_theme_constant_override("separation", 2)
	bscroll.add_child(_board_box)

	# --- right: the chat
	_panel(_room_box, Rect2(816, 84, 440, 392))
	_room_box.add_child(_caption("CHAT", Rect2(832, 92, 300, 36)))
	_chat_log = RichTextLabel.new()
	_chat_log.name = "ChatLog"
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.add_theme_font_size_override("normal_font_size", UiTheme.CAPTION)
	_place(_chat_log, Rect2(832, 128, 408, 280))
	_room_box.add_child(_chat_log)
	_chat_edit = _edit("ChatEdit", "", Rect2(832, 416, 292, 48))
	_chat_edit.placeholder_text = "Say something ..."
	_chat_edit.max_length = Net.CHAT_MAX
	_chat_edit.text_submitted.connect(func(_t: String) -> void: _send_chat())
	_room_box.add_child(_chat_edit)
	var send := _button("ChatSendButton", "SEND", Rect2(1132, 416, 108, 48), 18)
	send.pressed.connect(_send_chat)
	_room_box.add_child(send)

	# --- below, the full width: what is being raced, and the button that starts it
	_panel(_room_box, Rect2(24, 492, 1232, 204))
	# SPEC 122: the caption; `_refresh_room` sets it.
	# SPEC 130: the note used to start at x 240 while the caption ran to x 280. "THE RACE" is short
	# enough not to reach it; "THE STUNT MATCH" was not, and half the rooms were stunt matches -- so the
	# heading and the sentence beside it sat on top of each other in exactly the mode where the sentence
	# mattered most. The note starts clear of the caption now and still stops short of the right column.
	_setup_caption = _caption("THE RACE", Rect2(40, 498, 256, 32))
	_room_box.add_child(_setup_caption)
	_setup_note = _label("SetupNote", Rect2(304, 500, 556, 28), 16, SUB_COLOR)
	_room_box.add_child(_setup_note)
	# SPEC 140: the MODE button is gone -- every room is a race -- and the row closes up behind it
	# rather than leaving the hole it used to sit in. The track gets the width the mode button had.
	_track_button = _button("TrackButton", "", Rect2(40, 532, 470, 48), 19)
	_track_button.pressed.connect(_cycle_track)
	_room_box.add_child(_track_button)
	_laps_button = _button("LapsButton", "", Rect2(526, 532, 150, 48), 19)
	_laps_button.pressed.connect(_cycle_laps)
	_room_box.add_child(_laps_button)
	_room_max_button = _button("RoomMaxButton", "", Rect2(692, 532, 200, 48), 17)
	_room_max_button.pressed.connect(func() -> void:
		var m := int(Net.lobby.get("max", Net.MAX_PLAYERS))
		m = Net.MIN_ROOM_PLAYERS + (m - Net.MIN_ROOM_PLAYERS + 1) % (Net.MAX_PLAYERS - Net.MIN_ROOM_PLAYERS + 1)
		Net.request_setup({"max": m}))
	_room_box.add_child(_room_max_button)
	_room_public_button = _button("RoomPublicButton", "", Rect2(40, 592, 210, 48), 18)
	_room_public_button.pressed.connect(func() -> void:
		Net.request_setup({"public": not bool(Net.lobby.get("public", true))}))
	_room_box.add_child(_room_public_button)
	_car_button = _button("CarButton", "", Rect2(266, 592, 240, 48), 18)
	_car_button.pressed.connect(_choose_car)
	_room_box.add_child(_car_button)
	_color_button = _button("ChooseCarButton", "CHOOSE CAR  >", Rect2(522, 592, 200, 48), 18)
	_color_button.pressed.connect(_choose_car)
	_room_box.add_child(_color_button)
	# SPEC 121: your name, and it cannot be longer than the board can show (GameState.MAX_NAME_LENGTH).
	_my_name_edit = _edit("MyNameEdit", GameState.get_player_name(), Rect2(738, 592, 300, 48))
	_my_name_edit.max_length = GameState.MAX_NAME_LENGTH
	_my_name_edit.placeholder_text = "Your name (max %d)" % GameState.MAX_NAME_LENGTH
	_my_name_edit.text_submitted.connect(func(_t: String) -> void: _save_room_name())
	_my_name_edit.focus_exited.connect(_save_room_name)
	_room_box.add_child(_my_name_edit)
	# SPEC 121: START had 86 px of width for "START RACE" and clipped it. It is the biggest thing on the
	# panel now, which is also what it deserves to be.
	_start_button = _button("StartButton", "START RACE", Rect2(1054, 532, 186, 108), 22)
	_start_button.pressed.connect(_start_or_cancel)
	_room_box.add_child(_start_button)
	# SPEC 120: NO AI IN A ROOM -- a multiplayer race is between the players in it.
	_setup_controls.append_array([_track_button, _laps_button, _room_max_button, _room_public_button])

	# The countdown, big in the middle of the screen, only while it runs (SPEC 113: on a card of its own).
	_countdown_box = Control.new()
	_countdown_box.name = "CountdownBox"
	_countdown_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_countdown_box.visible = false
	_countdown_box.z_index = 60
	_place(_countdown_box, Rect2(440, 216, 400, 260))
	_room_box.add_child(_countdown_box)
	var cd_back := ColorRect.new()
	cd_back.name = "Back"
	cd_back.color = Color(0.09, 0.10, 0.12, 1.0)
	cd_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(cd_back, Rect2(0, 0, 400, 260))
	_countdown_box.add_child(cd_back)
	var cd_edge := ReferenceRect.new()
	cd_edge.name = "Edge"
	cd_edge.border_color = Color(0.45, 0.47, 0.52)
	cd_edge.border_width = 2.0
	cd_edge.editor_only = false
	cd_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(cd_edge, Rect2(0, 0, 400, 260))
	_countdown_box.add_child(cd_edge)
	var cd_caption := _caption("STARTING IN", Rect2(0, 18, 400, 36))
	cd_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_box.add_child(cd_caption)
	_countdown_label = Label.new()
	_countdown_label.name = "CountdownLabel"
	_countdown_label.add_theme_font_size_override("font_size", 140)
	_countdown_label.add_theme_color_override("font_color", TITLE_COLOR)
	_countdown_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_countdown_label.add_theme_constant_override("outline_size", 14)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_label.visible = false
	_place(_countdown_label, Rect2(0, 54, 400, 200))
	_countdown_box.add_child(_countdown_label)


func _build_password_popup() -> void:
	_pw_popup = Control.new()
	_pw_popup.name = "PasswordPopup"
	_pw_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pw_popup.visible = false
	add_child(_pw_popup)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pw_popup.add_child(shade)
	var box := ColorRect.new()
	box.color = Color(0.1, 0.1, 0.12, 0.97)
	_place(box, Rect2(390, 250, 500, 210))
	_pw_popup.add_child(box)
	# SPEC 125: the dialog says WHICH room, stays open while the server is asked, and shows a refusal
	# inside itself. It used to hide the instant Join was pressed and route "Wrong password" to the
	# status strip at the very bottom of the screen -- so the player was back on the room list with the
	# room they wanted still locked and an explanation forty rows away.
	_pw_title = _caption("", Rect2(410, 262, 460, 36))
	_pw_popup.add_child(_pw_title)
	_pw_popup_edit = _edit("PopupPasswordEdit", "", Rect2(410, 310, 460, 44))
	_pw_popup_edit.secret = true
	_pw_popup_edit.placeholder_text = "Password"
	_pw_popup_edit.text_submitted.connect(func(_t: String) -> void: _join_with_password())
	_pw_popup.add_child(_pw_popup_edit)
	_pw_note = _label("PopupNote", Rect2(410, 356, 460, 24), 15, UiTheme.WARN)
	_pw_popup.add_child(_pw_note)
	_pw_join = _button("PopupJoin", "Join", Rect2(410, 386, 225, 56), 22)
	_pw_join.pressed.connect(_join_with_password)
	_pw_popup.add_child(_pw_join)
	var cancel := _button("PopupCancel", "Cancel", Rect2(645, 386, 225, 56), 22)
	cancel.pressed.connect(_close_password)
	_pw_popup.add_child(cancel)


func _panel(parent: Control, r: Rect2) -> void:
	var p := ColorRect.new()
	p.color = PANEL_COLOR
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(p, r)
	parent.add_child(p)


func _caption(text: String, r: Rect2) -> Label:
	var l := _label("Caption", r, 20, CAPTION_COLOR)
	l.text = text
	return l


func _label(node_name: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.name = node_name
	l.add_theme_font_size_override("font_size", UiTheme.snap_size(font_size))    # SPEC 62
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(l, rect)
	return l


## SPEC 128: these used to be built FOCUS_NONE, every one of them -- so the lobby, which is the one
## screen in the game a player actually TYPES on, could not be reached from the keyboard at all. Tab
## walks it in reading order now (`_order_focus`), and nothing about using it with a pointer changed.
func _button(node_name: String, text: String, rect: Rect2, font_size: int) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", UiTheme.snap_size(font_size))    # SPEC 62
	_place(b, rect)
	return b


func _edit(node_name: String, text: String, rect: Rect2) -> LineEdit:
	var e := LineEdit.new()
	e.name = node_name
	e.text = text
	e.add_theme_font_size_override("font_size", UiTheme.BODY)   # SPEC 62
	_place(e, rect)
	return e


func _style_swatch(b: Button, c: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = c
	box.set_border_width_all(2)
	box.border_color = Color(1, 1, 1, 0.6)
	box.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", box)
	b.add_theme_color_override("font_color", Color.BLACK if c.get_luminance() > 0.6 else Color.WHITE)


func _place(c: Control, r: Rect2) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.end.x
	c.offset_bottom = r.end.y
