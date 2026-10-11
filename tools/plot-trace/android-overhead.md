# Android HD plotting overhead

Measured on the connected Galaxy S22 Ultra (SM-S908U), using its existing `sin(x^2)` graph, unchanged window/settings, BUSY overclock and eight samples per native LCD column. Both display modes target 16 ms updates. These are phone measurements, not Android emulator timings.

Temporary instrumentation measured the BUSY interval, calculation-thread CPU time, native-core CPU time, waits for the fair frame gate, screen-preparation CPU time and Canvas CPU time. Trial modes were broadcast to one instrumented release APK without restarting the calculator or editing equations. Four measured trials per mode were interleaved in deterministic shuffled order, plus one excluded warmup. The second series starts timing after the F4 key is released, avoiding its deliberate held-key throttle. All benchmark hooks, receivers and clock measurements were removed from build 1169.

## First series: isolate display work

| Mode | Mean time (s) | Standard deviation (s) |
| --- | ---: | ---: |
| Existing 60 Hz path | 1.706 | 0.050 |
| Display updates disabled | 1.514 | 0.001 |
| Existing path at 30 Hz | 1.526 | 0.010 |
| Native-sized LCD transport | 1.571 | 0.034 |
| Unchanged-pixel text recognition cache | 1.582 | 0.016 |
| Both transport and cache, 60 Hz | 1.503 | 0.012 |
| 50,000-instruction chunks, existing display | 1.607 | 0.050 |
| 50,000-instruction chunks, small transport | 1.496 | 0.057 |

The transport and cache together preserve smooth progression while approaching the no-display case. Reducing the frame rate also helps, but was not chosen. Larger chunks alone are not a convincing reason to increase key/snapshot latency.

## Second series: native copy and bookkeeping

The phone warmed during testing; its reported battery temperature reached roughly 40 °C. Use within-series comparisons, not direct comparisons between the two series. Baseline variability is appreciable, so these numbers are not a universal speedup for every plot or phone temperature.

| Mode | Mean time (s) | Standard deviation (s) |
| --- | ---: | ---: |
| Existing 60 Hz path | 2.060 | 0.249 |
| Small transport + cache | 1.632 | 0.123 |
| Transport + cache + no per-batch reference copy | 1.566 | 0.009 |
| Transport + cache + 50,000-instruction chunks | 1.583 | 0.005 |
| No display and no per-batch reference copy | 1.540 | 0.008 |

The retained path took about 24% less elapsed time than the warmed baseline. It finished within about 26 ms of the no-display experiment. Engine waits for frame access fell from 159 ms to 43 ms per plot. Screen-preparation CPU time fell from 1,496 ms to 77 ms; Canvas CPU time fell from 248 ms to 56 ms. These CPU times occur on different threads and must not be added to elapsed time.

In the retained path, calculation-thread CPU time was 1,514 ms, of which 1,501 ms was inside the native core: Java/JNI/locking bookkeeping was about 13 ms, or 0.9%. Eliminating that boundary is therefore not the primary remaining opportunity.

## Changes retained in build 1169

- Transport the 160×100 raster LCD rather than a pre-expanded bitmap when HD plotting is enabled. On this phone the previous ninefold scaling in each dimension produced 81 times as many pixels. Canvas scales the raster background with nearest-neighbor sampling; HD vector/text geometry still uses the original display destination and resolution. Grid/non-HD transport and screenshot export retain their existing paths.
- Cache only fallback glyph recognition for identical recognition pixels, dimensions and graph mode. Native identities still merge every frame. Pixel changes, scrolling, inversion, menu changes and graph-mode changes invalidate the cache. No font outlines changed.
- Remove the unused 16,000-pixel reference extraction after every native CPU batch. Live frames validate the unchanged toolbar against the clean base; completion/empty-graph paths already capture the exact reference used for complete-frame and state-cache validation.
- Keep 10,000-instruction batches, the fair frame handoff, completed-frame double buffering and the 16 ms BUSY display target. Stop republishing unchanged completed frames continuously; native pixels/BUSY transitions and periodic polling still update them.

ROM-backed checks passed with the reference extraction disabled: numerical curves, window/style fallbacks, axes/grid, empty graphs, incremental curves, progressive capture, menus, original-display toggle, saved/restored graphs, pending evaluation resume and ON interruption. Android text regression checks and release/lint builds passed. Clean-build phone checks cover repeated graph/menu/ReGraph/Y= cycles, Android Back options, ON interruption and progressive plotting.

Raw measurement outputs and temporary instrumented source are preserved locally under ignored `build/hd-overhead/`; they contain private calculator fixtures and are not committed.
