using System;
using static JsonBeef.Tests.JsonTestUtil;

namespace JsonBeef.Tests;

// The [JsonObject] types of E087-E089

[JsonObject]
class EdgeInt
{
	public int x;
}

[JsonObject]
class EdgeSmall
{
	public uint8 b;
	public uint32 u;
}

/// An integer written as a string holding a JSON integer (`"12"`); numbers read too.
struct EdgeQuotedInt : IJsonConverter<int>
{
	public static Result<void, JsonParseError> Read(JsonReader reader, ref int target)
	{
		if (reader.TokenType == .Number && reader.TryGetInt64(let number))
		{
			target = (int)number;
			return .Ok;
		}
		StringView text = reader.StringValue;
		int64 value = 0;
		if (reader.TokenType != .String || !JsonNumber.IsValid(text) || JsonNumber.Classify(text) != .Integer || !JsonNumber.TryParseInt64(text, out value))
			return .Err(JsonBind.Mismatch(reader, "an integer, or a string holding one"));
		target = (int)value;
		return .Ok;
	}

	public static void Write(int value, JsonWriter writer)
	{
		writer.WriteString(scope $"{value}");
	}
}

[JsonObject]
class EdgeQuoted
{
	[JsonUseConverter(typeof(EdgeQuotedInt))] public int x;
	[JsonUseConverter(typeof(EdgeQuotedInt))] public int y;
}

/// docs/spec-reference.md §16, one test per edge case (numbered as there). Each input is read from
/// memory and through 1-byte stream reads, which must agree. Cases for features of later phases (the
/// writer's JCS mode, JSON Pointer, JSONC, JSON5, sequences, typed binding) are added with them.
static class JsonEdgeCaseTests
{
	// Document level, whitespace, BOM

	[Test]
	public static void E001_Empty()
	{
		Rejects("", .UnexpectedEndOfInput, 1, 1);
	}

	[Test]
	public static void E002_OnlySpace()
	{
		Rejects(" ", .UnexpectedEndOfInput, 1, 2);
	}

	[Test]
	public static void E003_TopLevelScalars()
	{
		Accepts("null", "null");
		Accepts("true", "true");
		Accepts("false", "false");
		Accepts("\"a\"", "\"a\"");
		Accepts("42", "42");
		Accepts("-0.1", "-0.1");
	}

	[Test]
	public static void E004_AllFourWhitespaces()
	{
		Accepts(" \t\r\n[1]\r\n\t ", "[ 1 ]");
	}

	[Test]
	public static void E005_FormFeedIsNotWhitespace()
	{
		Rejects("\f[]", .UnexpectedChar, 1, 1);
		Rejects("[\f]", .UnexpectedChar, 1, 2);
	}

	[Test]
	public static void E006_VerticalTabIsNotWhitespace()
	{
		Rejects("[\v1]", .UnexpectedChar, 1, 2);
	}

	[Test]
	public static void E007_NoBreakSpaceIsNotWhitespace()
	{
		Rejects("\u{A0}[]", .UnexpectedChar, 1, 1);
	}

	[Test]
	public static void E008_WordJoinerIsNotWhitespace()
	{
		Rejects("[\u{2060}]", .UnexpectedChar, 1, 2);
	}

	[Test]
	public static void E009_BomSkipped()
	{
		Accepts("\xEF\xBB\xBF{}", "{ }");
		var config = JsonReadConfig();
		config.AllowBom = false;
		Rejects("\xEF\xBB\xBF{}", .UnexpectedChar, 1, 1, 0, config);
	}

	[Test]
	public static void E010_BomWithoutValue()
	{
		Rejects("\xEF\xBB\xBF", .UnexpectedEndOfInput, 1, 1);
	}

	[Test]
	public static void E011_TruncatedBom()
	{
		Rejects("\xEF\xBB{}", .InvalidUtf8, 1, 1);
	}

	[Test]
	public static void E012_SecondBomIsNotWhitespace()
	{
		Rejects("\xEF\xBB\xBF\xEF\xBB\xBF{}", .UnexpectedChar, 1, 1, 3);
	}

	[Test]
	public static void E013_Utf16Rejected()
	{
		Rejects("\xFF\xFE[\0]\0", .UnsupportedEncoding, 1, 1);
	}

	[Test]
	public static void E014_ContentAfterValue()
	{
		Rejects("[1]x", .InvalidStructure, 1, 4);
		Rejects("{}}", .InvalidStructure, 1, 3);
		Rejects("[1]]", .InvalidStructure, 1, 4);
	}

	[Test]
	public static void E015_TwoValues()
	{
		Rejects("[][]", .InvalidStructure, 1, 3);
		Rejects("{} {}", .InvalidStructure, 1, 4);
		Rejects("1 2", .InvalidStructure, 1, 3);
	}

	[Test]
	public static void E016_NulIsNotWhitespace()
	{
		Rejects("123\0", .InvalidStructure, 1, 4);
		Rejects("[1]\0", .InvalidStructure, 1, 4);
	}

	[Test]
	public static void E017_DepthLimit()
	{
		let ok = scope String();
		Repeat("[", 1024, ok);
		Repeat("]", 1024, ok);
		Accepts(ok);
		let deep = scope String();
		Repeat("[", 1025, deep);
		Repeat("]", 1025, deep);
		Rejects(deep, .ResourceLimitExceeded, 1, 1025, 1024);
	}

	[Test]
	public static void E018_HundredThousandOpenArrays()
	{
		let text = scope String();
		Repeat("[", 100000, text);
		Rejects(text, .ResourceLimitExceeded, 1, 1025);
	}

	[Test]
	public static void E019_EndOfInputInArray()
	{
		Rejects("[\"a\"", .UnexpectedEndOfInput, 1, 5);
	}

	[Test]
	public static void E020_EndOfInputInObject()
	{
		Rejects("{\"a\":1\n", .UnexpectedEndOfInput, 2, 1);
	}

	// Literals

	[Test]
	public static void E021_IncompleteLiterals()
	{
		Rejects("[nul]", .InvalidLiteral, 1, 2);
		Rejects("[tru]", .InvalidLiteral, 1, 2);
		Rejects("[fals]", .InvalidLiteral, 1, 2);
	}

	[Test]
	public static void E022_LiteralsAreLowercase()
	{
		Rejects("True", .InvalidLiteral, 1, 1);
		Rejects("NULL", .InvalidLiteral, 1, 1);
		Rejects("FALSE", .InvalidLiteral, 1, 1);
	}

	[Test]
	public static void E023_TrailingCharactersOnLiterals()
	{
		Rejects("nulll", .InvalidLiteral, 1, 1);
		Rejects("truex", .InvalidLiteral, 1, 1);
	}

	[Test]
	public static void E024_LiteralsNeedSeparators()
	{
		Rejects("[truefalse]", .InvalidLiteral, 1, 2);
		Accepts("[true,false]", "[ true false ]");
	}

	[Test]
	public static void E025_MissingComma()
	{
		Rejects("[true false]", .InvalidStructure, 1, 7);
	}

	// Arrays and objects

	[Test]
	public static void E026_TrailingCommaInArray()
	{
		Rejects("[1,]", .InvalidStructure, 1, 4);
	}

	[Test]
	public static void E027_TwoTrailingCommas()
	{
		Rejects("[1,,]", .InvalidStructure, 1, 4);
	}

	[Test]
	public static void E028_LeadingComma()
	{
		Rejects("[,]", .InvalidStructure, 1, 2);
		Rejects("[,1]", .InvalidStructure, 1, 2);
	}

	[Test]
	public static void E029_MissingValue()
	{
		Rejects("[1,,2]", .InvalidStructure, 1, 4);
	}

	[Test]
	public static void E030_TrailingCommaInObject()
	{
		Rejects("{\"a\":1,}", .InvalidStructure, 1, 8);
	}

	[Test]
	public static void E031_LoneCommaInObject()
	{
		Rejects("{,}", .InvalidStructure, 1, 2);
	}

	[Test]
	public static void E032_ColonExpected()
	{
		Rejects("{\"a\" 1}", .InvalidStructure, 1, 6);
		Rejects("{\"a\"::1}", .InvalidStructure, 1, 6);
		Rejects("{\"a\",1}", .InvalidStructure, 1, 5);
	}

	[Test]
	public static void E033_UnquotedName()
	{
		Rejects("{a:1}", .InvalidStructure, 1, 2);
	}

	[Test]
	public static void E034_NonStringNames()
	{
		Rejects("{1:1}", .InvalidStructure, 1, 2);
		Rejects("{null:1}", .InvalidStructure, 1, 2);
		Rejects("{[]:1}", .InvalidStructure, 1, 2);
	}

	[Test]
	public static void E035_SingleQuotedName()
	{
		Rejects("{'a':1}", .InvalidStructure, 1, 2);
	}

	[Test]
	public static void E036_CommaExpected()
	{
		Rejects("{\"a\":1 \"b\":2}", .InvalidStructure, 1, 8);
	}

	[Test]
	public static void E037_EmptyName()
	{
		Accepts("{\"\":0}", "{ : 0 }");
	}

	[Test]
	public static void E038_DuplicateNamesKept()
	{
		Accepts("{\"a\":1,\"a\":2}", "{ a: 1 a: 2 }");
		let doc = scope JsonDocument();
		Test.Assert(doc.Read("{\"a\":1,\"a\":2}") case .Ok);
		Test.Assert(doc.Root.Count == 2 && doc.Root["a"].GetInt64() == 2);
		var config = JsonReadConfig();
		config.DuplicateNames = .Error;
		Test.Assert(doc.Read("{\"a\":1,\"a\":2}", config) case .Err(let error) && error.mKind == .DuplicateName && error.mLine == 1 && error.mColumn == 8);
		config.DuplicateNames = .FirstWins;
		Test.Assert(doc.Read("{\"a\":1,\"a\":2}", config) case .Ok);
		Test.Assert(doc.Root.Count == 1 && doc.Root["a"].GetInt64() == 1);
		config.DuplicateNames = .LastWins;
		Test.Assert(doc.Read("{\"a\":1,\"b\":0,\"a\":2}", config) case .Ok);
		Test.Assert(doc.Root.Count == 2 && doc.Root["a"].GetInt64() == 2 && doc.Root[0].Name == "b");
	}

	[Test]
	public static void E039_DuplicateAfterUnescaping()
	{
		let reader = scope JsonReader("{\"a\":1,\"\\u0061\":2}");
		Test.Assert(reader.Next() case .Ok(.StartObject));
		Test.Assert(reader.Next() case .Ok(.PropertyName) && reader.StringValue == "a" && !reader.ValueIsEscaped);
		Test.Assert(reader.Next() case .Ok(.Number));
		Test.Assert(reader.Next() case .Ok(.PropertyName) && reader.StringValue == "a" && reader.ValueIsEscaped && reader.RawValue == "\\u0061");
	}

	[Test]
	public static void E040_NoNormalization()
	{
		Accepts("{\"\u{E9}\":1,\"e\u{301}\":2}", "{ \u{E9}: 1 e\u{301}: 2 }");
	}

	[Test]
	public static void E041_ProtoIsOrdinary()
	{
		Accepts("{\"__proto__\":{\"x\":1}}", "{ __proto__: { x: 1 } }");
	}

	[Test]
	public static void E042_DeepUnclosedArrayObject()
	{
		let text = scope String();
		Repeat("[{\"\":", 50000, text);
		Rejects(text, .ResourceLimitExceeded, 1, 2561);
	}

	// Number grammar

	[Test]
	public static void E043_LoneMinus()
	{
		Rejects("-", .InvalidNumber, 1, 2);
	}

	[Test]
	public static void E044_NegativeZeroInteger()
	{
		let reader = scope JsonReader();
		ReadNumber(reader, "-0");
		Test.Assert(IsInt64(reader, 0));
		Test.Assert(DoubleBits("-0") == 0x8000000000000000UL);
	}

	[Test]
	public static void E045_NegativeZeroFloat()
	{
		Test.Assert(DoubleBits("-0.0") == 0x8000000000000000UL);
		Test.Assert(DoubleBits("-0e5") == 0x8000000000000000UL);
	}

	[Test]
	public static void E046_LeadingZeros()
	{
		Rejects("00", .InvalidNumber, 1, 1);
		Rejects("01", .InvalidNumber, 1, 1);
		Rejects("-01", .InvalidNumber, 1, 1);
	}

	[Test]
	public static void E047_DigitAfterPoint()
	{
		Rejects("0.", .InvalidNumber, 1, 3);
		Rejects("1.", .InvalidNumber, 1, 3);
		Rejects("-2.", .InvalidNumber, 1, 4);
	}

	[Test]
	public static void E048_DigitBeforePoint()
	{
		Rejects(".5", .InvalidNumber, 1, 1);
		Rejects("-.5", .InvalidNumber, 1, 2);
	}

	[Test]
	public static void E049_DigitInExponent()
	{
		Rejects("1e", .InvalidNumber, 1, 3);
		Rejects("1e+", .InvalidNumber, 1, 4);
		Rejects("1E-", .InvalidNumber, 1, 4);
		Rejects("0.3e", .InvalidNumber, 1, 5);
	}

	[Test]
	public static void E050_Exponents()
	{
		let reader = scope JsonReader();
		for (let text in StringView[]("1E+2", "1e+02", "1e2"))
		{
			ReadNumber(reader, text);
			Test.Assert(reader.NumberKind == .Float && IsDouble(reader, 100));
		}
	}

	[Test]
	public static void E051_PlusSign()
	{
		Rejects("+1", .InvalidNumber, 1, 1);
	}

	[Test]
	public static void E052_Hexadecimal()
	{
		Rejects("0x1F", .InvalidNumber, 1, 2);
	}

	[Test]
	public static void E053_MalformedNumbers()
	{
		Rejects("1_000", .InvalidNumber, 1, 2);
		Rejects("1 000", .InvalidStructure, 1, 3);
		Rejects("1.2.3", .InvalidNumber, 1, 4);
		Rejects("1e2.3", .InvalidNumber, 1, 4);
		Rejects("- 1", .InvalidNumber, 1, 2);
	}

	[Test]
	public static void E054_NonAsciiDigits()
	{
		Rejects("\u{FF11}", .UnexpectedChar, 1, 1);
		Rejects("\u{663}", .UnexpectedChar, 1, 1);
	}

	[Test]
	public static void E055_NonFiniteNames()
	{
		Rejects("NaN", .InvalidNumber, 1, 1);
		Rejects("Infinity", .InvalidNumber, 1, 1);
		Rejects("-Infinity", .InvalidNumber, 1, 1);
		// AllowNonFiniteNumbers: numbers of kind NonFinite with the values they name
		var config = JsonReadConfig();
		config.AllowNonFiniteNumbers = true;
		Accepts("[NaN, Infinity, -Infinity]", "[ NaN Infinity -Infinity ]", config);
		let reader = scope JsonReader("[NaN,Infinity,-Infinity]", config);
		Test.Assert(reader.Next() case .Ok(.StartArray));
		double value = 0;
		Test.Assert(reader.Next() case .Ok(.Number));
		Test.Assert(reader.NumberKind == .NonFinite && reader.TryGetDouble(out value) && value.IsNaN);
		Test.Assert(reader.Next() case .Ok(.Number));
		Test.Assert(reader.TryGetDouble(out value) && value == double.PositiveInfinity);
		Test.Assert(reader.Next() case .Ok(.Number));
		Test.Assert(reader.GetDouble() == .Ok(double.NegativeInfinity));
		Rejects("NaNa", .InvalidNumber, 1, 1, -1, config);
		Rejects("[Infinit]", .InvalidNumber, 1, 2, -1, config);
	}

	[Test]
	public static void E056_NonFiniteVariants()
	{
		Rejects("-NaN", .InvalidNumber, 1, 2);
		Rejects("+Infinity", .InvalidNumber, 1, 1);
		Rejects("Inf", .InvalidLiteral, 1, 1);
		Rejects("nan", .InvalidLiteral, 1, 1);
		// Not with AllowNonFiniteNumbers either (`-NaN` and `+Infinity` are JSON5's)
		var config = JsonReadConfig();
		config.AllowNonFiniteNumbers = true;
		Rejects("-NaN", .InvalidNumber, 1, 2, -1, config);
		Rejects("+Infinity", .InvalidNumber, 1, 1, -1, config);
		Rejects("Inf", .InvalidNumber, 1, 1, -1, config);
		Rejects("nan", .InvalidLiteral, 1, 1, -1, config);
	}

	[Test]
	public static void E057_ExponentWithLeadingZeros()
	{
		let reader = scope JsonReader();
		ReadNumber(reader, "1e0000000000000000000000000001");
		Test.Assert(IsDouble(reader, 10));
	}

	[Test]
	public static void E058_HugeExponentIsOutOfRange()
	{
		let text = "[0.4e00669999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999969999999006]";
		Accepts(text);
		let reader = scope JsonReader(text);
		Test.Assert(reader.Next() case .Ok(.StartArray));
		Test.Assert(reader.Next() case .Ok(.Number) && reader.NumberKind == .Float);
		Test.Assert(!reader.TryGetDouble(?));
		Test.Assert(reader.GetDouble() case .Err(let error) && error.mKind == .NumberOutOfRange && error.mColumn == 2);
	}

	// Number values

	[Test]
	public static void E059_Int64Exact()
	{
		let reader = scope JsonReader();
		ReadNumber(reader, "9007199254740993");
		Test.Assert(IsInt64(reader, 9007199254740993));
		Test.Assert(DoubleBits("9007199254740993") == 0x4340000000000000UL);
	}

	[Test]
	public static void E060_Int64Max()
	{
		let reader = scope JsonReader();
		ReadNumber(reader, "9223372036854775807");
		Test.Assert(IsInt64(reader, int64.MaxValue));
	}

	[Test]
	public static void E061_Int64Min()
	{
		let reader = scope JsonReader();
		ReadNumber(reader, "-9223372036854775808");
		Test.Assert(IsInt64(reader, int64.MinValue));
	}

	[Test]
	public static void E062_UInt64()
	{
		let reader = scope JsonReader();
		ReadNumber(reader, "9223372036854775808");
		Test.Assert(IsUInt64(reader, 9223372036854775808UL));
		Test.Assert(!reader.TryGetInt64(?));
		Test.Assert(DoubleBits("9223372036854775808") == 0x43E0000000000000UL);
	}

	[Test]
	public static void E063_UInt64Max()
	{
		let reader = scope JsonReader();
		ReadNumber(reader, "18446744073709551615");
		Test.Assert(IsUInt64(reader, uint64.MaxValue));
	}

	[Test]
	public static void E064_BeyondUInt64()
	{
		let reader = scope JsonReader();
		ReadNumber(reader, "18446744073709551616");
		Test.Assert(reader.NumberKind == .BigInteger && reader.RawValue == "18446744073709551616");
		Test.Assert(!reader.TryGetUInt64(?) && !reader.TryGetInt64(?));
		Test.Assert(DoubleBits("18446744073709551616") == 0x43F0000000000000UL);
	}

	[Test]
	public static void E065_BelowInt64Min()
	{
		let reader = scope JsonReader();
		ReadNumber(reader, "-9223372036854775809");
		Test.Assert(reader.NumberKind == .BigInteger);
		Test.Assert(DoubleBits("-9223372036854775809") == 0xC3E0000000000000UL);
	}

	[Test]
	public static void E066_VeryBigNegative()
	{
		let reader = scope JsonReader();
		ReadNumber(reader, "-237462374673276894279832749832423479823246327846");
		Test.Assert(reader.NumberKind == .BigInteger && reader.RawValue == "-237462374673276894279832749832423479823246327846");
	}

	[Test]
	public static void E067_PointOne()
	{
		Test.Assert(DoubleBits("0.1") == 0x3FB999999999999AUL);
	}

	[Test]
	public static void E068_OneE23()
	{
		Test.Assert(DoubleBits("1e23") == 0x44B52D02C7E14AF6UL);
		Test.Assert(Format(1e23, .EcmaScript, scope .()) == "1e+23");
	}

	[Test]
	public static void E069_BeyondNineteenDigits()
	{
		Test.Assert(DoubleBits("9007199254740993.000000000000000000001") == 0x4340000000000001UL);
	}

	[Test]
	public static void E070_ExactTie()
	{
		Test.Assert(DoubleBits("1.00000000000000011102230246251565404236316680908203125") == 0x3FF0000000000000UL);
		Test.Assert(DoubleBits("1.00000000000000011102230246251565404236316680908203126") == 0x3FF0000000000001UL);
	}

	[Test]
	public static void E071_LargestSubnormal()
	{
		Test.Assert(DoubleBits("2.2250738585072011e-308") == 0x000FFFFFFFFFFFFFUL);
	}

	[Test]
	public static void E072_SmallestNormal()
	{
		Test.Assert(DoubleBits("2.2250738585072012e-308") == 0x0010000000000000UL);
	}

	[Test]
	public static void E073_SmallestSubnormal()
	{
		Test.Assert(DoubleBits("4.9406564584124654e-324") == 1);
	}

	[Test]
	public static void E074_HalfSmallestSubnormal()
	{
		Test.Assert(DoubleBits("2.4703282292062327e-324") == 0);
		Test.Assert(DoubleBits("2.4703282292062328e-324") == 1);
	}

	[Test]
	public static void E075_ExactTieWrittenOut()
	{
		const String tie = "2.4703282292062327208828439643411068618252990130716238221279284125033775363510437593264991818081799618989828234772285886546332835517796989819938739800539093906315035659515570226392290858392449105184435931802849936536152500319370457678249219365623669863658480757001585769269903706311928279558551332927834338409351978015531246597263579574622766465272827220056374006485499977096599470454020828166226237857393450736339007967761930577506740176324673600968951340535537458516661134223766678604162159680461914467291840300530057530849048765391711386591646239524912623653881879636239373280423891018672348497668235089863388587925628302755995657524455507255189313690836254779186948667994968324049705821028513185451396213837722826145437693412532098591327667236328125";
		Test.Assert(DoubleBits(scope $"{tie}e-324") == 0);
		Test.Assert(DoubleBits(scope $"{tie}1e-324") == 1);
	}

	[Test]
	public static void E076_LongMantissa()
	{
		let text = scope String("1");
		Repeat("0", 800, text);
		text.Append("e-800");
		Test.Assert(DoubleBits(text) == 0x3FF0000000000000UL);
	}

	[Test]
	public static void E077_LongFractionUnderflows()
	{
		let text = scope String("0.");
		Repeat("0", 10000, text);
		text.Append('1');
		Test.Assert(DoubleBits(text) == 0);
	}

	[Test]
	public static void E078_UnderflowToSignedZero()
	{
		Test.Assert(DoubleBits("1e-400") == 0);
		Test.Assert(DoubleBits("-1e-400") == 0x8000000000000000UL);
	}

	[Test]
	public static void E079_HugeNegativeExponents()
	{
		Test.Assert(DoubleBits("123.456e-789") == 0);
		Test.Assert(DoubleBits("123e-10000000") == 0);
	}

	[Test]
	public static void E080_LargestFinite()
	{
		Test.Assert(DoubleBits("1.7976931348623157e308") == 0x7FEFFFFFFFFFFFFFUL);
		Test.Assert(DoubleBits("1.7976931348623158e308") == 0x7FEFFFFFFFFFFFFFUL);
	}

	[Test]
	public static void E081_OverflowIsOutOfRange()
	{
		let reader = scope JsonReader();
		for (let text in StringView[]("1.7976931348623159e308", "1e309", "1.5e+9999", "-1e+9999", "123123e100000"))
		{
			ReadNumber(reader, text);
			Test.Assert(!reader.TryGetDouble(?), scope $"`{text}` is in range");
			Test.Assert(reader.GetDouble() case .Err(let error) && error.mKind == .NumberOutOfRange);
			Test.Assert(!JsonNumber.ParseDouble(text, let infinity) && infinity.IsInfinity);
		}
	}

	[Test]
	public static void E082_ZeroWithHugeExponent()
	{
		Test.Assert(DoubleBits("0e999999999999999999999") == 0);
	}

	[Test]
	public static void E083_ExponentSaturation()
	{
		Test.Assert(DoubleBits("1e-2147483649") == 0);
		Test.Assert(DoubleBits("1e-9223372036854775808") == 0);
	}

	[Test]
	public static void E084_LeadingFractionZeros()
	{
		Test.Assert(DoubleBits("0.0000000000000000000000000000000000000000000000000123e50") == 0x3FF3AE147AE147AEUL);
	}

	[Test]
	public static void E085_BigIntegerDouble()
	{
		let reader = scope JsonReader();
		ReadNumber(reader, "123456789012345678901234567890");
		Test.Assert(reader.NumberKind == .BigInteger);
		Test.Assert(DoubleBits("123456789012345678901234567890") == 0x45F8EE90FF6C373EUL);
	}

	[Test]
	public static void E086_FloatParsedDirectly()
	{
		Test.Assert(JsonNumber.ParseFloat("7.038531e-26", var value));
		Test.Assert(*(uint32*)&value == 0x15AE43FD);
	}

	// Typed binding ([JsonObject]), from memory and through 1-byte stream reads

	static JsonErrorKind BindError<T>(T target, StringView text) where T : class, IJsonSerializable
	{
		JsonErrorKind kind = (JsonErrorKind)255;
		for (int chunk < 2)
		{
			Result<void, JsonParseError> result;
			if (chunk == 0)
				result = JsonSerializer.Read(text, target);
			else
			{
				var config = JsonReadConfig();
				config.StreamBufferBytes = 16;
				result = JsonSerializer.Read(scope JsonTestStream(text, 1), target, config);
			}
			let found = result case .Err(let error) ? error.mKind : (JsonErrorKind)255;
			Test.Assert(chunk == 0 || found == kind, "the stream read differs");
			kind = found;
		}
		return kind;
	}

	[Test]
	public static void E087_FractionIntoInteger()
	{
		Test.Assert(BindError(scope EdgeInt(), "{\"x\":1.0}") == .TypeMismatch);
		Test.Assert(BindError(scope EdgeInt(), "{\"x\":1e2}") == .TypeMismatch);
		let value = scope EdgeInt();
		Test.Assert(JsonSerializer.Read("{\"x\":-7}", value) case .Ok && value.x == -7);
	}

	[Test]
	public static void E088_IntegerRanges()
	{
		Test.Assert(BindError(scope EdgeSmall(), "{\"b\":300}") == .NumberOutOfRange);
		Test.Assert(BindError(scope EdgeSmall(), "{\"u\":-1}") == .NumberOutOfRange);
		let value = scope EdgeSmall();
		Test.Assert(JsonSerializer.Read("{\"b\":255,\"u\":4294967295}", value) case .Ok && value.b == 255 && value.u == uint32.MaxValue);
	}

	[Test]
	public static void E089_NumberInAString()
	{
		Test.Assert(BindError(scope EdgeInt(), "{\"x\":\"12\"}") == .TypeMismatch);
		// A field opts in with a converter
		let value = scope EdgeQuoted();
		Test.Assert(JsonSerializer.Read("{\"x\":\"12\",\"y\":13}", value) case .Ok && value.x == 12 && value.y == 13);
		Test.Assert(BindError(scope EdgeQuoted(), "{\"x\":\"1.5\"}") == .TypeMismatch);
	}

	// String escapes

	[Test]
	public static void E090_AllowedEscapes()
	{
		Test.Assert(StringOf("\"\\\"\\\\\\/\\b\\f\\n\\r\\t\"", scope .()) == "\"\\/\b\f\n\r\t");
	}

	[Test]
	public static void E091_HexCaseInsensitive()
	{
		Test.Assert(StringOf("\"A\\u00e9\\u00E9\"", scope .()) == "A\u{E9}\u{E9}");
	}

	[Test]
	public static void E092_InvalidEscapes()
	{
		Rejects("\"\\U0041\"", .InvalidEscape, 1, 2);
		Rejects("\"\\x41\"", .InvalidEscape, 1, 2);
		Rejects("\"\\a\"", .InvalidEscape, 1, 2);
		Rejects("\"\\'\"", .InvalidEscape, 1, 2);
		Rejects("\"\\0\"", .InvalidEscape, 1, 2);
		Rejects("\"\\v\"", .InvalidEscape, 1, 2);
	}

	[Test]
	public static void E093_FourHexDigits()
	{
		Rejects("\"\\u004\"", .InvalidEscape, 1, 2);
		Rejects("\"\\u00G1\"", .InvalidEscape, 1, 2);
		Rejects("\"\\u\"", .InvalidEscape, 1, 2);
	}

	[Test]
	public static void E094_UnterminatedEscape()
	{
		Rejects("\"\\", .UnterminatedString, 1, 3);
		Rejects("\"\\\"", .UnterminatedString, 1, 4);
	}

	[Test]
	public static void E095_EscapedTab()
	{
		Rejects("\"\\\t\"", .InvalidEscape, 1, 2);
	}

	[Test]
	public static void E096_EscapedNul()
	{
		let text = StringOf("\"\\u0000\"", scope .());
		Test.Assert(text.Length == 1 && text[0] == '\0');
		let reader = scope JsonReader("{\"a\\u0000b\":1}");
		Test.Assert(reader.Next() case .Ok(.StartObject));
		Test.Assert(reader.Next() case .Ok(.PropertyName) && reader.StringValue == "a\0b");
	}

	[Test]
	public static void E097_SurrogatePair()
	{
		Test.Assert(StringOf("\"\\uD834\\uDD1E\"", scope .()) == "\u{1D11E}");
		Test.Assert(StringOf("\"\\ud834\\uDd1e\"", scope .()) == "\xF0\x9D\x84\x9E");
	}

	[Test]
	public static void E098_LoneHighSurrogate()
	{
		Rejects("\"\\uD834\"", .InvalidSurrogate, 1, 2);
		Test.Assert(StringOf("\"\\uD834\"", scope .(), Surrogates(.Replace)) == "\u{FFFD}");
		let wtf8 = StringOf("\"\\uD834\"", scope .(), Surrogates(.Wtf8));
		Test.Assert(wtf8 == "\xED\xA0\xB4");
		// The writer turns WTF-8 back into the escape, so the text round-trips
		let output = scope String();
		let writer = scope JsonWriter(output);
		writer.WriteString(wtf8);
		Test.Assert(writer.Finish() case .Ok && output == "\"\\ud834\"");
	}

	static JsonReadConfig Surrogates(JsonInvalidSurrogates mode)
	{
		var config = JsonReadConfig();
		config.InvalidSurrogates = mode;
		return config;
	}

	static JsonReadConfig ReplaceUtf8()
	{
		var config = JsonReadConfig();
		config.InvalidUtf8 = .Replace;
		return config;
	}

	[Test]
	public static void E099_LoneLowSurrogate()
	{
		Rejects("\"\\uDD1E\"", .InvalidSurrogate, 1, 2);
	}

	[Test]
	public static void E100_InvertedPair()
	{
		Rejects("\"\\uDD1E\\uD834\"", .InvalidSurrogate, 1, 2);
	}

	[Test]
	public static void E101_HighNotFollowedByLow()
	{
		Rejects("\"\\uD800A\"", .InvalidSurrogate, 1, 2);
		Rejects("\"\\uD800\\uD800\"", .InvalidSurrogate, 1, 2);
		Rejects("\"\\uD800abc\"", .InvalidSurrogate, 1, 2);
		Rejects("\"\\uD800\\n\"", .InvalidSurrogate, 1, 2);
		// One U+FFFD per unpaired escape; what follows it is read as usual
		Test.Assert(StringOf("\"\\uD800A\"", scope .(), Surrogates(.Replace)) == "\u{FFFD}A");
		Test.Assert(StringOf("\"\\uD800\\uD800\"", scope .(), Surrogates(.Replace)) == "\u{FFFD}\u{FFFD}");
		Test.Assert(StringOf("\"\\uDD1E\\uD834\"", scope .(), Surrogates(.Replace)) == "\u{FFFD}\u{FFFD}");
		Test.Assert(StringOf("\"\\uD800\\n\"", scope .(), Surrogates(.Wtf8)) == "\xED\xA0\x80\n");
		// A pair stays a pair
		Test.Assert(StringOf("\"\\uD834\\uDD1E\"", scope .(), Surrogates(.Wtf8)) == "\u{1D11E}");
		// A malformed escape after a high surrogate is still an error
		Rejects("\"\\uD800\\uZZZZ\"", .InvalidEscape, 1, 8, -1, Surrogates(.Replace));
	}

	[Test]
	public static void E102_HighThenRawSupplementary()
	{
		Rejects("\"\\uD800\u{10000}\"", .InvalidSurrogate, 1, 2);
		Test.Assert(StringOf("\"\\uD800\u{10000}\"", scope .(), Surrogates(.Wtf8)) == "\xED\xA0\x80\xF0\x90\x80\x80");
	}

	[Test]
	public static void E103_NoncharactersAreLegal()
	{
		Test.Assert(StringOf("\"\\uFFFF\"", scope .()) == "\u{FFFF}");
		Test.Assert(StringOf("\"\\uFDD0\"", scope .()) == "\u{FDD0}");
		Test.Assert(StringOf("\"\\uDBFF\\uDFFF\"", scope .()) == "\u{10FFFF}");
		// Not I-JSON: raw ones located at the character, escaped ones at the string
		var ijson = JsonReadConfig();
		ijson.IJson = true;
		Rejects("\"\\uFFFF\"", .Noncharacter, 1, 1, -1, ijson);
		Rejects("[\"ab\u{FDD0}\"]", .Noncharacter, 1, 5, -1, ijson);
		Rejects("{\"\u{10FFFE}\": 1}", .Noncharacter, 1, 3, -1, ijson);
		Rejects("\"\\uD83F\\uDFFF\"", .Noncharacter, 1, 1, -1, ijson);
		// Neighbors are fine
		Test.Assert(StringOf("\"\u{FDCF}\u{FDF0}\u{FFFD}\u{10FFFD}\"", scope .(), ijson) == "\u{FDCF}\u{FDF0}\u{FFFD}\u{10FFFD}");
	}

	[Test]
	public static void E104_ZeroWidthNoBreakSpaceInString()
	{
		Test.Assert(StringOf("\"\\uFEFF\"", scope .()) == "\u{FEFF}");
		Test.Assert(StringOf("\"\u{FEFF}\"", scope .()) == "\u{FEFF}");
	}

	// Raw characters in strings

	[Test]
	public static void E105_RawTab()
	{
		Rejects("\"a\tb\"", .ControlCharacterInString, 1, 3);
	}

	[Test]
	public static void E106_RawLineBreaks()
	{
		Rejects("\"a\nb\"", .ControlCharacterInString, 1, 3);
		Rejects("\"a\rb\"", .ControlCharacterInString, 1, 3);
	}

	[Test]
	public static void E107_RawDelete()
	{
		Test.Assert(StringOf("\"\x7F\"", scope .()) == "\x7F");
	}

	[Test]
	public static void E108_RawC1Controls()
	{
		Test.Assert(StringOf("\"\u{80}\u{9F}\"", scope .()) == "\u{80}\u{9F}");
	}

	[Test]
	public static void E109_RawLineSeparators()
	{
		Test.Assert(StringOf("\"\u{2028}\u{2029}\"", scope .()) == "\u{2028}\u{2029}");
	}

	[Test]
	public static void E110_RawTwoByteCharacter()
	{
		Test.Assert(StringOf("\"\xC3\xA9\"", scope .()) == "\u{E9}");
	}

	[Test]
	public static void E111_InvalidBytes()
	{
		Rejects("\"\xFF\"", .InvalidUtf8, 1, 2);
		Rejects("\"\x81\"", .InvalidUtf8, 1, 2);
		Rejects("\"\xE9\"", .InvalidUtf8, 1, 2);
		// InvalidUtf8.Replace: one U+FFFD each, the text around kept
		Test.Assert(StringOf("\"a\xFFb\"", scope .(), ReplaceUtf8()) == "a\u{FFFD}b");
		Test.Assert(StringOf("\"\x81\"", scope .(), ReplaceUtf8()) == "\u{FFFD}");
		Test.Assert(StringOf("\"\xE9t\xE9\\n\"", scope .(), ReplaceUtf8()) == "\u{FFFD}t\u{FFFD}\n");
	}

	[Test]
	public static void E112_Overlong()
	{
		Rejects("\"\xC0\xAF\"", .InvalidUtf8, 1, 2);
		Test.Assert(StringOf("\"\xC0\xAF\"", scope .(), ReplaceUtf8()) == "\u{FFFD}\u{FFFD}");
	}

	[Test]
	public static void E113_EncodedSurrogate()
	{
		Rejects("\"\xED\xA0\x80\"", .InvalidUtf8, 1, 2);
		Test.Assert(StringOf("\"\xED\xA0\x80\"", scope .(), ReplaceUtf8()) == "\u{FFFD}\u{FFFD}\u{FFFD}");
	}

	[Test]
	public static void E114_AboveUnicode()
	{
		Rejects("\"\xF4\x90\x80\x80\"", .InvalidUtf8, 1, 2);
		Test.Assert(StringOf("\"\xF4\x8F\xBF\xBF\"", scope .()) == "\u{10FFFF}");
		Test.Assert(StringOf("\"\xF4\x90\x80\x80\"", scope .(), ReplaceUtf8()) == "\u{FFFD}\u{FFFD}\u{FFFD}\u{FFFD}");
	}

	[Test]
	public static void E115_TruncatedSequence()
	{
		Rejects("\"\xE2\x82\"", .InvalidUtf8, 1, 2);
		Test.Assert(StringOf("\"\xE2\x82\"", scope .(), ReplaceUtf8()) == "\u{FFFD}");
	}

	[Test]
	public static void E116_InvalidOutsideString()
	{
		Rejects("[\xE5]", .InvalidUtf8, 1, 2);
		// Replacement is for strings only
		Rejects("[\xE5]", .InvalidUtf8, 1, 2, -1, ReplaceUtf8());
	}

	[Test]
	public static void E117_SixByteForm()
	{
		Rejects("\"\xFC\x80\x80\x80\x80\x80\"", .InvalidUtf8, 1, 2);
	}

	// Error locations

	[Test]
	public static void E118_LineAndColumn()
	{
		Rejects("[1,\n 2,\n x]", .InvalidLiteral, 3, 2, 9);
	}

	[Test]
	public static void E119_CrLfIsOneLineBreak()
	{
		Rejects("[1,\r\n x]", .InvalidLiteral, 2, 2);
	}

	[Test]
	public static void E120_ColumnsCountCodePoints()
	{
		Rejects("[\"\u{E9}\", x]", .InvalidLiteral, 1, 7, 7);
	}

	[Test]
	public static void E121_InvalidLiteralAtItsStart()
	{
		Rejects("{\"a\":tru}", .InvalidLiteral, 1, 6);
	}

	[Test]
	public static void E122_UnterminatedStringAtEnd()
	{
		Rejects("\"abc", .UnterminatedString, 1, 5);
	}

	// JSONC (Comments, TrailingCommas)

	static JsonReadConfig CommentsOnly()
	{
		var config = JsonReadConfig();
		config.Comments = true;
		return config;
	}

	[Test]
	public static void E123_LineCommentBeforeValue()
	{
		Accepts("// c\n{}", "{ }", CommentsOnly());
		Rejects("// c\n{}", .UnexpectedChar, 1, 1);
	}

	[Test]
	public static void E124_LineCommentAtEnd()
	{
		Accepts("{} // c", "{ }", CommentsOnly());
	}

	[Test]
	public static void E125_BlockCommentBetweenTokens()
	{
		Accepts("[1 /* x */, 2]", "[ 1 2 ]", CommentsOnly());
		Accepts("[1,\r\n/* a\r\n b */\r\n2]", "[ 1 2 ]", CommentsOnly());
	}

	[Test]
	public static void E126_CommentBetweenColonAndValue()
	{
		Rejects("{\"a\":/*c*/\"b\"}", .UnexpectedChar, 1, 6);
		Accepts("{\"a\":/*c*/\"b\"}", "{ a: \"b\" }", CommentsOnly());
	}

	[Test]
	public static void E127_CommentsDoNotNest()
	{
		Rejects("/* /* */ */ 1", .UnexpectedChar, 1, 10, -1, CommentsOnly());
	}

	[Test]
	public static void E128_UnterminatedComment()
	{
		Rejects("/* unterminated 1", .UnterminatedComment, 1, 1, 0, CommentsOnly());
		Rejects("[1, /* x", .UnterminatedComment, 1, 5, 4, CommentsOnly());
	}

	[Test]
	public static void E129_SlashAfterValue()
	{
		Accepts("{\"a\":\"b\"}/**/", "{ a: \"b\" }", CommentsOnly());
		Rejects("{\"a\":\"b\"}/**//", .UnexpectedChar, 1, 14, -1, CommentsOnly());
		Rejects("{\"a\":\"b\"}/", .UnexpectedChar, 1, 10, -1, CommentsOnly());
	}

	[Test]
	public static void E130_CommentMarkersInStrings()
	{
		Accepts("{\"a\":\"// not a comment\"}", "{ a: \"// not a comment\" }");
		Accepts("{\"a\":\"/* nor this */\"}", "{ a: \"/* nor this */\" }", CommentsOnly());
	}

	[Test]
	public static void E131_HashIsNotAComment()
	{
		Rejects("# c\n{}", .UnexpectedChar, 1, 1);
		Rejects("# c\n{}", .UnexpectedChar, 1, 1, -1, JsonReadConfig.Jsonc);
	}

	[Test]
	public static void E132_OnlyAComment()
	{
		Rejects("// only a comment", .UnexpectedEndOfInput, 1, 18, -1, CommentsOnly());
	}

	[Test]
	public static void E133_TrailingCommasSeparately()
	{
		Rejects("{\"a\":1,}", .InvalidStructure, 1, 8, -1, CommentsOnly());
		Accepts("{\"a\":1,}", "{ a: 1 }", JsonReadConfig.Jsonc);
		Accepts("[1,2,]", "[ 1 2 ]", JsonReadConfig.Jsonc);
		// One comma only, and never alone
		Rejects("[1,,]", .InvalidStructure, JsonReadConfig.Jsonc);
		Rejects("[,]", .InvalidStructure, JsonReadConfig.Jsonc);
		Rejects("{,}", .InvalidStructure, JsonReadConfig.Jsonc);
		var trailingOnly = JsonReadConfig();
		trailingOnly.TrailingCommas = true;
		Accepts("[1,]", "[ 1 ]", trailingOnly);
		Rejects("[1,/**/]", .UnexpectedChar, trailingOnly);
	}

	[Test]
	public static void E133b_CommentsHoldUtf8()
	{
		Accepts("[1 /* é 🎉 */, 2] // ünï", "[ 1 2 ]", CommentsOnly());
		Rejects("[1 /* \xFF */]", .InvalidUtf8, 1, 7, 6, CommentsOnly());
		Rejects("[1] // \xC3", .InvalidUtf8, 1, 8, 7, CommentsOnly());
	}

	// JSON5 (JsonDialect.Json5)

	/// The tokens of a JSON5 text from memory and through 1-byte stream reads (which must agree), with
	/// names and strings decoded and numbers as their JSON text (StringValue).
	static String Json5Trace(StringView text, String trace)
	{
		for (int chunk < 2)
		{
			let reader = scope JsonReader();
			// (The stream lives as long as the reader reads it: not scoped to the `else` below)
			let stream = scope JsonTestStream(text, 1);
			if (chunk == 0)
				reader.Reset(text, JsonReadConfig.Json5);
			else
			{
				var config = JsonReadConfig.Json5;
				config.StreamBufferBytes = 16;
				reader.Reset(stream, config);
			}
			let own = scope String();
			while (true)
			{
				JsonToken token;
				switch (reader.Next())
				{
				case .Ok(let read):
					token = read;
				case .Err(let error):
					Test.FatalError(scope $"`{text}`: {error}");
					return trace;
				}
				if (token == .EndOfDocument)
					break;
				if (!own.IsEmpty)
					own.Append(' ');
				switch (token)
				{
				case .StartObject: own.Append('{');
				case .EndObject: own.Append('}');
				case .StartArray: own.Append('[');
				case .EndArray: own.Append(']');
				case .PropertyName: own.AppendF("{}:", reader.StringValue);
				case .String: own.AppendF("\"{}\"", reader.StringValue);
				default: own.Append(reader.StringValue);
				}
			}
			if (chunk == 0)
				trace.Append(own);
			else
				Test.Assert(own == trace, scope $"`{text}`: the stream read gives `{own}`, memory `{trace}`");
		}
		return trace;
	}

	static void Json5Rejects(StringView text, JsonErrorKind kind, int line = Compiler.CallerLineNum)
	{
		let reader = scope JsonReader(text, JsonReadConfig.Json5);
		while (true)
		{
			switch (reader.Next())
			{
			case .Ok(let token):
				if (token == .EndOfDocument)
				{
					Test.FatalError(scope $"line {line}: `{text}` was accepted");
					return;
				}
			case .Err(let error):
				Test.Assert(error.mKind == kind, scope $"line {line}: `{text}`: {error.mKind} ({error.mMessage}), expected {kind}");
				return;
			}
		}
	}

	[Test]
	public static void E134_Json5IdentifierNames()
	{
		Test.Assert(Json5Trace("{while: true, $_a1: 1, ünï: 2}", scope .()) == "{ while: true $_a1: 1 ünï: 2 }");
		// Escapes of identifier characters, ZWNJ inside, digits after the first
		Test.Assert(Json5Trace("{\\u0061b: 1, a\u{200C}b2: 2, null: null}", scope .()) == "{ ab: 1 a\u{200C}b2: 2 null: null }");
	}

	[Test]
	public static void E135_Json5BadIdentifiers()
	{
		Json5Rejects("{a-b: 1}", .InvalidStructure);
		Json5Rejects("{10twenty: 1}", .InvalidStructure);
		Json5Rejects("{\\u002D: 1}", .InvalidEscape);
		Json5Rejects("{a\\x41: 1}", .InvalidEscape);
	}

	[Test]
	public static void E136_Json5UnicodeIdentifier()
	{
		Test.Assert(Json5Trace("{sigΣma: 1, \\u03A3: 2}", scope .()) == "{ sigΣma: 1 Σ: 2 }");
	}

	[Test]
	public static void E137_Json5SingleQuotes()
	{
		Test.Assert(Json5Trace("['I can\\'t', \"a'b\", 'say \"hi\"']", scope .()) == "[ \"I can't\" \"a'b\" \"say \"hi\"\" ]");
		Test.Assert(Json5Trace("{'key': 'v'}", scope .()) == "{ key: \"v\" }");
	}

	[Test]
	public static void E138_Json5LineContinuations()
	{
		Test.Assert(Json5Trace("'line 1 \\\nline 2'", scope .()) == "\"line 1 line 2\"");
		Test.Assert(Json5Trace("'line 1 \\\rline 2'", scope .()) == "\"line 1 line 2\"");
		Test.Assert(Json5Trace("'line 1 \\\r\nline 2'", scope .()) == "\"line 1 line 2\"");
		Test.Assert(Json5Trace("'line 1 \\\u{2028}line 2'", scope .()) == "\"line 1 line 2\"");
		// A raw line break is still an error; a raw U+2028 and a raw TAB are text
		Json5Rejects("'a\nb'", .ControlCharacterInString);
		Test.Assert(Json5Trace("'a\u{2028}b\tc'", scope .()) == "\"a\u{2028}b\tc\"");
	}

	[Test]
	public static void E139_Json5Escapes()
	{
		Test.Assert(Json5Trace("'\\A\\C\\/\\D\\C'", scope .()) == "\"AC/DC\"");
		Test.Assert(Json5Trace("'\\x41\\xe9\\v\\0'", scope .()) == "\"A\u{E9}\v\0\"");
		Json5Rejects("'\\1'", .InvalidEscape);
		Json5Rejects("'\\01'", .InvalidEscape);
		Json5Rejects("'\\x4'", .InvalidEscape);
	}

	[Test]
	public static void E140_Json5Hexadecimal()
	{
		Test.Assert(Json5Trace("[0xC8, 0XC8, -0xC8, +0xC8, 0xC8e4, -0x0]", scope .()) == "[ 200 200 -200 200 51428 -0 ]");
		// Beyond 64 bits: an exact big integer
		Test.Assert(Json5Trace("0x10000000000000000", scope .()) == "18446744073709551616");
		let doc = scope JsonDocument();
		Test.Assert(doc.Read("[0xFFFFFFFFFFFFFFFF, -0x8000000000000000]", JsonReadConfig.Json5) case .Ok);
		Test.Assert(doc.Root[0].NumberKind == .UInteger && doc.Root[0].GetUInt64() == uint64.MaxValue);
		Test.Assert(doc.Root[1].GetInt64() == int64.MinValue);
		Json5Rejects("0x", .InvalidNumber);
		Json5Rejects("0x1G", .InvalidNumber);
	}

	[Test]
	public static void E141_Json5DecimalPoints()
	{
		Test.Assert(Json5Trace("[.5, 5., +.5, -.0, 5.e4, +1]", scope .()) == "[ 0.5 5.0 0.5 -0.0 5.0e4 1 ]");
		let doc = scope JsonDocument();
		Test.Assert(doc.Read("[.5, 5., -.0, 5.e4]", JsonReadConfig.Json5) case .Ok);
		Test.Assert(doc.Root[0].GetDouble() == 0.5 && doc.Root[1].GetDouble() == 5 && JsonNumber.IsNegative(doc.Root[2].GetDouble()) && doc.Root[3].GetDouble() == 50000);
		Json5Rejects(".", .InvalidNumber);
		Json5Rejects("+", .InvalidNumber);
		Json5Rejects("1..2", .InvalidNumber);
	}

	[Test]
	public static void E142_Json5NoLeadingZeros()
	{
		for (let text in StringView[]("010", "00", "-00", "+0123", "080"))
			Json5Rejects(text, .InvalidNumber);
	}

	[Test]
	public static void E143_Json5NonFinite()
	{
		Test.Assert(Json5Trace("[Infinity, +Infinity, -Infinity, NaN, +NaN, -NaN]", scope .()) == "[ Infinity +Infinity -Infinity NaN +NaN -NaN ]");
		let reader = scope JsonReader("-NaN", JsonReadConfig.Json5);
		Test.Assert(reader.Next() case .Ok(.Number));
		double value = 0;
		Test.Assert(reader.NumberKind == .NonFinite && reader.TryGetDouble(out value) && value.IsNaN);
		Json5Rejects("Infinit", .InvalidNumber);
		Json5Rejects("inf", .InvalidLiteral);
	}

	[Test]
	public static void E144_Json5Whitespace()
	{
		Test.Assert(Json5Trace("[\v\f\u{A0}\u{FEFF}1\u{2028}\u{2029}\u{3000}\u{202F}]", scope .()) == "[ 1 ]");
		Test.Assert(Json5Trace("[1, // to U+2028\u{2028}2]", scope .()) == "[ 1 2 ]");
		// Before the end of an empty container, a name, a colon, a comma, after the document
		Test.Assert(Json5Trace("[\f]", scope .()) == "[ ]");
		Test.Assert(Json5Trace("{\u{A0}}", scope .()) == "{ }");
		Test.Assert(Json5Trace("{\v'a'\u{2029}:\u{3000}1\f, b\u{A0}:2\u{FEFF}}\u{A0}", scope .()) == "{ a: 1 b: 2 }");
	}

	[Test]
	public static void E145_Json5CommentOnly()
	{
		Json5Rejects("/* comment only */", .UnexpectedEndOfInput);
	}

	// Sequences (JsonSequenceReader)

	/// The values of a sequence as compact JSON, one per line, and each error as `!N:line:column`
	/// (N the record), from memory and through 1-byte stream reads (which must agree).
	static String Sequence(StringView text, JsonSequenceMode mode, String output, bool skipEmpty = false)
	{
		for (int chunk < 2)
		{
			let reader = scope JsonSequenceReader(mode);
			reader.SkipEmptyLines = skipEmpty;
			let stream = scope JsonTestStream(text, 1);
			if (chunk == 0)
				reader.Reset(text);
			else
			{
				var config = JsonReadConfig();
				config.StreamBufferBytes = 16;
				reader.Reset(stream, config);
			}
			let own = scope String();
			let doc = scope JsonDocument();
			while (true)
			{
				switch (reader.Next())
				{
				case .Ok(let more):
					if (!more)
						break;
					// (Concatenated values are checked as they are read: an error can come here)
					if (reader.ReadDocument(doc) case .Err(let valueError))
					{
						let located = reader.Locate(valueError);
						own.AppendF("!{}:{}:{}\n", reader.Index, located.mLine, located.mColumn);
						continue;
					}
					doc.Write(own);
					own.Append('\n');
					continue;
				case .Err(let error):
					own.AppendF("!{}:{}:{}\n", reader.Index, error.mLine, error.mColumn);
					continue;
				}
				break;
			}
			if (chunk == 0)
				output.Append(own);
			else
				Test.Assert(own == output, scope $"the stream read gives `{own}`, memory `{output}`");
		}
		return output;
	}

	[Test]
	public static void E146_LinesTwoValues()
	{
		Test.Assert(Sequence("{\"a\":1}\n{\"a\":2}\n", .Lines, scope .()) == "{\"a\":1}\n{\"a\":2}\n");
	}

	[Test]
	public static void E147_LinesBlankLine()
	{
		Test.Assert(Sequence("1\n\n2", .Lines, scope .()) == "1\n!2:2:1\n2\n");
		Test.Assert(Sequence("1\n\n \t\n2", .Lines, scope .(), true) == "1\n2\n");
	}

	[Test]
	public static void E148_LinesOneValuePerLine()
	{
		// The line gives an error, not its first value; the next line is read
		Test.Assert(Sequence("1 2\n3", .Lines, scope .()) == "!1:1:3\n3\n");
		// A value spanning lines is two broken lines
		Test.Assert(Sequence("{\"a\":\n1}", .Lines, scope .()) == "!1:1:6\n!2:2:2\n");
	}

	[Test]
	public static void E149_LinesCrLfWithoutFinalNewline()
	{
		Test.Assert(Sequence("{\"a\":1}\r\n{\"a\":2}", .Lines, scope .()) == "{\"a\":1}\n{\"a\":2}\n");
	}

	[Test]
	public static void E150_RecordSeparated()
	{
		Test.Assert(Sequence("\x1E1\n\x1E2\n", .RecordSeparated, scope .()) == "1\n2\n");
		// Consecutive separators are not empty elements
		Test.Assert(Sequence("\x1E\x1E\x1E[1]\n\x1E", .RecordSeparated, scope .()) == "[1]\n");
	}

	[Test]
	public static void E151_RecordSeparatedTruncatedNumber()
	{
		Test.Assert(Sequence("\x1E123\x1E4\n", .RecordSeparated, scope .()) == "!1:1:5\n4\n");
		// A string, array or object is delimited: no whitespace needed
		Test.Assert(Sequence("\x1E\"a\"\x1E[1]\x1E", .RecordSeparated, scope .()) == "\"a\"\n[1]\n");
	}

	[Test]
	public static void E152_RecordSeparatedGoesOn()
	{
		Test.Assert(Sequence("\x1E{\"a\":\x1E2\n", .RecordSeparated, scope .()) == "!1:1:7\n2\n");
	}

	[Test]
	public static void E153_Concatenated()
	{
		Test.Assert(Sequence("{}{}[]", .Concatenated, scope .()) == "{}\n{}\n[]\n");
		Test.Assert(Sequence("12", .Concatenated, scope .()) == "12\n");
		Test.Assert(Sequence(" 1 2\n\"a\"null ", .Concatenated, scope .()) == "1\n2\n\"a\"\nnull\n");
		Test.Assert(Sequence("", .Concatenated, scope .()) == "");
		// The first error ends the sequence
		Test.Assert(Sequence("[1] [2,] [3]", .Concatenated, scope .()) == "[1]\n!2:1:8\n");
	}

	// Writer

	/// The compact output of `text` read into a document.
	static String Written(StringView text, JsonWriteOptions options, String output)
	{
		let doc = scope JsonDocument();
		Test.Assert(doc.Read(text) case .Ok, scope $"`{text}` was rejected");
		Test.Assert(doc.Write(output, options) case .Ok, scope $"`{text}` could not be written");
		return output;
	}

	[Test]
	public static void E154_InfinityIsAWriteError()
	{
		let output = scope String();
		let writer = scope JsonWriter(output);
		writer.WriteStartArray();
		writer.WriteNumber(double.PositiveInfinity);
		writer.WriteEndArray();
		Test.Assert(writer.Finish() case .Err(let error) && error.mKind == .NonFiniteNumber);
		var options = JsonWriteOptions();
		options.NonFiniteNumbers = .Null;
		let nulls = scope String();
		let nullWriter = scope JsonWriter(nulls, options);
		nullWriter.WriteStartArray();
		nullWriter.WriteNumber(double.PositiveInfinity);
		nullWriter.WriteNumber(double.NaN);
		nullWriter.WriteEndArray();
		Test.Assert(nullWriter.Finish() case .Ok && nulls == "[null,null]");
		options.NonFiniteNumbers = .Tokens;
		let tokens = scope String();
		let tokenWriter = scope JsonWriter(tokens, options);
		tokenWriter.WriteStartArray();
		tokenWriter.WriteNumber(double.NegativeInfinity);
		tokenWriter.WriteNumber(double.NaN);
		tokenWriter.WriteEndArray();
		Test.Assert(tokenWriter.Finish() case .Ok && tokens == "[-Infinity,NaN]");
	}

	[Test]
	public static void E155_ControlCharactersEscaped()
	{
		Test.Assert(Written("\"\\u0000\\u001f\x7F\"", .(), scope .()) == "\"\\u0000\\u001f\x7F\"");
	}

	[Test]
	public static void E156_QuoteBackslashSlash()
	{
		Test.Assert(Written("\"\\\"\\\\\\/\"", .(), scope .()) == "\"\\\"\\\\/\"");
	}

	// Writer number layout

	[Test]
	public static void E157_EcmaScriptLayout()
	{
		Test.Assert(Format(1e21, .EcmaScript, scope .()) == "1e+21");
		Test.Assert(Format(1e20, .EcmaScript, scope .()) == "100000000000000000000");
		Test.Assert(Format(1e-7, .EcmaScript, scope .()) == "1e-7");
		Test.Assert(Format(0.000001, .EcmaScript, scope .()) == "0.000001");
		Test.Assert(Format(5e-324, .EcmaScript, scope .()) == "5e-324");
		Test.Assert(Format(0.1 + 0.2, .EcmaScript, scope .()) == "0.30000000000000004");
	}

	[Test]
	public static void E158_NegativeZero()
	{
		Test.Assert(Format(-0.0, .Plain, scope .()) == "-0.0");
		Test.Assert(Format(-0.0, .EcmaScript, scope .()) == "0");
	}

	[Test]
	public static void E159_IntegersNotThroughDouble()
	{
		Test.Assert(Written("9007199254740993", .(), scope .()) == "9007199254740993");
		Test.Assert(Written("[-0, -0.0, 1.0, 1E2, 18446744073709551616, 1e400]", .(), scope .()) == "[-0,-0.0,1.0,100.0,18446744073709551616,1e400]");
	}

	[Test]
	public static void E160_JcsMemberOrder()
	{
		let text = "{\"\u{20AC}\":1,\"\\r\":2,\"\u{FB33}\":3,\"1\":4,\"\u{1F600}\":5,\"\\u0080\":6,\"\u{F6}\":7}";
		Test.Assert(Written(text, .Jcs, scope .()) == "{\"\\r\":2,\"1\":4,\"\u{80}\":6,\"\u{F6}\":7,\"\u{20AC}\":1,\"\u{1F600}\":5,\"\u{FB33}\":3}");
		// Duplicates cannot be canonical
		let doc = scope JsonDocument();
		Test.Assert(doc.Read("{\"a\":1,\"a\":2}") case .Ok);
		Test.Assert(doc.Write(scope .(), .Jcs) case .Err(let error) && error.mKind == .DuplicateName);
	}

	[Test]
	public static void E161_JcsNumbers()
	{
		Test.Assert(Written("[333333333.33333329,1E30,4.50,2e-3,0.000000000000000000000000001]", .Jcs, scope .()) == "[333333333.3333333,1e+30,4.5,0.002,1e-27]");
		Test.Assert(Written("[-0, 9007199254740993, 18446744073709551616]", .Jcs, scope .()) == "[0,9007199254740992,18446744073709552000]");
		let doc = scope JsonDocument();
		Test.Assert(doc.Read("[1e400]") case .Ok);
		Test.Assert(doc.Write(scope .(), .Jcs) case .Err(let error) && error.mKind == .NumberOutOfRange);
	}

	[Test]
	public static void E162_JcsNumberSamples()
	{
		(uint64 bits, StringView text)[?] samples = .(
			(0x0000000000000000UL, "0"), (0x8000000000000000UL, "0"), (0x7FEFFFFFFFFFFFFFUL, "1.7976931348623157e+308"),
			(0x4340000000000000UL, "9007199254740992"), (0x4430000000000000UL, "295147905179352830000"),
			(0x44B52D02C7E14AF5UL, "9.999999999999997e+22"), (0x444B1AE4D6E2EF4FUL, "999999999999999900000"),
			(0x3EB0C6F7A0B5ED8CUL, "9.999999999999997e-7"), (0x41B3DE4355555554UL, "333333333.33333325"),
			(0xBECBF647612F3696UL, "-0.0000033333333333333333"), (0x43143FF3C1CB0959UL, "1424953923781206.2"));
		for (let sample in samples)
		{
			let text = Format(JsonNumber.FromBits(sample.bits), .EcmaScript, scope .());
			Test.Assert(text == sample.text, scope $"{sample.bits:X16}: `{text}`, expected `{sample.text}`");
		}
	}

	// JSON Pointer

	const String cRfc6901Document = "{\"foo\":[\"bar\",\"baz\"],\"\":0,\"a/b\":1,\"c%d\":2,\"e^f\":3,\"g|h\":4,\"i\\\\j\":5,\"k\\\"l\":6,\" \":7,\"m~n\":8}";

	static JsonNode Pointed(JsonDocument doc, StringView pointer)
	{
		switch (doc.Root.Find(pointer))
		{
		case .Ok(let node):
			return node;
		case .Err(let error):
			Test.FatalError(scope $"`{pointer}`: {error}");
			return default;
		}
	}

	static JsonPointerErrorKind PointerError(JsonDocument doc, StringView pointer)
	{
		switch (doc.Root.Find(pointer))
		{
		case .Ok:
			Test.FatalError(scope $"`{pointer}` found a value");
			return .NotFound;
		case .Err(let error):
			return error.mKind;
		}
	}

	[Test]
	public static void E163_Rfc6901Examples()
	{
		let doc = scope JsonDocument();
		Test.Assert(doc.Read(cRfc6901Document) case .Ok);
		Test.Assert(Pointed(doc, "") == doc.Root);
		Test.Assert(Pointed(doc, "/foo").IsArray);
		Test.Assert(Pointed(doc, "/foo/0").GetString() == "bar");
		Test.Assert(Pointed(doc, "/").GetInt64(-1) == 0);
		Test.Assert(Pointed(doc, "/a~1b").GetInt64() == 1);
		Test.Assert(Pointed(doc, "/c%d").GetInt64() == 2);
		Test.Assert(Pointed(doc, "/e^f").GetInt64() == 3);
		Test.Assert(Pointed(doc, "/g|h").GetInt64() == 4);
		Test.Assert(Pointed(doc, "/i\\j").GetInt64() == 5);
		Test.Assert(Pointed(doc, "/k\"l").GetInt64() == 6);
		Test.Assert(Pointed(doc, "/ ").GetInt64() == 7);
		Test.Assert(Pointed(doc, "/m~0n").GetInt64() == 8);
	}

	[Test]
	public static void E164_TildeOneDecodedFirst()
	{
		let doc = scope JsonDocument();
		Test.Assert(doc.Read("{\"~1\":1,\"/\":2}") case .Ok);
		Test.Assert(Pointed(doc, "/~01").GetInt64() == 1);
	}

	[Test]
	public static void E165_ArrayIndexes()
	{
		let doc = scope JsonDocument();
		Test.Assert(doc.Read(cRfc6901Document) case .Ok);
		Test.Assert(PointerError(doc, "/foo/01") == .InvalidIndex);
		Test.Assert(PointerError(doc, "/foo/-1") == .InvalidIndex);
		Test.Assert(PointerError(doc, "/foo/1e0") == .InvalidIndex);
		Test.Assert(PointerError(doc, "/foo/-") == .NotFound);
		Test.Assert(PointerError(doc, "/foo/2") == .NotFound);
		Test.Assert(PointerError(doc, "/foo/0/x") == .NotAContainer);
	}

	[Test]
	public static void E166_InvalidSyntax()
	{
		let doc = scope JsonDocument();
		Test.Assert(doc.Read(cRfc6901Document) case .Ok);
		Test.Assert(PointerError(doc, "foo") == .InvalidSyntax);
		Test.Assert(PointerError(doc, "/~2") == .InvalidSyntax);
		Test.Assert(PointerError(doc, "/~") == .InvalidSyntax);
		Test.Assert(!JsonPointer.IsValid("foo") && JsonPointer.IsValid("/a~0~1") && JsonPointer.IsValid(""));
	}

	[Test]
	public static void E167_NumericTokenOnObject()
	{
		let doc = scope JsonDocument();
		Test.Assert(doc.Read("{\"0\":1}") case .Ok);
		Test.Assert(Pointed(doc, "/0").GetInt64() == 1);
	}
}
