// The typed track's structures for std.json: serde-rs/json-benchmark's twitter, citm_catalog and
// canada schemas with the simplifications ../reference.py lists (enums, colors and *_id_str ids as
// strings; always-null fields as nullable strings; empty arrays as string lists; indices as integer
// lists; canada's coordinates as [2]f64). Optional fields that can be absent default to null.
const std = @import("std");
const common = @import("common.zig");

const Str = []const u8;
const Map = std.json.ArrayHashMap;

// ---- twitter ----

const Metadata = struct { result_type: Str, iso_language_code: Str };

const Url = struct { url: Str, expanded_url: Str, display_url: Str, indices: []u32 };

const UserUrl = struct { urls: []Url };

const UserEntitiesDescription = struct { urls: []Url };

const UserEntities = struct { url: ?UserUrl = null, description: UserEntitiesDescription };

const User = struct {
    id: u32,
    id_str: Str,
    name: Str,
    screen_name: Str,
    location: Str,
    description: Str,
    url: ?Str = null,
    entities: UserEntities,
    protected: bool,
    followers_count: u32,
    friends_count: u32,
    listed_count: u32,
    created_at: Str,
    favourites_count: u32,
    utc_offset: ?i32 = null,
    time_zone: ?Str = null,
    geo_enabled: bool,
    verified: bool,
    statuses_count: u32,
    lang: Str,
    contributors_enabled: bool,
    is_translator: bool,
    is_translation_enabled: bool,
    profile_background_color: Str,
    profile_background_image_url: Str,
    profile_background_image_url_https: Str,
    profile_background_tile: bool,
    profile_image_url: Str,
    profile_image_url_https: Str,
    profile_banner_url: ?Str = null,
    profile_link_color: Str,
    profile_sidebar_border_color: Str,
    profile_sidebar_fill_color: Str,
    profile_text_color: Str,
    profile_use_background_image: bool,
    default_profile: bool,
    default_profile_image: bool,
    following: bool,
    follow_request_sent: bool,
    notifications: bool,
};

const Hashtag = struct { text: Str, indices: []u32 };

const UserMention = struct { screen_name: Str, name: Str, id: u32, id_str: Str, indices: []u32 };

const Size = struct { w: u32, h: u32, resize: Str };

const Sizes = struct { medium: Size, small: Size, thumb: Size, large: Size };

const Media = struct {
    id: u64,
    id_str: Str,
    indices: []u32,
    media_url: Str,
    media_url_https: Str,
    url: Str,
    display_url: Str,
    expanded_url: Str,
    type: Str,
    sizes: Sizes,
    source_status_id: ?u64 = null,
    source_status_id_str: ?Str = null,
};

const StatusEntities = struct {
    hashtags: []Hashtag,
    symbols: []Str,
    urls: []Url,
    user_mentions: []UserMention,
    media: ?[]Media = null,
};

const Status = struct {
    metadata: Metadata,
    created_at: Str,
    id: u64,
    id_str: Str,
    text: Str,
    source: Str,
    truncated: bool,
    in_reply_to_status_id: ?u64 = null,
    in_reply_to_status_id_str: ?Str = null,
    in_reply_to_user_id: ?u32 = null,
    in_reply_to_user_id_str: ?Str = null,
    in_reply_to_screen_name: ?Str = null,
    user: User,
    geo: ?Str = null,
    coordinates: ?Str = null,
    place: ?Str = null,
    contributors: ?Str = null,
    retweeted_status: ?*Status = null,
    retweet_count: u32,
    favorite_count: u32,
    entities: StatusEntities,
    favorited: bool,
    retweeted: bool,
    possibly_sensitive: ?bool = null,
    lang: Str,
};

const SearchMetadata = struct {
    completed_in: f64,
    max_id: u64,
    max_id_str: Str,
    next_results: Str,
    query: Str,
    refresh_url: Str,
    count: u32,
    since_id: u64,
    since_id_str: Str,
};

const Twitter = struct { statuses: []Status, search_metadata: SearchMetadata };

// ---- citm_catalog ----

const Event = struct {
    description: ?Str = null,
    id: u32,
    logo: ?Str = null,
    name: Str,
    subTopicIds: []u32,
    subjectCode: ?Str = null,
    subtitle: ?Str = null,
    topicIds: []u32,
};

const Price = struct { amount: u32, audienceSubCategoryId: u32, seatCategoryId: u32 };

const Area = struct { areaId: u32, blockIds: []Str };

const SeatCategory = struct { areas: []Area, seatCategoryId: u32 };

const Performance = struct {
    eventId: u32,
    id: u32,
    logo: ?Str = null,
    name: ?Str = null,
    prices: []Price,
    seatCategories: []SeatCategory,
    seatMapImage: ?Str = null,
    start: u64,
    venueCode: Str,
};

const CitmCatalog = struct {
    areaNames: Map(Str),
    audienceSubCategoryNames: Map(Str),
    blockNames: Map(Str),
    events: Map(Event),
    performances: []Performance,
    seatCategoryNames: Map(Str),
    subTopicNames: Map(Str),
    subjectNames: Map(Str),
    topicNames: Map(Str),
    topicSubTopics: Map([]u32),
    venueNames: Map(Str),
};

// ---- canada ----

const Geometry = struct { type: Str, coordinates: [][][2]f64 };

const Feature = struct { type: Str, properties: Map(Str), geometry: Geometry };

const Canada = struct { type: Str, features: []Feature };

// ---- running ----

pub const Kind = enum { twitter, citm_catalog, canada };

pub fn kindOf(path: []const u8) ?Kind {
    const base = std.fs.path.basename(path);
    if (std.mem.eql(u8, base, "twitter.json")) return .twitter;
    if (std.mem.eql(u8, base, "citm_catalog.json")) return .citm_catalog;
    if (std.mem.eql(u8, base, "canada.json")) return .canada;
    return null;
}

pub fn parseAndFree(gpa: std.mem.Allocator, kind: Kind, doc: []const u8) !void {
    switch (kind) {
        .twitter => (try std.json.parseFromSlice(Twitter, gpa, doc, .{})).deinit(),
        .citm_catalog => (try std.json.parseFromSlice(CitmCatalog, gpa, doc, .{})).deinit(),
        .canada => (try std.json.parseFromSlice(Canada, gpa, doc, .{})).deinit(),
    }
}

pub fn printCheck(io: std.Io, gpa: std.mem.Allocator, kind: Kind, doc: []const u8) !void {
    switch (kind) {
        .twitter => {
            const p = try std.json.parseFromSlice(Twitter, gpa, doc, .{});
            defer p.deinit();
            var ids: u64 = 0;
            var followers: u64 = 0;
            var retweets: u64 = 0;
            var hashtags: u64 = 0;
            var chars: u64 = 0;
            var media: u64 = 0;
            var urls: u64 = 0;
            for (p.value.statuses) |s| {
                ids +%= s.id;
                followers += s.user.followers_count;
                retweets += @intFromBool(s.retweeted_status != null);
                hashtags += s.entities.hashtags.len;
                chars += common.codePoints(s.text);
                if (s.entities.media) |m| media += m.len;
                urls += s.user.entities.description.urls.len;
            }
            common.out(io, "check: {d} {d} {d} {d} {d} {d} {d} {d}\n", .{ p.value.statuses.len, ids, followers, retweets, hashtags, chars, media, urls });
        },
        .citm_catalog => {
            const p = try std.json.parseFromSlice(CitmCatalog, gpa, doc, .{});
            defer p.deinit();
            const c = p.value;
            var event_ids: u64 = 0;
            var names: u64 = 0;
            for (c.events.map.values()) |e| {
                event_ids += e.id;
                names += common.codePoints(e.name);
            }
            var perf_ids: u64 = 0;
            var amounts: u64 = 0;
            var areas: u64 = 0;
            for (c.performances) |perf| {
                perf_ids += perf.id;
                for (perf.prices) |pr| amounts += pr.amount;
                for (perf.seatCategories) |sc| areas += sc.areas.len;
            }
            var sub_topics: u64 = 0;
            for (c.topicSubTopics.map.values()) |v| sub_topics += v.len;
            common.out(io, "check: {d} {d} {d} {d} {d} {d} {d} {d}\n", .{ c.events.map.count(), event_ids, c.performances.len, perf_ids, amounts, areas, names, sub_topics });
        },
        .canada => {
            const p = try std.json.parseFromSlice(Canada, gpa, doc, .{});
            defer p.deinit();
            var rings: u64 = 0;
            var points: u64 = 0;
            var sum: u64 = 0;
            var chars: u64 = 0;
            for (p.value.features) |f| {
                rings += f.geometry.coordinates.len;
                for (f.geometry.coordinates) |ring| {
                    points += ring.len;
                    for (ring) |pt| sum +%= common.bits(pt[0]) +% common.bits(pt[1]);
                }
                for (f.properties.map.values()) |v| chars += common.codePoints(v);
            }
            common.out(io, "check: {d} {d} {d} {x:0>16} {d}\n", .{ p.value.features.len, rings, points, sum, chars });
        },
    }
}
