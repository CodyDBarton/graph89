# True HD plotting prototype

The Android and iOS settings now include **HD Plotting (Prototype)**, independent of Sharp Text and Compact Layout. Enable it, open Graph, and press F4 ReGraph. Turning it off immediately reveals the original calculator graph. Android requires Solid LCD with grayscale disabled. Supports all six full-screen TI-89 Titanium AMS 3.10 graph modes: Function, Parametric, Polar, Sequence, 3D wireframe and Differential Equations. Non-default curve styles, other 3D styles (hidden surface, contour and implicit), split-screen layouts and unverified ROMs retain the original display. Cursor movement, Trace and native graph popup menus preserve the HD scene beneath their calculator-owned overlays.

This actually evaluates additional points through AMS's `cpt_gr_fun` routine. It is not raster smoothing, spline fitting, a host equation parser, or a reimplementation of TI mathematics. The calculator's angle mode, variables, selected functions and window ranges continue to determine the results. With xres=1, seven additional x values between each adjacent original pair produce 1,265 samples over the 158 native horizontal intervals, versus 159 primary original samples. The ROM's existing adaptive checks are additional to these counts. Larger xres intervals receive more subdivisions to maintain eight samples per native column.

Parametric and polar curves replay `cpt_gr_param` / `cpt_gr_polar` at extra t/theta values. Both output coordinates come from the calculator's evaluator; angle mode and undefined-result handling remain calculator owned. Subdivision targets eight evaluations per 1/158 of the parameter range, capped at 160 subdivisions per original interval.

Sequence graphs retain integer n: inventing fractional sequence terms would change the mathematics. Their unrounded `GrLineFlt` coordinates produce sharp connected segments or native-style dot/square markers.

3D wireframes temporarily increase xgrid/ygrid by the HD factor, capped at 63 to stay within the native heap-block and host geometry limits. Native vertices and edge connectivity remain calculator owned. A verified Q14 projection loop supplies matrix, scale and centre before raster rounding. The default mesh increases from 225 vertices / 420 edges to 3,969 vertices / 7,812 edges. The HD mesh is published before native raster line drawing; its background excludes transient progress text. Rotation reprojects the native mesh. Optional 3D axes/box edges are captured as vector lines at native endpoint positions; labels are retained from the separate backing-bitmap passes. Original window grid settings are restored after completion or interruption.

Differential equations use the native solver and `GrLineFlt` output. During a graph calculation, tstep and Euler step are divided by the HD factor, RK tolerance by its square (never raising an already tighter tolerance), and slope-field resolution is doubled, capped at 63. Slope vectors are captured from native floating-point deltas before endpoint rounding. Original tstep, tolerance, Euler step and field resolution are restored at the graph return. No host ODE parser or solver is used.

Two unique caller instruction fingerprints identify the primary endpoint evaluations. Their original arguments, 68000 registers, condition flags and x value are retained. Each added call runs normal ROM code, then the original call runs with its original arguments. Re-entering the routine refreshes the CPU prefetch. Only validated RAM buffers are used, capture is bounded to 32,768 points, and interpolation/replay is limited to 160 subdivisions per primary interval. Unknown caller layouts are untouched. The ROM file and stored equations are unchanged.

Full BCD results are mapped to unrounded LCD coordinates. The renderers draw clipped vector segments at device resolution; they do not round results onto the 160×100 LCD first. Undefined results break paths. Opposite out-of-window values never bridge a pole. Clipping occurs before graphics paths are built to keep extreme numerical values away from the graphics rasterizer. Multiple functions retain independent paths. This is a fixed-density prototype, not an adaptive error-bounded renderer: sufficiently rapid oscillations or narrow features can still be missed.

Axes, ticks and grid dots are captured from `GrAxes` drawing calls on the actual LCD port. Backing-window calls are excluded so geometry is not duplicated. Known axis centers and scale ticks are mapped to unrounded window coordinates; unsupported geometry retains its native location. Only captured geometry pixels are removed from the background, restoring their pre-axis contents. Unknown graphics and labels remain intact. Android and iOS render the captured segments and circular grid dots at device resolution with the same thin stroke as curves. Geometry is bounded to 16,384 segments; incomplete or oversized capture keeps the original axes bitmap. While a supported graph is being computed, its HD samples are exported progressively, using the captured graph toolbar and the calculator's BUSY state to validate the live frame. Android refreshes the vector layer every display update even if the original LCD pixels have not changed. Original low-resolution curve pixels are never included in that live background. Completed graphs retain the original LCD reference and require the same mathematical window, full-screen graph geometry and at least four unchanged graph toolbar tiles. Cursor movement, Trace readouts and popup menus are treated as interaction overlays: their patches remain in the native LCD/sharp-text layer, while curves and axes outside those patches stay HD. Background bit 0 contains ink, bit 1 identifies native overlay patches, and bit 2 protects native cursor patches from false Sharp Text matches. Changed windows, other applications and unsupported graph layouts cannot reuse stale curves. When AMS adds a selected function without clearing the graph, the existing vectors and clean background are retained only if the window and prior LCD match exactly. Restored graph caches reload their window metadata from calculator RAM so incremental plots also retain earlier curves after reopening. Closing a menu restores the HD display when the original graph returns. F4 ReGraph replaces both the axes background and vectors.

Calculator states include a bounded, fixed-byte-order optional trailer. It preserves completed vectors/axes and, if saved mid-evaluation, the continuation required to finish the additional call and restore the original sample. Cached vectors are validated against the loaded original framebuffer before display. Old state files remain supported. The ON interrupt still executes through the normal CPU/key path.

## Isolated verification

```sh
python3 tools/plot-trace/run.py TI89Titanium_OS.89u --output build/plot-trace
```

The runner never loads or changes an app/simulator session. ROM images, state files, numerical results and framebuffer fixtures remain in ignored build output. It compares HD/off original LCD images exactly, checks newly evaluated numerical values against independent functions, and covers:

- `sin(x^2)`, `x^2`, `1/x`, `tan(x)`, and the undefined domain of `x^(1/2)`;
- multiple selected functions, adding a second function to an existing graph (also after state restore), and HD axes on empty graphs;
- live HD publication throughout plotting, without raster curve pixels in its background;
- changed window limits and coarse xres;
- vector axes, fractional tick spacing, grid dots and axes off, with cached geometry surviving restore;
- preserving nonstandard styles;
- ReGraph, cursor arrows, Trace movement, native menu open/close and Value prompts, returning from Y=, Home and the original toggle;
- completed graph save/restore, saving during an added evaluation, disabling mid-evaluation and ON interruption.

The iOS `testHDPlotEvaluatesAdditionalPointsAndToggle` test also checks actual iPhone/iPad rendering, more than 1,200 captured points, native menu restoration and unchanged original pixels when toggled off. Physical Android rendering needs device testing; the shared numerical core is covered by the host harness and the ARM64 APK is built.

SDK reference used to identify routines and guest types: [GCC4TI unknown.h](https://debrouxl.github.io/gcc4ti/unknown.html), particularly `cpt_gr_fun`, `execute_graph_func`, `GR_WIN_VARS`, `XCvtPtoF`, and `YCvtFtoP`. The SDK marks several internals as undocumented; caller signatures and state behavior were therefore verified against the local ROM.

Graph-format regression fixtures set the documented `GR_MODES` flags only in isolated test RAM at the `GrAxes` entry. Production capture never changes those flags. Original/HD fixtures use identical settings. The axis trailer is optional (`G89AXES2`, with `G89AXES1` backward compatibility); pre-axis cache files continue to display their original axes bitmap.

Android HD frames target a 16 ms cadence, subtracting snapshot work from the interval and requesting Canvas invalidation on the next display frame. Short native CPU batches and frame/text snapshots share a fair Java gate so a waiting reader cannot be continually overtaken by turbo. The LCD and plot data are captured together; text recognition and Canvas rendering run outside the gate. There is no extra sleep in the overclock loop. Real hardware can still have a lower frame rate if recognition or drawing takes longer than the frame budget.

For an active HD graph, Android skips raster character matching in the graph viewport, which is fully replaced by vectors. Toolbar/status recognition, retained text and original LCD data remain unchanged; native menus and the original display still receive normal recognition. This avoids rescanning every changing raster curve as possible text on each HD frame.

GS22U verification (SM-S908U): instrumented build 1166 produced 71 refreshes and 70 Canvas draws during a ReGraph of the existing oscillating function. Mean refresh/draw intervals were 16.06/15.96 ms, with longest intervals 24/36 ms. A phone screen recording confirmed progressive vector segments throughout the plotting interval. The installed build before this test was 1165. Temporary timing logs were removed for build 1167.

Android build 1168 fixes UI starvation outside graph-only tests: device logs from 1167 showed Canvas waiting on `ScreenChangeLock` held by refresh for up to 9.482 seconds. Refresh now prepares spare LCD/text/vector buffers without that lock and swaps them together under a short publication lock. Native zoom changes and screenshots use the frame-access gate, not the Canvas lock. An over-budget screen loop sleeps 1 ms rather than immediately reacquiring work; turbo still has no added sleep. On the connected SM-S908U, four graph/menu/ReGraph/Y= cycles plus Home/Catalog and Android Back-menu transitions completed without renewed long monitor contention or an ANR. Slow preparation above 100 ms is logged separately as `Graph89Frame` without blocking Canvas.

Trace navigation exports verified ROM cursor/label identities alongside the axis segments. Both hosts reconstruct the 11×11 circle/cross cursor as vector geometry, retaining its centre and native blink timing. Plot-number cells use the same approved font as Sharp Text, independently of that setting. Original LCD data stays untouched; unknown cursor bitmaps retain the native fallback. The cursor pass clips above coordinate readouts.

Held graph arrows use the ROM's larger 21×21 circle/cross cursor, captured separately from the resting 11×11 cursor. Cursor erase/restore/redraw transitions remain vector based. The shared CPU budget accelerates held arrows throughout the calculator. This works with HD disabled too.


**Cursor Scroll Speed** is adjustable from 1x to 10x (default 3x) and applies to
held arrows throughout the calculator: graph navigation/Trace, Home input,
Y= and mode-specific equation editors, and menus. A monotonic host clock gates
the first repeat at **0.35 seconds**. Verified OSInitKeyDelay countdown decrements
are held until that deadline, then released once. Subsequent native repeat
pacing uses the chosen CPU budget multiplier. Single taps and other key holds
stay unchanged; no persistent ROM/RAM keyboard setting is rewritten. Internal
preference/API names still contain GraphCursorSpeed for compatibility.

The multi-mode harness uses fresh sessions and an isolated real-time clock:

```sh
python3 tools/plot-trace/modes.py TI89Titanium_OS.89u --output build/plot-modes
```

It checks parametric circles, polar roses, sequence n², native 3D mesh/projection,
y′=y against exp(x), completed/pending save states, unchanged window settings,
rotation, and accelerated Home/editor holds across every mode. iOS UI tests cover
each mode's rendered graph, arrow/Trace/menu navigation, and the original toggle.

State trailer version 3 also saves pending density overrides. Loading an unfinished
3D/DE graph safely finishes the native calculation and restores its original
settings; the partial HD cache is discarded until a fresh ReGraph. Completed
caches retain HD geometry. Versions 1/2 remain readable.

Graph Math prompt rows retain validated medium-font DrawChar cells. Their
complete text rectangle, including unchanged pixels and inter-word spaces,
is excluded from vector repaint and is not classified as a cursor. This keeps
intersection curve/bound/result prompts readable with sharp text on or off.

Clipped 3D meshes can contain deleted edges (`-1` endpoints). Those records are
skipped before validating the other endpoint, rather than discarding the entire
HD scene. During rotation, live publication validates the current graph against
its completed toolbar reference. 3D Trace may reserve a shorter client viewport;
the cached scene is clipped to that viewport while retaining its vectors.

Graph readout overlays protect full validated text cells, including polar theta
and scientific-notation digits above the usual coordinate line. Text/plot locks
keep the CPU's existing acquisition order. Both hosts use the shared mask.

Retained text also tracks bounded pending DrawChar/DrawClipChar/DrawStr calls.
A host snapshot during rasterization may omit an unfinished glyph, but cannot
discard its identity before the native call returns. A fine-grained snapshot
regression previously lost theta and most digits after movement; their completed
identities now survive, without changing ROM pixels or approved font outlines.
