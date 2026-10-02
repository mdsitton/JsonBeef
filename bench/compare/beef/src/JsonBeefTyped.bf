using System;
using System.Collections;
using JsonBeef;

namespace JsonBeefTyped;

typealias Program = JsonBeefBench.Program;

/// The typed track's classes for JsonBeef's [JsonObject] (in a namespace of their own, outside
/// JsonBeefBench, whose Typed.bf classes of the same names are BJSON's): serde-rs/json-benchmark's
/// twitter, citm_catalog and canada schemas with the
/// simplifications ../../reference.py lists. The 64-bit ids are uint64 (LongId), the other integers
/// int64; Option<T> is a nullable field (`T?`, or a null String/object); fields that are absent stay
/// null (no allocation up front). Read with JsonSerializer.Read<T>(text, obj): straight from the
/// reader's tokens, no tree in between, every check on.

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
	public List<int> indices ~ delete _;
}

[JsonObject]
class UserUrl
{
	public List<Url> urls ~ DeleteContainerAndItems!(_);
}

[JsonObject]
class UserEntitiesDescription
{
	public List<Url> urls ~ DeleteContainerAndItems!(_);
}

[JsonObject]
class UserEntities
{
	public UserUrl url ~ delete _;
	public UserEntitiesDescription description ~ delete _;
}

[JsonObject]
class User
{
	public uint64 id;
	public String id_str ~ delete _;
	public String name ~ delete _;
	public String screen_name ~ delete _;
	public String location ~ delete _;
	public String description ~ delete _;
	public String url ~ delete _;
	public UserEntities entities ~ delete _;
	[JsonName("protected")]
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
	public List<int> indices ~ delete _;
}

[JsonObject]
class UserMention
{
	public String screen_name ~ delete _;
	public String name ~ delete _;
	public uint64 id;
	public String id_str ~ delete _;
	public List<int> indices ~ delete _;
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
	public Size medium ~ delete _;
	public Size small ~ delete _;
	public Size thumb ~ delete _;
	public Size large ~ delete _;
}

[JsonObject]
class Media
{
	public uint64 id;
	public String id_str ~ delete _;
	public List<int> indices ~ delete _;
	public String media_url ~ delete _;
	public String media_url_https ~ delete _;
	public String url ~ delete _;
	public String display_url ~ delete _;
	public String expanded_url ~ delete _;
	[JsonName("type")]
	public String media_type ~ delete _;
	public Sizes sizes ~ delete _;
	public uint64? source_status_id;
	public String source_status_id_str ~ delete _;
}

[JsonObject]
class StatusEntities
{
	public List<Hashtag> hashtags ~ DeleteContainerAndItems!(_);
	public List<String> symbols ~ DeleteContainerAndItems!(_);
	public List<Url> urls ~ DeleteContainerAndItems!(_);
	public List<UserMention> user_mentions ~ DeleteContainerAndItems!(_);
	/// Absent on most statuses: stays null then
	public List<Media> media ~ DeleteContainerAndItems!(_);
}

[JsonObject]
class Status
{
	public Metadata metadata ~ delete _;
	public String created_at ~ delete _;
	public uint64 id;
	public String id_str ~ delete _;
	public String text ~ delete _;
	public String source ~ delete _;
	public bool truncated;
	public uint64? in_reply_to_status_id;
	public String in_reply_to_status_id_str ~ delete _;
	public uint64? in_reply_to_user_id;
	public String in_reply_to_user_id_str ~ delete _;
	public String in_reply_to_screen_name ~ delete _;
	public User user ~ delete _;
	public String geo ~ delete _;
	public String coordinates ~ delete _;
	public String place ~ delete _;
	public String contributors ~ delete _;
	public Status retweeted_status ~ delete _;
	public int retweet_count;
	public int favorite_count;
	public StatusEntities entities ~ delete _;
	public bool favorited;
	public bool retweeted;
	public bool? possibly_sensitive;
	public String lang ~ delete _;
}

[JsonObject]
class SearchMetadata
{
	public double completed_in;
	public uint64 max_id;
	public String max_id_str ~ delete _;
	public String next_results ~ delete _;
	public String query ~ delete _;
	public String refresh_url ~ delete _;
	public int count;
	public uint64 since_id;
	public String since_id_str ~ delete _;
}

[JsonObject]
class Twitter
{
	public List<Status> statuses ~ DeleteContainerAndItems!(_);
	public SearchMetadata search_metadata ~ delete _;
}

// ---- citm_catalog ----

[JsonObject]
class Event
{
	public String description ~ delete _;
	public int id;
	public String logo ~ delete _;
	public String name ~ delete _;
	public List<int> subTopicIds ~ delete _;
	public String subjectCode ~ delete _;
	public String subtitle ~ delete _;
	public List<int> topicIds ~ delete _;
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
	public List<String> blockIds ~ DeleteContainerAndItems!(_);
}

[JsonObject]
class SeatCategory
{
	public List<Area> areas ~ DeleteContainerAndItems!(_);
	public int seatCategoryId;
}

[JsonObject]
class Performance
{
	public int eventId;
	public int id;
	public String logo ~ delete _;
	public String name ~ delete _;
	public List<Price> prices ~ DeleteContainerAndItems!(_);
	public List<SeatCategory> seatCategories ~ DeleteContainerAndItems!(_);
	public String seatMapImage ~ delete _;
	public uint64 start;
	public String venueCode ~ delete _;
}

[JsonObject]
class CitmCatalog
{
	public Dictionary<String, String> areaNames ~ DeleteDictionaryAndKeysAndValues!(_);
	public Dictionary<String, String> audienceSubCategoryNames ~ DeleteDictionaryAndKeysAndValues!(_);
	public Dictionary<String, String> blockNames ~ DeleteDictionaryAndKeysAndValues!(_);
	public Dictionary<String, Event> events ~ DeleteDictionaryAndKeysAndValues!(_);
	public List<Performance> performances ~ DeleteContainerAndItems!(_);
	public Dictionary<String, String> seatCategoryNames ~ DeleteDictionaryAndKeysAndValues!(_);
	public Dictionary<String, String> subTopicNames ~ DeleteDictionaryAndKeysAndValues!(_);
	public Dictionary<String, String> subjectNames ~ DeleteDictionaryAndKeysAndValues!(_);
	public Dictionary<String, String> topicNames ~ DeleteDictionaryAndKeysAndValues!(_);
	public Dictionary<String, List<int>> topicSubTopics ~ DeleteDictionaryAndKeysAndValues!(_);
	public Dictionary<String, String> venueNames ~ DeleteDictionaryAndKeysAndValues!(_);
}

// ---- canada ----

[JsonObject]
class Geometry
{
	[JsonName("type")]
	public String geometry_type ~ delete _;
	/// Rings of [lon, lat] pairs
	public List<List<List<double>>> coordinates ~ { if (_ != null) { for (let ring in _) DeleteContainerAndItems!(ring); delete _; } };
}

[JsonObject]
class Feature
{
	[JsonName("type")]
	public String feature_type ~ delete _;
	public Dictionary<String, String> properties ~ DeleteDictionaryAndKeysAndValues!(_);
	public Geometry geometry ~ delete _;
}

[JsonObject]
class Canada
{
	[JsonName("type")]
	public String canada_type ~ delete _;
	public List<Feature> features ~ DeleteContainerAndItems!(_);
}

static class Run
{
	/// Decodes `text` as `kind` into a new object and deletes it; with `check`, prints the check line
	/// first. Returns false on a parse or binding error.
	public static bool Typed(StringView kind, StringView text, bool check)
	{
		if (kind == "twitter")
		{
			let t = scope Twitter();
			if (!Read(text, t, check))
				return false;
			if (check)
			{
				uint64 ids = 0;
				int followers = 0, retweets = 0, hashtags = 0, chars = 0, media = 0, urls = 0;
				for (let s in t.statuses)
				{
					ids &+= s.id;
					followers += s.user.followers_count;
					if (s.retweeted_status != null)
						retweets++;
					hashtags += s.entities.hashtags.Count;
					chars += Program.Chars(s.text);
					media += (s.entities.media != null) ? s.entities.media.Count : 0;
					urls += s.user.entities.description.urls.Count;
				}
				Console.WriteLine(scope $"check: {t.statuses.Count} {ids} {followers} {retweets} {hashtags} {chars} {media} {urls}");
			}
			return true;
		}
		if (kind == "citm_catalog")
		{
			let c = scope CitmCatalog();
			if (!Read(text, c, check))
				return false;
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
				for (let l in c.topicSubTopics.Values)
					subTopics += l.Count;
				Console.WriteLine(scope $"check: {c.events.Count} {eventIds} {c.performances.Count} {perfIds} {amounts} {areas} {names} {subTopics}");
			}
			return true;
		}
		let canada = scope Canada();
		if (!Read(text, canada, check))
			return false;
		if (check)
		{
			int rings = 0, points = 0, chars = 0;
			uint64 sum = 0;
			for (let f in canada.features)
			{
				for (let ring in f.geometry.coordinates)
				{
					rings++;
					points += ring.Count;
					for (let pair in ring)
					{
						for (let x in pair)
							sum &+= Program.Bits(x);
					}
				}
				for (let v in f.properties.Values)
					chars += Program.Chars(v);
			}
			Console.WriteLine(scope $"check: {canada.features.Count} {rings} {points} {Hex(sum, .. scope .())} {chars}");
		}
		return true;
	}

	static bool Read<T>(StringView text, T target, bool check) where T : class, IJsonSerializable
	{
		if (JsonSerializer.Read(text, target) case .Err(let error))
		{
			if (check)
				Console.Error.WriteLine(scope $"error: {error}");
			return false;
		}
		return true;
	}

	static void Hex(uint64 value, String output)
	{
		for (int shift = 60; shift >= 0; shift -= 4)
			output.Append("0123456789abcdef"[(int)((value >> (uint64)shift) & 0xF)]);
	}

	static JsonReader sReader = new .() ~ delete _;

	/// The query track: only the queried values are read, everything else skipped (and checked) by the
	/// reader's SkipValue; Find goes to the array. Returns false on a parse error.
	public static bool Query(StringView kind, StringView text, bool check)
	{
		let reader = sReader;
		reader.Reset(text);
		if (kind == "twitter")
		{
			int statuses = 0;
			int64 followers = 0;
			int hashtags = 0;
			if (!Try(reader.Find("/statuses"), check) || reader.TokenType != .StartArray)
				return false;
			while (Element(reader, check, let more) && more)
			{
				statuses++;
				// The status: its user's followers_count and its entities' hashtags
				while (Member(reader, check, let member) && member)
				{
					if (reader.StringValue == "user")
					{
						if (!Next(reader, check))
							return false;
						while (Member(reader, check, let userMember) && userMember)
						{
							if (reader.StringValue == "followers_count")
							{
								if (!Next(reader, check))
									return false;
								if (!reader.TryGetInt64(let count))
									return false;
								followers += count;
							}
							else if (!Try(reader.SkipValue(), check))
								return false;
						}
					}
					else if (reader.StringValue == "entities")
					{
						if (!Next(reader, check))
							return false;
						while (Member(reader, check, let entityMember) && entityMember)
						{
							if (reader.StringValue == "hashtags")
							{
								if (!Next(reader, check))
									return false;
								while (Element(reader, check, let hashtag) && hashtag)
								{
									hashtags++;
									if (!Try(reader.SkipValue(), check))
										return false;
								}
							}
							else if (!Try(reader.SkipValue(), check))
								return false;
						}
					}
					else if (!Try(reader.SkipValue(), check))
						return false;
				}
			}
			if (!End(reader, check))
				return false;
			if (check)
				Console.WriteLine(scope $"check: {statuses} {followers} {hashtags}");
			return true;
		}
		if (kind == "citm_catalog")
		{
			int performances = 0;
			int64 ids = 0;
			if (!Try(reader.Find("/performances"), check) || reader.TokenType != .StartArray)
				return false;
			while (Element(reader, check, let more) && more)
			{
				performances++;
				while (Member(reader, check, let member) && member)
				{
					if (reader.StringValue == "id")
					{
						if (!Next(reader, check))
							return false;
						if (!reader.TryGetInt64(let id))
							return false;
						ids += id;
					}
					else if (!Try(reader.SkipValue(), check))
						return false;
				}
			}
			if (!End(reader, check))
				return false;
			if (check)
				Console.WriteLine(scope $"check: {performances} {ids}");
			return true;
		}
		// canada: every pair's longitude in features[*].geometry.coordinates[*][*]
		int pairs = 0;
		uint64 sum = 0;
		if (!Try(reader.Find("/features"), check) || reader.TokenType != .StartArray)
			return false;
		while (Element(reader, check, let feature) && feature)
		{
			while (Member(reader, check, let member) && member)
			{
				if (reader.StringValue != "geometry")
				{
					if (!Try(reader.SkipValue(), check))
						return false;
					continue;
				}
				if (!Next(reader, check))
					return false;
				while (Member(reader, check, let geometryMember) && geometryMember)
				{
					if (reader.StringValue != "coordinates")
					{
						if (!Try(reader.SkipValue(), check))
							return false;
						continue;
					}
					if (!Next(reader, check))
						return false;
					while (Element(reader, check, let ring) && ring)
					{
						while (Element(reader, check, let pair) && pair)
						{
							pairs++;
							// [lon, lat]: the first value, then the rest skipped
							if (!Next(reader, check))
								return false;
							if (!reader.TryGetDouble(let lon))
								return false;
							sum &+= Program.Bits(lon);
							while (Element(reader, check, let rest) && rest)
							{
								if (!Try(reader.SkipValue(), check))
									return false;
							}
						}
					}
				}
			}
		}
		if (!End(reader, check))
			return false;
		if (check)
			Console.WriteLine(scope $"check: {pairs} {Hex(sum, .. scope .())}");
		return true;
	}

	/// The next token in an object: `member` true at a name, false at its end.
	static bool Member(JsonReader reader, bool check, out bool member)
	{
		member = false;
		switch (reader.Next())
		{
		case .Ok(let token):
			member = token == .PropertyName;
			return true;
		case .Err(let error):
			if (check)
				Console.Error.WriteLine(scope $"error: {error}");
			return false;
		}
	}

	/// The next token in an array: `element` true at a value, false at its end.
	static bool Element(JsonReader reader, bool check, out bool element)
	{
		element = false;
		switch (reader.Next())
		{
		case .Ok(let token):
			element = token != .EndArray;
			return true;
		case .Err(let error):
			if (check)
				Console.Error.WriteLine(scope $"error: {error}");
			return false;
		}
	}

	static bool Next(JsonReader reader, bool check)
	{
		return Try(reader.Next(), check);
	}

	static bool Try<T>(Result<T, JsonParseError> result, bool check)
	{
		if (result case .Err(let error))
		{
			if (check)
				Console.Error.WriteLine(scope $"error: {error}");
			return false;
		}
		return true;
	}

	/// The rest of the document, skipped and checked: what follows the array, to the end.
	static bool End(JsonReader reader, bool check)
	{
		while (true)
		{
			switch (reader.Next())
			{
			case .Ok(let token):
				if (token == .EndOfDocument)
					return true;
				if (token == .PropertyName && !Try(reader.SkipValue(), check))
					return false;
			case .Err(let error):
				if (check)
					Console.Error.WriteLine(scope $"error: {error}");
				return false;
			}
		}
	}
}
