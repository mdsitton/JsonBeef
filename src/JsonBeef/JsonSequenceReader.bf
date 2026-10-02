using System;
using System.Collections;
using System.IO;
using internal JsonBeef;

namespace JsonBeef;

/// @brief How the values of a JSON sequence are delimited (spec-reference §12.3, §12.4).
public enum JsonSequenceMode : uint8
{
	/// @brief JSON Lines / NDJSON: one value per line (LF, or CRLF), each line exactly one value. A
	/// final newline is optional. An empty line is an error unless SkipEmptyLines is set. An error
	/// in one line does not stop the others.
	Lines,
	/// @brief Concatenated JSON: values one after another with optional whitespace (`{}{}`, `1 2`;
	/// `12` is one number), as yajl's multiple-values mode or Go's json.Decoder. The first error ends
	/// the sequence (a reader cannot tell where the next value starts).
	Concatenated,
	/// @brief RFC 7464 JSON text sequences (`application/json-seq`): each value after a record separator
	/// (0x1E) and normally followed by LF. Empty elements are skipped; an element that fails is
	/// reported and the next one read (RFC 7464 §2.1); a top-level number or literal not followed by
	/// whitespace is reported as possibly truncated and dropped (§2.4).
	RecordSeparated
}

/// @brief Reads a sequence of JSON values from one input: JSON Lines, concatenated values or RFC 7464
/// record-separated ones. Next moves to each value in turn and leaves `Reader` at its first token:
/// read it with the reader's Next, SkipValue, ReadRaw or a [JsonObject] type's JsonRead, or into a
/// document with ReadDocument. A line or element is checked whole before Next returns it, so each
/// gives a value or an error, never part of one (concatenated values are read once, as they come:
/// what of one is left unread is read and checked by the next call). Errors are located in the whole
/// input (line, column, offset; Locate does it for the reader's own); `Index` says which record they
/// belong to.
///
/// ```
/// let lines = scope JsonSequenceReader(.Lines);
/// lines.Reset(text);
/// while (true)
/// {
///     switch (lines.Next())
///     {
///     case .Ok(let more):
///         if (!more)
///             return;
///         let event = scope Event();
///         Try!(event.JsonRead(lines.Reader));
///     case .Err(let error):
///         Console.WriteLine($"record {lines.Index}: {error}");   // the next line is read next
///     }
/// }
/// ```
public class JsonSequenceReader
{
	JsonReader mReader = new .() ~ delete _;
	JsonSequenceMode mMode;
	JsonReadConfig mConfig;
	String mSourceName = new .() ~ delete _;

	// Lines and RecordSeparated: the input in memory, or what has been read of a stream
	StringView mText;
	Stream mStream;
	List<char8> mPending = new .() ~ delete _;
	bool mStreamDone;
	bool mStreamFailed;
	/// The next record's search position: in mText, or in mPending
	int mPos;
	/// The absolute offset of mPending[0] (streams), and the 1-based line at mPos
	int64 mBase;
	int mLine = 1;
	/// The current record: its text (a view of mText or mRecord), absolute offset, line and column
	String mRecord = new .() ~ delete _;
	int64 mRecordOffset;
	int mRecordLine;
	int mRecordColumn;
	/// Concatenated: a value is being read
	bool mInRecord;
	int mIndex;
	bool mStopped;

	/// @brief With Lines: skip lines that are empty or only spaces and tabs (NDJSON allows it) instead of
	/// reporting each as an error.
	public bool SkipEmptyLines;

	/// @brief Create a reader for sequences of the given kind; call Reset before reading.
	/// @param mode How the values are delimited.
	public this(JsonSequenceMode mode = .Lines)
	{
		mMode = mode;
	}

	/// @brief How the values are delimited (takes effect at the next Reset).
	public JsonSequenceMode Mode
	{
		get => mMode;
		set => mMode = value;
	}

	/// @brief The reader of the current value, at its first token after Next returned true.
	public JsonReader Reader => mReader;

	/// @brief The 1-based number of the current record: the line (Lines, counting every line), the
	/// element (RecordSeparated, counting the non-empty ones) or the value (Concatenated).
	public int Index => mIndex;

	/// @brief Start reading `text` (which must outlive the reading) from the beginning.
	/// @param text The sequence (UTF-8).
	/// @param config The dialect, limits and source name for every value. A byte order mark is
	/// skipped at the start of the input only (AllowBom).
	public void Reset(StringView text, JsonReadConfig config = .())
	{
		Start(config);
		mText = text;
		mStream = null;
		if (mMode == .Concatenated)
		{
			mReader.Reset(text, mConfig);
			mReader.AllowMultipleValues();
		}
	}

	/// @brief Start reading a stream: Lines and RecordSeparated through a buffer that holds one record
	/// at a time (MaxTokenBytes, when set, bounds a record), Concatenated through the reader's buffer.
	/// @param stream The sequence, read from its current position (it must outlive the reading).
	/// @param config The dialect, limits, buffer size and source name.
	public void Reset(Stream stream, JsonReadConfig config = .())
	{
		Start(config);
		mText = default;
		mStream = stream;
		if (mMode == .Concatenated)
		{
			mReader.Reset(stream, mConfig);
			mReader.AllowMultipleValues();
		}
	}

	void Start(JsonReadConfig config)
	{
		mSourceName.Set(config.SourceName);
		mConfig = config;
		mConfig.SourceName = mSourceName;
		mPending.Clear();
		mStreamDone = false;
		mStreamFailed = false;
		mPos = 0;
		mBase = 0;
		mLine = 1;
		mInRecord = false;
		mIndex = 0;
		mStopped = false;
		mRecordColumnAfterSeparator = 1;
	}

	/// @brief Move to the next value, first reading what is left of the current one.
	/// @return True with Reader at the value's first token, false at the end of the input, or an error:
	/// of what was left of the previous record (Index is still its number) or of the next one. With Lines
	/// and RecordSeparated the call after an error goes on with the following record; with
	/// Concatenated the sequence ends.
	public Result<bool, JsonParseError> Next()
	{
		if (mStopped)
			return false;
		if (mMode == .Concatenated)
			return NextConcatenated();
		while (true)
		{
			bool found;
			switch (NextRecord())
			{
			case .Ok(let present):
				found = present;
			case .Err(let error):
				return .Err(error);
			}
			if (!found)
				return false;
			var config = mConfig;
			// A byte order mark only at the start of the input
			config.AllowBom = mConfig.AllowBom && mRecordOffset == 0;
			// The whole record first, so that it gives a value or an error, never both
			mReader.Reset(mRecord, config);
			Try!(CheckRecord());
			mReader.Reset(mRecord, config);
			switch (mReader.Next())
			{
			case .Ok:
				return true;
			case .Err(let error):
				return .Err(Relocate(error));
			}
		}
	}

	/// The record read through (its value skipped, which checks it): exactly one value; for
	/// RecordSeparated a top-level number or literal must be followed by whitespace (RFC 7464 §2.4).
	Result<void, JsonParseError> CheckRecord()
	{
		JsonToken first;
		switch (mReader.Next())
		{
		case .Ok(let token):
			first = token;
		case .Err(let error):
			return .Err(Relocate(error));
		}
		// (A string ends at its quote: only numbers and literals can be cut short unseen)
		int scalarEnd = (first == .Number || first == .True || first == .False || first == .Null) ? mReader.EndOffset : -1;
		if (mReader.SkipValue() case .Err(let skipError))
			return .Err(Relocate(skipError));
		switch (mReader.Next())
		{
		case .Ok:
			// (Anything but the end of the document is the reader's error)
		case .Err(let error):
			return .Err(Relocate(error));
		}
		if (mMode == .RecordSeparated && scalarEnd >= 0 && (scalarEnd >= mRecord.Length || !JsonChar.IsSpace(mRecord[scalarEnd])))
		{
			let error = JsonParseError(.InvalidStructure, "A top-level number or literal must be followed by whitespace in a JSON text sequence: the element may be truncated, so it is dropped (RFC 7464 §2.4)",
				0, 0, scalarEnd, 1);
			return .Err(Relocate(error, true));
		}
		return .Ok;
	}

	/// @brief An error of Reader, located in the whole input (with Lines and RecordSeparated the reader
	/// reads one record, so its own positions are the record's).
	/// @param error An error Reader returned for the current value.
	/// @return The error with the input's line, column and offset.
	public JsonParseError Locate(JsonParseError error)
	{
		return mMode == .Concatenated ? error : Relocate(error);
	}

	/// @brief Read the current value into `doc` (its source text, read again as a document of its own:
	/// positions are relative to the value). Reader is then at the value's last token.
	/// @param doc The document, cleared first.
	/// @return .Ok, or an error.
	public Result<void, JsonParseError> ReadDocument(JsonDocument doc)
	{
		StringView raw;
		switch (mReader.ReadRaw())
		{
		case .Ok(let text):
			raw = text;
		case .Err(let error):
			return .Err(mMode == .Concatenated ? error : Relocate(error));
		}
		var config = mConfig;
		config.AllowBom = false;
		return doc.Read(raw, config);
	}

	/// Concatenated: past what is left of the current value, then the next value's first token.
	Result<bool, JsonParseError> NextConcatenated()
	{
		if (mReader.IsStopped)
		{
			mStopped = true;
			return false;
		}
		if (mInRecord)
		{
			mInRecord = false;
			while (mReader.CurrentDepth > 0)
			{
				if (mReader.Next() case .Err(let error))
				{
					mStopped = true;
					return .Err(error);
				}
			}
		}
		// (An error before the next value belongs to it)
		mIndex++;
		switch (mReader.Next())
		{
		case .Ok(let token):
			if (token == .EndOfDocument)
			{
				mIndex--;
				mStopped = true;
				return false;
			}
			mInRecord = true;
			return true;
		case .Err(let error):
			mStopped = true;
			return .Err(error);
		}
	}

	/// The next record into mRecord (with its offset, line and column): a line, or an element between
	/// record separators. False at the end of the input. With Lines, an empty line is an error (its
	/// record consumed) unless SkipEmptyLines.
	Result<bool, JsonParseError> NextRecord()
	{
		char8 delimiter = mMode == .Lines ? '\n' : (char8)0x1E;
		while (true)
		{
			// The bytes up to the delimiter, or the end of the input
			int64 start = Absolute(mPos);
			int end = Find(delimiter);
			if (end < 0)
			{
				if (mStreamFailed)
				{
					var error = JsonParseError(.IoError, "Reading the input failed", 0, 0, start, 0);
					if (!mSourceName.IsEmpty)
						error.SetSource(mSourceName);
					mStopped = true;
					return .Err(error);
				}
				// The rest of the input, if any
				end = Available();
				if (end == mPos)
					return false;
			}
			StringView text = View(mPos, end - mPos);
			int startLine = mLine;
			int startColumn = mMode == .RecordSeparated ? mRecordColumnAfterSeparator : 1;
			// Lines move on past the delimiter; elements after it (the separator starts the next one)
			bool atDelimiter = end < Available();
			mPos = end + (atDelimiter ? 1 : 0);
			for (let c in text)
			{
				if (c == '\n')
					mLine++;
			}
			if (mMode == .Lines && atDelimiter)
				mLine++;
			if (mMode == .RecordSeparated)
			{
				// Where the next element starts on its line: after the separator
				mRecordColumnAfterSeparator = ColumnAfter(text) + (atDelimiter ? 1 : 0);
				if (start == 0 && text.IsEmpty)
					continue;
			}
			if (mMode == .Lines && text.EndsWith('\r'))
				text.RemoveFromEnd(1);
			bool blank = true;
			for (let c in text)
			{
				if (c != ' ' && c != '\t' && c != '\r' && !(mMode == .RecordSeparated && c == '\n'))
				{
					blank = false;
					break;
				}
			}
			if (mMode == .Lines)
				mIndex = startLine;
			if (blank)
			{
				// RFC 7464: consecutive separators are not empty elements; JSON Lines: an empty line is an error
				if (mMode == .RecordSeparated || SkipEmptyLines)
				{
					Compact();
					continue;
				}
				// (A final newline does not start an empty last line)
				if (!atDelimiter && text.IsEmpty)
					return false;
				var error = JsonParseError(.InvalidStructure, "An empty line (JSON Lines: every line is one value; JsonSequenceReader.SkipEmptyLines skips them)", startLine, 1, start, 0);
				if (!mSourceName.IsEmpty)
					error.SetSource(mSourceName);
				Compact();
				return .Err(error);
			}
			if (mMode == .RecordSeparated)
				mIndex++;
			mRecord.Set(text);
			mRecordOffset = start;
			mRecordLine = startLine;
			mRecordColumn = startColumn;
			Compact();
			return true;
		}
	}

	/// RecordSeparated: the column the next element starts at (after its separator).
	int mRecordColumnAfterSeparator = 1;

	/// The column just past `text` on its last line, from the column the text started at.
	int ColumnAfter(StringView text)
	{
		int lastBreak = text.LastIndexOf('\n');
		if (lastBreak < 0)
			return mRecordColumnAfterSeparator + JsonChar.CountCodePoints(text.Ptr, 0, text.Length);
		return 1 + JsonChar.CountCodePoints(text.Ptr, lastBreak + 1, text.Length);
	}

	/// An error of the current record's reader, located in the whole input. `scalar`: an error made
	/// here, whose line and column are still to be found from the record.
	JsonParseError Relocate(JsonParseError error, bool scalar = false)
	{
		var error;
		if (scalar)
		{
			JsonChar.LineAndColumn(mRecord, (int)error.mOffset, let line, let column);
			error.mLine = (int32)line;
			error.mColumn = (int32)column;
		}
		if (error.mLine == 1)
			error.mColumn += (int32)(mRecordColumn - 1);
		if (error.mLine > 0)
			error.mLine += (int32)(mRecordLine - 1);
		error.mOffset += mRecordOffset;
		if (!mSourceName.IsEmpty)
			error.SetSource(mSourceName);
		return error;
	}

	// The input: memory, or a stream read into mPending

	/// The offset of the first `delimiter` from mPos, reading more of a stream as needed; -1 if none
	/// before the end of the input.
	int Find(char8 delimiter)
	{
		if (mStream == null)
		{
			int i = mText.Substring(mPos).IndexOf(delimiter);
			return i < 0 ? -1 : mPos + i;
		}
		int from = mPos;
		while (true)
		{
			for (int i = from; i < mPending.Count; i++)
			{
				if (mPending[i] == delimiter)
					return i;
			}
			from = mPending.Count;
			if (!Fill())
				return -1;
		}
	}

	/// Reads more of the stream into mPending. False at its end (or on an error, or past MaxTokenBytes
	/// for one record).
	bool Fill()
	{
		if (mStreamDone)
			return false;
		if (mConfig.MaxTokenBytes > 0 && mPending.Count - mPos > mConfig.MaxTokenBytes)
		{
			mStreamDone = true;
			mStreamFailed = true;
			return false;
		}
		char8[16384] buffer = ?;
		int chunk = mConfig.StreamBufferBytes > 0 ? Math.Clamp(mConfig.StreamBufferBytes, 16, buffer.Count) : buffer.Count;
		switch (mStream.TryRead(.((uint8*)&buffer, chunk)))
		{
		case .Ok(let read):
			if (read <= 0)
			{
				mStreamDone = true;
				return false;
			}
			mPending.AddRange(Span<char8>(&buffer, read));
			return true;
		case .Err:
			mStreamDone = true;
			mStreamFailed = true;
			return false;
		}
	}

	int Available() => mStream == null ? mText.Length : mPending.Count;

	StringView View(int start, int length) => mStream == null ? mText.Substring(start, length) : StringView(mPending.Ptr + start, length);

	int64 Absolute(int pos) => mStream == null ? pos : mBase + pos;

	/// Drops the consumed bytes of a stream's buffer (the record was copied to mRecord).
	void Compact()
	{
		if (mStream == null || mPos == 0)
			return;
		mPending.RemoveRange(0, mPos);
		mBase += mPos;
		mPos = 0;
	}
}
