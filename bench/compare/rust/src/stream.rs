// Streaming variants: one pass over every value without building any (see main.rs).
use crate::{fail, measure, Tally};
use serde::de::{DeserializeSeed, Deserializer, MapAccess, SeqAccess, Visitor};
use std::fmt;
use std::hint::black_box;

/// Walks any value, adding it to the tally
struct Walk<'a>(&'a mut Tally);
/// Reads an object key, adding it to the tally
struct Key<'a>(&'a mut Tally);

impl<'de> DeserializeSeed<'de> for Walk<'_> {
    type Value = ();
    fn deserialize<D: Deserializer<'de>>(self, d: D) -> Result<(), D::Error> {
        d.deserialize_any(self)
    }
}

impl<'de> Visitor<'de> for Walk<'_> {
    type Value = ();
    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("any JSON value")
    }
    fn visit_unit<E>(self) -> Result<(), E> {
        self.0.nulls += 1;
        Ok(())
    }
    fn visit_bool<E>(self, b: bool) -> Result<(), E> {
        self.0.boolean(b);
        Ok(())
    }
    fn visit_u64<E>(self, v: u64) -> Result<(), E> {
        self.0.number(v as f64);
        Ok(())
    }
    fn visit_i64<E>(self, v: i64) -> Result<(), E> {
        self.0.number(v as f64);
        Ok(())
    }
    fn visit_f64<E>(self, v: f64) -> Result<(), E> {
        self.0.number(v);
        Ok(())
    }
    fn visit_str<E>(self, s: &str) -> Result<(), E> {
        self.0.string(s);
        Ok(())
    }
    fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<(), A::Error> {
        self.0.arrays += 1;
        while seq.next_element_seed(Walk(&mut *self.0))?.is_some() {}
        Ok(())
    }
    fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<(), A::Error> {
        self.0.objects += 1;
        while map.next_key_seed(Key(&mut *self.0))?.is_some() {
            map.next_value_seed(Walk(&mut *self.0))?;
        }
        Ok(())
    }
}

impl<'de> DeserializeSeed<'de> for Key<'_> {
    type Value = ();
    fn deserialize<D: Deserializer<'de>>(self, d: D) -> Result<(), D::Error> {
        d.deserialize_str(self)
    }
}

impl<'de> Visitor<'de> for Key<'_> {
    type Value = ();
    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("an object key")
    }
    fn visit_str<E>(self, s: &str) -> Result<(), E> {
        self.0.key(s);
        Ok(())
    }
}

fn serde_pass(d: &[u8], t: &mut Tally) {
    let mut de = serde_json::Deserializer::from_slice(d);
    Walk(t).deserialize(&mut de).unwrap_or_else(|e| fail(e));
    de.end().unwrap_or_else(|e| fail(e));
}

fn jiter_value(j: &mut jiter::Jiter, peek: jiter::Peek, t: &mut Tally) -> jiter::JiterResult<()> {
    use jiter::Peek;
    match peek {
        Peek::Null => {
            j.known_null()?;
            t.nulls += 1;
        }
        Peek::True | Peek::False => {
            let b = j.known_bool(peek)?;
            t.boolean(b);
        }
        Peek::String => {
            let s = j.known_str()?;
            t.string(s);
        }
        Peek::Array => {
            t.arrays += 1;
            let mut next = j.known_array()?;
            while let Some(p) = next {
                jiter_value(j, p, t)?;
                next = j.array_step()?;
            }
        }
        Peek::Object => {
            t.objects += 1;
            let mut key = j.known_object()?;
            while let Some(k) = key {
                t.key(k);
                let p = j.peek()?;
                jiter_value(j, p, t)?;
                key = j.next_key()?;
            }
        }
        _ => {
            let n = j.known_number(peek)?;
            t.number(f64::from(n));
        }
    }
    Ok(())
}

fn jiter_pass(d: &[u8], t: &mut Tally) {
    let mut j = jiter::Jiter::new(d);
    let r = j.peek().and_then(|p| jiter_value(&mut j, p, t)).and_then(|_| j.finish());
    if let Err(e) = r {
        fail(format!("{e:?}"));
    }
}

/// Runs a streaming variant (prints the check, returns the measurement), or None if `variant` is not one
pub fn run(variant: &str, docs: &[Vec<u8>], min_samples: usize) -> Option<(f64, usize, bool)> {
    let pass: fn(&[u8], &mut Tally) = match variant {
        "serde_json-visitor" => serde_pass,
        "jiter-iter" => jiter_pass,
        _ => return None,
    };
    let mut t = Tally::new(true);
    for d in docs {
        pass(d, &mut t);
    }
    println!("{}", t.line());
    Some(measure(min_samples, || {
        let mut t = Tally::new(false);
        for d in docs {
            pass(d, &mut t);
        }
        black_box(&t);
    }))
}
