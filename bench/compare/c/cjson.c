// cJSON benchmark: cjson dom <input> <min-samples>
//   dom - cJSON_ParseWithLength of each document into its linked tree, then cJSON_Delete. cJSON keeps
//         every number as a double (and an int copy), so integers beyond 2^53 are rounded on parse.
// The check line (see ../reference.py) walks the tree once before timing.
#include <cJSON.h>
#include "bench.h"

static inputs_t in;

static void walk(const cJSON *v, check_t *c)
{
	switch (v->type & 0xFF)
	{
	case cJSON_Object:
		c->objects++;
		for (const cJSON *x = v->child; x; x = x->next)
		{
			c->keys++;
			c->chars += utf8_chars(x->string, strlen(x->string));
			walk(x, c);
		}
		break;
	case cJSON_Array:
		c->arrays++;
		for (const cJSON *x = v->child; x; x = x->next)
			walk(x, c);
		break;
	case cJSON_String:
		c->strings++;
		c->chars += utf8_chars(v->valuestring, strlen(v->valuestring));
		break;
	case cJSON_Number:
		c->numbers++;
		c->numsum += num_bits(v->valuedouble);
		break;
	case cJSON_True:
		c->trues++;
		break;
	case cJSON_False:
		c->falses++;
		break;
	case cJSON_NULL:
		c->nulls++;
		break;
	}
}

static cJSON *parse(doc_t *d)
{
	cJSON *root = cJSON_ParseWithLength(d->data, d->size);
	if (!root)
	{
		const char *at = cJSON_GetErrorPtr();
		fprintf(stderr, "parse error at offset %ld\n", at ? (long)(at - d->data) : -1L);
		exit(1);
	}
	return root;
}

static void op(void *unused)
{
	(void)unused;
	for (int i = 0; i < in.count; i++)
		cJSON_Delete(parse(&in.docs[i]));
}

int main(int argc, char **argv)
{
	if (argc < 4 || strcmp(argv[1], "dom") != 0)
		return usage("cjson", "dom");
	in = read_inputs(argv[2]);
	check_t c = {0};
	for (int i = 0; i < in.count; i++)
	{
		cJSON *root = parse(&in.docs[i]);
		walk(root, &c);
		cJSON_Delete(root);
	}
	print_check(&c);
	print_result(measure(op, NULL, atoi(argv[3])), in.total);
	return 0;
}
