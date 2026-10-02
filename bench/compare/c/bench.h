// Shared measurement, input handling and check line for the C and C++ harnesses. Every harness in
// bench/compare follows the same rule (see run.sh):
//   warm up for at least 1 s (at least one run), then time single runs until at least `min_samples`
//   were taken and at least 60% of them lie within ±10% of their median ("converged"), or 10 s of
//   measuring or 1000 samples have passed ("capped"). The median sample is reported.
// An input is one JSON file, or a batch (a .ndjson file): one document per line, split before timing,
// each line its own buffer; one run parses every document once. MB/s is over the file's size.
// (Measurement from XmlBeef's bench/compare/c/bench.h.)
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define BENCH_WARMUP_NS 1e9
#define BENCH_MAX_NS 10e9
#define BENCH_MAX_SAMPLES 1000
#define BENCH_WINDOW 0.10
#define BENCH_MAJORITY 0.6
// Zero bytes after every document (simdjson reads up to 64 bytes past the end)
#define BENCH_PADDING 64

static double bench_now_ns(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1e9 + ts.tv_nsec;
}

static int bench_cmp(const void *a, const void *b)
{
	double x = *(const double *)a, y = *(const double *)b;
	return (x > y) - (x < y);
}

typedef struct
{
	double median_ns;
	int samples;
	bool converged;
} measurement_t;

typedef void (*bench_op)(void *ctx);

static measurement_t measure(bench_op op, void *ctx, int min_samples)
{
	double warm = bench_now_ns();
	do
		op(ctx);
	while (bench_now_ns() - warm < BENCH_WARMUP_NS);

	static double samples[BENCH_MAX_SAMPLES], sorted[BENCH_MAX_SAMPLES];
	measurement_t m = {0};
	double start = bench_now_ns();
	int n = 0;
	while (n < BENCH_MAX_SAMPLES)
	{
		double t0 = bench_now_ns();
		op(ctx);
		samples[n++] = bench_now_ns() - t0;
		memcpy(sorted, samples, sizeof(double) * n);
		qsort(sorted, n, sizeof(double), bench_cmp);
		double median = (n % 2) ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
		m.median_ns = median;
		m.samples = n;
		if (n >= min_samples)
		{
			int within = 0;
			for (int i = 0; i < n; i++)
				within += samples[i] >= median * (1 - BENCH_WINDOW) && samples[i] <= median * (1 + BENCH_WINDOW);
			if (within >= BENCH_MAJORITY * n)
			{
				m.converged = true;
				break;
			}
		}
		if (bench_now_ns() - start >= BENCH_MAX_NS)
			break;
	}
	return m;
}

// Result line: "<ms> ms/op <MB/s> MB/s (n=<samples>, converged|capped)"
static void print_result(measurement_t m, long bytes)
{
	double ms = m.median_ns / 1e6;
	printf("%.3f ms/op %.1f MB/s (n=%d, %s)\n", ms, bytes / 1048576.0 / (ms / 1000.0), m.samples,
		m.converged ? "converged" : "capped");
	fflush(stdout);
}

// ---- Inputs ----

typedef struct
{
	char *data; // NUL-terminated, followed by BENCH_PADDING zero bytes
	size_t size;
} doc_t;

typedef struct
{
	doc_t *docs;
	int count;
	long total; // the file's size
	char *file; // the whole file, NUL-terminated and padded
} inputs_t;

static bool ends_with(const char *s, const char *suffix)
{
	size_t a = strlen(s), b = strlen(suffix);
	return a >= b && strcmp(s + a - b, suffix) == 0;
}

static char *copy_padded(const char *src, size_t len)
{
	char *p = (char *)calloc(1, len + 1 + BENCH_PADDING);
	memcpy(p, src, len);
	return p;
}

// The input's documents: the file, or each non-empty line of a .ndjson file
static inputs_t read_inputs(const char *path)
{
	inputs_t in = {0};
	FILE *f = fopen(path, "rb");
	if (!f)
	{
		fprintf(stderr, "cannot open %s\n", path);
		exit(2);
	}
	fseek(f, 0, SEEK_END);
	long size = ftell(f);
	fseek(f, 0, SEEK_SET);
	in.file = (char *)calloc(1, size + 1 + BENCH_PADDING);
	if (fread(in.file, 1, size, f) != (size_t)size)
		exit(2);
	fclose(f);
	in.total = size;
	int capacity = 16;
	in.docs = (doc_t *)malloc(sizeof(doc_t) * capacity);
	if (!ends_with(path, ".ndjson"))
	{
		in.docs[0].data = copy_padded(in.file, size);
		in.docs[0].size = size;
		in.count = 1;
		return in;
	}
	const char *p = in.file, *end = in.file + size;
	while (p < end)
	{
		const char *nl = (const char *)memchr(p, '\n', end - p);
		const char *stop = nl ? nl : end;
		if (stop > p)
		{
			if (in.count == capacity)
			{
				capacity *= 2;
				in.docs = (doc_t *)realloc(in.docs, sizeof(doc_t) * capacity);
			}
			in.docs[in.count].data = copy_padded(p, stop - p);
			in.docs[in.count].size = stop - p;
			in.count++;
		}
		p = stop + 1;
	}
	return in;
}

// "twitter", "citm_catalog" or "canada" for the typed and query modes (by file name), else NULL
static const char *input_kind(const char *path)
{
	const char *base = strrchr(path, '/');
	base = base ? base + 1 : path;
	static const char *kinds[] = {"twitter.json", "citm_catalog.json", "canada.json"};
	static const char *names[] = {"twitter", "citm_catalog", "canada"};
	for (int i = 0; i < 3; i++)
		if (strcmp(base, kinds[i]) == 0)
			return names[i];
	return NULL;
}

// ---- The check line (see ../reference.py) ----

// Unicode code points in UTF-8 text: every byte that is not a continuation byte
static long utf8_chars(const char *s, size_t len)
{
	long n = 0;
	for (size_t i = 0; i < len; i++)
		n += ((unsigned char)s[i] & 0xC0) != 0x80;
	return n;
}

// The bit pattern of a double, -0 counted as +0
static uint64_t num_bits(double d)
{
	d += 0.0;
	uint64_t u;
	memcpy(&u, &d, sizeof u);
	return u;
}

typedef struct
{
	long objects, arrays, keys, strings, numbers, trues, falses, nulls, chars;
	uint64_t numsum;
} check_t;

static void check_add(check_t *a, const check_t *b)
{
	a->objects += b->objects;
	a->arrays += b->arrays;
	a->keys += b->keys;
	a->strings += b->strings;
	a->numbers += b->numbers;
	a->trues += b->trues;
	a->falses += b->falses;
	a->nulls += b->nulls;
	a->chars += b->chars;
	a->numsum += b->numsum;
}

static void print_check(const check_t *c)
{
	printf("check: %ld %ld %ld %ld %ld %ld %ld %ld %ld %016llx\n", c->objects, c->arrays, c->keys, c->strings,
		c->numbers, c->trues, c->falses, c->nulls, c->chars, (unsigned long long)c->numsum);
	fflush(stdout);
}

static int usage(const char *name, const char *modes)
{
	fprintf(stderr, "usage: %s <%s> <input> <min-samples>\n", name, modes);
	return 2;
}
