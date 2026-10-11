// Shared helpers for the orchestrator scripts. Zero dependencies (Node 22).
import { spawnSync } from "node:child_process"
import fs from "node:fs"
import path from "node:path"

import { fileURLToPath } from "node:url"
export const ORCH = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..").split(path.sep).join("/")
export const REPOS = {
  ios: { path: "E:/Code/Projects/Qamooscheh-iOS", slug: "EpicNicks/Qamooscheh-iOS" },
}

export const ledgerDir = (name) => `${ORCH}/ledger/${name}`
export const readJson = (file, fallback = null) => {
  try { return JSON.parse(fs.readFileSync(file, "utf8")) } catch { return fallback }
}
export const writeJson = (file, value) => {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + "\n")
}
export function loadItem(name) {
  const item = readJson(`${ORCH}/items/${name}.json`)
  if (!item) throw new Error(`no item file items/${name}.json`)
  if (!REPOS[item.repo]) throw new Error(`item ${name}: repo must be ios`)
  return item
}

// gh CLI, already authenticated for this repo; BASE is the default branch.
export function gh(repoKey, args, cwd) {
  const r = spawnSync("gh", args,{ cwd: cwd ?? REPOS[repoKey].path, encoding: "utf8", maxBuffer: 256 << 20 })
  return { out: r.stdout ?? "", err: r.stderr ?? "", status: r.status }
}
export function ghJson(repoKey, args, cwd) {
  const r = gh(repoKey, args, cwd)
  if (!r.out.trim()) throw new Error(`gh ${args.join(" ")}: empty output (${r.err.trim().slice(0, 200)})`)
  return JSON.parse(r.out)
}
export function git(repoKey, args, cwd) {
  const r = spawnSync("git", args, { cwd: cwd ?? REPOS[repoKey].path, encoding: "utf8", maxBuffer: 256 << 20 })
  return { out: r.stdout ?? "", err: r.stderr ?? "", status: r.status }
}
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
export const out = (value) => console.log(JSON.stringify(value))
export const BASE = "master"
