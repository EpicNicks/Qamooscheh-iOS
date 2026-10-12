// node ratify.mjs <item> [--merge] [--accept-deviations] : the deterministic gate. Prints {decision: merge|hold, reasons, merged?}.
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { BASE, REPOS, ghJson, git, ledgerDir, loadItem, out, readJson, writeJson } from "./common.mjs"
import { ciOnce } from "./ci.mjs"

const name = process.argv[2]
const doMerge = process.argv.includes("--merge")
const item = loadItem(name)
const L = ledgerDir(name)
const repo = REPOS[item.repo]
const reasons = []
const hold = (r) => reasons.push(r)
const finish = (result) => { writeJson(`${L}/ratify.json`, result); out(result); process.exit(0) }

const state = readJson(`${L}/state.json`, {})
const dev = readJson(`${L}/dev.json`)
const review = readJson(`${L}/review.json`)
if (state.merged) finish({ name, decision: "hold", reasons: ["already merged"] })
if (!dev) finish({ name, decision: "hold", reasons: ["no dev.json"] })

if (dev.needsUser) hold(`dev needs the user: ${dev.needsUser}`)
// --accept-deviations may lift this one hold, but only after the checks below have passed (see the end).
const acceptDeviations = process.argv.includes("--accept-deviations")
let devHoldIdx = -1
if (dev.deviations?.length) { devHoldIdx = reasons.length; hold(`deviations from the plan need the user: ${dev.deviations.join(" | ").slice(0, 300)}`) }
const safe = { reviewClean: false, headMatches: false, ciGreen: false, files: null, stray: [] }

// A PR is optional (project rule: no new PRs). If dev.json names an existing one, still read its body/state.
let pr = null
if (typeof dev.pr === "number") {
  try { pr = ghJson(item.repo, ["api", `repos/${repo.slug}/pulls/${dev.pr}`]) } catch (e) { finish({ name, decision: "hold", reasons: [`cannot read PR: ${e.message}`] }) }
  if (pr.state !== "open") hold(`PR is ${pr.state}`)
}
let head
try { head = ciOnce(item).head } catch (e) { finish({ name, decision: "hold", reasons: [`cannot read branch ${item.branch}: ${e.message}`.slice(0, 200)] }) }
if (pr && pr.head.sha !== head) hold(`PR head ${pr.head.sha.slice(0, 7)} differs from branch head ${head.slice(0, 7)}`)

// The review must be of the current head, with no blocker/high findings.
if (!review) hold("no review.json")
else {
  if (review.head !== head) hold(`review is of ${String(review.head).slice(0, 7)}, branch head is ${head.slice(0, 7)}`)
  const bad = (review.findings ?? []).filter((f) => f.severity === "blocker" || f.severity === "high")
  if (bad.length) hold(`${bad.length} open blocker/high finding(s)`)
  safe.headMatches = review.head === head
  safe.reviewClean = bad.length === 0
}

// CI green on this exact head.
try {
  const ci = ciOnce(item)
  if (!ci.done) hold("CI not finished")
  else if (!ci.allGreen) hold("CI not green")
  else safe.ciGreen = ci.head === head
} catch (e) { hold(`cannot read CI: ${e.message}`.slice(0, 200)) }

// Current with the base branch, and diff hygiene.
git(item.repo, ["fetch", "-q"])
const br = `origin/${item.branch}`
if (git(item.repo, ["rev-parse", "--verify", "-q", br]).status !== 0) hold(`branch ${br} not found`)
else {
  if (git(item.repo, ["merge-base", "--is-ancestor", `origin/${BASE}`, br]).status !== 0) hold(`branch is behind ${BASE}`)
  const files = git(item.repo, ["diff", "--name-only", `origin/${BASE}...${br}`]).out.split("\n").filter(Boolean)
  const res = item.allowedPaths.map((p) => new RegExp(p))
  const stray = files.filter((f) => !res.some((r) => r.test(f)))
  safe.files = files
  safe.stray = stray
  if (stray.length) hold(`files outside the allowed paths: ${stray.slice(0, 5).join(", ")}`)
  if (item.requiresDocs && !files.some((f) => f.startsWith("docs/"))) hold("no docs/ change")
  const added = git(item.repo, ["diff", `origin/${BASE}...${br}`]).out.split("\n").filter((l) => l.startsWith("+") && !l.startsWith("+++")).join("\n")
  if (/(ghp_|gho_|github_pat_)[A-Za-z0-9_]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY/.test(added)) hold("a token or private key appears in the diff")
  const msgs = git(item.repo, ["log", `origin/${BASE}..${br}`, "--format=%B"]).out
  if (/co-authored-by|generated with \[?claude/i.test([msgs, pr?.body ?? "", ...(dev.unverified ?? [])].join("\n"))) hold("attribution in a commit message, the PR body or dev.unverified")
}
// Without a PR the unverified list is written into the merge commit message below, so it is always listed.
if (pr && dev.unverified?.length && !/not verified|unverified/i.test(pr.body ?? "")) hold("unverified items are not listed in the PR body")

// Lift only the deviations hold, and only when every safety condition is met.
let acceptedDeviations = 0
if (acceptDeviations && devHoldIdx >= 0 && safe.reviewClean && safe.headMatches && safe.ciGreen && safe.files
    && (item.reviewer || "opus") !== "opus"
    && !safe.files.some((f) => /(Network|Keychain|Token)/i.test(f))
    && safe.stray.length === 0) {
  reasons.splice(devHoldIdx, 1)
  acceptedDeviations = dev.deviations.length
}

const result = { name, decision: reasons.length ? "hold" : "merge", reasons }
if (acceptedDeviations && result.decision === "merge") {
  result.acceptedDeviations = acceptedDeviations
  fs.mkdirSync(L, { recursive: true })
  const stamp = new Date().toISOString()
  fs.appendFileSync(`${L}/deviations.md`, dev.deviations.map((d) => `- ${head} ${stamp}: ${d}\n`).join(""))
}
if (result.decision === "merge" && doMerge) {
  // Merge directly: clean detached checkout of origin/master, --no-ff merge of the branch, push master.
  git(item.repo, ["fetch", "-q"])
  const rest = (review.findings ?? []).filter((x) => x.severity === "medium" || x.severity === "low")
  const NL = "\n"
  const msg = [`Merge ${item.branch}: ${item.title}`, "",
    `Independent review of ${head.slice(0, 7)} found no open blocker or high findings; CI green on all jobs.`,
    ...(rest.length ? [`Remaining notes: ${rest.map((x) => `${x.file}:${x.line} ${x.summary}`).join("; ")}.`] : []),
    ...(dev.unverified?.length ? ["", "Not verified:", ...dev.unverified.map((u) => "- " + u)] : [])].join(NL) + NL
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "qm-merge-"))
  const m = { merged: false, why: "" }
  try {
    const add = git(item.repo, ["worktree", "add", "--detach", tmp, `origin/${BASE}`])
    if (add.status !== 0) m.why = `worktree add failed: ${add.err.trim().slice(0, 150)}`
    else {
      const mg = git(item.repo, ["merge", "--no-ff", "-m", msg, `origin/${item.branch}`], tmp)
      if (mg.status !== 0) { git(item.repo, ["merge", "--abort"], tmp); m.why = `merge failed: ${(mg.err || mg.out).trim().slice(0, 150)}` }
      else {
        const push = git(item.repo, ["push", "origin", `HEAD:${BASE}`], tmp)
        if (push.status !== 0) m.why = `push failed: ${push.err.trim().slice(0, 150)}`
        else m.merged = true
      }
    }
  } finally {
    git(item.repo, ["worktree", "remove", "--force", "--force", tmp])
    try { fs.rmSync(tmp, { recursive: true, force: true }) } catch {}
    git(item.repo, ["worktree", "prune"])
  }
  result.merged = m.merged
  if (m.merged) {
    git(item.repo, ["push", "origin", "--delete", item.branch])
    if (state.worktree) {
      git(item.repo, ["worktree", "remove", "--force", "--force", state.worktree])
      if (fs.existsSync(state.worktree)) { try { fs.rmSync(state.worktree, { recursive: true, force: true }) } catch {} }
    }
    git(item.repo, ["worktree", "prune"])
    git(item.repo, ["branch", "-D", item.branch])
    for (const b of git(item.repo, ["branch", "--list", "worktree-agent-*"]).out.split("\n").map((s) => s.trim().replace(/^[*+]\s*/, "")).filter(Boolean)) git(item.repo, ["branch", "-D", b])
    git(item.repo, ["fetch", "-q"])
    if (git(item.repo, ["rev-parse", "--abbrev-ref", "HEAD"]).out.trim() === BASE && !git(item.repo, ["status", "--porcelain"]).out.trim()) git(item.repo, ["merge", "-q", "--ff-only", `origin/${BASE}`])
    writeJson(`${L}/state.json`, { ...state, merged: true, pr: dev.pr ?? null })
  } else {
    result.decision = "hold"
    result.reasons.push(`direct merge refused: ${m.why}`)
  }
}
finish(result)
