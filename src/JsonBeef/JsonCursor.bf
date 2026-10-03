using System;
using FormatCore;
using internal FormatCore;
using internal JsonBeef;

namespace JsonBeef;

/// Where JsonReaderCore's bytes come from: FormatCore's `IInputCursor` (`ByteCursor<JsonText>` for
/// memory, `BufferedStreamCursor<JsonText>` for a Stream, `JsonPushCursor` for push input). The reader
/// reads a window through a pointer indexed by absolute offsets; nothing is validated up front (JsonText):
/// only strings may hold non-ASCII bytes, so the reader checks UTF-8 as it scans them. This class turns
/// a JsonReadConfig into the cursors' settings and their input errors into JsonParseErrors.
internal static class JsonInput
{
	/// The cursor-level settings of `config`.
	public static InputSettings Settings(JsonReadConfig config)
	{
		InputSettings settings = default;
		settings.mMaxInputBytes = config.MaxInputBytes;
		settings.mMaxTokenBytes = config.MaxTokenBytes;
		settings.mStreamBufferBytes = config.StreamBufferBytes;
		settings.mBom = config.AllowBom ? .Skip : .Reject;
		settings.mFormatName = "JSON";
		settings.mUtf8Rule = "JSON must be UTF-8, RFC 8259 §8.1";
		return settings;
	}

	/// The input error as JSON's: its kind mapped, a rejected BOM worded with the setting that rejects it.
	public static JsonParseError Error(InputError error)
	{
		JsonErrorKind kind;
		switch (error.mKind)
		{
		case .InvalidUtf8, .InvalidEncoding:
			kind = .InvalidUtf8;
		case .InvalidChar:
			kind = .UnexpectedChar;
		case .UnsupportedEncoding:
			kind = .UnsupportedEncoding;
		case .ByteOrderMark:
			return JsonParseError(.UnexpectedChar, "A byte order mark (U+FEFF) is not allowed (JsonReadConfig.AllowBom is off)",
				error.mLine, error.mColumn, error.mOffset, error.mLength);
		case .ResourceLimitExceeded:
			kind = .ResourceLimitExceeded;
		case .IoError:
			kind = .IoError;
		}
		return JsonParseError(kind, error.mMessage, error.mLine, error.mColumn, error.mOffset, error.mLength);
	}
}
