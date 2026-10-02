// Query variants: reference.py's on-demand queries (see main.rs), each reading only the values asked for.
use crate::{bits, fail, measure, Kind};
use jiter::{Jiter, JiterResult};
use serde::de::IgnoredAny;
use serde::Deserialize;
use sonic_rs::JsonValueTrait;
use std::hint::black_box;

/// The query's result: twitter (statuses, followers, hashtags), citm (performances, id sum, -),
/// canada (pairs, longitude numsum, -); printed per reference.py
type Answer = [u64; 3];

fn line(kind: Kind, a: Answer) -> String {
    match kind {
        Kind::Twitter => format!("check: {} {} {}", a[0], a[1], a[2]),
        Kind::Citm => format!("check: {} {}", a[0], a[1]),
        Kind::Canada => format!("check: {} {:016x}", a[0], a[1]),
    }
}

// ---- sonic-rs: lazy values and iterators ----

fn sonic(kind: Kind, doc: &[u8]) -> sonic_rs::Result<Answer> {
    let mut a = [0u64; 3];
    match kind {
        Kind::Twitter => {
            let statuses = sonic_rs::get(doc, &["statuses"])?;
            for s in statuses.into_array_iter().unwrap() {
                let s = s?;
                a[0] += 1;
                a[1] += s.pointer(&["user", "followers_count"]).and_then(|v| v.as_u64()).unwrap();
                for h in s.pointer(&["entities", "hashtags"]).unwrap().into_array_iter().unwrap() {
                    h?;
                    a[2] += 1;
                }
            }
        }
        Kind::Citm => {
            for p in sonic_rs::get(doc, &["performances"])?.into_array_iter().unwrap() {
                let p = p?;
                a[0] += 1;
                a[1] += p.get("id").and_then(|v| v.as_u64()).unwrap();
            }
        }
        Kind::Canada => {
            for f in sonic_rs::get(doc, &["features"])?.into_array_iter().unwrap() {
                let f = f?;
                for ring in f.pointer(&["geometry", "coordinates"]).unwrap().into_array_iter().unwrap() {
                    for pair in ring?.into_array_iter().unwrap() {
                        let pair = pair?;
                        a[0] += 1;
                        a[1] = a[1].wrapping_add(bits(pair.get(0).and_then(|v| v.as_f64()).unwrap()));
                    }
                }
            }
        }
    }
    Ok(a)
}

// ---- jiter: walk the path, skip the rest ----

/// Visits an object's members: `f(jiter, index into names)` for the named ones, next_skip for the rest
fn fields(j: &mut Jiter, names: &[&str], mut f: impl FnMut(&mut Jiter, usize) -> JiterResult<()>) -> JiterResult<()> {
    let mut key = j.next_object()?.map(|k| names.iter().position(|n| *n == k));
    while let Some(found) = key {
        match found {
            Some(i) => f(j, i)?,
            None => j.next_skip()?,
        }
        key = j.next_key()?.map(|k| names.iter().position(|n| *n == k));
    }
    Ok(())
}

/// Visits an array's elements: `f` must consume each one
fn elements(j: &mut Jiter, mut f: impl FnMut(&mut Jiter) -> JiterResult<()>) -> JiterResult<()> {
    let mut next = j.next_array()?;
    while next.is_some() {
        f(j)?;
        next = j.array_step()?;
    }
    Ok(())
}

fn jiter(kind: Kind, doc: &[u8]) -> JiterResult<Answer> {
    let mut a = [0u64; 3];
    let mut j = Jiter::new(doc);
    match kind {
        Kind::Twitter => fields(&mut j, &["statuses"], |j, _| {
            elements(j, |j| {
                a[0] += 1;
                fields(j, &["user", "entities"], |j, i| {
                    if i == 0 {
                        fields(j, &["followers_count"], |j, _| {
                            a[1] += f64::from(j.next_int()?) as u64;
                            Ok(())
                        })
                    } else {
                        fields(j, &["hashtags"], |j, _| {
                            elements(j, |j| {
                                a[2] += 1;
                                j.next_skip()
                            })
                        })
                    }
                })
            })
        })?,
        Kind::Citm => fields(&mut j, &["performances"], |j, _| {
            elements(j, |j| {
                a[0] += 1;
                fields(j, &["id"], |j, _| {
                    a[1] += f64::from(j.next_int()?) as u64;
                    Ok(())
                })
            })
        })?,
        Kind::Canada => fields(&mut j, &["features"], |j, _| {
            elements(j, |j| {
                fields(j, &["geometry"], |j, _| {
                    fields(j, &["coordinates"], |j, _| {
                        elements(j, |j| {
                            elements(j, |j| {
                                // [longitude, latitude]: read the first, skip the second
                                j.next_array()?;
                                let x = f64::from(j.next_number()?);
                                a[0] += 1;
                                a[1] = a[1].wrapping_add(bits(x));
                                while j.array_step()?.is_some() {
                                    j.next_skip()?;
                                }
                                Ok(())
                            })
                        })
                    })
                })
            })
        })?,
    }
    j.finish()?;
    Ok(a)
}

// ---- serde_json: structs with only the queried fields ----

#[derive(Deserialize)]
struct TwitterQ {
    statuses: Vec<StatusQ>,
}
#[derive(Deserialize)]
struct StatusQ {
    user: UserQ,
    entities: EntitiesQ,
}
#[derive(Deserialize)]
struct UserQ {
    followers_count: u64,
}
#[derive(Deserialize)]
struct EntitiesQ {
    hashtags: Vec<IgnoredAny>,
}
#[derive(Deserialize)]
struct CitmQ {
    performances: Vec<PerformanceQ>,
}
#[derive(Deserialize)]
struct PerformanceQ {
    id: u64,
}
#[derive(Deserialize)]
struct CanadaQ {
    features: Vec<FeatureQ>,
}
#[derive(Deserialize)]
struct FeatureQ {
    geometry: GeometryQ,
}
#[derive(Deserialize)]
struct GeometryQ {
    coordinates: Vec<Vec<(f64, IgnoredAny)>>,
}

fn partial(kind: Kind, doc: &[u8]) -> serde_json::Result<Answer> {
    let mut a = [0u64; 3];
    match kind {
        Kind::Twitter => {
            let t: TwitterQ = serde_json::from_slice(doc)?;
            a[0] = t.statuses.len() as u64;
            for s in &t.statuses {
                a[1] += s.user.followers_count;
                a[2] += s.entities.hashtags.len() as u64;
            }
        }
        Kind::Citm => {
            let c: CitmQ = serde_json::from_slice(doc)?;
            a[0] = c.performances.len() as u64;
            a[1] = c.performances.iter().map(|p| p.id).sum();
        }
        Kind::Canada => {
            let c: CanadaQ = serde_json::from_slice(doc)?;
            for f in &c.features {
                for ring in &f.geometry.coordinates {
                    for (x, _) in ring {
                        a[0] += 1;
                        a[1] = a[1].wrapping_add(bits(*x));
                    }
                }
            }
        }
    }
    Ok(a)
}

pub fn run(variant: &str, kind: Kind, doc: &[u8], min_samples: usize) -> (f64, usize, bool) {
    let q = |doc: &[u8]| -> Answer {
        match variant {
            "sonic-rs-get" => sonic(kind, doc).unwrap_or_else(|e| fail(e)),
            "jiter-query" => jiter(kind, doc).unwrap_or_else(|e| fail(format!("{e:?}"))),
            _ => partial(kind, doc).unwrap_or_else(|e| fail(e)),
        }
    };
    println!("{}", line(kind, q(doc)));
    measure(min_samples, || {
        black_box(q(doc));
    })
}
