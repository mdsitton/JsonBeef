using System;
using FormatCore;

namespace JsonBeef;

/// @brief Categories of errors that can occur when reading or converting JSON.
public enum JsonErrorKind : uint8
{
	// Encoding
	/// @brief Bytes that are not well-formed UTF-8.
	InvalidUtf8,
	/// @brief The input is UTF-16 or UTF-32: JSON must be UTF-8 (RFC 8259 §8.1).
	UnsupportedEncoding,

	// Lexical
	/// @brief A character that cannot appear where it is (outside strings).
	UnexpectedChar,
	/// @brief The input ended inside a value, or before the document's value.
	UnexpectedEndOfInput,
	/// @brief A misspelled or truncated `true`, `false` or `null`.
	InvalidLiteral,
	/// @brief Text that starts like a number but does not follow the JSON number grammar.
	InvalidNumber,
	/// @brief A string without its closing quote.
	UnterminatedString,
	/// @brief An unknown escape, or `\u` without four hex digits.
	InvalidEscape,
	/// @brief A `\u` escape of a surrogate that is not part of a high-low pair.
	InvalidSurrogate,
	/// @brief A control character (U+0000-U+001F) written raw inside a string.
	ControlCharacterInString,
	/// @brief A `/*` comment without its `*/` (JsonReadConfig.Comments).
	UnterminatedComment,

	// Structure
	/// @brief A `,`, `:`, `]` or `}` missing, doubled or misplaced, or anything after the document's value.
	InvalidStructure,
	/// @brief A member name an earlier member of the object already has (JsonDuplicateNames.Error).
	DuplicateName,
	/// @brief A noncharacter (U+FDD0-U+FDEF, U+FFFE, U+FFFF and the last two code points of every
	/// plane) in a string or name: legal JSON, but not I-JSON (JsonReadConfig.IJson, RFC 7493 §2.1).
	Noncharacter,

	// Values
	/// @brief A number whose value does not fit the requested type (a double beyond ±1.8e308, an
	/// integer beyond the type's range).
	NumberOutOfRange,

	// Typed binding ([JsonObject])
	/// @brief A value of another kind than the field needs (a string for an integer, `null` for a
	/// field that cannot be null, a fraction for an integer).
	TypeMismatch,
	/// @brief A [JsonRequired] member is absent.
	MissingValue,
	/// @brief A value of the right kind that the field cannot take: an unknown enum case or
	/// discriminator, a converter's rejection.
	InvalidValue,
	/// @brief A member no field maps, in a [JsonObject(Strict = true)] type.
	UnknownMember,

	// Limits
	/// @brief A resource limit of JsonReadConfig was exceeded.
	ResourceLimitExceeded,

	// File I/O
	/// @brief Reading the input failed.
	IoError
}

/// @brief A read error with its location: FormatCore's `ParseError` with JSON's error kinds (the
/// carrier of all four format libraries; this was its model).
///
/// The error owns nothing and needs no cleanup, so it can be dropped freely (including by `Try!`).
/// `mMessage` views a per-thread buffer: it stays valid until the next JsonParseError is created on the
/// same thread, which in practice means the next failing JsonBeef call. Copy it to keep it longer
/// (`JsonDiagnostic`), or `Detach` it. In typed binding, `mPath` is the JSON Pointer (RFC 6901) of the
/// value the error is in, from the bound object (`/statuses/3/user/id`).
public typealias JsonParseError = FormatCore.ParseError<JsonErrorKind>;
