using System;

namespace JsonBeef;

/// @brief An error that owns its text, for keeping it: a list of diagnostics, errors from several
/// readers, documents or threads. (A JsonParseError's message views a per-thread buffer that the next
/// error on the thread replaces; a document's collected errors live until it is cleared or read again.)
/// Delete it when done.
///
/// ```
/// let kept = new List<JsonDiagnostic>();
/// defer { DeleteContainerAndItems!(kept); }
/// for (let path in paths)
/// {
///     if (doc.ReadFile(path) case .Err(let error))
///         kept.Add(new JsonDiagnostic(error));
/// }
/// ```
public class JsonDiagnostic
{
	/// @brief The category of error.
	public JsonErrorKind mKind;
	/// @brief Human-readable description.
	public String mMessage ~ delete _;
	/// @brief Name of the input the position refers to; empty if unnamed.
	public String mSource ~ delete _;
	/// @brief 1-based line (0 when there is no position).
	public int32 mLine;
	/// @brief 1-based column, in code points.
	public int32 mColumn;
	/// @brief Byte offset into the input.
	public int64 mOffset;
	/// @brief Length of the erroneous span in bytes.
	public int32 mLength;

	/// @brief Copy an error.
	/// @param error The error (its text is copied, so it may be the last one of its thread).
	public this(JsonParseError error)
	{
		mKind = error.mKind;
		mMessage = new String(error.mMessage);
		mSource = new String(error.mSource);
		mLine = error.mLine;
		mColumn = error.mColumn;
		mOffset = error.mOffset;
		mLength = error.mLength;
	}

	/// @brief The diagnostic as a JsonParseError whose text views this object (valid while it lives).
	public JsonParseError Error
	{
		get
		{
			JsonParseError error = default;
			error.mKind = mKind;
			error.mMessage = mMessage;
			error.mSource = mSource;
			error.mLine = mLine;
			error.mColumn = mColumn;
			error.mOffset = mOffset;
			error.mLength = mLength;
			return error;
		}
	}

	/// @brief Formats the diagnostic as JsonParseError.ToString does (`source:line:column: message`).
	/// @param strBuffer The string to append to.
	public override void ToString(String strBuffer)
	{
		Error.ToString(strBuffer);
	}
}
