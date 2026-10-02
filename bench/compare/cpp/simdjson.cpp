// simdjson benchmark: simdjson <dom|ondemand|query> <input> <min-samples>
//   dom      - simdjson::dom::parser::parse of each document into its tape (the parser, and so its
//              buffers, reused across documents and runs: simdjson's documented usage; a document
//              lives until the next parse). Input buffers carry SIMDJSON_PADDING zero bytes, so
//              nothing is copied.
//   ondemand - streaming track: simdjson::ondemand::parser::iterate over each document and a
//              recursive walk of every value, keys unescaped (unescaped_key), strings unescaped
//              (get_string), numbers read with get_number (int64, uint64 or double); no tree.
//   query    - on-demand track (twitter, citm_catalog, canada only; see ../reference.py): the On-Demand
//              API reads only the queried fields, skipping everything else unparsed.
// The check line (see ../reference.py) comes from one untimed pass (code points counted exactly; the
// timed passes add byte lengths). Runtime dispatch picks the best kernel for this CPU.
#include <simdjson.h>
#include <string>
extern "C" {
#include "../c/bench.h"
}

using namespace simdjson;

static inputs_t in;
static bool exact;
static const char *kind;

static long len(std::string_view s)
{
	return exact ? utf8_chars(s.data(), s.size()) : (long)s.size();
}

static void fail(error_code e)
{
	fprintf(stderr, "parse error: %s\n", error_message(e));
	exit(1);
}

// ---- dom ----

static void walk(dom::element v, check_t *c)
{
	switch (v.type())
	{
	case dom::element_type::OBJECT:
		c->objects++;
		for (auto field : dom::object(v))
		{
			c->keys++;
			c->chars += len(field.key);
			walk(field.value, c);
		}
		break;
	case dom::element_type::ARRAY:
		c->arrays++;
		for (auto x : dom::array(v))
			walk(x, c);
		break;
	case dom::element_type::STRING:
		c->strings++;
		c->chars += len(std::string_view(v));
		break;
	case dom::element_type::INT64:
		c->numbers++;
		c->numsum += num_bits((double)int64_t(v));
		break;
	case dom::element_type::UINT64:
		c->numbers++;
		c->numsum += num_bits((double)uint64_t(v));
		break;
	case dom::element_type::DOUBLE:
		c->numbers++;
		c->numsum += num_bits(double(v));
		break;
	case dom::element_type::BOOL:
		if (bool(v))
			c->trues++;
		else
			c->falses++;
		break;
	case dom::element_type::NULL_VALUE:
		c->nulls++;
		break;
	default:
		fprintf(stderr, "unexpected element type\n");
		exit(1);
	}
}

static dom::parser dom_parser;

static dom::element dom_parse(doc_t *d)
{
	dom::element root;
	auto e = dom_parser.parse(d->data, d->size, false).get(root);
	if (e)
		fail(e);
	return root;
}

static void dom_op(void *)
{
	for (int i = 0; i < in.count; i++)
		dom_parse(&in.docs[i]);
}

// ---- ondemand (streaming) ----

static ondemand::parser od_parser;

static error_code od_walk(ondemand::value v, check_t *c);

static error_code od_number(ondemand::number_type t, ondemand::value v, check_t *c)
{
	c->numbers++;
	switch (t)
	{
	case ondemand::number_type::signed_integer:
	{
		int64_t i;
		SIMDJSON_TRY(v.get_int64().get(i));
		c->numsum += num_bits((double)i);
		break;
	}
	case ondemand::number_type::unsigned_integer:
	{
		uint64_t u;
		SIMDJSON_TRY(v.get_uint64().get(u));
		c->numsum += num_bits((double)u);
		break;
	}
	default:
	{
		double d;
		SIMDJSON_TRY(v.get_double().get(d));
		c->numsum += num_bits(d);
		break;
	}
	}
	return SUCCESS;
}

static error_code od_walk(ondemand::value v, check_t *c)
{
	ondemand::json_type t;
	SIMDJSON_TRY(v.type().get(t));
	switch (t)
	{
	case ondemand::json_type::object:
	{
		c->objects++;
		ondemand::object obj;
		SIMDJSON_TRY(v.get_object().get(obj));
		for (auto field : obj)
		{
			std::string_view key;
			SIMDJSON_TRY(field.unescaped_key().get(key));
			c->keys++;
			c->chars += len(key);
			ondemand::value x;
			SIMDJSON_TRY(field.value().get(x));
			SIMDJSON_TRY(od_walk(x, c));
		}
		break;
	}
	case ondemand::json_type::array:
	{
		c->arrays++;
		ondemand::array arr;
		SIMDJSON_TRY(v.get_array().get(arr));
		for (auto item : arr)
		{
			ondemand::value x;
			SIMDJSON_TRY(item.get(x));
			SIMDJSON_TRY(od_walk(x, c));
		}
		break;
	}
	case ondemand::json_type::string:
	{
		std::string_view s;
		SIMDJSON_TRY(v.get_string().get(s));
		c->strings++;
		c->chars += len(s);
		break;
	}
	case ondemand::json_type::number:
	{
		ondemand::number_type nt;
		SIMDJSON_TRY(v.get_number_type().get(nt));
		SIMDJSON_TRY(od_number(nt, v, c));
		break;
	}
	case ondemand::json_type::boolean:
	{
		bool b;
		SIMDJSON_TRY(v.get_bool().get(b));
		if (b)
			c->trues++;
		else
			c->falses++;
		break;
	}
	case ondemand::json_type::null:
	{
		bool is_null;
		SIMDJSON_TRY(v.is_null().get(is_null));
		c->nulls++;
		break;
	}
	default:
		return INCORRECT_TYPE;
	}
	return SUCCESS;
}

static void od_parse(doc_t *d, check_t *c)
{
	ondemand::document doc;
	auto e = od_parser.iterate(padded_string_view(d->data, d->size, d->size + BENCH_PADDING)).get(doc);
	ondemand::value root;
	if (!e)
		e = doc.get_value().get(root);
	if (!e)
		e = od_walk(root, c);
	if (!e && !doc.at_end())
		e = TRAILING_CONTENT;
	if (e)
		fail(e);
}

static check_t sink;

static void od_op(void *)
{
	check_t c = {};
	for (int i = 0; i < in.count; i++)
		od_parse(&in.docs[i], &c);
	sink = c;
}

// ---- query ----

struct query_t
{
	uint64_t a, b, c;
};

static query_t result;

static error_code run_query(doc_t *d, query_t *q)
{
	*q = {};
	ondemand::document doc;
	SIMDJSON_TRY(od_parser.iterate(padded_string_view(d->data, d->size, d->size + BENCH_PADDING)).get(doc));
	if (strcmp(kind, "twitter") == 0)
	{
		for (auto status : doc["statuses"])
		{
			uint64_t followers;
			SIMDJSON_TRY(status["user"]["followers_count"].get_uint64().get(followers));
			ondemand::array tags;
			SIMDJSON_TRY(status["entities"]["hashtags"].get_array().get(tags));
			size_t hashtags;
			SIMDJSON_TRY(tags.count_elements().get(hashtags));
			q->a++;
			q->b += followers;
			q->c += hashtags;
		}
	}
	else if (strcmp(kind, "citm_catalog") == 0)
	{
		for (auto performance : doc["performances"])
		{
			uint64_t id;
			SIMDJSON_TRY(performance["id"].get_uint64().get(id));
			q->a++;
			q->b += id;
		}
	}
	else
	{
		for (auto feature : doc["features"])
			for (auto ring : feature["geometry"]["coordinates"])
				for (auto pair : ring)
				{
					ondemand::array xy;
					SIMDJSON_TRY(pair.get_array().get(xy));
					double x;
					SIMDJSON_TRY(xy.at(0).get_double().get(x));
					q->a++;
					q->b += num_bits(x);
				}
	}
	return SUCCESS;
}

static void query_op(void *)
{
	query_t q;
	auto e = run_query(&in.docs[0], &q);
	if (e)
		fail(e);
	result = q;
}

int main(int argc, char **argv)
{
	if (argc < 4)
		return usage("simdjson", "dom|ondemand|query");
	std::string mode = argv[1];
	in = read_inputs(argv[2]);
	int n = atoi(argv[3]);
	if (mode == "dom")
	{
		check_t c = {};
		exact = true;
		for (int i = 0; i < in.count; i++)
			walk(dom_parse(&in.docs[i]), &c);
		exact = false;
		print_check(&c);
		print_result(measure(dom_op, nullptr, n), in.total);
	}
	else if (mode == "ondemand")
	{
		check_t c = {};
		exact = true;
		for (int i = 0; i < in.count; i++)
			od_parse(&in.docs[i], &c);
		exact = false;
		print_check(&c);
		print_result(measure(od_op, nullptr, n), in.total);
	}
	else if (mode == "query")
	{
		kind = input_kind(argv[2]);
		if (!kind)
			return 3;
		query_op(nullptr);
		if (strcmp(kind, "twitter") == 0)
			printf("check: %llu %llu %llu\n", (unsigned long long)result.a, (unsigned long long)result.b,
				(unsigned long long)result.c);
		else if (strcmp(kind, "citm_catalog") == 0)
			printf("check: %llu %llu\n", (unsigned long long)result.a, (unsigned long long)result.b);
		else
			printf("check: %llu %016llx\n", (unsigned long long)result.a, (unsigned long long)result.b);
		fflush(stdout);
		print_result(measure(query_op, nullptr, n), in.total);
	}
	else
		return usage("simdjson", "dom|ondemand|query");
	return 0;
}
