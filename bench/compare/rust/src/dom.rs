// DOM variants: parse into the library's generic value and drop it (timed); walk it once for the check.
use crate::{fail, measure, Tally};
use std::hint::black_box;

fn walk_serde(v: &serde_json::Value, t: &mut Tally) {
    use serde_json::Value;
    match v {
        Value::Null => t.nulls += 1,
        Value::Bool(b) => t.boolean(*b),
        Value::Number(n) => t.number(n.as_f64().unwrap()),
        Value::String(s) => t.string(s),
        Value::Array(a) => {
            t.arrays += 1;
            a.iter().for_each(|x| walk_serde(x, t));
        }
        Value::Object(o) => {
            t.objects += 1;
            for (k, x) in o {
                t.key(k);
                walk_serde(x, t);
            }
        }
    }
}

fn walk_sonic(v: &sonic_rs::Value, t: &mut Tally) {
    use sonic_rs::{JsonContainerTrait, JsonType, JsonValueTrait};
    match v.get_type() {
        JsonType::Null => t.nulls += 1,
        JsonType::Boolean => t.boolean(v.as_bool().unwrap()),
        JsonType::Number => t.number(v.as_f64().unwrap()),
        JsonType::String => t.string(v.as_str().unwrap()),
        JsonType::Array => {
            t.arrays += 1;
            v.as_array().unwrap().iter().for_each(|x| walk_sonic(x, t));
        }
        JsonType::Object => {
            t.objects += 1;
            for (k, x) in v.as_object().unwrap().iter() {
                t.key(k);
                walk_sonic(x, t);
            }
        }
    }
}

fn walk_static(s: &simd_json::StaticNode, t: &mut Tally) {
    use simd_json::StaticNode;
    match s {
        StaticNode::Null => t.nulls += 1,
        StaticNode::Bool(b) => t.boolean(*b),
        StaticNode::I64(i) => t.number(*i as f64),
        StaticNode::U64(u) => t.number(*u as f64),
        StaticNode::F64(f) => t.number(*f),
    }
}

fn walk_owned(v: &simd_json::OwnedValue, t: &mut Tally) {
    use simd_json::OwnedValue as V;
    match v {
        V::Static(s) => walk_static(s, t),
        V::String(s) => t.string(s),
        V::Array(a) => {
            t.arrays += 1;
            a.iter().for_each(|x| walk_owned(x, t));
        }
        V::Object(o) => {
            t.objects += 1;
            for (k, x) in o.iter() {
                t.key(k);
                walk_owned(x, t);
            }
        }
    }
}

fn walk_borrowed(v: &simd_json::BorrowedValue, t: &mut Tally) {
    use simd_json::BorrowedValue as V;
    match v {
        V::Static(s) => walk_static(s, t),
        V::String(s) => t.string(s),
        V::Array(a) => {
            t.arrays += 1;
            a.iter().for_each(|x| walk_borrowed(x, t));
        }
        V::Object(o) => {
            t.objects += 1;
            for (k, x) in o.iter() {
                t.key(k);
                walk_borrowed(x, t);
            }
        }
    }
}

fn walk_jiter(v: &jiter::JsonValue, t: &mut Tally) {
    use jiter::JsonValue as V;
    match v {
        V::Null => t.nulls += 1,
        V::Bool(b) => t.boolean(*b),
        V::Int(i) => t.number(*i as f64),
        V::BigInt(b) => t.number(f64::from(jiter::NumberInt::BigInt(b.clone()))),
        V::Float(f) => t.number(*f),
        V::Str(s) => t.string(s),
        V::Array(a) => {
            t.arrays += 1;
            a.iter().for_each(|x| walk_jiter(x, t));
        }
        V::Object(o) => {
            t.objects += 1;
            for (k, x) in o.iter() {
                t.key(k);
                walk_jiter(x, t);
            }
        }
    }
}

/// Runs a DOM variant (prints the check, returns the measurement), or None if `variant` is not one
pub fn run(variant: &str, docs: &[Vec<u8>], min_samples: usize) -> Option<(f64, usize, bool)> {
    let mut t = Tally::new(true);
    let mut buf: Vec<u8> = Vec::new();
    let r = match variant {
        "serde_json-value" => {
            for d in docs {
                let v: serde_json::Value = serde_json::from_slice(d).unwrap_or_else(|e| fail(e));
                walk_serde(&v, &mut t);
            }
            println!("{}", t.line());
            measure(min_samples, || {
                for d in docs {
                    let v: serde_json::Value = serde_json::from_slice(d).unwrap_or_else(|e| fail(e));
                    black_box(&v);
                }
            })
        }
        "sonic-rs-value" => {
            for d in docs {
                let v: sonic_rs::Value = sonic_rs::from_slice(d).unwrap_or_else(|e| fail(e));
                walk_sonic(&v, &mut t);
            }
            println!("{}", t.line());
            measure(min_samples, || {
                for d in docs {
                    let v: sonic_rs::Value = sonic_rs::from_slice(d).unwrap_or_else(|e| fail(e));
                    black_box(&v);
                }
            })
        }
        "simd-json-owned" => {
            for d in docs {
                let mut b = d.clone();
                let v = simd_json::to_owned_value(&mut b).unwrap_or_else(|e| fail(e));
                walk_owned(&v, &mut t);
            }
            println!("{}", t.line());
            measure(min_samples, || {
                for d in docs {
                    buf.clear();
                    buf.extend_from_slice(d);
                    let v = simd_json::to_owned_value(&mut buf).unwrap_or_else(|e| fail(e));
                    black_box(&v);
                }
            })
        }
        "simd-json-borrowed" => {
            for d in docs {
                let mut b = d.clone();
                let v = simd_json::to_borrowed_value(&mut b).unwrap_or_else(|e| fail(e));
                walk_borrowed(&v, &mut t);
            }
            println!("{}", t.line());
            measure(min_samples, || {
                for d in docs {
                    buf.clear();
                    buf.extend_from_slice(d);
                    let v = simd_json::to_borrowed_value(&mut buf).unwrap_or_else(|e| fail(e));
                    black_box(&v);
                }
            })
        }
        "jiter-value" => {
            for d in docs {
                let v = jiter::JsonValue::parse(d, false).unwrap_or_else(|e| fail(e));
                walk_jiter(&v, &mut t);
            }
            println!("{}", t.line());
            measure(min_samples, || {
                for d in docs {
                    let v = jiter::JsonValue::parse(d, false).unwrap_or_else(|e| fail(e));
                    black_box(&v);
                }
            })
        }
        _ => return None,
    };
    Some(r)
}
