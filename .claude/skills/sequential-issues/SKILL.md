---
name: sequential-issues
description: Work Qamooscheh-iOS port items one at a time with light-context agents that pass files, not conversation. Use when asked to run, continue or add port items (develop -> CI + fresh review -> up to 5 fix rounds -> scripted ratify and merge).
---

# Sequential item runner (iOS)

Adapted from Qamooscheh-Android's skill. Per item: Develop -> (CI wait || fresh reviewer) -> up to 5 fix rounds -> scripted ratify and merge.
Items run strictly one after another; `needs-user` stops the queue. Agents share only `ledger/<name>/`.

## Steps
1. List `items/*.json`. An item with `gate` set and `approved: false` is blocked: propose a design to the user, then write it into `issue` and set `approved: true`.
2. For each approved item: `node lib/brief.mjs <name>`.
3. Launch the Workflow: `{scriptPath: "E:/Code/Projects/Qamooscheh-iOS/.claude/skills/sequential-issues/run.workflow.js", args: {items: [{name, reviewer}, ...]}}` in queue order. Start with one item the first time.
4. Report one line per item: merged, held (reasons) or needs-user. Read only ledger files of held items.
5. After a merge: update the item's `ios` key in the backend `features.yaml` (once that key exists), close the issue.

Without the Workflow tool, follow `ORCHESTRATOR.md` (a paste-ready orchestrator prompt).

## Rules
- No local Swift toolchain: CI is the compiler. Prefer logic in SwiftPM packages so `swift test` proves it.
- Never hand-edit a generated `.xcodeproj`; edit `project.yml`.
- No attribution trailer/footer in commits or PR bodies (ratify holds on it).
- Anything off-plan, needing a design decision, a device, or a visual check is held and brought to the user.
- Requires: a GitHub remote `EpicNicks/Qamooscheh-iOS` with branch `master` and `gh` authenticated.

## Item file (`items/<name>.json`)
`name, repo ("ios"), branch, title, closes, issue (plan text naming exact web/Android source files to read), allowedPaths (regexes), acceptance, requiresDocs, allowProtocol (unused), gate, approved, reviewer (opus|sonnet)`.
