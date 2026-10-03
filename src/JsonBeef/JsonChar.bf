using System;
using FormatCore;
using internal FormatCore;
using internal JsonBeef;

namespace JsonBeef;

/// JSON's own byte classes and stop sets for the reader and the writers. The format-free byte helpers
/// (SWAR tests, UTF-8 validation and decoding, hex digits, code point counting, line location) are
/// FormatCore's `Swar`, `Bytes16`, `Utf8` and `Hex`; JSON's character rules for them are `JsonText`.
internal static class JsonChar
{
	/// Character classes of the bytes that may start a token, for the reader's dispatch.
	public enum ByteClass : uint8
	{
		/// Anything that cannot start a token or be whitespace.
		Other,
		/// Space, tab, LF, CR.
		Space,
		/// `"`
		Quote,
		/// `-` and `0`-`9`
		Number,
		/// `{` `}` `[` `]` `,` `:`
		Punct,
		/// `t` `f` `n`
		Literal,
		/// `/`: a comment with JsonReadConfig.Comments
		Slash
	}

	/// The class of every byte.
	public static ByteClass[256] sByteClass = BuildByteClasses();

	static ByteClass[256] BuildByteClasses()
	{
		ByteClass[256] classes = .();
		classes[(int)' '] = .Space;
		classes[(int)'\t'] = .Space;
		classes[(int)'\n'] = .Space;
		classes[(int)'\r'] = .Space;
		classes[(int)'"'] = .Quote;
		classes[(int)'-'] = .Number;
		for (int c = (int)'0'; c <= (int)'9'; c++)
			classes[c] = .Number;
		classes[(int)'{'] = .Punct;
		classes[(int)'}'] = .Punct;
		classes[(int)'['] = .Punct;
		classes[(int)']'] = .Punct;
		classes[(int)','] = .Punct;
		classes[(int)':'] = .Punct;
		classes[(int)'t'] = .Literal;
		classes[(int)'f'] = .Literal;
		classes[(int)'n'] = .Literal;
		classes[(int)'/'] = .Slash;
		return classes;
	}

	/// @brief Whether `c` is JSON whitespace: space, tab, LF or CR (RFC 8259 §2).
	[Inline]
	public static bool IsSpace(char8 c)
	{
		return c == ' ' || c == '\n' || c == '\r' || c == '\t';
	}

	[Inline]
	public static bool IsDigit(char8 c)
	{
		return (uint8)c - (uint8)'0' <= 9;
	}

	/// @brief The high bit of each byte that ends a string's plain run: `"`, `\` or a byte below 0x20
	/// (a control character, an error). Bytes ≥ 0x80 are checked by the string scan and pass here.
	[Inline]
	public static uint64 StringStops(uint64 word)
	{
		return Swar.BytesEqual(word, (uint8)'"') | Swar.BytesEqual(word, (uint8)'\\') | Swar.BytesBelowSpace(word);
	}

	/// @brief The index (0-15) of the first byte of `p[0 ..< 16]` that ends a string's plain ASCII run
	/// (`"`, `\`, a control character or a non-ASCII byte), or 16 when there is none: one 16-byte vector
	/// compare (SSE2, no movemask needed until a stop is found).
	[Inline]
	public static int FirstStringStop16(char8* p)
	{
		let bytes = Bytes16.Load(p);
		var mask = (bytes == Bytes16.Splat((uint8)'"')) | (bytes == Bytes16.Splat((uint8)'\\')) | (bytes < Bytes16.Splat((uint8)' '));
		return mask.FirstSet();
	}
}
