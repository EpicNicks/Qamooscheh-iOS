# Qamooscheh iOS: port plan

**Status:** Draft v0.1 (2026-10-10). Sources of truth, in order: backend `API_SPEC.md` (contract), `features.yaml` (what exists where), Android `docs/SPEC.md` (design), Android code (behaviour), web code (fallback).
Paths: Android `E:/Code/Projects/Qamooscheh-Android`, Web `E:/Code/Projects/Qamooscheh-Web/Qamooscheh-Web`, Backend `C:/Users/epicn/source/repos/Qamooscheh`.

## 1. Constraints that shape everything

1. **No Swift compiler on this machine.** GitHub Actions on macOS is the only compiler, test runner and screenshot source. Every design choice below favours code that can be verified by `swift test` without a simulator.
2. **Agents work with light context** (section 6): small packages, one slice per task, files not conversation.
3. **Parity first.** Same backend and CDN, same wire types (ported from the C# contracts, not the TS), same grader artifact. No backend changes for parity.

## 2. Stack

| Concern | Choice |
|---|---|
| Language / UI | Swift 6 (language mode 5 until concurrency noise is understood), SwiftUI, iOS 17+ (`@Observable`, SwiftData-capable, NavigationStack) |
| Project generation | **XcodeGen** (`project.yml`); `.xcodeproj` is generated in CI and gitignored. Hand-editing a pbxproj blind is not an option |
| Modules | Local **SwiftPM packages**, one per concern, mirroring Android's modules (section 3) |
| HTTP | `URLSession` + `Codable`; a 401 -> refresh once -> retry actor, matching `httpClient.ts` |
| Persistence | SwiftData (or GRDB if SwiftData proves flaky on CI); offline queue keyed per user |
| Prefs / secrets | `UserDefaults` for prefs; tokens in Keychain |
| Background | `BGTaskScheduler` (queue flush, prefetch); `UNUserNotificationCenter` local reminders |
| TTS | `AVSpeechSynthesizer` |
| Google sign-in | `GoogleSignIn-iOS` SDK, same web client ID as `serverClientId` |
| Widgets / shortcuts | WidgetKit, App Intents (post-parity) |
| Tests | XCTest / Swift Testing in packages; `swift-snapshot-testing` for UI on a pinned simulator, PNGs uploaded as CI artifacts |
| CI | GitHub Actions, one pinned macOS image + Xcode version in one place (`.github/workflows/ci.yml`) |
| Release | fastlane `match` + TestFlight upload, needs Apple Developer account (section 8) |

## 3. Module layout

```
Packages/
  QModel        wire types (Codable) ported from C# *Contracts.cs, enums, content types   [no deps]
  QDomain       pure ports of web src/domain/* WITH their vitest tests as XCTest          [QModel]
  QNetwork      API client, auth/refresh actor, CDN client, SHA-256 verify                [QModel, CryptoKit]
  QData         repositories, store, offline queue, content cache (version-pinned, hash-addressed)   [QModel, QNetwork]
  QGrader       Grader protocol + runtime(s), fixture-driven verdict tests                [QModel]
  QDesign       tokens, theme, primitives (Button, Card, Modal)                           [SwiftUI]
  QKeyboard     key layouts + candidate-above-key logic, shared by in-app keyboard and extension
  QFeatures     SwiftUI screens grouped by folder: Auth, Onboarding, Learn, Lesson, Library, Words, Social, Profile
App/            thin app target: entry point, nav graph, DI wiring
KeyboardExt/    custom keyboard extension (post-parity, M8)
```

Rule: `QModel`, `QDomain`, `QKeyboard` (logic part) have no UIKit/SwiftUI imports so they also build and test on a Linux runner if we ever want cheap CI. Everything except `QDesign`/`QFeatures`/`App` must be verifiable by `swift test`.

## 4. The two real risks

### 4.1 Grader runtime (decided by a spike, like Android M1)
Android's outcome: WASI build on Chicory was ~100x too slow, so the **browser build on a JS engine** is primary. iOS has neither Chicory nor `androidx.javascriptengine`. Candidates, in the order the spike tries them:
1. **JavaScriptCore** (`JSContext`) running the browser bundle: fastest and no extra UI, but needs `WebAssembly` available in `JSContext` and the .NET loader's browser globals (`fetch`, `location`) shimmed. Android hit the same shim question.
2. **Hidden `WKWebView`** loading the bundle from a custom `WKURLSchemeHandler`, called via `callAsyncJavaScript`. Slower to warm, but a real browser engine; this is the safe fallback and the one most likely to work first.
3. **WasmKit** (pure-Swift WASM interpreter) on the WASI build. Expected too slow, same as Chicory; only if 1 and 2 fail.
4. **No local grading**: "Checked when you sync", server grades on submit (already the web's best-effort design).

The spike needs real timing, which only a CI simulator can give, so its pass criteria are relaxed to "correct verdicts on the fixture set, p95 recorded"; device timing comes from the first TestFlight build. Output: `docs/grader-spike.md`.
`Grader` protocol is copied from Android section 4.5 (`warmUp()`, batch `grade(_:)`), so feature code never knows which runtime is behind it.

### 4.2 The system keyboard (Android D7: "must")
iOS keyboard extensions cannot match Android's IME: no composing region, 48-60 MB memory cap, networking only with Full Access, and "candidate above the pressed key" must be drawn by us. Plan: ship the **in-app keyboard first** (M5, from `QKeyboard`), and treat the extension (M8) as a separate redesign with its own spike. This needs your decision on whether v1 ships without it.

## 5. Milestones (vertical slices; each ends green on CI)

| # | Milestone | Exit criteria (all checked by CI) |
|---|---|---|
| M0 | Skeleton | XcodeGen project builds for simulator; empty tab shell; all packages exist with one passing test each; CI workflow + snapshot artifact job working |
| M1 | Grader spike | Fixture verdicts match server on the chosen runtime; `docs/grader-spike.md` with chosen variant and fallback order |
| M2 | Model + network + auth | Wire types round-trip golden JSON; 401->refresh->retry tested with a stub `URLProtocol`; login/register/onboarding screens; manifest SHA-256 verify; full-course download per pinned version |
| M3 | Domain port | Every web `domain/*.test.ts` ported 1:1 and green (`pathProgress`, `roadLayout`, `exerciseResolution`, `answerFeedback`, `typedAnswerMarks`, `lessonScore`, ...) |
| M4 | Path | Road, nodes, popovers, goal ring, update banner and roll-forward; snapshot parity with web/Android screenshots |
| M5 | Lesson core + language layers | All exercise types, grader feedback, results, offline queue, TTS; Persian/Japanese in-app keyboards, RTL, furigana, fonts |
| M6 | Remaining screens | Story, checkpoint, practice, remix/themes, glossary, vocab, profile, friends, leagues, settings, help/about |
| M7 | Native integrations | Reminders + re-enable prompt, haptics, sound, share cards, shortcuts, deep links, widget, streak counter |
| M8 | Keyboard extension | Separate spike, then build |
| M9 | Release | Accessibility, signing, TestFlight upload from CI |

Order rationale: M2 and M3 are pure logic, so they can be verified with no UI and give the cheapest early CI feedback; UI milestones come after the foundation compiles.

## 6. Light-context strategy (the Android `sequential-issues` skill, adapted)

Copied to `.claude/skills/sequential-issues/`, with these iOS changes:

| Android | iOS |
|---|---|
| Developer runs Gradle locally | **Cannot build locally.** Dev pushes, opens PR immediately, CI is the compiler |
| 2 fix rounds | **5 fix rounds**: the fix loop is the compile loop |
| `master`, Gradle env rules | `master`, no local toolchain rule, XcodeGen rule |
| CI error regex for Kotlin/Gradle | Regex for `error:`, `BUILD FAILED`, XCTest failures |
| `features.yaml` `android` key | `ios` key (needs the backend change in section 9) |
| Roborazzi screenshots | Snapshot PNGs as CI artifacts, reviewer is told UI is unverified |

How context stays small:
1. **One item = one slice = one package or screen.** Item JSON names `allowedPaths` (e.g. `^Packages/QDomain/`), so the developer reads that package plus the Android/web source files the item names, nothing else.
2. **Items cite sources precisely**: "port `web:src/domain/roadLayout.ts` and its test; Android reference `core/domain/.../RoadLayout.kt`". The agent never surveys either repo.
3. **Agents pass files, not conversation**: `ledger/<item>/{brief-dev.md, dev.json, review.json, ci.json, ratify.json}`. A fresh reviewer and a fresh fixer each read only their brief and the failing CI lines (<=25).
4. **Scripted gates**: CI wait, ratify and merge are plain Node scripts (zero model tokens); a Haiku agent only relays one command's JSON.
5. **Anything needing a device, a visual check, or a design decision is held** for you, not guessed.
6. **This plan is read once by the human; agents get item briefs**, not this file. Keep `CLAUDE.md` short and point to the item.

## 7. CI design (`.github/workflows/ci.yml`, written in M0)

- Job `packages`: matrix over `Packages/*`, `swift test` (fast, cheap, the main signal).
- Job `app`: `xcodegen generate`, `xcodebuild build-for-testing` then `test-without-building` on a pinned simulator, `-resultBundlePath` uploaded on failure.
- Job `snapshots`: runs snapshot tests, uploads PNGs as artifacts (the only way I can see UI).
- macOS minutes cost 10x Linux: concurrency group cancels superseded runs; packages with no UI deps are candidates to move to Linux runners later.

## 8. What only you can do

1. Create the GitHub repo `EpicNicks/Qamooscheh-iOS` (or tell me the name) so PRs, Actions and the runner can work.
2. Apple Developer Program account; later: App Store Connect API key + `match` repo as GitHub secrets for signing/TestFlight (M9).
3. Google iOS OAuth client (and reversed client ID in Info.plist) for Google sign-in.
4. Visual and on-device checks (layout, haptics, keyboard feel) from simulator-screenshot artifacts / TestFlight.

## 9. Open decisions (recommended answers first)

1. **Backend ledger:** `features.yaml` allows exactly three surface keys and a test enforces it. Add an `ios` key (defaulting `not_yet`) in the backend repo; until then the runner's ledger step is skipped. *Recommended: yes, one small backend PR.*
2. **Minimum iOS:** 17. (16 would cost `@Observable`.)
3. **Bundle ID:** mirror Android: `com.parsling.ios` (dev: `.dev`).
4. **Keyboard extension in v1?** *Recommended: no. In-app keyboard only; extension is M8.*
5. **Persistence:** SwiftData vs GRDB. *Recommended: SwiftData, switch only if CI shows it flaky.*
6. **Default branch:** `master`.
