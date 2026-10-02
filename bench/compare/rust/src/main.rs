// Rust JSON benchmark: jsonbench <variant> <input> <min-samples>
//
// DOM (parse into the library's generic value, then drop it; the check walks the value once, untimed):
//   serde_json-value   - serde_json::from_slice::<serde_json::Value> (default features: BTreeMap
//                        objects, u64/i64/f64 numbers).
//   sonic-rs-value     - sonic_rs::from_slice::<sonic_rs::Value> (its own SIMD DOM parser).
//   simd-json-owned    - simd_json::to_owned_value (String keys and values). simd-json parses in
//                        place, so each document is first copied into a reused Vec<u8>; the copy is
//                        inside the timed region.
//   simd-json-borrowed - simd_json::to_borrowed_value (Cow strings borrowing the buffer), with the same
//                        copy.
//   jiter-value        - jiter::JsonValue::parse (pydantic's parser; Arc<Vec> arrays and objects).
// Typed (the json-benchmark schema in typed.rs, serde derives shared by all three; twitter,
// citm_catalog and canada only, else exit 3):
//   serde_json-typed   - serde_json::from_slice::<T>.
//   sonic-rs-typed     - sonic_rs::from_slice::<T>.
//   simd-json-typed    - simd_json::serde::from_slice::<T> over a copy in a reused Vec<u8> (timed).
// Streaming (one pass over every value without building one; keys and strings decoded and their
// lengths added, numbers converted to f64 and their bits summed, everything counted):
//   serde_json-visitor - serde_json::Deserializer driven by a DeserializeSeed/Visitor that walks the
//                        whole document (borrowed strings when unescaped, its scratch buffer when not).
//   jiter-iter         - jiter::Jiter pull iteration (peek, known_* for every value).
// Query (reference.py's on-demand queries; twitter, citm_catalog and canada only):
//   sonic-rs-get       - sonic_rs::get for the top-level array, then its lazy array iterators and
//                        LazyValue::pointer/get; values not on the path are skipped, never parsed.
//   jiter-query        - jiter::Jiter walking only the path, every other value skipped (next_skip).
//   serde_json-partial - serde_json::from_slice into structs holding only the queried fields (serde
//                        skips everything else with IgnoredAny).
//
// An input is a file, or a batch (.ndjson): one document per line, split before timing, each line
// its own buffer; one run parses every document once. Prints the check line (see ../reference.py)
// first. Exit 1: parse error; 2: usage; 3: the variant does not apply to this input. Timings follow
// the shared rule (see measure and ../run.sh).
use std::time::Instant;

mod dom;
mod query;
mod stream;
mod typed;

/// The rule shared by every harness in bench/compare (see ../run.sh): warm up for at least 1 s, then
/// time single runs until at least `min_samples` were taken and at least 60% lie within ±10% of their
/// median, or 10 s / 1000 samples have passed. Returns the median sample in ns.
pub fn measure(min_samples: usize, mut op: impl FnMut()) -> (f64, usize, bool) {
    let warm = Instant::now();
    loop {
        op();
        if warm.elapsed().as_secs_f64() >= 1.0 {
            break;
        }
    }
    let start = Instant::now();
    let mut samples: Vec<f64> = Vec::new();
    loop {
        let t0 = Instant::now();
        op();
        samples.push(t0.elapsed().as_nanos() as f64);
        let mut sorted = samples.clone();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let n = sorted.len();
        let median = if n % 2 == 1 { sorted[n / 2] } else { (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0 };
        if n >= min_samples {
            let within = samples.iter().filter(|&&s| s >= median * 0.9 && s <= median * 1.1).count();
            if within as f64 >= 0.6 * n as f64 {
                return (median, n, true);
            }
        }
        if n >= 1000 || start.elapsed().as_secs_f64() >= 10.0 {
            return (median, n, false);
        }
    }
}

/// The bit pattern of a double, -0 counted as +0
pub fn bits(d: f64) -> u64 {
    (d + 0.0).to_bits()
}

/// The dom/stream check (see ../reference.py). With `exact` off (timed streaming runs) string
/// lengths are UTF-8 bytes, which only need touching.
#[derive(Default, Clone, Copy)]
pub struct Tally {
    pub exact: bool,
    pub objects: u64,
    pub arrays: u64,
    pub keys: u64,
    pub strings: u64,
    pub numbers: u64,
    pub trues: u64,
    pub falses: u64,
    pub nulls: u64,
    pub chars: u64,
    pub numsum: u64,
}

impl Tally {
    pub fn new(exact: bool) -> Self {
        Tally { exact, ..Default::default() }
    }
    #[inline]
    fn len(&self, s: &str) -> u64 {
        if self.exact { s.chars().count() as u64 } else { s.len() as u64 }
    }
    #[inline]
    pub fn key(&mut self, s: &str) {
        self.keys += 1;
        self.chars += self.len(s);
    }
    #[inline]
    pub fn string(&mut self, s: &str) {
        self.strings += 1;
        self.chars += self.len(s);
    }
    #[inline]
    pub fn number(&mut self, d: f64) {
        self.numbers += 1;
        self.numsum = self.numsum.wrapping_add(bits(d));
    }
    #[inline]
    pub fn boolean(&mut self, b: bool) {
        if b { self.trues += 1 } else { self.falses += 1 }
    }
    pub fn line(&self) -> String {
        format!(
            "check: {} {} {} {} {} {} {} {} {} {:016x}",
            self.objects, self.arrays, self.keys, self.strings, self.numbers, self.trues, self.falses,
            self.nulls, self.chars, self.numsum
        )
    }
}

/// Exit 1 with the library's message (a parse error)
pub fn fail(e: impl std::fmt::Display) -> ! {
    eprintln!("parse error: {e}");
    std::process::exit(1)
}

#[derive(Clone, Copy, PartialEq)]
pub enum Kind {
    Twitter,
    Citm,
    Canada,
}

fn kind(path: &str) -> Option<Kind> {
    match path.rsplit('/').next().unwrap_or(path) {
        "twitter.json" => Some(Kind::Twitter),
        "citm_catalog.json" => Some(Kind::Citm),
        "canada.json" => Some(Kind::Canada),
        _ => None,
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 4 {
        eprintln!("usage: jsonbench <variant> <input> <min-samples>");
        std::process::exit(2);
    }
    let (variant, path) = (args[1].as_str(), args[2].as_str());
    let min_samples: usize = args[3].parse().unwrap_or(5);
    let file = std::fs::read(path).unwrap_or_else(|e| {
        eprintln!("cannot open {path}: {e}");
        std::process::exit(2)
    });
    let total = file.len();
    let docs: Vec<Vec<u8>> = if path.ends_with(".ndjson") {
        file.split(|&b| b == b'\n').filter(|l| !l.is_empty()).map(|l| l.to_vec()).collect()
    } else {
        vec![file]
    };

    let measured = if let Some(r) = dom::run(variant, &docs, min_samples) {
        r
    } else if let Some(r) = stream::run(variant, &docs, min_samples) {
        r
    } else if variant.ends_with("-typed") || matches!(variant, "sonic-rs-get" | "jiter-query" | "serde_json-partial") {
        let Some(k) = kind(path) else {
            eprintln!("{variant} applies to twitter, citm_catalog and canada only");
            std::process::exit(3)
        };
        if variant.ends_with("-typed") {
            typed::run(variant, k, &docs[0], min_samples)
        } else {
            query::run(variant, k, &docs[0], min_samples)
        }
    } else {
        eprintln!("unknown variant {variant}");
        std::process::exit(2)
    };
    let (median, n, converged) = measured;
    let ms = median / 1e6;
    println!(
        "{:.3} ms/op {:.1} MB/s (n={}, {})",
        ms,
        total as f64 / 1048576.0 / (ms / 1000.0),
        n,
        if converged { "converged" } else { "capped" }
    );
}
