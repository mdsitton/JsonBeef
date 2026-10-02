using System;
using System.Collections;
using System.IO;
using JsonBeef;

namespace JsonBeef.Tests;

enum TestColor
{
	Red,
	DarkBlue
}

[JsonObject]
class TestServer
{
	public String Host ~ delete _;
	public int32 Port;
}

[JsonObject(ShowGenerated = true)]
class TestBasic
{
	public bool flag;
	public int32 count;
	public uint64 big;
	public double ratio;
	public float small;
	public String name ~ delete _;
	public TestColor color;
	public int? maybe;
	public List<int> numbers ~ delete _;
	public Dictionary<String, String> labels ~ DeleteDictionaryAndKeysAndValues!(_);
}

[JsonObject]
struct TestPoint2
{
	public int32 x;
	public int32 y;
}

[JsonObject(Naming = .CamelCase)]
class TestConfig
{
	[JsonRequired] public String Id ~ delete _;
	public int32 PoolSize = 4;
	public int8 Level;
	[JsonName("enabled?")] public bool Enabled;
	[JsonAlias("descr"), JsonAlias("about")] public String Description ~ delete _;
	public TestServer Main ~ delete _;
	public List<TestServer> Servers ~ DeleteContainerAndItems!(_);
	public Dictionary<String, TestServer> ByName ~ DeleteDictionaryAndKeysAndValues!(_);
	public TestPoint2 Origin;
	public TestPoint2? Corner;
	public List<TestPoint2> Path ~ delete _;
	public List<List<double>> Matrix ~ { if (_ != null) DeleteContainerAndItems!(_); };
	public Dictionary<String, List<int>> Groups ~ { if (_ != null) { for (let entry in _) { delete entry.key; delete entry.value; } delete _; } };
	public Dictionary<int32, String> ByNumber ~ DeleteDictionaryAndValues!(_);
	public Dictionary<TestColor, bool> Flags ~ delete _;
	public List<String> Tags ~ DeleteContainerAndItems!(_);
	[JsonIgnore] public int NotMapped = 7;
	public static int sNotAField;
}

[JsonObject(Naming = .SnakeCase)]
class TestNamesSnake
{
	public int HTTPPort;
	public int poolSize;
	public int Max_Value;
}

[JsonObject(Naming = .KebabCase)]
class TestNamesKebab
{
	public int HTTPPort;
	public int poolSize;
}

[JsonObject(Naming = .PascalCase)]
class TestNamesPascal
{
	public int httpPort;
	public TestColor Color = .DarkBlue;
}

[JsonObject(Strict = true)]
class TestStrict
{
	public int a;
}

[JsonObject(OmitNulls = true)]
class TestOmit
{
	public String text ~ delete _;
	public int? number;
	public List<int> list ~ delete _;
	public int always;
}

[JsonObject(EnumsAsNumbers = true)]
class TestEnumNumbers
{
	public TestColor color;
}

// Polymorphism

[JsonObject(Discriminator = "kind")]
abstract class TestShape
{
	public String id ~ delete _;
}

[JsonObject(TypeName = "circle")]
class TestCircle : TestShape
{
	public double r;
}

[JsonObject(TypeName = "rect")]
class TestRect : TestShape
{
	public double w;
	public double h;
}

[JsonObject]
class TestDrawing
{
	public List<TestShape> shapes ~ DeleteContainerAndItems!(_);
	public TestShape focus ~ delete _;
}

[JsonObject(Discriminator = "type", TypeName = "animal")]
class TestAnimal
{
	public String name ~ delete _;
}

[JsonObject(TypeName = "dog")]
class TestDog : TestAnimal
{
	public bool goodBoy;
}

[JsonObject]
class TestZoo
{
	public List<TestAnimal> animals ~ DeleteContainerAndItems!(_);
}

// Converters

/// A point written as [x, y].
struct TestVec
{
	public double mX;
	public double mY;
}

[JsonConverter(typeof(TestVec))]
struct TestVecJson : IJsonConverter<TestVec>
{
	public static Result<void, JsonParseError> Read(JsonReader reader, ref TestVec target)
	{
		if (reader.TokenType != .StartArray)
			return .Err(JsonBind.Mismatch(reader, "an array [x, y]"));
		Try!(reader.Next());
		target.mX = Try!(reader.GetDouble());
		Try!(reader.Next());
		target.mY = Try!(reader.GetDouble());
		if (Try!(reader.Next()) != .EndArray)
			return .Err(JsonBind.Mismatch(reader, "the end of [x, y]"));
		return .Ok;
	}

	public static void Write(TestVec value, JsonWriter writer)
	{
		writer.WriteStartArray();
		writer.WriteNumber(value.mX);
		writer.WriteNumber(value.mY);
		writer.WriteEndArray();
	}
}

/// An integer written as a hex string: "0x1f".
struct TestHexJson : IJsonConverter<int>
{
	public static Result<void, JsonParseError> Read(JsonReader reader, ref int target)
	{
		if (reader.TokenType != .String || !reader.StringValue.StartsWith("0x"))
			return .Err(JsonBind.Mismatch(reader, "a hex string"));
		switch (int64.Parse(reader.StringValue.Substring(2), .HexNumber))
		{
		case .Ok(let value):
			target = (int)value;
			return .Ok;
		case .Err:
			return .Err(JsonBind.Invalid(reader, "not a hex number"));
		}
	}

	public static void Write(int value, JsonWriter writer)
	{
		writer.WriteString(scope $"0x{value:x}");
	}
}

[JsonObject]
class TestConverted
{
	public TestVec at;
	public List<TestVec> trail ~ delete _;
	[JsonUseConverter(typeof(TestHexJson))] public int mask;
	[JsonUseConverter(typeof(TestHexJson))] public List<int> masks ~ delete _;
}

/// A type that holds itself.
[JsonObject]
class TestTree
{
	public String label ~ delete _;
	public TestTree next ~ delete _;
	public List<TestTree> children ~ DeleteContainerAndItems!(_);
}

/// For reads into an allocator: no destructors, the allocator owns what the read creates.
[JsonObject]
class TestArena
{
	public String name;
	public List<String> items;
	public TestArenaChild child;
	public Dictionary<String, TestArenaChild> more;
}

[JsonObject]
class TestArenaChild
{
	public String color;
}

static class JsonObjectTests
{
	static void ExpectError(Result<void, JsonParseError> result, JsonErrorKind kind, StringView fragment, int line = Compiler.CallerLineNum)
	{
		switch (result)
		{
		case .Ok:
			Test.FatalError(scope $"line {line}: no error, expected {kind}");
		case .Err(let error):
			let text = error.ToString(.. scope .());
			if (error.mKind != kind || !text.Contains(fragment))
				Test.FatalError(scope $"line {line}: got {error.mKind}: {text}");
		}
	}

	static void ExpectOk(Result<void, JsonParseError> result, int line = Compiler.CallerLineNum)
	{
		if (result case .Err(let error))
			Test.FatalError(scope $"line {line}: {error}");
	}

	static String Write<T>(T source, String output, JsonWriteOptions options = .()) where T : IJsonSerializable
	{
		if (JsonSerializer.Write(source, output, options) case .Err(let error))
			Test.FatalError(scope $"write failed: {error}");
		return output;
	}

	[Test]
	public static void Basic_RoundTrip()
	{
		let basic = scope TestBasic();
		let text = """
			{"flag": true, "count": -5, "big": 18446744073709551615, "ratio": 0.1, "small": 0.1, "name": "x",
			 "color": "DarkBlue", "maybe": null, "numbers": [1, 2, 3], "labels": {"a": "b"}}
			""";
		ExpectOk(JsonSerializer.Read(text, basic));
		Test.Assert(basic.flag && basic.count == -5 && basic.big == uint64.MaxValue && basic.ratio == 0.1 && basic.small == 0.1f);
		Test.Assert(basic.name == "x" && basic.color == .DarkBlue && !basic.maybe.HasValue && basic.numbers.Count == 3 && basic.labels["a"] == "b");
		// A float is written as its own shortest digits
		Test.Assert(Write(basic, .. scope .()) == """
			{"flag":true,"count":-5,"big":18446744073709551615,"ratio":0.1,"small":0.1,"name":"x","color":"DarkBlue","maybe":null,"numbers":[1,2,3],"labels":{"a":"b"}}
			""");
		// The generated method bodies, for reading when debugging a mapping
		Test.Assert(TestBasic.JsonGeneratedSource.Contains("JsonBeef.JsonBind.NextMember(_rd)"));
	}

	[Test]
	public static void Recursive()
	{
		let tree = scope TestTree();
		let text = "{\"label\":\"root\",\"next\":{\"label\":\"n\",\"next\":null,\"children\":null},\"children\":[{\"label\":\"c\",\"next\":null,\"children\":[]}]}";
		ExpectOk(JsonSerializer.Read(text, tree));
		Test.Assert(tree.next.label == "n" && tree.children[0].label == "c" && tree.children[0].children.IsEmpty);
		Test.Assert(Write(tree, .. scope .()) == text);
	}

	const String cConfig = """
		{
		  "id": "c1", "poolSize": 16, "level": -128, "enabled?": true, "descr": "older name",
		  "main": {"Host": "h", "Port": 1},
		  "servers": [{"Host": "s1", "Port": 2}, {"Port": 3, "Host": "s2"}, null],
		  "byName": {"x": {"Host": "hx", "Port": 9}},
		  "origin": {"x": 1, "y": 2}, "corner": {"y": 4, "x": 3},
		  "path": [{"x": 5, "y": 6}],
		  "matrix": [[1, 2.5], [], [-0.0]],
		  "groups": {"a": [1, 2], "b": []},
		  "byNumber": {"-3": "minus three", "7": "seven"},
		  "flags": {"red": true, "darkBlue": false},
		  "tags": ["t", null],
		  "unknown": {"deep": [1, {"x": "\\u00e9"}]},
		  "notMapped": 99
		}
		""";

	[Test]
	public static void Config_EveryShape()
	{
		let config = scope TestConfig();
		ExpectOk(JsonSerializer.Read(cConfig, config));
		Test.Assert(config.Id == "c1" && config.PoolSize == 16 && config.Level == -128 && config.Enabled && config.Description == "older name");
		Test.Assert(config.Main.Host == "h" && config.Main.Port == 1);
		Test.Assert(config.Servers.Count == 3 && config.Servers[1].Host == "s2" && config.Servers[1].Port == 3 && config.Servers[2] == null);
		Test.Assert(config.ByName["x"].Port == 9);
		Test.Assert(config.Origin.x == 1 && config.Origin.y == 2 && config.Corner.Value.x == 3 && config.Path[0].y == 6);
		Test.Assert(config.Matrix.Count == 3 && config.Matrix[0][1] == 2.5 && config.Matrix[1].IsEmpty && JsonNumber.IsNegative(config.Matrix[2][0]));
		Test.Assert(config.Groups["a"].Count == 2 && config.Groups["b"].IsEmpty);
		Test.Assert(config.ByNumber[-3] == "minus three" && config.ByNumber[7] == "seven");
		Test.Assert(config.Flags[.Red] && !config.Flags[.DarkBlue]);
		Test.Assert(config.Tags[0] == "t" && config.Tags[1] == null);
		Test.Assert(config.NotMapped == 7);

		// Written back: names through CamelCase, the current name for an alias, nothing ignored
		let output = Write(config, .. scope .());
		Test.Assert(output == """
			{"id":"c1","poolSize":16,"level":-128,"enabled?":true,"description":"older name","main":{"Host":"h","Port":1},"servers":[{"Host":"s1","Port":2},{"Host":"s2","Port":3},null],"byName":{"x":{"Host":"hx","Port":9}},"origin":{"x":1,"y":2},"corner":{"x":3,"y":4},"path":[{"x":5,"y":6}],"matrix":[[1.0,2.5],[],[-0.0]],"groups":{"a":[1,2],"b":[]},"byNumber":{"-3":"minus three","7":"seven"},"flags":{"red":true,"darkBlue":false},"tags":["t",null]}
			""", output);

		// And read again into a new object, the same
		let again = scope TestConfig();
		ExpectOk(JsonSerializer.Read(output, again));
		Test.Assert(Write(again, .. scope .()) == output);
	}

	[Test]
	public static void Read_FillsExistingObjects()
	{
		let config = scope TestConfig();
		config.Main = new .();
		config.Main.Port = 42;
		config.Tags = new .();
		config.Tags.Add(new .("old"));
		ExpectOk(JsonSerializer.Read("{\"id\": \"i\", \"main\": {\"Host\": \"h\"}, \"tags\": [\"new\"]}", config));
		// Absent members keep their values; an existing object is read into; a list is refilled
		Test.Assert(config.PoolSize == 4 && config.Main.Port == 42 && config.Main.Host == "h");
		Test.Assert(config.Tags.Count == 1 && config.Tags[0] == "new");
		// null clears what the object owns
		ExpectOk(JsonSerializer.Read("{\"id\": null, \"main\": null, \"tags\": null, \"corner\": null}", config));
		Test.Assert(config.Id == null && config.Main == null && config.Tags == null && !config.Corner.HasValue);
	}

	[Test]
	public static void Read_Errors()
	{
		ExpectError(JsonSerializer.Read("{\"poolSize\": 1}", scope TestConfig()), .MissingValue, "1:1: The member \"id\" is required");
		ExpectError(JsonSerializer.Read("{\"id\": 5}", scope TestConfig()), .TypeMismatch, "1:8: /id: Expected a string, found the number 5");
		ExpectError(JsonSerializer.Read("{\"id\": \"x\", \"poolSize\": \"16\"}", scope TestConfig()), .TypeMismatch, "/poolSize: Expected an integer, found the string \"16\"");
		ExpectError(JsonSerializer.Read("{\"id\": \"x\", \"poolSize\": 1.0}", scope TestConfig()), .TypeMismatch, "Expected an integer, found the number 1.0");
		ExpectError(JsonSerializer.Read("{\"id\": \"x\", \"poolSize\": 1e2}", scope TestConfig()), .TypeMismatch, "found the number 1e2");
		ExpectError(JsonSerializer.Read("{\"id\": \"x\", \"poolSize\": null}", scope TestConfig()), .TypeMismatch, "Expected an integer, found `null`");
		ExpectError(JsonSerializer.Read("{\"id\": \"x\", \"level\": 128}", scope TestConfig()), .NumberOutOfRange, "/level: The number 128 is out of the field's range (-128 to 127)");
		ExpectError(JsonSerializer.Read("{\"big\": -1}", scope TestBasic()), .NumberOutOfRange, "(0 to 18446744073709551615)");
		ExpectError(JsonSerializer.Read("{\"big\": 18446744073709551616}", scope TestBasic()), .NumberOutOfRange, "/big");
		ExpectError(JsonSerializer.Read("{\"ratio\": 1e400}", scope TestBasic()), .NumberOutOfRange, "beyond the range of a double");
		ExpectError(JsonSerializer.Read("{\"small\": 1e39}", scope TestBasic()), .NumberOutOfRange, "beyond the range of a float");
		ExpectError(JsonSerializer.Read("{\"color\": \"Green\"}", scope TestBasic()), .InvalidValue, "/color: Unknown value \"Green\" (expected one of: Red, DarkBlue)");
		ExpectError(JsonSerializer.Read("{\"flag\": 1}", scope TestBasic()), .TypeMismatch, "Expected `true` or `false`");
		ExpectError(JsonSerializer.Read("[]", scope TestBasic()), .TypeMismatch, "1:1: Expected an object, found an array");
		// The path of an error deep inside
		ExpectError(JsonSerializer.Read("{\"id\": \"x\", \"servers\": [{\"Port\": 1}, {\"Port\": \"2\"}]}", scope TestConfig()), .TypeMismatch, "1:47: /servers/1/Port: Expected an integer");
		ExpectError(JsonSerializer.Read("{\"id\": \"x\", \"matrix\": [[1], [2, true]]}", scope TestConfig()), .TypeMismatch, "/matrix/1/1: Expected a number, found `true`");
		ExpectError(JsonSerializer.Read("{\"id\": \"x\", \"groups\": {\"a/b\": [\"x\"]}}", scope TestConfig()), .TypeMismatch, "/groups/a~1b/0:");
		ExpectError(JsonSerializer.Read("{\"id\": \"x\", \"byNumber\": {\"07\": \"x\"}}", scope TestConfig()), .InvalidValue, "/byNumber: The key \"07\" is not an integer");
		ExpectError(JsonSerializer.Read("{\"id\": \"x\", \"flags\": {\"Red\": true}}", scope TestConfig()), .InvalidValue, "The key \"Red\" is not one of: red, darkBlue");
		ExpectError(JsonSerializer.Read("{\"id\": \"x\", \"origin\": null}", scope TestConfig()), .TypeMismatch, "/origin: Expected an object, found `null`");
		ExpectError(JsonSerializer.Read("{\"id\": \"x\", \"path\": [null]}", scope TestConfig()), .TypeMismatch, "/path/0: Expected an object");
		// The text must end after the value, and be JSON throughout (also in what no field maps)
		ExpectError(JsonSerializer.Read("{\"id\": \"x\"} 1", scope TestConfig()), .InvalidStructure, "end of the input");
		ExpectError(JsonSerializer.Read("{\"id\": \"x\", \"other\": [1,]}", scope TestConfig()), .InvalidStructure, "1:25:");
	}

	[Test]
	public static void Read_Duplicates()
	{
		ExpectError(JsonSerializer.Read("{\"id\": \"a\", \"id\": \"b\"}", scope TestConfig()), .DuplicateName, "1:13: The member \"id\" is given twice");
		// An alias and the name read the same field
		ExpectError(JsonSerializer.Read("{\"id\": \"a\", \"description\": \"x\", \"about\": \"y\"}", scope TestConfig()), .DuplicateName, "\"about\"");
		ExpectError(JsonSerializer.Read("{\"id\": \"a\", \"groups\": {\"k\": [], \"k\": [1]}}", scope TestConfig()), .DuplicateName, "/groups: The member \"k\"");
		var last = JsonReadConfig();
		last.DuplicateNames = .LastWins;
		let config = scope TestConfig();
		ExpectOk(JsonSerializer.Read("{\"id\": \"a\", \"id\": \"b\", \"groups\": {\"k\": [], \"k\": [1]}}", config, last));
		Test.Assert(config.Id == "b" && config.Groups["k"].Count == 1);
		var first = JsonReadConfig();
		first.DuplicateNames = .FirstWins;
		let config2 = scope TestConfig();
		ExpectOk(JsonSerializer.Read("{\"id\": \"a\", \"id\": \"b\", \"groups\": {\"k\": [], \"k\": [1]}, \"poolSize\": 2}", config2, first));
		Test.Assert(config2.Id == "a" && config2.Groups["k"].IsEmpty && config2.PoolSize == 2);
	}

	[Test]
	public static void Names_Policies()
	{
		let snake = scope TestNamesSnake();
		snake.HTTPPort = 1;
		Test.Assert(Write(snake, .. scope .()) == "{\"http_port\":1,\"pool_size\":0,\"max_value\":0}");
		let kebab = scope TestNamesKebab();
		Test.Assert(Write(kebab, .. scope .()) == "{\"http-port\":0,\"pool-size\":0}");
		let pascal = scope TestNamesPascal();
		Test.Assert(Write(pascal, .. scope .()) == "{\"HttpPort\":0,\"Color\":\"DarkBlue\"}");
		ExpectOk(JsonSerializer.Read("{\"HttpPort\": 3, \"Color\": \"Red\"}", pascal));
		Test.Assert(pascal.httpPort == 3 && pascal.Color == .Red);
	}

	[Test]
	public static void Strict_RejectsUnknownMembers()
	{
		ExpectError(JsonSerializer.Read("{\"a\": 1, \"b\": 2}", scope TestStrict()), .UnknownMember, "1:10: Unknown member \"b\"");
		let strict = scope TestStrict();
		ExpectOk(JsonSerializer.Read("{\"a\": 5}", strict));
		Test.Assert(strict.a == 5);
	}

	[Test]
	public static void OmitNulls()
	{
		let omit = scope TestOmit();
		Test.Assert(Write(omit, .. scope .()) == "{\"always\":0}");
		omit.number = 2;
		omit.text = new .("t");
		Test.Assert(Write(omit, .. scope .()) == "{\"text\":\"t\",\"number\":2,\"always\":0}");
	}

	[Test]
	public static void EnumsAsNumbers()
	{
		let value = scope TestEnumNumbers();
		value.color = .DarkBlue;
		Test.Assert(Write(value, .. scope .()) == "{\"color\":1}");
		ExpectOk(JsonSerializer.Read("{\"color\": 0}", value));
		Test.Assert(value.color == .Red);
		ExpectError(JsonSerializer.Read("{\"color\": 2}", value), .InvalidValue, "2 is not a value of JsonBeef.Tests.TestColor");
		ExpectError(JsonSerializer.Read("{\"color\": \"Red\"}", value), .TypeMismatch, "Expected an integer");
	}

	[Test]
	public static void Write_Errors()
	{
		let basic = scope TestBasic();
		basic.ratio = double.NaN;
		Test.Assert(JsonSerializer.Write(basic, scope String()) case .Err(let nan) && nan.mKind == .NonFiniteNumber);
		basic.ratio = 0;
		basic.color = (TestColor)7;
		Test.Assert(JsonSerializer.Write(basic, scope String()) case .Err(let invalid) && invalid.mKind == .InvalidValue && StringView(invalid.mMessage).Contains("7 is not a case"));
	}

	[Test]
	public static void Write_Layouts()
	{
		let server = scope TestServer();
		server.Host = new .("h");
		server.Port = 1;
		Test.Assert(Write(server, .. scope .(), .Pretty) == "{\n  \"Host\": \"h\",\n  \"Port\": 1\n}\n");
		// RFC 8785: members sorted
		Test.Assert(Write(server, .. scope .(), .Jcs) == "{\"Host\":\"h\",\"Port\":1}");
		let point = TestPoint2() { x = 2, y = 1 };
		Test.Assert(Write(point, .. scope .()) == "{\"x\":2,\"y\":1}");
	}

	[Test]
	public static void Polymorphic()
	{
		let drawing = scope TestDrawing();
		// The discriminator first, or anywhere: the reader looks ahead and comes back
		let text = "{\"shapes\": [{\"kind\": \"circle\", \"r\": 2}, {\"w\": 3, \"kind\": \"rect\", \"h\": 4, \"id\": \"r1\"}], \"focus\": {\"r\": 1, \"kind\": \"circle\"}}";
		for (int chunk in int[](0, 1, 5))
		{
			if (chunk == 0)
				ExpectOk(JsonSerializer.Read(text, drawing));
			else
			{
				var config = JsonReadConfig();
				config.StreamBufferBytes = 16;
				ExpectOk(JsonSerializer.Read(scope JsonTestStream(text, chunk), drawing, config));
			}
			Test.Assert(drawing.shapes.Count == 2);
			Test.Assert(drawing.shapes[0] is TestCircle && ((TestCircle)drawing.shapes[0]).r == 2);
			let rect = drawing.shapes[1] as TestRect;
			Test.Assert(rect != null && rect.w == 3 && rect.h == 4 && rect.id == "r1");
			Test.Assert((drawing.focus as TestCircle).r == 1);
		}
		// Written with the discriminator first
		Test.Assert(Write(drawing, .. scope .()) == "{\"shapes\":[{\"kind\":\"circle\",\"id\":null,\"r\":2.0},{\"kind\":\"rect\",\"id\":\"r1\",\"w\":3.0,\"h\":4.0}],\"focus\":{\"kind\":\"circle\",\"id\":null,\"r\":1.0}}");

		ExpectError(JsonSerializer.Read("{\"shapes\": [{\"kind\": \"star\"}]}", scope TestDrawing()), .InvalidValue, "1:13: /shapes/0: Unknown \"kind\": \"star\" (expected one of: circle, rect)");
		ExpectError(JsonSerializer.Read("{\"shapes\": [{\"r\": 1}]}", scope TestDrawing()), .MissingValue, "/shapes/0: The object has no \"kind\" member");
		ExpectError(JsonSerializer.Read("{\"focus\": {\"kind\": 1}}", scope TestDrawing()), .TypeMismatch, "it must be a string");
		ExpectError(JsonSerializer.Read("{\"focus\": {\"kind\": \"circle\", \"kind\": \"circle\"}}", scope TestDrawing()), .DuplicateName, "\"kind\"");
		// A subtype read directly checks the name
		ExpectError(JsonSerializer.Read("{\"kind\": \"rect\"}", scope TestCircle()), .InvalidValue, "/kind: \"kind\" is \"rect\", but the object is read as \"circle\"");
		// Errors inside the dispatched object have its path
		ExpectError(JsonSerializer.Read("{\"shapes\": [{\"kind\": \"circle\", \"r\": \"x\"}]}", scope TestDrawing()), .TypeMismatch, "/shapes/0/r:");

		// A concrete base: no discriminator reads the base
		let zoo = scope TestZoo();
		ExpectOk(JsonSerializer.Read("{\"animals\": [{\"name\": \"a\"}, {\"type\": \"dog\", \"name\": \"d\", \"goodBoy\": true}, {\"type\": \"animal\"}]}", zoo));
		Test.Assert(zoo.animals[0].GetType() == typeof(TestAnimal) && (zoo.animals[1] as TestDog).goodBoy && zoo.animals[2].GetType() == typeof(TestAnimal));
		Test.Assert(Write(zoo, .. scope .()) == "{\"animals\":[{\"type\":\"animal\",\"name\":\"a\"},{\"type\":\"dog\",\"name\":\"d\",\"goodBoy\":true},{\"type\":\"animal\",\"name\":null}]}");
	}

	[Test]
	public static void Converters()
	{
		let value = scope TestConverted();
		ExpectOk(JsonSerializer.Read("{\"at\": [1, 2.5], \"trail\": [[0, 0], [3, 4]], \"mask\": \"0x1f\", \"masks\": [\"0x1\", \"0xff\"]}", value));
		Test.Assert(value.at.mX == 1 && value.at.mY == 2.5 && value.trail[1].mY == 4 && value.mask == 31 && value.masks[1] == 255);
		Test.Assert(Write(value, .. scope .()) == "{\"at\":[1.0,2.5],\"trail\":[[0.0,0.0],[3.0,4.0]],\"mask\":\"0x1f\",\"masks\":[\"0x1\",\"0xff\"]}");
		ExpectError(JsonSerializer.Read("{\"at\": {}}", value), .TypeMismatch, "/at: Expected an array [x, y], found an object");
		ExpectError(JsonSerializer.Read("{\"masks\": [\"0x1\", \"0xzz\"]}", value), .InvalidValue, "/masks/1: not a hex number");
	}

	[Test]
	public static void Allocator()
	{
		let arena = scope BumpAllocator();
		let value = scope TestArena();
		ExpectOk(JsonSerializer.Read("{\"name\": \"n\", \"items\": [\"a\", \"b\"], \"child\": {\"color\": \"red\"}, \"more\": {\"k\": {\"color\": \"blue\"}}}", value, .(), arena));
		Test.Assert(value.name == "n" && value.items[1] == "b" && value.child.color == "red" && value.more["k"].color == "blue");
		// Read again: nothing allocated from the arena is deleted
		ExpectOk(JsonSerializer.Read("{\"name\": null, \"items\": [\"c\"], \"child\": null}", value, .(), arena));
		Test.Assert(value.name == null && value.items.Count == 1 && value.child == null);
	}

	[Test]
	public static void Files()
	{
		let path = scope $"{Path.GetTempPath(.. scope .())}jsonbeef-object-test.json";
		defer { File.Delete(path).IgnoreError(); }
		let server = scope TestServer();
		server.Host = new .("h");
		server.Port = 5;
		Test.Assert(JsonSerializer.WriteFile(server, path) case .Ok);
		let read = scope TestServer();
		ExpectOk(JsonSerializer.ReadFile(path, read));
		Test.Assert(read.Host == "h" && read.Port == 5);
		Test.Assert(File.WriteAllText(path, "{\"Port\": \"x\"}") case .Ok);
		switch (JsonSerializer.ReadFile(path, read))
		{
		case .Ok:
			Test.FatalError("no error");
		case .Err(let error):
			Test.Assert(error.ToString(.. scope .()) == scope $"{path}:1:10: /Port: Expected an integer, found the string \"x\"");
		}
		ExpectError(JsonSerializer.ReadFile(scope $"{path}.missing", read), .IoError, "Cannot open the file");
	}

	// Documents

	[Test]
	public static void Node_Read()
	{
		let doc = scope JsonDocument();
		var config = JsonReadConfig();
		config.MetadataMode = .Positions;
		Test.Assert(doc.Read("{\"data\": {\"id\": \"c\", \"servers\": [{\"Host\": \"a\", \"Port\": \"x\"}]}}", config) case .Ok);
		// Located at the node from the document's positions
		ExpectError(JsonSerializer.Read(doc.Root["data"], scope TestConfig()), .TypeMismatch, "1:56: /servers/0/Port: Expected an integer, found the string \"x\"");
		doc.Root["data"]["servers"][0]["Port"].SetNumber(7);
		let config2 = scope TestConfig();
		ExpectOk(JsonSerializer.Read(doc.Root["data"], config2));
		Test.Assert(config2.Servers[0].Port == 7);

		// Without positions, the path still says where
		let plain = scope JsonDocument();
		Test.Assert(plain.Read("{\"Port\": true}") case .Ok);
		ExpectError(JsonSerializer.Read(plain.Root, scope TestServer()), .TypeMismatch, "/Port: Expected an integer");

		// A float field from the source text, not from the double (which would round twice)
		let floats = scope JsonDocument();
		var positions = JsonReadConfig();
		positions.MetadataMode = .Positions;
		Test.Assert(floats.Read("{\"small\": 7.038531e-26}", positions) case .Ok);
		let basic = scope TestBasic();
		ExpectOk(JsonSerializer.Read(floats.Root, basic));
		float small = basic.small;
		Test.Assert(*(uint32*)&small == 0x15AE43FD);
		// From a reader too
		ExpectOk(JsonSerializer.Read("{\"small\": 7.038531e-26}", basic));
		small = basic.small;
		Test.Assert(*(uint32*)&small == 0x15AE43FD);

		// The discriminator anywhere, and a struct
		let shapes = scope JsonDocument();
		Test.Assert(shapes.Read("{\"focus\": {\"r\": 5, \"kind\": \"circle\"}, \"p\": {\"x\": 1, \"y\": 2}}") case .Ok);
		let drawing = scope TestDrawing();
		ExpectOk(JsonSerializer.Read(shapes.Root, drawing));
		Test.Assert((drawing.focus as TestCircle).r == 5);
		var point = TestPoint2();
		ExpectOk(JsonSerializer.Read(shapes.Root["p"], ref point));
		Test.Assert(point.x == 1 && point.y == 2);
	}

	[Test]
	public static void Node_WriteInPlace()
	{
		let source = """
			// settings
			{
			  "id": "c1",
			  "poolSize": 16, // workers
			  "about": "older",
			  "ratio": 1.50,
			  "servers": [
			    {"Host": "a", "Port": 1, "note": "kept"},
			    {"Host": "b", "Port": 2}
			  ],
			  "groups": {"a": [1], "gone": [2]},
			  "extra": true
			}
			""";
		let doc = scope JsonDocument();
		var config = JsonReadConfig.Jsonc;
		config.MetadataMode = .PreserveStyle;
		Test.Assert(doc.Read(source, config) case .Ok);
		let value = scope TestConfig();
		ExpectOk(JsonSerializer.Read(doc.Root, value));

		// Unchanged: the text stays byte for byte (a value equal to what is there is not rewritten)
		Test.Assert(value.JsonWrite(doc.Root) case .Ok);
		let unchangedOutput = scope String();
		Test.Assert(doc.Write(unchangedOutput) case .Ok);
		Test.Assert(unchangedOutput.Contains("\"poolSize\": 16, // workers") && unchangedOutput.Contains("{\"Host\": \"a\", \"Port\": 1, \"note\": \"kept\"}"), unchangedOutput);
		// The alias was renamed to the current name; members of no field stay
		Test.Assert(unchangedOutput.Contains("\"description\": \"older\"") && unchangedOutput.Contains("\"extra\": true"), unchangedOutput);

		// Changes go in place
		value.PoolSize = 32;
		value.Servers[1].Port = 20;
		delete value.Servers[0];
		value.Servers.RemoveAt(0);
		value.Groups["a"].Add(5);
		if (value.Groups.GetAndRemove("gone") case .Ok(let removed))
		{
			delete removed.key;
			delete removed.value;
		}
		let output = scope String();
		Test.Assert(value.JsonWrite(doc.Root) case .Ok);
		Test.Assert(doc.Write(output) case .Ok);
		Test.Assert(output.StartsWith("// settings\n{\n  \"id\": \"c1\",\n  \"poolSize\": 32, // workers\n"), output);
		Test.Assert(output.Contains("\"groups\": {\"a\": [1, 5]}") && output.Contains("\"extra\": true"), output);
		// Array elements are updated by position: the first element node now holds the second server, and
		// keeps the member no field maps ("note"); new members follow the document's layout
		Test.Assert(output == """
			// settings
			{
			  "id": "c1",
			  "poolSize": 32, // workers
			  "description": "older",
			  "ratio": 1.50,
			  "servers": [
			    {"Host": "b", "Port": 20, "note": "kept"}
			  ],
			  "groups": {"a": [1, 5]},
			  "extra": true,
			  "level": 0,
			  "enabled?": false,
			  "main": null,
			  "byName": null,
			  "origin": {
			    "x": 0,
			    "y": 0
			  },
			  "corner": null,
			  "path": null,
			  "matrix": null,
			  "byNumber": null,
			  "flags": null,
			  "tags": null
			}
			""", output);
		// What was written reads back as the object
		let again = scope TestConfig();
		let check = scope JsonDocument();
		Test.Assert(check.Read(output, JsonReadConfig.Jsonc) case .Ok);
		ExpectOk(JsonSerializer.Read(check.Root, again));
		Test.Assert(again.PoolSize == 32 && again.Servers.Count == 1 && again.Servers[0].Port == 20 && again.Groups.Count == 1 && again.Groups["a"].Count == 2);
	}

	[Test]
	public static void Node_WriteNewDocument()
	{
		let doc = scope JsonDocument();
		let drawing = scope TestDrawing();
		drawing.shapes = new .();
		let circle = new TestCircle();
		circle.r = 1.5;
		drawing.shapes.Add(circle);
		let converted = scope TestConverted();
		converted.at = .() { mX = 1, mY = 2 };
		converted.mask = 255;
		Test.Assert(drawing.JsonWrite(doc.CreateRoot()) case .Ok);
		Test.Assert(doc.Write(.. scope .()) == "{\"shapes\":[{\"kind\":\"circle\",\"id\":null,\"r\":1.5}],\"focus\":null}");
		let doc2 = scope JsonDocument();
		Test.Assert(converted.JsonWrite(doc2.CreateRoot()) case .Ok);
		Test.Assert(doc2.Write(.. scope .()) == "{\"at\":[1.0,2.0],\"trail\":null,\"mask\":\"0xff\",\"masks\":null}");
		// NaN has no JSON form
		let basic = scope TestBasic();
		basic.ratio = double.PositiveInfinity;
		Test.Assert(basic.JsonWrite(doc2.CreateRoot()) case .Err(let error) && error.mKind == .InvalidValue);
	}
}
