using System;
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
	BigInteger
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
/// `RawValue`); they never see non-JSON text.
public static class JsonNumber
{
	/// Powers of ten that a double holds exactly (5^22 < 2^53).
	const double[23] cExactPowersOf10 = .(1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12,
		1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22);

	/// @brief The correctly rounded double of a JSON number token (round to nearest, ties to even): an
	/// overflow gives ±∞ and an underflow ±0, as IEEE 754 rounding does.
	/// @param token A token that matches the JSON number grammar.
	/// @param value Receives the double.
	/// @return Whether the value is finite (false: it overflowed to ±∞).
	public static bool ParseDouble(StringView token, out double value)
	{
		if (TryParsePlainDouble(token, out value))
			return true;
		return ParseDoubleSlow(token, out value);
	}

	/// The general path: corlib's fast_float (correctly rounded for any length) on the unsigned text.
	static bool ParseDoubleSlow(StringView token, out double value)
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
		bool negative = token[0] == '-';
		char8* text = token.Ptr + (negative ? 1 : 0);
		int length = token.Length - (negative ? 1 : 0);
		float result = 0;
		if (!float.[Friend]Parse(text, (int32)length, '.', &result))
			Runtime.FatalError("JsonNumber.ParseFloat: the token is not a JSON number");
		value = negative ? -result : result;
		return !result.IsInfinity;
	}

	/// Clinger's fast path (TomlBeef's TryParsePlainFloat with JSON's grammar): digits whose value fits an
	/// exact double mantissa (at most 2^53, 19 digits) and a decimal exponent within ±22, or a little
	/// beyond 22 when the mantissa times the excess power is still exact. Then mantissa and power are both
	/// exact, and one IEEE multiply or divide rounds correctly. Anything else returns false.
	[Inline]
	static bool TryParsePlainDouble(StringView token, out double value)
	{
		value = 0;
		char8* ptr = token.Ptr;
		int length = token.Length;
		int pos = ptr[0] == '-' ? 1 : 0;

		uint64 mantissa = 0;
		int digits = 0;
		while (pos < length && JsonChar.IsDigit(ptr[pos]))
		{
			mantissa = mantissa * 10 + ((uint8)ptr[pos++] - (uint8)'0');
			digits++;
		}
		if (digits > 19)
			return false;
		int exponent = 0;
		if (pos < length && ptr[pos] == '.')
		{
			pos++;
			int fracStart = pos;
			while (pos < length && JsonChar.IsDigit(ptr[pos]) && digits < 19)
			{
				mantissa = mantissa * 10 + ((uint8)ptr[pos++] - (uint8)'0');
				digits++;
			}
			// A 20th digit: the general path
			if (pos < length && JsonChar.IsDigit(ptr[pos]))
				return false;
			exponent = -(pos - fracStart);
		}
		if (pos < length)
		{
			// `e` or `E`
			pos++;
			bool negativeExponent = false;
			if (ptr[pos] == '-' || ptr[pos] == '+')
				negativeExponent = ptr[pos++] == '-';
			int expValue = 0;
			int expStart = pos;
			while (pos < length && pos - expStart < 4)
				expValue = expValue * 10 + ((uint8)ptr[pos++] - (uint8)'0');
			if (pos != length)
				return false;
			exponent += negativeExponent ? -expValue : expValue;
		}
		if (mantissa > (1UL << 53))
			return false;
		double result = (double)mantissa;
		if (exponent < 0)
		{
			if (exponent < -22)
				return false;
			result /= cExactPowersOf10[-exponent];
		}
		else if (exponent <= 22)
			result *= cExactPowersOf10[exponent];
		else
		{
			// 1e30: the mantissa times the excess power may still be exact
			if (exponent > 22 + 15)
				return false;
			uint64 scaled = mantissa;
			for (int i < exponent - 22)
			{
				scaled *= 10;
				if (scaled > (1UL << 53))
					return false;
			}
			result = (double)scaled * 1e22;
		}
		value = ptr[0] == '-' ? -result : result;
		return true;
	}

	/// @brief The int64 of an integer token, if it fits.
	/// @param token A JSON integer token (no fraction or exponent).
	/// @param value Receives the value.
	/// @return Whether it fits.
	public static bool TryParseInt64(StringView token, out int64 value)
	{
		value = 0;
		bool negative = token[0] == '-';
		if (!TryParseMagnitude(token, var magnitude))
			return false;
		if (negative)
		{
			if (magnitude > (uint64)int64.MaxValue + 1)
				return false;
			value = magnitude == 0 ? 0 : -(int64)(magnitude - 1) - 1;
			return true;
		}
		if (magnitude > (uint64)int64.MaxValue)
			return false;
		value = (int64)magnitude;
		return true;
	}

	/// @brief The uint64 of an integer token, if it fits (`-0` does; other negative values do not).
	public static bool TryParseUInt64(StringView token, out uint64 value)
	{
		value = 0;
		if (!TryParseMagnitude(token, var magnitude))
			return false;
		if (token[0] == '-' && magnitude != 0)
			return false;
		value = magnitude;
		return true;
	}

	/// The magnitude of an integer token, if it fits uint64.
	static bool TryParseMagnitude(StringView token, out uint64 magnitude)
	{
		magnitude = 0;
		int pos = token[0] == '-' ? 1 : 0;
		int digits = token.Length - pos;
		if (digits > 20)
			return false;
		for (int i = pos; i < token.Length; i++)
		{
			uint8 digit = (uint8)token[i] - (uint8)'0';
			if (digit > 9)
				return false;
			// 19 digits always fit; the 20th may overflow
			if (i - pos == 19 && (magnitude > 1844674407370955161UL || (magnitude == 1844674407370955161UL && digit > 5)))
				return false;
			magnitude = magnitude * 10 + digit;
		}
		return true;
	}

	/// @brief The kind of a JSON number token (the reader's classification, from its text).
	public static JsonNumberKind Classify(StringView token)
	{
		for (let c in token)
		{
			if (c == '.' || c == 'e' || c == 'E')
				return .Float;
		}
		if (TryParseInt64(token, ?))
			return .Integer;
		if (TryParseUInt64(token, ?))
			return .UInteger;
		return .BigInteger;
	}

	/// @brief Append the shortest decimal text that reads back as `value` (zmij's digits, laid out in
	/// `format`). Non-finite values are written `NaN`, `Infinity`, `-Infinity`: not JSON, so the writers
	/// check for them first.
	/// @param output The string to append to.
	/// @param value The double.
	/// @param format The layout.
	public static void AppendDouble(String output, double value, JsonFloatFormat format = .Plain)
	{
		if (!value.IsFinite)
		{
			output.Append(value.IsNaN ? "NaN" : value < 0 ? "-Infinity" : "Infinity");
			return;
		}
		char8[32] digits = ?;
		int count = GetShortestDigits(value, &digits, let point);
		bool negative = IsNegative(value);
		if (count == 0)
		{
			// Zero
			if (format == .EcmaScript)
				output.Append('0');
			else
				output.Append(negative ? "-0.0" : "0.0");
			return;
		}
		if (negative)
			output.Append('-');
		AppendLayout(output, &digits, count, point, format);
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
	public static bool IsNegative(double value)
	{
		var value;
		return ((*(uint64*)&value) >> 63) != 0;
	}

	/// @brief The IEEE 754 bits of `value`.
	[Inline]
	public static uint64 ToBits(double value)
	{
		var value;
		return *(uint64*)&value;
	}

	/// @brief The double with IEEE 754 bits `bits`.
	[Inline]
	public static double FromBits(uint64 bits)
	{
		var bits;
		return *(double*)&bits;
	}

	/// Lays out `count` significant digits `d1 d2 …` of the value 0.d1d2… × 10^point.
	static void AppendLayout(String output, char8* digits, int count, int point, JsonFloatFormat format)
	{
		int n = point;
		int k = count;
		if (k <= n && n <= 21)
		{
			// Integral: the digits and n - k zeros
			output.Append(digits, k);
			for (int i < n - k)
				output.Append('0');
			if (format == .Plain)
				output.Append(".0");
		}
		else if (0 < n && n <= 21)
		{
			output.Append(digits, n);
			output.Append('.');
			output.Append(digits + n, k - n);
		}
		else if (-6 < n && n <= 0)
		{
			output.Append("0.");
			for (int i < -n)
				output.Append('0');
			output.Append(digits, k);
		}
		else
		{
			output.Append(digits[0]);
			if (k > 1)
			{
				output.Append('.');
				output.Append(digits + 1, k - 1);
			}
			output.Append('e');
			int e = n - 1;
			if (e < 0)
			{
				output.Append('-');
				e = -e;
			}
			else if (format == .EcmaScript)
				output.Append('+');
			output.AppendF("{}", e);
		}
	}

	/// The shortest round-trip significant digits of a finite `value` (from corlib's zmij writer), without
	/// leading or trailing zeros, into `digits` (room for 32), with the decimal point position: the value
	/// is ±0.d1d2… × 10^point. @return The digit count, 0 for zero.
	internal static int GetShortestDigits(double value, char8* digits, out int point)
	{
		char8[64] text = ?;
		int length = double.[Friend]ToString_RoundTripFast(value, &text);
		int pos = 0;
		if (text[0] == '-')
			pos++;
		// The text is `ddd[.ddd][e±dd]`: collect the digits, note where the point is
		int count = 0;
		int intDigits = -1;
		int leadingZeros = 0;
		while (pos < length && text[pos] != 'e' && text[pos] != 'E')
		{
			char8 c = text[pos++];
			if (c == '.')
			{
				intDigits = count + leadingZeros;
				continue;
			}
			if (c == '0' && count == 0)
			{
				leadingZeros++;
				continue;
			}
			digits[count++] = c;
		}
		if (intDigits < 0)
			intDigits = count + leadingZeros;
		int exponent = 0;
		if (pos < length)
		{
			pos++;
			bool negative = false;
			if (text[pos] == '+' || text[pos] == '-')
				negative = text[pos++] == '-';
			while (pos < length)
				exponent = exponent * 10 + (text[pos++] - '0');
			if (negative)
				exponent = -exponent;
		}
		while (count > 0 && digits[count - 1] == '0')
			count--;
		point = intDigits + exponent - leadingZeros;
		return count;
	}
}
