using System;
using System.Collections;
using internal JsonBeef;

namespace JsonBeef;

/// @brief Where a value or a member name came from in the source (JsonMetadataMode.Positions).
public struct JsonSourceRange
{
	/// @brief Name of the source (JsonReadConfig.SourceName, or the path for ReadFile); empty if unnamed.
	/// Borrowed from the document: valid until it is cleared, read again or deleted.
	public StringView mSource;
	/// @brief 1-based line of the start.
	public int mLine;
	/// @brief 1-based column of the start, in code points.
	public int mColumn;
	/// @brief Byte offset of the start.
	public int mOffset;
	/// @brief Length in bytes: a string or name from quote to quote, a number or literal its token, an
	/// array or object from its bracket through the closing one.
	public int mLength;

	public this(int line, int column, int offset, int length, StringView source = default)
	{
		mSource = source;
		mLine = line;
		mColumn = column;
		mOffset = offset;
		mLength = length;
	}

	/// @brief Formats the position as `source:line:column`, or `line:column` without a source name.
	/// @param strBuffer The string to append to.
	public override void ToString(String strBuffer)
	{
		if (!mSource.IsEmpty)
		{
			strBuffer.Append(mSource);
			strBuffer.Append(':');
		}
		strBuffer.AppendF("{}:{}", mLine, mColumn);
	}
}

/// A value's source range and its member name's (Positions), by node ID. Line 0: not located yet (memory
/// input locates on request, from the kept source; a stream locates while reading).
internal struct JsonRangeRecord
{
	public int64 mOffset;
	public int64 mNameOffset;
	public int32 mLength;
	/// -1: no name (an array element, the root).
	public int32 mNameLength;
	public int32 mLine;
	public int32 mColumn;
	public int32 mNameLine;
	public int32 mNameColumn;
}

extension JsonDocument
{
	/// Positions: one range per node ID (empty in other modes).
	internal List<JsonRangeRecord> mRanges = new .() ~ delete _;
	/// The offsets where lines start in the source copy, built on the first request.
	List<int> mLineStarts = new .() ~ delete _;

	/// The line and column of `offset` in the source copy (lines LF, CR or CRLF; columns in code points;
	/// a leading BOM takes no column), from an index of line starts built once.
	internal void LocateInSource(int offset, out int line, out int column)
	{
		if (mLineStarts.IsEmpty)
		{
			mLineStarts.Add(JsonChar.StartsWithBom(mSource, mSourceLength) ? 3 : 0);
			int i = 0;
			while (i < mSourceLength)
			{
				char8 c = mSource[i];
				if (c == '\n' || c == '\r')
				{
					i += (c == '\r' && i + 1 < mSourceLength && mSource[i + 1] == '\n') ? 2 : 1;
					mLineStarts.Add(i);
					continue;
				}
				i++;
			}
		}
		// The last line start at or before the offset
		int low = 0;
		int high = mLineStarts.Count - 1;
		while (low < high)
		{
			int mid = (low + high + 1) / 2;
			if (mLineStarts[mid] <= offset)
				low = mid;
			else
				high = mid - 1;
		}
		line = low + 1;
		column = JsonChar.CountCodePoints(mSource, mLineStarts[low], Math.Max(offset, mLineStarts[low])) + 1;
	}

	/// The source range of node `id`'s value (`name` false) or member name.
	internal bool TryGetRange(uint32 id, bool name, out JsonSourceRange range)
	{
		range = default;
		if (id >= (uint32)mRanges.Count)
			return false;
		ref JsonRangeRecord record = ref mRanges[id];
		int64 offset = name ? record.mNameOffset : record.mOffset;
		int32 length = name ? record.mNameLength : record.mLength;
		if (length < 0)
			return false;
		int line = name ? record.mNameLine : record.mLine;
		int column = name ? record.mNameColumn : record.mColumn;
		if (line == 0)
		{
			if (mSource == null)
				return false;
			LocateInSource((int)offset, out line, out column);
		}
		range = .(line, column, (int)offset, length, mSourceName);
		return true;
	}
}

extension JsonNode
{
	/// @brief Where the value is in the source: available when the document was read with
	/// JsonMetadataMode.Positions (not for values added by editing, nor for an invalid handle).
	/// @param range Receives the range (its source name is borrowed from the document).
	/// @return Whether there is one.
	public bool TryGetSourceRange(out JsonSourceRange range)
	{
		range = default;
		return IsValid && mDocument.TryGetRange(mId, false, out range);
	}

	/// @brief Where the member's name is in the source, from its opening quote through its closing one
	/// (JsonMetadataMode.Positions; false for array elements and the root).
	/// @param range Receives the range.
	/// @return Whether there is one.
	public bool TryGetNameRange(out JsonSourceRange range)
	{
		range = default;
		return IsValid && mDocument.TryGetRange(mId, true, out range);
	}
}
