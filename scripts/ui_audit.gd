class_name UiAudit
extends RefCounted
## TEXT THAT FITS AND DOES NOT COLLIDE (SPEC 97). Walks a screen's visible controls, works out where each
## piece of text is actually drawn (a centred label in a wide box only occupies its middle), and reports
## two kinds of trouble: text that does not fit its box (overflowing, or silently clipped), and two
## pieces of text that share pixels. Run on every screen by `tools/check_overlaps.gd` and by the tests,
## so an overlapping label is a failing check, not something a player finds.
##
## Custom-drawn text (`draw_string` in a `_draw`) is invisible to this: the board, the damage doll and
## the pick-ups draw their own, and the screenshots are what catch those. SPEC 111: a custom-drawn node
## that has an `audit_rect() -> Rect2` (the timing tower, the minimap) is audited as a box -- text over
## it is an overlap, which is what a tester saw ("UI elements overlap the leaderboard and the map").
##
## SPEC 122: and a THIRD kind of trouble -- a row that does not fit the window it scrolls in. Text-fit
## alone cannot see this: the room browser's rows were 776 px wide and every label inside them fitted
## perfectly, but the ScrollContainer showing them was 488 px, so half of every row (including the JOIN
## button) was off the side of a panel with 300 px of empty space to its right. `_scroll_problems`
## measures every ScrollContainer's content against its own window and reports the overflow.

const MIN_OVERLAP := 3.0
## How much wider than its window a scrolling row may be before it counts as a defect. A pixel or two is
## rounding; anything a player would have to scroll sideways for is not.
const SCROLL_SLACK := 4.0

## Every problem on the screen: [{kind: "overflow" | "clipped" | "overlap" | "offscreen", a, b, detail}].
static func audit(root: Node) -> Array:
	settle(root)
	var items: Array = []
	_collect(root, items)
	var problems: Array = []
	_scroll_problems(root, problems)
	for it in items:
		var n: Control = it["node"] as Control
		if n == null:
			continue
		if float(it["needed"]) > n.size.x + 2.0:
			problems.append({"kind": "clipped" if bool(it["clips"]) else "overflow", "a": _path(n), "b": "",
					"detail": "needs %.0f px, has %.0f: \"%s\"" % [float(it["needed"]), n.size.x,
					String(it["text"]).left(48)]})
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Dictionary = items[i]
			var b: Dictionary = items[j]
			var na: Node = a["node"]
			var nb: Node = b["node"]
			if na.is_ancestor_of(nb) or nb.is_ancestor_of(na):
				continue
			var inter: Rect2 = (a["rect"] as Rect2).intersection(b["rect"] as Rect2)
			if inter.size.x > MIN_OVERLAP and inter.size.y > MIN_OVERLAP:
				problems.append({"kind": "overlap", "a": _path(na), "b": _path(nb),
						"detail": "%.0fx%.0f px shared: \"%s\" / \"%s\"" % [inter.size.x, inter.size.y,
						String(a["text"]).left(30), String(b["text"]).left(30)]})
	return problems


## SPEC 122: horizontal overflow inside a ScrollContainer. A container whose horizontal scrolling is
## switched OFF is fine by construction (Godot forces the child to the window's width), so only the ones
## that really can scroll sideways are measured -- and they are measured against what their content
## DEMANDS (`get_combined_minimum_size`), not against what it was given, because a row that has been
## squeezed reports the squeezed width.
static func _scroll_problems(root: Node, problems: Array) -> void:
	for node in _scrollers(root):
		var sc: ScrollContainer = node
		if not sc.is_visible_in_tree():
			continue
		if sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
			continue
		var window: float = sc.size.x
		var bar: ScrollBar = sc.get_v_scroll_bar()
		if bar != null and bar.visible:
			window -= bar.size.x
		for child in sc.get_children():
			var c: Control = child as Control
			if c == null or c is ScrollBar or not c.visible:
				continue
			var want := c.get_combined_minimum_size().x
			if want > window + SCROLL_SLACK:
				problems.append({"kind": "offscreen", "a": _path(sc), "b": _path(c),
						"detail": "content wants %.0f px, the window is %.0f" % [want, window]})


static func _scrollers(node: Node) -> Array:
	var out: Array = []
	if node is ScrollContainer:
		out.append(node)
	for child in node.get_children():
		out.append_array(_scrollers(child))
	return out


## Lays the containers out NOW. A container sorts its children on the next frame; a headless test never
## has one, so every button of a VBox sat at its top-left and "overlapped" every other. Three passes, so
## nested containers converge.
static func settle(root: Node) -> void:
	for pass_n in 3:
		root.propagate_notification(Container.NOTIFICATION_SORT_CHILDREN)


## One line per problem, for a report.
static func lines(problems: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for p in problems:
		var d: Dictionary = p
		out.append("%-8s %s%s  --  %s" % [String(d["kind"]), String(d["a"]),
				("  x  " + String(d["b"])) if String(d["b"]) != "" else "", String(d["detail"])])
	return out


static func _collect(node: Node, items: Array) -> void:
	if node is Control:
		var c: Control = node
		if not c.is_visible_in_tree():
			return
		var it := _text_item(c)
		if not it.is_empty():
			items.append(it)
	elif node is CanvasItem and not (node as CanvasItem).visible:
		return
	elif node is CanvasItem and node.has_method("audit_rect"):
		var box: Rect2 = node.call("audit_rect")
		if box.size.x > 0.0 and box.size.y > 0.0:
			var label: String = String(node.call("audit_text")) if node.has_method("audit_text") else String(node.name)
			items.append({"node": node, "text": label, "rect": box, "needed": 0.0, "clips": true})
	for child in node.get_children():
		_collect(child, items)


## Where this control's text is drawn, and how wide it wants to be. Empty for a control without text.
static func _text_item(c: Control) -> Dictionary:
	var text := ""
	var wraps := false
	var clips := false
	var h_align := HORIZONTAL_ALIGNMENT_LEFT
	var v_align := VERTICAL_ALIGNMENT_TOP
	var font: Font = null
	var font_size := 16
	var lines_n := 1
	var line_h := 0.0
	if c is Label:
		var l: Label = c
		text = l.text
		wraps = l.autowrap_mode != TextServer.AUTOWRAP_OFF
		clips = l.clip_text
		h_align = l.horizontal_alignment
		v_align = l.vertical_alignment
		font = l.get_theme_font("font")
		font_size = l.get_theme_font_size("font_size")
		lines_n = maxi(l.get_line_count(), 1)
		line_h = l.get_line_height()
	elif c is Button:
		var b: Button = c
		text = b.text
		clips = b.clip_text
		h_align = b.alignment
		v_align = VERTICAL_ALIGNMENT_CENTER
		font = b.get_theme_font("font")
		font_size = b.get_theme_font_size("font_size")
		lines_n = maxi(text.count("\n") + 1, 1)
		line_h = font.get_height(font_size) if font != null else float(font_size)
	elif c is RichTextLabel:
		var r: RichTextLabel = c
		text = r.get_parsed_text()
		if text.strip_edges() == "":
			return {}
		return {"node": c, "text": text, "rect": Rect2(c.global_position, Vector2(c.size.x,
				minf(float(r.get_content_height()), c.size.y))), "needed": 0.0, "clips": true}
	elif c is LineEdit:
		var e: LineEdit = c
		text = e.text if e.text != "" else e.placeholder_text
		return {"node": c, "text": text, "rect": Rect2(c.global_position, c.size), "needed": 0.0, "clips": true}
	else:
		return {}
	if text.strip_edges() == "" or font == null:
		return {}
	# Scrolled out of a ScrollContainer (or any clipping ancestor) is not on screen.
	var visible_rect := _visible_rect(c)
	if visible_rect.size.x <= 0.0 or visible_rect.size.y <= 0.0:
		return {}
	var needed := 0.0
	for line in text.split("\n"):
		needed = maxf(needed, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var w := c.size.x if wraps else minf(needed, c.size.x) if clips else needed
	var h := float(lines_n) * maxf(line_h, 1.0)
	var x := 0.0
	if h_align == HORIZONTAL_ALIGNMENT_CENTER:
		x = (c.size.x - w) * 0.5
	elif h_align == HORIZONTAL_ALIGNMENT_RIGHT:
		x = c.size.x - w
	var y := 0.0
	if v_align == VERTICAL_ALIGNMENT_CENTER:
		y = (c.size.y - h) * 0.5
	elif v_align == VERTICAL_ALIGNMENT_BOTTOM:
		y = c.size.y - h
	var rect := Rect2(c.global_position + Vector2(x, y), Vector2(w, h)).intersection(visible_rect)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return {}
	return {"node": c, "text": text, "rect": rect, "needed": needed if not wraps else 0.0, "clips": clips}


## The control's own rect, cut down by every ancestor that clips its children (a ScrollContainer's
## window, a clipping panel): what a player can actually see of it.
static func _visible_rect(c: Control) -> Rect2:
	var rect := Rect2(c.global_position, c.size)
	var at: Node = c.get_parent()
	while at != null and not (at is Window):
		if at is Control and (at as Control).clip_contents:
			rect = rect.intersection(Rect2((at as Control).global_position, (at as Control).size))
		at = at.get_parent()
	return rect


static func _path(n: Node) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var at: Node = n
	var depth := 0
	while at != null and depth < 4 and not (at is Window):
		parts.insert(0, at.name)
		at = at.get_parent()
		depth += 1
	return "/".join(parts)
