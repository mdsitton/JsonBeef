// Go JSON benchmark: go-jsonbench <variant> <input> <min-samples>
//
// DOM (untyped: Unmarshal into an `any`, objects as map[string]any, arrays as []any, numbers as
// float64, each library's default):
//
//	json-any       encoding/json Unmarshal (the standard library)
//	jsonv2-any     encoding/json/v2 Unmarshal (in the standard library since Go 1.27 without
//	               GOEXPERIMENT; v2's defaults: invalid UTF-8 and duplicate names rejected)
//	sonic-any      github.com/bytedance/sonic Unmarshal (ConfigDefault; JIT + SIMD on amd64)
//	gojson-any     github.com/goccy/go-json Unmarshal
//	jsoniter-any   github.com/json-iterator/go Unmarshal (jsoniter.ConfigDefault)
//	segmentio-any  github.com/segmentio/encoding/json Unmarshal
//
// Typed (the structures in typed.go, through their encoding/json tags):
//
//	json-typed, jsonv2-typed, sonic-typed, gojson-typed, jsoniter-typed, segmentio-typed
//
// Streaming (one pass over every token, no tree; every key and string decoded, every number
// converted to float64 and its bits added):
//
//	json-token     encoding/json Decoder.Token over a bytes.Reader
//	jsontext       encoding/json/jsontext Decoder.ReadToken over a bytes.Reader
//	jsoniter-iter  jsoniter.Iterator (ConfigDefault), recursing with WhatIsNext and the callback
//	               readers (ReadObjectCB, ReadArrayCB), ReadString and ReadFloat64
//
// On-demand / selective (the queries in ../reference.py):
//
//	gjson          github.com/tidwall/gjson GetBytes with paths (statuses.#.user.followers_count and
//	               the like), then ForEach over the arrays it returns
//	jsonparser     github.com/buger/jsonparser ArrayEach and Get/GetInt/GetFloat
//	sonic-get      sonic.Get (ast.Node, parsed lazily as it is walked): Get by key, ForEach over arrays
//	json-partial   encoding/json Unmarshal into structures holding only the queried fields (the rest is
//	               skipped by the decoder)
//
// An input is a .json file or a .ndjson batch (split into lines before timing, one run parses each
// line once). Typed and query variants handle twitter.json, citm_catalog.json and canada.json and exit
// 3 (n/a) on other inputs. Prints the check line (see ../reference.py) first. Timings follow the
// shared rule (see measure and ../run.sh).
package main

import (
	"bytes"
	stdjson "encoding/json"
	"encoding/json/jsontext"
	jsonv2 "encoding/json/v2"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/buger/jsonparser"
	"github.com/bytedance/sonic"
	"github.com/bytedance/sonic/ast"
	gojson "github.com/goccy/go-json"
	jsoniter "github.com/json-iterator/go"
	segjson "github.com/segmentio/encoding/json"
	"github.com/tidwall/gjson"
)

// measure warms up for at least 1 s (at least one run), then times single runs until at least
// minSamples were taken and at least 60% lie within ±10% of their median ("converged"), or 10 s of
// measuring or 1000 samples have passed. Returns the median sample in ns.
// (From XmlBeef's bench/compare/go/main.go.)
func measure(minSamples int, op func()) (median float64, n int, converged bool) {
	warm := time.Now()
	for {
		op()
		if time.Since(warm) >= time.Second {
			break
		}
	}
	start := time.Now()
	var samples []float64
	for {
		t0 := time.Now()
		op()
		samples = append(samples, float64(time.Since(t0).Nanoseconds()))
		sorted := append([]float64(nil), samples...)
		sort.Float64s(sorted)
		n = len(sorted)
		if n%2 == 1 {
			median = sorted[n/2]
		} else {
			median = (sorted[n/2-1] + sorted[n/2]) / 2
		}
		if n >= minSamples {
			within := 0
			for _, s := range samples {
				if s >= median*0.9 && s <= median*1.1 {
					within++
				}
			}
			if float64(within) >= 0.6*float64(n) {
				return median, n, true
			}
		}
		if n >= 1000 || time.Since(start) >= 10*time.Second {
			return median, n, false
		}
	}
}

// numBits is the bit pattern of a float64, -0 counted as +0
func numBits(f float64) uint64 { return math.Float64bits(f + 0.0) }

// check: objects arrays keys strings numbers true false null chars numsum (see ../reference.py)
type check struct {
	objects, arrays, keys, strings, numbers, trues, falses, nulls, chars int
	numsum                                                               uint64
}

func (c *check) line() string {
	return fmt.Sprintf("check: %d %d %d %d %d %d %d %d %d %016x", c.objects, c.arrays, c.keys, c.strings,
		c.numbers, c.trues, c.falses, c.nulls, c.chars, c.numsum)
}

// length in code points when checking, in bytes when timing (the timed runs only need to touch it)
func strLen(s string, exact bool) int {
	if exact {
		return utf8.RuneCountInString(s)
	}
	return len(s)
}

func (c *check) walk(v any) {
	switch t := v.(type) {
	case map[string]any:
		c.objects++
		for k, x := range t {
			c.keys++
			c.chars += utf8.RuneCountInString(k)
			c.walk(x)
		}
	case []any:
		c.arrays++
		for _, x := range t {
			c.walk(x)
		}
	case string:
		c.strings++
		c.chars += utf8.RuneCountInString(t)
	case float64:
		c.numbers++
		c.numsum += numBits(t)
	case bool:
		if t {
			c.trues++
		} else {
			c.falses++
		}
	case nil:
		c.nulls++
	default:
		fail(fmt.Errorf("unexpected value type %T", v))
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "error:", err)
	os.Exit(1)
}

// ---- Streaming ----

// The token-stream state shared by json-token and jsontext: whether the next string is a key
type frame struct{ object, key bool }

type tokenState struct{ stack []frame }

// value records that a value (scalar or container start) was read, and whether a string just read
// was a key
func (s *tokenState) isKey() bool {
	n := len(s.stack)
	return n > 0 && s.stack[n-1].object && s.stack[n-1].key
}

func (s *tokenState) afterValue() {
	n := len(s.stack)
	if n > 0 && s.stack[n-1].object {
		s.stack[n-1].key = true
	}
}

func (s *tokenState) afterKey() { s.stack[len(s.stack)-1].key = false }

func (s *tokenState) push(object bool) { s.stack = append(s.stack, frame{object, true}) }

func (s *tokenState) pop() {
	s.stack = s.stack[:len(s.stack)-1]
	s.afterValue()
}

func streamJSONToken(data []byte, c *check, exact bool) error {
	dec := stdjson.NewDecoder(bytes.NewReader(data))
	var st tokenState
	for {
		tok, err := dec.Token()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		switch t := tok.(type) {
		case stdjson.Delim:
			switch t {
			case '{':
				c.objects++
				st.push(true)
			case '[':
				c.arrays++
				st.push(false)
			default:
				st.pop()
			}
		case string:
			c.chars += strLen(t, exact)
			if st.isKey() {
				c.keys++
				st.afterKey()
			} else {
				c.strings++
				st.afterValue()
			}
		case float64:
			c.numbers++
			c.numsum += numBits(t)
			st.afterValue()
		case bool:
			if t {
				c.trues++
			} else {
				c.falses++
			}
			st.afterValue()
		case nil:
			c.nulls++
			st.afterValue()
		}
	}
}

func streamJSONText(data []byte, c *check, exact bool) error {
	dec := jsontext.NewDecoder(bytes.NewReader(data))
	var st tokenState
	for {
		tok, err := dec.ReadToken()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		switch tok.Kind() {
		case '{':
			c.objects++
			st.push(true)
		case '[':
			c.arrays++
			st.push(false)
		case '}', ']':
			st.pop()
		case '"':
			c.chars += strLen(tok.String(), exact)
			if st.isKey() {
				c.keys++
				st.afterKey()
			} else {
				c.strings++
				st.afterValue()
			}
		case '0':
			c.numbers++
			f, err := tok.Float()
			if err != nil {
				return err
			}
			c.numsum += numBits(f)
			st.afterValue()
		case 't':
			c.trues++
			st.afterValue()
		case 'f':
			c.falses++
			st.afterValue()
		case 'n':
			c.nulls++
			st.afterValue()
		}
	}
}

func iterValue(it *jsoniter.Iterator, c *check, exact bool) {
	switch it.WhatIsNext() {
	case jsoniter.ObjectValue:
		c.objects++
		it.ReadObjectCB(func(it *jsoniter.Iterator, key string) bool {
			c.keys++
			c.chars += strLen(key, exact)
			iterValue(it, c, exact)
			return true
		})
	case jsoniter.ArrayValue:
		c.arrays++
		it.ReadArrayCB(func(it *jsoniter.Iterator) bool {
			iterValue(it, c, exact)
			return true
		})
	case jsoniter.StringValue:
		c.strings++
		c.chars += strLen(it.ReadString(), exact)
	case jsoniter.NumberValue:
		c.numbers++
		c.numsum += numBits(it.ReadFloat64())
	case jsoniter.BoolValue:
		if it.ReadBool() {
			c.trues++
		} else {
			c.falses++
		}
	case jsoniter.NilValue:
		it.ReadNil()
		c.nulls++
	default:
		it.ReportError("WhatIsNext", "invalid value")
	}
}

func streamJsoniter(it *jsoniter.Iterator, data []byte, c *check, exact bool) error {
	it.ResetBytes(data)
	iterValue(it, c, exact)
	if it.Error != nil && it.Error != io.EOF {
		return it.Error
	}
	return nil
}

// ---- Queries (see ../reference.py) ----

func queryGjson(data []byte, kind string) string {
	switch kind {
	case "twitter":
		var followers, hashtags int64
		statuses := gjson.GetBytes(data, "statuses")
		count := 0
		statuses.ForEach(func(_, s gjson.Result) bool {
			count++
			followers += s.Get("user.followers_count").Int()
			hashtags += s.Get("entities.hashtags.#").Int()
			return true
		})
		return fmt.Sprintf("check: %d %d %d", count, followers, hashtags)
	case "citm_catalog":
		var count, ids int64
		gjson.GetBytes(data, "performances").ForEach(func(_, p gjson.Result) bool {
			count++
			ids += p.Get("id").Int()
			return true
		})
		return fmt.Sprintf("check: %d %d", count, ids)
	default:
		var pairs int
		var sum uint64
		gjson.GetBytes(data, "features").ForEach(func(_, f gjson.Result) bool {
			f.Get("geometry.coordinates").ForEach(func(_, ring gjson.Result) bool {
				ring.ForEach(func(_, pair gjson.Result) bool {
					pairs++
					sum += numBits(pair.Get("0").Float())
					return true
				})
				return true
			})
			return true
		})
		return fmt.Sprintf("check: %d %016x", pairs, sum)
	}
}

func queryJsonparser(data []byte, kind string) (string, error) {
	var err error
	keep := func(e error) {
		if e != nil && err == nil {
			err = e
		}
	}
	switch kind {
	case "twitter":
		var count, followers, hashtags int64
		_, e := jsonparser.ArrayEach(data, func(s []byte, _ jsonparser.ValueType, _ int, e error) {
			keep(e)
			count++
			f, e := jsonparser.GetInt(s, "user", "followers_count")
			keep(e)
			followers += f
			_, e = jsonparser.ArrayEach(s, func([]byte, jsonparser.ValueType, int, error) { hashtags++ }, "entities", "hashtags")
			keep(e)
		}, "statuses")
		keep(e)
		return fmt.Sprintf("check: %d %d %d", count, followers, hashtags), err
	case "citm_catalog":
		var count, ids int64
		_, e := jsonparser.ArrayEach(data, func(p []byte, _ jsonparser.ValueType, _ int, e error) {
			keep(e)
			count++
			id, e := jsonparser.GetInt(p, "id")
			keep(e)
			ids += id
		}, "performances")
		keep(e)
		return fmt.Sprintf("check: %d %d", count, ids), err
	default:
		var pairs int
		var sum uint64
		_, e := jsonparser.ArrayEach(data, func(f []byte, _ jsonparser.ValueType, _ int, e error) {
			keep(e)
			_, e = jsonparser.ArrayEach(f, func(ring []byte, _ jsonparser.ValueType, _ int, e error) {
				keep(e)
				_, e = jsonparser.ArrayEach(ring, func(pair []byte, _ jsonparser.ValueType, _ int, e error) {
					keep(e)
					pairs++
					x, e := jsonparser.GetFloat(pair, "[0]")
					keep(e)
					sum += numBits(x)
				})
				keep(e)
			}, "geometry", "coordinates")
			keep(e)
		}, "features")
		keep(e)
		return fmt.Sprintf("check: %d %016x", pairs, sum), err
	}
}

func querySonic(data []byte, kind string) (string, error) {
	root, err := sonic.Get(data)
	if err != nil {
		return "", err
	}
	var ferr error
	keep := func(e error) {
		if e != nil && ferr == nil {
			ferr = e
		}
	}
	switch kind {
	case "twitter":
		var count, followers, hashtags int64
		keep(root.Get("statuses").ForEach(func(_ ast.Sequence, s *ast.Node) bool {
			count++
			f, e := s.GetByPath("user", "followers_count").Int64()
			keep(e)
			followers += f
			// Len is 0 on a node not loaded yet, so the hashtags are counted by walking them
			keep(s.GetByPath("entities", "hashtags").ForEach(func(ast.Sequence, *ast.Node) bool {
				hashtags++
				return true
			}))
			return true
		}))
		return fmt.Sprintf("check: %d %d %d", count, followers, hashtags), ferr
	case "citm_catalog":
		var count, ids int64
		keep(root.Get("performances").ForEach(func(_ ast.Sequence, p *ast.Node) bool {
			count++
			id, e := p.Get("id").Int64()
			keep(e)
			ids += id
			return true
		}))
		return fmt.Sprintf("check: %d %d", count, ids), ferr
	default:
		var pairs int
		var sum uint64
		keep(root.Get("features").ForEach(func(_ ast.Sequence, f *ast.Node) bool {
			keep(f.GetByPath("geometry", "coordinates").ForEach(func(_ ast.Sequence, ring *ast.Node) bool {
				keep(ring.ForEach(func(_ ast.Sequence, pair *ast.Node) bool {
					pairs++
					x, e := pair.Index(0).Float64()
					keep(e)
					sum += numBits(x)
					return true
				}))
				return true
			}))
			return true
		}))
		return fmt.Sprintf("check: %d %016x", pairs, sum), ferr
	}
}

func queryPartial(data []byte, kind string) (string, error) {
	switch kind {
	case "twitter":
		var t partialTwitter
		if err := stdjson.Unmarshal(data, &t); err != nil {
			return "", err
		}
		var followers, hashtags int64
		for _, s := range t.Statuses {
			followers += s.User.FollowersCount
			hashtags += int64(len(s.Entities.Hashtags))
		}
		return fmt.Sprintf("check: %d %d %d", len(t.Statuses), followers, hashtags), nil
	case "citm_catalog":
		var t partialCitm
		if err := stdjson.Unmarshal(data, &t); err != nil {
			return "", err
		}
		var ids int64
		for _, p := range t.Performances {
			ids += p.ID
		}
		return fmt.Sprintf("check: %d %d", len(t.Performances), ids), nil
	default:
		var t partialCanada
		if err := stdjson.Unmarshal(data, &t); err != nil {
			return "", err
		}
		var pairs int
		var sum uint64
		for _, f := range t.Features {
			for _, r := range f.Geometry.Coordinates {
				for _, p := range r {
					pairs++
					sum += numBits(p[0])
				}
			}
		}
		return fmt.Sprintf("check: %d %016x", pairs, sum), nil
	}
}

// ---- Inputs ----

// The input's documents: the file, or each non-empty line of a .ndjson file
func readInput(path string) ([][]byte, int) {
	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	if !strings.HasSuffix(path, ".ndjson") {
		return [][]byte{data}, len(data)
	}
	var docs [][]byte
	for _, line := range bytes.Split(data, []byte("\n")) {
		if len(line) > 0 {
			docs = append(docs, append([]byte(nil), line...))
		}
	}
	return docs, len(data)
}

func inputKind(path string) string {
	switch filepath.Base(path) {
	case "twitter.json":
		return "twitter"
	case "citm_catalog.json":
		return "citm_catalog"
	case "canada.json":
		return "canada"
	}
	return ""
}

type unmarshal func([]byte, any) error

var unmarshalers = map[string]unmarshal{
	"json":      stdjson.Unmarshal,
	"jsonv2":    func(b []byte, v any) error { return jsonv2.Unmarshal(b, v) },
	"sonic":     sonic.Unmarshal,
	"gojson":    gojson.Unmarshal,
	"jsoniter":  jsoniter.ConfigDefault.Unmarshal,
	"segmentio": segjson.Unmarshal,
}

func main() {
	if len(os.Args) < 4 {
		fmt.Fprintln(os.Stderr, "usage: go-jsonbench <variant> <input> <min-samples>")
		os.Exit(2)
	}
	variant, path := os.Args[1], os.Args[2]
	minSamples, err := strconv.Atoi(os.Args[3])
	if err != nil {
		os.Exit(2)
	}
	docs, total := readInput(path)
	kind := inputKind(path)
	var op func()

	switch {
	case strings.HasSuffix(variant, "-any"):
		u, ok := unmarshalers[strings.TrimSuffix(variant, "-any")]
		if !ok {
			os.Exit(2)
		}
		var c check
		for _, d := range docs {
			var v any
			if err := u(d, &v); err != nil {
				fail(err)
			}
			c.walk(v)
		}
		fmt.Println(c.line())
		op = func() {
			for _, d := range docs {
				var v any
				if err := u(d, &v); err != nil {
					fail(err)
				}
			}
		}
	case strings.HasSuffix(variant, "-typed"):
		u, ok := unmarshalers[strings.TrimSuffix(variant, "-typed")]
		if !ok {
			os.Exit(2)
		}
		if kind == "" {
			os.Exit(3)
		}
		v := newTyped(kind)
		if err := u(docs[0], v); err != nil {
			fail(err)
		}
		fmt.Println(typedCheck(v))
		op = func() {
			if err := u(docs[0], newTyped(kind)); err != nil {
				fail(err)
			}
		}
	case variant == "json-token" || variant == "jsontext" || variant == "jsoniter-iter":
		var stream func([]byte, *check, bool) error
		switch variant {
		case "json-token":
			stream = streamJSONToken
		case "jsontext":
			stream = streamJSONText
		default:
			it := jsoniter.ConfigDefault.BorrowIterator(nil)
			stream = func(d []byte, c *check, exact bool) error { return streamJsoniter(it, d, c, exact) }
		}
		var c check
		for _, d := range docs {
			if err := stream(d, &c, true); err != nil {
				fail(err)
			}
		}
		fmt.Println(c.line())
		op = func() {
			var c check
			for _, d := range docs {
				if err := stream(d, &c, false); err != nil {
					fail(err)
				}
			}
		}
	case variant == "gjson" || variant == "jsonparser" || variant == "sonic-get" || variant == "json-partial":
		if kind == "" {
			os.Exit(3)
		}
		var query func([]byte, string) (string, error)
		switch variant {
		case "gjson":
			query = func(d []byte, k string) (string, error) {
				if !gjson.ValidBytes(d) {
					return "", errors.New("invalid JSON")
				}
				return queryGjson(d, k), nil
			}
		case "jsonparser":
			query = queryJsonparser
		case "sonic-get":
			query = querySonic
		default:
			query = queryPartial
		}
		line, err := query(docs[0], kind)
		if err != nil {
			fail(err)
		}
		fmt.Println(line)
		// gjson's timed runs skip the validity check above: gjson.GetBytes does not validate
		if variant == "gjson" {
			op = func() { _ = queryGjson(docs[0], kind) }
		} else {
			op = func() {
				if _, err := query(docs[0], kind); err != nil {
					fail(err)
				}
			}
		}
	default:
		fmt.Fprintln(os.Stderr, "unknown variant", variant)
		os.Exit(2)
	}

	median, n, converged := measure(minSamples, op)
	ms := median / 1e6
	state := "capped"
	if converged {
		state = "converged"
	}
	fmt.Printf("%.3f ms/op %.1f MB/s (n=%d, %s)\n", ms, float64(total)/1048576.0/(ms/1000.0), n, state)
}
