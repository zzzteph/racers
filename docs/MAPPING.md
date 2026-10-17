# Making your own tracks

Everything in this file is about **you** building circuits to race on, in the Godot editor, without
touching the game's code (SPEC 78). A track is an ordinary Godot scene made of nodes you drag around, and
it is picked up by the game the moment you save it — there is no list to edit and no build step.

Open the project in Godot 4.7.2, and keep this file next to you the first time.

---

## Making a track

A circuit is one line — the centre of the road — plus whatever you put beside it. Make a scene whose
root is a **`MapTrack`** node, save it in `scenes/tracks/`, draw the line with the **`Path2D`** child,
and drop **`MapBlock`** buildings and **`MapProp`** cones, tyre stacks and oil drums where you want them.

**The quick way:** duplicate **`scenes/tracks/_template.tscn`** (right-click it in the FileSystem dock →
Duplicate), name the copy `mycircuit.tscn` (a name that starts with `_` is a template and is never
listed), open it, and change things. It is a finished, drivable circuit: an oval, two buildings, three
cones, two tyre stacks and an oil drum.

**From nothing:**

1. **Scene → New Scene → Other Node → `MapTrack`**, save as `scenes/tracks/mycircuit.tscn`. It makes
   its `Path2D` child for you.
2. Select the `Path2D` and draw the centreline with the curve tool in the toolbar (the pen icon adds
   points; drag a point's handles to round a corner). **Close the loop** — the last point on top of the
   first. The **first point is the start line** and the **direction you drew is the direction of the
   race**: the root draws the road at its real width, the start line, and a yellow chevron every 600 px
   pointing the way, so you can see both before you drive. Keep the line at least 120 px from the
   top and left edges of the viewport — the world starts at (0,0) and grows to fit whatever you draw.
3. On the root set `display_name`, `track_width` (100–130 px is the usual range), `laps` and `accent`.
4. **Buildings**: add a `MapBlock` child (Add Child Node → MapBlock), drag it where you want it, set
   `size`, `height` and `color`. It is solid — cars bounce off it and the rope bends round its corners —
   so it must sit off the road; one on the tarmac is refused with its name. `town_scenery` on the root
   adds a whole procedural town around the road as well, if you want the look without placing it.
5. **Objects**: add `MapProp` children and set `kind`: **CONE** and **TYRES** stand where you put them
   (a cone on the racing line is allowed — it is a choice), **OIL_DRUM** is an oil slick on the road
   that never dries. Any other kind is ignored on a circuit, and the warnings say so. `auto_props` on the root (on by default) also places cones and tyre stacks at every
   corner for you; turn it off to have only yours.
6. Check it. The root node's warning triangle in the scene tree lists the refusals and the advice
   (`MapTrack.validate()`): it refuses a line that crosses itself, a corner too tight to drive
   (`MapTrack.MIN_RADIUS`, 70 px), a loop that does not close, a road past the world's edge, or a
   building on the road.
7. **Play it**: it appears in the track list under **Yours** the moment the file is saved. Records and
   sprint laps work as on any track; there are no medals for a track you drew.

The width matters more than it looks: the whole difficulty of a corner is its radius against the road
width, and the warnings name the tightest corner so you can judge it before driving it.

**Shipping it:** a release zip packs everything in `scenes/tracks/`, so a circuit you save there is in
the next build for everybody, and the online lobby's track list reads the same registry.

---

---

## Reference

| Node | What it is | Key properties |
| --- | --- | --- |
| `MapTrack` | the root of a track scene; takes `MapBlock` and `MapProp` children | `display_name`, `track_width`, `laps`, `accent`, `auto_props`, `town_scenery` |
| `MapBlock` | a building: solid, ropes bend on it | `size`, `height`, `color` |
| `MapProp` | on a circuit, CONE, TYRES and OIL_DRUM count | `kind` |

| Number | Value | Why |
| --- | --- | --- |
| `MapTrack.MIN_RADIUS` | 70 px | a tighter corner cannot be driven |
| a car | 36 × 18 px | for judging a gap |
