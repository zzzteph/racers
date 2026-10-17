class_name TrackRegistry
extends RefCounted
## Authored metadata for every track (SPEC 14). Pure data + static lookups; no scene tree, no
## GameState (SPEC decision 10 — this file is read from `--script` test runs and from Track/TrackData).
##
## Adding a track costs exactly one entry in ENTRIES plus one `scripts/tracks/<id>.gd` generator.
## Every getter takes an unknown id without erroring and returns the documented fallback, so a corrupt
## records.cfg or a stale GameState.selected_track can never break the game.

## One scale for the whole game: the speedo (Dashboard.KMH_PER_PX = 0.2) and the track lengths shown on
## the select screen use the same factor. Was 12.5 cm (0.45 km/h per px/s), which put the standard car
## at 261 km/h on a few-hundred-metre circuit.
const METRES_PER_PX := 0.2 / 3.6     # 1 px/s = 0.2 km/h on the speedo (Dashboard.KMH_PER_PX): 5.6 cm per px
const DEFAULT_ID := "circle"

## One list: the tracks are no longer grouped (the select screen shows no headings for a single category).
const CATEGORY_ALL := "Tracks"

## SPEC 124: A LINK IS A PIECE OF ROAD THAT IS NOT ON THE CENTRELINE. `Track.is_on_track()` measures the
## distance to the centreline and nothing else, so anywhere a circuit doubles back on itself the ground
## between the two legs is grass -- and grass caps a car at `off_track_max_speed` (58 px/s), which makes
## every cut across it slower than going round by an order of magnitude. A cut is therefore never a
## decision; it is a mistake with a longer name.
##
## A link is a paved rectangle joining two legs. It drives at road speed, it is drawn as road, and the
## scenery keeps off it. A BREAKABLE across its mouth is what turns it into a decision: the route is shut
## until somebody pays to open it, and open for everyone afterwards (`Breakables`).
##
## Both are in world coordinates, and both are per circuit: `"<id>": [Rect2, ...]`. A circuit with
## neither -- which is all of them at the moment -- behaves exactly as it always has. A link has to pass
## within a gate radius of every checkpoint the road it skips carries, or a lap down it would not count
## (`tools/probe_gates.gd`).
const LINKS := {}
## SPEC 124: the walls that shut the links, in world coordinates. Put one just clear of the road the
## link leaves -- a wall drawn ON the road would stop the cars that were only driving past.
const BREAKABLES := {}

const DEFAULT_WIDTH := 110.0
const DEFAULT_LAPS := 10
const DEFAULT_CHECKPOINTS := 8

## Authored fields only. Derived geometry (length, corners, radius, straight) is measured from the real
## centerline by get_stats() and can therefore never go stale against a generator.
const ENTRIES := [
	{
		"id": "circle",
		"display_name": "Circle",
		"short_name": "Circle",
		"location": "The oval",
		"category": CATEGORY_ALL,
		"accent": Color(0.247, 0.639, 0.302),      # #3FA34D
		"width": 110.0,
		"laps": 10,
		"checkpoints": 8,
		"difficulty": 0,
		"description": "The oval. Learn the rope here: one long corner, two straights, no excuses.",
		"has_bridge": false,
		"dash_safe": false,
		"generator": "",
		"scenery": "country",     # SPEC 120: trees and rocks on the ground the road leaves empty
	},
	{
		"id": "figure8",
		"display_name": "Figure 8",
		"short_name": "Figure 8",
		"location": "The crossover",
		"category": CATEGORY_ALL,
		"accent": Color(0.247, 0.498, 0.639),      # #3F7FA3
		"width": 110.0,
		"laps": 10,
		"checkpoints": 12,
		"difficulty": 0,
		"description": "Crosses itself on a bridge. Watch which branch you are on.",
		"has_bridge": true,
		"dash_safe": false,
		"generator": "",
		"scenery": "country",     # SPEC 120: trees and rocks on the ground the road leaves empty
	},
	{
		"id": "singapore",
		"display_name": "Neon Harbour",
		"short_name": "Neon Harbour",
		"location": "Night Streets",
		"category": CATEGORY_ALL,
		"accent": Color(0.878, 0.541, 0.118),      # #E08A1E
		"width": 102.0,
		"laps": 10,
		"checkpoints": 14,
		"difficulty": 0,
		"description": "Corner after corner between the walls, and the shortest straight of the eight.",
		"has_bridge": false,
		"dash_safe": true,
		"generator": "res://scripts/tracks/singapore.gd",
		"scenery": "country",     # SPEC 120: trees and rocks on the ground the road leaves empty
	},
	{
		"id": "serpent",
		"display_name": "Serpent",
		"short_name": "Serpent",
		"location": "Six screens of bends",
		"category": CATEGORY_ALL,
		"accent": Color(0.55, 0.38, 0.82),
		"width": 112.0,
		"laps": 10,
		"checkpoints": 16,
		"difficulty": 3,
		"description": "Long and winding: you never see more than the next bend. The camera rides with you.",
		"has_bridge": false,
		"dash_safe": false,
		"generator": "res://scripts/tracks/serpent.gd",
		"scenery": "country",     # SPEC 120: trees and rocks on the ground the road leaves empty
		# SPEC 110: six screens of world, for the camera that moves.
		"world": Vector2(3200, 1800),
	},
]


## id -> ENTRIES index, built once.
static var _index: Dictionary = {}
## id -> measured stats, built on first get_stats() for that id.
static var _stats_cache: Dictionary = {}


static func _build_index() -> void:
	if not _index.is_empty():
		return
	for i in ENTRIES.size():
		_index[String(ENTRIES[i]["id"])] = i


# ------------------------------------------------------------------ tracks you drew yourself (SPEC 78)

## Where a hand-drawn circuit lives. Any scene in here whose root is a MapTrack is a track: no entry to
## add, nothing to register. They are listed after the ones that ship, under their own category.
const USER_FOLDER := "res://scenes/tracks/"
const USER_CATEGORY := "Yours"
## id -> the entry built from the scene, so a track is only read off disk once per run.
static var _user_cache: Dictionary = {}
static var _user_scanned := false


## The ids of every drawable track in `scenes/tracks/` that is actually drivable (a template -- a file
## whose name starts with "_" -- is read but never listed).
static func user_ids() -> PackedStringArray:
	_scan_user()
	var out := PackedStringArray()
	for id in _user_cache.keys():
		var e: Dictionary = _user_cache[id]
		if bool(e.get("ok", false)) and bool(e.get("listed", true)):
			out.append(String(id))
	return out


## SPEC 111: a drawn track handed over as a node (tests, or anything that builds one without a file).
## It is listed like a file in `scenes/tracks/` until `remove_user_track`.
static func add_user_track(id: String, track: MapTrack) -> Dictionary:
	_scan_user()
	var e := _entry_from(id, track)
	_user_cache[id] = e
	_stats_cache.erase(id)
	TrackData.clear_cache()
	return e


static func remove_user_track(id: String) -> void:
	_user_cache.erase(id)
	_stats_cache.erase(id)
	TrackData.clear_cache()


## What a drawn track put beside its road (SPEC 111): {blocks: [{rect, color, lift, name}],
## props: [{kind, pos, name}], auto_props: bool}. Empty for a track that ships.
static func user_items(id: String) -> Dictionary:
	_scan_user()
	if not _user_cache.has(id):
		return {}
	return (_user_cache[id] as Dictionary).get("items", {})


## Whether the race places its own cones and tyre stacks on this track (always, for one that ships).
static func user_auto_props(id: String) -> bool:
	var items := user_items(id)
	return bool(items.get("auto_props", true)) if not items.is_empty() else true


static func is_user(id: String) -> bool:
	_scan_user()
	return _user_cache.has(id)


## What a hand-drawn track looks like to the rest of the game: the same entry shape the built-in tracks
## have, filled in from the scene, plus whether it passed its own checks.
static func user_entry(id: String) -> Dictionary:
	_scan_user()
	return _user_cache.get(id, {})


static func _scan_user() -> void:
	if _user_scanned:
		return
	_user_scanned = true
	var dir := DirAccess.open(USER_FOLDER)
	if dir == null:
		return
	for f in dir.get_files():
		var name := String(f)
		if not (name.ends_with(".tscn") or name.ends_with(".scn") or name.ends_with(".tscn.remap")):
			continue
		var id := name.replace(".remap", "").get_basename()
		var path := "%s%s.tscn" % [USER_FOLDER, id]
		if not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var node := packed.instantiate()
		var track := node as MapTrack
		if track == null:
			node.free()
			continue
		var e := _entry_from(id, track)
		e["listed"] = not id.begins_with("_")     # SPEC 111: "_template" is read, checked, never listed
		_user_cache[id] = e
		node.free()


## The same entry shape the built-in tracks have, filled in from a MapTrack node -- plus the line and
## the things beside it, read once here so the race never opens the scene again.
static func _entry_from(id: String, track: MapTrack) -> Dictionary:
	var problems := track.validate()
	return {
		"id": id,
		"display_name": track.display_name if track.display_name != "" else id.capitalize(),
		"short_name": (track.display_name if track.display_name != "" else id).substr(0, 14),
		"location": "Yours", "category": USER_CATEGORY, "accent": track.accent,
		"width": track.track_width, "laps": track.laps, "checkpoints": 8, "difficulty": 2,
		"description": "A circuit you drew.", "has_bridge": false, "dash_safe": true,
		"generator": "", "world": track.get_world_size(),
		# SPEC 120: a drawn circuit wears the town it was drawn with, or trees on the ground it leaves.
		"scenery": "town" if track.town_scenery else "country",
		"ok": problems.is_empty(), "problems": problems, "notes": track.notes(),
		"listed": true, "centerline": track.get_centerline(), "items": track.get_items(),
	}


## The centreline of a hand-drawn track, or an empty line when it is not one.
static func user_centerline(id: String) -> PackedVector2Array:
	if not is_user(id):
		return PackedVector2Array()
	return (_user_cache[id] as Dictionary).get("centerline", PackedVector2Array())


# ------------------------------------------------------------------ lookups

static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for e in ENTRIES:
		out.append(String(e["id"]))
	# SPEC 78: the tracks you drew, after the ones that ship.
	for id in user_ids():
		out.append(String(id))
	return out


static func has(id: String) -> bool:
	_build_index()
	return _index.has(id) or Array(user_ids()).has(id)


static func get_entry(id: String) -> Dictionary:
	_build_index()
	if not _index.has(id):
		# SPEC 78: a hand-drawn circuit answers every question a built-in one does.
		var mine := user_entry(id)
		return mine if not mine.is_empty() and bool(mine.get("ok", false)) else {}
	return ENTRIES[int(_index[id])]


## `id` when it is a real track, DEFAULT_ID otherwise. Every caller that must end up with a usable
## track (Track.setup, GameState.start_race) goes through this.
static func resolve(id: String) -> String:
	return id if has(id) else DEFAULT_ID


static func _field(id: String, key: String, fallback: Variant) -> Variant:
	var e := get_entry(id)
	if e.is_empty() or not e.has(key):
		return fallback
	return e[key]


static func get_display_name(id: String) -> String:
	return String(_field(id, "display_name", id))


static func get_short_name(id: String) -> String:
	return String(_field(id, "short_name", id))


static func get_location(id: String) -> String:
	return String(_field(id, "location", ""))


static func get_category(id: String) -> String:
	return String(_field(id, "category", CATEGORY_ALL))


## Every category that appears in ENTRIES, in registry (display) order, without duplicates.
static func categories() -> PackedStringArray:
	var out := PackedStringArray()
	for e in ENTRIES:
		var c := String(e["category"])
		if not out.has(c):
			out.append(c)
	return out


static func ids_in(category: String) -> PackedStringArray:
	var out := PackedStringArray()
	for e in ENTRIES:
		if String(e["category"]) == category:
			out.append(String(e["id"]))
	return out


static func get_accent(id: String) -> Color:
	return _field(id, "accent", Color(0.35, 0.72, 1.0)) as Color


## The size of the WORLD this track lives in (SPEC 52). The classic tracks are exactly one screen
## (1280x720) and say nothing; a bigger track names its own size, and the barrier, the grass, the props
## and the camera all follow it. The close camera is forced on anything bigger than a screen -- the whole
## point of a big world is that you cannot see it all at once.
static func get_world_size(id: String) -> Vector2:
	var v: Variant = _field(id, "world", null)
	if v is Vector2 and (v as Vector2).x >= 640.0 and (v as Vector2).y >= 480.0:
		return v
	return Vector2(1280, 720)


## True when this track's world is bigger than one screen.
static func is_big(id: String) -> bool:
	var w := get_world_size(id)
	return w.x > 1280.0 or w.y > 720.0


## The scenery a track wears (SPEC 52): "" for the circuits, "town" for a town. Drawn only; nothing
## here is ever driven into.
static func get_scenery(id: String) -> String:
	return String(_field(id, "scenery", ""))


## SPEC 124: the paved links off this circuit's centreline (empty for most of them).
static func get_links(id: String) -> Array:
	return (LINKS.get(id, []) as Array).duplicate()


## SPEC 124: the breakable walls on this circuit (empty for most of them).
static func get_breakables(id: String) -> Array:
	return (BREAKABLES.get(id, []) as Array).duplicate()


static func get_width(id: String) -> float:
	return float(_field(id, "width", DEFAULT_WIDTH))


static func get_laps(id: String) -> int:
	return int(_field(id, "laps", DEFAULT_LAPS))


static func get_checkpoint_count(id: String) -> int:
	return int(_field(id, "checkpoints", DEFAULT_CHECKPOINTS))


## 1..5, DERIVED from the circuit's own measured geometry, never authored. The authored numbers used to
## be free text: Jeddah and Singapore were rated 5 and Bahrain 3 while all six had the same minimum-radius
## band, the same clean 3-lap time band and the same rhythm, so the select screen's badge said nothing.
## An entry may still pin a number by giving a non-zero `difficulty`; all eight ship with 0, i.e. derived.
##
## The score is what actually makes a track hard to drive with this rope: how tight its tightest corner is
## (the speed you have to scrub off), how much of the lap is corner rather than straight (how little rest
## there is), and how much grass there is outside the road when you get it wrong.
static func get_difficulty(id: String) -> int:
	var authored := int(_field(id, "difficulty", 0))
	if authored > 0:
		return clampi(authored, 1, 5)
	var stats := get_stats(id)
	var length := float(stats.get("length_px", 0.0))
	if length <= 0.0:
		return 1
	var min_r := float(stats.get("min_radius", 400.0))
	var straight := float(stats.get("longest_straight", 0.0))
	# How often the car has to change what it is doing: corners per 1000 px of lap. 0 at 0.8 (the oval,
	# one long constant bend) and 1 at 3.6 (Marina Bay). This is the term that separates a track with one
	# tight corner you settle into from one that never lets go.
	var density := clampf((float(stats.get("corners", 1)) * 1000.0 / length - 0.8) / 2.8, 0.0, 1.0)
	# 0 at a 320 px radius (flat out), 1 at 140 px (second gear).
	var tightness := clampf((320.0 - min_r) / 180.0, 0.0, 1.0)
	# 0 when a quarter of the lap is one straight, 1 when there is no straight worth the name.
	var relentless := clampf((0.25 - straight / length) / 0.22, 0.0, 1.0)
	# 0 with 24 px of grass past the barrier, 1 with none: a wall punishes the same mistake harder.
	var walled := clampf((24.0 - get_runoff(id)) / 24.0, 0.0, 1.0)
	var score := 0.50 * density + 0.16 * tightness + 0.19 * relentless + 0.15 * walled
	return clampi(1 + int(floor(score * 4.999)), 1, 5)


## Grass (px) between the outer road edge and the barrier the car is clamped at, measured from the real
## centerline. 22 px (`Track.BARRIER_MARGIN`) of the screen edge is barrier, so this is what is left.
static func get_runoff(id: String) -> float:
	var pts := TrackData.get_centerline(id)
	if pts.size() < 3:
		return 0.0
	var outer := TrackShape.bounds_of(pts).grow(get_width(id) * 0.5)
	var margin := minf(minf(outer.position.x, outer.position.y),
			minf(1280.0 - outer.end.x, 720.0 - outer.end.y))
	return maxf(margin - 22.0, 0.0)


static func get_description(id: String) -> String:
	return String(_field(id, "description", ""))


static func has_bridge(id: String) -> bool:
	return bool(_field(id, "has_bridge", false))


static func is_dash_safe(id: String) -> bool:
	return bool(_field(id, "dash_safe", false))


## SPEC 131: how far round its own lap a circuit starts, 0..1 of the way along the drawn line (an
## entry's optional "start_at"). Without it a circuit starts where its generator began.
static func get_start_at(id: String) -> float:
	return clampf(float(_field(id, "start_at", 0.0)), 0.0, 1.0)


static func get_generator_path(id: String) -> String:
	return String(_field(id, "generator", ""))


# ------------------------------------------------------------------ derived stats

## Measured from the real centerline, once per id, and cached. Never authored, so it cannot go stale.
## Unknown ids get a zeroed dictionary with the same keys (the select screen prints it as "0 m").
static func get_stats(id: String) -> Dictionary:
	if _stats_cache.has(id):
		return _stats_cache[id]
	var stats := {
		"length_px": 0.0, "length_m": 0.0, "corners": 0, "min_radius": 0.0, "longest_straight": 0.0,
	}
	if has(id):
		var pts := TrackData.get_centerline(id)
		if pts.size() >= 3:
			var length := TrackShape.total_length(pts, true)
			var min_r: Dictionary = TrackShape.min_corner_radius(pts)
			stats["length_px"] = length
			stats["length_m"] = length * METRES_PER_PX
			stats["corners"] = TrackShape.count_corners(pts)
			stats["min_radius"] = float(min_r.get("radius", 0.0))
			stats["longest_straight"] = TrackShape.longest_straight(pts)
	_stats_cache[id] = stats
	return stats


## Test hook: forget the measured stats so a regenerated centerline is re-measured.
static func clear_stats_cache() -> void:
	_stats_cache.clear()
