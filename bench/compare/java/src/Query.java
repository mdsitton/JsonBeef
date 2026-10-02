// The query track (see JsonBench.java and ../reference.py): fastjson2's JSONPath.extract(JSONReader),
// one compiled path per extracted value list, each a pass over the bytes that skips what the path does
// not select. Paths whose implementation would read the whole document into a tree first (fastjson2's
// extractSupport flag) are refused with exit 3, so this never emulates the query with a full DOM.
// fastjson2's [*] flattens nested arrays, and a trailing [0] after [*][*] picks each ring's first pair,
// so the canada path selects the pairs (small JSONArrays) and the harness reads each pair's first value.
import com.alibaba.fastjson2.JSONPath;
import com.alibaba.fastjson2.JSONReader;
import java.util.List;

final class Query {
	static JSONPath path(String p) {
		JSONPath path = JSONPath.of(p);
		try {
			var f = path.getClass().getDeclaredField("extractSupport");
			f.setAccessible(true);
			if (!f.getBoolean(path)) {
				System.err.println(p + ": fastjson2 would read the whole document into a tree (no extract support)");
				System.exit(3);
			}
		} catch (NoSuchFieldException e) {
			// single-segment paths always extract from the reader
		} catch (ReflectiveOperationException | RuntimeException e) {
			System.err.println("cannot inspect " + path.getClass() + ": " + e);
			System.exit(3);
		}
		return path;
	}

	static List<?> list(JSONPath path, byte[] d) {
		try (JSONReader r = JSONReader.of(d)) {
			Object v = path.extract(r);
			return v instanceof List<?> l ? l : List.of();
		}
	}

	static JsonBench.Op op(String kind, byte[] data) {
		JsonBench.Op op;
		switch (kind) {
			case "twitter" -> {
				JSONPath followers = path("$.statuses[*].user.followers_count");
				JSONPath hashtags = path("$.statuses[*].entities.hashtags[*]");
				op = () -> {
					List<?> f = list(followers, data);
					long sum = 0, tags = 0;
					for (Object x : f) sum += ((Number) x).longValue();
					tags = list(hashtags, data).size();
					JsonBench.sink = "check: " + f.size() + " " + sum + " " + tags;
				};
			}
			case "citm_catalog" -> {
				JSONPath ids = path("$.performances[*].id");
				op = () -> {
					List<?> l = list(ids, data);
					long sum = 0;
					for (Object x : l) sum += ((Number) x).longValue();
					JsonBench.sink = "check: " + l.size() + " " + sum;
				};
			}
			default -> {
				JSONPath lon = path("$.features[*].geometry.coordinates[*][*]");
				op = () -> {
					List<?> l = list(lon, data);
					long sum = 0;
					for (Object x : l) sum += Double.doubleToRawLongBits(JsonBench.toDouble((Number) ((List<?>) x).get(0)) + 0.0);
					JsonBench.sink = String.format("check: %d %016x", l.size(), sum);
				};
			}
		}
		try {
			op.run();
		} catch (Exception e) {
			throw new RuntimeException(e);
		}
		System.out.println(JsonBench.sink);
		return op;
	}
}
