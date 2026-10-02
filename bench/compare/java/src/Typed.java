// The typed track (see JsonBench.java and ../reference.py): the input decoded into Schema's classes by
// Jackson, fastjson2, Gson or DSL-JSON; the check line is computed from the decoded objects.
import com.alibaba.fastjson2.JSON;
import com.google.gson.Gson;
import java.io.ByteArrayInputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.List;

final class Typed {
	interface Decode {
		Object decode(byte[] d, Class<?> type) throws Exception;
	}

	static final Gson GSON = new Gson();

	static JsonBench.Op op(String variant, String kind, byte[] data) throws Exception {
		Class<?> type = switch (kind) {
			case "twitter" -> Schema.Twitter.class;
			case "citm_catalog" -> Schema.CitmCatalog.class;
			default -> Schema.Canada.class;
		};
		Decode decode = switch (variant) {
			case "jackson-typed" -> (d, t) -> JsonBench.JACKSON.readValue(d, t);
			case "fastjson2-typed" -> (d, t) -> JSON.parseObject(d, t);
			case "gson-typed" -> (d, t) -> GSON.fromJson(new InputStreamReader(new ByteArrayInputStream(d), StandardCharsets.UTF_8), t);
			default -> (d, t) -> {
				Object v = JsonBench.dsl().deserialize(t, d, d.length);
				if (v == null) throw new IllegalStateException("DSL-JSON returned null");
				return v;
			};
		};
		System.out.println(check(decode.decode(data, type)));
		return () -> JsonBench.sink = decode.decode(data, type);
	}

	static long chars(String s) {
		return s.codePointCount(0, s.length());
	}

	static String check(Object v) {
		if (v instanceof Schema.Twitter t) {
			long ids = 0, followers = 0, retweets = 0, hashtags = 0, text = 0, media = 0, descUrls = 0;
			for (Schema.Status s : t.statuses) {
				ids += s.id;
				followers += s.user.followers_count;
				if (s.retweeted_status != null) retweets++;
				hashtags += s.entities.hashtags.size();
				text += chars(s.text);
				if (s.entities.media != null) media += s.entities.media.size();
				descUrls += s.user.entities.description.urls.size();
			}
			return "check: " + t.statuses.size() + " " + Long.toUnsignedString(ids) + " " + followers + " " + retweets + " "
				+ hashtags + " " + text + " " + media + " " + descUrls;
		}
		if (v instanceof Schema.CitmCatalog c) {
			long eventIds = 0, names = 0, perfIds = 0, amounts = 0, areas = 0, subTopics = 0;
			for (Schema.Event e : c.events.values()) {
				eventIds += e.id;
				names += chars(e.name);
			}
			for (Schema.Performance p : c.performances) {
				perfIds += p.id;
				for (Schema.Price pr : p.prices) amounts += pr.amount;
				for (Schema.SeatCategory sc : p.seatCategories) areas += sc.areas.size();
			}
			for (List<Long> l : c.topicSubTopics.values()) subTopics += l.size();
			return "check: " + c.events.size() + " " + eventIds + " " + c.performances.size() + " " + perfIds + " " + amounts
				+ " " + areas + " " + names + " " + subTopics;
		}
		Schema.Canada c = (Schema.Canada) v;
		long rings = 0, points = 0, sum = 0, props = 0;
		for (Schema.Feature f : c.features) {
			for (List<double[]> ring : f.geometry.coordinates) {
				rings++;
				for (double[] p : ring) {
					points++;
					for (double x : p) sum += Double.doubleToRawLongBits(x + 0.0);
				}
			}
			for (String s : f.properties.values()) props += chars(s);
		}
		return String.format("check: %d %d %d %016x %d", c.features.size(), rings, points, sum, props);
	}
}
