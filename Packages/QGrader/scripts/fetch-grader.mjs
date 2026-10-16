#!/usr/bin/env node
// Bundles a published browser grader into Sources/QGrader/Resources/grader/{lang}/v{N}/.
// Every file is verified against sha256+size in the build's manifest.json.
// Usage:
//   node scripts/fetch-grader.mjs [--lang fa] [--from <backend>/artifacts]   local backend artifacts (default)
//   node scripts/fetch-grader.mjs [--lang fa] --base https://cdn.parsling.com --version N
// Prints the manifest.json sha256 (the trust anchor bootstrap delivers).
import { createHash } from "node:crypto";
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const outRoot = join(here, "..", "Sources", "QGrader", "Resources", "grader");
const args = process.argv.slice(2);
const arg = (name, dflt) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : dflt; };
const lang = arg("--lang", "fa");
const base = arg("--base", null);
const from = arg("--from", process.env.GRADER_LOCAL_ARTIFACTS || "C:/Users/epicn/source/repos/Qamooscheh/artifacts");
const sha = (b) => createHash("sha256").update(b).digest("hex");

let version, read;
if (base) {
  version = Number(arg("--version", "0"));
  if (!version) throw new Error("--base needs --version N");
  const root = `${base.replace(/\/+$/, "")}/grader/${lang}/browser/v${version}`;
  read = async (p) => {
    const r = await fetch(`${root}/${p}`);
    if (!r.ok) throw new Error(`${root}/${p}: ${r.status}`);
    return new Uint8Array(await r.arrayBuffer());
  };
} else {
  const langDir = join(from, "grader", lang, "browser");
  version = Math.max(...readdirSync(langDir).map((d) => /^v(\d+)$/.exec(d)).filter(Boolean).map((m) => Number(m[1])));
  const root = join(langDir, `v${version}`);
  read = async (p) => readFileSync(join(root, p));
}

const manifestBytes = await read("manifest.json");
const manifest = JSON.parse(new TextDecoder().decode(manifestBytes));
if (manifest.language !== lang || manifest.variant !== "browser" || manifest.version !== version) throw new Error("manifest does not match request");
const dest = join(outRoot, lang, `v${version}`);
rmSync(join(outRoot, lang), { recursive: true, force: true });
for (const { path, sha256, size } of manifest.files) {
  if (path.includes("..") || path.startsWith("/")) throw new Error(`unsafe path ${path}`);
  const bytes = await read(path);
  if (sha(bytes) !== sha256.toLowerCase() || bytes.length !== size) throw new Error(`${path}: sha256/size mismatch`);
  mkdirSync(dirname(join(dest, path)), { recursive: true });
  writeFileSync(join(dest, path), bytes);
}
writeFileSync(join(dest, "manifest.json"), manifestBytes);
console.log(`${lang}: browser v${version}, manifest sha256 ${sha(manifestBytes)} (${manifest.files.length} files verified)`);
