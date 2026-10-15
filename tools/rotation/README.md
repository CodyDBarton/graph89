# Smooth 3D rotation prototype

The shared native layer retains actual calculator Q14 XYZ vertices and edge connectivity, then projects them on the host with a continuously interpolated orthonormal camera. It does not interpolate raster images or evaluate the equation with a separate parser. Complete calculator projection passes update the target camera; one native interval of smoothing absorbs their steps. Non-arrow commands cancel interpolation, graph/topology changes reset it, and large camera jumps snap. Axes and labels follow the same projection and honor verified AMS 3.10 format flags. Wireframe with AXES/OFF is supported; BOX and other styles retain the existing path.

Host frame capture remains subject to the graph-window and toolbar checks and native popup/Trace masks. Trace uses the calculator-owned scene. The cache is ephemeral and rebuilt after a state restore or plot change. The first CPU prototype was choppier on hardware and is disabled. iOS now uses a separate Metal view to project cached mesh geometry at the display's cadence; emulator/text snapshots remain at 30 Hz. Android retains its previous rotation renderer. GPU frame submissions are measured separately from visible presentation; simulator results are not a physical-device FPS claim. Native saved-screen modal rectangles mask the retained graph, including the white background of F1 → 9 Format.

Checks:
- Compile/run `test-camera.c` for native endpoint projection, orthonormal interpolation and the 350°/10° wrap.
- Run `tools/visual-stress/run.py ROM --scenario rotation --output OUTPUT` in isolated state.
- Run `check-captures.py BEFORE AFTER` to verify distinct views, correct native endpoints, axis labels and stopping.
- iOS `testSmooth3DRotationAndAxes` exercises real key holds, native axes, interpolation and ESC.

For existing calculator sessions, use Graph F1 → 9: Format, set Axes = AXES and Labels = ON, then F4 ReGraph. Test setup enables those native settings only in isolated sessions; production does not silently rewrite saved calculator formats.

The renderer now rebases camera samples onto its display clock instead of
consuming an interpolation that may already have expired in the emulator
queue. A dedicated CADisplayLink requests the screen's maximum refresh range.
The native clock and Core Animation timestamps are converted by age; they
must not be compared directly after host sleep. Camera normalization rejects
degenerate bases, and each mask update uses new GPU texture storage so it
cannot overwrite a texture being sampled by an in-flight frame. All native
axis lettering in the graph viewport is erased before drawing host labels.
Physical-device diagnostics use drawable presented callbacks (not submission
counts); simulator SDKs do not expose those callbacks. The sustained rotation
test additionally checks native LCD pixels and records power status. It
reproduced LCD power-off around 9 seconds with accelerated rotation; the
user subsequently requested disabling automatic power-down entirely. The
shared AMS 3.10 hook lets OSTimerExpired run normally but returns false for
APD timer 2 only. It does not redirect guest execution or modify the ROM,
stack, other timers, or manual OFF. The sustained test checks 30 seconds of
rotation plus manual OFF and wake.

Camera updates now use a metadata-only native getter on a separate serial
queue at display cadence, with at most one outstanding request. It takes the
native plot lock and copies camera/axis metadata only, without advancing the
CPU or reading LCD/text/mesh buffers. Full snapshots and mask updates remain
at 30 Hz. An unchanged native sample timestamp rejects older full snapshots
that finish after a newer fast sample; geometry-generation checks prevent
using a camera with an incompatible cached mesh. The emulator remains the
camera authority. The fast path is suspended when Metal rotation is inactive.

Physical iPhone A/B comparison (same build/scene; test-only
`--ui-test-30hz-camera` disables the fast getter): the original path measured
74.3 presented fps versus 75.5 for fast camera polling, with 25 ms p95 frame
intervals in both runs. Distinct submitted camera poses over the measured
five-second window increased from 60.2/s to 66.2/s (about 10%). These are
single-pair measurements, not proof of a significant presentation-rate gain;
pose submissions are separate from actual drawable presentation callbacks.
The comparison waits for engine readiness before navigating to Graph.

Phone-driven camera prototype: Host3DCamera integrates an orthonormal camera
with quaternion angular velocity on the display clock. Native samples provide
rotation direction/speed and gentle phase corrections; the display no longer
restarts an interpolation for each sample. Non-arrow commands stop local
motion immediately and allow the calculator view to realign. The calculator
continues running and remains the command/state authority; no ROM or guest
angle fields are overwritten. Fast per-display camera polling is disabled in
this mode; 30 Hz full snapshots provide reference samples. A test-only
`--ui-test-intermediate-camera` retains the previous path for A/B comparison.
Native curve-only LCD changes skip font recognition and CPU graph repainting
while the host owns the moving viewport. Stopping, dialogs or disabling Metal
force recognition to refresh normally. Approved axis outlines are unchanged.
The display link now requests the screen maximum as its minimum and preferred
rate; this is still a request, not a guaranteed presentation cadence.

Same-build physical iPhone comparison: intermediate 72.4 presented fps, host
camera 79.9 presented fps. The p95 frame interval stayed 25 ms in both modes.
Distinct submitted camera views increased from 66.7/s to 80.5/s in the measured
five-second interval. This is a prototype improvement, not sustained 120 fps.
Pure Swift checks cover independent motion without new native samples, equal
angular speed at 30/120 Hz, commands, late samples, angle wrap, reset, stale
reference handling and monotonic integration of display-target timestamps.

Further physical profiling isolated the remaining main-thread stall: each
font-recognition pass cost about 20–21 ms, while Metal GPU work averaged
0.3–0.4 ms and encoding was under 0.1 ms. Blanking graph pixels alone did not
help because recognition still tried glyphs at all image coordinates. During
host-owned motion, `graphChromeOnly` now restricts fallback scan origins to
complete cells in the top 16 and bottom 7 rows. Full recognition is the default
and is restored when motion stops, menus open, or Metal is disabled. The saved
native LCD and emulated state are unaffected. Recognition samples fell to
2.5–2.7 ms on the physical iPhone.

The final physical sustained run measured 120 presented fps and an 8.33 ms
p95 interval through over 30 seconds, including a direction change and
restarting automatic rotation. Native APD was prevented four times. Manual
OFF/wake passed, and the final simulator toggle/Format regression also passed.
Bounded timing instrumentation records display callbacks, drawable wait,
encoding CPU time and GPU execution only for rotation UI-test runs. Recent
results are kept under ignored `build/rotation/render-*` logs.

Motion smoothness follow-up: presentation was already 120 fps at both CPU
100% and 250%, but the old Host3DCamera reset orientation to the native pose
on duplicate timestamps, and slerped position immediately on fresh samples.
A constant-speed synthetic test reproduced 21 backward frames at 10 Hz
native updates versus one at 25 Hz. The fix ignores duplicate poses during
motion, estimates angular velocity across a bounded 0.4-second history, and
corrects phase through a limited target velocity. A time-based first-order
filter with a 0.35-second time constant integrates velocity analytically; no
fresh sample teleports the moving orientation. Reference delivery age and
future display targets are included in phase error. Startup/stop, explicit
commands, stale-reference handling, and short-arc wrap remain covered.

Physical CPU100 before/after: both 120 presented fps / 8.33 ms p95; backward
frames in the final 240-frame window 14 → 0; relative angular-speed standard
deviation approximately 120% → 7.2%; mean angular speed 70.4 → 71.0 deg/s.
CPU250 likewise had zero backward frames after the fix (previously eight),
with angular-speed variation 35% → 0.6%. Values are short-window observations,
not guarantees for every graph or interaction. The CPU tests use isolated
preferences and leave the user's actual CPU slider setting untouched.
`test-camera-motion.swift --check` validates sparse/duplicate references,
constant mean speed, zero backward frames and zero sample-time pose jumps.
Both motion and original camera math tests passed, as did the physical
CPU100/250 test and simulator settings/Format regression.


Short-tap / stop handling (2026-10-14): consecutive native projections are no
longer sufficient to infer a held arrow. Every new arrow press stops local
extrapolation; only a real hold of at least 0.35 seconds enables it again.
Releases are tracked, so a burst of short taps remains discrete even if its
native projections arrive close together. A relative orientation offset keeps
the displayed angle on stopping and applies later native steps from that angle.
Pre-input snapshots already in flight update that offset without moving the
view. The display link pauses and redraws immediately on input.

`test-host-camera.swift` now covers rapid taps, no drift after release, stopping
without a backward snap, old snapshots after stopping, and restarting with a
hold. `test3DRotationShortTapsAndStop` exercises those interactions on a physical
iPhone at 100% CPU, checking that the displayed pose stops changing after short
taps, tap-to-stop, and Escape, then that a hold restarts continuous motion.
