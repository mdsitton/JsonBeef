// C# JSON benchmark: JsonBench <variant> <input> <min-samples>
//   DOM (one run parses every document into the tree and drops it):
//     jsondocument      - System.Text.Json JsonDocument.Parse over the UTF-8 bytes (pooled buffers,
//                         disposed after each parse), default options (max depth 64).
//     jsonnode          - System.Text.Json JsonNode.Parse over the bytes. JsonNode.Parse keeps a
//                         JsonElement and creates the child nodes of an object or array only when they
//                         are first accessed, so the timed run also enumerates every container (no value
//                         is converted) to build the whole tree.
//     newtonsoft-jtoken - Newtonsoft.Json JToken.ReadFrom over a JsonTextReader over a StreamReader over
//                         a MemoryStream of the bytes (Newtonsoft reads text, not bytes: the UTF-8
//                         decoding is inside the timing). DateParseHandling.None: by default Newtonsoft
//                         turns date-like strings into DateTime values, which changes the strings.
//   Typed (twitter, citm_catalog, canada only; any other input exits 3, n/a; schema in Typed.cs):
//     stj-typed         - JsonSerializer.Deserialize over the bytes with a source-generated
//                         JsonSerializerContext (default options: case-sensitive exact names).
//     newtonsoft-typed  - JsonSerializer.Deserialize<T> over a JsonTextReader as above.
//   Streaming (one pass over every token, no tree):
//     utf8jsonreader    - System.Text.Json Utf8JsonReader over the bytes: every key and string unescaped
//                         with CopyString into a reused char buffer, every number read with GetDouble.
//     newtonsoft-reader - Newtonsoft.Json JsonTextReader (as above; it unescapes every string and parses
//                         every number itself: long, BigInteger beyond long, or double).
// Newtonsoft keeps integers beyond long as exact BigIntegers; .NET's BigInteger-to-double cast truncates
// (11,267 of the 22,657 such values in integers.json come out one ulp low), so the check converts them
// through their decimal text instead (see Check.ToDouble).
// No on-demand/selective variant: .NET has no such API (n/a). An input is one file, or a .ndjson batch:
// one document per line, split before timing. Prints the check line (see ../reference.py) first.
// Timings follow the shared rule (see Measure and ../run.sh); the 1 s warm-up also lets the JIT
// (tiered, with PGO) compile the parser.
using System.Diagnostics;
using System.Globalization;
using System.Numerics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

if (args.Length < 3)
{
	Console.Error.WriteLine("usage: JsonBench <jsondocument|jsonnode|newtonsoft-jtoken|stj-typed|newtonsoft-typed|utf8jsonreader|newtonsoft-reader> <input> <min-samples>");
	return 2;
}
string variant = args[0];
string path = args[1];
int minSamples = int.Parse(args[2]);
byte[] file = File.ReadAllBytes(path);
long total = file.Length;
var docs = new List<byte[]>();
if (path.EndsWith(".ndjson", StringComparison.Ordinal))
{
	int start = 0;
	for (int i = 0; i <= file.Length; i++)
	{
		if (i == file.Length || file[i] == (byte)'\n')
		{
			if (i > start)
				docs.Add(file[start..i]);
			start = i + 1;
		}
	}
}
else
	docs.Add(file);

string? kind = Path.GetFileName(path) switch
{
	"twitter.json" => "twitter",
	"citm_catalog.json" => "citm_catalog",
	"canada.json" => "canada",
	_ => null,
};

string checkLine;
Action op;
try
{
	switch (variant)
	{
		case "jsondocument":
		{
			var c = new Check();
			foreach (var d in docs)
			{
				using var doc = JsonDocument.Parse(d);
				c.Element(doc.RootElement);
			}
			checkLine = c.Line();
			op = () =>
			{
				foreach (var d in docs)
					JsonDocument.Parse(d).Dispose();
			};
			break;
		}
		case "jsonnode":
		{
			var c = new Check();
			foreach (var d in docs)
				c.Node(JsonNode.Parse(d));
			checkLine = c.Line();
			op = () =>
			{
				foreach (var d in docs)
				{
					var n = JsonNode.Parse(d);
					Materialize(n);
					GC.KeepAlive(n);
				}
			};
			break;
		}
		case "newtonsoft-jtoken":
		{
			var c = new Check();
			foreach (var d in docs)
				c.Token(ReadJToken(d));
			checkLine = c.Line();
			op = () =>
			{
				foreach (var d in docs)
					GC.KeepAlive(ReadJToken(d));
			};
			break;
		}
		case "stj-typed":
		case "newtonsoft-typed":
		{
			if (kind == null)
				return 3;
			bool stj = variant == "stj-typed";
			byte[] d = docs[0];
			string k = kind;
			checkLine = Typed.Check(k, stj ? Typed.FromStj(k, d) : Typed.FromNewtonsoft(k, d));
			op = stj ? () => GC.KeepAlive(Typed.FromStj(k, d)) : () => GC.KeepAlive(Typed.FromNewtonsoft(k, d));
			break;
		}
		case "utf8jsonreader":
		{
			var c = new Check();
			char[] buffer = new char[file.Length + 16];
			foreach (var d in docs)
				Utf8Pass(d, c, buffer, true);
			checkLine = c.Line();
			op = () =>
			{
				var t = new Check();
				foreach (var d in docs)
					Utf8Pass(d, t, buffer, false);
				GC.KeepAlive(t);
			};
			break;
		}
		case "newtonsoft-reader":
		{
			var c = new Check();
			foreach (var d in docs)
				NewtonsoftPass(d, c, true);
			checkLine = c.Line();
			op = () =>
			{
				var t = new Check();
				foreach (var d in docs)
					NewtonsoftPass(d, t, false);
				GC.KeepAlive(t);
			};
			break;
		}
		default:
			Console.Error.WriteLine($"unknown variant {variant}");
			return 2;
	}
}
catch (Exception e)
{
	Console.Error.WriteLine($"parse error: {e.GetType().Name}: {e.Message}");
	return 1;
}
Console.WriteLine(checkLine);
var result = Measure(minSamples, op);
double ms = result.MedianNs / 1e6;
Console.WriteLine($"{ms:F3} ms/op {total / 1048576.0 / (ms / 1000.0):F1} MB/s (n={result.Samples}, {(result.Converged ? "converged" : "capped")})");
return 0;

static JsonTextReader NewtonsoftReader(byte[] d) =>
	new(new StreamReader(new MemoryStream(d), Encoding.UTF8)) { DateParseHandling = DateParseHandling.None };

static JToken ReadJToken(byte[] d)
{
	using var reader = NewtonsoftReader(d);
	return JToken.ReadFrom(reader);
}

// Creates every child node of a lazily built JsonNode tree
static void Materialize(JsonNode? n)
{
	switch (n)
	{
		case JsonObject o:
			foreach (var kv in o)
				Materialize(kv.Value);
			break;
		case JsonArray a:
			foreach (var x in a)
				Materialize(x);
			break;
	}
}

static void Utf8Pass(byte[] d, Check c, char[] buffer, bool exact)
{
	var reader = new Utf8JsonReader(d);
	while (reader.Read())
	{
		switch (reader.TokenType)
		{
			case JsonTokenType.StartObject:
				c.Objects++;
				break;
			case JsonTokenType.StartArray:
				c.Arrays++;
				break;
			case JsonTokenType.PropertyName:
				c.Keys++;
				c.Chars += Check.Len(buffer.AsSpan(0, reader.CopyString(buffer)), exact);
				break;
			case JsonTokenType.String:
				c.Strings++;
				c.Chars += Check.Len(buffer.AsSpan(0, reader.CopyString(buffer)), exact);
				break;
			case JsonTokenType.Number:
				c.Number(reader.GetDouble());
				break;
			case JsonTokenType.True:
				c.Trues++;
				break;
			case JsonTokenType.False:
				c.Falses++;
				break;
			case JsonTokenType.Null:
				c.Nulls++;
				break;
		}
	}
}

static void NewtonsoftPass(byte[] d, Check c, bool exact)
{
	using var reader = NewtonsoftReader(d);
	while (reader.Read())
	{
		switch (reader.TokenType)
		{
			case JsonToken.StartObject:
				c.Objects++;
				break;
			case JsonToken.StartArray:
				c.Arrays++;
				break;
			case JsonToken.PropertyName:
				c.Keys++;
				c.Chars += Check.Len((string)reader.Value!, exact);
				break;
			case JsonToken.String:
				c.Strings++;
				c.Chars += Check.Len((string)reader.Value!, exact);
				break;
			case JsonToken.Integer:
			case JsonToken.Float:
				c.Number(Check.ToDouble(reader.Value!, exact));
				break;
			case JsonToken.Boolean:
				if ((bool)reader.Value!)
					c.Trues++;
				else
					c.Falses++;
				break;
			case JsonToken.Null:
				c.Nulls++;
				break;
		}
	}
}

// Warm up for at least 1 s (at least one run), then time single runs until at least minSamples were
// taken and at least 60% lie within ±10% of their median, or 10 s / 1000 samples have passed.
// (From XmlBeef's bench/compare/cs.)
static (double MedianNs, int Samples, bool Converged) Measure(int minSamples, Action op)
{
	var warm = Stopwatch.StartNew();
	do
		op();
	while (warm.Elapsed.TotalSeconds < 1);
	var start = Stopwatch.StartNew();
	var samples = new List<double>();
	while (true)
	{
		long t0 = Stopwatch.GetTimestamp();
		op();
		samples.Add(Stopwatch.GetElapsedTime(t0).TotalMilliseconds * 1e6);
		var sorted = samples.Order().ToList();
		int n = sorted.Count;
		double median = n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
		if (n >= minSamples && samples.Count(s => s >= median * 0.9 && s <= median * 1.1) >= 0.6 * n)
			return (median, n, true);
		if (n >= 1000 || start.Elapsed.TotalSeconds >= 10)
			return (median, n, false);
	}
}

/// <summary>The dom/stream check line (see ../reference.py)</summary>
sealed class Check
{
	public long Objects, Arrays, Keys, Strings, Numbers, Trues, Falses, Nulls, Chars;
	public ulong NumSum;

	public string Line() =>
		$"check: {Objects} {Arrays} {Keys} {Strings} {Numbers} {Trues} {Falses} {Nulls} {Chars} {NumSum:x16}";

	/// <summary>The bit pattern of a double, -0 counted as +0</summary>
	public static ulong Bits(double d) => (ulong)BitConverter.DoubleToInt64Bits(d + 0.0);

	public void Number(double d)
	{
		Numbers++;
		NumSum = unchecked(NumSum + Bits(d));
	}

	/// <summary>Length in code points when checking, in UTF-16 units when timing</summary>
	public static long Len(ReadOnlySpan<char> s, bool exact)
	{
		if (!exact)
			return s.Length;
		long n = 0;
		foreach (char ch in s)
			n += char.IsLowSurrogate(ch) ? 0 : 1;
		return n;
	}

	/// <summary>A Newtonsoft number (long, BigInteger beyond long, or double) as a double. .NET's
	/// BigInteger-to-double conversion truncates instead of rounding to nearest (so does (double)JValue,
	/// which uses it), so the check converts a BigInteger through its decimal text; the timed runs only
	/// touch the value and use the cheap cast.</summary>
	public static double ToDouble(object v, bool exact = true) => v switch
	{
		long l => l,
		BigInteger b => exact ? double.Parse(b.ToString(CultureInfo.InvariantCulture), CultureInfo.InvariantCulture) : (double)b,
		double d => d,
		decimal m => (double)m,
		_ => throw new InvalidDataException($"unexpected number type {v.GetType()}"),
	};

	public void Element(JsonElement e)
	{
		switch (e.ValueKind)
		{
			case JsonValueKind.Object:
				Objects++;
				foreach (var p in e.EnumerateObject())
				{
					Keys++;
					Chars += Len(p.Name, true);
					Element(p.Value);
				}
				break;
			case JsonValueKind.Array:
				Arrays++;
				foreach (var x in e.EnumerateArray())
					Element(x);
				break;
			case JsonValueKind.String:
				Strings++;
				Chars += Len(e.GetString()!, true);
				break;
			case JsonValueKind.Number:
				Number(e.GetDouble());
				break;
			case JsonValueKind.True:
				Trues++;
				break;
			case JsonValueKind.False:
				Falses++;
				break;
			case JsonValueKind.Null:
				Nulls++;
				break;
		}
	}

	public void Node(JsonNode? n)
	{
		switch (n)
		{
			case null:
				Nulls++;
				break;
			case JsonObject o:
				Objects++;
				foreach (var kv in o)
				{
					Keys++;
					Chars += Len(kv.Key, true);
					Node(kv.Value);
				}
				break;
			case JsonArray a:
				Arrays++;
				foreach (var x in a)
					Node(x);
				break;
			case JsonValue v:
				switch (v.GetValueKind())
				{
					case JsonValueKind.String:
						Strings++;
						Chars += Len(v.GetValue<string>(), true);
						break;
					case JsonValueKind.Number:
						Number(v.GetValue<double>());
						break;
					case JsonValueKind.True:
						Trues++;
						break;
					case JsonValueKind.False:
						Falses++;
						break;
					case JsonValueKind.Null:
						Nulls++;
						break;
				}
				break;
		}
	}

	public void Token(JToken t)
	{
		switch (t)
		{
			case JObject o:
				Objects++;
				foreach (var p in o.Properties())
				{
					Keys++;
					Chars += Len(p.Name, true);
					Token(p.Value);
				}
				break;
			case JArray a:
				Arrays++;
				foreach (var x in a)
					Token(x);
				break;
			case JValue v:
				switch (v.Type)
				{
					case JTokenType.String:
						Strings++;
						Chars += Len((string)v.Value!, true);
						break;
					case JTokenType.Integer:
					case JTokenType.Float:
						Number(ToDouble(v.Value!));
						break;
					case JTokenType.Boolean:
						if ((bool)v.Value!)
							Trues++;
						else
							Falses++;
						break;
					case JTokenType.Null:
						Nulls++;
						break;
					default:
						throw new InvalidDataException($"unexpected token type {v.Type}");
				}
				break;
		}
	}
}
