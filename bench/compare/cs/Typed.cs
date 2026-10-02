// The typed schema (see ../reference.py): serde-rs/json-benchmark's twitter, citm_catalog and canada
// structures with its simplifications (string enums, Color and *_id_str as strings, always-null fields
// as nullable strings, empty arrays as string lists, (u8, u8) indices as int lists, canada coordinates
// as double pairs). Property names are the JSON member names, so neither library needs a naming policy;
// one set of classes serves System.Text.Json (source-generated context below) and Newtonsoft.Json.
#pragma warning disable IDE1006, CS8618 // JSON member names; set by the deserializers
using System.Text;
using System.Text.Json.Serialization;
using Newtonsoft.Json;

static class Typed
{
	static readonly Newtonsoft.Json.JsonSerializer NewtonsoftSerializer =
		Newtonsoft.Json.JsonSerializer.Create(new JsonSerializerSettings { DateParseHandling = DateParseHandling.None });

	public static object FromStj(string kind, byte[] d) => kind switch
	{
		"twitter" => System.Text.Json.JsonSerializer.Deserialize(d, TypedContext.Default.Twitter)!,
		"citm_catalog" => System.Text.Json.JsonSerializer.Deserialize(d, TypedContext.Default.CitmCatalog)!,
		_ => System.Text.Json.JsonSerializer.Deserialize(d, TypedContext.Default.FeatureCollection)!,
	};

	public static object FromNewtonsoft(string kind, byte[] d)
	{
		using var reader = new JsonTextReader(new StreamReader(new MemoryStream(d), Encoding.UTF8));
		return kind switch
		{
			"twitter" => NewtonsoftSerializer.Deserialize<Twitter>(reader)!,
			"citm_catalog" => NewtonsoftSerializer.Deserialize<CitmCatalog>(reader)!,
			_ => NewtonsoftSerializer.Deserialize<FeatureCollection>(reader)!,
		};
	}

	static long Chars(string s)
	{
		long n = 0;
		foreach (char ch in s)
			n += char.IsLowSurrogate(ch) ? 0 : 1;
		return n;
	}

	public static string Check(string kind, object value)
	{
		switch (value)
		{
			case Twitter t:
			{
				ulong ids = 0;
				long followers = 0, retweets = 0, hashtags = 0, text = 0, media = 0, urls = 0;
				foreach (var s in t.statuses)
				{
					ids = unchecked(ids + s.id);
					followers += s.user.followers_count;
					retweets += s.retweeted_status != null ? 1 : 0;
					hashtags += s.entities.hashtags.Count;
					text += Chars(s.text);
					media += s.entities.media?.Count ?? 0;
					urls += s.user.entities.description.urls.Count;
				}
				return $"check: {t.statuses.Count} {ids} {followers} {retweets} {hashtags} {text} {media} {urls}";
			}
			case CitmCatalog c:
			{
				long eventIds = 0, perfIds = 0, amounts = 0, areas = 0, names = 0, subTopics = 0;
				foreach (var e in c.events.Values)
				{
					eventIds += e.id;
					names += Chars(e.name);
				}
				foreach (var p in c.performances)
				{
					perfIds += p.id;
					foreach (var pr in p.prices)
						amounts += pr.amount;
					foreach (var sc in p.seatCategories)
						areas += sc.areas.Count;
				}
				foreach (var l in c.topicSubTopics.Values)
					subTopics += l.Count;
				return $"check: {c.events.Count} {eventIds} {c.performances.Count} {perfIds} {amounts} {areas} {names} {subTopics}";
			}
			case FeatureCollection fc:
			{
				long rings = 0, points = 0, chars = 0;
				ulong sum = 0;
				foreach (var f in fc.features)
				{
					foreach (var ring in f.geometry.coordinates)
					{
						rings++;
						points += ring.Count;
						foreach (var p in ring)
							foreach (var x in p)
								sum = unchecked(sum + global::Check.Bits(x));
					}
					foreach (var v in f.properties.Values)
						chars += Chars(v);
				}
				return $"check: {fc.features.Count} {rings} {points} {sum:x16} {chars}";
			}
		}
		throw new InvalidOperationException();
	}
}

[JsonSerializable(typeof(Twitter))]
[JsonSerializable(typeof(CitmCatalog))]
[JsonSerializable(typeof(FeatureCollection))]
partial class TypedContext : JsonSerializerContext
{
}

// ---- twitter ----

sealed class Twitter
{
	public List<Status> statuses { get; set; }
	public SearchMetadata search_metadata { get; set; }
}

sealed class Status
{
	public Metadata metadata { get; set; }
	public string created_at { get; set; }
	public ulong id { get; set; }
	public string id_str { get; set; }
	public string text { get; set; }
	public string source { get; set; }
	public bool truncated { get; set; }
	public ulong? in_reply_to_status_id { get; set; }
	public string? in_reply_to_status_id_str { get; set; }
	public uint? in_reply_to_user_id { get; set; }
	public string? in_reply_to_user_id_str { get; set; }
	public string? in_reply_to_screen_name { get; set; }
	public User user { get; set; }
	public string? geo { get; set; }
	public string? coordinates { get; set; }
	public string? place { get; set; }
	public string? contributors { get; set; }
	public Status? retweeted_status { get; set; }
	public uint retweet_count { get; set; }
	public uint favorite_count { get; set; }
	public StatusEntities entities { get; set; }
	public bool favorited { get; set; }
	public bool retweeted { get; set; }
	public bool? possibly_sensitive { get; set; }
	public string lang { get; set; }
}

sealed class Metadata
{
	public string result_type { get; set; }
	public string iso_language_code { get; set; }
}

sealed class User
{
	public uint id { get; set; }
	public string id_str { get; set; }
	public string name { get; set; }
	public string screen_name { get; set; }
	public string location { get; set; }
	public string description { get; set; }
	public string? url { get; set; }
	public UserEntities entities { get; set; }
	public bool @protected { get; set; }
	public uint followers_count { get; set; }
	public uint friends_count { get; set; }
	public uint listed_count { get; set; }
	public string created_at { get; set; }
	public uint favourites_count { get; set; }
	public int? utc_offset { get; set; }
	public string? time_zone { get; set; }
	public bool geo_enabled { get; set; }
	public bool verified { get; set; }
	public uint statuses_count { get; set; }
	public string lang { get; set; }
	public bool contributors_enabled { get; set; }
	public bool is_translator { get; set; }
	public bool is_translation_enabled { get; set; }
	public string profile_background_color { get; set; }
	public string profile_background_image_url { get; set; }
	public string profile_background_image_url_https { get; set; }
	public bool profile_background_tile { get; set; }
	public string profile_image_url { get; set; }
	public string profile_image_url_https { get; set; }
	public string? profile_banner_url { get; set; }
	public string profile_link_color { get; set; }
	public string profile_sidebar_border_color { get; set; }
	public string profile_sidebar_fill_color { get; set; }
	public string profile_text_color { get; set; }
	public bool profile_use_background_image { get; set; }
	public bool default_profile { get; set; }
	public bool default_profile_image { get; set; }
	public bool following { get; set; }
	public bool follow_request_sent { get; set; }
	public bool notifications { get; set; }
}

sealed class UserEntities
{
	public UserUrl? url { get; set; }
	public UserEntitiesDescription description { get; set; }
}

sealed class UserUrl
{
	public List<Url> urls { get; set; }
}

sealed class Url
{
	public string url { get; set; }
	public string expanded_url { get; set; }
	public string display_url { get; set; }
	public List<int> indices { get; set; }
}

sealed class UserEntitiesDescription
{
	public List<Url> urls { get; set; }
}

sealed class StatusEntities
{
	public List<Hashtag> hashtags { get; set; }
	public List<string> symbols { get; set; }
	public List<Url> urls { get; set; }
	public List<UserMention> user_mentions { get; set; }
	public List<Media>? media { get; set; }
}

sealed class Hashtag
{
	public string text { get; set; }
	public List<int> indices { get; set; }
}

sealed class UserMention
{
	public string screen_name { get; set; }
	public string name { get; set; }
	public uint id { get; set; }
	public string id_str { get; set; }
	public List<int> indices { get; set; }
}

sealed class Media
{
	public ulong id { get; set; }
	public string id_str { get; set; }
	public List<int> indices { get; set; }
	public string media_url { get; set; }
	public string media_url_https { get; set; }
	public string url { get; set; }
	public string display_url { get; set; }
	public string expanded_url { get; set; }
	public string type { get; set; }
	public Sizes sizes { get; set; }
	public ulong? source_status_id { get; set; }
	public string? source_status_id_str { get; set; }
}

sealed class Sizes
{
	public Size medium { get; set; }
	public Size small { get; set; }
	public Size thumb { get; set; }
	public Size large { get; set; }
}

sealed class Size
{
	public int w { get; set; }
	public int h { get; set; }
	public string resize { get; set; }
}

sealed class SearchMetadata
{
	public double completed_in { get; set; }
	public ulong max_id { get; set; }
	public string max_id_str { get; set; }
	public string next_results { get; set; }
	public string query { get; set; }
	public string refresh_url { get; set; }
	public int count { get; set; }
	public ulong since_id { get; set; }
	public string since_id_str { get; set; }
}

// ---- citm_catalog ----

sealed class CitmCatalog
{
	public Dictionary<string, string> areaNames { get; set; }
	public Dictionary<string, string> audienceSubCategoryNames { get; set; }
	public Dictionary<string, string> blockNames { get; set; }
	public Dictionary<string, Event> events { get; set; }
	public List<Performance> performances { get; set; }
	public Dictionary<string, string> seatCategoryNames { get; set; }
	public Dictionary<string, string> subTopicNames { get; set; }
	public Dictionary<string, string> subjectNames { get; set; }
	public Dictionary<string, string> topicNames { get; set; }
	public Dictionary<string, List<long>> topicSubTopics { get; set; }
	public Dictionary<string, string> venueNames { get; set; }
}

sealed class Event
{
	public string? description { get; set; }
	public long id { get; set; }
	public string? logo { get; set; }
	public string name { get; set; }
	public List<long> subTopicIds { get; set; }
	public string? subjectCode { get; set; }
	public string? subtitle { get; set; }
	public List<long> topicIds { get; set; }
}

sealed class Performance
{
	public long eventId { get; set; }
	public long id { get; set; }
	public string? logo { get; set; }
	public string? name { get; set; }
	public List<Price> prices { get; set; }
	public List<SeatCategory> seatCategories { get; set; }
	public string? seatMapImage { get; set; }
	public ulong start { get; set; }
	public string venueCode { get; set; }
}

sealed class Price
{
	public long amount { get; set; }
	public long audienceSubCategoryId { get; set; }
	public long seatCategoryId { get; set; }
}

sealed class SeatCategory
{
	public List<Area> areas { get; set; }
	public long seatCategoryId { get; set; }
}

sealed class Area
{
	public long areaId { get; set; }
	public List<string> blockIds { get; set; }
}

// ---- canada ----

sealed class FeatureCollection
{
	public string type { get; set; }
	public List<Feature> features { get; set; }
}

sealed class Feature
{
	public string type { get; set; }
	public Dictionary<string, string> properties { get; set; }
	public Geometry geometry { get; set; }
}

sealed class Geometry
{
	public string type { get; set; }
	public List<List<double[]>> coordinates { get; set; }
}
