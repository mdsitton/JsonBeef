// glaze benchmark: glaze <dom|typed|query> <input> <min-samples>
//   dom   - glz::read_json into glz::generic (its default generic value: numbers as double, objects
//           in insertion order), a fresh value per document, destroyed after it.
//   typed - glz::read_json into structs mirroring serde-rs/json-benchmark (see ../reference.py; pure
//           compile-time reflection of aggregates, std::optional for nullable or absent fields,
//           std::unique_ptr for the recursive retweeted_status, std::map for id-keyed maps,
//           std::array for indices and coordinate pairs), default options (unknown keys are errors;
//           the schema has them all). A fresh value per run.
//   query - on-demand track: glz::lazy_json over the buffer, reading only the queried fields (it skips
//           the rest without validating it, like gjson; the check runs once on known-good input).
// The check line (see ../reference.py) is computed once before timing.
#include <glaze/glaze.hpp>
#include <glaze/json/lazy.hpp>
#include <array>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>
extern "C" {
#include "../c/bench.h"
}

// ---- twitter ----

struct Metadata
{
	std::string result_type;
	std::string iso_language_code;
};

struct Url
{
	std::string url;
	std::string expanded_url;
	std::string display_url;
	std::array<uint32_t, 2> indices;
};

struct UserUrl
{
	std::vector<Url> urls;
};

struct UserEntitiesDescription
{
	std::vector<Url> urls;
};

struct UserEntities
{
	std::optional<UserUrl> url;
	UserEntitiesDescription description;
};

struct User
{
	uint32_t id;
	std::string id_str;
	std::string name;
	std::string screen_name;
	std::string location;
	std::string description;
	std::optional<std::string> url;
	UserEntities entities;
	bool protected_;
	uint32_t followers_count;
	uint32_t friends_count;
	uint32_t listed_count;
	std::string created_at;
	uint32_t favourites_count;
	std::optional<int32_t> utc_offset;
	std::optional<std::string> time_zone;
	bool geo_enabled;
	bool verified;
	uint32_t statuses_count;
	std::string lang;
	bool contributors_enabled;
	bool is_translator;
	bool is_translation_enabled;
	std::string profile_background_color;
	std::string profile_background_image_url;
	std::string profile_background_image_url_https;
	bool profile_background_tile;
	std::string profile_image_url;
	std::string profile_image_url_https;
	std::optional<std::string> profile_banner_url;
	std::string profile_link_color;
	std::string profile_sidebar_border_color;
	std::string profile_sidebar_fill_color;
	std::string profile_text_color;
	bool profile_use_background_image;
	bool default_profile;
	bool default_profile_image;
	bool following;
	bool follow_request_sent;
	bool notifications;
};

template <>
struct glz::meta<User>
{
	static constexpr auto modify = glz::object("protected", &User::protected_);
};

struct Hashtag
{
	std::string text;
	std::array<uint32_t, 2> indices;
};

struct UserMention
{
	std::string screen_name;
	std::string name;
	uint32_t id;
	std::string id_str;
	std::array<uint32_t, 2> indices;
};

struct Size
{
	uint32_t w;
	uint32_t h;
	std::string resize;
};

struct Sizes
{
	Size medium;
	Size small;
	Size thumb;
	Size large;
};

struct Media
{
	uint64_t id;
	std::string id_str;
	std::array<uint32_t, 2> indices;
	std::string media_url;
	std::string media_url_https;
	std::string url;
	std::string display_url;
	std::string expanded_url;
	std::string type;
	Sizes sizes;
	std::optional<uint64_t> source_status_id;
	std::optional<std::string> source_status_id_str;
};

struct StatusEntities
{
	std::vector<Hashtag> hashtags;
	std::vector<std::string> symbols;
	std::vector<Url> urls;
	std::vector<UserMention> user_mentions;
	std::optional<std::vector<Media>> media;
};

struct Status
{
	Metadata metadata;
	std::string created_at;
	uint64_t id;
	std::string id_str;
	std::string text;
	std::string source;
	bool truncated;
	std::optional<uint64_t> in_reply_to_status_id;
	std::optional<std::string> in_reply_to_status_id_str;
	std::optional<uint32_t> in_reply_to_user_id;
	std::optional<std::string> in_reply_to_user_id_str;
	std::optional<std::string> in_reply_to_screen_name;
	User user;
	std::optional<std::string> geo;
	std::optional<std::string> coordinates;
	std::optional<std::string> place;
	std::optional<std::string> contributors;
	std::unique_ptr<Status> retweeted_status;
	uint32_t retweet_count;
	uint32_t favorite_count;
	StatusEntities entities;
	bool favorited;
	bool retweeted;
	std::optional<bool> possibly_sensitive;
	std::string lang;
};

struct SearchMetadata
{
	double completed_in;
	uint64_t max_id;
	std::string max_id_str;
	std::string next_results;
	std::string query;
	std::string refresh_url;
	uint32_t count;
	uint64_t since_id;
	std::string since_id_str;
};

struct Twitter
{
	std::vector<Status> statuses;
	SearchMetadata search_metadata;
};

// ---- citm_catalog ----

struct Event
{
	std::optional<std::string> description;
	uint32_t id;
	std::optional<std::string> logo;
	std::string name;
	std::vector<uint32_t> subTopicIds;
	std::optional<std::string> subjectCode;
	std::optional<std::string> subtitle;
	std::vector<uint32_t> topicIds;
};

struct Price
{
	uint32_t amount;
	uint32_t audienceSubCategoryId;
	uint32_t seatCategoryId;
};

struct Area
{
	uint32_t areaId;
	std::vector<std::string> blockIds;
};

struct SeatCategory
{
	std::vector<Area> areas;
	uint32_t seatCategoryId;
};

struct Performance
{
	uint32_t eventId;
	uint32_t id;
	std::optional<std::string> logo;
	std::optional<std::string> name;
	std::vector<Price> prices;
	std::vector<SeatCategory> seatCategories;
	std::optional<std::string> seatMapImage;
	uint64_t start;
	std::string venueCode;
};

using Names = std::map<std::string, std::string>;

struct CitmCatalog
{
	Names areaNames;
	Names audienceSubCategoryNames;
	Names blockNames;
	std::map<std::string, Event> events;
	std::vector<Performance> performances;
	Names seatCategoryNames;
	Names subTopicNames;
	Names subjectNames;
	Names topicNames;
	std::map<std::string, std::vector<uint32_t>> topicSubTopics;
	Names venueNames;
};

// ---- canada ----

struct Geometry
{
	std::string type;
	std::vector<std::vector<std::array<double, 2>>> coordinates;
};

struct Feature
{
	std::string type;
	std::map<std::string, std::string> properties;
	Geometry geometry;
};

struct FeatureCollection
{
	std::string type;
	std::vector<Feature> features;
};

// ---- the harness ----

static inputs_t in;
static std::string_view text;
static const char *kind;

static long chars(const std::string &s)
{
	return utf8_chars(s.data(), s.size());
}

static void walk(const glz::generic &v, check_t *c)
{
	if (v.is_object())
	{
		c->objects++;
		for (auto &[key, x] : v.get_object())
		{
			c->keys++;
			c->chars += chars(key);
			walk(x, c);
		}
	}
	else if (v.is_array())
	{
		c->arrays++;
		for (auto &x : v.get_array())
			walk(x, c);
	}
	else if (v.is_string())
	{
		c->strings++;
		c->chars += chars(v.get_string());
	}
	else if (v.is_number())
	{
		c->numbers++;
		c->numsum += num_bits(v.get_number());
	}
	else if (v.is_boolean())
		(v.get_boolean() ? c->trues : c->falses)++;
	else if (v.is_null())
		c->nulls++;
}

template <class T>
static void read(T &value, std::string_view s)
{
	auto e = glz::read_json(value, s);
	if (e)
	{
		fprintf(stderr, "parse error: %s\n", glz::format_error(e, s).c_str());
		exit(1);
	}
}

static void dom_op(void *)
{
	for (int i = 0; i < in.count; i++)
	{
		glz::generic v;
		read(v, std::string_view(in.docs[i].data, in.docs[i].size));
	}
}

template <class T>
static void typed_op(void *)
{
	T v{};
	read(v, text);
}

static std::string twitter_check()
{
	Twitter t{};
	read(t, text);
	uint64_t ids = 0, followers = 0, retweets = 0, hashtags = 0, chars_ = 0, media = 0, urls = 0;
	for (auto &s : t.statuses)
	{
		ids += s.id;
		followers += s.user.followers_count;
		retweets += s.retweeted_status != nullptr;
		hashtags += s.entities.hashtags.size();
		chars_ += chars(s.text);
		media += s.entities.media ? s.entities.media->size() : 0;
		urls += s.user.entities.description.urls.size();
	}
	return "check: " + std::to_string(t.statuses.size()) + " " + std::to_string(ids) + " " + std::to_string(followers) +
		" " + std::to_string(retweets) + " " + std::to_string(hashtags) + " " + std::to_string(chars_) + " " +
		std::to_string(media) + " " + std::to_string(urls);
}

static std::string citm_check()
{
	CitmCatalog c{};
	read(c, text);
	uint64_t eventIds = 0, names = 0, perfIds = 0, amounts = 0, areas = 0, subTopics = 0;
	for (auto &[_, e] : c.events)
	{
		eventIds += e.id;
		names += chars(e.name);
	}
	for (auto &p : c.performances)
	{
		perfIds += p.id;
		for (auto &pr : p.prices)
			amounts += pr.amount;
		for (auto &sc : p.seatCategories)
			areas += sc.areas.size();
	}
	for (auto &[_, v] : c.topicSubTopics)
		subTopics += v.size();
	return "check: " + std::to_string(c.events.size()) + " " + std::to_string(eventIds) + " " +
		std::to_string(c.performances.size()) + " " + std::to_string(perfIds) + " " + std::to_string(amounts) + " " +
		std::to_string(areas) + " " + std::to_string(names) + " " + std::to_string(subTopics);
}

static std::string canada_check()
{
	FeatureCollection f{};
	read(f, text);
	uint64_t rings = 0, points = 0, sum = 0, names = 0;
	for (auto &feature : f.features)
	{
		for (auto &ring : feature.geometry.coordinates)
		{
			rings++;
			points += ring.size();
			for (auto &p : ring)
				sum += num_bits(p[0]) + num_bits(p[1]);
		}
		for (auto &[_, v] : feature.properties)
			names += chars(v);
	}
	char hex[17];
	snprintf(hex, sizeof hex, "%016llx", (unsigned long long)sum);
	return "check: " + std::to_string(f.features.size()) + " " + std::to_string(rings) + " " + std::to_string(points) +
		" " + hex + " " + std::to_string(names);
}

// ---- query ----

struct query_t
{
	uint64_t a, b, c;
};

static query_t result;

template <class T>
static T must(const glz::expected<T, glz::error_ctx> &r)
{
	if (!r)
	{
		fprintf(stderr, "query error: %s\n", glz::format_error(r.error(), text).c_str());
		exit(1);
	}
	return *r;
}

static void query_op(void *)
{
	query_t q{};
	auto doc = glz::lazy_json(text);
	if (!doc)
	{
		fprintf(stderr, "parse error\n");
		exit(1);
	}
	auto &d = *doc;
	if (strcmp(kind, "twitter") == 0)
	{
		for (auto status : d["statuses"])
		{
			q.a++;
			q.b += must(status["user"]["followers_count"].get<uint64_t>());
			for (auto tag : status["entities"]["hashtags"])
			{
				(void)tag;
				q.c++;
			}
		}
	}
	else if (strcmp(kind, "citm_catalog") == 0)
	{
		for (auto performance : d["performances"])
		{
			q.a++;
			q.b += must(performance["id"].get<uint64_t>());
		}
	}
	else
	{
		for (auto feature : d["features"])
			for (auto ring : feature["geometry"]["coordinates"])
				for (auto pair : ring)
				{
					q.a++;
					q.b += num_bits(must(pair[0].get<double>()));
				}
	}
	result = q;
}

int main(int argc, char **argv)
{
	if (argc < 4)
		return usage("glaze", "dom|typed|query");
	std::string mode = argv[1];
	in = read_inputs(argv[2]);
	text = std::string_view(in.docs[0].data, in.docs[0].size);
	int n = atoi(argv[3]);
	if (mode == "dom")
	{
		check_t c = {};
		for (int i = 0; i < in.count; i++)
		{
			glz::generic v;
			read(v, std::string_view(in.docs[i].data, in.docs[i].size));
			walk(v, &c);
		}
		print_check(&c);
		print_result(measure(dom_op, nullptr, n), in.total);
		return 0;
	}
	kind = input_kind(argv[2]);
	if (!kind || (mode != "typed" && mode != "query"))
		return kind ? usage("glaze", "dom|typed|query") : 3;
	if (mode == "typed")
	{
		bench_op op;
		if (strcmp(kind, "twitter") == 0)
		{
			printf("%s\n", twitter_check().c_str());
			op = typed_op<Twitter>;
		}
		else if (strcmp(kind, "citm_catalog") == 0)
		{
			printf("%s\n", citm_check().c_str());
			op = typed_op<CitmCatalog>;
		}
		else
		{
			printf("%s\n", canada_check().c_str());
			op = typed_op<FeatureCollection>;
		}
		fflush(stdout);
		print_result(measure(op, nullptr, n), in.total);
		return 0;
	}
	query_op(nullptr);
	if (strcmp(kind, "twitter") == 0)
		printf("check: %llu %llu %llu\n", (unsigned long long)result.a, (unsigned long long)result.b, (unsigned long long)result.c);
	else if (strcmp(kind, "citm_catalog") == 0)
		printf("check: %llu %llu\n", (unsigned long long)result.a, (unsigned long long)result.b);
	else
		printf("check: %llu %016llx\n", (unsigned long long)result.a, (unsigned long long)result.b);
	fflush(stdout);
	print_result(measure(query_op, nullptr, n), in.total);
	return 0;
}
