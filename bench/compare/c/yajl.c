// YAJL benchmark: yajl <tree|stream> <input> <min-samples>
//   tree   - yajl_tree_parse of each (NUL-terminated) document into yajl_val nodes, then
//            yajl_tree_free. Numbers keep their text plus an int64 and a double (strtod) where valid;
//            subnormal doubles are flagged invalid (strtod's ERANGE), so the check reads their text.
//   stream - YAJL's callback (SAX) parser: yajl_alloc, yajl_parse over the whole buffer,
//            yajl_complete_parse, yajl_free per document. Callbacks count containers, keys and
//            literals, add up key and string lengths (decoded by YAJL), and convert numbers with
//            strtod from the yajl_number callback (YAJL's yajl_integer callback rejects integers
//            beyond int64 as an overflow, so the raw-number callback is the way to read any integer).
// The check line (see ../reference.py) comes from one untimed pass (code points counted exactly; the
// timed passes add byte lengths).
#include <yajl/yajl_parse.h>
#include <yajl/yajl_tree.h>
#include "bench.h"

static inputs_t in;
static bool exact;

static long len(const char *s, size_t n)
{
	return exact ? utf8_chars(s, n) : (long)n;
}

// ---- tree ----

static void walk(yajl_val v, check_t *c)
{
	switch (v->type)
	{
	case yajl_t_object:
		c->objects++;
		for (size_t i = 0; i < v->u.object.len; i++)
		{
			c->keys++;
			c->chars += utf8_chars(v->u.object.keys[i], strlen(v->u.object.keys[i]));
			walk(v->u.object.values[i], c);
		}
		break;
	case yajl_t_array:
		c->arrays++;
		for (size_t i = 0; i < v->u.array.len; i++)
			walk(v->u.array.values[i], c);
		break;
	case yajl_t_string:
		c->strings++;
		c->chars += utf8_chars(v->u.string, strlen(v->u.string));
		break;
	case yajl_t_number:
		c->numbers++;
		// A double strtod reports as out of range (a subnormal) is flagged as neither double nor
		// integer; then the raw text is all there is
		c->numsum += num_bits(YAJL_IS_DOUBLE(v) ? v->u.number.d
			: YAJL_IS_INTEGER(v) ? (double)v->u.number.i : strtod(v->u.number.r, NULL));
		break;
	case yajl_t_true:
		c->trues++;
		break;
	case yajl_t_false:
		c->falses++;
		break;
	case yajl_t_null:
		c->nulls++;
		break;
	default:
		break;
	}
}

static yajl_val tree_parse(doc_t *d)
{
	char err[256];
	yajl_val root = yajl_tree_parse(d->data, err, sizeof err);
	if (!root)
	{
		fprintf(stderr, "parse error: %s\n", err);
		exit(1);
	}
	return root;
}

static void tree_op(void *unused)
{
	(void)unused;
	for (int i = 0; i < in.count; i++)
		yajl_tree_free(tree_parse(&in.docs[i]));
}

// ---- stream ----

static int on_null(void *ctx)
{
	((check_t *)ctx)->nulls++;
	return 1;
}

static int on_bool(void *ctx, int b)
{
	if (b)
		((check_t *)ctx)->trues++;
	else
		((check_t *)ctx)->falses++;
	return 1;
}

static int on_number(void *ctx, const char *s, size_t n)
{
	char buf[512];
	if (n >= sizeof buf)
		return 0;
	memcpy(buf, s, n);
	buf[n] = 0;
	check_t *c = (check_t *)ctx;
	c->numbers++;
	c->numsum += num_bits(strtod(buf, NULL));
	return 1;
}

static int on_string(void *ctx, const unsigned char *s, size_t n)
{
	check_t *c = (check_t *)ctx;
	c->strings++;
	c->chars += len((const char *)s, n);
	return 1;
}

static int on_key(void *ctx, const unsigned char *s, size_t n)
{
	check_t *c = (check_t *)ctx;
	c->keys++;
	c->chars += len((const char *)s, n);
	return 1;
}

static int on_start_map(void *ctx)
{
	((check_t *)ctx)->objects++;
	return 1;
}

static int on_start_array(void *ctx)
{
	((check_t *)ctx)->arrays++;
	return 1;
}

static int on_end(void *ctx)
{
	(void)ctx;
	return 1;
}

static const yajl_callbacks callbacks = {on_null, on_bool, NULL, NULL, on_number, on_string,
	on_start_map, on_key, on_end, on_start_array, on_end};

static void stream_parse(doc_t *d, check_t *c)
{
	yajl_handle h = yajl_alloc(&callbacks, NULL, c);
	if (yajl_parse(h, (const unsigned char *)d->data, d->size) != yajl_status_ok ||
		yajl_complete_parse(h) != yajl_status_ok)
	{
		unsigned char *msg = yajl_get_error(h, 0, NULL, 0);
		fprintf(stderr, "parse error: %s\n", msg);
		exit(1);
	}
	yajl_free(h);
}

static check_t sink;

static void stream_op(void *unused)
{
	(void)unused;
	check_t c = {0};
	for (int i = 0; i < in.count; i++)
		stream_parse(&in.docs[i], &c);
	sink = c;
}

int main(int argc, char **argv)
{
	if (argc < 4)
		return usage("yajl", "tree|stream");
	bool tree = strcmp(argv[1], "tree") == 0;
	if (!tree && strcmp(argv[1], "stream") != 0)
		return usage("yajl", "tree|stream");
	in = read_inputs(argv[2]);
	check_t c = {0};
	exact = true;
	for (int i = 0; i < in.count; i++)
	{
		if (tree)
		{
			yajl_val root = tree_parse(&in.docs[i]);
			walk(root, &c);
			yajl_tree_free(root);
		}
		else
			stream_parse(&in.docs[i], &c);
	}
	exact = false;
	print_check(&c);
	print_result(measure(tree ? tree_op : stream_op, NULL, atoi(argv[3])), in.total);
	return 0;
}
