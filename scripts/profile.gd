class_name Profile
extends RefCounted
## The player's career (SPEC 56): coins, which tracks are open, which cars, colours and effects are owned,
## and what is fitted to each car. Saved to `user://profile.cfg`; owned by GameState, which is the only
## thing that touches the disk.
##
## The ladder is Mario Kart's, per difficulty: Circle is open on every level, and every other track opens
## on the level you beat the track BEFORE it on. Beating Circle on Easy opens Figure 8 on Easy only --
## Medium and Hard stay shut until you win there too.
##
## Nothing here knows about the scene tree, the UI or the physics: it is the save file and the rules, so
## the tests can drive it directly.

const PATH := "user://profile.cfg"
## Awarded for finishing, by place (1st..4th+), before the difficulty multiplier.
const PLACE_COINS := [100, 60, 35, 20]
const FIRST_WIN_BONUS := 150
const GOLD_MEDAL_BONUS := 75
const DIFFICULTY_MULTIPLIER := {"easy": 1.0, "medium": 1.5, "hard": 2.0}
## Parts (SPEC 61): bought per car, from `Parts.CATALOGUE`. Each slot always has a free stock part
## fitted, so a car is never without one.
const COLOR_PRICE := 80
const PALETTE_PRICE := 400
const EFFECT_PRICE := 150
## Free from the start: every colour of every car (SPEC 111; it was the first two), and no effects.
const FREE_COLORS := 2
const EFFECTS := ["flames", "stars", "underglow", "smoke"]

var coins: int = 0
## "<track>@<difficulty>" -> true for every race won (1st place, with at least one rival).
var wins: Dictionary = {}
var cars: PackedStringArray = PackedStringArray()          # unlocked car ids (the starter is always in)
var colors: Dictionary = {}                                # "<car>@<index>" -> true
var effects: PackedStringArray = PackedStringArray()       # owned cosmetic effects
var equipped: PackedStringArray = PackedStringArray()      # ...and the ones actually worn
var parts: Dictionary = {}                                 # "<car>@<part>" -> true (bought)
var fitting: Dictionary = {}                               # "<car>@<slot>" -> part id (fitted)
## "<track>@<car>" -> true: a gold medal already paid for, so it cannot be farmed.
var golds: Dictionary = {}

var path: String = PATH


func _init() -> void:
	cars = PackedStringArray([CarRegistry.DEFAULT_ID])


# ---------------------------------------------------------------- the ladder, and what replaced it

## SPEC 117: EVERY TRACK IS OPEN ("all arenas must be unlocked -- but they should have stars"). The
## ladder is gone. It was a chain: each circuit needed a win on the one before it, at that same
## difficulty, so a player who wanted to drive the mountain had to win four other races first and a
## player who wanted to drive it on HARD had to win them all again. Five circuits that are each a
## different job (SPEC 117 cut the list to five) are a menu, not a queue.
##
## What is kept is the RECORD of what you have beaten, as STARS: one for a win on easy, two on medium,
## three on hard, and a track shows the best it has been won at. Nothing is withheld; the stars say
## where you have been.
const STARS_FOR := {"easy": 1, "medium": 2, "hard": 3}


## Every track, in the order the screen lists them.
static func ladder() -> PackedStringArray:
	return TrackRegistry.ids()


## SPEC 117: always true. Kept as a function because the track screen, the lobby and the tests all ask
## it, and "can I race this?" is a question worth having an answer to even when the answer is yes.
func is_track_unlocked(_track_id: String, _difficulty: String) -> bool:
	return true


func has_win(track_id: String, difficulty: String) -> bool:
	return bool(wins.get("%s@%s" % [track_id, difficulty], false))


## SPEC 117: the stars on a track -- 1 for a win on easy, 2 on medium, 3 on hard, and the best of them
## is what the track carries. 0 for a track you have not won.
func track_stars(track_id: String) -> int:
	var best := 0
	for level in STARS_FOR:
		if has_win(track_id, String(level)):
			best = maxi(best, int(STARS_FOR[level]))
	return best


## The stars a win at this difficulty would put on the track, whether or not it would be an improvement.
static func stars_for(difficulty: String) -> int:
	return int(STARS_FOR.get(difficulty, 1))


## Every star earned across every circuit -- what the track screen puts at the top.
func total_stars() -> int:
	var n := 0
	for id in TrackRegistry.ids():
		n += track_stars(String(id))
	return n


# ---------------------------------------------------------------- racing

## The result of a race: coins earned and anything it opened. `place` is 1-based, `rivals` how many cars
## were raced against (a solo time trial pays nothing and unlocks nothing -- there was nobody to beat).
func finish_race(track_id: String, difficulty: String, place: int, rivals: int,
		gold_car: String = "") -> Dictionary:
	var out := {"coins": 0, "unlocked": "", "first_win": false, "gold": false,
			"stars": track_stars(track_id), "new_star": false}
	if rivals <= 0 or place <= 0:
		return out
	var base: int = PLACE_COINS[mini(place - 1, PLACE_COINS.size() - 1)]
	var earned := int(round(float(base) * float(DIFFICULTY_MULTIPLIER.get(difficulty, 1.0))))
	if place == 1:
		var key := "%s@%s" % [track_id, difficulty]
		var before := track_stars(track_id)
		if not bool(wins.get(key, false)):
			wins[key] = true
			out["first_win"] = true
			earned += FIRST_WIN_BONUS
		# SPEC 117: a win opens nothing -- everything was already open -- but it can put a star on the
		# track, and a better star than the one already there is worth saying out loud.
		out["stars"] = track_stars(track_id)
		out["new_star"] = out["stars"] > before
	if gold_car != "":
		var gkey := "%s@%s" % [track_id, gold_car]
		if not bool(golds.get(gkey, false)):
			golds[gkey] = true
			out["gold"] = true
			earned += GOLD_MEDAL_BONUS
	coins += earned
	out["coins"] = earned
	return out


# ---------------------------------------------------------------- the garage

func is_car_unlocked(car_id: String) -> bool:
	return cars.has(car_id) or car_id == CarRegistry.DEFAULT_ID


func car_price(car_id: String) -> int:
	return CarRegistry.get_price(car_id)


func buy_car(car_id: String) -> bool:
	if is_car_unlocked(car_id) or not CarRegistry.has(car_id):
		return false
	return _spend(car_price(car_id), func() -> void: cars.append(car_id))


## SPEC 111: every colour is free from the start ("all car colours should be available from the start"
## -- a colour is a look, not a reward; the game's unlocks are cars and parts). `buy_color` and the
## bought-colour records stay for old profiles, and always say "owned".
func is_color_unlocked(_car_id: String, _index: int) -> bool:
	return true


func buy_color(car_id: String, index: int) -> bool:
	if is_color_unlocked(car_id, index):
		return false
	return _spend(COLOR_PRICE, func() -> void: colors["%s@%d" % [car_id, index]] = true)


## The whole palette of one car at once, cheaper than one by one.
func buy_palette(car_id: String, size: int) -> bool:
	var missing: Array = []
	for i in size:
		if not is_color_unlocked(car_id, i):
			missing.append(i)
	if missing.is_empty():
		return false
	return _spend(PALETTE_PRICE, func() -> void:
		for i in missing:
			colors["%s@%d" % [car_id, int(i)]] = true)


func has_effect(name: String) -> bool:
	return effects.has(name)


func buy_effect(name: String) -> bool:
	if has_effect(name) or not EFFECTS.has(name):
		return false
	return _spend(EFFECT_PRICE, func() -> void:
		effects.append(name)
		equipped.append(name))              # what you just paid for goes on the car


func is_equipped(name: String) -> bool:
	return equipped.has(name)


## Puts an owned effect on the car, or takes it off. Returns what it is now.
func toggle_equip(name: String) -> bool:
	if not has_effect(name):
		return false
	if equipped.has(name):
		var keep := PackedStringArray()
		for e in equipped:
			if e != name:
				keep.append(e)
		equipped = keep
		return false
	equipped.append(name)
	return true


## A stock part is owned by everybody, always (SPEC 61).
func owns_part(car_id: String, part_id: String) -> bool:
	return Parts.price(part_id) <= 0 or bool(parts.get("%s@%s" % [car_id, part_id], false))


## Buys a part for this car and fits it at once -- nobody buys a part to leave it in the box.
func buy_part(car_id: String, part_id: String) -> bool:
	var part := Parts.find(part_id)
	if part.is_empty() or owns_part(car_id, part_id):
		return false
	return _spend(Parts.price(part_id), func() -> void:
		parts["%s@%s" % [car_id, part_id]] = true
		fitting["%s@%s" % [car_id, _slot_of(part_id)]] = part_id)


## Fits an owned part. Returns false if it is not owned or not a part.
func fit_part(car_id: String, part_id: String) -> bool:
	if not owns_part(car_id, part_id) or Parts.find(part_id).is_empty():
		return false
	fitting["%s@%s" % [car_id, _slot_of(part_id)]] = part_id
	return true


func fitted_part(car_id: String, slot: String) -> String:
	var id := String(fitting.get("%s@%s" % [car_id, slot], ""))
	return id if not Parts.find(id).is_empty() else Parts.stock(slot)


## Every slot's fitted part, for the physics and the garage.
func fitted(car_id: String) -> Dictionary:
	var out := {}
	for slot in Parts.SLOTS:
		out[slot] = fitted_part(car_id, String(slot))
	return out


static func _slot_of(part_id: String) -> String:
	for slot in Parts.SLOTS:
		for p in Parts.in_slot(String(slot)):
			if String((p as Dictionary)["id"]) == part_id:
				return String(slot)
	return ""


func _spend(price: int, then: Callable) -> bool:
	if price > coins:
		return false
	coins -= price
	then.call()
	return true


# ---------------------------------------------------------------- the save file

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("career", "coins", coins)
	cfg.set_value("career", "wins", wins)
	cfg.set_value("career", "golds", golds)
	cfg.set_value("garage", "cars", cars)
	cfg.set_value("garage", "colors", colors)
	cfg.set_value("garage", "effects", effects)
	cfg.set_value("garage", "equipped", equipped)
	cfg.set_value("garage", "parts", parts)
	cfg.set_value("garage", "fitting", fitting)
	var err := cfg.save(path)
	if err != OK:
		push_warning("Profile: could not save to %s (error %d)" % [path, err])


## Reads the file, keeping every value that is still valid; a missing or corrupt file leaves a new career.
func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	coins = maxi(int(cfg.get_value("career", "coins", 0)), 0)
	wins = cfg.get_value("career", "wins", {}) as Dictionary
	golds = cfg.get_value("career", "golds", {}) as Dictionary
	var saved := cfg.get_value("garage", "cars", PackedStringArray()) as PackedStringArray
	cars = PackedStringArray([CarRegistry.DEFAULT_ID])
	for id in saved:
		if CarRegistry.has(id) and not cars.has(id):
			cars.append(id)
	colors = cfg.get_value("garage", "colors", {}) as Dictionary
	var owned := cfg.get_value("garage", "effects", PackedStringArray()) as PackedStringArray
	effects = PackedStringArray()
	for e in owned:
		if EFFECTS.has(e):
			effects.append(e)
	var worn := cfg.get_value("garage", "equipped", PackedStringArray()) as PackedStringArray
	equipped = PackedStringArray()
	for e in worn:
		if effects.has(e):
			equipped.append(e)
	parts = cfg.get_value("garage", "parts", {}) as Dictionary
	fitting = {}
	var saved_fitting := cfg.get_value("garage", "fitting", {}) as Dictionary
	for k in saved_fitting.keys():
		# A part that no longer exists (a catalogue edit) quietly falls back to stock.
		if not Parts.find(String(saved_fitting[k])).is_empty():
			fitting[k] = saved_fitting[k]
