using System;
using System.Collections;
using internal JsonBeef;

namespace JsonBeef;

/// @brief What JsonBind.NextMember and NextElement reached.
public enum JsonStep : uint8
{
	/// @brief A member's name, or an element's first token.
	Item,
	/// @brief The container's end.
	End,
	/// @brief An error (JsonBind.Error has it).
	Error
}

/// @brief What to do with a member whose field an earlier member already filled (JsonBind.OnDuplicate).
public enum JsonDuplicateAction : uint8
{
	/// @brief Fail (JsonBind.Error has the error).
	Error,
	/// @brief Skip the member (JsonDuplicateNames.FirstWins).
	Skip,
	/// @brief Read it over the earlier one (JsonDuplicateNames.LastWins).
	Read
}

/// @brief The run-time half of [JsonObject]: what the generated JsonRead and JsonWrite call per value,
/// and what converters use for located errors. The bool-returning readers keep their error in the
/// reader, for JsonBind.Error.
///
/// Reading checks kinds and ranges strictly: an integer field takes an integer token in its range (not
/// `1.0` or `1e2`), a float or double field any number within its range (never an infinity), a String
/// a string or `null`, a bool `true` or `false`.
public static class JsonBind
{
	// Errors

	/// @brief The error of the JsonBind call that last returned false (or JsonStep.Error) on `reader`.
	/// @param reader The reader.
	/// @return The error.
	public static JsonParseError Error(JsonReader reader)
	{
		return reader.mBindError;
	}

	/// @brief A TypeMismatch error at the current token: "Expected `expected`, found …".
	/// @param reader The reader.
	/// @param expected What the field needs: "an integer", "an array [x, y]".
	/// @return The error.
	public static JsonParseError Mismatch(JsonReader reader, StringView expected)
	{
		let message = scope String();
		message.Append("Expected ");
		message.Append(expected);
		message.Append(", found ");
		Describe(reader, message);
		return At(reader, .TypeMismatch, message);
	}

	/// @brief An InvalidValue error at the current token: a value of the right kind that does not fit.
	/// @param reader The reader.
	/// @param message What is wrong.
	/// @return The error.
	public static JsonParseError Invalid(JsonReader reader, StringView message)
	{
		return At(reader, .InvalidValue, message);
	}

	/// @brief The error with `/name` put in front of its path: generated code adds the member it was
	/// reading as the error leaves it.
	/// @param error The error.
	/// @param name The member's name.
	/// @return The error.
	public static JsonParseError AtMember(JsonParseError error, StringView name)
	{
		var error;
		error.PrependPath(name);
		return error;
	}

	/// @brief The error with `/index` put in front of its path.
	/// @param error The error.
	/// @param index The array index.
	/// @return The error.
	public static JsonParseError AtIndex(JsonParseError error, int index)
	{
		var error;
		error.PrependPath(index.ToString(.. scope .()), false);
		return error;
	}

	/// @brief A MissingValue error for the required member `name`, at `offset` (the object's start).
	/// @param reader The reader.
	/// @param offset Where the object starts.
	/// @param name The member's name.
	/// @return The error.
	public static JsonParseError Missing(JsonReader reader, int offset, StringView name)
	{
		let message = scope String();
		message.Append("The member \"");
		AppendShort(message, name);
		message.Append("\" is required");
		return reader.MakeError(.MissingValue, message, offset, 1);
	}

	/// @brief An UnknownMember error at the current member name (a Strict type).
	/// @param reader The reader, at a PropertyName.
	/// @return The error.
	public static JsonParseError Unknown(JsonReader reader)
	{
		let message = scope String();
		message.Append("Unknown member \"");
		AppendShort(message, reader.StringValue);
		message.Append("\" (the type is Strict: every member must map to a field)");
		return At(reader, .UnknownMember, message);
	}

	/// @brief An InvalidValue error at the current string: none of the enum's case names.
	/// @param reader The reader, at a String.
	/// @param cases The case names, for the message (`a, b, c`).
	/// @return The error.
	public static JsonParseError UnknownCase(JsonReader reader, StringView cases)
	{
		let message = scope String();
		message.Append("Unknown value \"");
		AppendShort(message, reader.StringValue);
		message.AppendF("\" (expected one of: {})", cases);
		return At(reader, .InvalidValue, message);
	}

	/// @brief An InvalidValue error at the current number: none of the enum's case values.
	/// @param reader The reader, at a Number.
	/// @param enumName The enum type, for the message.
	/// @return The error.
	public static JsonParseError UnknownNumber(JsonReader reader, StringView enumName)
	{
		return At(reader, .InvalidValue, scope $"{reader.RawValue} is not a value of {enumName}");
	}

	/// The current token's error of `kind`.
	static JsonParseError At(JsonReader reader, JsonErrorKind kind, StringView message)
	{
		int offset = reader.Offset;
		return reader.MakeError(kind, message, offset, Math.Max(reader.EndOffset - offset, 1));
	}

	/// What the current token is, for "found …".
	static void Describe(JsonReader reader, String message)
	{
		switch (reader.TokenType)
		{
		case .StartObject:
			message.Append("an object");
		case .StartArray:
			message.Append("an array");
		case .String:
			message.Append("the string \"");
			AppendShort(message, reader.RawValue);
			message.Append('"');
		case .PropertyName:
			message.Append("the member name \"");
			AppendShort(message, reader.RawValue);
			message.Append('"');
		case .Number:
			message.Append("the number ");
			AppendShort(message, reader.RawValue);
		case .True:
			message.Append("`true`");
		case .False:
			message.Append("`false`");
		case .Null:
			message.Append("`null`");
		case .EndObject:
			message.Append("the end of the object");
		case .EndArray:
			message.Append("the end of the array");
		default:
			message.Append("the end of the document");
		}
	}

	/// `text`, cut after 40 bytes (at a code point boundary) with `…`.
	static void AppendShort(String message, StringView text)
	{
		if (text.Length <= 40)
		{
			message.Append(text);
			return;
		}
		int end = 40;
		while (end > 0 && ((uint8)text[end] & 0xC0) == 0x80)
			end--;
		message.Append(text.Substring(0, end));
		message.Append("…");
	}

	// Structure

	/// @brief Before an object's members: true at its StartObject (reading the first token, or a member's
	/// value after its name, first), else a mismatch.
	/// @param reader The reader.
	/// @return Whether it is an object (else the error is kept).
	[Inline]
	public static bool BeginObject(JsonReader reader)
	{
		if (reader.TokenType == .StartObject)
			return true;
		return BeginSlow(reader, .StartObject, "an object");
	}

	/// @brief Before an array's elements, as BeginObject.
	/// @param reader The reader.
	/// @return Whether it is an array (else the error is kept).
	[Inline]
	public static bool BeginArray(JsonReader reader)
	{
		if (reader.TokenType == .StartArray)
			return true;
		return BeginSlow(reader, .StartArray, "an array");
	}

	static bool BeginSlow(JsonReader reader, JsonToken want, StringView expected)
	{
		if (reader.TokenType == .None || reader.TokenType == .PropertyName)
		{
			switch (reader.Next())
			{
			case .Ok(let token):
				if (token == want)
					return true;
			case .Err(let error):
				reader.mBindError = error;
				return false;
			}
		}
		reader.mBindError = Mismatch(reader, expected);
		return false;
	}

	/// @brief In an object: the next member's name, or its end.
	/// @param reader The reader.
	/// @return Item at a PropertyName, End at EndObject, or Error.
	[Inline]
	public static JsonStep NextMember(JsonReader reader)
	{
		switch (reader.Next())
		{
		case .Ok(let token):
			return token == .PropertyName ? .Item : .End;
		case .Err(let error):
			reader.mBindError = error;
			return .Error;
		}
	}

	/// @brief In an array: the next element's first token, or its end.
	/// @param reader The reader.
	/// @return Item at a value, End at EndArray, or Error.
	[Inline]
	public static JsonStep NextElement(JsonReader reader)
	{
		switch (reader.Next())
		{
		case .Ok(let token):
			return token == .EndArray ? .End : .Item;
		case .Err(let error):
			reader.mBindError = error;
			return .Error;
		}
	}

	/// @brief After a member's name: its value's first token.
	/// @param reader The reader.
	/// @return Whether it was read (else the error is kept).
	[Inline]
	public static bool Value(JsonReader reader)
	{
		switch (reader.Next())
		{
		case .Ok:
			return true;
		case .Err(let error):
			reader.mBindError = error;
			return false;
		}
	}

	/// @brief Skip the value the current token starts, checking it (JsonReader.SkipValue).
	/// @param reader The reader.
	/// @return Whether it was read (else the error is kept).
	public static bool Skip(JsonReader reader)
	{
		if (reader.SkipValue() case .Err(let error))
		{
			reader.mBindError = error;
			return false;
		}
		return true;
	}

	/// @brief At the name of a member whose field is already filled: what JsonReadConfig.DuplicateNames
	/// says (FirstWins: skip it, LastWins: read it again; otherwise an error, since a typed field holds
	/// one value).
	/// @param reader The reader, at the PropertyName.
	/// @return The action (Error: the error is kept).
	public static JsonDuplicateAction OnDuplicate(JsonReader reader)
	{
		switch (reader.Config.DuplicateNames)
		{
		case .FirstWins:
			return .Skip;
		case .LastWins:
			return .Read;
		default:
			let message = scope String();
			message.Append("The member \"");
			AppendShort(message, reader.StringValue);
			message.Append("\" is given twice (also under an alias: typed binding reads one value per field; JsonReadConfig.DuplicateNames FirstWins or LastWins picks one)");
			reader.mBindError = At(reader, .DuplicateName, message);
			return .Error;
		}
	}

	// Scalars

	/// @brief Whether the current token is `null`.
	[Inline]
	public static bool IsNull(JsonReader reader)
	{
		return reader.TokenType == .Null;
	}

	/// @brief `true` or `false`.
	/// @param reader The reader.
	/// @param value Receives the value.
	/// @return Whether the token is a boolean (else the error is kept).
	[Inline]
	public static bool ReadBool(JsonReader reader, out bool value)
	{
		let token = reader.TokenType;
		value = token == .True;
		if (token == .True || token == .False)
			return true;
		reader.mBindError = Mismatch(reader, "`true` or `false`");
		return false;
	}

	/// @brief An integer token within [min, max].
	/// @param reader The reader.
	/// @param min The field type's smallest value.
	/// @param max The field type's largest value.
	/// @param value Receives the value.
	/// @return Whether it is one (else the error is kept: a mismatch, or NumberOutOfRange).
	[Inline]
	public static bool ReadInteger(JsonReader reader, int64 min, int64 max, out int64 value)
	{
		value = 0;
		if (reader.TokenType == .Number && reader.NumberKind == .Integer)
		{
			value = reader.IntegerPayload;
			if (value >= min && value <= max)
				return true;
		}
		reader.mBindError = IntegerError(reader, min, max);
		return false;
	}

	static JsonParseError IntegerError(JsonReader reader, int64 min, int64 max)
	{
		return IntegerError(reader, min.ToString(.. scope .()), max.ToString(.. scope .()));
	}

	/// @brief A non-negative integer token up to 2^64 - 1.
	/// @param reader The reader.
	/// @param value Receives the value.
	/// @return Whether it is one (else the error is kept).
	[Inline]
	public static bool ReadUInt64(JsonReader reader, out uint64 value)
	{
		if (reader.TryGetUInt64(out value))
			return true;
		reader.mBindError = IntegerError(reader, "0", "18446744073709551615");
		return false;
	}

	static JsonParseError IntegerError(JsonReader reader, StringView min, StringView max)
	{
		if (reader.TokenType != .Number || reader.NumberKind == .Float || reader.NumberKind == .NonFinite)
			return Mismatch(reader, "an integer");
		return At(reader, .NumberOutOfRange, scope $"The number {reader.RawValue} is out of the field's range ({min} to {max})");
	}

	/// @brief Any number token, as the correctly rounded double; beyond the double range an error, never
	/// an infinity.
	/// @param reader The reader.
	/// @param value Receives the value.
	/// @return Whether it is a number in range (else the error is kept).
	[Inline]
	public static bool ReadDouble(JsonReader reader, out double value)
	{
		if (reader.TryGetDouble(out value))
			return true;
		if (reader.TokenType != .Number)
			reader.mBindError = Mismatch(reader, "a number");
		else
			reader.mBindError = At(reader, .NumberOutOfRange, scope $"The number {reader.RawValue} is beyond the range of a double (±1.7976931348623157e308)");
		return false;
	}

	/// @brief Any number token, as the correctly rounded float (parsed directly, not through a double,
	/// which would round twice); beyond the float range an error.
	/// @param reader The reader.
	/// @param value Receives the value.
	/// @return Whether it is a number in range (else the error is kept).
	public static bool ReadFloat(JsonReader reader, out float value)
	{
		value = 0;
		if (reader.TokenType != .Number)
		{
			reader.mBindError = Mismatch(reader, "a number");
			return false;
		}
		if (reader.NumberKind == .NonFinite)
		{
			value = (float)JsonNumber.NonFiniteValue(reader.RawValue);
			return true;
		}
		if (JsonNumber.ParseFloat(reader.StringValue, out value))
			return true;
		reader.mBindError = At(reader, .NumberOutOfRange, scope $"The number {reader.RawValue} is beyond the range of a float (±3.4028235e38)");
		return false;
	}

	/// @brief A string into `target` (set, or a new String when it is null), or `null` (the String deleted
	/// when the object owns it: without an allocator).
	/// @param reader The reader.
	/// @param target The field or item.
	/// @param allocator The read's allocator, or null for the heap.
	/// @return Whether the token is a string or null (else the error is kept).
	[Inline]
	public static bool ReadString(JsonReader reader, ref String target, ITypedAllocator allocator)
	{
		if (reader.TokenType == .String)
		{
			if (target == null)
				target = (allocator != null) ? new:allocator String(reader.StringValue) : new String(reader.StringValue);
			else
				target.Set(reader.StringValue);
			return true;
		}
		return StringSlow(reader, ref target, allocator);
	}

	static bool StringSlow(JsonReader reader, ref String target, ITypedAllocator allocator)
	{
		if (reader.TokenType == .Null)
		{
			if (allocator == null)
				delete target;
			target = null;
			return true;
		}
		reader.mBindError = Mismatch(reader, "a string");
		return false;
	}

	/// @brief A string token's text (an enum case name).
	/// @param reader The reader.
	/// @param text Receives the decoded text (valid until the next token).
	/// @return Whether the token is a string (else the error is kept).
	[Inline]
	public static bool ReadText(JsonReader reader, out StringView text)
	{
		text = reader.StringValue;
		if (reader.TokenType == .String)
			return true;
		reader.mBindError = Mismatch(reader, "a string");
		return false;
	}

	/// @brief For a field that cannot be null: the mismatch error for `null`, else true.
	/// @param reader The reader.
	/// @param expected What the field needs.
	/// @return Whether the token is not `null` (else the error is kept).
	[Inline]
	public static bool NotNull(JsonReader reader, StringView expected)
	{
		if (reader.TokenType != .Null)
			return true;
		reader.mBindError = Mismatch(reader, expected);
		return false;
	}

	// Dictionary keys

	/// @brief The current member name as an integer key within [min, max] (decimal, as JSON writes
	/// integers: `-12`, not `+12` or `012`).
	/// @param reader The reader, at a PropertyName.
	/// @param min The key type's smallest value.
	/// @param max The key type's largest value.
	/// @param value Receives the key.
	/// @return Whether it is one (else the error is kept).
	public static bool KeyInteger(JsonReader reader, int64 min, int64 max, out int64 value)
	{
		value = 0;
		StringView key = reader.StringValue;
		if (JsonWriter.IsNumberText(key) && JsonNumber.Classify(key) == .Integer && JsonNumber.TryParseInt64(key, out value) && value >= min && value <= max)
			return true;
		reader.mBindError = BadKey(reader, scope $"an integer from {min} to {max}");
		return false;
	}

	/// @brief The current member name as an unsigned 64-bit key.
	/// @param reader The reader, at a PropertyName.
	/// @param value Receives the key.
	/// @return Whether it is one (else the error is kept).
	public static bool KeyUInt64(JsonReader reader, out uint64 value)
	{
		value = 0;
		StringView key = reader.StringValue;
		if (JsonWriter.IsNumberText(key) && key[0] != '-' && JsonNumber.TryParseUInt64(key, out value) && JsonNumber.Classify(key) != .Float)
			return true;
		reader.mBindError = BadKey(reader, "an integer from 0 to 18446744073709551615");
		return false;
	}

	/// @brief An InvalidValue error at the current member name: a key the dictionary's key type cannot
	/// take (an enum case it does not have).
	/// @param reader The reader, at a PropertyName.
	/// @param expected What the key must be.
	/// @return The error.
	public static JsonParseError BadKey(JsonReader reader, StringView expected)
	{
		let message = scope String();
		message.Append("The key \"");
		AppendShort(message, reader.StringValue);
		message.AppendF("\" is not {}", expected);
		return At(reader, .InvalidValue, message);
	}

	// Polymorphism

	/// @brief At a StartObject: the value of its discriminator member `name`, wherever it is in the
	/// object (the reader looks ahead and comes back; a stream keeps the object in its buffer for this).
	/// @param reader The reader.
	/// @param name The discriminator's member name.
	/// @param typeName Receives the value.
	/// @param found Receives whether the member is there.
	/// @return Whether the look-ahead succeeded and the member, if there, is a string (else the error is
	/// kept).
	public static bool ReadDiscriminator(JsonReader reader, StringView name, String typeName, out bool found)
	{
		found = false;
		JsonToken token;
		switch (reader.PeekMember(name, out token, typeName))
		{
		case .Ok(let present):
			found = present;
		case .Err(let error):
			reader.mBindError = error;
			return false;
		}
		if (found && token != .String)
		{
			reader.mBindError = At(reader, .TypeMismatch, scope $"The member \"{name}\" names the object's type: it must be a string");
			return false;
		}
		return true;
	}

	/// @brief An error at the current StartObject for a discriminator value no type has, or none when
	/// the base type cannot be created.
	/// @param reader The reader.
	/// @param name The discriminator's member name.
	/// @param typeName Its value (empty: absent).
	/// @param expected The type names the field can hold.
	/// @return The error.
	public static JsonParseError UnknownType(JsonReader reader, StringView name, StringView typeName, StringView expected)
	{
		if (typeName.IsEmpty)
			return At(reader, .MissingValue, scope $"The object has no \"{name}\" member to name its type (one of: {expected})");
		let message = scope String();
		message.AppendF("Unknown \"{}\": \"", name);
		AppendShort(message, typeName);
		message.AppendF("\" (expected one of: {})", expected);
		return At(reader, .InvalidValue, message);
	}

	/// @brief Reading a type's own members: its discriminator member's value must be its type name.
	/// @param reader The reader, at the member's value.
	/// @param name The discriminator's member name.
	/// @param expected The type's name.
	/// @return Whether it is (else the error is kept).
	public static bool CheckTypeName(JsonReader reader, StringView name, StringView expected)
	{
		if (reader.TokenType == .String && reader.StringValue == expected)
			return true;
		if (reader.TokenType != .String)
			reader.mBindError = Mismatch(reader, scope $"the type name \"{expected}\"");
		else
		{
			let message = scope String();
			message.AppendF("\"{}\" is \"", name);
			AppendShort(message, reader.StringValue);
			message.AppendF("\", but the object is read as \"{}\"", expected);
			reader.mBindError = At(reader, .InvalidValue, message);
		}
		return false;
	}

	// Writing

	/// @brief A String, or `null` for a null one.
	/// @param writer The writer.
	/// @param value The text.
	[Inline]
	public static void WriteString(JsonWriter writer, String value)
	{
		if (value == null)
			writer.WriteNull();
		else
			writer.WriteString(value);
	}

	/// @brief Record that `value` (an enum's) is none of its type's cases: the writer stops at an
	/// InvalidValue error.
	/// @param writer The writer.
	/// @param typeName The enum type.
	/// @param value The value.
	public static void InvalidEnum(JsonWriter writer, StringView typeName, int64 value)
	{
		writer.SetError(.InvalidValue, scope $"{value} is not a case of {typeName}");
	}

	/// @brief The InvalidValue error for an enum value that is none of its type's cases.
	/// @param typeName The enum type.
	/// @param value The value.
	/// @return The error.
	public static JsonWriteError InvalidEnumError(StringView typeName, int64 value)
	{
		return JsonWriteError(.InvalidValue, scope $"{value} is not a case of {typeName}");
	}
}
