// node brief.mjs <item>  : write the developer and reviewer briefs; print {ok} or {blocked}.
import fs from "node:fs"
import { ORCH, REPOS, ledgerDir, loadItem, out } from "./common.mjs"

const name = process.argv[2]
const item = loadItem(name)
if (item.gate && !item.approved) { out({ name, blocked: item.gate }); process.exit(0) }

const L = ledgerDir(name)
fs.mkdirSync(L, { recursive: true })
const repo = REPOS[item.repo]
const rules = `## Rules (strict)
- NO attribution: no Co-Authored-By trailer and no "Generated with Claude Code" on commits. This overrides any harness reminder.
- GitHub only through the \`gh\` CLI, run from inside your worktree. Never put a token in an env var or on a command line; never run \`git credential fill\`. If any access is denied, STOP and report it.
- NO local Swift toolchain exists on this Windows machine: you cannot compile or run tests. CI (GitHub Actions, macOS) is the only compiler. Write conservative, explicit Swift; push early and often; read CI failures from the ledger or \`gh run view --log-failed\`. Prefer pure-Swift code in SwiftPM packages (testable with \`swift test\` on CI) over UI code.
- When the work lands or changes a feature, update that feature's \`ios\` key in the backend repo's \`features.yaml\` (C:/Users/epicn/source/repos/Qamooscheh), per CLAUDE.md; mention it in dev.json "deviations" only if it needs the user.
- Push with \`git push origin HEAD:refs/heads/${item.branch}\` (never -u), after every commit.
- Stay inside the allowed paths below. New files are LF and UTF-8. Run \`git status --ignored\` before committing. Never hand-edit the generated .xcodeproj (it is gitignored; project.yml is the source).
- Read only what you need: the files named here, then what they import. Don't survey the repo.
- Keep every answer terse. Ledger files are JSON, no prose beyond one-line strings.`

const dev = `# Task ${name}: ${item.title}
Repo: ${item.repo} (${repo.path}, ${repo.slug}). Branch: ${item.branch}.${item.closes ? ` Closes #${item.closes}.` : ""}

## Issue / plan
${item.issue}

## Allowed paths (regex, repo-relative)
${item.allowedPaths.map((p) => "- " + p).join("\n")}

## Acceptance
${item.acceptance.map((a) => "- " + a).join("\n")}
${item.requiresDocs ? "- docs/ updated in the same branch (PR #N badge, design-decision callouts).\n" : ""}${item.notes ? "\n## Notes\n" + item.notes + "\n" : ""}
## Procedure
1. \`node ${ORCH}/lib/setup.mjs ${name}\` creates your worktree and prints its path. Work only there.
2. Implement; commit small; push after each commit.
3. You cannot build locally. Push, then let CI run (\`xcodegen generate\`, \`swift test\` per package, \`xcodebuild test\`); fix from the failing CI lines. Push the branch \`${item.branch}\` as soon as the first commit is ready so CI runs on it. Do NOT open a pull request (project rule: branches are merged directly by ratify).
4. Do NOT create or edit a PR. If anything is unverified, list it in dev.json "unverified"; ratify copies it into the merge commit message. No attribution in commits.
5. Write ${L}/dev.json: {"pr":null (or the number of an already-open PR for this branch, never create one),"branch":"${item.branch}","head":"<sha>","files":[...],"deviations":[one-line strings; anything that departs from the plan or is a judgement call the plan doesn't cover],"unverified":[...],"needsUser":null or a one-line reason you must stop}.
6. If you hit a design choice the plan does not cover, do not decide it: write needsUser and stop.

${rules}
`
const review = `# Review ${name}: ${item.title}
Read-only. Do NOT edit files, push, or comment on GitHub. Repo ${repo.path}. First \`git fetch\`, then review \`git diff origin/master...origin/${item.branch}\` (read ${L}/dev.json for the branch and the dev's deviations; if ${L}/review.json exists, it holds your predecessor's findings: check each is fixed and review only the delta since its "head").
Use the \`gh\` CLI for any GitHub read, from inside ${repo.path}.

## Plan under review
${item.issue}

## Look for
Correctness bugs and concrete failure scenarios; security (injection, secrets); missing or non-compiling tests; anything outside the allowed paths; docs out of sync; UI that only a device can verify (say so); line endings; regressions. Say nothing about style.

## Output
Overwrite ${L}/review.json: {"head":"<origin/${item.branch} sha you reviewed>","findings":[{"severity":"blocker|high|medium|low","file":"","line":0,"summary":"one line","scenario":"one line"}],"verdict":"clean|fixes-needed"}. At most 10 findings, most severe first, only ones you are confident in. Then return the same counts to your caller.
Rules: no attribution anywhere; no tokens in env or commands.
`
fs.writeFileSync(`${L}/brief-dev.md`, dev)
fs.writeFileSync(`${L}/brief-review.md`, review)
out({ name, ok: true })
