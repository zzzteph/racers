# Tests

Headless SceneTree test runner (no window, no real mouse). From anywhere:

```
"C:/Users/steph/Downloads/godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:/Users/steph/Documents/GitHub/racers" --script res://tests/run_tests.gd
```

If the project was never opened in the editor, import it first (registers `class_name` globals):

```
"C:/Users/steph/Downloads/godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:/Users/steph/Documents/GitHub/racers" --import
```

Output: one `PASS`/`FAIL` line per check and a summary. Exit code 0 = all passed, 1 = at least one failure.
The whole suite (748 checks, including several full 3-lap autopilot races per track and four full-buffer
performance runs; `tests/net_lobby_tests.gd` -- chat, names, the room countdown, puppets, standing rooms,
the leaderboard -- is loaded by it) takes roughly six minutes.
Any `SCRIPT ERROR` / `ERROR:` in the output should also be treated as a failure.

Coverage: track geometry (closed, on screen, figure-8 crosses once), on-track checks, rope speed model,
rotation, lock/bounds, off-track crawl and recovery, figure-8 bridge (branch-aware progress, draw layering and
checkpoint progression across the crossing — a driven car on each branch consumes only its own branch's
checkpoints, never the other branch's spatially adjacent ones),
LapTracker (in-order laps, cutting rejected, race_finished), GameState records (temporary `user://test_records.cfg`),
scene instantiation, and an autopilot that drives the real race scene for 3 laps on both tracks plus a reckless
autopilot that proves corner cutting leaves the track.

Tester round additions: the `off_track_changed` signal (one event per transition, cleared by `reset_to`),
unknown-track-id fallback, `TrackData.resample_closed` spacing, the mouse target clamp vs. the `target_point`
override and the `RopeLine` child the car builds, determinism / no NaN over a long chaotic run, the race's
interrupt paths (Esc pauses, Esc in the pause menu resumes with the hold, lost window focus pauses, pausing
is refused after the finish), a voided lap reaching the HUD through the real race wiring plus the gate
highlight following the pending checkpoint, the finish screen's "NEW RECORD!" appearing only on the improved
line, the main menu showing stored records, and autopilot assertions that the car never leaves the screen and
that the three lap times are positive and sum to the total.

Review round 1 additions: the difficulty pin (a cursor 96-192 px ahead drives clean, a cursor at the
full-speed distance runs off at the bends), the gradual off-track slowdown, laps counting at the start line,
sanitising of bad `records.cfg` values, and race-flow checks (countdown rope preview + hint, the 1 s resume
hold, no OFF TRACK warning after finishing on the grass, the car braking to a stop with the rope hidden, and
the per-track HUD rects staying off the road).

Physics-extension round additions (SPEC 12.6, 62 checks): the tire curve (linear region, peak at `D`,
saturation past the peak, odd in the slip angle, sub-linear load sensitivity, grass mu) and its degenerate
inputs; every wheel-state field finite in five car states with the four loads summing to 1.0; frame-rate
independence at 1/60, 1/120 and 1/30; weight transfer (braking loads the front, cornering loads the
**outside** pair) and the roll settling without ringing; surface and bridge-deck suspension bumps; a
provoked drift and its recovery when the cursor comes back, plus a gentle run that never drifts; grass
sliding more while the crawl cap holds; both SPEC 8.2 rollover trips (barrier slam, surface-flip scrub) with
their signals, 1.70 s control-return limit, on-screen and finiteness guarantees, the `rollovers_enabled` off
switch, `reset_to()` mid-roll, 30 s of adversarial input, and a rollover on a pending checkpoint that does
not corrupt lap tracking; skid marks (none while cruising, laid while sliding, ring-buffer cap and
recycling, `clear()`, surface and deck-layer attribution); effects and the HUD drift line (capped pools,
silence during the countdown, no node leak over 600 frames); and a per-track full-buffer performance
measurement (~0.5-0.6 ms per physics frame with 1600 segments, against a 6 ms pin).

Tester round 3 additions (SPEC 12.12, 6 checks): skid marks are frame-rate independent by total marked
*length* (3240 / 3232 / 3223 px for the same 2 s slide at 60 / 120 / 30 Hz, with a slower frame laying
fewer, longer segments) and a `sample(0.0)` frame lays nothing; a mid-slide teleport breaks the streaks
instead of painting a line across the screen; a rollover interrupted by a pause (`lock()`) freezes instead
of running itself out and still lands GROUNDED 1.53 s after release; two identically seeded races produce
identical physics, marks and particles; and the per-frame cost with a full 1600-segment buffer is pinned as
a distribution rather than an average, with the split reported per subsystem.

That distribution is pinned at p50 < 2 ms, p95 < 3 ms and p99 < 4 ms, plus the hard guarantee that **no**
frame reaches the 16.6 ms budget (typical measurement: p50 ~0.6 ms, p95 ~1.0 ms, p99 ~1.2 ms). The tight
pins are deliberately on percentiles rather than on the single slowest sample: these are wall-clock times
on a desktop OS, and across runs of one unchanged build the max of 600 samples swung 1.1 -> 5.4 ms while
p50 and p95 barely moved, so pinning the max alone failed about one run in three at random. p99 still
discards only 5 samples of 600, so a regression that makes frames broadly slower still fails the test.

Note: the runner must not reference `Race`/`Hud`/`FinishScreen` as static types — those scripts use the
`GameState` autoload identifier, which is not yet registered when the `--script` runner is compiled. They are
loaded at runtime via `load("res://scenes/race.tscn")`.
