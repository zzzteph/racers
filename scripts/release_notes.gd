class_name ReleaseNotes
extends RefCounted
## WHAT CHANGED, IN THE GAME (SPEC 113). CHANGELOG.md is the one record of what every build added and
## took away; the game shows it, so a player (or a tester) can read the release notes without leaving
## the game. In an export the file itself is not there (a markdown file is not a resource, and the
## export's include filter never picked it up), so `tools/bake_release_notes.gd` bakes it into
## `ReleaseNotesData.TEXT` before every release; the suite fails when that copy is stale. The file is
## read when it exists (the editor, the tests), the baked copy otherwise.
##
## The file's shape: `## <version> — <date>` heads a section; `- **Bold.** words` is an item, and an
## indented line continues the item above it. Anything before the first heading is the preamble.

const PATH := "res://CHANGELOG.md"
const DEFAULT_LIMIT := 8


## The notes' text: the file when it is there, the baked copy otherwise ("" with neither).
static func text(path: String = PATH) -> String:
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var t := f.get_as_text()
			f.close()
			return t
	return ReleaseNotesData.TEXT


## The baked copy, for the test that keeps it current.
static func baked() -> String:
	return ReleaseNotesData.TEXT


## The sections, newest first: [{version, date, items: [String]}].
static func sections(path: String = PATH) -> Array:
	return parse(text(path))


static func parse(text: String) -> Array:
	var out: Array = []
	var current: Dictionary = {}
	for raw in text.split("\n"):
		var line := raw.trim_suffix("\r")
		if line.begins_with("## "):
			if not current.is_empty():
				out.append(current)
			var head := line.substr(3).strip_edges()
			var sep := head.find(" — ")
			if sep < 0:
				sep = head.find(" - ")
			var version := head.substr(0, sep).strip_edges() if sep >= 0 else head
			var date := head.substr(sep + 3).strip_edges() if sep >= 0 else ""
			current = {"version": version, "date": date, "items": []}
			continue
		if current.is_empty():
			continue
		var stripped := line.strip_edges()
		if stripped.begins_with("- "):
			(current["items"] as Array).append(stripped.substr(2).strip_edges())
		elif stripped != "" and not (current["items"] as Array).is_empty():
			var items: Array = current["items"]
			items[items.size() - 1] = String(items[items.size() - 1]) + " " + stripped
	if not current.is_empty():
		out.append(current)
	return out


## The newest version the notes know of ("" with no notes).
static func newest(path: String = PATH) -> String:
	var s := sections(path)
	return String(s[0]["version"]) if not s.is_empty() else ""


## SPEC 115: THIS BUILD IN ONE LINE. Every item in the notes opens with its own headline in bold --
## "**The arena is a stunt arena now.** There are no coins..." -- so the summary of a version is those
## headlines, in order, joined with a dot and cut at `chars`. Nobody reads a changelog from a corner of
## the title screen; they read one line and decide whether to open the rest.
##
## `chars` defaults to what fits in the corner of the title menu BESIDE the button column: the whole
## headlines that fit, never a half one, and no ellipsis unless a single headline is longer than the
## line. The audit found the first version of this at 92 characters, sitting on top of the Settings
## button.
static func summary(list: Array, version: String = "", chars: int = 56) -> String:
	var section: Dictionary = {}
	for s in list:
		if version == "" or String((s as Dictionary)["version"]) == version:
			section = s
			break
	if section.is_empty():
		return ""
	var heads := PackedStringArray()
	for it in section.get("items", []):
		var head := _headline(String(it))
		if head == "":
			continue
		var joined := "  ·  ".join(heads + PackedStringArray([head]))
		if heads.size() > 0 and joined.length() > chars:
			break
		heads.append(head)
		if joined.length() >= chars:
			break
	var out := "  ·  ".join(heads)
	return out.left(chars - 1).strip_edges() + "…" if out.length() > chars else out


## The bold phrase an item opens with, without the punctuation it runs into the rest of the line with.
## An item with no bold lead has no headline, and is left out of the summary.
static func _headline(item: String) -> String:
	if not item.begins_with("**"):
		return ""
	var close := item.find("**", 2)
	if close < 0:
		return ""
	return item.substr(2, close - 2).strip_edges().rstrip(".:,;-")


## The notes as BBCode for a RichTextLabel: the newest `limit` versions, each a heading and its items.
static func bbcode(list: Array, limit: int = DEFAULT_LIMIT) -> String:
	var parts := PackedStringArray()
	for i in mini(list.size(), limit):
		var s: Dictionary = list[i]
		var date := String(s.get("date", ""))
		parts.append("[b][color=#ffeb4d]%s[/color][/b]%s" % [_esc(String(s["version"])),
				("   [color=#aab0b8]%s[/color]" % _esc(date)) if date != "" else ""])
		for it in s.get("items", []):
			parts.append("  •  " + _markdown_to_bb(String(it)))
		parts.append("")
	return "\n".join(parts).strip_edges()


## `**bold**` and `` `code` `` are all the markdown the notes use.
static func _markdown_to_bb(s: String) -> String:
	var out := _esc(s)
	var bold := true
	while out.find("**") >= 0:
		out = _replace_first(out, "**", "[b]" if bold else "[/b]")
		bold = not bold
	var code := true
	while out.find("`") >= 0:
		out = _replace_first(out, "`", "[code]" if code else "[/code]")
		code = not code
	return out


static func _replace_first(s: String, what: String, with: String) -> String:
	var i := s.find(what)
	return s if i < 0 else s.substr(0, i) + with + s.substr(i + what.length())


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]").replace("]", "[rb]")
