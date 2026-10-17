class_name Feedback
extends RefCounted
## FEEDBACK THAT LANDS IN THE FORM (SPEC 112). A player writes in the game and presses SEND; the game
## posts one ordinary form submission to a Google Form, and the answer appears in its Sheet like any
## other response -- no server code, no account, nothing opens in a browser.
##
## Every Google Form has a submit address ending in `/formResponse`, and every question an id like
## `entry.1234567`; the ids below were read off the form's page. Change the form and re-read them
## (tools/send_feedback.gd posts one entry from the command line to check).
##
## No autoload is named here (tests use this class bare): the caller hands over the player's name and
## where they were.

const FORM_ID := "1FAIpQLSfj5Fwe_qduiSjfV3gfmyaYpvo3REXWc89Ctn3PvdNTb6aj1Q"
const FORM_URL := "https://docs.google.com/forms/d/e/" + FORM_ID + "/formResponse"
const ENTRIES := {
	"rating": "entry.432679203",     # linear scale 1-5
	"type": "entry.331551608",       # Bug / Suggestion / General
	"details": "entry.468455090",    # paragraph
	"version": "entry.2018506613",   # short answer, filled by the game
	"name": "entry.465977324",       # short answer, the player's own name
}
const TYPES := ["Bug", "Suggestion", "General"]
const DEFAULT_TYPE := "General"
const MAX_DETAILS := 600
const MAX_NAME := 24
const HEADERS := ["Content-Type: application/x-www-form-urlencoded"]
## Failed sends wait here for the next launch (never on the web build: the browser hides Google's
## reply, so a "failure" there is usually a success, and a retry would be a duplicate).
const QUEUE_PATH := "user://feedback_queue.json"
const QUEUE_MAX := 20
## Seconds between two sends from one machine: enough for a second thought, not for a flood.
const MIN_INTERVAL := 30.0

## The queue is retried once per run (the title menu does it), whatever the number of visits.
static var retried_this_run: bool = false


## "Windows", "Linux", "macOS", "Android", "iOS" or "Web" -- the first thing a bug report needs.
static func platform_name() -> String:
	if OS.has_feature("web"):
		return "Web"
	return OS.get_name()


## The web build cannot read Google's reply (a cross-site post), so a send there is fire-and-forget.
static func is_fire_and_forget() -> bool:
	return OS.has_feature("web")


## Printable text, trimmed, capped -- newlines kept (a paragraph is allowed a paragraph).
static func clean(text: String, max_len: int) -> String:
	var out := ""
	for ch in text:
		var c := ch.unicode_at(0)
		if c == 10 or c >= 32:
			out += ch
	out = out.strip_edges()
	if out.length() > max_len:
		out = out.left(max_len - 1).strip_edges() + "…"
	return out


## The line the game adds under the player's words: the platform and where they were.
static func context_line(where: String) -> String:
	var w := clean(where, 80)
	return "[%s%s]" % [platform_name(), (", " + w) if w != "" else ""]


## The form submission, url-encoded. `rating` 1-5 (0 leaves the question blank), `type` one of TYPES
## (anything else is General), `details` the player's words with the context line under them.
static func build_body(rating: int, type: String, details: String, name: String, where: String,
		version: String = "") -> String:
	var fields: Array = []
	if rating >= 1 and rating <= 5:
		fields.append([ENTRIES["rating"], str(rating)])
	fields.append([ENTRIES["type"], type if TYPES.has(type) else DEFAULT_TYPE])
	var words := clean(details, MAX_DETAILS)
	fields.append([ENTRIES["details"], (words + "\n\n" if words != "" else "") + context_line(where)])
	fields.append([ENTRIES["version"], version if version != "" else Version.number()])
	fields.append([ENTRIES["name"], clean(name, MAX_NAME)])
	var parts := PackedStringArray()
	for f in fields:
		parts.append("%s=%s" % [String(f[0]), String(f[1]).uri_encode()])
	return "&".join(parts)


## A submission's fields back out of a body (tests, and the queue's report).
static func parse_body(body: String) -> Dictionary:
	var out := {}
	for part in body.split("&", false):
		var kv := part.split("=", true, 1)
		if kv.size() == 2:
			out[String(kv[0])] = String(kv[1]).uri_decode()
	return out


# ---------------------------------------------------------------- the queue

static func queue_load(path: String = QUEUE_PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Array:
		var out: Array = []
		for item in parsed:
			if item is String and String(item) != "":
				out.append(String(item))
		return out
	return []


static func queue_save(bodies: Array, path: String = QUEUE_PATH) -> void:
	if bodies.is_empty():
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(bodies))
	f.close()


## Keeps a failed send for the next launch; the oldest goes once there are QUEUE_MAX.
static func queue_add(body: String, path: String = QUEUE_PATH) -> void:
	var bodies := queue_load(path)
	bodies.append(body)
	while bodies.size() > QUEUE_MAX:
		bodies.pop_front()
	queue_save(bodies, path)
