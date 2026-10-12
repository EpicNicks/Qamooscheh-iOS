import fs from "node:fs"
const p = process.argv[2]
const raw = fs.readFileSync(p, "utf8")
try { JSON.parse(raw); console.log("already valid"); process.exit(0) } catch {}
// double any backslash that is not a valid JSON escape (and not already part of \\)
const s = raw.replace(/\\(\\|["\/bfnrt]|u[0-9a-fA-F]{4})|\\/g, (m, ok) => (ok ? m : "\\\\"))
JSON.parse(s)
fs.writeFileSync(p, s)
console.log("repaired")
