// nlohmann/json benchmark: nlohmann <dom|sax> <input> <min-samples>
//   dom - nlohmann::json::parse(begin, end) of each document into a json value (std::map objects,
//         int64/uint64/double numbers), destroyed after each document.
//   sax - streaming track: nlohmann::json::sax_parse with a json_sax handler that counts containers,
//         keys and literals, adds up key and string lengths and every number's bits.
// The check line (see ../reference.py) comes from one untimed pass (code points counted exactly; the
// timed passes add byte lengths).
#include <nlohmann/json.hpp>
#include <string>
extern "C" {
#include "../c/bench.h"
}

using json = nlohmann::json;

static inputs_t in;
static bool exact;

static long len(const std::string &s)
{
	return exact ? utf8_chars(s.data(), s.size()) : (long)s.size();
}

static void walk(const json &v, check_t *c)
{
	switch (v.type())
	{
	case json::value_t::object:
		c->objects++;
		for (auto &[key, x] : v.items())
		{
			c->keys++;
			c->chars += len(key);
			walk(x, c);
		}
		break;
	case json::value_t::array:
		c->arrays++;
		for (auto &x : v)
			walk(x, c);
		break;
	case json::value_t::string:
		c->strings++;
		c->chars += len(v.get_ref<const std::string &>());
		break;
	case json::value_t::number_integer:
		c->numbers++;
		c->numsum += num_bits((double)v.get<int64_t>());
		break;
	case json::value_t::number_unsigned:
		c->numbers++;
		c->numsum += num_bits((double)v.get<uint64_t>());
		break;
	case json::value_t::number_float:
		c->numbers++;
		c->numsum += num_bits(v.get<double>());
		break;
	case json::value_t::boolean:
		(v.get<bool>() ? c->trues : c->falses)++;
		break;
	case json::value_t::null:
		c->nulls++;
		break;
	default:
		break;
	}
}

struct Handler : nlohmann::json_sax<json>
{
	check_t c = {};
	bool null() override { c.nulls++; return true; }
	bool boolean(bool b) override { (b ? c.trues : c.falses)++; return true; }
	bool number_integer(number_integer_t i) override { return num((double)i); }
	bool number_unsigned(number_unsigned_t u) override { return num((double)u); }
	bool number_float(number_float_t d, const string_t &) override { return num(d); }
	bool num(double d) { c.numbers++; c.numsum += num_bits(d); return true; }
	bool string(string_t &s) override { c.strings++; c.chars += len(s); return true; }
	bool binary(binary_t &) override { return true; }
	bool start_object(std::size_t) override { c.objects++; return true; }
	bool key(string_t &s) override { c.keys++; c.chars += len(s); return true; }
	bool end_object() override { return true; }
	bool start_array(std::size_t) override { c.arrays++; return true; }
	bool end_array() override { return true; }
	bool parse_error(std::size_t position, const std::string &, const nlohmann::detail::exception &e) override
	{
		fprintf(stderr, "parse error at %zu: %s\n", position, e.what());
		exit(1);
	}
};

static bool sax;
static check_t sink;

static void parse(doc_t *d, check_t *c)
{
	if (sax)
	{
		Handler h;
		json::sax_parse(d->data, d->data + d->size, &h);
		check_add(c, &h.c);
		return;
	}
	try
	{
		json root = json::parse(d->data, d->data + d->size);
		if (c)
			walk(root, c);
	}
	catch (const json::parse_error &e)
	{
		fprintf(stderr, "parse error: %s\n", e.what());
		exit(1);
	}
}

static void op(void *)
{
	check_t c = {};
	for (int i = 0; i < in.count; i++)
		parse(&in.docs[i], sax ? &c : nullptr);
	sink = c;
}

int main(int argc, char **argv)
{
	if (argc < 4)
		return usage("nlohmann", "dom|sax");
	std::string mode = argv[1];
	if (mode != "dom" && mode != "sax")
		return usage("nlohmann", "dom|sax");
	sax = mode == "sax";
	in = read_inputs(argv[2]);
	check_t c = {};
	exact = true;
	for (int i = 0; i < in.count; i++)
		parse(&in.docs[i], &c);
	exact = false;
	print_check(&c);
	print_result(measure(op, nullptr, atoi(argv[3])), in.total);
	return 0;
}
