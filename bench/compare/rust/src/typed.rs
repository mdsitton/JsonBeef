// The typed benchmark's schema: serde-rs/json-benchmark's structs (src/copy/twitter.rs,
// citm_catalog.rs, canada.rs) with ../reference.py's simplifications (string enums, Color and id_str
// as String, always-null fields as Option<String>, empty arrays as Vec<String>, indices as Vec<u64>,
// canada's coordinates as f64 pairs). serde derives, shared by serde_json, sonic-rs and simd-json.
// Every field is decoded; the checks read only some of them.
#![allow(dead_code)]
use crate::{bits, fail, measure, Kind};
use serde::Deserialize;
use std::collections::BTreeMap as Map;
use std::hint::black_box;

// ---- twitter ----

#[derive(Deserialize)]
pub struct Twitter {
    pub statuses: Vec<Status>,
    pub search_metadata: SearchMetadata,
}

#[derive(Deserialize)]
pub struct Status {
    pub metadata: Metadata,
    pub created_at: String,
    pub id: u64,
    pub id_str: String,
    pub text: String,
    pub source: String,
    pub truncated: bool,
    pub in_reply_to_status_id: Option<u64>,
    pub in_reply_to_status_id_str: Option<String>,
    pub in_reply_to_user_id: Option<u64>,
    pub in_reply_to_user_id_str: Option<String>,
    pub in_reply_to_screen_name: Option<String>,
    pub user: User,
    pub geo: Option<String>,
    pub coordinates: Option<String>,
    pub place: Option<String>,
    pub contributors: Option<String>,
    pub retweeted_status: Option<Box<Status>>,
    pub retweet_count: u64,
    pub favorite_count: u64,
    pub entities: StatusEntities,
    pub favorited: bool,
    pub retweeted: bool,
    pub possibly_sensitive: Option<bool>,
    pub lang: String,
}

#[derive(Deserialize)]
pub struct Metadata {
    pub result_type: String,
    pub iso_language_code: String,
}

#[derive(Deserialize)]
pub struct User {
    pub id: u64,
    pub id_str: String,
    pub name: String,
    pub screen_name: String,
    pub location: String,
    pub description: String,
    pub url: Option<String>,
    pub entities: UserEntities,
    pub protected: bool,
    pub followers_count: u64,
    pub friends_count: u64,
    pub listed_count: u64,
    pub created_at: String,
    pub favourites_count: u64,
    pub utc_offset: Option<i64>,
    pub time_zone: Option<String>,
    pub geo_enabled: bool,
    pub verified: bool,
    pub statuses_count: u64,
    pub lang: String,
    pub contributors_enabled: bool,
    pub is_translator: bool,
    pub is_translation_enabled: bool,
    pub profile_background_color: String,
    pub profile_background_image_url: String,
    pub profile_background_image_url_https: String,
    pub profile_background_tile: bool,
    pub profile_image_url: String,
    pub profile_image_url_https: String,
    pub profile_banner_url: Option<String>,
    pub profile_link_color: String,
    pub profile_sidebar_border_color: String,
    pub profile_sidebar_fill_color: String,
    pub profile_text_color: String,
    pub profile_use_background_image: bool,
    pub default_profile: bool,
    pub default_profile_image: bool,
    pub following: bool,
    pub follow_request_sent: bool,
    pub notifications: bool,
}

#[derive(Deserialize)]
pub struct UserEntities {
    pub url: Option<UserUrl>,
    pub description: UserEntitiesDescription,
}

#[derive(Deserialize)]
pub struct UserUrl {
    pub urls: Vec<Url>,
}

#[derive(Deserialize)]
pub struct Url {
    pub url: String,
    pub expanded_url: String,
    pub display_url: String,
    pub indices: Vec<u64>,
}

#[derive(Deserialize)]
pub struct UserEntitiesDescription {
    pub urls: Vec<Url>,
}

#[derive(Deserialize)]
pub struct StatusEntities {
    pub hashtags: Vec<Hashtag>,
    pub symbols: Vec<String>,
    pub urls: Vec<Url>,
    pub user_mentions: Vec<UserMention>,
    pub media: Option<Vec<Media>>,
}

#[derive(Deserialize)]
pub struct Hashtag {
    pub text: String,
    pub indices: Vec<u64>,
}

#[derive(Deserialize)]
pub struct UserMention {
    pub screen_name: String,
    pub name: String,
    pub id: u64,
    pub id_str: String,
    pub indices: Vec<u64>,
}

#[derive(Deserialize)]
pub struct Media {
    pub id: u64,
    pub id_str: String,
    pub indices: Vec<u64>,
    pub media_url: String,
    pub media_url_https: String,
    pub url: String,
    pub display_url: String,
    pub expanded_url: String,
    #[serde(rename = "type")]
    pub media_type: String,
    pub sizes: Sizes,
    pub source_status_id: Option<u64>,
    pub source_status_id_str: Option<String>,
}

#[derive(Deserialize)]
pub struct Sizes {
    pub medium: Size,
    pub small: Size,
    pub thumb: Size,
    pub large: Size,
}

#[derive(Deserialize)]
pub struct Size {
    pub w: u64,
    pub h: u64,
    pub resize: String,
}

#[derive(Deserialize)]
pub struct SearchMetadata {
    pub completed_in: f64,
    pub max_id: u64,
    pub max_id_str: String,
    pub next_results: String,
    pub query: String,
    pub refresh_url: String,
    pub count: u64,
    pub since_id: u64,
    pub since_id_str: String,
}

// ---- citm_catalog ----

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CitmCatalog {
    pub area_names: Map<String, String>,
    pub audience_sub_category_names: Map<String, String>,
    pub block_names: Map<String, String>,
    pub events: Map<String, Event>,
    pub performances: Vec<Performance>,
    pub seat_category_names: Map<String, String>,
    pub sub_topic_names: Map<String, String>,
    pub subject_names: Map<String, String>,
    pub topic_names: Map<String, String>,
    pub topic_sub_topics: Map<String, Vec<u64>>,
    pub venue_names: Map<String, String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Event {
    pub description: Option<String>,
    pub id: u64,
    pub logo: Option<String>,
    pub name: String,
    pub sub_topic_ids: Vec<u64>,
    pub subject_code: Option<String>,
    pub subtitle: Option<String>,
    pub topic_ids: Vec<u64>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Performance {
    pub event_id: u64,
    pub id: u64,
    pub logo: Option<String>,
    pub name: Option<String>,
    pub prices: Vec<Price>,
    pub seat_categories: Vec<SeatCategory>,
    pub seat_map_image: Option<String>,
    pub start: u64,
    pub venue_code: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Price {
    pub amount: u64,
    pub audience_sub_category_id: u64,
    pub seat_category_id: u64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SeatCategory {
    pub areas: Vec<Area>,
    pub seat_category_id: u64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Area {
    pub area_id: u64,
    pub block_ids: Vec<String>,
}

// ---- canada ----

#[derive(Deserialize)]
pub struct FeatureCollection {
    #[serde(rename = "type")]
    pub obj_type: String,
    pub features: Vec<Feature>,
}

#[derive(Deserialize)]
pub struct Feature {
    #[serde(rename = "type")]
    pub obj_type: String,
    pub properties: Map<String, String>,
    pub geometry: Geometry,
}

#[derive(Deserialize)]
pub struct Geometry {
    #[serde(rename = "type")]
    pub obj_type: String,
    pub coordinates: Vec<Vec<[f64; 2]>>,
}

// ---- checks (see ../reference.py) ----

fn cp(s: &str) -> u64 {
    s.chars().count() as u64
}

fn check_twitter(t: &Twitter) -> String {
    let st = &t.statuses;
    format!(
        "check: {} {} {} {} {} {} {} {}",
        st.len(),
        st.iter().fold(0u64, |a, s| a.wrapping_add(s.id)),
        st.iter().map(|s| s.user.followers_count).sum::<u64>(),
        st.iter().filter(|s| s.retweeted_status.is_some()).count(),
        st.iter().map(|s| s.entities.hashtags.len()).sum::<usize>(),
        st.iter().map(|s| cp(&s.text)).sum::<u64>(),
        st.iter().map(|s| s.entities.media.as_ref().map_or(0, |m| m.len())).sum::<usize>(),
        st.iter().map(|s| s.user.entities.description.urls.len()).sum::<usize>(),
    )
}

fn check_citm(c: &CitmCatalog) -> String {
    let perf = &c.performances;
    format!(
        "check: {} {} {} {} {} {} {} {}",
        c.events.len(),
        c.events.values().fold(0u64, |a, e| a.wrapping_add(e.id)),
        perf.len(),
        perf.iter().fold(0u64, |a, p| a.wrapping_add(p.id)),
        perf.iter().flat_map(|p| &p.prices).map(|p| p.amount).sum::<u64>(),
        perf.iter().flat_map(|p| &p.seat_categories).map(|s| s.areas.len()).sum::<usize>(),
        c.events.values().map(|e| cp(&e.name)).sum::<u64>(),
        c.topic_sub_topics.values().map(|v| v.len()).sum::<usize>(),
    )
}

fn check_canada(c: &FeatureCollection) -> String {
    let rings: Vec<&Vec<[f64; 2]>> = c.features.iter().flat_map(|f| &f.geometry.coordinates).collect();
    let sum = rings.iter().flat_map(|r| r.iter()).flat_map(|p| p.iter()).fold(0u64, |a, &x| a.wrapping_add(bits(x)));
    format!(
        "check: {} {} {} {:016x} {}",
        c.features.len(),
        rings.len(),
        rings.iter().map(|r| r.len()).sum::<usize>(),
        sum,
        c.features.iter().flat_map(|f| f.properties.values()).map(|v| cp(v)).sum::<u64>(),
    )
}

/// One typed variant on one input type: check once, then time decoding
fn bench<T: for<'de> Deserialize<'de>>(variant: &str, doc: &[u8], min_samples: usize, check: fn(&T) -> String) -> (f64, usize, bool) {
    let mut buf: Vec<u8> = Vec::new();
    let mut decode = |doc: &[u8]| -> T {
        match variant {
            "serde_json-typed" => serde_json::from_slice(doc).unwrap_or_else(|e| fail(e)),
            "sonic-rs-typed" => sonic_rs::from_slice(doc).unwrap_or_else(|e| fail(e)),
            _ => {
                buf.clear();
                buf.extend_from_slice(doc);
                simd_json::serde::from_slice(&mut buf).unwrap_or_else(|e| fail(e))
            }
        }
    };
    let v = decode(doc);
    println!("{}", check(&v));
    drop(v);
    measure(min_samples, || {
        black_box(decode(doc));
    })
}

pub fn run(variant: &str, kind: Kind, doc: &[u8], min_samples: usize) -> (f64, usize, bool) {
    if !matches!(variant, "serde_json-typed" | "sonic-rs-typed" | "simd-json-typed") {
        eprintln!("unknown variant {variant}");
        std::process::exit(2);
    }
    match kind {
        Kind::Twitter => bench::<Twitter>(variant, doc, min_samples, check_twitter),
        Kind::Citm => bench::<CitmCatalog>(variant, doc, min_samples, check_citm),
        Kind::Canada => bench::<FeatureCollection>(variant, doc, min_samples, check_canada),
    }
}
