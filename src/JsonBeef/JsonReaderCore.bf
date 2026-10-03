using System;
using System.Collections;
using FormatCore;
using internal FormatCore;
using internal JsonBeef;

namespace JsonBeef;

/// The error type of the reader's internal methods: empty, so their results are no bigger than their
/// values (KdlBeef measured a JsonParseError-sized error in every Result as a real cost). The error
/// itself is recorded in the reader by Fail, and Next returns it.
internal struct JsonFailure
{
}

/// The reader itself, over a cursor (in-memory text or a buffered stream). It reads through a window:
/// `mData[offset]` for `mBase <= offset < mEnd`, offsets absolute, so the offsets it keeps survive the
/// window moving. Anything that may read at the window's end asks for more first (`Avail`, `AvailN`,
/// `Grow`); for in-memory text the window is the whole input and those checks compile away.
///
/// Parsing is iterative: the open containers are a bit stack (1 = object), so depth costs a bit, not
/// stack. Every token is fully validated when it is read (UTF-8 up front, then grammar, escapes and
/// surrogate pairs, number grammar); strings with escapes are decoded into a reusable buffer.
///
/// Invariants:
/// - **Retention.** The window keeps every byte from min(mRetain, mPos) on: mRetain is the start of the
///   token being read, and stays there until the next call, so the token's views stay valid; a new call
///   releases it.
/// - **Views.** mValue and mRaw view the window or mStringBuffer: valid until the next call (Grow
///   rebases them when the window moves). mError views the per-thread error buffers.
internal class JsonReaderCore<TCursor> where TCursor : IJsonCursor
{
	enum State : uint8
	{
		/// Not set up yet: the cursor's Begin comes first.
		Start,
		/// A value: the document's, an array element after `,`, or a member's after `:`.
		Value,
		/// After `[`: an element or `]`.
		ArrayStart,
		/// After `{`: a member name or `}`.
		ObjectStart,
		/// After `,` in an object: a member name.
		Name,
		/// After a member name: `:` and the value.
		Colon,
		/// After a value: `,` or the container's end, or at depth 0 the end of the input.
		AfterValue,
		/// Collect-errors: End tokens of containers recovery closes (mPendingCloses; with mClosingAtEnd
		/// every open one, then the end of the document), then AfterValue.
		Closing,
		End,
		Failed
	}

	internal TCursor mCursor;
	char8* mData;
	int mBase;
	int mPos;
	int mEnd;
	/// The start of the token being read (int.MaxValue: none).
	int mRetain;
	/// ReadRaw: the start of the value being skipped, kept in the window with everything after it until
	/// the next public NextToken (int.MaxValue: none).
	int mHold = int.MaxValue;
	/// The cursor stopped on an error of the input; the reader's next error is replaced by it.
	bool mInputFailed;
	State mState;
	internal JsonParseError mError;
	JsonReadConfig mConfig;
	/// mConfig.Dialect is Json5 (JsonReaderCore.Json5.bf).
	bool mJson5;
	/// Concatenated values (JsonSequenceReader): after a value at depth 0 another may follow, and an
	/// input without any is not an error. Reset clears it.
	internal bool mMultipleValues;

	/// The open containers: bit d is set when the container at depth d (0-based) is an object.
	uint64[] mBits ~ delete _;
	int mDepth;

	/// JSON5's decoded strings and normalized numbers
	String mStringBuffer ~ delete _;
	/// JSON's decoded strings (DecodeEscaped)
	JsonDecodeBuffer mDecodeBuffer ~ delete _;

	// The current token
	internal JsonToken mToken;
	internal int mTokenStart;
	internal int mTokenEnd;
	/// The token's depth: the open containers around it (a Start token's own is not around it).
	internal int TokenDepth
	{
		[Inline]
		get => mToken == .StartObject || mToken == .StartArray ? mDepth - 1 : mDepth;
	}
	/// String, PropertyName: the decoded text. Number, literals: the token's text.
	internal StringView mValue;
	/// String, PropertyName: the text between the quotes, escapes as written. Number, literals: the
	/// token's text.
	internal StringView mRaw;
	internal bool mEscaped;
	internal JsonNumberKind mNumberKind;
	/// Integer: the value. UInteger: the value's bits.
	internal int64 mInteger;
	/// Float: the first 19 significant digits as an integer, the decimal exponent that goes with them,
	/// and whether those are all the digits (Clinger's fast path then applies).
	internal uint64 mFloatMantissa;
	internal int32 mFloatExponent;
	internal bool mFloatExact;

	// Collect-errors (JsonReadConfig.CollectErrors)
	int mErrorCount;
	/// Where the last error was: an error at or before it moves the resynchronization a byte on, so
	/// recovery always progresses.
	int mLastErrorOffset;
	/// The string being read (its opening quote; -1 when none) and whether it is a member name: an
	/// error inside one is resynchronized at its closing quote.
	int mStringStart;
	bool mStringIsName;
	/// End tokens still to report for containers recovery closes (State.Closing).
	int mPendingCloses;
	/// The input ended at an error: every open container gets its End token, then EndOfDocument.
	bool mClosingAtEnd;

	public this()
	{
		mBits = new uint64[16];
		mStringBuffer = new .();
		mDecodeBuffer = new .();
		mConfig = .();
	}

	public void Reset(TCursor cursor, JsonReadConfig config)
	{
		mCursor = cursor;
		mConfig = config;
		if (config.Dialect == .Json5)
		{
			mConfig.Comments = true;
			mConfig.TrailingCommas = true;
			mConfig.AllowNonFiniteNumbers = true;
		}
		if (config.IJson)
		{
			// I-JSON is UTF-8 Unicode text with finite numbers, in JSON's grammar: no leniency
			mConfig.Dialect = .Json;
			mConfig.AllowNonFiniteNumbers = false;
			mConfig.InvalidUtf8 = .Error;
			mConfig.InvalidSurrogates = .Error;
		}
		mJson5 = mConfig.Dialect == .Json5;
		mMultipleValues = false;
		mData = null;
		mBase = 0;
		mPos = 0;
		mEnd = 0;
		mRetain = int.MaxValue;
		mHold = int.MaxValue;
		mInputFailed = false;
		mState = .Start;
		mDepth = 0;
		mToken = .None;
		mTokenStart = 0;
		mTokenEnd = 0;
		mValue = default;
		mRaw = default;
		mEscaped = false;
		mNumberKind = .Integer;
		mInteger = 0;
		mErrorCount = 0;
		mLastErrorOffset = -1;
		mStringStart = -1;
		mStringIsName = false;
		mPendingCloses = 0;
		mClosingAtEnd = false;
	}

	/// The next token; on failure the error is in mError. (JsonReader.Next makes the public Result, so
	/// the large error is copied once.)
	[Inline]
	public Result<JsonToken, JsonFailure> NextToken()
	{
		if (mState == .Failed)
			return .Err(.());
		// A value ReadRaw kept is released (memory input keeps everything anyway)
		if (!mCursor.IsWhole)
			mHold = int.MaxValue;
		let result = ReadNext();
		if (result case .Err)
			AfterError();
		return result;
	}

	/// Push input: the next token if the bytes fed so far hold all of it, else (`starved`) nothing: the
	/// reader goes back to before the token, as if it had not started, to read it again once more is
	/// fed or the input is finished. So a token is read only whole, with the same result as from memory.
	/// The token is then None: what the previous one held may already be overwritten.
	public Result<JsonToken, JsonFailure> NextTokenPush(out bool starved)
	{
		starved = false;
		if (mState == .Failed)
			return .Err(.());
		// Everything a token can change before it turns out to be cut off
		int pos = mPos;
		State state = mState;
		int depth = mDepth;
		int stringStart = mStringStart;
		bool stringIsName = mStringIsName;
		int pendingCloses = mPendingCloses;
		bool closingAtEnd = mClosingAtEnd;
		int lastErrorOffset = mLastErrorOffset;
		mCursor.TakeStarved();
		let result = ReadNext();
		if (mCursor.TakeStarved())
		{
			// (Cut off inside a string: only a `"` fed later can end it)
			mStarvedInString = mStringStart >= 0;
			// No token: the previous one's values may be gone (its decoded text, its number's parts)
			mPos = pos;
			mState = state;
			mDepth = depth;
			mToken = .None;
			mTokenStart = pos;
			mTokenEnd = pos;
			mValue = default;
			mRaw = default;
			mEscaped = false;
			mStringStart = stringStart;
			mStringIsName = stringIsName;
			mPendingCloses = pendingCloses;
			mClosingAtEnd = closingAtEnd;
			mLastErrorOffset = lastErrorOffset;
			mInputFailed = false;
			starved = true;
			return .Ok(.None);
		}
		if (result case .Err)
			AfterError();
		return result;
	}

	/// Push input: the last NextTokenPush ran out inside a string.
	public bool mStarvedInString;

	/// Push input: where the bytes the reader still needs start (the current token, or what is being
	/// read). Bytes before it may be dropped.
	public int KeepFrom => Math.Min(Math.Min(mRetain, mHold), mPos);

	/// Push input: takes in the window as it is after a Feed (moved, longer, or finished), moving the
	/// token's views with it.
	public void RefreshWindow()
	{
		if (mData == null)
			return;
		char8* oldData = mData;
		int oldBase = mBase;
		int oldEnd = mEnd;
		mCursor.Fill(ref mData, ref mBase, ref mEnd, KeepFrom, mPos, 0);
		if (mData != oldData)
			RebaseViews(oldData, oldBase, oldEnd);
	}

	/// Whether the read has stopped at an error.
	public bool IsStopped => mState == .Failed;

	/// The current depth: the number of open containers.
	public int CurrentDepth => mDepth;

	/// The config the reader was reset with.
	public JsonReadConfig Config => mConfig;

	// On-demand

	/// Past the value the current token starts, checking every token as NextToken does (strings,
	/// escapes, UTF-8, numbers, structure), to its last token: a container's End token; a scalar is its
	/// own. At a PropertyName, the member's value; before the first token, the document's value. At an
	/// End token or the end of the document there is nothing to skip.
	public Result<void, JsonFailure> SkipValue()
	{
		if (mState == .Failed)
			return .Err(.());
		if (mToken == .None || mToken == .PropertyName)
			Try!(Step());
		if (mToken != .StartObject && mToken != .StartArray)
			return .Ok;
		int depth = mDepth - 1;
		if (SkipFast(depth))
			return .Ok;
		repeat
		{
			Try!(Step());
		}
		while (mDepth > depth);
		return .Ok;
	}

	/// SkipValue's loop for memory input: the container from mPos to its end, checked as the token loop
	/// checks it (structure, strings with their escapes and UTF-8, numbers, literals, depth and length
	/// limits), but without making tokens or decoding strings. Anything it does not take (an error, a
	/// comment, a trailing comma, a string or number past its limit) is handed to the token loop where it
	/// is, in the equivalent state, which reports the exact error or reads on: as FastBuild hands over to
	/// the reader.
	/// @return Whether it reached the end of the container at `depth` (mToken its End token).
	bool SkipFast(int depth)
	{
		// (I-JSON's checks on strings and numbers are the token loop's)
		if (!mCursor.IsWhole || mConfig.CollectErrors || mConfig.IJson)
			return false;
		while (true)
		{
			SkipSpace();
			if (mPos >= mEnd)
				return false;
			char8 c = mData[mPos];
			switch (mState)
			{
			case .ObjectStart, .Name:
				if (c == '}' && mState == .ObjectStart)
				{
					EndContainer();
					if (mDepth == depth)
						return true;
					continue;
				}
				if (c != '"')
					return false;
				int end = StringEnd(mPos);
				if (end < 0 || (mConfig.MaxStringBytes > 0 && end - mPos - 1 > mConfig.MaxStringBytes))
					return false;
				mPos = end + 1;
				mState = .Colon;
			case .Colon:
				if (c != ':')
					return false;
				mPos++;
				mState = .Value;
			case .ArrayStart, .Value:
				if (c == ']' && mState == .ArrayStart)
				{
					EndContainer();
					if (mDepth == depth)
						return true;
					continue;
				}
				switch (JsonChar.sByteClass[(uint8)c])
				{
				case .Quote:
					int end = StringEnd(mPos);
					if (end < 0 || (mConfig.MaxStringBytes > 0 && end - mPos - 1 > mConfig.MaxStringBytes))
						return false;
					mPos = end + 1;
				case .Number:
					int end = NumberEnd(mPos);
					if (end < 0 || (mConfig.MaxNumberLength > 0 && end - mPos > mConfig.MaxNumberLength))
						return false;
					mPos = end;
				case .Literal:
					int end = LiteralEnd(mPos);
					if (end < 0)
						return false;
					mPos = end;
				case .Punct:
					if (c != '[' && c != '{')
						return false;
					if (mConfig.MaxDepth > 0 && mDepth >= mConfig.MaxDepth)
						return false;
					StartContainer(c == '{');
					continue;
				default:
					return false;
				}
				mState = .AfterValue;
			case .AfterValue:
				bool inObject = InObject;
				if (c == ',')
				{
					mPos++;
					mState = inObject ? .Name : .Value;
				}
				else if (c == (inObject ? '}' : ']'))
				{
					EndContainer();
					if (mDepth == depth)
						return true;
				}
				else
					return false;
			default:
				return false;
			}
		}
	}

	/// The closing quote of the well-formed string whose opening quote is at `start` (escapes and
	/// surrogate pairs checked, UTF-8 checked), or -1 for anything else. Memory input.
	int StringEnd(int start)
	{
		int p = start + 1;
		while (true)
		{
			p = ScanStringRun(p);
			if (p >= mEnd)
				return -1;
			char8 c = mData[p];
			if (c == '"')
				return p;
			if (c == '\\')
			{
				if (p + 1 >= mEnd)
					return -1;
				switch (mData[p + 1])
				{
				case '"', '\\', '/', 'b', 'f', 'n', 'r', 't':
					p += 2;
				case 'u':
					int cp = Hex4At(p);
					if (cp < 0)
						return -1;
					if (cp < 0xD800 || cp > 0xDFFF)
						p += 6;
					else
					{
						// A high surrogate, and its escaped low one
						if (cp >= 0xDC00 || p + 7 >= mEnd || mData[p + 6] != '\\' || mData[p + 7] != 'u')
							return -1;
						int low = Hex4At(p + 6);
						if (low < 0xDC00 || low > 0xDFFF)
							return -1;
						p += 12;
					}
				default:
					return -1;
				}
				continue;
			}
			if ((uint8)c < 0x20)
				return -1;
			// Non-ASCII: as many well-formed sequences as follow
			repeat
			{
				int length = Utf8.ValidSequenceLength(mData, p, mEnd);
				if (length == 0)
					return -1;
				p += length;
			}
			while (p < mEnd && (uint8)mData[p] >= 0x80);
		}
	}

	/// The value of the `\u` escape at `p` (its backslash), or -1. Memory input.
	int Hex4At(int p)
	{
		if (p + 6 > mEnd)
			return -1;
		uint32 value = Hex.Digits4(mData + p + 2);
		return value <= 0xFFFF ? (int)value : -1;
	}

	/// The end of the well-formed number at `start` (followed by nothing that would continue it), or -1.
	/// Memory input.
	int NumberEnd(int start)
	{
		int p = start;
		if (mData[p] == '-')
			p++;
		if (p >= mEnd || !JsonChar.IsDigit(mData[p]))
			return -1;
		if (mData[p] == '0')
		{
			p++;
			if (p < mEnd && JsonChar.IsDigit(mData[p]))
				return -1;
		}
		else
		{
			while (p < mEnd && JsonChar.IsDigit(mData[p]))
				p++;
		}
		if (p < mEnd && mData[p] == '.')
		{
			p++;
			if (p >= mEnd || !JsonChar.IsDigit(mData[p]))
				return -1;
			while (p < mEnd && JsonChar.IsDigit(mData[p]))
				p++;
		}
		if (p < mEnd && (mData[p] == 'e' || mData[p] == 'E'))
		{
			p++;
			if (p < mEnd && (mData[p] == '+' || mData[p] == '-'))
				p++;
			if (p >= mEnd || !JsonChar.IsDigit(mData[p]))
				return -1;
			while (p < mEnd && JsonChar.IsDigit(mData[p]))
				p++;
		}
		if (p < mEnd && (IsWordByte(mData[p]) || mData[p] == '.' || mData[p] == '+' || mData[p] == '-'))
			return -1;
		return p;
	}

	/// The end of the literal `true`, `false` or `null` at `start`, or -1. Memory input.
	int LiteralEnd(int start)
	{
		char8 c = mData[start];
		uint32 expected = c == 't' ? 0x65757274 : c == 'f' ? 0x736C6166 : 0x6C6C756E;
		int length = c == 'f' ? 5 : 4;
		if (start + length > mEnd || Swar.Load32(mData + start) != expected || (length == 5 && mData[start + 4] != 'e') ||
			(start + length < mEnd && IsWordByte(mData[start + length])))
			return -1;
		return start + length;
	}

	/// The source text of the value the current token starts (as SkipValue, which moves the reader to
	/// its last token): a string with its quotes, a container from bracket to bracket. A stream keeps
	/// the text in its window until the next NextToken, so it is bounded by MaxTokenBytes there.
	public Result<StringView, JsonFailure> ReadRaw()
	{
		if (mState == .Failed)
			return .Err(.());
		if (mToken == .None || mToken == .PropertyName)
			Try!(Step());
		int start = mTokenStart;
		if (mToken == .StartObject || mToken == .StartArray)
		{
			if (!mCursor.IsWhole)
				mHold = start;
			Try!(SkipValue());
		}
		else if (mToken == .EndObject || mToken == .EndArray || mToken == .EndOfDocument)
			return View(mTokenStart, 0);
		return View(start, mTokenEnd - start);
	}

	/// At a StartObject: looks ahead for the member `name` (its value's first token in `token`, a string's
	/// text appended to `text`), then goes back to just after the `{` as if nothing was read. Members
	/// passed are checked as SkipValue checks them. A stream keeps the object in its window meanwhile.
	/// @return Whether the member is there.
	public Result<bool, JsonFailure> PeekMember(StringView name, out JsonToken token, String text)
	{
		token = .None;
		int pos = mPos;
		State state = mState;
		int depth = mDepth;
		int tokenStart = mTokenStart;
		int tokenEnd = mTokenEnd;
		if (!mCursor.IsWhole)
			mHold = tokenStart;
		bool found = false;
		while (true)
		{
			if (Try!(Step()) != .PropertyName)
				break;
			bool match = mValue == name;
			Try!(Step());
			if (match)
			{
				found = true;
				token = mToken;
				if (mToken == .String)
					text.Append(mValue);
				break;
			}
			Try!(SkipValue());
		}
		// Back to the start: the open containers' bits below this object did not change
		mPos = pos;
		mState = state;
		mDepth = depth;
		mToken = .StartObject;
		mTokenStart = tokenStart;
		mTokenEnd = tokenEnd;
		mValue = default;
		mRaw = default;
		return found;
	}

	/// One token for SkipValue and ReadRaw: as NextToken, keeping what ReadRaw holds.
	[Inline]
	Result<JsonToken, JsonFailure> Step()
	{
		let result = ReadNext();
		if (result case .Err)
			AfterError();
		return result;
	}

	Result<JsonToken, JsonFailure> ReadNext()
	{
		Retain(int.MaxValue);
		switch (mState)
		{
		case .Start:
			switch (mCursor.Begin(ref mData, ref mBase, ref mEnd))
			{
			case .Ok(let start):
				mPos = start;
			case .Err(let error):
				mError = error;
				if (!mConfig.SourceName.IsEmpty)
					mError.SetSource(mConfig.SourceName);
				return .Err(.());
			}
			mState = .Value;
			if (mMultipleValues)
			{
				// Concatenated values: none at all is an empty sequence
				SkipSpace();
				while (SkipJson5Space())
				{
				}
				if (!Avail(mPos))
				{
					mState = .End;
					mToken = .EndOfDocument;
					mTokenStart = mPos;
					mTokenEnd = mPos;
					return .Ok(.EndOfDocument);
				}
			}
			return ReadValue(false);
		case .Value:
			return ReadValue(true);
		case .ArrayStart:
			SkipSpace();
			if (Avail(mPos) && mData[mPos] == ']')
				return EndContainer();
			return ReadValue(false);
		case .ObjectStart:
			SkipSpace();
			if (!Avail(mPos))
				return .Err(EndOfInput("The input ends inside an object: expected a member name or `}`"));
			if (mData[mPos] == '}')
				return EndContainer();
			if (mJson5)
				return ReadName5();
			if (mData[mPos] == '"')
				return ReadString(true);
			return .Err(Unexpected(.InvalidStructure, "a member name (a string in double quotes) or `}`"));
		case .Name:
			return ReadNameAfterComma();
		case .Colon:
			SkipSpace();
			if (!Avail(mPos))
				return .Err(EndOfInput("The input ends inside an object: expected `:` after the member name"));
			if (mData[mPos] != ':')
			{
				if (SkipJson5Space())
					return ReadNext();
				return .Err(Unexpected(.InvalidStructure, "`:` after the member name"));
			}
			mPos++;
			SkipOneSpace();
			mState = .Value;
			return ReadValue(false);
		case .AfterValue:
			return ReadAfterValue();
		case .Closing:
			return ReadClosing();
		case .End:
			return .Ok(.EndOfDocument);
		case .Failed:
			return .Err(.());
		}
	}

	/// After a value: `,` or the container's end; at depth 0, nothing but whitespace.
	[Inline]
	Result<JsonToken, JsonFailure> ReadAfterValue()
	{
		SkipSpace();
		if (mDepth == 0)
		{
			if (Avail(mPos))
				return UnexpectedAfterValue();
			mState = .End;
			mToken = .EndOfDocument;
			mTokenStart = mPos;
			mTokenEnd = mPos;
			return .Ok(.EndOfDocument);
		}
		bool inObject = InObject;
		if (!Avail(mPos))
			return .Err(EndOfInput(inObject ? "The input ends inside an object: expected `,` or `}`" : "The input ends inside an array: expected `,` or `]`"));
		char8 c = mData[mPos];
		if (c == ',')
		{
			mPos++;
			if (inObject)
				return ReadNameAfterComma();
			mState = .Value;
			return ReadValue(true);
		}
		if (c == (inObject ? '}' : ']'))
			return EndContainer();
		return UnexpectedAfterValue();
	}

	/// After a value, something that is neither `,` nor the container's end (nor, at depth 0, the end of
	/// the input): JSON5's other whitespace, after which the state reads again, or the error. Out of
	/// line, so that ReadAfterValue stays small and inlined.
	[NoInline]
	Result<JsonToken, JsonFailure> UnexpectedAfterValue()
	{
		if (SkipJson5Space())
			return ReadAfterValue();
		if (mDepth == 0)
		{
			// Concatenated values (JsonSequenceReader): the next one starts here
			if (mMultipleValues)
			{
				mState = .Value;
				return ReadValue(false);
			}
			return .Err(Unexpected(.InvalidStructure, "the end of the input after the JSON value (a document holds one value)"));
		}
		return .Err(Unexpected(.InvalidStructure, InObject ? "`,` or `}` after a member's value" : "`,` or `]` after an array element"));
	}

	/// After `,` in an object: the next member's name.
	[Inline]
	Result<JsonToken, JsonFailure> ReadNameAfterComma()
	{
		mState = .Name;
		SkipSpace();
		if (!Avail(mPos))
			return .Err(EndOfInput("The input ends inside an object: expected a member name after `,`"));
		char8 c = mData[mPos];
		if (c == '"' && !mJson5)
			return ReadString(true);
		if (c == '}')
		{
			if (mConfig.TrailingCommas)
				return EndContainer();
			return .Err(Fail(.InvalidStructure, "Expected a member name after `,`, found `}` (a trailing comma is not allowed)", mPos));
		}
		if (mJson5)
			return ReadName5();
		return .Err(Unexpected(.InvalidStructure, "a member name (a string in double quotes) after `,`"));
	}

	/// A value: a scalar token, or the start of a container. `afterComma`: in an array after `,` (for
	/// the trailing-comma message).
	Result<JsonToken, JsonFailure> ReadValue(bool afterComma)
	{
		SkipSpace();
		if (!Avail(mPos))
		{
			if (mDepth == 0)
				return .Err(EndOfInput("Expected a JSON value, found the end of the input"));
			return .Err(EndOfInput(InObject ? "The input ends inside an object: expected a value" : "The input ends inside an array: expected a value"));
		}
		char8 c = mData[mPos];
		switch (JsonChar.sByteClass[(uint8)c])
		{
		case .Quote:
			if (mJson5)
				return ReadString5(false);
			return ReadString(false);
		case .Number:
			if (mJson5)
				return ReadNumber5();
			return ReadNumber();
		case .Literal:
			return ReadLiteral();
		case .Punct:
			if (c == '[')
				return StartContainer(false);
			if (c == '{')
				return StartContainer(true);
			if (c == ']' && afterComma && mDepth > 0 && !InObject)
			{
				if (mConfig.TrailingCommas)
					return EndContainer();
				return .Err(Fail(.InvalidStructure, "Expected a value after `,`, found `]` (a trailing comma is not allowed)", mPos));
			}
			return .Err(Unexpected(.InvalidStructure, "a value"));
		default:
			if (mJson5)
			{
				if (c == '\'')
					return ReadString5(false);
				if (c == '+' || c == '.' || c == 'N' || c == 'I')
					return ReadNumber5();
				// (After `[` the state reads again: the array may be empty)
				if (SkipJson5Space())
					return mState == .ArrayStart ? ReadNext() : ReadValue(afterComma);
			}
			if ((c == 'N' || c == 'I') && mConfig.AllowNonFiniteNumbers)
				return ReadNonFinite(mPos);
			return .Err(UnexpectedInValue());
		}
	}

	/// `NaN`, `Infinity` or `-Infinity` at `start` (AllowNonFiniteNumbers): a number of kind NonFinite.
	Result<JsonToken, JsonFailure> ReadNonFinite(int start)
	{
		Retain(start);
		int p = start;
		if (mData[p] == '-')
			p++;
		StringView expected = (Avail(p) && mData[p] == 'N') ? "NaN" : "Infinity";
		int end = WordEnd(p);
		if (end - p != expected.Length || View(p, expected.Length) != expected || (expected == "NaN" && p > start))
		{
			end = Math.Max(end, p);
			return .Err(Fail(.InvalidNumber, scope $"Invalid number `{View(start, end - start)}` (the non-finite numbers are `NaN`, `Infinity` and `-Infinity`)", start, Math.Max(end - start, 1)));
		}
		mNumberKind = .NonFinite;
		mToken = .Number;
		mTokenStart = start;
		mTokenEnd = end;
		mValue = View(start, end - start);
		mRaw = mValue;
		mEscaped = false;
		mPos = end;
		mState = .AfterValue;
		return .Ok(.Number);
	}

	/// The error for a byte that cannot start a value, worded for the likely cause.
	JsonFailure UnexpectedInValue()
	{
		char8 c = mData[mPos];
		if (c == '\'')
			return Fail(.UnexpectedChar, "Expected a value, found `'` (strings are written in double quotes)", mPos);
		if (c == '+')
			return Fail(.InvalidNumber, "A number cannot start with `+`", mPos);
		if (c == '.')
			return Fail(.InvalidNumber, "A number needs a digit before its decimal point (`0.5`, not `.5`)", mPos);
		if (IsWordByte(c))
		{
			int end = WordEnd(mPos);
			StringView word = View(mPos, end - mPos);
			if (word == "NaN" || word == "Infinity")
				return Fail(.InvalidNumber, scope $"`{word}` is not a JSON number (JsonReadConfig.AllowNonFiniteNumbers allows `NaN`, `Infinity` and `-Infinity`)", mPos, end - mPos);
			return Fail(.InvalidLiteral, scope $"Invalid literal `{word}` (JSON's literals are `true`, `false` and `null`)", mPos, end - mPos);
		}
		return Unexpected(.UnexpectedChar, "a value");
	}

	Result<JsonToken, JsonFailure> StartContainer(bool isObject)
	{
		if (mConfig.MaxDepth > 0 && mDepth >= mConfig.MaxDepth)
			return .Err(Fail(.ResourceLimitExceeded, scope $"The nesting depth exceeds MaxDepth ({mConfig.MaxDepth})", mPos));
		int word = mDepth >> 6;
		if (word >= mBits.Count)
		{
			let old = mBits;
			mBits = new uint64[old.Count * 2];
			old.CopyTo(mBits);
			delete old;
		}
		uint64 bit = 1UL << (mDepth & 63);
		if (isObject)
			mBits[word] |= bit;
		else
			mBits[word] &= ~bit;
		mToken = isObject ? .StartObject : .StartArray;
		mTokenStart = mPos;
		mTokenEnd = mPos + 1;
		mDepth++;
		mPos++;
		mState = isObject ? .ObjectStart : .ArrayStart;
		return .Ok(mToken);
	}

	Result<JsonToken, JsonFailure> EndContainer()
	{
		mDepth--;
		mToken = mData[mPos] == '}' ? .EndObject : .EndArray;
		mTokenStart = mPos;
		mTokenEnd = mPos + 1;
		mPos++;
		mState = .AfterValue;
		return .Ok(mToken);
	}

	/// Whether the innermost open container is an object (mDepth > 0).
	bool InObject
	{
		[Inline]
		get
		{
			int d = mDepth - 1;
			return ((mBits[d >> 6] >> (d & 63)) & 1) != 0;
		}
	}

	// Literals

	Result<JsonToken, JsonFailure> ReadLiteral()
	{
		int start = mPos;
		Retain(start);
		char8 c = mData[start];
		// The literal's first four bytes as a little-endian word (and `false`'s `e`)
		uint32 expected = c == 't' ? 0x65757274 : c == 'f' ? 0x736C6166 : 0x6C6C756E;
		int length = c == 'f' ? 5 : 4;
		if (!AvailN(start, length) || Swar.Load32(mData + start) != expected || (length == 5 && mData[start + 4] != 'e') ||
			(Avail(start + length) && IsWordByte(mData[start + length])))
		{
			StringView literal = c == 't' ? "true" : c == 'f' ? "false" : "null";
			int end = WordEnd(start);
			StringView word = View(start, end - start);
			if (word.Length < length && literal.StartsWith(word))
			{
				if (!Avail(end))
					return .Err(Fail(.InvalidLiteral, scope $"The input ends inside the literal `{literal}` (found `{word}`)", start, end - start));
				return .Err(Fail(.InvalidLiteral, scope $"Invalid literal `{word}` (expected `{literal}`)", start, end - start));
			}
			return .Err(Fail(.InvalidLiteral, scope $"Invalid literal `{word}` (JSON's literals are `true`, `false` and `null`)", start, end - start));
		}
		mToken = c == 't' ? .True : c == 'f' ? .False : .Null;
		mTokenStart = start;
		mTokenEnd = start + length;
		mValue = View(start, length);
		mRaw = mValue;
		mEscaped = false;
		mPos = start + length;
		mState = .AfterValue;
		return .Ok(mToken);
	}

	[Inline]
	static bool IsWordByte(char8 c)
	{
		return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
	}

	/// The end of the run of ASCII letters, digits and `_` from `pos` (at most 32 bytes: it only words
	/// error messages).
	int WordEnd(int pos)
	{
		int end = pos;
		while (end - pos < 32 && Avail(end) && IsWordByte(mData[end]))
			end++;
		return end;
	}

	// Numbers

	Result<JsonToken, JsonFailure> ReadNumber()
	{
		int start = mPos;
		Retain(start);
		int p = start;
		bool negative = false;
		if (mData[p] == '-')
		{
			negative = true;
			p++;
			if (Avail(p) && mData[p] == 'I')
			{
				if (mConfig.AllowNonFiniteNumbers)
					return ReadNonFinite(start);
				int end = WordEnd(p);
				if (View(p, end - p) == "Infinity")
					return .Err(Fail(.InvalidNumber, "`-Infinity` is not a JSON number (JsonReadConfig.AllowNonFiniteNumbers allows `NaN`, `Infinity` and `-Infinity`)", start, end - start));
			}
			if (!Avail(p) || !JsonChar.IsDigit(mData[p]))
				return .Err(NumberError("Expected a digit after `-`", p));
		}
		uint64 magnitude = 0;
		int digits = 0;
		bool big = false;
		if (mData[p] == '0')
		{
			p++;
			digits = 1;
			if (Avail(p) && JsonChar.IsDigit(mData[p]))
				return .Err(Fail(.InvalidNumber, "A number cannot have a leading zero (`01`): write `1`, or `0.1` for a fraction", start, p + 1 - start));
		}
		else
		{
			// 19 digits always fit; the 20th may overflow; more make a big integer
			while (true)
			{
				// Eight digits at a time while they fit
				while (digits <= 11 && p + 8 <= mEnd)
				{
					uint64 word = Swar.Load64(mData + p);
					if (!Swar.AllDigits(word))
						break;
					magnitude = magnitude * 100000000 + Swar.ParseEightDigits(word);
					digits += 8;
					p += 8;
				}
				while (p < mEnd && JsonChar.IsDigit(mData[p]))
				{
					uint64 digit = (uint8)mData[p] - (uint8)'0';
					if (digits < 19)
						magnitude = magnitude * 10 + digit;
					else if (digits == 19 && (magnitude < 1844674407370955161UL || (magnitude == 1844674407370955161UL && digit <= 5)))
						magnitude = magnitude * 10 + digit;
					else
						big = true;
					digits++;
					p++;
				}
				if (p < mEnd || !Grow(p, 1))
					break;
			}
		}
		bool isFloat = false;
		// For a float, Clinger's fast path in GetDouble: the first 19 digits as a mantissa (exact when
		// there are no more) and the decimal exponent, gathered in this one scan
		uint64 mantissa = magnitude;
		int mantissaDigits = digits;
		bool exact = digits <= 19;
		int exponent = 0;
		if (Avail(p) && mData[p] == '.')
		{
			p++;
			if (!Avail(p) || !JsonChar.IsDigit(mData[p]))
				return .Err(NumberError("Expected a digit after the decimal point", p));
			while (true)
			{
				while (mantissaDigits <= 11 && p + 8 <= mEnd)
				{
					uint64 word = Swar.Load64(mData + p);
					if (!Swar.AllDigits(word))
						break;
					mantissa = mantissa * 100000000 + Swar.ParseEightDigits(word);
					mantissaDigits += 8;
					exponent -= 8;
					p += 8;
				}
				while (p < mEnd && JsonChar.IsDigit(mData[p]))
				{
					if (mantissaDigits < 19)
					{
						mantissa = mantissa * 10 + (uint64)((uint8)mData[p] - (uint8)'0');
						mantissaDigits++;
						exponent--;
					}
					else
						exact = false;
					p++;
				}
				if (p < mEnd || !Grow(p, 1))
					break;
			}
			isFloat = true;
		}
		if (Avail(p) && (mData[p] == 'e' || mData[p] == 'E'))
		{
			p++;
			bool negativeExponent = false;
			if (Avail(p) && (mData[p] == '+' || mData[p] == '-'))
			{
				negativeExponent = mData[p] == '-';
				p++;
			}
			if (!Avail(p) || !JsonChar.IsDigit(mData[p]))
				return .Err(NumberError("Expected a digit in the exponent", p));
			// Saturating: any exponent this large already means 0 or overflow (or the fast path is off)
			int explicitExponent = 0;
			while (true)
			{
				while (p < mEnd && JsonChar.IsDigit(mData[p]))
				{
					if (explicitExponent < 100000)
						explicitExponent = explicitExponent * 10 + ((uint8)mData[p] - (uint8)'0');
					p++;
				}
				if (p < mEnd || !Grow(p, 1))
					break;
			}
			exponent += negativeExponent ? -explicitExponent : explicitExponent;
			isFloat = true;
		}
		int length = p - start;
		if (mConfig.MaxNumberLength > 0 && length > mConfig.MaxNumberLength)
			return .Err(Fail(.ResourceLimitExceeded, scope $"The number ({length} bytes) exceeds MaxNumberLength ({mConfig.MaxNumberLength})", start, length));
		// Something that continues the number's text: a malformed number, not a missing separator
		if (Avail(p) && (IsWordByte(mData[p]) || mData[p] == '.' || mData[p] == '+' || mData[p] == '-'))
		{
			let message = scope String();
			message.Append("Unexpected ");
			Hex.AppendCharDescription(message, mData, p, mEnd, let charLength);
			message.AppendF(" after the number `{}`", View(start, length));
			return .Err(Fail(.InvalidNumber, message, p, charLength));
		}
		if (isFloat)
		{
			mNumberKind = .Float;
			mFloatMantissa = mantissa;
			mFloatExponent = (int32)exponent;
			mFloatExact = exact && !big;
		}
		else if (big)
			mNumberKind = .BigInteger;
		else if (negative)
		{
			if (magnitude <= (uint64)int64.MaxValue + 1)
			{
				mNumberKind = .Integer;
				mInteger = magnitude == 0 ? 0 : -(int64)(magnitude - 1) - 1;
			}
			else
				mNumberKind = .BigInteger;
		}
		else if (magnitude <= (uint64)int64.MaxValue)
		{
			mNumberKind = .Integer;
			mInteger = (int64)magnitude;
		}
		else
		{
			mNumberKind = .UInteger;
			mInteger = (int64)magnitude;
		}
		mToken = .Number;
		mTokenStart = start;
		mTokenEnd = p;
		mValue = View(start, length);
		mRaw = mValue;
		mEscaped = false;
		if (mConfig.IJson && (isFloat || mNumberKind == .BigInteger) && !GetDouble(?))
			return .Err(Fail(.NumberOutOfRange, scope $"The number `{mRaw}` is beyond the range of a double, which I-JSON does not allow (RFC 7493 §2.2)", start, length));
		mPos = p;
		mState = .AfterValue;
		return .Ok(.Number);
	}

	/// Past the digits from `p` (reading more of a stream as needed).
	[Inline]
	int SkipDigits(int p)
	{
		var p;
		while (true)
		{
			while (p < mEnd && JsonChar.IsDigit(mData[p]))
				p++;
			if (p < mEnd || !Grow(p, 1))
				return p;
		}
	}

	/// "Expected X, found Y" for a malformed number, at `p`.
	JsonFailure NumberError(StringView expected, int p)
	{
		let message = scope String();
		message.Append(expected);
		message.Append(", found ");
		if (!Avail(p))
		{
			message.Append("the end of the input");
			return Fail(.InvalidNumber, message, p, 0);
		}
		if (IsInvalidUtf8At(p))
			return InvalidUtf8(p);
		Hex.AppendCharDescription(message, mData, p, mEnd, let length);
		return Fail(.InvalidNumber, message, p, length);
	}

	// Strings

	/// A string value or a member name (`isName`), from its opening quote at mPos.
	Result<JsonToken, JsonFailure> ReadString(bool isName)
	{
		int start = mPos;
		Retain(start);
		mStringStart = start;
		mStringIsName = isName;
		int p = Try!(ScanStringText(start, start + 1));
		char8 c = mData[p];
		if (c == '"')
		{
			mValue = View(start + 1, p - start - 1);
			mRaw = mValue;
			mEscaped = false;
		}
		else if (c == '\\' || (uint8)c >= 0x80)
		{
			// Escapes, or (InvalidUtf8.Replace) an ill-formed sequence: decoded
			mValue = Try!(DecodeEscaped(start, ref p));
			mRaw = View(start + 1, p - start - 1);
			mEscaped = true;
		}
		else
			return .Err(ControlCharacter(p));
		if (mConfig.MaxStringBytes > 0 && mValue.Length > mConfig.MaxStringBytes)
			return .Err(Fail(.ResourceLimitExceeded, scope $"The string ({mValue.Length} bytes) exceeds MaxStringBytes ({mConfig.MaxStringBytes})", start, p + 1 - start));
		if (mConfig.IJson)
		{
			int at = Utf8.FindNoncharacter(mValue);
			if (at >= 0)
			{
				// Located at the character when it is written raw, else at the string
				int offset = mEscaped ? start : start + 1 + at;
				int length = mEscaped ? p + 1 - start : (((uint8)mValue[at] == 0xEF) ? 3 : 4);
				uint32 cp = (uint32)Utf8.Decode(mValue.Ptr, at, ?);
				return .Err(Fail(.Noncharacter, scope $"The noncharacter U+{cp:X4} is not allowed in I-JSON (RFC 7493 §2.1)", offset, length));
			}
		}
		mToken = isName ? .PropertyName : .String;
		mTokenStart = start;
		mTokenEnd = p + 1;
		mPos = p + 1;
		mState = isName ? .Colon : .AfterValue;
		mStringStart = -1;
		return .Ok(mToken);
	}

	/// The first byte from `p` in the window that ends a string's plain ASCII run (`"`, `\`, a control
	/// character or a non-ASCII byte), or mEnd: 8 bytes at a time, then byte by byte at the window's end.
	[Inline]
	int ScanStringRun(int p)
	{
		var p;
		while (p + 16 <= mEnd)
		{
			int stop = JsonChar.FirstStringStop16(mData + p);
			if (stop < 16)
				return p + stop;
			p += 16;
		}
		while (p + 8 <= mEnd)
		{
			uint64 word = Swar.Load64(mData + p);
			uint64 stops = JsonChar.StringStops(word) | (word & Swar.High);
			if (stops != 0)
				return p + Swar.FirstByte(stops);
			p += 8;
		}
		while (p < mEnd)
		{
			char8 c = mData[p];
			if (c == '"' || c == '\\' || (uint8)c < 0x20 || (uint8)c >= 0x80)
				return p;
			p++;
		}
		return p;
	}

	/// From `p` inside the string that starts at `start`, past plain text and well-formed UTF-8 to the
	/// next `"`, `\` or control character, which is then in the window. UTF-8 is checked here, the one
	/// place non-ASCII text can be (the input is not validated before the reader). With
	/// InvalidUtf8.Replace an ill-formed sequence is a stop too, for the decoder to replace.
	[Inline]
	Result<int, JsonFailure> ScanStringText(int start, int p)
	{
		var p;
		while (true)
		{
			p = ScanStringRun(p);
			if (p < mEnd)
			{
				if ((uint8)mData[p] < 0x80)
					return p;
				// Non-ASCII: as many well-formed sequences as follow
				repeat
				{
					int length = Utf8At(p);
					if (length == 0)
					{
						if (mConfig.InvalidUtf8 == .Replace)
							return p;
						return .Err(InvalidUtf8(p));
					}
					p += length;
				}
				while (p < mEnd && (uint8)mData[p] >= 0x80);
				continue;
			}
			if (!Grow(p, 1))
				return .Err(UnterminatedString(start, p));
		}
	}

	/// The length of the well-formed UTF-8 sequence at `p` (a byte ≥ 0x80 in the window), or 0.
	[Inline]
	int Utf8At(int p)
	{
		if (p + 4 > mEnd)
			Grow(p, 4);
		return Utf8.ValidSequenceLength(mData, p, mEnd);
	}

	/// Whether the byte at `p` (in the window) starts an ill-formed UTF-8 sequence.
	[Inline]
	bool IsInvalidUtf8At(int p)
	{
		return (uint8)mData[p] >= 0x80 && Utf8At(p) == 0;
	}

	/// The error for the ill-formed UTF-8 sequence at `p`.
	JsonFailure InvalidUtf8(int p)
	{
		if (p + 4 > mEnd)
			Grow(p, 4);
		let message = scope String();
		Utf8.FindInvalid<JsonText>(mData, p, Math.Min(p + 4, mEnd), message, ?, let length);
		return Fail(.InvalidUtf8, message, p, length);
	}

	/// Decodes a string with escapes (or, with InvalidUtf8.Replace, ill-formed UTF-8) into mDecodeBuffer,
	/// from its opening quote at `start`; `p` is at its first backslash or ill-formed byte and ends at
	/// its closing quote. Writes go through a raw pointer: a run of plain text with room for it and 16
	/// bytes more made first, or an escape's at most 4 bytes, which that slack covers.
	/// @return The decoded text (valid until the next string).
	Result<StringView, JsonFailure> DecodeEscaped(int start, ref int p)
	{
		let buffer = mDecodeBuffer;
		char8* dest = buffer.Ptr;
		char8* limit = buffer.Limit;
		int count = p - start - 1;
		if (dest + count + 16 > limit)
			buffer.Grow(ref dest, ref limit, count + 16);
		JsonDecodeBuffer.CopyRun(dest, mData + start + 1, count, start + 17 <= mEnd);
		dest += count;
		while (true)
		{
			char8 c = mData[p];
			if (c == '"')
				return StringView(buffer.Ptr, dest - buffer.Ptr);
			if ((uint8)c < 0x20)
				return .Err(ControlCharacter(p));
			if ((uint8)c >= 0x80)
			{
				// InvalidUtf8.Replace: the scan stopped at an ill-formed sequence
				if (p + 4 > mEnd)
					Grow(p, 4);
				*(dest++) = (char8)0xEF;
				*(dest++) = (char8)0xBF;
				*(dest++) = (char8)0xBD;
				p += Utf8.MaximalSubpartLength(mData, p, mEnd);
			}
			else
			{
				// A backslash
				if (!Avail(p + 1))
					return .Err(UnterminatedString(start, p + 1));
				char8 e = mData[p + 1];
				switch (e)
				{
				case '"': *(dest++) = '"'; p += 2;
				case '\\': *(dest++) = '\\'; p += 2;
				case '/': *(dest++) = '/'; p += 2;
				case 'b': *(dest++) = '\b'; p += 2;
				case 'f': *(dest++) = '\f'; p += 2;
				case 'n': *(dest++) = '\n'; p += 2;
				case 'r': *(dest++) = '\r'; p += 2;
				case 't': *(dest++) = '\t'; p += 2;
				case 'u':
					// The common case inline: four hex digits in the window naming no surrogate
					uint32 cp = (p + 6 <= mEnd) ? Hex.Digits4(mData + p + 2) : 0x10000;
					if (cp < 0xD800 || (cp > 0xDFFF && cp <= 0xFFFF))
					{
						dest += Utf8.Encode(dest, cp);
						p += 6;
					}
					else
						Try!(DecodeUnicodeEscape(ref p, ref dest));
				default:
					return .Err(InvalidEscape(p));
				}
			}
			// The text up to the next stop
			int q = Try!(ScanStringText(start, p));
			count = q - p;
			if (dest + count + 16 > limit)
				buffer.Grow(ref dest, ref limit, count + 16);
			JsonDecodeBuffer.CopyRun(dest, mData + p, count, p + 16 <= mEnd);
			dest += count;
			p = q;
		}
	}

	/// The error for the backslash at `p`, which starts no escape.
	JsonFailure InvalidEscape(int p)
	{
		if (IsInvalidUtf8At(p + 1))
			return InvalidUtf8(p + 1);
		let message = scope String();
		message.Append("Invalid escape: `\\` followed by ");
		Hex.AppendCharDescription(message, mData, p + 1, mEnd, let length);
		message.Append(" (JSON's escapes are `\\\"` `\\\\` `\\/` `\\b` `\\f` `\\n` `\\r` `\\t` and `\\uXXXX`)");
		return Fail(.InvalidEscape, message, p, 1 + length);
	}

	/// A `\uXXXX` escape at `p` (and the low surrogate's escape after a high one): writes the code
	/// point's UTF-8 (at most 4 bytes) at `dest` and moves `p` and `dest` past it.
	Result<void, JsonFailure> DecodeUnicodeEscape(ref int p, ref char8* dest)
	{
		uint32 cp = Try!(ReadHex4(p));
		if (cp >= 0xD800 && cp <= 0xDFFF && mConfig.InvalidSurrogates != .Error)
		{
			// Replace or Wtf8: a pair as usual, an unpaired escape replaced or kept as WTF-8 bytes
			int low = cp < 0xDC00 ? LowSurrogateAt(p + 6) : -1;
			if (low >= 0)
			{
				cp = 0x10000 + ((cp - 0xD800) << 10) + ((uint32)low - 0xDC00);
				p += 12;
			}
			else
			{
				p += 6;
				if (mConfig.InvalidSurrogates == .Replace)
					dest += Utf8.Encode(dest, 0xFFFD);
				else
				{
					*(dest++) = (char8)(0xE0 | (cp >> 12));
					*(dest++) = (char8)(0x80 | ((cp >> 6) & 0x3F));
					*(dest++) = (char8)(0x80 | (cp & 0x3F));
				}
				return .Ok;
			}
		}
		else if (cp >= 0xD800 && cp <= 0xDFFF)
		{
			if (cp >= 0xDC00)
				return .Err(Fail(.InvalidSurrogate, scope $"The escape `{View(p, 6)}` is a low surrogate without a high surrogate before it (a lone surrogate is not Unicode text)", p, 6));
			// A high surrogate: an escaped low one must follow
			if (!AvailN(p + 6, 2) || mData[p + 6] != '\\' || mData[p + 7] != 'u')
				return .Err(Fail(.InvalidSurrogate, scope $"The escape `{View(p, 6)}` is a high surrogate without an escaped low surrogate (`\\uDC00`-`\\uDFFF`) after it (a lone surrogate is not Unicode text)", p, 6));
			uint32 low = Try!(ReadHex4(p + 6));
			if (low < 0xDC00 || low > 0xDFFF)
				return .Err(Fail(.InvalidSurrogate, scope $"The escape `{View(p, 6)}` is a high surrogate followed by `{View(p + 6, 6)}`, which is not a low surrogate (`\\uDC00`-`\\uDFFF`)", p, 12));
			cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
			p += 12;
		}
		else
			p += 6;
		dest += Utf8.Encode(dest, cp);
		return .Ok;
	}

	/// The low surrogate escaped at `p` (`\uDC00`-`\uDFFF`), or -1 for anything else (reported where it
	/// is read on its own).
	int LowSurrogateAt(int p)
	{
		if (!AvailN(p, 6) || mData[p] != '\\' || mData[p + 1] != 'u')
			return -1;
		int value = 0;
		for (int i = 2; i < 6; i++)
		{
			uint8 digit = Hex.DigitValue(mData[p + i]);
			if (digit == 255)
				return -1;
			value = (value << 4) | digit;
		}
		return value >= 0xDC00 && value <= 0xDFFF ? value : -1;
	}

	/// The value of the four hex digits of the `\u` escape at `p`.
	Result<uint32, JsonFailure> ReadHex4(int p)
	{
		uint32 value = 0;
		for (int i < 4)
		{
			int q = p + 2 + i;
			if (!Avail(q))
				return .Err(Fail(.InvalidEscape, "The escape `\\u` needs four hex digits, found the end of the input", p, q - p));
			uint8 digit = Hex.DigitValue(mData[q]);
			if (digit == 255)
			{
				if (IsInvalidUtf8At(q))
					return .Err(InvalidUtf8(q));
				let message = scope String();
				message.Append("The escape `\\u` needs four hex digits, found ");
				Hex.AppendCharDescription(message, mData, q, mEnd, let length);
				return .Err(Fail(.InvalidEscape, message, p, q + length - p));
			}
			value = (value << 4) | digit;
		}
		return value;
	}

	JsonFailure UnterminatedString(int start, int p)
	{
		return Fail(.UnterminatedString, "The input ends inside a string: expected its closing `\"`", p, 0);
	}

	JsonFailure ControlCharacter(int p)
	{
		let message = scope String();
		message.Append("The control character ");
		Hex.AppendCharDescription(message, mData, p, mEnd, ?);
		message.Append(" must be escaped in a string");
		return Fail(.ControlCharacterInString, message, p);
	}

	// Whitespace

	/// Past whitespace (and comments, with JsonReadConfig.Comments). Most gaps in minified JSON are
	/// empty: two compares decide that inline.
	[Inline]
	void SkipSpace()
	{
		// (JSON5's other spaces, VT, FF and non-ASCII ones, are taken where JSON's error for them would be
		// reported: SkipJson5Space. The token path pays nothing for them.)
		if (mPos < mEnd && (uint8)mData[mPos] > (uint8)' ' && mData[mPos] != '/')
			return;
		SkipSpaceRun();
	}

	/// Past the one space that follows `:` in pretty-printed JSON (half of its whitespace runs) when a
	/// token follows it: inline here, where it is common, and not in every SkipSpace, so that minified
	/// input's paths do not grow. (After `,` too measured worse: canada's hot code moved.)
	[Inline]
	void SkipOneSpace()
	{
		if (mPos + 1 < mEnd && mData[mPos] == ' ' && (uint8)mData[mPos + 1] > (uint8)' ' && mData[mPos + 1] != '/')
			mPos++;
	}

	/// Past a run of whitespace: a byte or two (a space after `:`, a newline), then indentation 8 bytes
	/// at a time; and comments. A malformed comment is left where it starts, for the error that follows.
	void SkipSpaceRun()
	{
		while (true)
		{
			while (mPos < mEnd)
			{
				if (!JsonChar.IsSpace(mData[mPos]))
				{
					if (mData[mPos] == '/' && mConfig.Comments && SkipComment())
						continue;
					return;
				}
				mPos++;
				if (mPos >= mEnd || !JsonChar.IsSpace(mData[mPos]))
					continue;
				mPos++;
				if (SkipIndentation())
					return;
			}
			if (!Grow(mPos, 1))
				return;
		}
	}

	/// The rest of a run of whitespace from its third byte (indentation), 8 bytes at a time, in locals
	/// (stores through `this` would be reloaded). Out of line, so that the one- and two-byte runs
	/// SkipSpaceRun ends itself pay nothing for the loop's setup.
	/// @return Whether the run ended at a byte that is not `/` (else, at a comment or the window's end,
	/// SkipSpaceRun goes on).
	[NoInline]
	bool SkipIndentation()
	{
		char8* data = mData;
		int end = mEnd;
		int pos = mPos;
		while (pos + 8 <= end)
		{
			uint64 word = Swar.Load64(data + pos);
			// The byte that ends a run is almost always above 0x20 and the bytes before it spaces: the
			// exact test (tabs, line breaks, control characters) only when a byte below 0x20 comes first
			uint64 above = Swar.BytesAboveSpace(word);
			uint64 below = Swar.BytesBelowSpace(word);
			uint64 nonSpace;
			if (below == 0 || (above != 0 && (below & ((above & (~above + 1)) - 1)) == 0))
				nonSpace = above;
			else
				nonSpace = Swar.NonSpaceBytes(word);
			if (nonSpace != 0)
			{
				pos += Swar.FirstByte(nonSpace);
				mPos = pos;
				return data[pos] != '/';
			}
			pos += 8;
		}
		mPos = pos;
		return false;
	}

	// Comments (JsonReadConfig.Comments)

	/// Past the comment at mPos (a `/`): `//` to the end of its line (before the CR or LF), `/* */`
	/// through its `*/` (not nested), UTF-8 checked inside. @return False, leaving mPos, when it is not a
	/// well-formed comment: CommentError reports it. (Out of line: the whitespace loop stays small.)
	[NoInline]
	bool SkipComment()
	{
		int p = CommentEnd(mPos);
		if (p < 0)
			return false;
		mPos = p;
		return true;
	}

	/// The end of the comment at `start`, or -1 when it is not a complete, well-formed one.
	int CommentEnd(int start)
	{
		if (!Avail(start + 1))
			return -1;
		char8 kind = mData[start + 1];
		if (kind != '/' && kind != '*')
			return -1;
		int p = start + 2;
		while (true)
		{
			if (!Avail(p))
				return kind == '/' ? p : -1;
			char8 c = mData[p];
			if ((uint8)c >= 0x80)
			{
				int length = Utf8At(p);
				if (length == 0)
					return -1;
				// JSON5's line terminators include U+2028 and U+2029
				if (mJson5 && kind == '/' && length == 3 && (uint8)c == 0xE2 && (uint8)mData[p + 1] == 0x80 && ((uint8)mData[p + 2] & 0xFE) == 0xA8)
					return p;
				p += length;
				continue;
			}
			if (kind == '/')
			{
				if (c == '\n' || c == '\r')
					return p;
			}
			else if (c == '*' && Avail(p + 1) && mData[p + 1] == '/')
				return p + 2;
			p++;
		}
	}

	/// The error for the `/` at `p` that starts no well-formed comment.
	JsonFailure CommentError(int p)
	{
		if (!mConfig.Comments)
			return Fail(.UnexpectedChar, "Unexpected `/`: comments are not JSON (JsonReadConfig.Comments allows them)", p);
		if (Avail(p + 1) && (mData[p + 1] == '/' || mData[p + 1] == '*'))
		{
			// Inside it: an ill-formed UTF-8 sequence, or the end of the input before `*/`
			int q = p + 2;
			while (Avail(q))
			{
				if ((uint8)mData[q] >= 0x80)
				{
					if (IsInvalidUtf8At(q))
						return InvalidUtf8(q);
					q += Utf8At(q);
					continue;
				}
				q++;
			}
			return Fail(.UnterminatedComment, "The input ends inside a comment: expected `*/`", p, 2);
		}
		return Fail(.UnexpectedChar, "Unexpected `/`: a comment starts with `//` or `/*`", p);
	}

	// The window

	/// Keeps the window from `pos` on (the token being read; int.MaxValue: nothing). Memory input keeps
	/// everything anyway, so this folds away there.
	[Inline]
	void Retain(int pos)
	{
		if (!mCursor.IsWhole)
			mRetain = pos;
	}

	/// Whether the byte at `pos` is available, reading more of a stream if needed.
	[Inline]
	bool Avail(int pos)
	{
		return pos < mEnd || Grow(pos, 1);
	}

	/// Whether `count` bytes from `pos` are available, reading more of a stream if needed.
	[Inline]
	bool AvailN(int pos, int count)
	{
		return pos + count <= mEnd || Grow(pos, count);
	}

	/// Asks the cursor for more input, keeping the current token, and moves the token's views if the
	/// window moved. @return Whether `count` bytes from `pos` are now available. Inlined so that for
	/// in-memory input (Fill is an inlined `false`) it folds to a compare.
	[Inline]
	bool Grow(int pos, int count)
	{
		char8* oldData = mData;
		int oldBase = mBase;
		int oldEnd = mEnd;
		bool grew = mCursor.Fill(ref mData, ref mBase, ref mEnd, Math.Min(Math.Min(Math.Min(mRetain, mHold), mPos), pos), pos, count);
		if (mData != oldData)
			RebaseViews(oldData, oldBase, oldEnd);
		if (!grew)
		{
			if (mCursor.HasInputError)
				mInputFailed = true;
			return false;
		}
		return pos + count <= mEnd;
	}

	void RebaseViews(char8* oldData, int oldBase, int oldEnd)
	{
		char8* low = oldData + oldBase;
		char8* high = oldData + oldEnd;
		Rebase(ref mValue, low, high, oldData);
		Rebase(ref mRaw, low, high, oldData);
	}

	/// Moves a view of the old window to the same offsets in the new one.
	void Rebase(ref StringView view, char8* low, char8* high, char8* oldData)
	{
		if (view.Ptr >= low && view.Ptr < high)
			view = .(mData + (view.Ptr - oldData), view.Length);
	}

	[Inline]
	StringView View(int start, int length)
	{
		return StringView(mData + start, length);
	}

	// Errors

	/// Records the error (Next reports it) and returns the token internal methods fail with. After the
	/// input itself failed (a stream's I/O, encoding or size error), that error is reported instead: the
	/// reader's own came from running into the end of what could be read.
	JsonFailure Fail(JsonErrorKind kind, StringView message, int offset, int length = 1)
	{
		if (mInputFailed && mCursor.TryGetInputError(let inputError))
			mError = inputError;
		else
		{
			int line = 0;
			int column = 0;
			if (mCursor.Locate(offset, var l, var c))
			{
				line = l;
				column = c;
			}
			mError = JsonParseError(kind, message, line, column, offset, length);
		}
		if (!mConfig.SourceName.IsEmpty)
			mError.SetSource(mConfig.SourceName);
		return .();
	}

	/// The input ended where more was needed, at mPos.
	JsonFailure EndOfInput(StringView message)
	{
		return Fail(.UnexpectedEndOfInput, message, mPos, 0);
	}

	/// "Expected X, found Y" at mPos (which must be available).
	JsonFailure Unexpected(JsonErrorKind kind, StringView expected)
	{
		if (IsInvalidUtf8At(mPos))
			return InvalidUtf8(mPos);
		if (mData[mPos] == '/')
			return CommentError(mPos);
		let message = scope String();
		message.Append("Expected ");
		message.Append(expected);
		message.Append(", found ");
		Hex.AppendCharDescription(message, mData, mPos, mEnd, let length);
		return Fail(kind, message, mPos, length);
	}

	// Collect-errors

	/// After an error: stop, or with CollectErrors resynchronize so the next call goes on. Recovery
	/// makes no error of its own (the pending one's message is in the per-thread buffer) and always
	/// moves on: an error at or before the last one's offset resynchronizes a byte further.
	void AfterError()
	{
		bool fatal = mInputFailed || mState == .Start || mError.mKind == .ResourceLimitExceeded ||
			mError.mKind == .IoError || mError.mKind == .UnsupportedEncoding;
		if (!mConfig.CollectErrors || fatal || (mConfig.MaxErrors > 0 && ++mErrorCount >= mConfig.MaxErrors))
		{
			mState = .Failed;
			return;
		}
		Recover();
	}

	void Recover()
	{
		int anchor = (int)mError.mOffset;
		if (anchor <= mLastErrorOffset)
			anchor = mLastErrorOffset + 1;
		mLastErrorOffset = anchor;
		mPos = Math.Max(anchor, mBase);
		if (mStringStart >= 0)
		{
			// Inside a string: past its closing quote (or to the line's end, for a string not closed
			// there); a broken name takes its member with it
			bool isName = mStringIsName;
			mStringStart = -1;
			mPos = SkipStringBody(mPos);
			if (isName)
				SkipMemberRest();
			else
				mState = .AfterValue;
			CloseIfAtEnd();
			return;
		}
		if (!Avail(mPos) || mError.mKind == .UnterminatedComment)
		{
			// (A comment not closed runs to the end of the input)
			mClosingAtEnd = true;
			mState = .Closing;
			return;
		}
		char8 c = mData[mPos];
		switch (mState)
		{
		case .Value, .ArrayStart:
			if (mDepth == 0)
			{
				// Something that is not a value where the document's should be: skipped
				mPos = c == ',' || c == ']' || c == '}' || c == ':' ? mPos + 1 : SkipTokenRun(mPos);
				SkipSpace();
				if (!Avail(mPos))
					mState = .End;
			}
			else if (c == ',' || c == ']' || c == '}')
			{
				// A missing value: the comma or bracket is read as what follows a value
				mState = .AfterValue;
			}
			else if (c == ':')
				mPos++;
			else
			{
				mPos = SkipTokenRun(mPos);
				mState = .AfterValue;
			}
		case .ObjectStart, .Name:
			if (c == '}')
				mState = .AfterValue;
			else if (c == ']')
				CloseTo(c);
			else if (c == ',')
				mPos++;
			else
				SkipMemberRest();
		case .Colon:
			if (c == ',' || c == '}')
			{
				// A name without a value: the member is dropped (JsonDocument does)
				mState = .AfterValue;
			}
			else if (c == ']')
				CloseTo(c);
			else if (CanStartValue(c))
				mState = .Value;
			else
				mPos = SkipTokenRun(mPos);
		case .AfterValue:
			if (mDepth == 0)
			{
				// Content after the document's value: the read ends
				mClosingAtEnd = true;
				mState = .Closing;
			}
			else if (c == ']' || c == '}')
				CloseTo(c);
			else if (InObject ? c == '"' : CanStartValue(c))
			{
				// A missing comma
				mState = InObject ? .Name : .Value;
			}
			else
				mPos = c == ',' || c == ':' || c == '[' || c == '{' ? mPos + 1 : SkipTokenRun(mPos);
		default:
			mState = .Failed;
		}
		CloseIfAtEnd();
	}

	/// At the end of the input after recovery: close what is open.
	void CloseIfAtEnd()
	{
		if (mState == .Failed || mState == .End)
			return;
		SkipSpace();
		if (!Avail(mPos))
		{
			mClosingAtEnd = true;
			mState = .Closing;
		}
	}

	/// A closing bracket that is not the innermost container's: the containers inside the one it closes
	/// end there (their End tokens first), or it is skipped when no open container is of its kind.
	void CloseTo(char8 closer)
	{
		bool wantObject = closer == '}';
		for (int d = mDepth - 1; d >= 0; d--)
		{
			if (((mBits[d >> 6] >> (d & 63)) & 1) != 0 == wantObject)
			{
				mPendingCloses = mDepth - 1 - d;
				mState = mPendingCloses > 0 ? .Closing : .AfterValue;
				return;
			}
		}
		mPos++;
		mState = .AfterValue;
	}

	/// State.Closing: the End token of a container recovery closes (an empty token where the reader is),
	/// or at the end of the input, when everything is closed, the end of the document.
	Result<JsonToken, JsonFailure> ReadClosing()
	{
		if (mPendingCloses == 0 && !(mClosingAtEnd && mDepth > 0))
		{
			if (mClosingAtEnd)
			{
				mState = .End;
				mToken = .EndOfDocument;
				mTokenStart = mPos;
				mTokenEnd = mPos;
				return .Ok(.EndOfDocument);
			}
			mState = .AfterValue;
			return ReadAfterValue();
		}
		if (mPendingCloses > 0)
			mPendingCloses--;
		bool isObject = InObject;
		mDepth--;
		mToken = isObject ? .EndObject : .EndArray;
		mTokenStart = mPos;
		mTokenEnd = mPos;
		return .Ok(mToken);
	}

	/// Whether `c` can start a value.
	static bool CanStartValue(char8 c)
	{
		return c == '"' || c == '-' || JsonChar.IsDigit(c) || c == '[' || c == '{' || c == 't' || c == 'f' || c == 'n';
	}

	/// Past a run of anything but whitespace, `"` and structural characters (a broken literal or number,
	/// garbage), at least one byte.
	int SkipTokenRun(int p)
	{
		int q = p;
		while (Avail(q))
		{
			char8 c = mData[q];
			if (JsonChar.IsSpace(c) || c == ',' || c == ':' || c == '[' || c == ']' || c == '{' || c == '}' || c == '"')
				break;
			q++;
		}
		return q > p ? q : Math.Min(p + 1, Avail(p) ? p + 1 : p);
	}

	/// From inside a string, past its closing quote; a raw line break or the end of the input ends it
	/// there (a string not closed on its line).
	int SkipStringBody(int p)
	{
		var p;
		while (Avail(p))
		{
			char8 c = mData[p];
			if (c == '\\')
				p += 2;
			else if (c == '"')
				return p + 1;
			else if (c == '\n' || c == '\r')
				return p;
			else
				p++;
		}
		return Math.Min(p, mEnd);
	}

	/// Past one value of any kind, brackets balanced and strings skipped whole.
	int SkipBalanced(int p)
	{
		if (!Avail(p))
			return p;
		char8 c = mData[p];
		if (c == '"')
			return SkipStringBody(p + 1);
		if (c != '[' && c != '{')
			return SkipTokenRun(p);
		int depth = 0;
		var p;
		while (Avail(p))
		{
			c = mData[p];
			if (c == '"')
			{
				p = SkipStringBody(p + 1);
				continue;
			}
			if (c == '[' || c == '{')
				depth++;
			else if (c == ']' || c == '}')
			{
				depth--;
				if (depth == 0)
					return p + 1;
			}
			p++;
		}
		return p;
	}

	/// The rest of a broken member (from its name or what stands for it): the name, and with a `:`
	/// after it the value too; then what follows a value.
	void SkipMemberRest()
	{
		if (Avail(mPos) && mData[mPos] != ':')
			mPos = SkipBalanced(mPos);
		SkipSpace();
		if (Avail(mPos) && mData[mPos] == ':')
		{
			mPos++;
			SkipSpace();
			if (Avail(mPos) && mData[mPos] != ',' && mData[mPos] != '}' && mData[mPos] != ']')
				mPos = SkipBalanced(mPos);
		}
		mState = .AfterValue;
	}

	// Values of the current token

	/// The current number token's double (correctly rounded); false if it overflows (the value is ±∞).
	/// A NonFinite token gives its NaN or infinity, and true: it names that value.
	public bool GetDouble(out double value)
	{
		switch (mNumberKind)
		{
		case .Integer:
			// Exact below 2^53 (`-0` is −0.0); beyond, the conversion rounds as the text would
			if (mInteger != 0 && mInteger > -((int64)1 << 53) && mInteger < ((int64)1 << 53))
			{
				value = (double)mInteger;
				return true;
			}
		case .Float:
			if (mFloatExact && JsonNumber.TryClinger(mFloatMantissa, mFloatExponent, mValue[0] == '-', out value))
				return true;
		case .NonFinite:
			value = JsonNumber.NonFiniteValue(mRaw);
			return true;
		default:
		}
		// The number's JSON text (a JSON5 number's, normalized: `.5` is `0.5`)
		return JsonNumber.ParseDoubleSlow(mValue, out value);
	}

	/// Locates `offset` for an error made outside the reader (a value conversion).
	public JsonParseError MakeError(JsonErrorKind kind, StringView message, int offset, int length)
	{
		int line = 0;
		int column = 0;
		if (mCursor.Locate(offset, var l, var c))
		{
			line = l;
			column = c;
		}
		var error = JsonParseError(kind, message, line, column, offset, length);
		if (!mConfig.SourceName.IsEmpty)
			error.SetSource(mConfig.SourceName);
		return error;
	}
}
