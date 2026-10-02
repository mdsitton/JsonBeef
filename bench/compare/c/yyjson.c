// yyjson benchmark: yyjson dom <input> <min-samples>
//   dom - yyjson_read_opts (default flags: RFC 8259, no extensions) of each document into its immutable
//         document, then yyjson_doc_free. yyjson has no streaming reader (its incremental reader still
//         builds the document), so it appears in the DOM track only.
// The check line (see ../reference.py) walks the document once before timing. Integers are kept as
// uint64/int64 and converted to double for the check.
#include <yyjson.h>
#include "bench.h"

static inputs_t in;

static void walk(yyjson_val *v, check_t *c)
{
	switch (yyjson_get_type(v))
	{
	case YYJSON_TYPE_OBJ:
	{
		c->objects++;
		yyjson_obj_iter it = yyjson_obj_iter_with(v);
		yyjson_val *key;
		while ((key = yyjson_obj_iter_next(&it)))
		{
			c->keys++;
			c->chars += utf8_chars(yyjson_get_str(key), yyjson_get_len(key));
			walk(yyjson_obj_iter_get_val(key), c);
		}
		break;
	}
	case YYJSON_TYPE_ARR:
	{
		c->arrays++;
		yyjson_arr_iter it = yyjson_arr_iter_with(v);
		yyjson_val *x;
		while ((x = yyjson_arr_iter_next(&it)))
			walk(x, c);
		break;
	}
	case YYJSON_TYPE_STR:
		c->strings++;
		c->chars += utf8_chars(yyjson_get_str(v), yyjson_get_len(v));
		break;
	case YYJSON_TYPE_NUM:
		c->numbers++;
		c->numsum += num_bits(yyjson_get_num(v));
		break;
	case YYJSON_TYPE_BOOL:
		if (yyjson_get_bool(v))
			c->trues++;
		else
			c->falses++;
		break;
	case YYJSON_TYPE_NULL:
		c->nulls++;
		break;
	default:
		break;
	}
}

static yyjson_doc *parse(doc_t *d)
{
	yyjson_read_err err;
	yyjson_doc *doc = yyjson_read_opts(d->data, d->size, 0, NULL, &err);
	if (!doc)
	{
		fprintf(stderr, "parse error: %s at %zu\n", err.msg, err.pos);
		exit(1);
	}
	return doc;
}

static void op(void *unused)
{
	(void)unused;
	for (int i = 0; i < in.count; i++)
		yyjson_doc_free(parse(&in.docs[i]));
}

int main(int argc, char **argv)
{
	if (argc < 4 || strcmp(argv[1], "dom") != 0)
		return usage("yyjson", "dom");
	in = read_inputs(argv[2]);
	check_t c = {0};
	for (int i = 0; i < in.count; i++)
	{
		yyjson_doc *doc = parse(&in.docs[i]);
		walk(yyjson_doc_get_root(doc), &c);
		yyjson_doc_free(doc);
	}
	print_check(&c);
	print_result(measure(op, NULL, atoi(argv[3])), in.total);
	return 0;
}
