using System;
using internal JsonBeef;

namespace JsonBeef;

/// @brief Why a JSON Pointer found no value.
public enum JsonPointerErrorKind : uint8
{
	/// @brief The pointer is not one: it does not start with `/` (and is not empty), or has a `~` not
	/// followed by `0` or `1`.
	InvalidSyntax,
	/// @brief A token on an array is not an index: `0` or a digit 1-9 and digits (`01`, `-1`, `1e0` are not).
	InvalidIndex,
	/// @brief No member has the name, the index is past the last element, or it is `-` (the element after
	/// the last, which exists only to append to).
	NotFound,
	/// @brief A token goes into a value that is not an array or object.
	NotAContainer
}

/// @brief A JSON Pointer evaluation error: the kind and the failing token's offset in the pointer.
public struct JsonPointerError
{
	public JsonPointerErrorKind mKind;
	/// @brief Byte offset of the failing token's `/` in the pointer (0 for a syntax error at the start).
	public int mOffset;

	public this(JsonPointerErrorKind kind, int offset)
	{
		mKind = kind;
		mOffset = offset;
	}

	public override void ToString(String output)
	{
		switch (mKind)
		{
		case .InvalidSyntax: output.Append("invalid JSON Pointer syntax");
		case .InvalidIndex: output.Append("invalid array index");
		case .NotFound: output.Append("no such value");
		case .NotAContainer: output.Append("not an array or object");
		}
		output.AppendF(" at offset {}", mOffset);
	}
}

/// @brief JSON Pointer (RFC 6901): evaluation against a document, syntax checks and escaping.
public static class JsonPointer
{
	/// @brief Whether `pointer` is valid JSON Pointer syntax.
	public static bool IsValid(StringView pointer)
	{
		if (pointer.IsEmpty)
			return true;
		if (pointer[0] != '/')
			return false;
		for (int i < pointer.Length)
		{
			if (pointer[i] == '~' && (i + 1 >= pointer.Length || (pointer[i + 1] != '0' && pointer[i + 1] != '1')))
				return false;
		}
		return true;
	}

	/// @brief Append `name` as a pointer token: `~` written `~0`, `/` written `~1`.
	public static void AppendToken(String output, StringView name)
	{
		for (let c in name)
		{
			if (c == '~')
				output.Append("~0");
			else if (c == '/')
				output.Append("~1");
			else
				output.Append(c);
		}
	}

	/// The decoded token from `pos` (just after its `/`) to the next `/` or the end, into `token` when it
	/// has escapes (`~1` is decoded before `~0`, so `~01` is `~1`); `pos` moves to that `/` or the end.
	/// @return The token (a view of the pointer, or of `token`), or an error for a bad `~`.
	internal static Result<StringView> NextToken(StringView pointer, ref int pos, String token)
	{
		int start = pos;
		bool escaped = false;
		while (pos < pointer.Length && pointer[pos] != '/')
		{
			if (pointer[pos] == '~')
			{
				if (pos + 1 >= pointer.Length || (pointer[pos + 1] != '0' && pointer[pos + 1] != '1'))
					return .Err;
				escaped = true;
				pos++;
			}
			pos++;
		}
		StringView raw = pointer.Substring(start, pos - start);
		if (!escaped)
			return raw;
		token.Clear();
		for (int i = 0; i < raw.Length; i++)
		{
			if (raw[i] == '~')
			{
				token.Append(raw[i + 1] == '1' ? '/' : '~');
				i++;
			}
			else
				token.Append(raw[i]);
		}
		return StringView(token);
	}

	/// The array index a token names: `0`, or a digit 1-9 then digits (no sign, no leading zero), or -1.
	internal static int ParseIndex(StringView token)
	{
		if (token.IsEmpty || token.Length > 10 || (token[0] == '0' && token.Length > 1))
			return -1;
		int64 value = 0;
		for (let c in token)
		{
			if (!JsonChar.IsDigit(c))
				return -1;
			value = value * 10 + (c - '0');
		}
		return value <= int32.MaxValue ? (int)value : -1;
	}

	/// The value at `pointer` from `start`.
	internal static Result<JsonNode, JsonPointerError> Evaluate(JsonNode start, StringView pointer)
	{
		if (!start.IsValid)
			return .Err(.(.NotFound, 0));
		if (pointer.IsEmpty)
			return start;
		if (pointer[0] != '/')
			return .Err(.(.InvalidSyntax, 0));
		let scratch = scope String();
		JsonNode node = start;
		int pos = 0;
		while (pos < pointer.Length)
		{
			int tokenStart = pos;
			pos++;
			StringView token;
			switch (NextToken(pointer, ref pos, scratch))
			{
			case .Ok(let decoded):
				token = decoded;
			case .Err:
				return .Err(.(.InvalidSyntax, tokenStart));
			}
			switch (node.Kind)
			{
			case .Object:
				let member = node[token];
				if (!member.IsValid)
					return .Err(.(.NotFound, tokenStart));
				node = member;
			case .Array:
				if (token == "-")
					return .Err(.(.NotFound, tokenStart));
				int index = ParseIndex(token);
				if (index < 0)
					return .Err(.(.InvalidIndex, tokenStart));
				let element = node[index];
				if (!element.IsValid)
					return .Err(.(.NotFound, tokenStart));
				node = element;
			default:
				return .Err(.(.NotAContainer, tokenStart));
			}
		}
		return node;
	}
}
