using System;
using FormatCore;
using internal FormatCore;

namespace JsonBeef;

/// JSON's character rules for FormatCore's generic text code (cursors, line counting, the validator):
/// nothing is validated up front, because only strings may hold non-ASCII bytes and the reader checks
/// UTF-8 as it scans them (errors then come in document order); no code point is banned beyond UTF-8
/// well-formedness; LF, CR and CRLF are the newlines (JSON5's LS and PS are whitespace, not lines).
struct JsonText : ITextPolicy
{
	public static bool ValidatesUpFront
	{
		[Inline]
		get => false;
	}

	[Inline]
	public static bool IsPlainWord(uint64 word) => Swar.IsAscii(word);

	[Inline]
	public static bool AllowsAscii(uint8 b) => true;

	public static bool BansCodePoints
	{
		[Inline]
		get => false;
	}

	[Inline]
	public static bool AllowsCodePoint(uint32 cp) => true;

	public static void AppendBanned(String message, uint32 cp)
	{
		message.Append("The character ");
		Hex.AppendCodePointName(message, cp);
		message.Append(" is not allowed");
	}

	[Inline]
	public static int NewlineLength(char8* text, int pos, int end) => Utf8.AsciiNewlineLength(text, pos, end);

	[Inline]
	public static uint64 MayHoldNewline(uint64 word) => Swar.BytesBelow0E(word);

	public static bool OnlyAsciiNewlines
	{
		[Inline]
		get => true;
	}
}
