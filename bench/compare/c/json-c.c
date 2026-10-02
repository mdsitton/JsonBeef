// json-c benchmark: json-c dom <input> <min-samples>
//   dom - json_tokener_parse_ex of each document (one tokener, reset per document, default depth
//         limit 32) into json-c's reference-counted objects, then json_object_put. Integers are
//         int64, or uint64 above INT64_MAX (json-c 0.14+). Note: with json-c 0.19 the heap grows by
//         about three times the input size per parse even though json_object_put reports the root
//         freed (the same with a fresh tokener per document), so its peak RSS grows with the number
//         of runs; not investigated further.
// The check line (see ../reference.py) walks the tree once before timing.
#include <json-c/json.h>
#include <stdint.h>
#include "bench.h"

static inputs_t in;
static json_tokener *tok;

static void walk(struct json_object *v, check_t *c)
{
	switch (json_object_get_type(v))
	{
	case json_type_object:
	{
		c->objects++;
		json_object_object_foreach(v, key, x)
		{
			c->keys++;
			c->chars += utf8_chars(key, strlen(key));
			walk(x, c);
		}
		break;
	}
	case json_type_array:
	{
		c->arrays++;
		size_t n = json_object_array_length(v);
		for (size_t i = 0; i < n; i++)
			walk(json_object_array_get_idx(v, i), c);
		break;
	}
	case json_type_string:
		c->strings++;
		c->chars += utf8_chars(json_object_get_string(v), json_object_get_string_len(v));
		break;
	case json_type_int:
	{
		c->numbers++;
		int64_t i = json_object_get_int64(v);
		c->numsum += num_bits(i == INT64_MAX ? (double)json_object_get_uint64(v) : (double)i);
		break;
	}
	case json_type_double:
		c->numbers++;
		c->numsum += num_bits(json_object_get_double(v));
		break;
	case json_type_boolean:
		if (json_object_get_boolean(v))
			c->trues++;
		else
			c->falses++;
		break;
	case json_type_null:
		c->nulls++;
		break;
	}
}

static struct json_object *parse(doc_t *d)
{
	json_tokener_reset(tok);
	struct json_object *root = json_tokener_parse_ex(tok, d->data, (int)d->size);
	enum json_tokener_error err = json_tokener_get_error(tok);
	if (err != json_tokener_success)
	{
		fprintf(stderr, "parse error: %s at %zu\n", json_tokener_error_desc(err), json_tokener_get_parse_end(tok));
		exit(1);
	}
	return root;
}

static void op(void *unused)
{
	(void)unused;
	for (int i = 0; i < in.count; i++)
		json_object_put(parse(&in.docs[i]));
}

int main(int argc, char **argv)
{
	if (argc < 4 || strcmp(argv[1], "dom") != 0)
		return usage("json-c", "dom");
	in = read_inputs(argv[2]);
	tok = json_tokener_new();
	check_t c = {0};
	for (int i = 0; i < in.count; i++)
	{
		struct json_object *root = parse(&in.docs[i]);
		walk(root, &c);
		json_object_put(root);
	}
	print_check(&c);
	print_result(measure(op, NULL, atoi(argv[3])), in.total);
	return 0;
}
