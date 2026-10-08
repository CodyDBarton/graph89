# Android busy-overclock timing — 2026-10-08

Test expression: `nInt(sin(x^2),x,0,8)`.

| Statistic | Before | After |
| --- | ---: | ---: |
| Mean | 337.708 ms | 318.199 ms |
| Median | 326.423 ms | 315.491 ms |
| Sample standard deviation | 20.526 ms | 7.217 ms |

Mean throughput increased **6.13%**, corresponding to **5.78% less calculation time**. The median throughput increase was **3.46%**. This is one expression on an M4-hosted Android emulator; it does not measure Galaxy S22 Ultra performance or establish a universal percentage.

## Method

- Actual optimized release ARM64 Android apps with their normal UI and screen-refresh thread running, installed sequentially in the same isolated Android 11 (API 30, Google APIs ARM64) emulator.
- Before: commit `806c97b18dafee78844dcd3bb3950e5c6dc235c4`, original 30-extra-batch/1-ms-sleep busy loop. After: current working implementation, version code 1138, continuous busy loop in 10,000-iteration chunks.
- CPU Speed 100%; Overclock when Busy enabled; grayscale and energy saving disabled; haptic feedback disabled; state-on-exit disabled. Identical firmware and ROM preferences.
- An Android-created snapshot contained the fully typed expression before Enter. Every trial restored the same unmodified snapshot, allowed 1.5 seconds for app startup, and then submitted Enter.
- Identical temporary native timing hooks, compiled only in isolated copies, sampled BUSY before and after every native engine call. The clock began at the first observed BUSY pixel and stopped at the first observed clear pixel. Typing, app launch and the initial input queue delay were excluded; engine sleeps, screen-flag detection delay during BUSY, OS scheduling and Java loop overhead remained included. Timer edges are quantized by native batch boundaries, which differ between old and new loops.
- One warm-up per build was excluded, followed by ten measured trials each. Pair order alternated before/after and after/before. Logs were filtered to the active app process to exclude delayed records from previous processes.
- Every measured result had the same hash for the result LCD region (x=100–159, y=70–83). The result `.601722` was also visually checked on both builds.

`trials.json` includes the warm-ups and all raw timings; `summary.json` contains the computed statistics. Instrumented copies, APKs, screenshots and calculator state remain in ignored `build/android-overclock-comparison/`. The distributable APK contains no benchmark hooks. No firmware or calculator snapshot is checked into this report.
