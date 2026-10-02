// The typed track's classes, shared by Jackson, fastjson2, Gson and DSL-JSON: serde-rs/json-benchmark's
// twitter, citm_catalog and canada structs (src/copy/*.rs, src/canada.rs) with ../reference.py's
// simplifications (string enums, ids and colors as strings; always-null fields as nullable strings;
// empty arrays as lists of strings; doubles for coordinates). Public fields named as in the JSON;
// Option<T> fields are boxed (null when absent or null). User.protected is a Java keyword, so that one
// field carries each library's rename annotation. @CompiledJson makes DSL-JSON's annotation processor
// generate converters for every class.
import com.alibaba.fastjson2.annotation.JSONField;
import com.dslplatform.json.CompiledJson;
import com.dslplatform.json.JsonAttribute;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.google.gson.annotations.SerializedName;
import java.util.List;
import java.util.Map;

public final class Schema {
	// ---- twitter ----

	@CompiledJson
	public static class Twitter {
		public List<Status> statuses;
		public SearchMetadata search_metadata;
	}

	@CompiledJson
	public static class Status {
		public Metadata metadata;
		public String created_at;
		public long id;
		public String id_str;
		public String text;
		public String source;
		public boolean truncated;
		public Long in_reply_to_status_id;
		public String in_reply_to_status_id_str;
		public Long in_reply_to_user_id;
		public String in_reply_to_user_id_str;
		public String in_reply_to_screen_name;
		public User user;
		public String geo;
		public String coordinates;
		public String place;
		public String contributors;
		public Status retweeted_status;
		public long retweet_count;
		public long favorite_count;
		public StatusEntities entities;
		public boolean favorited;
		public boolean retweeted;
		public Boolean possibly_sensitive;
		public String lang;
	}

	@CompiledJson
	public static class Metadata {
		public String result_type;
		public String iso_language_code;
	}

	@CompiledJson
	public static class User {
		public long id;
		public String id_str;
		public String name;
		public String screen_name;
		public String location;
		public String description;
		public String url;
		public UserEntities entities;
		@JsonProperty("protected")
		@SerializedName("protected")
		@JSONField(name = "protected")
		@JsonAttribute(name = "protected")
		public boolean isProtected;
		public long followers_count;
		public long friends_count;
		public long listed_count;
		public String created_at;
		public long favourites_count;
		public Long utc_offset;
		public String time_zone;
		public boolean geo_enabled;
		public boolean verified;
		public long statuses_count;
		public String lang;
		public boolean contributors_enabled;
		public boolean is_translator;
		public boolean is_translation_enabled;
		public String profile_background_color;
		public String profile_background_image_url;
		public String profile_background_image_url_https;
		public boolean profile_background_tile;
		public String profile_image_url;
		public String profile_image_url_https;
		public String profile_banner_url;
		public String profile_link_color;
		public String profile_sidebar_border_color;
		public String profile_sidebar_fill_color;
		public String profile_text_color;
		public boolean profile_use_background_image;
		public boolean default_profile;
		public boolean default_profile_image;
		public boolean following;
		public boolean follow_request_sent;
		public boolean notifications;
	}

	@CompiledJson
	public static class UserEntities {
		public UserUrl url;
		public UserEntitiesDescription description;
	}

	@CompiledJson
	public static class UserUrl {
		public List<Url> urls;
	}

	@CompiledJson
	public static class Url {
		public String url;
		public String expanded_url;
		public String display_url;
		public List<Long> indices;
	}

	@CompiledJson
	public static class UserEntitiesDescription {
		public List<Url> urls;
	}

	@CompiledJson
	public static class StatusEntities {
		public List<Hashtag> hashtags;
		public List<String> symbols;
		public List<Url> urls;
		public List<UserMention> user_mentions;
		public List<Media> media;
	}

	@CompiledJson
	public static class Hashtag {
		public String text;
		public List<Long> indices;
	}

	@CompiledJson
	public static class UserMention {
		public String screen_name;
		public String name;
		public long id;
		public String id_str;
		public List<Long> indices;
	}

	@CompiledJson
	public static class Media {
		public long id;
		public String id_str;
		public List<Long> indices;
		public String media_url;
		public String media_url_https;
		public String url;
		public String display_url;
		public String expanded_url;
		public String type;
		public Sizes sizes;
		public Long source_status_id;
		public String source_status_id_str;
	}

	@CompiledJson
	public static class Sizes {
		public Size medium;
		public Size small;
		public Size thumb;
		public Size large;
	}

	@CompiledJson
	public static class Size {
		public long w;
		public long h;
		public String resize;
	}

	@CompiledJson
	public static class SearchMetadata {
		public double completed_in;
		public long max_id;
		public String max_id_str;
		public String next_results;
		public String query;
		public String refresh_url;
		public long count;
		public long since_id;
		public String since_id_str;
	}

	// ---- citm_catalog ----

	@CompiledJson
	public static class CitmCatalog {
		public Map<String, String> areaNames;
		public Map<String, String> audienceSubCategoryNames;
		public Map<String, String> blockNames;
		public Map<String, Event> events;
		public List<Performance> performances;
		public Map<String, String> seatCategoryNames;
		public Map<String, String> subTopicNames;
		public Map<String, String> subjectNames;
		public Map<String, String> topicNames;
		public Map<String, List<Long>> topicSubTopics;
		public Map<String, String> venueNames;
	}

	@CompiledJson
	public static class Event {
		public String description;
		public long id;
		public String logo;
		public String name;
		public List<Long> subTopicIds;
		public String subjectCode;
		public String subtitle;
		public List<Long> topicIds;
	}

	@CompiledJson
	public static class Performance {
		public long eventId;
		public long id;
		public String logo;
		public String name;
		public List<Price> prices;
		public List<SeatCategory> seatCategories;
		public String seatMapImage;
		public long start;
		public String venueCode;
	}

	@CompiledJson
	public static class Price {
		public long amount;
		public long audienceSubCategoryId;
		public long seatCategoryId;
	}

	@CompiledJson
	public static class SeatCategory {
		public List<Area> areas;
		public long seatCategoryId;
	}

	@CompiledJson
	public static class Area {
		public long areaId;
		public List<String> blockIds;
	}

	// ---- canada ----

	@CompiledJson
	public static class Canada {
		public String type;
		public List<Feature> features;
	}

	@CompiledJson
	public static class Feature {
		public String type;
		public Map<String, String> properties;
		public Geometry geometry;
	}

	@CompiledJson
	public static class Geometry {
		public String type;
		public List<List<double[]>> coordinates;
	}
}
