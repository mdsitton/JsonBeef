using System;
using System.Collections;
using System.IO;
using BJSON;
using BJSON.Attributes;
using BJSON.Models;

namespace JsonBeefBench;

/// The typed track's classes for BJSON's [JsonObject]: serde-rs/json-benchmark's twitter and
/// citm_catalog schemas with the simplifications ../../reference.py lists (enums, colors and
/// *_id_str ids as strings; always-null fields as nullable strings; empty arrays as string lists;
/// indices as integer lists). Integers are int (64-bit), the 64-bit ids too: BJSON's generated
/// serializer writes every integer field through WriteInt(int64), so a uint64 field does not compile
/// (the ids are below 2^63). BJSON reads a
/// missing or null class field by leaving it as it is, so optional objects are allocated up front;
/// strings are allocated by BJSON when present.
///
/// Two shapes need one of BJSON's converters ([JsonConverter], its documented extension point):
/// the recursive retweeted_status (a field of a [JsonObject] class must be allocated before reading,
/// which a Status inside a Status cannot be) and citm's topicSubTopics, a Dictionary of Lists (BJSON
/// rejects a List as a Dictionary value). canada's coordinates, Lists of Lists of pairs, are not
/// expressible (no List of Lists), so canada is n/a for BJSON.

// ---- twitter ----

[JsonObject]
class Metadata
{
	public String result_type ~ delete _;
	public String iso_language_code ~ delete _;
}

[JsonObject]
class Url
{
	public String url ~ delete _;
	public String expanded_url ~ delete _;
	public String display_url ~ delete _;
	public List<int> indices = new .() ~ delete _;
}

[JsonObject]
class UserUrl
{
	public List<Url> urls = new .() ~ DeleteContainerAndItems!(_);
}

[JsonObject]
class UserEntitiesDescription
{
	public List<Url> urls = new .() ~ DeleteContainerAndItems!(_);
}

[JsonObject]
class UserEntities
{
	public UserUrl url = new .() ~ delete _;
	public UserEntitiesDescription description = new .() ~ delete _;
}

[JsonObject]
class User
{
	public int id;
	public String id_str ~ delete _;
	public String name ~ delete _;
	public String screen_name ~ delete _;
	public String location ~ delete _;
	public String description ~ delete _;
	public String url ~ delete _;
	public UserEntities entities = new .() ~ delete _;
	[JsonPropertyName("protected")]
	public bool is_protected;
	public int followers_count;
	public int friends_count;
	public int listed_count;
	public String created_at ~ delete _;
	public int favourites_count;
	public int? utc_offset;
	public String time_zone ~ delete _;
	public bool geo_enabled;
	public bool verified;
	public int statuses_count;
	public String lang ~ delete _;
	public bool contributors_enabled;
	public bool is_translator;
	public bool is_translation_enabled;
	public String profile_background_color ~ delete _;
	public String profile_background_image_url ~ delete _;
	public String profile_background_image_url_https ~ delete _;
	public bool profile_background_tile;
	public String profile_image_url ~ delete _;
	public String profile_image_url_https ~ delete _;
	public String profile_banner_url ~ delete _;
	public String profile_link_color ~ delete _;
	public String profile_sidebar_border_color ~ delete _;
	public String profile_sidebar_fill_color ~ delete _;
	public String profile_text_color ~ delete _;
	public bool profile_use_background_image;
	public bool default_profile;
	public bool default_profile_image;
	public bool following;
	public bool follow_request_sent;
	public bool notifications;
}

[JsonObject]
class Hashtag
{
	public String text ~ delete _;
	public List<int> indices = new .() ~ delete _;
}

[JsonObject]
class UserMention
{
	public String screen_name ~ delete _;
	public String name ~ delete _;
	public int id;
	public String id_str ~ delete _;
	public List<int> indices = new .() ~ delete _;
}

[JsonObject]
class Size
{
	public int w;
	public int h;
	public String resize ~ delete _;
}

[JsonObject]
class Sizes
{
	public Size medium = new .() ~ delete _;
	public Size small = new .() ~ delete _;
	public Size thumb = new .() ~ delete _;
	public Size large = new .() ~ delete _;
}

[JsonObject]
class Media
{
	public int id;
	public String id_str ~ delete _;
	public List<int> indices = new .() ~ delete _;
	public String media_url ~ delete _;
	public String media_url_https ~ delete _;
	public String url ~ delete _;
	public String display_url ~ delete _;
	public String expanded_url ~ delete _;
	[JsonPropertyName("type")]
	public String media_type ~ delete _;
	public Sizes sizes = new .() ~ delete _;
	public int? source_status_id;
	public String source_status_id_str ~ delete _;
}

[JsonObject]
class StatusEntities
{
	public List<Hashtag> hashtags = new .() ~ DeleteContainerAndItems!(_);
	public List<String> symbols = new .() ~ DeleteContainerAndItems!(_);
	public List<Url> urls = new .() ~ DeleteContainerAndItems!(_);
	public List<UserMention> user_mentions = new .() ~ DeleteContainerAndItems!(_);
	/// Absent on most statuses: stays empty then
	public List<Media> media = new .() ~ DeleteContainerAndItems!(_);
}

/// Reads a nested Status (retweeted_status) into a new object
class StatusConverter : IJsonConverter<Status>
{
	public Result<void> WriteJson(Stream stream, Status value) => .Err;

	public Result<Status> ReadJson(JsonValue value)
	{
		let status = new Status();
		if (status.JsonDeserialize(value) case .Err)
		{
			delete status;
			return .Err;
		}
		return status;
	}
}

[JsonObject]
class Status
{
	public Metadata metadata = new .() ~ delete _;
	public String created_at ~ delete _;
	public int id;
	public String id_str ~ delete _;
	public String text ~ delete _;
	public String source ~ delete _;
	public bool truncated;
	public int? in_reply_to_status_id;
	public String in_reply_to_status_id_str ~ delete _;
	public int? in_reply_to_user_id;
	public String in_reply_to_user_id_str ~ delete _;
	public String in_reply_to_screen_name ~ delete _;
	public User user = new .() ~ delete _;
	public String geo ~ delete _;
	public String coordinates ~ delete _;
	public String place ~ delete _;
	public String contributors ~ delete _;
	[JsonConverter(typeof(StatusConverter))]
	public Status retweeted_status ~ delete _;
	public int retweet_count;
	public int favorite_count;
	public StatusEntities entities = new .() ~ delete _;
	public bool favorited;
	public bool retweeted;
	public bool? possibly_sensitive;
	public String lang ~ delete _;
}

[JsonObject]
class SearchMetadata
{
	public double completed_in;
	public int max_id;
	public String max_id_str ~ delete _;
	public String next_results ~ delete _;
	public String query ~ delete _;
	public String refresh_url ~ delete _;
	public int count;
	public int since_id;
	public String since_id_str ~ delete _;
}

[JsonObject]
class Twitter
{
	public List<Status> statuses = new .() ~ DeleteContainerAndItems!(_);
	public SearchMetadata search_metadata = new .() ~ delete _;
}

// ---- citm_catalog ----

[JsonObject]
class Event
{
	public String description ~ delete _;
	public int id;
	public String logo ~ delete _;
	public String name ~ delete _;
	public List<int> subTopicIds = new .() ~ delete _;
	public String subjectCode ~ delete _;
	public String subtitle ~ delete _;
	public List<int> topicIds = new .() ~ delete _;
}

[JsonObject]
class Price
{
	public int amount;
	public int audienceSubCategoryId;
	public int seatCategoryId;
}

[JsonObject]
class Area
{
	public int areaId;
	public List<String> blockIds = new .() ~ DeleteContainerAndItems!(_);
}

[JsonObject]
class SeatCategory
{
	public List<Area> areas = new .() ~ DeleteContainerAndItems!(_);
	public int seatCategoryId;
}

[JsonObject]
class Performance
{
	public int eventId;
	public int id;
	public String logo ~ delete _;
	public String name ~ delete _;
	public List<Price> prices = new .() ~ DeleteContainerAndItems!(_);
	public List<SeatCategory> seatCategories = new .() ~ DeleteContainerAndItems!(_);
	public String seatMapImage ~ delete _;
	public int start;
	public String venueCode ~ delete _;
}

/// Reads topicSubTopics, a map of id lists, which BJSON's generated code cannot (no List values)
class SubTopicsConverter : IJsonConverter<Dictionary<String, List<int>>>
{
	public Result<void> WriteJson(Stream stream, Dictionary<String, List<int>> value) => .Err;

	public Result<Dictionary<String, List<int>>> ReadJson(JsonValue value)
	{
		if (!value.IsObject())
			return .Err;
		let map = new Dictionary<String, List<int>>();
		for (let kv in value.AsObject().Value)
		{
			if (!kv.value.IsArray())
			{
				DeleteDictionaryAndKeysAndValues!(map);
				return .Err;
			}
			let list = new List<int>();
			for (let x in kv.value.AsArray().Value)
				list.Add((int)x);
			map.Add(new String(kv.key), list);
		}
		return map;
	}
}

[JsonObject]
class CitmCatalog
{
	public Dictionary<String, String> areaNames = new .() ~ DeleteDictionaryAndKeysAndValues!(_);
	public Dictionary<String, String> audienceSubCategoryNames = new .() ~ DeleteDictionaryAndKeysAndValues!(_);
	public Dictionary<String, String> blockNames = new .() ~ DeleteDictionaryAndKeysAndValues!(_);
	public Dictionary<String, Event> events = new .() ~ DeleteDictionaryAndKeysAndValues!(_);
	public List<Performance> performances = new .() ~ DeleteContainerAndItems!(_);
	public Dictionary<String, String> seatCategoryNames = new .() ~ DeleteDictionaryAndKeysAndValues!(_);
	public Dictionary<String, String> subTopicNames = new .() ~ DeleteDictionaryAndKeysAndValues!(_);
	public Dictionary<String, String> subjectNames = new .() ~ DeleteDictionaryAndKeysAndValues!(_);
	public Dictionary<String, String> topicNames = new .() ~ DeleteDictionaryAndKeysAndValues!(_);
	[JsonConverter(typeof(SubTopicsConverter))]
	public Dictionary<String, List<int>> topicSubTopics ~ { if (_ != null) DeleteDictionaryAndKeysAndValues!(_); };
	public Dictionary<String, String> venueNames = new .() ~ DeleteDictionaryAndKeysAndValues!(_);
}

static class Typed
{
	/// Decodes `text` as `kind` into a new object and deletes it; with `check`, prints the check line
	/// first. Returns false on a parse or binding error.
	public static bool Run(StringView kind, StringView text, bool check)
	{
		if (kind == "twitter")
		{
			let t = scope Twitter();
			if (BJSON.Json.Deserialize<Twitter>(text, t) case .Err(let err))
			{
				if (check)
					Console.Error.WriteLine(scope $"error: {err}");
				return false;
			}
			if (check)
			{
				uint64 ids = 0;
				int followers = 0, retweets = 0, hashtags = 0, chars = 0, media = 0, urls = 0;
				for (let s in t.statuses)
				{
					ids &+= (uint64)s.id;
					followers += s.user.followers_count;
					if (s.retweeted_status != null)
						retweets++;
					hashtags += s.entities.hashtags.Count;
					chars += Program.Chars(s.text);
					media += s.entities.media.Count;
					urls += s.user.entities.description.urls.Count;
				}
				Console.WriteLine(scope $"check: {t.statuses.Count} {ids} {followers} {retweets} {hashtags} {chars} {media} {urls}");
			}
			return true;
		}
		let c = scope CitmCatalog();
		if (BJSON.Json.Deserialize<CitmCatalog>(text, c) case .Err(let err))
		{
			if (check)
				Console.Error.WriteLine(scope $"error: {err}");
			return false;
		}
		if (check)
		{
			int eventIds = 0, names = 0, perfIds = 0, amounts = 0, areas = 0, subTopics = 0;
			for (let e in c.events.Values)
			{
				eventIds += e.id;
				names += Program.Chars(e.name);
			}
			for (let p in c.performances)
			{
				perfIds += p.id;
				for (let pr in p.prices)
					amounts += pr.amount;
				for (let sc in p.seatCategories)
					areas += sc.areas.Count;
			}
			if (c.topicSubTopics != null)
			{
				for (let l in c.topicSubTopics.Values)
					subTopics += l.Count;
			}
			Console.WriteLine(scope $"check: {c.events.Count} {eventIds} {c.performances.Count} {perfIds} {amounts} {areas} {names} {subTopics}");
		}
		return true;
	}
}
