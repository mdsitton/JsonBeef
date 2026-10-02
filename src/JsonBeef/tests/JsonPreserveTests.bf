using System;
using System.Collections;

namespace JsonBeef.Tests;

/// Mutation (JsonNode's setters, Add, Insert, Remove, Rename) and PreserveStyle: unchanged documents
/// written back byte for byte, edits regenerating only what changed and keeping their neighbors.
static class JsonPreserveTests
{
	static JsonReadConfig Preserve(bool jsonc = true)
	{
		var config = jsonc ? JsonReadConfig.Jsonc : JsonReadConfig();
		config.MetadataMode = .PreserveStyle;
		return config;
	}

	static void Read(JsonDocument doc, StringView text, JsonReadConfig config)
	{
		if (doc.Read(text, config) case .Err(let error))
			Test.FatalError(scope $"`{text}` was rejected: {error.mLine}:{error.mColumn}: {error.mMessage}");
	}

	static String Written(JsonDocument doc, String output)
	{
		Test.Assert(doc.Write(output) case .Ok);
		return output;
	}

	/// Asserts that the document writes `expected` (showing what it wrote otherwise).
	static void Expect(JsonDocument doc, StringView expected)
	{
		let written = Written(doc, scope .());
		if (written != expected)
		{
			let shown = scope String(written);
			shown.Replace("\r", "\\r");
			shown.Replace("\n", "\\n");
			Test.FatalError(scope $"wrote `{shown}`");
		}
	}

	const String cSettings = "\xEF\xBB\xBF// Settings\r\n{\r\n  /* the name */\r\n  \"name\": \"\\u00e9t\\u00e9\",\r\n  \"size\": 1.50, // in meters\r\n  \"tags\": [\"a\", \"b\",],\r\n  \"deep\": {\"x\": 1E2},\r\n}\r\n// end\r\n";

	[Test]
	public static void Echo_ByteForByte()
	{
		let doc = scope JsonDocument();
		Read(doc, cSettings, Preserve());
		Test.Assert(Written(doc, scope .()) == cSettings);
		// From a stream too
		let streamed = scope JsonDocument();
		var config = Preserve();
		config.StreamBufferBytes = 16;
		Test.Assert(streamed.Read(scope JsonTestStream(cSettings, 3), config) case .Ok);
		Test.Assert(Written(streamed, scope .()) == cSettings);
		// The plain writer gives strict JSON
		Test.Assert(doc.Write(.. scope .(), JsonWriteOptions()) == "{\"name\":\"\u{E9}t\u{E9}\",\"size\":1.5,\"tags\":[\"a\",\"b\"],\"deep\":{\"x\":100.0}}");
	}

	[Test]
	public static void Edit_ScalarKeepsItsSurroundings()
	{
		let doc = scope JsonDocument();
		Read(doc, cSettings, Preserve());
		doc.Root["size"].SetNumber((int64)2);
		let expected = scope String(cSettings);
		expected.Replace("1.50", "2");
		Test.Assert(Written(doc, scope .()) == expected);
	}

	[Test]
	public static void Edit_RenameKeepsTheValueSpelling()
	{
		let doc = scope JsonDocument();
		Read(doc, cSettings, Preserve());
		doc.Root["name"].Rename("title");
		let expected = scope String(cSettings);
		expected.Replace("\"name\"", "\"title\"");
		Test.Assert(Written(doc, scope .()) == expected);
		// A value's spelling survives a change next to it
		doc.Root["deep"].Add("y").SetBool(true);
		Test.Assert(Written(doc, scope .()).Contains("{\"x\": 1E2, \"y\": true}"));
	}

	[Test]
	public static void Edit_RemoveTakesItsCommentsAndComma()
	{
		let doc = scope JsonDocument();
		Read(doc, "{\n  // a's comment\n  \"a\": 1, // a\n  \"b\": 2, // b\n  \"c\": 3 // c\n}", Preserve());
		doc.Root["b"].Remove();
		Expect(doc, "{\n  // a's comment\n  \"a\": 1, // a\n  \"c\": 3 // c\n}");
		doc.Root["c"].Remove();
		// The last member now: its comma goes, its end-of-line comment stays
		Expect(doc, "{\n  // a's comment\n  \"a\": 1 // a\n}");
		doc.Root["a"].Remove();
		Expect(doc, "{\n}");
	}

	[Test]
	public static void Edit_AddFollowsTheSiblings()
	{
		let doc = scope JsonDocument();
		Read(doc, "{\r\n    \"a\": 1,\r\n    \"list\": [1, 2],\r\n    \"empty\": {}\r\n}\r\n", Preserve(false));
		doc.Root.Add("b").SetString("x");
		doc.Root["list"].Add().SetNumber((int64)3);
		doc.Root["empty"].Add("k").SetNull();
		Expect(doc, "{\r\n    \"a\": 1,\r\n    \"list\": [1, 2, 3],\r\n    \"empty\": {\r\n        \"k\": null\r\n    },\r\n    \"b\": \"x\"\r\n}\r\n");
	}

	[Test]
	public static void Edit_InsertBeforeAndAfter()
	{
		let doc = scope JsonDocument();
		Read(doc, "{\n  \"a\": 1,\n  \"c\": 3\n}", Preserve(false));
		doc.Root["c"].InsertBefore("b").SetNumber((int64)2);
		doc.Root["c"].InsertAfter("d").SetNumber((int64)4);
		Test.Assert(Written(doc, scope .()) == "{\n  \"a\": 1,\n  \"b\": 2,\n  \"c\": 3,\n  \"d\": 4\n}");
	}

	[Test]
	public static void Edit_TrailingCommaConventionKept()
	{
		let doc = scope JsonDocument();
		Read(doc, "[1, 2,]", Preserve());
		doc.Root.Add().SetNumber((int64)3);
		Expect(doc, "[1, 2, 3,]");
		doc.Root[0].Remove();
		Expect(doc, "[2, 3,]");
	}

	[Test]
	public static void Edit_ContainerReplaced()
	{
		let doc = scope JsonDocument();
		Read(doc, "{\n  \"a\": [1, 2], // keep\n  \"b\": 2\n}", Preserve());
		let replaced = doc.Root["a"].SetObject();
		replaced.Add("x").SetNumber((int64)1);
		Test.Assert(Written(doc, scope .()) == "{\n  \"a\": {\n    \"x\": 1\n  }, // keep\n  \"b\": 2\n}");
	}

	[Test]
	public static void Edit_NewRootKeepsTheFileComments()
	{
		let doc = scope JsonDocument();
		Read(doc, "// header\n[1]\n// footer\n", Preserve());
		doc.CreateRoot().SetObject().Add("a").SetNumber((int64)1);
		Test.Assert(Written(doc, scope .()) == "// header\n{\"a\":1}\n// footer\n");
	}

	// Ported from microsoft/node-jsonc-parser src/test/edit.test.ts (MIT): the cases whose semantics
	// JsonBeef shares. Deliberate differences: removing an array's only element keeps its lines (`[\n]`,
	// not `[]`), a trailing comma stays when the last element is removed (the file's convention), and a
	// container on one line stays on one line when it grows.

	static void Edited(StringView text, delegate void(JsonDocument doc) edit, StringView expected)
	{
		let doc = scope JsonDocument();
		Read(doc, text, Preserve());
		edit(doc);
		Expect(doc, expected);
	}

	[Test]
	public static void JsoncParser_RemoveProperty()
	{
		Edited("{\n  \"x\": \"y\"\n}", scope (doc) => doc.Root["x"].Remove(), "{\n}");
		Edited("{\n  \"x\": \"y\", \"a\": []\n}", scope (doc) => doc.Root["x"].Remove(), "{\n  \"a\": []\n}");
		Edited("{\n  \"x\": \"y\", \"a\": []\n}", scope (doc) => doc.Root["a"].Remove(), "{\n  \"x\": \"y\"\n}");
	}

	[Test]
	public static void JsoncParser_SetItem()
	{
		let text = "{\n  \"x\": [1, 2, 3],\n  \"y\": 0\n}";
		Edited(text, scope (doc) => doc.Root["x"][0].SetNumber((int64)6), "{\n  \"x\": [6, 2, 3],\n  \"y\": 0\n}");
		Edited(text, scope (doc) => doc.Root["x"][1].SetNumber((int64)5), "{\n  \"x\": [1, 5, 3],\n  \"y\": 0\n}");
		Edited(text, scope (doc) => doc.Root["x"][2].SetNumber((int64)4), "{\n  \"x\": [1, 2, 4],\n  \"y\": 0\n}");
	}

	[Test]
	public static void JsoncParser_InsertItems()
	{
		Edited("[\n  2,\n  3\n]", scope (doc) => doc.Root[0].InsertBefore().SetNumber((int64)1), "[\n  1,\n  2,\n  3\n]");
		Edited("[\n]", scope (doc) => doc.Root.Add().SetNumber((int64)1), "[\n  1\n]");
		Edited("[\n  1,\n  3\n]", scope (doc) => doc.Root[0].InsertAfter().SetNumber((int64)2), "[\n  1,\n  2,\n  3\n]");
		Edited("[\n  1,\n  2\n]", scope (doc) => doc.Root.Add().SetNumber((int64)3), "[\n  1,\n  2,\n  3\n]");
		Edited("[\n]", scope (doc) => doc.Root.Add().SetString("bar"), "[\n  \"bar\"\n]");
		Edited("[\n  1,\n  2\n]", scope (doc) => doc.Root.Add().SetString("bar"), "[\n  1,\n  2,\n  \"bar\"\n]");
	}

	[Test]
	public static void JsoncParser_RemoveItems()
	{
		Edited("[\n  1,\n  2,\n  3\n]", scope (doc) => doc.Root[1].Remove(), "[\n  1,\n  3\n]");
		Edited("[\n  1,\n  2,\n  \"bar\"\n]", scope (doc) => doc.Root[2].Remove(), "[\n  1,\n  2\n]");
		Edited("// This is a comment\n[\n  1,\n  \"foo\",\n  \"bar\"\n]", scope (doc) => doc.Root[2].Remove(), "// This is a comment\n[\n  1,\n  \"foo\"\n]");
		Edited("{\"items\":[\"1\",\"2\"]}", scope (doc) => doc.Root["items"][1].Remove(), "{\"items\":[\"1\"]}");
		Edited("{\"items\":[1,2]}", scope (doc) => doc.Root["items"][1].Remove(), "{\"items\":[1]}");
	}

	[Test]
	public static void JsoncParser_InsertProperty()
	{
		Edited("{\n  \"x\": \"y\"\n}", scope (doc) => doc.Root.Add("foo").SetString("bar"), "{\n  \"x\": \"y\",\n  \"foo\": \"bar\"\n}");
		Edited("{\n  \"x\": \"y\"\n}", scope (doc) => doc.Root["x"].SetString("bar"), "{\n  \"x\": \"bar\"\n}");
		Edited("{\n  \"x\": {\n    \"a\": 1,\n    \"b\": true\n  }\n}\n", scope (doc) => doc.Root["x"]["b"].InsertBefore("c").SetString("bar"),
			"{\n  \"x\": {\n    \"a\": 1,\n    \"c\": \"bar\",\n    \"b\": true\n  }\n}\n");
		Edited("{\n  \"x\": {\n    \"a\": 1,\n    \"b\": true\n  }\n}\n", scope (doc) => doc.Root.Add("c").SetString("bar"),
			"{\n  \"x\": {\n    \"a\": 1,\n    \"b\": true\n  },\n  \"c\": \"bar\"\n}\n");
		Edited("{\n}", scope (doc) => doc.Root.Add("foo").SetArray().Add().SetString("bar"), "{\n  \"foo\": [\n    \"bar\"\n  ]\n}");
	}

	// Mutation of a plain document

	[Test]
	public static void Mutate_BuildFromCode()
	{
		let doc = scope JsonDocument();
		let root = doc.CreateRoot().SetObject();
		root.Add("name").SetString("Ada");
		root.Add("age").SetNumber((int64)36);
		let langs = root.Add("langs").SetArray();
		langs.Add().SetString("en");
		langs.Add().SetString("fr");
		root.Add("pi").SetNumber(3.25);
		root.Add("big").SetNumberText("18446744073709551616");
		root.Add("ok").SetBool(true);
		root.Add("none").SetNull();
		Test.Assert(Written(doc, scope .()) == "{\"name\":\"Ada\",\"age\":36,\"langs\":[\"en\",\"fr\"],\"pi\":3.25,\"big\":18446744073709551616,\"ok\":true,\"none\":null}");
		Test.Assert(root["langs"][1].GetString() == "fr" && root["big"].NumberKind == .BigInteger && root["pi"].GetDouble() == 3.25);
	}

	[Test]
	public static void Mutate_RemoveInsertRename()
	{
		let doc = scope JsonDocument();
		Test.Assert(doc.Read("{\"a\":[1,2,3],\"b\":{\"c\":true}}") case .Ok);
		let two = doc.Root["a"][1];
		two.InsertBefore().SetString("x");
		two.InsertAfter().SetNull();
		doc.Root["a"][0].Remove();
		doc.Root["b"].Rename("renamed");
		let c = doc.Root["renamed"]["c"];
		doc.Root["renamed"].Remove();
		Test.Assert(!c.IsValid && !doc.Root["renamed"].IsValid);
		Test.Assert(Written(doc, scope .()) == "{\"a\":[\"x\",2,null,3]}");
		Test.Assert(doc.Root.Set("a").IsArray && doc.Root.Set("z").IsNull && doc.Root.Count == 2);
		Test.Assert(doc.Root.RemoveMember("a") == 1 && Written(doc, scope .()) == "{\"z\":null}");
	}

	[Test]
	public static void Mutate_NumbersAndText()
	{
		let doc = scope JsonDocument();
		let root = doc.CreateRoot().SetArray();
		Test.Assert(root.Add().SetNumberText("1.50e+03"));
		Test.Assert(!root.Add().SetNumberText("01"));
		Test.Assert(root.Add().SetNumberText("-0"));
		Test.Assert(root.Add().SetNumberText("1e400"));
		root.Add().SetNumber(uint64.MaxValue);
		root.Add().SetString("a\0b\"");
		Test.Assert(Written(doc, scope .()) == "[1500.0,null,-0,1e400,18446744073709551615,\"a\\u0000b\\\"\"]");
		Test.Assert(!root[3].TryGetDouble(?));
		Test.Assert(root[2].TryGetDouble(let zero) && JsonNumber.IsNegative(zero));
		Test.Assert(JsonDocument.IsValidText("é") && !JsonDocument.IsValidText("\xFF"));
	}

	[Test]
	public static void Mutate_LookupIndexFollowsChanges()
	{
		let doc = scope JsonDocument();
		let root = doc.CreateRoot().SetObject();
		for (int i < 40)
			root.Add(scope $"k{i}").SetNumber((int64)i);
		Test.Assert(root["k39"].GetInt64() == 39);
		root["k39"].Rename("last");
		Test.Assert(!root["k39"].IsValid && root["last"].GetInt64() == 39);
		root.Add("k5").SetNumber((int64)-5);
		Test.Assert(root["k5"].GetInt64() == -5);
		root.RemoveMember("k5");
		Test.Assert(!root["k5"].IsValid && root.Count == 39);
	}
}
