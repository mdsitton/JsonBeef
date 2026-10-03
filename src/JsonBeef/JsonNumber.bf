using System;
using FormatCore;
using internal FormatCore;
using internal JsonBeef;

namespace JsonBeef;

/// @brief What a number token holds, decided by the reader from its text.
public enum JsonNumberKind : uint8
{
	/// @brief An integer token (no fraction or exponent) whose value fits `int64`. `-0` is one, with
	/// value 0 (its double is −0.0).
	Integer,
	/// @brief An integer token from 2^63 to 2^64 − 1: fits `uint64` only.
	UInteger,
	/// @brief A token with a fraction or an exponent. Its double may be out of range (`1e400`).
	Float,
	/// @brief An integer token beyond the 64-bit types. Its text is exact; its double is approximate.
	BigInteger,
	/// @brief `NaN`, `Infinity` or `-Infinity` (JsonReadConfig.AllowNonFiniteNumbers; JSON5 adds `+`
	/// and `-NaN`): not JSON, read only when asked for. Its double is the NaN or infinity it names.
	NonFinite
}

/// @brief How doubles are written.
public enum JsonFloatFormat : uint8
{
	/// @brief Shortest round-trip digits; an integral value keeps `.0` and negative zero is `-0.0`, so a
	/// float stays a float (`1.0`, `100.0`, `1e21`, `1.5e-7`, `5e-324`). Fixed notation for decimal
	/// exponents from −6 to 21, as ECMAScript; the exponent has no `+` and no padding.
	Plain,
	/// @brief ECMAScript's `Number::toString` (RFC 8785, JSON.stringify): `1`, `100`, `1e+21`, `1.5e-7`,
	/// negative zero as `0`.
	EcmaScript
}

/// @brief Number conversion and formatting: exact integers, correctly rounded doubles and floats, and
/// shortest round-trip output. Conversions take a validated JSON number token (the reader's
/// `RawValue`); they never see non-JSON text. The arithmetic is FormatCore's (`DecimalParse`,
/// `ShortestDouble`, `BigDecimal`, `FloatBits`), which came from here: Clinger's fast path with the
/// exponent extension, corlib's fast_float through `[Friend]` with `.` pinned (no culture), zmij's
/// shortest digits.
public static class JsonNumber
{
	/// @brief The correctly rounded double of a JSON number token (round to nearest, ties to even): an
	/// overflow gives ±∞ and an underflow ±0, as IEEE 754 rounding does.
	/// @param token A token that matches the JSON number grammar.
	/// @param value Receives the double.
	/// @return Whether the value is finite (false: it overflowed to ±∞).
	public static bool ParseDouble(StringView token, out double value)
	{
		if (!DecimalParse.ParseDouble(token, out value, false))
			Runtime.FatalError("JsonNumber.ParseDouble: the token is not a JSON number");
		return !value.IsInfinity;
	}

	/// The general path: corlib's fast_float (correctly rounded for any length) on the unsigned text.
	/// Inlined into the fast build (out of line it cost canada's document read 2.5%).
	[Inline]
	internal static bool ParseDoubleSlow(StringView token, out double value)
	{
		if (!DecimalParse.ParseDoubleSlow(token, out value, false))
			Runtime.FatalError("JsonNumber.ParseDouble: the token is not a JSON number");
		return !value.IsInfinity;
	}

	/// The slow path for the reader, out of line and calling corlib directly (with `.` pinned, as
	/// DecimalParse does): through DecimalParse (inlined or not) the reader's number-heavy events cost
	/// 0.3-0.8% more, a code-layout effect measured on canada and floats.
	[NoInline]
	internal static bool ParseDoubleSlowOutOfLine(StringView token, out double value)
	{
		bool negative = token[0] == '-';
		char8* text = token.Ptr + (negative ? 1 : 0);
		int length = token.Length - (negative ? 1 : 0);
		double result = 0;
		if (!double.[Friend]Parse(text, (int32)length, '.', &result))
			Runtime.FatalError("JsonNumber.ParseDouble: the token is not a JSON number");
		value = negative ? -result : result;
		return !result.IsInfinity;
	}

	/// @brief The correctly rounded float (binary32) of a JSON number token, parsed directly: through a
	/// double it would round twice (`7.038531e-26`).
	/// @param token A token that matches the JSON number grammar.
	/// @param value Receives the float.
	/// @return Whether the value is finite.
	public static bool ParseFloat(StringView token, out float value)
	{
		if (!DecimalParse.ParseFloat32(token, out value, false))
			Runtime.FatalError("JsonNumber.ParseFloat: the token is not a JSON number");
		return !value.IsInfinity;
	}

	/// Clinger's fast path on a mantissa and decimal exponent (value = ±mantissa × 10^exponent), for the
	/// reader and the fast build, which gather them while scanning the token.
	[Inline]
	internal static bool TryClinger(uint64 mantissa, int exponent, bool negative, out double value)
	{
		return DecimalParse.TryClinger(mantissa, exponent, negative, out value);
	}

	/// @brief The int64 of an integer token, if it fits.
	/// @param token A JSON integer token (no fraction or exponent).
	/// @param value Receives the value.
	/// @return Whether it fits.
	public static bool TryParseInt64(StringView token, out int64 value)
	{
		return DecimalParse.TryParseInt64(token, out value, false);
	}

	/// @brief The uint64 of an integer token, if it fits (`-0` does; other negative values do not).
	public static bool TryParseUInt64(StringView token, out uint64 value)
	{
		return DecimalParse.TryParseUInt64(token, out value, false);
	}

	/// Appends the decimal digits of the hexadecimal integer `hex` (digits only, any length: JSON5's
	/// `0x…` beyond 64 bits).
	internal static void AppendHexAsDecimal(String output, StringView hex)
	{
		BigDecimal.AppendRadixAsDecimal(output, hex, 16, false);
	}

	/// The double of a NonFinite token: `NaN` (any sign) or `Infinity` with an optional sign.
	internal static double NonFiniteValue(StringView token)
	{
		if (token.EndsWith("NaN"))
			return double.NaN;
		return token[0] == '-' ? double.NegativeInfinity : double.PositiveInfinity;
	}

	/// @brief Whether `text` is a JSON number: RFC 8259's number production, nothing before or after
	/// (`-0`, `1.5e3`; not `+1`, `01`, `.5`, `1.`, ` 1`). The parse and classify methods take only such
	/// text: check first what did not come from the reader (a converter's string, a dictionary key).
	/// @param text The text.
	/// @return Whether it is one.
	public static bool IsValid(StringView text)
	{
		return JsonWriter.IsNumberText(text);
	}

	/// @brief The kind of a JSON number token (the reader's classification, from its text).
	public static JsonNumberKind Classify(StringView token)
	{
		for (let c in token)
		{
			if (c == '.' || c == 'e' || c == 'E')
				return .Float;
		}
		switch (DecimalParse.ClassifyInteger(token, false))
		{
		case .Int64: return .Integer;
		case .UInt64: return .UInteger;
		case .Big: return .BigInteger;
		}
	}

	/// @brief Append the shortest decimal text that reads back as `value` (zmij's digits, laid out in
	/// `format`). Non-finite values are written `NaN`, `Infinity`, `-Infinity`: not JSON, so the writers
	/// check for them first.
	/// @param output The string to append to.
	/// @param value The double.
	/// @param format The layout.
	public static void AppendDouble(String output, double value, JsonFloatFormat format = .Plain)
	{
		// One call per layout: each gets FormatCore's layout inlined with its tests folded
		bool finite = format == .Plain ? ShortestDouble.Append(output, value, .JsonPlain) : ShortestDouble.Append(output, value, .EcmaScript);
		if (!finite)
			output.Append(value.IsNaN ? "NaN" : value < 0 ? "-Infinity" : "Infinity");
	}

	/// @brief The double as ECMAScript's `Number::toString`, except that negative zero is `-0`: the
	/// number layout of the canonical form (docs/test-suites.md §9.2).
	/// @param output The string to append to.
	/// @param value The double (finite).
	public static void AppendCanonical(String output, double value)
	{
		if (value == 0 && IsNegative(value))
		{
			output.Append("-0");
			return;
		}
		AppendDouble(output, value, .EcmaScript);
	}

	/// @brief Whether the sign bit of `value` is set (true for −0.0, which compares equal to 0).
	[Inline]
	public static bool IsNegative(double value) => FloatBits.IsNegative(value);

	/// @brief The IEEE 754 bits of `value`.
	[Inline]
	public static uint64 ToBits(double value) => FloatBits.ToBits(value);

	/// @brief The double with IEEE 754 bits `bits`.
	[Inline]
	public static double FromBits(uint64 bits) => FloatBits.FromBits(bits);

	/// @brief Append the shortest decimal text that reads back as the float `value` (binary32: `0.1`,
	/// not the double's `0.10000000149011612`), laid out in `format`. Non-finite values as AppendDouble.
	/// @param output The string to append to.
	/// @param value The float.
	/// @param format The layout.
	public static void AppendFloat(String output, float value, JsonFloatFormat format = .Plain)
	{
		if (!ShortestDouble.Append(output, value, format == .Plain ? FloatLayout.JsonPlain : FloatLayout.EcmaScript))
			AppendDouble(output, value, format);
	}
}
