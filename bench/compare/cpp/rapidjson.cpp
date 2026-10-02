// RapidJSON benchmark: rapidjson <dom|insitu|sax|dom-full|sax-full> <input> <min-samples>
//   dom      - Document::Parse(str, length) of each document (default flags) into a fresh Document
//              (its MemoryPoolAllocator), destroyed after each document. Strings are copied.
//   insitu   - Document::ParseInsitu: strings are decoded in place, so each run first copies the
//              document into a reused buffer (the copy is timed: the source must survive the run).
//   sax      - streaming track: Reader::Parse with a handler that counts containers, keys and literals,
//              adds up key and string lengths (decoded by RapidJSON) and adds every number's bits
//              (Int/Uint/Int64/Uint64 converted to double, Double as given).
//   dom-full, sax-full - the same with kParseFullPrecisionFlag: RapidJSON's default float conversion
//              is fast but not always correctly rounded (it can be 1 ulp off), which these columns
//              show.
// The check line (see ../reference.py) comes from one untimed pass (code points counted exactly; the
// timed passes add byte lengths).
#include <rapidjson/document.h>
#include <rapidjson/error/en.h>
#include <rapidjson/reader.h>
#include <string>
#include <vector>
extern "C" {
#include "../c/bench.h"
}

using namespace rapidjson;

static inputs_t in;
static bool exact;

static long len(const char *s, size_t n)
{
	return exact ? utf8_chars(s, n) : (long)n;
}

static void walk(const Value &v, check_t *c)
{
	switch (v.GetType())
	{
	case kObjectType:
		c->objects++;
		for (auto &m : v.GetObject())
		{
			c->keys++;
			c->chars += len(m.name.GetString(), m.name.GetStringLength());
			walk(m.value, c);
		}
		break;
	case kArrayType:
		c->arrays++;
		for (auto &x : v.GetArray())
			walk(x, c);
		break;
	case kStringType:
		c->strings++;
		c->chars += len(v.GetString(), v.GetStringLength());
		break;
	case kNumberType:
		c->numbers++;
		c->numsum += num_bits(v.IsUint64() ? (double)v.GetUint64() : v.IsInt64() ? (double)v.GetInt64() : v.GetDouble());
		break;
	case kTrueType:
		c->trues++;
		break;
	case kFalseType:
		c->falses++;
		break;
	case kNullType:
		c->nulls++;
		break;
	}
}

static void fail(ParseErrorCode code, size_t offset)
{
	fprintf(stderr, "parse error: %s at %zu\n", GetParseError_En(code), offset);
	exit(1);
}

template <unsigned Flags>
static void dom_parse(doc_t *d, check_t *c)
{
	Document doc;
	doc.Parse<Flags>(d->data, d->size);
	if (doc.HasParseError())
		fail(doc.GetParseError(), doc.GetErrorOffset());
	if (c)
		walk(doc, c);
}

static std::vector<char> scratch;

static void insitu_parse(doc_t *d, check_t *c)
{
	memcpy(scratch.data(), d->data, d->size + 1);
	Document doc;
	doc.ParseInsitu(scratch.data());
	if (doc.HasParseError())
		fail(doc.GetParseError(), doc.GetErrorOffset());
	if (c)
		walk(doc, c);
}

struct Handler : BaseReaderHandler<UTF8<>, Handler>
{
	check_t c = {};
	bool Null() { c.nulls++; return true; }
	bool Bool(bool b) { (b ? c.trues : c.falses)++; return true; }
	bool Int(int i) { return Num((double)i); }
	bool Uint(unsigned u) { return Num((double)u); }
	bool Int64(int64_t i) { return Num((double)i); }
	bool Uint64(uint64_t u) { return Num((double)u); }
	bool Double(double d) { return Num(d); }
	bool Num(double d) { c.numbers++; c.numsum += num_bits(d); return true; }
	bool String(const char *s, SizeType n, bool) { c.strings++; c.chars += len(s, n); return true; }
	bool Key(const char *s, SizeType n, bool) { c.keys++; c.chars += len(s, n); return true; }
	bool StartObject() { c.objects++; return true; }
	bool EndObject(SizeType) { return true; }
	bool StartArray() { c.arrays++; return true; }
	bool EndArray(SizeType) { return true; }
};

template <unsigned Flags>
static void sax_parse(doc_t *d, check_t *c)
{
	Reader reader;
	Handler h;
	MemoryStream ms(d->data, d->size);
	ParseResult r = reader.Parse<Flags>(ms, h);
	if (!r)
		fail(r.Code(), r.Offset());
	check_add(c, &h.c);
}

typedef void (*parse_fn)(doc_t *, check_t *);
static parse_fn parse;
static bool streaming; // the SAX modes tally in the timed runs too; the DOM modes only parse
static check_t sink;

static void op(void *)
{
	check_t c = {};
	for (int i = 0; i < in.count; i++)
		parse(&in.docs[i], streaming ? &c : nullptr);
	sink = c;
}

int main(int argc, char **argv)
{
	if (argc < 4)
		return usage("rapidjson", "dom|insitu|sax|dom-full|sax-full");
	std::string mode = argv[1];
	if (mode == "dom")
		parse = dom_parse<kParseDefaultFlags>;
	else if (mode == "dom-full")
		parse = dom_parse<kParseFullPrecisionFlag>;
	else if (mode == "insitu")
		parse = insitu_parse;
	else if (mode == "sax")
		parse = sax_parse<kParseDefaultFlags>;
	else if (mode == "sax-full")
		parse = sax_parse<kParseFullPrecisionFlag>;
	else
		return usage("rapidjson", "dom|insitu|sax|dom-full|sax-full");
	streaming = mode.rfind("sax", 0) == 0;
	in = read_inputs(argv[2]);
	size_t largest = 0;
	for (int i = 0; i < in.count; i++)
		largest = std::max(largest, in.docs[i].size);
	scratch.resize(largest + 1);
	check_t c = {};
	exact = true;
	for (int i = 0; i < in.count; i++)
		parse(&in.docs[i], &c);
	exact = false;
	print_check(&c);
	print_result(measure(op, nullptr, atoi(argv[3])), in.total);
	return 0;
}
