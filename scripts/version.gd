class_name Version
extends RefCounted
## What build this is (SPEC 72).
##
## ONE number lives in ONE place: `application/config/version` in project.godot. Everything else reads
## it -- the corner of the main menu, the server's welcome, the Docker image tag, the name of the release
## zip, the tests that keep CHANGELOG.md honest. Nothing hard-codes a number of its own, so a release is
## a single edit plus a tag.
##
## The shape is `MAJOR.MINOR.PATCH`, and the SPEC section is counted in tens (SPEC 113: "0.112.0 looks
## weird -- the important number in the middle, the minor one third, and we count in tens"):
##   * MAJOR  0 while the game is still being built out.
##   * MINOR  the tens of the highest section of docs/SPEC.md in this build: sections 110-119 are 11.
##            Every new ten of sections moves it -- the number that matters.
##   * PATCH  the section within that ten: 0.11.3 IS "everything up to SPEC 113". That is the whole
##            trick: the spec numbers the features, so the version says which features are in your
##            hands, and a bug report that says "0.11.1" says exactly what it was missing.
##   * A fix that adds no section appends a FOURTH number: 0.11.3.1.
## Up to 0.112.0 the number was 0.<section>.<patch>; the old builds keep their names in CHANGELOG.md.
##
## `PROTOCOL` (scripts/net.gd) is a different number and stays that way: it says whether two builds can
## talk to each other at all, and it only moves when the wire format changes. The version is for people;
## the protocol is for sockets.

## Read when the project settings are missing it (a bare `--script` run of a tool, mostly).
const FALLBACK := "0.11.0"

## The wire number, read off scripts/net.gd rather than through the `Net` autoload: a tool or a test run
## with `--script` has no autoloads, and a version line is exactly the thing such a run wants to print.
static var _protocol: int = -1


## "0.71.0"
static func number() -> String:
	var v := String(ProjectSettings.get_setting("application/config/version", ""))
	return v if v != "" else FALLBACK


## "v0.71.0" -- what a human sees.
static func label() -> String:
	return "v" + number()


## `Net.PROTOCOL`, without needing the autoload to be alive.
static func protocol() -> int:
	if _protocol < 0:
		var s: GDScript = load("res://scripts/net.gd") as GDScript
		var consts: Dictionary = s.get_script_constant_map() if s != null else {}
		_protocol = int(consts.get("PROTOCOL", 0))
	return _protocol


## What goes in a corner, on a server listing and in a bug report: the build and the wire it speaks.
static func line() -> String:
	return "%s - net %d" % [label(), protocol()]


## "0.11.3" -> [0, 11, 3, 0]; "0.11.3.1" -> [0, 11, 3, 1]. Anything unparseable reads as 0, so a
## mangled version is simply "oldest".
static func parts(v: String) -> PackedInt32Array:
	var out := PackedInt32Array([0, 0, 0, 0])
	var bits := v.strip_edges().trim_prefix("v").split(".")
	for i in mini(bits.size(), 4):
		out[i] = maxi(int(String(bits[i]).to_int()), 0)
	return out


## -1 if `a` is older than `b`, 0 if they are the same build, 1 if `a` is newer.
static func compare(a: String, b: String) -> int:
	var pa := parts(a)
	var pb := parts(b)
	for i in 4:
		if pa[i] != pb[i]:
			return -1 if pa[i] < pb[i] else 1
	return 0


## True when `other` is a NEWER build than this one -- the server is ahead, and the player wants to know
## before they wonder why a track is missing. Not a refusal: only PROTOCOL refuses.
static func is_behind(other: String) -> bool:
	return other != "" and compare(number(), other) < 0


## The one line to show when a server is ahead of us ("" when it is not).
static func update_hint(server_version: String) -> String:
	if not is_behind(server_version):
		return ""
	return "This server runs %s -- you have %s. Grab the new build from the releases page." % [
			"v" + server_version.strip_edges().trim_prefix("v"), label()]
