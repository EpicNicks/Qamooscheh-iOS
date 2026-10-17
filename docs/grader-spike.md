# Grader spike (M1)

**Decision (user, 2026-10-17): the shipping runtime is JavaScriptCore.** The hidden WKWebView runtime stays implemented as the fallback behind the `Grader` protocol (`FallbackGrader`); no production default is wired in this spike. Open risk: JavaScriptCore could not start on the macOS runner (no wasm SIMD) and has only been measured on the iOS simulator, so it needs a real-device check before it is relied on.

Artifact: `fa` browser grader **v98** from `cdn.parsling.com`, manifest sha256 `9615b4d995000200eb326ba62fb00c0a5194099125ebdc7a9960e19d83a48375`, every file verified against its manifest (`Packages/QGrader/scripts/fetch-grader.mjs`, `GraderBundle.verify()` test). Bundled in `Packages/QGrader/Sources/QGrader/Resources/grader/fa/v98/`.
Same build as Android/web; shim is Android's `grader-host.js` (JavaScriptCore) or the web's `main.mjs` loaded as an ES module (WKWebView).

Note: the local backend artifacts (`artifacts/grader/fa/browser/v1`) are stale (they fail the backend's own separator and xp vectors), so the latest published CDN build was bundled instead. `ja` is not bundled.

## Results (CI, GitHub Actions macos-15, Xcode 16.4)

Correctness = 15 `expect` vectors match exactly, 8 more have accept/reject sanity expectations, the rest are interpreted (or refused for "unknown ..."), and 21 xp rows match through the grading call. Timings are warm single answers, n=200. All runs graded with 0 problems whenever a runtime started. The same code was measured in several runs and the numbers differ a lot; every run is listed rather than one favourable sample.

### iOS 18.5 simulator (`grader-sim` job)

| Run | Runtime | Cold warm-up | p50 | p95 | max |
|---|---|---|---|---|---|
| 38914372675 | WKWebView | start timed out at 120 s (test failed) | n/a | n/a | n/a |
| 38914372675 | JavaScriptCore | 12.4 s | 5.0 ms | 81.6 ms | 2182 ms |
| 39008388983 | WKWebView | 8.3 s | 0.96 ms | 3.88 ms | 29 ms |
| 39008388983 | JavaScriptCore | 12.9 s | 6.1 ms | 64.2 ms | 1527 ms |
| 39009055469 | WKWebView | 221.5 s | 3.03 ms | 28.1 ms | 341 ms |
| 39009055469 | JavaScriptCore | 1.3 s | 2.89 ms | 4.84 ms | 7.4 ms |
| 39041546444 | WKWebView | start timed out at the test's 60 s limit (test failed; the recovery test in the same run started in 7.4 s) | n/a | n/a | n/a |
| 39041546444 | JavaScriptCore | 1.6 s | 4.30 ms | 121 ms | 572 ms |
| 39042188312 | WKWebView | start timed out at the 300 s limit (301 s, test failed, nothing graded; the recovery test in the same run passed in 173 s) | n/a | n/a | n/a |
| 39043272792 | WKWebView | recovery smoke test timed out at its 120 s limit (151 s; fixture test skipped by the new opt-in); nothing graded | n/a | n/a | n/a |
| 39042188312 | JavaScriptCore | all vectors graded, 0 problems (test took 84.6 s including 200-iteration timing); warm-up/percentiles not recorded | n/a | n/a | n/a |
| 39043785640 (head) | WKWebView (non-gating step) | 526.8 s (recovery test passed in 15.5 s) | 15.4 ms | 372.9 ms | 3482 ms |
| 39043785640 (head) | JavaScriptCore | 3.1 s | 3.71 ms | 8.30 ms | 62.5 ms |

### macOS runner (`swift test`)

| Run | Runtime | Cold warm-up | p50 | p95 | max |
|---|---|---|---|---|---|
| 38914372675 | WKWebView | 3.1 s | 0.97 ms | 5.04 ms | 13.5 ms |
| 39008388983 | WKWebView | 2.5 s | 0.60 ms | 1.85 ms | 227 ms |
| 39009055469 | WKWebView | 2.9 s | 1.22 ms | 3.55 ms | 117 ms |
| 39043785640 (head) | WKWebView | 2.2 s | n/a | 2.25 ms | n/a |
| all four | JavaScriptCore | cannot start (no wasm SIMD) | n/a | n/a | n/a |

### What the variance says

- On the simulator the ranking is not stable. WKWebView p95 ranged 3.9 to 372.9 ms and its cold start 8.3 s to 527 s (four attempts timed out: 120 s, 60 s, 300 s, and the 120 s recovery smoke test; the head run started only after 527 s, so the fallback's simulator cost is an order of magnitude above the earlier samples); JavaScriptCore p95 ranged 4.8 to 121 ms and cold start 1.3 s to 12.9 s. Neither runtime wins consistently, and the best and worst single numbers of each overlap. Shared CI simulators are noisy; treat all of these as order-of-magnitude only.
- WKWebView on the macOS runner was steady (warm-up 2.2-3.1 s, p95 1.9-5.0 ms) but that host is not the iOS simulator and not a device.
- JavaScriptCore on the macOS runner never starts: the .NET loader asserts "doesn't support WASM SIMD"; `WebAssembly.validate` rejects SIMD there (simd=false; exceptions, bulk-memory, tail-call true). On the simulator the same probe says simd=true. JSC support is host/configuration dependent.
- JavaScriptCore needs a dedicated thread that pumps its run loop (wasm compile completion); implemented in `JSCoreGrader`.
- WebKit is used only through the Objective-C target `QGraderWebKit`: `import WebKit` in Swift autolinks `libswiftWebKit`, which the Xcode 16.4 / iOS 18.5 runtime lacked for test bundles and crashed the app and package tests at launch.

## Test policy

A runtime test is skipped only for a documented condition: JavaScriptCore with no wasm SIMD (macOS hosts), and the WKWebView fixture run on the iOS simulator, which is opt-in (`QGRADER_WEBVIEW_FIXTURES=1`). Reason: across five simulator runs WKWebView start-up took 8 s, 221 s, or timed out at 120 s, 60 s and 300 s (run 39042188312) with no vector ever graded, while another WKWebView in the same run sometimes started. Raising the limit further would not give a meaningful test. JavaScriptCore is the shipping runtime and gates; WKWebView is only the fallback. CI runs the WKWebView fixture suite on the simulator in a separate non-gating step (`continue-on-error`) so every run still records whether it started and its timings. It always runs, and gates, on macOS hosts (steady 2.2-3.1 s). `testRecoversAfterContentProcessTermination` was kept as a gating simulator smoke test first, but it also timed out at 120 s in run 39043272792 (JavaScriptCore passed in the same run), so it is opt-in on the simulator too and runs in the same non-gating step; both WKWebView tests gate on macOS hosts, where WKWebView starts in about 3 s. Once a fixture run is enabled, startup timeouts and grading failures fail it. `WebViewGrader` re-launches its web view after a web content process termination (`testRecoversAfterContentProcessTermination` simulates the callback; a real termination needs a device).

## Not verified (CI cannot show these)

- Real-device numbers. The simulator is a macOS process with a JIT; a shipping iOS app has no JIT in-process, so JavaScriptCore (in-process) is likely slower on device than the simulator figures, and its wasm SIMD support there is unproven (it is absent on the macOS runner). This is the main risk of the JavaScriptCore decision and needs a device check: does it start, cold start, p95, memory.
- Hidden WKWebView behaviour when the app is backgrounded or under memory pressure (real content-process kill).
- App Review (guideline 2.5.2) acceptance of the bundled wasm.

## Recommendation / status

The user chose JavaScriptCore (2026-10-17) after these conflicting measurements. The data does not by itself favour either runtime on the simulator; JavaScriptCore has the unresolved device/SIMD risk, WKWebView has unstable simulator start-up. Keep both behind `Grader`; `FallbackGrader(primary:fallback:)` lets JavaScriptCore be primary with WKWebView as fallback if the device check fails or startup throws. `warmUp()` should run at launch or sign-in, not on the first Check, since cold start was 1.3-12.9 s for JavaScriptCore and 2.2-527 s for WKWebView across runs.

## Open

- ja grader bundling and a backend-deploy build step (copy of web `fetch-grader`/`verify-grader`) are not done; `fetch-grader.mjs` handles both local artifacts and `--base <cdn> --version N`.
- The backend `features.yaml` `ios` key was not edited (no `ios` key yet).
