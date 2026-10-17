extends Node
## Global game state (autoload "GameState").
## Holds the selected track, race constants, persistent records and scene switching helpers.
## NOTE: only UI/flow scripts (group C) may reference GameState. Car/Track/LapTracker must not,
## so they stay usable from `--script` test runs.

## Default race length. Per-track lap counts live in TrackRegistry (SPEC 14.4); this is the fallback
## and is still what the tests pin.
const LAPS := 3
const MENU_SCENE := "res://scenes/main_menu.tscn"
const SELECT_SCENE := "res://scenes/track_select.tscn"
const CAR_SELECT_SCENE := "res://scenes/car_select.tscn"
const MAX_OPPONENTS := 4
const DIFFICULTIES := ["easy", "medium", "hard"]
## The rivals' personalities (SPEC 42): every rival is dealt one at random. (AIDriver.ALL_PERSONALITIES)
const PROFILES := ["pro", "hothead", "drifter", "bully", "rookie", "wildcard"]
## Old style names still accepted (a saved line-up, an older lobby): AIDriver maps them.
const PROFILE_ALIASES := ["clean", "aggressive"]
const RACE_SCENE := "res://scenes/race.tscn"
const RECORDS_PATH := "user://records.cfg"
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
const HELP_SCENE := "res://scenes/help.tscn"
const GARAGE_SCENE := "res://scenes/garage.tscn"
const DEFAULT_SETTINGS := {
	"player_name": "Player",
	"fullscreen": false,
	"music_volume": 0.7,
	"sfx_volume": 0.9,
	# SPEC 63: the FPS counter, the practice unlock and the close camera lost their toggles (the wheel
	# zooms now, and there is a How to play screen instead). The keys stay, for the tools and the tests.
	"show_fps": false,
	# SPEC 50: the close camera -- the view rides with the car instead of showing the whole track at once.
	"close_camera": false,
	# SPEC 54: fewer particles, fewer model refreshes and a 60 fps cap, for a machine that needs them.
	"low_graphics": true,     # SPEC 63: on by default -- nobody wants to be asked
	# SPEC 56: opens every track without winning your way there. For practice and for testing a track --
	# it pays no coins and unlocks nothing, it only lets you drive.
	"unlock_all": false,
	# SPEC 126: CALM. The camera shake is a cue, and for some players it is also the reason the game
	# cannot be played for long. This turns the SPECTACLE down without removing anything a player has
	# to see: the shake is a quarter, and every warning, chip and status line is untouched.
	"calm_effects": false,
	"rivals": 2,
	"rival_difficulty": "medium",
	# SPEC 110: a race is 3-4 laps ("no classic one-screen racer runs ten"); ENDURANCE is the track's
	# own count (ten), on the track screen's button.
	"endurance": false,
	# Multiplayer (SPEC 43): the last DIRECT address, the last tab, and this install's reconnect token.
	"mp_address": "127.0.0.1",
	"mp_tab": "online",
	# SPEC 113: the build whose release notes the player has seen (they open once for a new build).
	"seen_version": "",
	"player_token": "",
}
const MAX_NAME_LENGTH := 16
const MAX_FPS := 144
const LOW_MAX_FPS := 60
## SPEC 54: live puffs per car's effects. The rivals get fewer than the player either way -- their dust
## is scenery, yours is feedback.
const PUFFS_FULL := 90
const PUFFS_LOW := 36
const PUFFS_RIVAL_SHARE := 0.6


## The puff pool a car's effects should use, given the graphics setting (SPEC 54).
func puff_budget(is_player: bool) -> int:
	var base: int = PUFFS_LOW if bool(settings.get("low_graphics", false)) else PUFFS_FULL
	return base if is_player else int(base * PUFFS_RIVAL_SHARE)

## Currently selected track id; any id in TrackRegistry.
var selected_track: String = TrackRegistry.DEFAULT_ID
## Currently selected car id; any id in CarRegistry.
var selected_car: String = CarRegistry.DEFAULT_ID
## Index into CarRegistry.get_palette(selected_car).
var selected_color: int = 0
## How many AI rivals (0 = a solo time trial, up to MAX_OPPONENTS).
var opponent_count: int = 2
## One entry per possible rival: {"car": "random" | car id, "color": -1 (random) | palette index,
## "difficulty": "easy" | "medium" | "hard", "profile": "clean" | "aggressive"}.
var opponents: Array = []
## When > 0, every race is this many laps instead of the track's own count (the test suite runs the
## 3-lap reference races with it).
var laps_override: int = 0
## Player settings (DEFAULT_SETTINGS keys), saved to `settings_path`. Tests point it elsewhere.
var settings: Dictionary = DEFAULT_SETTINGS.duplicate()
var settings_path: String = SETTINGS_PATH
var _fps_layer: CanvasLayer = null
var _fps_label: Label = null
## Path used for records; tests may override it before calling load/save.
var records_path: String = RECORDS_PATH
## { record_key: { "best_lap": float, "best_total": float } } — missing key / INF means no record.
## The key is the track id for the default car (so records written before cars existed stay the Sport's)
## and "<track>@<car>" for every other car: lap times of different cars are never mixed.
var records: Dictionary = {}
## SPEC 56: the career -- coins, the tracks won, the cars, colours, effects and upgrades owned.
var profile := Profile.new()


func _init() -> void:
	for i in MAX_OPPONENTS:
		opponents.append({"car": "random", "color": -1, "difficulty": "medium", "profile": "random"})


func _ready() -> void:
	load_records()
	profile.load_from_disk()
	load_settings()
	apply_settings()
	# The race setup the player chose last time (the track screen's RIVALS / DIFFICULTY).
	opponent_count = clampi(int(settings["rivals"]), 0, MAX_OPPONENTS)
	_fill_opponents(String(settings["rival_difficulty"]))


func _process(_delta: float) -> void:
	if _fps_label != null and _fps_label.visible:
		_fps_label.text = "%d fps" % Engine.get_frames_per_second()


# ---------------------------------------------------------------- settings

func load_settings() -> void:
	settings = DEFAULT_SETTINGS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	for key in DEFAULT_SETTINGS.keys():
		if cfg.has_section_key("settings", key):
			var v: Variant = cfg.get_value("settings", key)
			if typeof(v) == typeof(DEFAULT_SETTINGS[key]) or (DEFAULT_SETTINGS[key] is float and v is int):
				settings[key] = v
	settings["player_name"] = sanitize_name(String(settings["player_name"]))
	settings["music_volume"] = clampf(float(settings["music_volume"]), 0.0, 1.0)
	settings["sfx_volume"] = clampf(float(settings["sfx_volume"]), 0.0, 1.0)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in settings.keys():
		cfg.set_value("settings", key, settings[key])
	var err := cfg.save(settings_path)
	if err != OK:
		push_warning("GameState: could not save settings to %s (error %d)" % [settings_path, err])


func set_setting(key: String, value: Variant) -> void:
	if not DEFAULT_SETTINGS.has(key):
		return
	if key == "player_name":
		value = sanitize_name(String(value))
	settings[key] = value
	apply_settings()
	save_settings()


func get_setting(key: String) -> Variant:
	return settings.get(key, DEFAULT_SETTINGS.get(key))


func get_player_name() -> String:
	return String(settings.get("player_name", "Player"))


## Printable, trimmed, at most MAX_NAME_LENGTH characters; "Player" when nothing is left.
static func sanitize_name(n: String) -> String:
	var out := ""
	for ch in n.strip_edges():
		if ch.unicode_at(0) >= 32 and ch != "[" and ch != "]":
			out += ch
	out = out.substr(0, MAX_NAME_LENGTH).strip_edges()
	return out if out != "" else "Player"


## Pushes the settings to the window, the audio and the FPS counter. Window changes are skipped in a
## headless run (there is no window).
func apply_settings() -> void:
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		var want_full := bool(settings["fullscreen"])
		var mode := DisplayServer.window_get_mode()
		var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if want_full and not is_full:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not want_full and is_full:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		# No VSync (SPEC 45): the frame rate is capped instead, so a menu does not run the GPU flat out.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		# SPEC 54: a weak machine gains nothing from being asked for 144 frames a second.
		Engine.max_fps = LOW_MAX_FPS if bool(settings["low_graphics"]) else MAX_FPS
	# How many rival car models may re-render their 3D viewport in one frame (the player's never waits).
	CarModel3D.renders_per_frame = 1 if bool(settings["low_graphics"]) else 2
	var audio := get_node_or_null("/root/Audio")
	if audio != null and audio.has_method("set_volumes"):
		audio.set_volumes(float(settings["music_volume"]), float(settings["sfx_volume"]))
	if _fps_layer == null:
		_fps_layer = CanvasLayer.new()
		_fps_layer.layer = 100
		add_child(_fps_layer)
		_fps_label = Label.new()
		_fps_label.position = Vector2(1196, 698)    # SPEC 108: bottom right, off the dashboard
		_fps_label.add_theme_font_size_override("font_size", 14)
		_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_fps_label.add_theme_constant_override("outline_size", 3)
		_fps_layer.add_child(_fps_label)
	_fps_label.visible = bool(settings["show_fps"])


func go_to_settings() -> void:
	_change_scene(SETTINGS_SCENE)


## How to play (SPEC 63).
func go_to_help() -> void:
	_change_scene(HELP_SCENE)


## The garage (SPEC 64): parts, colours, effects and profiles for the car you have chosen.
func go_to_garage() -> void:
	_change_scene(GARAGE_SCENE)


# ---------------------------------------------------------------- the career (SPEC 56)

## SPEC 117: every track is open, always. Kept because the track screen and the lobby both ask.
func is_track_unlocked(_track_id: String, _difficulty: String = "") -> bool:
	return true


## SPEC 117: the stars a track carries -- 1 for a win on easy, 2 on medium, 3 on hard.
func track_stars(track_id: String) -> int:
	return profile.track_stars(track_id)


func get_coins() -> int:
	return profile.coins


func save_profile() -> void:
	profile.save()


## Pays for a finished race and opens whatever it opened (SPEC 56). Returns what was earned, for the
## finish screen to show: {coins, unlocked, first_win, gold}.
func reward_race(track_id: String, place: int, rivals: int, gold_car: String = "") -> Dictionary:
	var out: Dictionary = profile.finish_race(track_id, get_rival_difficulty(), place, rivals, gold_car)
	if int(out["coins"]) > 0:
		save_profile()
	return out


# ---------------------------------------------------------------- tracks

## Every track id, in registry (display) order. Replaces the old `TRACK_IDS` constant.
static func track_ids() -> PackedStringArray:
	return TrackRegistry.ids()


func is_valid_track(track_id: String) -> bool:
	return TrackRegistry.has(track_id)


func get_track_name(track_id: String) -> String:
	return TrackRegistry.get_short_name(track_id)


## Race length for a track (SPEC 14.4). Unknown ids fall back to LAPS.
func get_laps(track_id: String) -> int:
	if laps_override > 0:
		return laps_override
	if bool(settings.get("endurance", false)):
		return TrackRegistry.get_laps(track_id)
	return sprint_laps(track_id)


## SPEC 110: the sprint distance -- four laps of a short track, three of a long one, two of a very
## long one (the Serpent's 500 m).
static func sprint_laps(track_id: String) -> int:
	var m := float(TrackRegistry.get_stats(track_id).get("length_m", 0.0))
	return 4 if m < 250.0 else (3 if m < 400.0 else 2)


func is_endurance() -> bool:
	return bool(settings.get("endurance", false))


func set_endurance(on: bool) -> void:
	set_setting("endurance", on)


## SPEC 110: coins earned inside a race beyond the finish (the spins' purse).
func add_coins(n: int) -> void:
	if n <= 0:
		return
	profile.coins += n
	save_profile()


## The records field for a race of `laps` laps: best-race totals are only comparable at the same lap
## count, so every count has its own ("best_total" is the original 3-lap one). Best laps are shared.
static func total_field(laps: int) -> String:
	return "best_total" if laps == 3 else "best_total_%d" % laps


# ---------------------------------------------------------------- records

## The records.cfg section for a track + car.
static func record_key(track_id: String, car_id: String = CarRegistry.DEFAULT_ID) -> String:
	var car := CarRegistry.resolve(car_id)
	return track_id if car == CarRegistry.DEFAULT_ID else "%s@%s" % [track_id, car]


func _all_record_keys() -> PackedStringArray:
	var keys := PackedStringArray()
	for id in TrackRegistry.ids():
		for car in CarRegistry.ids():
			keys.append(record_key(id, car))
	return keys


func load_records() -> void:
	records.clear()
	var keys := _all_record_keys()
	for k in keys:
		records[k] = {"best_lap": INF, "best_total": INF}
	var cfg := ConfigFile.new()
	var err := cfg.load(records_path)
	if err != OK:
		return  # no file yet (or unreadable) -> empty records
	for k in keys:
		if not cfg.has_section(k):
			continue
		for key in cfg.get_section_keys(k):
			if key == "best_lap" or key.begins_with("best_total"):
				records[k][key] = _sanitize_record(cfg.get_value(k, key))


## Accepts only finite, positive int/float record values; anything else (strings, arrays, 0, negative,
## inf/nan) is treated as "no record" (INF).
static func _sanitize_record(value: Variant) -> float:
	var t := typeof(value)
	if t != TYPE_FLOAT and t != TYPE_INT:
		return INF
	var f := float(value)
	if not is_finite(f) or f <= 0.0:
		return INF
	return f


func save_records() -> void:
	# Load first, then overwrite only the sections we own. Building a fresh ConfigFile destroyed every
	# section for an id the current registry does not list, so the first record set after a track was
	# renamed or removed silently deleted that track's saved times (decision 30.13).
	var cfg := ConfigFile.new()
	cfg.load(records_path)
	for id in records.keys():
		var r: Dictionary = records[id]
		for key in r.keys():
			if is_finite(float(r[key])):
				cfg.set_value(id, key, r[key])
			elif cfg.has_section_key(id, key):
				cfg.erase_section_key(id, key)
	var err := cfg.save(records_path)
	if err != OK:
		push_warning("GameState: could not save records to %s (error %d)" % [records_path, err])


## `car_id` "" means the currently selected car.
func get_best_lap(track_id: String, car_id: String = "") -> float:
	return float(records.get(_key_for(track_id, car_id), {}).get("best_lap", INF))


## `laps` -1 means the lap count this track is raced over now.
func get_best_total(track_id: String, car_id: String = "", laps: int = -1) -> float:
	var field := total_field(get_laps(track_id) if laps < 0 else laps)
	return float(records.get(_key_for(track_id, car_id), {}).get(field, INF))


func _key_for(track_id: String, car_id: String) -> String:
	return record_key(track_id, selected_car if car_id.is_empty() else car_id)


## Records a finished race for `car_id` ("" = the selected car).
## Returns {"new_best_lap": bool, "new_best_total": bool}. Saves to disk when anything improved.
func submit_result(track_id: String, total_time: float, lap_times: Array, car_id: String = "") -> Dictionary:
	var rkey := _key_for(track_id, car_id)
	if not records.has(rkey):
		records[rkey] = {"best_lap": INF, "best_total": INF}
	var result := {"new_best_lap": false, "new_best_total": false}
	# Written values go through the same filter as read ones, so a record can never be stored that
	# load_records() would then silently discard.
	var best_lap_this_race := INF
	for t in lap_times:
		best_lap_this_race = minf(best_lap_this_race, _sanitize_record(t))
	if best_lap_this_race < get_best_lap(track_id, car_id):
		records[rkey]["best_lap"] = best_lap_this_race
		result["new_best_lap"] = true
	var total := _sanitize_record(total_time)
	if total < get_best_total(track_id, car_id, lap_times.size()):
		records[rkey][total_field(lap_times.size())] = total
		result["new_best_total"] = true
	if result["new_best_lap"] or result["new_best_total"]:
		save_records()
	return result


# ---------------------------------------------------------------- formatting

## Formats seconds as "m:ss.mmm"; non-finite or negative values give "-:--.---".
static func format_time(seconds: float) -> String:
	if not is_finite(seconds) or seconds < 0.0:
		return "-:--.---"
	var total_ms := int(round(seconds * 1000.0))
	var minutes := total_ms / 60000
	var secs := (total_ms / 1000) % 60
	var ms := total_ms % 1000
	return "%d:%02d.%03d" % [minutes, secs, ms]


# ---------------------------------------------------------------- scene flow

func go_to_menu() -> void:
	_change_scene(MENU_SCENE)


## The track select screen (SPEC 16.1): the title menu's "Race" button, and where the pause / finish
## "Tracks" button lands.
func go_to_track_select() -> void:
	_change_scene(SELECT_SCENE)


func select_car(car_id: String) -> void:
	var id := CarRegistry.resolve(car_id)
	if id != selected_car:
		selected_color = 0
	selected_car = id


func select_color(index: int) -> void:
	selected_color = posmod(index, CarRegistry.PALETTE_SIZE)


func set_opponent_count(n: int) -> void:
	opponent_count = clampi(n, 0, MAX_OPPONENTS)
	settings["rivals"] = opponent_count
	save_settings()


## One difficulty for the whole field (the track screen's simple setup): random cars, colours and driving
## style (clean or aggressive). Remembered in the settings.
func set_rival_difficulty(level: String) -> void:
	if not DIFFICULTIES.has(level):
		return
	_fill_opponents(level)
	settings["rival_difficulty"] = level
	save_settings()


func get_rival_difficulty() -> String:
	return String(settings.get("rival_difficulty", "medium"))


func _fill_opponents(level: String) -> void:
	if not DIFFICULTIES.has(level):
		level = "medium"
	for i in MAX_OPPONENTS:
		opponents[i] = {"car": "random", "color": -1, "difficulty": level, "profile": "random"}


## A driving style: `wanted` if it is a real one, else a random pick ("random").
## SPEC 143: `dealt` is what the rest of the field already has -- a random pick never repeats one while
## there is a personality left to deal, so a three-rival race is three DIFFERENT rivals (it used to be
## two hotheads and a bully one race in four).
static func pick_profile(wanted: String, rng: RandomNumberGenerator, dealt: Array = []) -> String:
	if PROFILES.has(wanted) or PROFILE_ALIASES.has(wanted):
		return wanted
	var pool: Array = []
	for pr in PROFILES:
		if not dealt.has(pr):
			pool.append(pr)
	if pool.is_empty():
		pool = PROFILES.duplicate()
	return pool[rng.randi_range(0, pool.size() - 1)]


## The line-up for the next race: `opponent_count` rivals with "random" cars / colours resolved (by
## `rng`), never repeating the player's own car AND colour. [{car, color, difficulty, profile}, ...]
func resolve_opponents(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var taken := {"%s/%d" % [selected_car, selected_color]: true}
	var dealt: Array = []
	for i in opponent_count:
		var o: Dictionary = opponents[i]
		var car := String(o.get("car", "random"))
		if car == "random" or not CarRegistry.has(car):
			car = CarRegistry.ids()[rng.randi_range(0, CarRegistry.ids().size() - 1)]
		var color := int(o.get("color", -1))
		if color < 0:
			color = rng.randi_range(0, CarRegistry.PALETTE_SIZE - 1)
		var guard := 0
		while taken.has("%s/%d" % [car, color]) and guard < CarRegistry.PALETTE_SIZE:
			color = (color + 1) % CarRegistry.PALETTE_SIZE
			guard += 1
		taken["%s/%d" % [car, color]] = true
		var profile := pick_profile(String(o.get("profile", "random")), rng, dealt)
		dealt.append(AIDriver.resolve_personality(profile))
		out.append({"car": car, "color": color, "difficulty": String(o.get("difficulty", "medium")),
				"profile": profile})
	return out


const LOBBY_SCENE := "res://scenes/lobby.tscn"


func go_to_lobby() -> void:
	_change_scene(LOBBY_SCENE)


## The race scene as it is, without resetting anything (a network race brings its own setup).
func go_to_race_scene() -> void:
	_change_scene(RACE_SCENE)


func go_to_car_select() -> void:
	_change_scene(CAR_SELECT_SCENE)


## SPEC 73: the id of a car the player actually owns -- `id` if it is theirs, the starter otherwise.
## Browsing a locked car is allowed everywhere (that is how it gets bought); LEAVING a screen with one,
## announcing one to a room or racing one is not, and every one of those routes comes through here.
func owned_car(id: String = "") -> String:
	var want := CarRegistry.resolve(id if id != "" else selected_car)
	return want if profile.is_car_unlocked(want) else CarRegistry.DEFAULT_ID


## SPEC 71: whatever route got here, the race is driven in a car the player owns.
func ensure_owned_car() -> void:
	if profile.is_car_unlocked(selected_car):
		return
	selected_car = CarRegistry.DEFAULT_ID
	selected_color = 0


func calm_effects() -> bool:
	return bool(get_setting("calm_effects"))


func start_race(track_id: String) -> void:
	ensure_owned_car()
	if not is_valid_track(track_id):
		push_warning("GameState: unknown track '%s', using '%s'" % [track_id, TrackRegistry.DEFAULT_ID])
		track_id = TrackRegistry.DEFAULT_ID
	selected_track = track_id
	_change_scene(RACE_SCENE)


func restart_race() -> void:
	start_race(selected_track)


func quit_game() -> void:
	get_tree().quit()


func _change_scene(path: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = false
	tree.change_scene_to_file.call_deferred(path)
