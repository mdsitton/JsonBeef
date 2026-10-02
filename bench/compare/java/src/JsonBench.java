// Java JSON benchmark: jsonbench <variant> <input> <min-samples>
// DOM (parse into the library's generic tree, then drop it):
//   jackson-tree      - Jackson 3 ObjectMapper.readTree(byte[]) into JsonNode (default settings: floats
//                       as DoubleNode, integers as Int/Long/BigIntegerNode).
//   fastjson2-object  - fastjson2 JSON.parse(byte[]) into JSONObject/JSONArray (floats as BigDecimal,
//                       its default).
//   gson-tree         - Gson JsonParser.parseReader over an InputStreamReader of the bytes, into
//                       JsonElement (numbers kept as LazilyParsedNumber text until read).
//   dsljson-object    - DSL-JSON DslJson.deserialize(Object.class, bytes, length) into Map/List/
//                       String/Long/Double (its ObjectConverter; no generated code involved).
// Typed (the classes in Schema.java, mirroring serde-rs/json-benchmark; see ../reference.py):
//   jackson-typed, fastjson2-typed, gson-typed - each library's reflection/default binding over public
//                       fields; dsljson-typed - DSL-JSON with the converters its annotation processor
//                       (CompiledJsonAnnotationProcessor, run by javac -proc:full) generates for the
//                       @CompiledJson classes, loaded through the ServiceLoader.
// Streaming (one pass over every token, no tree: every key and string read as a String, every number
//   converted to double):
//   jackson-stream    - Jackson JsonParser.nextToken loop over the bytes.
//   gson-stream       - Gson JsonReader (peek/next*) over an InputStreamReader of the bytes.
//   fastjson2-stream  - fastjson2 JSONReader pull API (nextIfObjectStart, readFieldName, readNumber...).
// Query (selective extraction, see ../reference.py): fastjson2-path - JSONPath.extract(JSONReader)
//   per path, which skips what the path does not select (extract support checked at start-up; exits 3
//   otherwise).
// An input is a file, or a .ndjson batch split into one byte[] per line before timing. Prints the check
// line (see ../reference.py) first. Timings follow the shared rule (see measure); the 1 s warm-up also
// lets the JIT compile the parser. Exits 1 on a parse error, 3 for typed/query on other inputs.
import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONReader;
import com.dslplatform.json.DslJson;
import com.dslplatform.json.runtime.Settings;
import com.google.gson.JsonElement;
import com.google.gson.JsonParser;
import com.google.gson.stream.JsonReader;
import com.google.gson.stream.JsonToken;
import java.io.ByteArrayInputStream;
import java.io.InputStreamReader;
import java.math.BigDecimal;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import tools.jackson.core.JsonParser.NumberType;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.json.JsonMapper;

public class JsonBench {
	interface Op {
		void run() throws Exception;
	}

	/** Warm up for at least 1 s, then time single runs until at least minSamples were taken and at
	 * least 60% lie within ±10% of their median, or 10 s / 1000 samples have passed. */
	static double[] measure(int minSamples, Op op) throws Exception {
		long warm = System.nanoTime();
		do
			op.run();
		while (System.nanoTime() - warm < 1_000_000_000L);
		long start = System.nanoTime();
		List<Double> samples = new ArrayList<>();
		while (true) {
			long t0 = System.nanoTime();
			op.run();
			samples.add((double) (System.nanoTime() - t0));
			List<Double> sorted = new ArrayList<>(samples);
			Collections.sort(sorted);
			int n = sorted.size();
			double median = n % 2 == 1 ? sorted.get(n / 2) : (sorted.get(n / 2 - 1) + sorted.get(n / 2)) / 2;
			if (n >= minSamples) {
				int within = 0;
				for (double s : samples)
					if (s >= median * 0.9 && s <= median * 1.1)
						within++;
				if (within >= 0.6 * n)
					return new double[] {median, n, 1};
			}
			if (n >= 1000 || System.nanoTime() - start >= 10_000_000_000L)
				return new double[] {median, n, 0};
		}
	}

	/** The DOM/stream check (see ../reference.py) */
	static final class Check {
		long objects, arrays, keys, strings, numbers, trues, falses, nulls, chars, numsum;

		void str(String s, boolean exact) {
			chars += exact ? s.codePointCount(0, s.length()) : s.length();
		}

		void num(double d) {
			numbers++;
			numsum += Double.doubleToRawLongBits(d + 0.0);
		}

		String line() {
			return String.format("check: %d %d %d %d %d %d %d %d %d %016x", objects, arrays, keys, strings, numbers,
				trues, falses, nulls, chars, numsum);
		}
	}

	/** A Number as the nearest double (BigInteger/BigDecimal round correctly) */
	static double toDouble(Number n) {
		if (n instanceof Integer || n instanceof Long || n instanceof Short || n instanceof Byte)
			return (double) n.longValue();
		return n.doubleValue();
	}

	static final ObjectMapper JACKSON = JsonMapper.builder().build();
	static DslJson<Object> dsl;

	static DslJson<Object> dsl() {
		if (dsl == null)
			dsl = new DslJson<>(Settings.withRuntime().includeServiceLoader());
		return dsl;
	}

	// ---- DOM walks (check only) ----

	static void walkJackson(JsonNode n, Check c) {
		switch (n.getNodeType()) {
			case OBJECT -> {
				c.objects++;
				for (Map.Entry<String, JsonNode> e : n.properties()) {
					c.keys++;
					c.str(e.getKey(), true);
					walkJackson(e.getValue(), c);
				}
			}
			case ARRAY -> {
				c.arrays++;
				for (JsonNode x : n.values())
					walkJackson(x, c);
			}
			case STRING -> {
				c.strings++;
				c.str(n.stringValue(), true);
			}
			case NUMBER -> c.num(n.doubleValue());
			case BOOLEAN -> {
				if (n.booleanValue()) c.trues++;
				else c.falses++;
			}
			case NULL -> c.nulls++;
			default -> throw new IllegalStateException("unexpected node " + n.getNodeType());
		}
	}

	/** fastjson2 and DSL-JSON trees: Map, List, String, Number, Boolean, null */
	@SuppressWarnings("unchecked")
	static void walkObject(Object v, Check c) {
		if (v instanceof Map<?, ?> m) {
			c.objects++;
			for (Map.Entry<String, Object> e : ((Map<String, Object>) m).entrySet()) {
				c.keys++;
				c.str(e.getKey(), true);
				walkObject(e.getValue(), c);
			}
		} else if (v instanceof List<?> l) {
			c.arrays++;
			for (Object x : l)
				walkObject(x, c);
		} else if (v instanceof String s) {
			c.strings++;
			c.str(s, true);
		} else if (v instanceof Number n) {
			c.num(toDouble(n));
		} else if (v instanceof Boolean b) {
			if (b) c.trues++;
			else c.falses++;
		} else if (v == null) {
			c.nulls++;
		} else
			throw new IllegalStateException("unexpected value " + v.getClass());
	}

	static void walkGson(JsonElement e, Check c) {
		if (e.isJsonObject()) {
			c.objects++;
			for (Map.Entry<String, JsonElement> m : e.getAsJsonObject().entrySet()) {
				c.keys++;
				c.str(m.getKey(), true);
				walkGson(m.getValue(), c);
			}
		} else if (e.isJsonArray()) {
			c.arrays++;
			for (JsonElement x : e.getAsJsonArray())
				walkGson(x, c);
		} else if (e.isJsonNull()) {
			c.nulls++;
		} else {
			var p = e.getAsJsonPrimitive();
			if (p.isString()) {
				c.strings++;
				c.str(p.getAsString(), true);
			} else if (p.isBoolean()) {
				if (p.getAsBoolean()) c.trues++;
				else c.falses++;
			} else
				c.num(p.getAsDouble());
		}
	}

	// ---- Streaming passes (also the check, with exact = true) ----

	static void jacksonStream(byte[] d, Check c, boolean exact) {
		try (tools.jackson.core.JsonParser p = JACKSON.createParser(d)) {
			tools.jackson.core.JsonToken t;
			while ((t = p.nextToken()) != null) {
				switch (t) {
					case START_OBJECT -> c.objects++;
					case START_ARRAY -> c.arrays++;
					case PROPERTY_NAME -> {
						c.keys++;
						c.str(p.currentName(), exact);
					}
					case VALUE_STRING -> {
						c.strings++;
						c.str(p.getString(), exact);
					}
					case VALUE_NUMBER_INT, VALUE_NUMBER_FLOAT -> c.num(p.getDoubleValue());
					case VALUE_TRUE -> c.trues++;
					case VALUE_FALSE -> c.falses++;
					case VALUE_NULL -> c.nulls++;
					default -> {
					}
				}
			}
		}
	}

	static void gsonStream(byte[] d, Check c, boolean exact) throws Exception {
		try (JsonReader r = new JsonReader(new InputStreamReader(new ByteArrayInputStream(d), StandardCharsets.UTF_8))) {
			int depth = 0;
			do {
				JsonToken t = r.peek();
				switch (t) {
					case BEGIN_OBJECT -> {
						r.beginObject();
						c.objects++;
						depth++;
					}
					case END_OBJECT -> {
						r.endObject();
						depth--;
					}
					case BEGIN_ARRAY -> {
						r.beginArray();
						c.arrays++;
						depth++;
					}
					case END_ARRAY -> {
						r.endArray();
						depth--;
					}
					case NAME -> {
						c.keys++;
						c.str(r.nextName(), exact);
					}
					case STRING -> {
						c.strings++;
						c.str(r.nextString(), exact);
					}
					case NUMBER -> c.num(r.nextDouble());
					case BOOLEAN -> {
						if (r.nextBoolean()) c.trues++;
						else c.falses++;
					}
					case NULL -> {
						r.nextNull();
						c.nulls++;
					}
					default -> throw new IllegalStateException("unexpected " + t);
				}
			} while (depth > 0);
			if (r.peek() != JsonToken.END_DOCUMENT)
				throw new IllegalStateException("trailing data");
		}
	}

	static void fastjsonValue(JSONReader r, Check c, boolean exact) {
		if (r.nextIfObjectStart()) {
			c.objects++;
			while (!r.nextIfObjectEnd()) {
				c.keys++;
				c.str(r.readFieldName(), exact);
				fastjsonValue(r, c, exact);
			}
		} else if (r.nextIfArrayStart()) {
			c.arrays++;
			while (!r.nextIfArrayEnd())
				fastjsonValue(r, c, exact);
		} else if (r.isString()) {
			c.strings++;
			c.str(r.readString(), exact);
		} else if (r.isNumber()) {
			c.num(toDouble(r.readNumber()));
		} else if (r.nextIfNull()) {
			c.nulls++;
		} else if (r.readBoolValue()) {
			c.trues++;
		} else
			c.falses++;
	}

	static void fastjsonStream(byte[] d, Check c, boolean exact) {
		try (JSONReader r = JSONReader.of(d)) {
			fastjsonValue(r, c, exact);
			if (!r.isEnd())
				throw new IllegalStateException("trailing data");
		}
	}

	interface Stream {
		void pass(byte[] d, Check c, boolean exact) throws Exception;
	}

	interface Dom {
		Object parse(byte[] d) throws Exception;
	}

	static List<byte[]> readInputs(String path) throws Exception {
		byte[] all = Files.readAllBytes(Path.of(path));
		List<byte[]> docs = new ArrayList<>();
		if (!path.endsWith(".ndjson")) {
			docs.add(all);
			return docs;
		}
		int start = 0;
		for (int i = 0; i <= all.length; i++) {
			if (i == all.length || all[i] == '\n') {
				if (i > start)
					docs.add(java.util.Arrays.copyOfRange(all, start, i));
				start = i + 1;
			}
		}
		return docs;
	}

	static String kind(String path) {
		String base = Path.of(path).getFileName().toString();
		return switch (base) {
			case "twitter.json" -> "twitter";
			case "citm_catalog.json" -> "citm_catalog";
			case "canada.json" -> "canada";
			default -> null;
		};
	}

	static Object sink;

	public static void main(String[] args) throws Exception {
		if (args.length < 3) {
			System.err.println("usage: jsonbench <variant> <input> <min-samples>");
			System.exit(2);
		}
		String variant = args[0];
		List<byte[]> docs = readInputs(args[1]);
		long total = Files.size(Path.of(args[1]));
		int minSamples = Integer.parseInt(args[2]);
		Op op;
		try {
			op = switch (variant) {
				case "jackson-tree", "fastjson2-object", "gson-tree", "dsljson-object" -> dom(variant, docs);
				case "jackson-stream", "gson-stream", "fastjson2-stream" -> stream(variant, docs);
				case "jackson-typed", "fastjson2-typed", "gson-typed", "dsljson-typed" -> {
					String k = kind(args[1]);
					if (k == null) System.exit(3);
					yield Typed.op(variant, k, docs.get(0));
				}
				case "fastjson2-path" -> {
					String k = kind(args[1]);
					if (k == null) System.exit(3);
					yield Query.op(k, docs.get(0));
				}
				default -> {
					System.err.println("unknown variant " + variant);
					System.exit(2);
					yield null;
				}
			};
		} catch (Exception | StackOverflowError e) {
			System.err.println("parse error: " + e);
			System.exit(1);
			return;
		}
		System.out.flush();
		double[] m = measure(minSamples, op);
		double ms = m[0] / 1e6;
		System.out.printf("%.3f ms/op %.1f MB/s (n=%d, %s)%n", ms, total / 1048576.0 / (ms / 1000.0), (int) m[1],
			m[2] == 1 ? "converged" : "capped");
	}

	static Op dom(String variant, List<byte[]> docs) throws Exception {
		Dom parse = switch (variant) {
			case "jackson-tree" -> JACKSON::readTree;
			case "fastjson2-object" -> JSON::parse;
			case "gson-tree" -> d -> JsonParser.parseReader(new InputStreamReader(new ByteArrayInputStream(d), StandardCharsets.UTF_8));
			default -> d -> dsl().deserialize(Object.class, d, d.length);
		};
		Check c = new Check();
		for (byte[] d : docs) {
			Object tree = parse.parse(d);
			if (tree instanceof JsonNode n) walkJackson(n, c);
			else if (tree instanceof JsonElement e) walkGson(e, c);
			else walkObject(tree, c);
		}
		System.out.println(c.line());
		return () -> {
			for (byte[] d : docs)
				sink = parse.parse(d);
		};
	}

	static Op stream(String variant, List<byte[]> docs) throws Exception {
		Stream pass = switch (variant) {
			case "jackson-stream" -> JsonBench::jacksonStream;
			case "gson-stream" -> JsonBench::gsonStream;
			default -> JsonBench::fastjsonStream;
		};
		Check c = new Check();
		for (byte[] d : docs)
			pass.pass(d, c, true);
		System.out.println(c.line());
		return () -> {
			Check t = new Check();
			for (byte[] d : docs)
				pass.pass(d, t, false);
			sink = t;
		};
	}
}
