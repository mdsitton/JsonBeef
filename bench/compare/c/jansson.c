// Jansson benchmark: jansson dom <input> <min-samples>
//   dom - json_loadb of each document (flags 0) into Jansson's reference-counted values, then
//         json_decref. Integers are json_int_t (long long): Jansson rejects integers above
//         INT64_MAX ("too big integer").
// The check line (see ../reference.py) walks the tree once before timing.
#include <jansson.h>
#include "bench.h"

static inputs_t in;

static void walk(json_t *v, check_t *c)
{
	switch (json_typeof(v))
	{
	case JSON_OBJECT:
	{
		c->objects++;
		const char *key;
		json_t *x;
		void *it;
		for (it = json_object_iter(v); it; it = json_object_iter_next(v, it))
		{
			key = json_object_iter_key(it);
			x = json_object_iter_value(it);
			c->keys++;
			c->chars += utf8_chars(key, json_object_iter_key_len(it));
			walk(x, c);
		}
		break;
	}
	case JSON_ARRAY:
	{
		c->arrays++;
		size_t i;
		json_t *x;
		json_array_foreach(v, i, x) walk(x, c);
		break;
	}
	case JSON_STRING:
		c->strings++;
		c->chars += utf8_chars(json_string_value(v), json_string_length(v));
		break;
	case JSON_INTEGER:
		c->numbers++;
		c->numsum += num_bits((double)json_integer_value(v));
		break;
	case JSON_REAL:
		c->numbers++;
		c->numsum += num_bits(json_real_value(v));
		break;
	case JSON_TRUE:
		c->trues++;
		break;
	case JSON_FALSE:
		c->falses++;
		break;
	case JSON_NULL:
		c->nulls++;
		break;
	}
}

static json_t *parse(doc_t *d)
{
	json_error_t err;
	json_t *root = json_loadb(d->data, d->size, 0, &err);
	if (!root)
	{
		fprintf(stderr, "parse error: %s at line %d column %d\n", err.text, err.line, err.column);
		exit(1);
	}
	return root;
}

static void op(void *unused)
{
	(void)unused;
	for (int i = 0; i < in.count; i++)
		json_decref(parse(&in.docs[i]));
}

int main(int argc, char **argv)
{
	if (argc < 4 || strcmp(argv[1], "dom") != 0)
		return usage("jansson", "dom");
	in = read_inputs(argv[2]);
	check_t c = {0};
	for (int i = 0; i < in.count; i++)
	{
		json_t *root = parse(&in.docs[i]);
		walk(root, &c);
		json_decref(root);
	}
	print_check(&c);
	print_result(measure(op, NULL, atoi(argv[3])), in.total);
	return 0;
}
