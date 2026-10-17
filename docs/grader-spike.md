# Grader spike (M1)

Artifact: `fa` browser grader **v98** from `cdn.parsling.com`, manifest sha256 `9615b4d995000200eb326ba62fb00c0a5194099125ebdc7a9960e19d83a48375`, every file verified against its manifest (`Packages/QGrader/scripts/fetch-grader.mjs`, `GraderBundle.verify()` test). Bundled in `Packages/QGrader/Sources/QGrader/Resources/grader/fa/v98/`.
Same build as Android/web; shim is Android's `grader-host.js` (JavaScriptCore) or the web's `main.mjs` loaded as an ES module (WKWebView).

Note: the local backend artifacts (`artifacts/grader/fa/browser/v1`) are stale (they fail the backend's own separator and xp vectors), so the latest published CDN build was bundled instead. `ja` is not bundled.

## Results (CI, GitHub Actions macos-15, Xcode 16.4)

Correctness = 15 `expect` vectors match exactly, the other 14 are interpreted (or refused for "unknown ..."), and 21 xp rows match through the grading call. Timings are warm single answers, n=200.

| Runtime | Host | Correct | Cold warm-up | p50 | p95 | max |
|---|---|---|---|---|---|---|
| WKWebView | iOS 18.5 simulator | 0 problems | 8.3 s | 0.96 ms | 3.88 ms | 29 ms |
| JavaScriptCore | iOS 18.5 simulator | 0 problems | 12.9 s | 6.1 ms | 64 ms | 1527 ms |
| WKWebView | macOS runner (swift test) | 0 problems | 2.5 s | 0.60 ms | 1.85 ms | 227 ms |
| JavaScriptCore | macOS runner (swift test) | cannot start | n/a | n/a | n/a | n/a |

- JavaScriptCore on the macOS runner: the .NET loader asserts "doesn't support WASM SIMD"; the probe shows `WebAssembly.validate` rejects SIMD there (simd=false; exceptions, bulk-memory, tail-call true). On the simulator the same probe says simd=true and the suite passes. So JSC support is host/configuration dependent.
- JavaScriptCore needs a dedicated thread that pumps its run loop (wasm compile completion); implemented in `JSCoreGrader`.
- WebKit is used only through the Objective-C target `QGraderWebKit`: `import WebKit` in Swift autolinks `libswiftWebKit`, which the Xcode 16.4 / iOS 18.5 runtime lacked for test bundles and crashed the app and package tests at launch.

## Not verified (CI cannot show these)

- Real-device numbers. The simulator is an x86/arm macOS process with a JIT; a shipping iOS app has no JIT in-process, so JavaScriptCore (in-process) is likely slower on device than the simulator figures, and its SIMD support there is unproven. WKWebView runs out of process with JIT.
- Hidden WKWebView behaviour when the app is backgrounded or under memory pressure.
- App Review (guideline 2.5.2) acceptance of the bundled wasm.

## Recommendation (final runtime is the user's decision)

Prefer the hidden WKWebView: correct everywhere measured, p95 under 4 ms, and does not depend on in-process wasm SIMD or JIT. Keep JavaScriptCore as the in-process alternative only if a device measurement shows an acceptable p95 and cold start; `FallbackGrader(primary:fallback:)` supports either order. Both sit behind the `Grader` protocol, so M5 code and tests are unaffected. Cold start (8-13 s on a CI simulator) means `warmUp()` should run at launch or at sign-in, not on the first Check.

## Open

- ja grader bundling and a backend-deploy build step (copy of web `fetch-grader`/`verify-grader`) are not done; `fetch-grader.mjs` handles both local artifacts and `--base <cdn> --version N`.
- The backend `features.yaml` `ios` key was not edited (no `ios` key yet).
