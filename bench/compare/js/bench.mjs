// JavaScript JSON benchmark: <node|bun|deno run --allow-read> bench.mjs <json-parse|simdjson> <input> <min-samples>
//   json-parse - the engine's built-in JSON.parse into plain objects and arrays (numbers as doubles):
//                V8 under Node and Deno, JavaScriptCore under Bun. JSON.parse takes a string, so the
//                harness decodes the UTF-8 file (TextDecoder) outside the timing.
//   simdjson   - Node only: simdjson_nodejs (npm simdjson 0.9.2, a native addon over a 2022 simdjson,
//                built by build.sh js) simdjson.parse(string) into plain JavaScript objects.
// The same script runs on all three runtimes (node:fs, process.hrtime.bigint). A .ndjson input is a
// batch: its lines are split before timing and each is parsed as its own document; one operation
// parses every line once. Prints the check line (see ../reference.py) first; exits 1 on a parse error.
// Timings follow the shared rule (see measure and ../run.sh); the 1 s warm-up also lets the JIT
// optimize.
import { readFileSync } from "node:fs";
import process from "node:process";
import { createRequire } from "node:module";

function measure(minSamples, op) {
  const warm = process.hrtime.bigint();
  do op();
  while (process.hrtime.bigint() - warm < 1_000_000_000n);
  const start = process.hrtime.bigint();
  const samples = [];
  for (;;) {
    const t0 = process.hrtime.bigint();
    op();
    samples.push(Number(process.hrtime.bigint() - t0));
    const sorted = [...samples].sort((a, b) => a - b);
    const n = sorted.length;
    const median = n % 2 ? sorted[(n - 1) / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
    if (n >= minSamples && samples.filter((s) => s >= median * 0.9 && s <= median * 1.1).length >= 0.6 * n)
      return { median, n, converged: true };
    if (n >= 1000 || process.hrtime.bigint() - start >= 10_000_000_000n) return { median, n, converged: false };
  }
}

// The bit pattern of a double (-0 counted as +0) as an unsigned 64-bit BigInt
const f64 = new Float64Array(1);
const u64 = new BigUint64Array(f64.buffer);
const MASK = (1n << 64n) - 1n;

// Code points: UTF-16 units that are not low surrogates
function chars(s) {
  let n = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0xdc00 || c > 0xdfff) n++;
  }
  return n;
}

// objects, arrays, keys, strings, numbers, true, false, null, chars, numsum
function walk(v, c) {
  if (v === null) c[7]++;
  else if (Array.isArray(v)) {
    c[1]++;
    for (const x of v) walk(x, c);
  } else if (typeof v === "object") {
    c[0]++;
    for (const k in v) {
      c[2]++;
      c[8] += chars(k);
      walk(v[k], c);
    }
  } else if (typeof v === "string") {
    c[3]++;
    c[8] += chars(v);
  } else if (typeof v === "number") {
    c[4]++;
    f64[0] = v + 0.0;
    c[9] = (c[9] + u64[0]) & MASK;
  } else if (v === true) c[5]++;
  else c[6]++;
}

const [variant, path, min] = process.argv.slice(2);
if (!["json-parse", "simdjson"].includes(variant) || !path || !min) {
  console.error("usage: bench.mjs <json-parse|simdjson> <input> <min-samples>");
  process.exit(2);
}
const parse = variant === "simdjson" ? createRequire(import.meta.url)("simdjson").parse : JSON.parse;
const bytes = readFileSync(path);
const total = bytes.length;
const text = new TextDecoder().decode(bytes);
const texts = path.endsWith(".ndjson") ? text.split("\n").filter((l) => l.trim() !== "") : [text];
const c = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0n];
try {
  for (const t of texts) walk(parse(t), c);
} catch (e) {
  console.error("parse error:", e.message);
  process.exit(1);
}
console.log(`check: ${c.slice(0, 9).join(" ")} ${c[9].toString(16).padStart(16, "0")}`);
let sink = 0;
const m = measure(Number(min), () => {
  for (const t of texts) sink ^= parse(t) === null ? 1 : 0;
});
const ms = m.median / 1e6;
console.log(`${ms.toFixed(3)} ms/op ${(total / 1048576 / (ms / 1000)).toFixed(1)} MB/s (n=${m.n}, ${m.converged ? "converged" : "capped"})`);
if (sink === 2) console.log(sink);
