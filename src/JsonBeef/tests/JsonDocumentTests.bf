using System;
using System.Collections;
using System.IO;
using internal JsonBeef;
using static JsonBeef.Tests.JsonTestUtil;

namespace JsonBeef.Tests;

/// JsonDocument and JsonNode: building, navigation, lookups (with the member index), values, handles,
/// streams and files; JsonWriter: layouts, escaping options, misuse.
static class JsonDocumentTests
{
	static void Read(JsonDocument doc, StringView text)
	{
		if (doc.Read(text) case .Err(let error))
			Test.FatalError(scope $"`{text}` was rejected: {error.mLine}:{error.mColumn}: {error.mMessage}");
	}

	static String Compact(JsonDocument doc, String output)
	{
		Test.Assert(doc.Write(output) case .Ok);
		return output;
	}

	[Test]
	public static void Build_TreeAndNavigation()
	{
		let doc = scope JsonDocument();
		Read(doc, "{\"a\": [1, {\"b\": null}, \"x\"], \"c\": true}");
		let root = doc.Root;
		Test.Assert(root.IsObject && root.Count == 2 && root.Kind == .Object);
		let a = root["a"];
		Test.Assert(a.IsArray && a.Count == 3 && a.Name == "a" && a.IsMember && a.Parent == root);
		Test.Assert(a[0].GetInt64() == 1 && a[1]["b"].IsNull && a[2].GetString() == "x");
		Test.Assert(a.FirstChild == a[0] && a.LastChild == a[2] && a[1].Next == a[2] && a[1].Previous == a[0]);
		Test.Assert(!a[0].IsMember && a[0].Name == "");
		Test.Assert(root["c"].GetBool() && root["c"].IsBool);
		Test.Assert(!root.Parent.IsValid && !a[2].Next.IsValid && !a[0].Previous.IsValid);
		// Members in order
		let names = scope String();
		for (let member in root.Members)
			names.Append(member.Name);
		Test.Assert(names == "ac");
		int count = 0;
		for (let element in a.Children)
			count++;
		Test.Assert(count == 3 && a.Children.Count == 3 && root.Members.Count == 2);
	}

	[Test]
	public static void Lookups_ChainOnInvalidHandles()
	{
		let doc = scope JsonDocument();
		Read(doc, "{\"a\": {\"b\": 2}}");
		Test.Assert(doc.Root["a"]["b"].GetInt64() == 2);
		Test.Assert(!doc.Root["x"]["y"].IsValid);
		Test.Assert(doc.Root["x"]["y"].GetInt64(7) == 7 && doc.Root["x"].GetString("d") == "d");
		Test.Assert(!doc.Root["a"][5].IsValid && !doc.Root["a"]["b"]["c"].IsValid && !doc.Root[-1].IsValid);
		Test.Assert(!doc.Root["a"]["b"].TryGetString(?) && !doc.Root["a"].TryGetDouble(?));
		Test.Assert(doc.Root.Contains("a") && !doc.Root.Contains("b"));
		Test.Assert(doc.Root.At("/a/b").GetInt64() == 2 && !doc.Root.At("/a/c").IsValid);
	}

	[Test]
	public static void Lookups_LargeObjectsUseTheIndex()
	{
		// Past the index threshold, with a duplicate: the last one wins, as in a scan
		let text = scope String("{");
		for (int i < 100)
			text.AppendF("\"k{}\":{},", i, i);
		text.Append("\"k7\":-7}");
		let doc = scope JsonDocument();
		Read(doc, text);
		Test.Assert(doc.Root.Count == 101);
		for (int i < 100)
			Test.Assert(doc.Root[scope $"k{i}"].GetInt64() == (i == 7 ? -7 : i));
		Test.Assert(!doc.Root["k100"].IsValid && !doc.Root[""].IsValid);
		// Duplicate policies past the threshold
		var config = JsonReadConfig();
		config.DuplicateNames = .Error;
		Test.Assert(doc.Read(text, config) case .Err(let error) && error.mKind == .DuplicateName);
		config.DuplicateNames = .LastWins;
		Test.Assert(doc.Read(text, config) case .Ok);
		Test.Assert(doc.Root.Count == 100 && doc.Root["k7"].GetInt64() == -7 && doc.Root[99].Name == "k7");
		config.DuplicateNames = .FirstWins;
		Test.Assert(doc.Read(text, config) case .Ok);
		Test.Assert(doc.Root.Count == 100 && doc.Root["k7"].GetInt64() == 7);
	}

	[Test]
	public static void Values_Numbers()
	{
		let doc = scope JsonDocument();
		Read(doc, "[1, -0, 1.5, 18446744073709551615, 18446744073709551616, 1e400, -1e400, 9007199254740993]");
		let a = doc.Root;
		Test.Assert(a[0].NumberKind == .Integer && a[0].GetInt64() == 1 && a[0].GetUInt64() == 1 && a[0].GetDouble() == 1);
		Test.Assert(a[1].TryGetDouble(let negativeZero) && JsonNumber.IsNegative(negativeZero) && a[1].GetInt64(5) == 0);
		Test.Assert(a[2].NumberKind == .Float && !a[2].TryGetInt64(?) && a[2].GetDouble() == 1.5);
		Test.Assert(a[3].NumberKind == .UInteger && a[3].GetUInt64() == uint64.MaxValue && !a[3].TryGetInt64(?));
		Test.Assert(a[4].NumberKind == .BigInteger && a[4].GetDouble() == 18446744073709551616.0);
		Test.Assert(a[5].NumberKind == .Float && !a[5].TryGetDouble(?) && a[5].GetDouble(-1) == -1);
		Test.Assert(!a[6].TryGetDouble(?));
		Test.Assert(a[7].GetInt64() == 9007199254740993 && a[7].GetDouble() == 9007199254740992.0);
		let texts = scope String();
		for (let element in a.Children)
		{
			element.AppendNumber(texts);
			texts.Append(' ');
		}
		Test.Assert(texts == "1 -0 1.5 18446744073709551615 18446744073709551616 1e400 -1e400 9007199254740993 ");
	}

	[Test]
	public static void Values_Strings()
	{
		let doc = scope JsonDocument();
		Read(doc, "{\"plain\": \"abc\", \"esc\\u00e9\": \"a\\nb\\u0000\", \"\": \"\"}");
		Test.Assert(doc.Root["plain"].GetString() == "abc");
		Test.Assert(doc.Root["esc\u{E9}"].GetString() == "a\nb\0");
		Test.Assert(doc.Root[""].IsString && doc.Root[""].GetString("x") == "");
	}

	[Test]
	public static void Handles_GoStaleOnRead()
	{
		let doc = scope JsonDocument();
		Read(doc, "[1]");
		let old = doc.Root[0];
		Test.Assert(old.IsValid);
		Read(doc, "[2]");
		Test.Assert(!old.IsValid && doc.Root[0].GetInt64() == 2);
		doc.Clear();
		Test.Assert(doc.IsEmpty && !doc.Root.IsValid);
		Test.Assert(doc.GetNode(.(1)).IsValid == false);
	}

	[Test]
	public static void Read_ErrorLeavesTheDocumentEmpty()
	{
		let doc = scope JsonDocument();
		Read(doc, "[1]");
		Test.Assert(doc.Read("[1,") case .Err(let error) && error.mKind == .UnexpectedEndOfInput);
		Test.Assert(doc.IsEmpty);
	}

	[Test]
	public static void Read_StreamCopiesEverything()
	{
		let text = "{\"name\": \"\\u00e9t\\u00e9\", \"list\": [1, 2.5, \"long string that crosses the small buffer\"], \"big\": 123456789012345678901234567890}";
		let stream = scope JsonTestStream(text, 3);
		var config = JsonReadConfig();
		config.StreamBufferBytes = 16;
		let doc = scope JsonDocument();
		Test.Assert(doc.Read(stream, config) case .Ok);
		let memory = scope JsonDocument();
		Read(memory, text);
		Test.Assert(Compact(doc, scope .()) == Compact(memory, scope .()));
		Test.Assert(doc.Root["name"].GetString() == "\u{E9}t\u{E9}" && doc.Root["list"][2].GetString().Length == 41);
	}

	[Test]
	public static void Read_File()
	{
		let path = scope String();
		Path.GetTempPath(path);
		path.Append("jsonbeef-test-read-file.json");
		Test.Assert(File.WriteAllText(path, "{\"a\": [true]}") case .Ok);
		defer { File.Delete(path).IgnoreError(); }
		let doc = scope JsonDocument();
		if (doc.ReadFile(path) case .Err(let readError))
			Test.FatalError(scope $"{path}: {readError.mKind}: {readError.mMessage} (exists: {File.Exists(path)})");
		Test.Assert(doc.Root["a"][0].GetBool() && doc.SourceName == path);
		var config = JsonReadConfig();
		config.StreamBufferBytes = 16;
		Test.Assert(doc.ReadFile(path, config) case .Ok);
		Test.Assert(doc.Root["a"][0].GetBool());
		Test.Assert(doc.ReadFile("/nonexistent/jsonbeef.json") case .Err(let error) && error.mKind == .IoError);
		Test.Assert(File.WriteAllText(path, "[1,]") case .Ok);
		Test.Assert(doc.ReadFile(path) case .Err(let syntax) && syntax.mSource == path && syntax.mColumn == 4);
	}

	[Test]
	public static void Deep_NestingIsIterative()
	{
		// Reading, writing and walking 100,000 levels needs no stack
		let text = scope String();
		Repeat("[", 100000, text);
		text.Append('1');
		Repeat("]", 100000, text);
		var config = JsonReadConfig();
		config.MaxDepth = 0;
		let doc = scope JsonDocument();
		Test.Assert(doc.Read(text, config) case .Ok);
		Test.Assert(Compact(doc, scope .()) == text);
		Test.Assert(doc.Write(scope .(), .Jcs) case .Ok);
		// (Indented output grows with the square of the depth: 1,000 levels here)
		let thousand = scope String();
		Repeat("[", 1000, thousand);
		Repeat("]", 1000, thousand);
		let small = scope JsonDocument();
		Read(small, thousand);
		let pretty = scope String();
		Test.Assert(small.Write(pretty, .Pretty) case .Ok);
		Test.Assert(pretty.Length > 1000 * 1000);
		JsonNode node = doc.Root;
		int depth = 0;
		while (node.IsArray)
		{
			node = node[0];
			depth++;
		}
		Test.Assert(depth == 100000 && node.GetInt64() == 1);
	}

	[Test]
	public static void Write_Pretty()
	{
		let doc = scope JsonDocument();
		Read(doc, "{\"a\":[1,[],{}],\"b\":{\"c\":\"d\"},\"e\":[]}");
		let pretty = scope String();
		Test.Assert(doc.Write(pretty, .Pretty) case .Ok);
		Test.Assert(pretty == "{\n  \"a\": [\n    1,\n    [],\n    {}\n  ],\n  \"b\": {\n    \"c\": \"d\"\n  },\n  \"e\": []\n}\n", pretty);
		var options = JsonWriteOptions();
		options.Indented = true;
		options.IndentText = "\t";
		options.NewLine = "\r\n";
		let tabs = scope String();
		Test.Assert(doc.Write(doc.Root["b"], tabs, options) case .Ok);
		Test.Assert(tabs == "{\r\n\t\"c\": \"d\"\r\n}");
	}

	[Test]
	public static void Write_EscapingOptions()
	{
		let doc = scope JsonDocument();
		Read(doc, "\"<\u{E9}>&\u{2028}\u{1F600}\"");
		Test.Assert(Compact(doc, scope .()) == "\"<\u{E9}>&\u{2028}\u{1F600}\"");
		var options = JsonWriteOptions();
		options.EscapeNonAscii = true;
		let ascii = scope String();
		Test.Assert(doc.Write(ascii, options) case .Ok && ascii == "\"<\\u00e9>&\\u2028\\ud83d\\ude00\"");
		options = .();
		options.EscapeHtml = true;
		options.EscapeLineSeparators = true;
		let html = scope String();
		Test.Assert(doc.Write(html, options) case .Ok && html == "\"\\u003c\u{E9}\\u003e\\u0026\\u2028\u{1F600}\"");
	}

	[Test]
	public static void Writer_Streaming()
	{
		let output = scope String();
		let writer = scope JsonWriter(output);
		writer.WriteStartObject();
		writer.WritePropertyName("n");
		writer.WriteNumber((int64)-5);
		writer.WritePropertyName("u");
		writer.WriteNumber(uint64.MaxValue);
		writer.WritePropertyName("d");
		writer.WriteNumber(2.0);
		writer.WritePropertyName("t");
		writer.WriteNumberText("1.50e+03");
		writer.WritePropertyName("s");
		writer.WriteString("a\"b");
		writer.WritePropertyName("l");
		writer.WriteStartArray();
		writer.WriteBool(true);
		writer.WriteNull();
		writer.WriteEndArray();
		writer.WriteEndObject();
		Test.Assert(writer.Finish() case .Ok);
		Test.Assert(output == "{\"n\":-5,\"u\":18446744073709551615,\"d\":2.0,\"t\":1.50e+03,\"s\":\"a\\\"b\",\"l\":[true,null]}", output);
	}

	[Test]
	public static void Writer_Misuse()
	{
		let output = scope String();
		let writer = scope JsonWriter(output);
		writer.WriteStartObject();
		writer.WriteNumber((int64)1);
		Test.Assert(writer.HasError);
		Test.Assert(writer.Finish() case .Err(let missingName) && missingName.mKind == .InvalidStructure);
		writer.Reset(output);
		writer.WriteStartArray();
		writer.WriteEndObject();
		Test.Assert(writer.Finish() case .Err(let mismatch) && mismatch.mKind == .InvalidStructure);
		writer.Reset(output);
		writer.WriteNull();
		writer.WriteNull();
		Test.Assert(writer.Finish() case .Err(let second) && second.mKind == .InvalidStructure);
		writer.Reset(output);
		writer.WriteStartArray();
		Test.Assert(writer.Finish() case .Err(let unclosed) && unclosed.mKind == .InvalidStructure);
		writer.Reset(output);
		writer.WriteNumberText("01");
		Test.Assert(writer.Finish() case .Err(let number) && number.mKind == .InvalidNumber);
		writer.Reset(output);
		writer.WriteString("\xFF");
		Test.Assert(writer.Finish() case .Err(let utf8) && utf8.mKind == .InvalidUtf8);
		writer.Reset(output);
		Test.Assert(writer.Finish() case .Err(let empty) && empty.mKind == .InvalidStructure);
	}

	[Test]
	public static void Write_EmptyDocument()
	{
		let doc = scope JsonDocument();
		Test.Assert(doc.Write(scope .()) case .Err(let error) && error.mKind == .InvalidStructure);
	}

	[Test]
	public static void Utf16Order()
	{
		Test.Assert(JsonDocument.CompareUtf16("a", "b") < 0 && JsonDocument.CompareUtf16("b", "a") > 0);
		Test.Assert(JsonDocument.CompareUtf16("a", "ab") < 0 && JsonDocument.CompareUtf16("", "") == 0);
		// A supplementary character (D83D ...) sorts below U+E000 and above U+D7FF
		Test.Assert(JsonDocument.CompareUtf16("\u{1F600}", "\u{E000}") < 0 && JsonDocument.CompareUtf16("\u{1F600}", "\u{D7FF}") > 0);
		Test.Assert(JsonDocument.CompareUtf16("\u{1F600}", "\u{1F601}") < 0 && JsonDocument.CompareUtf16("\u{10000}", "\u{1F600}") < 0);
	}

	[Test]
	public static void IJson_Checks()
	{
		var config = JsonReadConfig();
		config.IJson = true;
		let doc = scope JsonDocument();
		// Numbers beyond a double are errors; precision loss is not
		Test.Assert(doc.Read("[1e400]", config) case .Err(let big) && big.mKind == .NumberOutOfRange && big.mColumn == 2);
		Test.Assert(doc.Read("[-1e309]", config) case .Err(let negative) && negative.mKind == .NumberOutOfRange);
		Test.Assert(doc.Read("[123456789012345678901234567890, 0.1, 1e-400]", config) case .Ok);
		// Duplicates are errors whatever DuplicateNames says
		config.DuplicateNames = .LastWins;
		Test.Assert(doc.Read("{\"a\": 1, \"a\": 2}", config) case .Err(let duplicate) && duplicate.mKind == .DuplicateName && duplicate.mColumn == 10);
		// The lenient options give way
		config.AllowNonFiniteNumbers = true;
		config.InvalidUtf8 = .Replace;
		config.InvalidSurrogates = .Wtf8;
		Test.Assert(doc.Read("[NaN]", config) case .Err(let nan) && nan.mKind == .InvalidNumber);
		Test.Assert(doc.Read("[\"\xFF\"]", config) case .Err(let utf8) && utf8.mKind == .InvalidUtf8);
		Test.Assert(doc.Read("[\"\\uD800\"]", config) case .Err(let surrogate) && surrogate.mKind == .InvalidSurrogate);
		// Through the reader too, and SkipValue checks the same
		let reader = scope JsonReader("[[\"\\uFFFF\"], 1]", config);
		Test.Assert(reader.Next() case .Ok(.StartArray));
		Test.Assert(reader.Next() case .Ok(.StartArray));
		Test.Assert(reader.SkipValue() case .Err(let skipped) && skipped.mKind == .Noncharacter);
	}

	[Test]
	public static void NonFinite_ReadAndWrite()
	{
		var config = JsonReadConfig();
		config.AllowNonFiniteNumbers = true;
		let text = "[NaN, Infinity, -Infinity, 1.5]";
		for (int chunk < 2)
		{
			let doc = scope JsonDocument();
			if (chunk == 0)
				Test.Assert(doc.Read(text, config) case .Ok);
			else
			{
				var streamConfig = config;
				streamConfig.StreamBufferBytes = 16;
				Test.Assert(doc.Read(scope JsonTestStream(text, 1), streamConfig) case .Ok);
			}
			Test.Assert(doc.Root[0].NumberKind == .NonFinite && doc.Root[0].GetDouble().IsNaN);
			Test.Assert(doc.Root[1].GetDouble() == double.PositiveInfinity && doc.Root[2].GetDouble() == double.NegativeInfinity);
			// Writing them is the writer's choice: an error by default (the output stays JSON)
			Test.Assert(doc.Write(scope String()) case .Err(let error) && error.mKind == .NonFiniteNumber);
			var tokens = JsonWriteOptions();
			tokens.NonFiniteNumbers = .Tokens;
			Test.Assert(doc.Write(.. scope .(), tokens) == "[NaN,Infinity,-Infinity,1.5]");
			var nulls = JsonWriteOptions();
			nulls.NonFiniteNumbers = .Null;
			Test.Assert(doc.Write(.. scope .(), nulls) == "[null,null,null,1.5]");
		}
		// A document read with PreserveStyle writes them back as they were
		var preserve = config;
		preserve.MetadataMode = .PreserveStyle;
		let kept = scope JsonDocument();
		Test.Assert(kept.Read(text, preserve) case .Ok);
		Test.Assert(kept.Write(.. scope .()) == text);
	}
}
