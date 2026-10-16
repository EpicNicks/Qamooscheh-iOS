// Loads the .NET "browser" grader bundle inside a bare V8 context: no fetch,
// no ES module loader, no DOM, no timers. The embedder supplies, before
// evaluating this script:
//   __qmReadText(path)   -> Promise<string>       (a bundle file as UTF-8)
//   __qmReadBinary(path) -> Promise<ArrayBuffer>  (a bundle file as bytes)
//   __qmLog(message)     -> void                  (optional diagnostics)
// Paths are relative to the bundle root ("main.mjs", "_framework/dotnet.js").
//
// After evaluation, `globalThis.__qmGraderReady` is a Promise resolving once
// the runtime is up. Then `globalThis.__qmGradeEnvelopes(json)` takes a JSON
// array of GraderRequest and returns a JSON array of GraderResponse.
(function () {
  "use strict";
  const BASE = "https://grader.invalid/";
  const log = typeof __qmLog === "function" ? __qmLog : function () {};

  // ---- minimal globals the .NET loader and Emscripten reach for ----------
  const g = globalThis;
  if (typeof g.console === "undefined") {
    const out = (...a) => log(a.map(String).join(" "));
    g.console = { log: out, info: out, warn: out, error: out, debug: out, trace: out, assert: (c, ...a) => { if (!c) out(...a); } };
  }
  if (typeof g.setTimeout === "undefined") {
    // No real timers in the isolate. The runtime only uses them to yield,
    // so running the callback on the next microtask is enough.
    let nextId = 1;
    const cancelled = new Set();
    g.setTimeout = (fn, _ms, ...args) => {
      const id = nextId++;
      Promise.resolve().then(() => { if (!cancelled.delete(id)) fn(...args); });
      return id;
    };
    g.clearTimeout = (id) => { cancelled.add(id); };
    g.setInterval = () => { throw new Error("setInterval is not available in the grader host"); };
    g.clearInterval = () => {};
  }
  if (typeof g.performance === "undefined") {
    const start = Date.now();
    g.performance = { now: () => Date.now() - start };
  }
  if (typeof g.crypto === "undefined") {
    // Only used for hash seeds and GUIDs, never for anything secret here.
    g.crypto = { getRandomValues: (a) => { for (let i = 0; i < a.length; i++) a[i] = Math.floor(Math.random() * 256); return a; } };
  }

  if (typeof g.URL === "undefined") {
    // Just enough of URL for the loader: absolute http(s) URLs and paths
    // relative to one. No query/hash semantics beyond keeping them attached.
    const URLLite = function (spec, base) {
      spec = String(spec);
      let href;
      if (/^[a-z][a-z0-9+.-]*:/i.test(spec)) href = spec;
      else {
        if (base === undefined) throw new TypeError("Invalid URL: " + spec);
        const b = new URLLite(base).href;
        const origin = b.match(/^[a-z]+:\/\/[^/]*/i)[0];
        let dir = spec.startsWith("/") ? "" : b.slice(origin.length).split(/[?#]/)[0].replace(/[^/]*$/, "");
        const parts = (dir + spec).split("/");
        const out = [];
        for (const p of parts) {
          if (p === "..") out.pop();
          else if (p !== ".") out.push(p);
        }
        href = origin + out.join("/").replace(/^(?!\/)/, "/");
      }
      this.href = href;
      const m = href.match(/^([a-z][a-z0-9+.-]*:)(?:\/\/([^/?#]*))?([^?#]*)(\?[^#]*)?(#.*)?$/i) || [];
      this.protocol = m[1] || "";
      this.host = this.hostname = m[2] || "";
      this.origin = this.protocol + "//" + this.host;
      this.pathname = m[3] || "/";
      this.search = m[4] || "";
      this.hash = m[5] || "";
    };
    URLLite.prototype.toString = function () { return this.href; };
    g.URL = URLLite;
  }

  // ---- in-memory Response, enough for the loader's resource paths ---------
  function makeResponse(path, bodyPromise) {
    return bodyPromise.then((buf) => ({
      ok: true,
      status: 200,
      statusText: "OK",
      url: BASE + path,
      type: "basic",
      // No content type: WebAssembly.instantiateStreaming (where it exists)
      // insists on a real Response, so steer the loader to arrayBuffer().
      headers: { get: () => null },
      arrayBuffer: () => Promise.resolve(buf),
      json: () => Promise.resolve(JSON.parse(new TextDecoderLite().decode(buf))),
      text: () => Promise.resolve(new TextDecoderLite().decode(buf)),
      clone() { return this; },
    }));
  }

  // UTF-8 decoding without relying on TextDecoder being present.
  function TextDecoderLite() {}
  TextDecoderLite.prototype.decode = function (buf) {
    if (typeof TextDecoder !== "undefined") return new TextDecoder().decode(buf);
    const bytes = new Uint8Array(buf);
    let s = "";
    for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
    return decodeURIComponent(escape(s));
  };

  // Every network read the runtime attempts is served from the bundle. There
  // is no network in the isolate, and this grader never needs one.
  g.fetch = (input) => {
    const url = typeof input === "string" ? input : input.url;
    const path = resolve(url, "_framework/dotnet.js");
    if (path === null) return Promise.reject(new TypeError("grader host: no network for " + url));
    return makeResponse(path, __qmReadBinary(path));
  };

  // ---- ES modules -> functions ---------------------------------------------
  // Each bundle module has no static imports and a single trailing export.
  // It's rewritten into an async function body that returns its exports;
  // `import.meta` becomes a parameter and dynamic `import()` goes through the
  // registry below.
  const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
  const modules = new Map(); // path -> Promise<namespace>

  function transform(path, src) {
    let exportsExpr = null;
    src = src.replace(/\/\/# sourceMappingURL=.*$/m, "");
    // export{a as b,c}
    src = src.replace(/(^|[;}\n])\s*export\s*\{([^}]*)\}\s*;?/, (_, pre, list) => {
      const pairs = list.split(",").map((s) => s.trim()).filter(Boolean).map((item) => {
        const m = item.split(/\s+as\s+/);
        return JSON.stringify(m[1] || m[0]) + ":" + m[0];
      });
      exportsExpr = "{" + pairs.join(",") + "}";
      return pre;
    });
    // export default X
    src = src.replace(/(^|[;}\n])\s*export\s+default\s+([\w$]+)\s*;?/, (_, pre, name) => {
      exportsExpr = "{default:" + name + "}";
      return pre;
    });
    // export const NAME = ...
    const named = [];
    src = src.replace(/(^|[;\n])\s*export\s+const\s+([\w$]+)/g, (_, pre, name) => {
      named.push(name);
      return pre + "const " + name;
    });
    if (named.length) exportsExpr = "{" + named.map((n) => JSON.stringify(n) + ":" + n).join(",") + "}";
    if (exportsExpr === null) throw new Error("grader host: no export found in " + path);
    if (/(^|[;}\n])\s*export(\s+(default|const|let|var|function|class|async)\b|\s*[{*])/.test(src)) throw new Error("grader host: unsupported export form in " + path);
    src = src.replace(/import\.meta/g, "__qm_meta");
    src = src.replace(/(^|[^\w$.])import\s*\(/g, "$1__qm_import(");
    return src + "\n;return " + exportsExpr + ";";
  }

  function resolve(spec, fromPath) {
    if (spec.startsWith(BASE)) return spec.slice(BASE.length).split("?")[0];
    const u = new URL(spec, BASE + fromPath);
    return u.href.startsWith(BASE) ? u.href.slice(BASE.length).split("?")[0] : null;
  }

  function importModule(path) {
    let p = modules.get(path);
    if (!p) {
      p = __qmReadText(path).then((src) => {
        const fn = new AsyncFunction("__qm_meta", "__qm_import", transform(path, src));
        const meta = { url: BASE + path };
        return fn(meta, (spec) => {
          const target = resolve(String(spec), path);
          if (target === null) return Promise.reject(new Error("grader host: can't import " + spec));
          return importModule(target);
        });
      });
      modules.set(path, p);
    }
    return p;
  }

  // ---- boot ----------------------------------------------------------------
  g.__qmGraderReady = (async () => {
    const { dotnet } = await importModule("_framework/dotnet.js");
    const api = await dotnet
      .withResourceLoader((type, name, defaultUri) => {
        const path = resolve(defaultUri, "_framework/dotnet.js");
        if (type === "dotnetjs" || type === "manifest") return defaultUri; // goes through __qm_import
        return makeResponse(path, __qmReadBinary(path));
      })
      .create();
    const mainAssembly = api.getConfig().mainAssemblyName; // e.g. Qamooscheh.Persian.Grader.Browser.dll
    const exports = await api.getAssemblyExports(mainAssembly);
    // Each language's shim exposes GraderExports in a namespace named after
    // its assembly (Qamooscheh.<Language>.Grader.Browser).
    const ns = mainAssembly.replace(/\.dll$/, "").split(".").reduce((o, k) => o && o[k], exports);
    if (!ns || !ns.GraderExports) throw new Error("grader host: no GraderExports in " + mainAssembly);
    const graderExports = ns.GraderExports;
    g.__qmGradeEnvelopes = (json) =>
      JSON.stringify(JSON.parse(json).map((r) => JSON.parse(graderExports.GradeEnvelope(JSON.stringify(r)))));
    // The first real call pays for lazy assembly/JIT setup (~0.5 s on an
    // emulator). Pay it here, inside warm-up, instead of on the first Check.
    graderExports.GradeEnvelope(JSON.stringify({
      exerciseType: "TypeIn", scriptMode: "Native", submitted: "a", acceptedAnswers: ["a"],
    }));
    return "ready";
  })();
})();
